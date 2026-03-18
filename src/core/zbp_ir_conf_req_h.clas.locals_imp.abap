CLASS lhc_Req DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    " CẬP NHẬT HẰNG SỐ: Khớp với dữ liệu thực tế 'S', 'A', 'R' trong DB
    CONSTANTS:
      gc_st_draft     TYPE zde_requ_status VALUE 'DRAFT',
      gc_st_submitted TYPE zde_requ_status VALUE 'SUBMITTED',
      gc_st_approved  TYPE zde_requ_status VALUE 'APPROVED',
      gc_st_rejected  TYPE zde_requ_status VALUE 'REJECTED',
      gc_st_active    TYPE zde_requ_status VALUE 'ACTIVE'.

    CONSTANTS:
      gc_role_manager TYPE c LENGTH 20 VALUE 'MANAGER',
      gc_role_itadmin TYPE c LENGTH 20 VALUE 'IT ADMIN',
      gc_role_keyuser TYPE c LENGTH 20 VALUE 'KEY USER'.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Req RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features FOR Req RESULT result.

    METHODS approve FOR MODIFY IMPORTING keys FOR ACTION Req~approve RESULT result.
    METHODS reject FOR MODIFY IMPORTING keys FOR ACTION Req~reject RESULT result.
    METHODS submit FOR MODIFY IMPORTING keys FOR ACTION Req~submit RESULT result.
    METHODS promote FOR MODIFY IMPORTING keys FOR ACTION Req~promote RESULT result.
    METHODS createRequest FOR MODIFY IMPORTING keys FOR ACTION Req~createRequest RESULT result.

    METHODS set_default_and_admin_fields FOR DETERMINE ON MODIFY IMPORTING keys FOR Req~set_default_and_admin_fields.
    METHODS validate_before_save FOR VALIDATE ON SAVE IMPORTING keys FOR Req~validate_before_save.

ENDCLASS.

