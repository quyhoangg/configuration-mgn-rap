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
    METHODS rollback FOR MODIFY IMPORTING keys FOR ACTION Req~rollback RESULT result.
    METHODS createRequest FOR MODIFY IMPORTING keys FOR ACTION Req~createRequest RESULT result.

    METHODS set_default_and_admin_fields FOR DETERMINE ON MODIFY IMPORTING keys FOR Req~set_default_and_admin_fields.
    METHODS validate_before_save FOR VALIDATE ON SAVE IMPORTING keys FOR Req~validate_before_save.

ENDCLASS.

CLASS lhc_Req IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_instance_features.
    " 1. Đọc trạng thái các bản ghi
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    " 2. Xác định Role người dùng một lần duy nhất (Single Source of Truth)
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id = @sy-uname AND is_active = @abap_true
      INTO @DATA(lv_current_role).

    LOOP AT lt_reqs INTO DATA(ls_req).
      " Khởi tạo mặc định là Disabled
      DATA(lv_approve_fc) = if_abap_behv=>fc-o-disabled.
      DATA(lv_promote_fc) = if_abap_behv=>fc-o-disabled.

      " Logic duyệt: Phải là trạng thái 'S' VÀ người dùng phải là 'MANAGER'
      IF ls_req-Status = 'S' AND lv_current_role = 'MANAGER'.
        lv_approve_fc = if_abap_behv=>fc-o-enabled.
      ENDIF.

      " Logic Promote: Phải là trạng thái 'A' VÀ người dùng là 'IT_ADMIN' (hoặc MANAGER tùy bạn)
      IF ls_req-Status = 'A' AND ( lv_current_role = 'MANAGER' OR lv_current_role = 'IT_ADMIN' ).
        lv_promote_fc = if_abap_behv=>fc-o-enabled.
      ENDIF.

      APPEND VALUE #( %tky            = ls_req-%tky
                      %action-approve = lv_approve_fc
                      %action-reject  = lv_approve_fc
                      %action-promote = lv_promote_fc
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

      " ── WRITE-BACK: zmmsafestock_req → zmmsafestock khi manager approve ──
      SELECT * FROM zmmsafestock_req
        WHERE req_id = @<r>-ReqId
        INTO TABLE @DATA(lt_ss_req).

      IF lt_ss_req IS NOT INITIAL.
        LOOP AT lt_ss_req ASSIGNING FIELD-SYMBOL(<ss>).

          CASE <ss>-action_type.

            WHEN 'U'.
              SELECT SINGLE @abap_true FROM zmmsafestock
                WHERE item_id = @<ss>-source_item_id
                INTO @DATA(lv_ss_exists).

              IF lv_ss_exists = abap_true.
                DATA(lv_new_version) = <ss>-version_no + 1.
                UPDATE zmmsafestock SET
                  env_id     = @<ss>-env_id,
                  plant_id   = @<ss>-plant_id,
                  mat_group  = @<ss>-mat_group,
                  min_qty    = @<ss>-min_qty,
                  version_no = @<ss>-version_no,
                  req_id     = @<r>-ReqId,
                  changed_by = @sy-uname,
                  changed_at = @lv_now
                WHERE item_id = @<ss>-source_item_id.
              ENDIF.

            WHEN 'C'.
              INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                client     = sy-mandt
                item_id    = <ss>-item_id
                req_id     = <r>-ReqId
                env_id     = <ss>-env_id
                plant_id   = <ss>-plant_id
                mat_group  = <ss>-mat_group
                min_qty    = <ss>-min_qty
                version_no = 1
                created_by = sy-uname
                created_at = lv_now
                changed_by = sy-uname
                changed_at = lv_now
              ) ).

            WHEN 'X'.
              DELETE FROM zmmsafestock
                WHERE item_id = @<ss>-source_item_id.

          ENDCASE.

        ENDLOOP.

        " Cập nhật line_status → 'A' cho tất cả req lines của request này
        UPDATE zmmsafestock_req SET
          line_status = 'A',
          changed_by  = @sy-uname,
          changed_at  = @lv_now
        WHERE req_id = @<r>-ReqId.

      ENDIF.
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

    " 1. Đọc dữ liệu Header (Sử dụng LOCAL MODE để đọc cả Buffer)
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      DATA(lv_has_error) = abap_false.

      " 2. Lấy lý do từ parameter của Action Popup
      DATA(ls_key_entry) = VALUE #( keys[ %tky = <r>-%tky ] OPTIONAL ).
      DATA(lv_reason)    = ls_key_entry-%param-reason.

      " 3. Làm sạch dữ liệu trạng thái (Xử lý lỗi dấu nháy đơn 'S do khoảng trắng)
      DATA(lv_current_status) = condense( <r>-Status ).

      " 4. Kiểm tra lý do trống
      IF lv_reason IS INITIAL.
        lv_has_error = abap_true.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = 'Vui lòng nhập lý do từ chối!' )
                      ) TO reported-req.
      ENDIF.

      " 5. Kiểm tra trạng thái S (Submitted) - Dùng so sánh an toàn
      IF lv_current_status <> 'S' AND lv_has_error = abap_false.
        lv_has_error = abap_true.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Yêu cầu không ở trạng thái S (Thực tế đọc được: '{ lv_current_status }')| )
                      ) TO reported-req.
        CONTINUE.
      ENDIF.

      IF lv_has_error = abap_true. CONTINUE. ENDIF.

      " 6. Ghi Log Audit (Sử dụng BASE để giữ lại dữ liệu cũ và cập nhật Status mới)
      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_req_id   = <r>-ReqId
            iv_conf_id  = <r>-ConfId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'REJECT'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = VALUE #( BASE <r> Status = 'R' Reason = lv_reason )
          ).
        CATCH cx_root.
      ENDTRY.

      " 7. Cập nhật vào Database
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status Reason RejectedBy RejectedAt )
        WITH VALUE #( ( %tky       = <r>-%tky
                        Status     = 'R'
                        Reason     = lv_reason
                        RejectedBy = sy-uname
                        RejectedAt = lv_now ) ).
    ENDLOOP.

    " 8. Đọc lại dữ liệu cuối cùng để trả về %param (BẮT BUỘC ĐỂ FIORI HIỆN MÀU ĐỎ)
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_final_reqs).

    result = VALUE #( FOR res IN lt_final_reqs ( %tky   = res-%tky
                                                 %param = res ) ).
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

  METHOD rollback.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-Status <> gc_st_approved AND <r>-Status <> gc_st_active.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Rollback chi duoc khi status la Approved hoac Active' )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      TRY.
          DATA(lt_restore) = zcl_gsp26_rule_snapshot=>restore_from_snapshot(
            iv_req_id     = <r>-ReqId
            iv_changed_by = sy-uname ).

          LOOP AT lt_restore INTO DATA(ls_res).
            APPEND VALUE #(
              %tky = <r>-%tky
              %msg = new_message_with_text(
                severity = COND #( WHEN ls_res-success = abap_true
                                   THEN if_abap_behv_message=>severity-success
                                   ELSE if_abap_behv_message=>severity-warning )
                text = ls_res-message )
            ) TO reported-req.
          ENDLOOP.
        CATCH cx_root INTO DATA(lx).
          APPEND VALUE #(
            %tky = <r>-%tky
            %msg = new_message_with_text(
              severity = if_abap_behv_message=>severity-error
              text     = |Rollback failed: { lx->get_text( ) }| )
          ) TO reported-req.
          APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
          CONTINUE.
      ENDTRY.

      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = <r>-ConfId
            iv_req_id   = <r>-ReqId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'ROLLBACK'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = VALUE #( BASE <r> Status = 'ROLLED_BACK' ) ).
        CATCH cx_root.
      ENDTRY.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky      = <r>-%tky
          Status    = 'ROLLED_BACK'
          ChangedBy = sy-uname
          ChangedAt = lv_now
        ) ).
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.

  METHOD createRequest.

    " ── Khai báo tất cả biến ở đây ──
    DATA lv_now              TYPE timestampl.
    DATA lv_conf_id_x16      TYPE sysuuid_x16.
    DATA lv_uuid_c36         TYPE sysuuid_c36.
    DATA lv_env              TYPE zde_env_id.
    DATA lv_req_id_x16       TYPE sysuuid_x16.
    DATA lv_req_item_id_x16  TYPE sysuuid_x16.
    DATA lv_req_id_c36       TYPE sysuuid_c36.
    DATA lv_target_app       TYPE char30.
    DATA lv_conf_id_c36      TYPE string.
    DATA lt_route            TYPE TABLE OF zmmrouteconf.
    DATA lt_safe             TYPE TABLE OF zmmsafestock.
    DATA lt_price            TYPE TABLE OF zsd_price_conf.
    DATA lt_limit            TYPE TABLE OF zfilimitconf.
    DATA ls_route            TYPE zmmrouteconf.
    DATA ls_safe             TYPE zmmsafestock.
    DATA ls_price            TYPE zsd_price_conf.
    DATA ls_limit            TYPE zfilimitconf.

    IF keys IS INITIAL. RETURN. ENDIF.

    LOOP AT keys INTO DATA(ls_key).

      CLEAR: lv_now, lv_conf_id_x16, lv_uuid_c36, lv_env,
             lv_req_id_x16, lv_req_item_id_x16, lv_req_id_c36,
             lv_target_app, lv_conf_id_c36,
             lt_route, lt_safe, lt_price, lt_limit.

      GET TIME STAMP FIELD lv_now.

      " ── Validate ConfId ──
      IF ls_key-%param-ConfId IS INITIAL.
        APPEND VALUE #(
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'ConfId is empty' )
        ) TO reported-req.
        CONTINUE.
      ENDIF.

      " ── Normalize UUID C36 ──
      lv_conf_id_c36 = to_upper( ls_key-%param-ConfId ).
      IF strlen( lv_conf_id_c36 ) = 32.
        lv_conf_id_c36 = lv_conf_id_c36(8)
          && '-' && lv_conf_id_c36+8(4)
          && '-' && lv_conf_id_c36+12(4)
          && '-' && lv_conf_id_c36+16(4)
          && '-' && lv_conf_id_c36+20(12).
      ENDIF.

      " ── Convert UUID C36 → X16 ──
      lv_uuid_c36 = lv_conf_id_c36.
      TRY.
          cl_system_uuid=>convert_uuid_c36_static(
            EXPORTING uuid     = lv_uuid_c36
            IMPORTING uuid_x16 = lv_conf_id_x16 ).
        CATCH cx_uuid_error INTO DATA(lx_uuid).
          APPEND VALUE #(
            %msg = new_message_with_text(
              severity = if_abap_behv_message=>severity-error
              text     = |UUID error: { lx_uuid->get_text( ) }| )
          ) TO reported-req.
          CONTINUE.
      ENDTRY.

      " ── Env ──
      lv_env = COND #(
        WHEN ls_key-%param-TargetEnvId IS INITIAL
        THEN 'DEV'
        ELSE ls_key-%param-TargetEnvId ).

      " ── Tạo header + item qua RAP ──
      MODIFY ENTITIES OF zir_conf_req_h
        IN LOCAL MODE
        ENTITY Req
          CREATE SET FIELDS
            WITH VALUE #( (
              %cid        = 'NEW_REQ'
              ConfId      = lv_conf_id_x16
              EnvId       = lv_env
              ModuleId    = ls_key-%param-ModuleId
              ReqTitle    = |Maintain { ls_key-%param-ConfName }|
              Description = |Created from config|
              Reason      = ls_key-%param-Reason
            ) )
        ENTITY Req
          CREATE BY \_Items SET FIELDS
            WITH VALUE #( (
              %cid_ref = 'NEW_REQ'
              %target  = VALUE #( (
                %cid        = 'NEW_ITEM'
                ConfId      = lv_conf_id_x16
                Action      = ls_key-%param-ActionType
                TargetEnvId = lv_env
                Notes       = ls_key-%param-Notes
                VersionNo   = 0
              ) )
            ) )
        MAPPED   DATA(ls_mapped)
        FAILED   DATA(ls_failed)
        REPORTED DATA(ls_reported).

      IF ls_failed-req IS NOT INITIAL.
        APPEND LINES OF ls_failed-req   TO failed-req.
        APPEND LINES OF ls_reported-req TO reported-req.
        CONTINUE.
      ENDIF.

      " ── Lấy req_id + req_item_id từ mapped ──
      lv_req_id_x16      = ls_mapped-req[ 1 ]-%key-ReqId.
      lv_req_item_id_x16 = ls_mapped-item[ 1 ]-%key-ReqItemId.

      " ── Snapshot theo TargetCds ──
      CASE ls_key-%param-TargetCds.

        WHEN 'ZI_MM_ROUTE_CONF'.
          SELECT * FROM zmmrouteconf
            WHERE env_id = @lv_env
            INTO TABLE @lt_route.

          LOOP AT lt_route INTO ls_route.
            INSERT zmmrouteconf_req FROM @( VALUE zmmrouteconf_req(
              client           = sy-mandt
              req_id           = lv_req_id_x16
              req_item_id      = lv_req_item_id_x16
              item_id          = cl_system_uuid=>create_uuid_x16_static( )
              source_item_id   = ls_route-item_id
              conf_id          = lv_conf_id_x16
              action_type      = 'U'
              old_env_id       = ls_route-env_id
              old_plant_id     = ls_route-plant_id
              old_send_wh      = ls_route-send_wh
              old_receive_wh   = ls_route-receive_wh
              old_inspector_id = ls_route-inspector_id
              old_trans_mode   = ls_route-trans_mode
              old_is_allowed   = ls_route-is_allowed
              old_version_no   = ls_route-version_no
              env_id           = ls_route-env_id
              plant_id         = ls_route-plant_id
              send_wh          = ls_route-send_wh
              receive_wh       = ls_route-receive_wh
              inspector_id     = ls_route-inspector_id
              trans_mode       = ls_route-trans_mode
              is_allowed       = ls_route-is_allowed
              version_no       = ls_route-version_no
              line_status      = 'D'
              created_by       = sy-uname
              created_at       = lv_now
              changed_by       = sy-uname
              changed_at       = lv_now
            ) ).
          ENDLOOP.

        WHEN 'ZI_MM_SAFE_STOCK'.
          SELECT * FROM zmmsafestock
            WHERE env_id = @lv_env
            INTO TABLE @lt_safe.

          LOOP AT lt_safe INTO ls_safe.
            INSERT zmmsafestock_req FROM @( VALUE zmmsafestock_req(
              client         = sy-mandt
              req_id         = lv_req_id_x16
              req_item_id    = lv_req_item_id_x16
              item_id        = cl_system_uuid=>create_uuid_x16_static( )
              source_item_id = ls_safe-item_id
              conf_id        = lv_conf_id_x16
              action_type    = 'U'
              old_env_id     = ls_safe-env_id
              old_plant_id   = ls_safe-plant_id
              old_mat_group  = ls_safe-mat_group
              old_min_qty    = ls_safe-min_qty
              old_version_no = ls_safe-version_no
              env_id         = ls_safe-env_id
              plant_id       = ls_safe-plant_id
              mat_group      = ls_safe-mat_group
              min_qty        = ls_safe-min_qty
              version_no     = ls_safe-version_no
              line_status    = 'D'
              created_by     = sy-uname
              created_at     = lv_now
              changed_by     = sy-uname
              changed_at     = lv_now
            ) ).
          ENDLOOP.

        WHEN 'ZI_SD_PRICE_CONF'.
          SELECT * FROM zsd_price_conf
            WHERE env_id = @lv_env
            INTO TABLE @lt_price.

          LOOP AT lt_price INTO ls_price.
            INSERT zsd_price_req FROM @( VALUE zsd_price_req(
              client            = sy-mandt
              req_id            = lv_req_id_x16
              req_item_id       = lv_req_item_id_x16
              item_id           = cl_system_uuid=>create_uuid_x16_static( )
              source_item_id    = ls_price-item_id
              conf_id           = lv_conf_id_x16
              action_type       = 'U'
              old_env_id        = ls_price-env_id
              old_branch_id     = ls_price-branch_id
              old_cust_group    = ls_price-cust_group
              old_material_grp  = ls_price-material_grp
              old_max_discount  = ls_price-max_discount
              old_min_order_val = ls_price-min_order_val
              old_currency      = ls_price-currency
              old_valid_from    = ls_price-valid_from
              old_valid_to      = ls_price-valid_to
              old_version_no    = ls_price-version_no
              env_id            = ls_price-env_id
              branch_id         = ls_price-branch_id
              cust_group        = ls_price-cust_group
              material_grp      = ls_price-material_grp
              max_discount      = ls_price-max_discount
              min_order_val     = ls_price-min_order_val
              currency          = ls_price-currency
              valid_from        = ls_price-valid_from
              valid_to          = ls_price-valid_to
              version_no        = ls_price-version_no
              line_status       = 'D'
              created_by        = sy-uname
              created_at        = lv_now
              changed_by        = sy-uname
              changed_at        = lv_now
            ) ).
          ENDLOOP.

        WHEN 'ZI_FI_LIMIT_CONF'.
          SELECT * FROM zfilimitconf
            WHERE env_id = @lv_env
            INTO TABLE @lt_limit.

          LOOP AT lt_limit INTO ls_limit.
            INSERT zfilimitreq FROM @( VALUE zfilimitreq(
              client            = sy-mandt
              req_id            = lv_req_id_x16
              req_item_id       = lv_req_item_id_x16
              item_id           = cl_system_uuid=>create_uuid_x16_static( )
              source_item_id    = ls_limit-item_id
              conf_id           = lv_conf_id_x16
              action_type       = 'U'
              old_env_id        = ls_limit-env_id
              old_expense_type  = ls_limit-expense_type
              old_gl_account    = ls_limit-gl_account
              old_auto_appr_lim = ls_limit-auto_appr_lim
              old_currency      = ls_limit-currency
              old_version_no    = ls_limit-version_no
              env_id            = ls_limit-env_id
              expense_type      = ls_limit-expense_type
              gl_account        = ls_limit-gl_account
              auto_appr_lim     = ls_limit-auto_appr_lim
              currency          = ls_limit-currency
              version_no        = ls_limit-version_no
              line_status       = 'D'
              created_by        = sy-uname
              created_at        = lv_now
              changed_by        = sy-uname
              changed_at        = lv_now
            ) ).
          ENDLOOP.

      ENDCASE.

      " ── Trả về result ──
      cl_system_uuid=>convert_uuid_x16_static(
        EXPORTING uuid     = lv_req_id_x16
        IMPORTING uuid_c36 = lv_req_id_c36 ).

      lv_target_app = SWITCH #( ls_key-%param-TargetCds
        WHEN 'ZI_MM_ROUTE_CONF' THEN 'MM_ROUTE_REQ'
        WHEN 'ZI_MM_SAFE_STOCK' THEN 'MM_SAFE_REQ'
        WHEN 'ZI_SD_PRICE_CONF' THEN 'SD_PRICE_REQ'
        WHEN 'ZI_FI_LIMIT_CONF' THEN 'FI_LIMIT_REQ'
        ELSE                         'CONF_REQ' ).

      APPEND VALUE #(
        %param-ReqId     = lv_req_id_c36
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