CLASS lhc_Req IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_instance_features.
    " 1. Đọc dữ liệu hiện tại
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    " 2. Lấy Role người dùng (Đảm bảo Manager mới được duyệt)
    DATA lv_role TYPE c LENGTH 20.
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id  = @sy-uname AND is_active = @abap_true
      INTO @lv_role.

    LOOP AT lt_reqs INTO DATA(ls_req).
      " Kiểm soát nút Update/Submit
      DATA(lv_update) = COND #( WHEN ls_req-Status = gc_st_draft OR ls_req-Status IS INITIAL
                                 THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_submit) = COND #( WHEN ls_req-Status = gc_st_draft
                                 THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ).

      " LOGIC QUAN TRỌNG: Nút Approve/Reject sẽ sáng khi Status = 'S' và User là Manager
      DATA(lv_approve_reject) = COND #( WHEN ls_req-Status = gc_st_submitted AND lv_role = gc_role_manager
                                         THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ).

      " Nút Promote sáng khi đã Approved ('A')
      DATA(lv_promote) = COND #( WHEN ls_req-Status = gc_st_approved AND lv_role = gc_role_itadmin
                                 THEN if_abap_behv=>fc-o-enabled ELSE if_abap_behv=>fc-o-disabled ).

      APPEND VALUE #( %tky            = ls_req-%tky
                      %update         = lv_update
                      %action-submit  = lv_submit
                      %action-approve = lv_approve_reject
                      %action-reject  = lv_approve_reject
                      %action-promote = lv_promote
                    ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD approve.
    DATA: lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    " 1. Đọc dữ liệu Header và Items kèm theo
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(reqs)
      ENTITY Req BY \_Items ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(items).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      DATA(lv_has_error) = abap_false.

      " 2. Kiểm tra trạng thái
      IF <r>-Status <> 'S'.
        lv_has_error = abap_true.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-error
                         text = 'Yêu cầu không ở trạng thái chờ duyệt.' ) ) TO reported-req.
      ENDIF.

      " 3. Lọc và Kiểm tra Items
      DATA(lt_curr_items) = items.
      DELETE lt_curr_items WHERE ReqId <> <r>-ReqId.

      IF lt_curr_items IS INITIAL AND lv_has_error = abap_false.
        lv_has_error = abap_true.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                         severity = if_abap_behv_message=>severity-error
                         text = 'Yêu cầu trống, không thể duyệt.' ) ) TO reported-req.
      ENDIF.

      IF lv_has_error = abap_true. CONTINUE. ENDIF.

      " 4. Gọi Validator (Không truyền is_data để tránh lỗi kiểu dữ liệu)
      LOOP AT lt_curr_items INTO DATA(ls_item).
        DATA(lt_val_errors) = zcl_gsp26_rule_validator=>validate_request_item(
                                iv_conf_id       = ls_item-ConfId
                                iv_action        = ls_item-Action
                                iv_target_env_id = ls_item-TargetEnvId ).
        IF lt_val_errors IS NOT INITIAL.
          lv_has_error = abap_true.
          APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
          LOOP AT lt_val_errors INTO DATA(ls_err).
            APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                             severity = if_abap_behv_message=>severity-error
                             text = |Item { ls_item-ConfId }: { ls_err-message }| ) ) TO reported-req.
          ENDLOOP.
        ENDIF.
      ENDLOOP.

      IF lv_has_error = abap_true. CONTINUE. ENDIF.

      " 5. Ghi Log Audit
      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = VALUE #( lt_curr_items[ 1 ]-ConfId OPTIONAL )
            iv_req_id   = <r>-ReqId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'APPROVE'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = <r> ).
        CATCH cx_root.
      ENDTRY.

      " 6. Cập nhật trạng thái 'A'
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ApprovedBy ApprovedAt )
        WITH VALUE #( ( %tky = <r>-%tky Status = 'A' ApprovedBy = sy-uname ApprovedAt = lv_now ) ).
    ENDLOOP.

    " 7. Đọc lại để trả về %param (Giúp đổi màu ngay lập tức)
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_final).

    result = VALUE #( FOR ls_final IN lt_final ( %tky = ls_final-%tky %param = ls_final ) ).
  ENDMETHOD.

  " --- CÁC METHOD KHÁC (GIỮ NGUYÊN LOGIC CỦA BẠN VÀ CẬP NHẬT HẰNG SỐ) ---

  METHOD reject.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).

      " Tìm key entry tương ứng với header hiện tại
      DATA(lv_reason) = VALUE zde_requ_status( ).

      LOOP AT keys INTO DATA(ls_key_entry)
        WHERE %tky = <r>-%tky.
        lv_reason = ls_key_entry-%param-reason.
        EXIT.
      ENDLOOP.

      IF lv_reason IS INITIAL.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Vui lòng nhập lý do từ chối!'
          )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      IF <r>-Status <> gc_st_submitted.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Chỉ có thể từ chối yêu cầu ở trạng thái S'
          )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      " Audit + update như cũ
      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_req_id   = <r>-ReqId
            iv_conf_id  = <r>-ConfId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'REJECT'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = VALUE #( BASE <r> Status = gc_st_rejected Reason = lv_reason )
          ).
        CATCH cx_root.
      ENDTRY.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status Reason RejectedBy RejectedAt )
        WITH VALUE #( (
          %tky       = <r>-%tky
          Status     = gc_st_rejected
          Reason     = lv_reason
          RejectedBy = sy-uname
          RejectedAt = lv_now
        ) ).
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.

  METHOD submit.
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(reqs).
    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-Status <> gc_st_draft. CONTINUE. ENDIF.

      READ ENTITIES OF zir_conf_req_h IN LOCAL MODE ENTITY Req BY \_Items
      ALL FIELDS WITH VALUE #( ( %tky = <r>-%tky ) )
      RESULT DATA(items).
      IF items IS INITIAL.
        APPEND VALUE #(
        %tky = <r>-%tky %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
        text = 'Request must contain at least one item before submit' ) )
        TO reported-Req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE ENTITY Req
      UPDATE FIELDS ( Status )
      WITH VALUE #( ( %tky = <r>-%tky Status = gc_st_submitted ) ).
    ENDLOOP.
    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.

  METHOD set_default_and_admin_fields.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(lt_req).

    MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req UPDATE FIELDS ( Status EnvId CreatedBy CreatedAt ChangedBy ChangedAt )
      WITH VALUE #( FOR ls_req IN lt_req (
          %tky      = ls_req-%tky
          Status    = COND #( WHEN ls_req-Status IS INITIAL THEN gc_st_draft ELSE ls_req-Status )
          EnvId     = COND #( WHEN ls_req-EnvId  IS INITIAL THEN 'DEV'       ELSE ls_req-EnvId )
          CreatedBy = COND #( WHEN ls_req-CreatedBy IS INITIAL THEN sy-uname ELSE ls_req-CreatedBy )
          CreatedAt = COND #( WHEN ls_req-CreatedAt IS INITIAL THEN lv_now   ELSE ls_req-CreatedAt )
          ChangedBy = sy-uname
          ChangedAt = lv_now ) ).
  ENDMETHOD.

  METHOD validate_before_save.
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      " Chỉ check status — KHÔNG check Item ở đây
      IF <r>-Status = gc_st_approved OR <r>-Status = gc_st_rejected.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Completed request cannot be changed'
          )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
      ENDIF.
    ENDLOOP.

  ENDMETHOD.

  METHOD promote.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-Status <> gc_st_approved.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Promote chỉ được khi status là Approved'
          )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = <r>-ConfId
            iv_req_id   = <r>-ReqId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'PROMOTE'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = VALUE #( BASE <r> Status = gc_st_active     )
          ).
        CATCH cx_root.
      ENDTRY.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky      = <r>-%tky
          Status    = gc_st_active
          ChangedBy = sy-uname
          ChangedAt = lv_now
        ) ).
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.

  METHOD createRequest.

    IF keys IS INITIAL.
      APPEND VALUE #(
        %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text     = 'STEP0: keys is INITIAL' )
      ) TO reported-req.
      RETURN.
    ENDIF.

    LOOP AT keys INTO DATA(ls_key).
      IF ls_key-%param-ConfId IS INITIAL.
        APPEND VALUE #(
         %msg = new_message_with_text(
           severity = if_abap_behv_message=>severity-error
           text     = 'STEP1: ConfId empty' )
       ) TO reported-req.
        CONTINUE.
      ENDIF.

      DATA: lv_target_app  TYPE char30,
            lv_conf_id_x16 TYPE sysuuid_x16,
            lv_req_id_x16  TYPE sysuuid_x16,
            lv_req_id_c36  TYPE sysuuid_c36,
            lv_item_id_x16 TYPE sysuuid_x16,
            lv_now         TYPE timestampl.

      GET TIME STAMP FIELD lv_now.

      CASE ls_key-%param-TargetCds.
        WHEN 'ZI_MM_ROUTE_CONF'. lv_target_app = 'MM_ROUTE_REQ'.
        WHEN 'ZI_MM_SAFE_STOCK'. lv_target_app = 'MM_SAFE_REQ'.
        WHEN 'ZI_SD_PRICE_CONF'. lv_target_app = 'SD_PRICE_REQ'.
        WHEN 'ZI_FI_LIMIT_CONF'. lv_target_app = 'FI_LIMIT_REQ'.
        WHEN OTHERS.             lv_target_app = 'CONF_REQ'.
      ENDCASE.
      " UUID từ frontend có thể có hoặc không có dấu '-'
      " cl_system_uuid expect đúng format C36: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      DATA(lv_conf_id_c36) = ls_key-%param-ConfId.


      " Nếu length = 32 (không có dash) thì insert dash
      IF strlen( lv_conf_id_c36 ) = 32.
        lv_conf_id_c36 = |{ lv_conf_id_c36(8) }-{ lv_conf_id_c36+8(4) }-{ lv_conf_id_c36+12(4) }-{ lv_conf_id_c36+16(4) }-{ lv_conf_id_c36+20(12) }|.
      ENDIF.

      TRY.
          " Dùng lv_conf_id_c36 đã được clean
          cl_system_uuid=>convert_uuid_c36_static(
            EXPORTING uuid     = lv_conf_id_c36
            IMPORTING uuid_x16 = lv_conf_id_x16 ).

          lv_req_id_x16  = cl_system_uuid=>create_uuid_x16_static( ).
          lv_item_id_x16 = cl_system_uuid=>create_uuid_x16_static( ).

          cl_system_uuid=>convert_uuid_x16_static(
            EXPORTING uuid     = lv_req_id_x16
            IMPORTING uuid_c36 = lv_req_id_c36 ).

        CATCH cx_uuid_error INTO DATA(lx_uuid).
          APPEND VALUE #(
            %msg = new_message_with_text(
              severity = if_abap_behv_message=>severity-error
              " ✅ Log lv_conf_id_c36 để debug chính xác hơn
              text = |UUID convert failed. Input=[{ lv_conf_id_c36 }] Err=[{ lx_uuid->get_text( ) }]| )
          ) TO reported-req.
          CONTINUE.
      ENDTRY.

      DATA(lv_env) = COND zde_env_id(
        WHEN ls_key-%param-TargetEnvId IS INITIAL THEN 'DEV'
        ELSE ls_key-%param-TargetEnvId ).

      INSERT zconfreqh FROM @( VALUE zconfreqh(
        client      = sy-mandt
        req_id      = lv_req_id_x16
        conf_id     = lv_conf_id_x16
        env_id      = lv_env
        module_id   = ls_key-%param-ModuleId
        req_title   = |Maintain { ls_key-%param-ConfName }|
        description = |Created from config app|
        reason      = ls_key-%param-Reason
        status      = gc_st_draft
        created_by  = sy-uname
        created_at  = lv_now
        changed_by  = sy-uname
        changed_at  = lv_now
      ) ).


" Sau INSERT zconfreqh
IF sy-subrc <> 0.
  APPEND VALUE #( %msg = new_message_with_text(
    severity = if_abap_behv_message=>severity-error
    text = |HEADER INSERT FAILED subrc={ sy-subrc }| ) ) TO reported-req.
  CONTINUE.
ENDIF.

APPEND VALUE #( %msg = new_message_with_text(
  severity = if_abap_behv_message=>severity-success
  text = |HEADER OK. conf_id_x16={ lv_conf_id_x16 } req_id={ lv_req_id_c36 }| ) ) TO reported-req.

APPEND VALUE #( %msg = new_message_with_text(
  severity = if_abap_behv_message=>severity-success
  text = |ITEM OK. About to append result| ) ) TO reported-req.

      IF sy-subrc <> 0.
        APPEND VALUE #(
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = |Failed to insert header| )
        ) TO reported-req.
        CONTINUE.
      ENDIF.

      INSERT zconfreqi FROM @( VALUE zconfreqi(
        client        = sy-mandt
        req_item_id   = lv_item_id_x16
        req_id        = lv_req_id_x16
        conf_id       = lv_conf_id_x16
        action        = ls_key-%param-ActionType
        target_env_id = lv_env
        notes         = ls_key-%param-Notes
        version_no    = 0
        created_by    = sy-uname
        created_at    = lv_now
        changed_by    = sy-uname
        changed_at    = lv_now
      ) ).
      break point.
APPEND VALUE #( %msg = new_message_with_text(
  severity = if_abap_behv_message=>severity-warning
  text = |INSERT zconfreqi subrc={ sy-subrc }| )
) TO reported-req.
      IF sy-subrc <> 0.
        " Rollback header nếu item fail
        DELETE zconfreqh FROM @( VALUE zconfreqh(
          client = sy-mandt
          req_id = lv_req_id_x16
        ) ).
        APPEND VALUE #(
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = |Failed to insert item| )
        ) TO reported-req.
        CONTINUE.
      ENDIF.

      " Thêm log trước khi append result
      APPEND VALUE #( %msg = new_message_with_text(
        severity = if_abap_behv_message=>severity-success
        text = |About to append result ReqId={ lv_req_id_c36 }| ) ) TO reported-req.

      " Trả về đầy đủ — ReqId đã biết trước
      APPEND VALUE #(
        %param-ReqId     = lv_req_id_c36
        %param-ReqItemId = ''
        %param-ConfId    = ls_key-%param-ConfId
        %param-ModuleId  = ls_key-%param-ModuleId
        %param-TargetCds = ls_key-%param-TargetCds
        %param-TargetApp = lv_target_app
      ) TO result.

    ENDLOOP.
  ENDMETHOD.


ENDCLASS.

CLASS lhc_Item DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS validate_item FOR VALIDATE ON SAVE IMPORTING keys FOR Item~validate_item.
ENDCLASS.

CLASS lhc_Item IMPLEMENTATION.
  METHOD validate_item.
    "    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
    "      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
    "    RESULT DATA(lt_items).

    "    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<i>).
    "     IF <i>-ConfId IS INITIAL.
    "      APPEND VALUE #(
    "       %tky = <i>-%tky
    "      %msg = new_message_with_text(
    "       severity = if_abap_behv_message=>severity-error
    "      text     = 'ConfId là bắt buộc'
    "   )
    " ) TO reported-item.
    " APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
    " ENDIF.

    "       IF <i>-Action IS INITIAL.
    "        APPEND VALUE #(
    "           %tky = <i>-%tky
    "           %msg = new_message_with_text(
    "            severity = if_abap_behv_message=>severity-error
    "          text     = 'Action là bắt buộc'
    "          )
    "       ) TO reported-item.
    "        APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
    "     ENDIF.

    "      IF <i>-TargetEnvId IS INITIAL.
    "    APPEND VALUE #(
    "        %tky = <i>-%tky
    "      %msg = new_message_with_text(
    "          severity = if_abap_behv_message=>severity-error
    "          text     = 'TargetEnvId là bắt buộc'
    "           )
    "     ) TO reported-item.
    "        APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
    "      ENDIF.
    "    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
