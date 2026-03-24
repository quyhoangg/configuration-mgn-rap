CLASS lhc_Req DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    CONSTANTS:
      gc_st_draft       TYPE zde_requ_status VALUE 'DRAFT',
      gc_st_submitted   TYPE zde_requ_status VALUE 'SUBMITTED',
      gc_st_approved    TYPE zde_requ_status VALUE 'APPROVED',
      gc_st_rejected    TYPE zde_requ_status VALUE 'REJECTED',
      gc_st_active      TYPE zde_requ_status VALUE 'ACTIVE',
      gc_st_rolled_back TYPE zde_requ_status VALUE 'ROLLED_BACK'.

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
     METHODS apply FOR MODIFY IMPORTING keys FOR ACTION Req~apply RESULT
  result.
    METHODS rollback FOR MODIFY IMPORTING keys FOR ACTION Req~rollback RESULT result.
    METHODS createRequest FOR MODIFY IMPORTING keys FOR ACTION Req~createRequest RESULT result.
    METHODS updateReason FOR MODIFY IMPORTING keys FOR ACTION Req~updateReason RESULT result.

    METHODS set_default_and_admin_fields FOR DETERMINE ON MODIFY IMPORTING keys FOR Req~set_default_and_admin_fields.
    METHODS validate_before_save FOR VALIDATE ON SAVE IMPORTING keys FOR Req~validate_before_save.

ENDCLASS.

CLASS lhc_Req IMPLEMENTATION.





  METHOD get_instance_authorizations.
    " 1. Lấy Role người dùng hiện hành từ bảng zuserrole
    DATA lv_role TYPE c LENGTH 20.
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id  = @sy-uname AND is_active = @abap_true
      INTO @lv_role.

    " 2. Đọc các record đang xử lý
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    " 3. Map phân quyền (Ai không có role tương ứng -> auth-unauthorized -> NÚT BIẾN MẤT)
    DATA(lv_auth_submit)  = COND #( WHEN lv_role IS NOT INITIAL
                                      THEN if_abap_behv=>auth-allowed
                                      ELSE if_abap_behv=>auth-unauthorized ).

    DATA(lv_auth_manager) = COND #( WHEN lv_role = 'MANAGER'
                                      THEN if_abap_behv=>auth-allowed
                                      ELSE if_abap_behv=>auth-unauthorized ).

    DATA(lv_auth_itadmin) = COND #( WHEN lv_role = 'IT ADMIN'
                                      THEN if_abap_behv=>auth-allowed
                                      ELSE if_abap_behv=>auth-unauthorized ).

    " 4. Áp dụng kết quả cho từng Item
    LOOP AT lt_reqs INTO DATA(ls_req).
      APPEND VALUE #( %tky                 = ls_req-%tky
                      %update              = if_abap_behv=>auth-allowed
                      %delete              = if_abap_behv=>auth-allowed
                      %action-submit       = lv_auth_submit
                      %action-approve      = lv_auth_manager
                      %action-reject       = lv_auth_manager
                      %action-updatereason = lv_auth_manager
                      %action-promote      = lv_auth_itadmin
                      %action-apply        = lv_auth_itadmin
                      %action-rollback     = lv_auth_itadmin
                    ) TO result.
    ENDLOOP.
  ENDMETHOD.


  METHOD get_instance_features.
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
      IF zcl_gsp26_rule_status=>is_transition_valid_by_status(
             iv_current_status = CONV string( <r>-Status )
             iv_next_status    = zcl_gsp26_rule_status=>cv_approved ) = abap_false.
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
        CATCH cx_root INTO DATA(lx_audit_apr).
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-warning
            text = |Audit log failed: { lx_audit_apr->get_text( ) }| ) ) TO reported-req.
      ENDTRY.

      " 6. Cập nhật trạng thái APPROVED
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ApprovedBy ApprovedAt )
        WITH VALUE #( ( %tky = <r>-%tky Status = gc_st_approved ApprovedBy = sy-uname ApprovedAt = lv_now ) ).
      " Tăng version sau khi approve thành công
      DATA(lt_ver_results) = zcl_gsp26_rule_snapshot=>increment_version( iv_req_id = <r>-ReqId ).


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

              " ── WRITE-BACK: zmmrouteconf_req → zmmrouteconf ──
      SELECT * FROM zmmrouteconf_req
        WHERE req_id = @<r>-ReqId
        INTO TABLE @DATA(lt_route_req).

      IF lt_route_req IS NOT INITIAL.
        LOOP AT lt_route_req ASSIGNING FIELD-SYMBOL(<rt>).
          CASE <rt>-action_type.
            WHEN 'U'.
              SELECT SINGLE @abap_true FROM zmmrouteconf
                WHERE item_id = @<rt>-source_item_id
                INTO @DATA(lv_rt_exists).
              IF lv_rt_exists = abap_true.
                UPDATE zmmrouteconf SET
                  env_id       = @<rt>-env_id,
                  plant_id     = @<rt>-plant_id,
                  send_wh      = @<rt>-send_wh,
                  receive_wh   = @<rt>-receive_wh,
                  inspector_id = @<rt>-inspector_id,
                  trans_mode   = @<rt>-trans_mode,
                  is_allowed   = @<rt>-is_allowed,
                  version_no   = @<rt>-version_no,
                  req_id       = @<r>-ReqId,
                  changed_by   = @sy-uname,
                  changed_at   = @lv_now
                WHERE item_id = @<rt>-source_item_id.
              ENDIF.
            WHEN 'C'.
              INSERT zmmrouteconf FROM @( VALUE zmmrouteconf(
                client       = sy-mandt
                item_id      = <rt>-item_id
                req_id       = <r>-ReqId
                env_id       = <rt>-env_id
                plant_id     = <rt>-plant_id
                send_wh      = <rt>-send_wh
                receive_wh   = <rt>-receive_wh
                inspector_id = <rt>-inspector_id
                trans_mode   = <rt>-trans_mode
                is_allowed   = <rt>-is_allowed
                version_no   = 1
                created_by   = sy-uname
                created_at   = lv_now
                changed_by   = sy-uname
                changed_at   = lv_now
              ) ).
            WHEN 'X'.
              DELETE FROM zmmrouteconf WHERE item_id = @<rt>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zmmrouteconf_req SET
          line_status = 'A', changed_by = @sy-uname, changed_at = @lv_now
          WHERE req_id = @<r>-ReqId.
      ENDIF.

      " ── WRITE-BACK: zfilimitreq → zfilimitconf ──
      SELECT * FROM zfilimitreq
        WHERE req_id = @<r>-ReqId
        INTO TABLE @DATA(lt_fi_req).

      IF lt_fi_req IS NOT INITIAL.
        LOOP AT lt_fi_req ASSIGNING FIELD-SYMBOL(<fi>).
          CASE <fi>-action_type.
            WHEN 'U'.
              SELECT SINGLE @abap_true FROM zfilimitconf
                WHERE item_id = @<fi>-source_item_id
                INTO @DATA(lv_fi_exists).
              IF lv_fi_exists = abap_true.
                UPDATE zfilimitconf SET
                  env_id        = @<fi>-env_id,
                  expense_type  = @<fi>-expense_type,
                  gl_account    = @<fi>-gl_account,
                  auto_appr_lim = @<fi>-auto_appr_lim,
                  currency      = @<fi>-currency,
                  version_no    = @<fi>-version_no,
                  req_id        = @<r>-ReqId,
                  changed_by    = @sy-uname,
                  changed_at    = @lv_now
                WHERE item_id = @<fi>-source_item_id.
              ENDIF.
            WHEN 'C'.
              INSERT zfilimitconf FROM @( VALUE zfilimitconf(
                client        = sy-mandt
                item_id       = <fi>-item_id
                req_id        = <r>-ReqId
                env_id        = <fi>-env_id
                expense_type  = <fi>-expense_type
                gl_account    = <fi>-gl_account
                auto_appr_lim = <fi>-auto_appr_lim
                currency      = <fi>-currency
                version_no    = 1
                created_by    = sy-uname
                created_at    = lv_now
                changed_by    = sy-uname
                changed_at    = lv_now
              ) ).
            WHEN 'X'.
              DELETE FROM zfilimitconf WHERE item_id = @<fi>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zfilimitreq SET
          line_status = 'A', changed_by = @sy-uname, changed_at = @lv_now
          WHERE req_id = @<r>-ReqId.
      ENDIF.

      " ── WRITE-BACK: zsd_price_req → zsd_price_conf ──
      SELECT * FROM zsd_price_req
        WHERE req_id = @<r>-ReqId
        INTO TABLE @DATA(lt_sd_req).

      IF lt_sd_req IS NOT INITIAL.
        LOOP AT lt_sd_req ASSIGNING FIELD-SYMBOL(<sd>).
          CASE <sd>-action_type.
            WHEN 'U'.
              SELECT SINGLE @abap_true FROM zsd_price_conf
                WHERE item_id = @<sd>-source_item_id
                INTO @DATA(lv_sd_exists).
              IF lv_sd_exists = abap_true.
                UPDATE zsd_price_conf SET
                  env_id        = @<sd>-env_id,
                  branch_id     = @<sd>-branch_id,
                  cust_group    = @<sd>-cust_group,
                  material_grp  = @<sd>-material_grp,
                  max_discount  = @<sd>-max_discount,
                  min_order_val = @<sd>-min_order_val,
                  currency      = @<sd>-currency,
                  valid_from    = @<sd>-valid_from,
                  valid_to      = @<sd>-valid_to,
                  version_no    = @<sd>-version_no,
                  req_id        = @<r>-ReqId,
                  changed_by    = @sy-uname,
                  changed_at    = @lv_now
                WHERE item_id = @<sd>-source_item_id.
              ENDIF.
            WHEN 'C'.
              INSERT zsd_price_conf FROM @( VALUE zsd_price_conf(
                client        = sy-mandt
                item_id       = <sd>-item_id
                req_id        = <r>-ReqId
                env_id        = <sd>-env_id
                branch_id     = <sd>-branch_id
                cust_group    = <sd>-cust_group
                material_grp  = <sd>-material_grp
                max_discount  = <sd>-max_discount
                min_order_val = <sd>-min_order_val
                currency      = <sd>-currency
                valid_from    = <sd>-valid_from
                valid_to      = <sd>-valid_to
                version_no    = 1
                created_by    = sy-uname
                created_at    = lv_now
                changed_by    = sy-uname
                changed_at    = lv_now
              ) ).
            WHEN 'X'.
              DELETE FROM zsd_price_conf WHERE item_id = @<sd>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zsd_price_req SET
          line_status = 'A', changed_by = @sy-uname, changed_at = @lv_now
          WHERE req_id = @<r>-ReqId.
      ENDIF.


        " Cập nhật line_status → APPROVED cho tất cả req lines của request này
        UPDATE zmmsafestock_req SET
          line_status = @gc_st_approved,
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

  METHOD reject.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    " 1. Đọc dữ liệu Header
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      DATA(lv_has_error) = abap_false.

      " 2. Lấy lý do từ parameter của Action Popup
      DATA(ls_key_entry) = VALUE #( keys[ %tky = <r>-%tky ] OPTIONAL ).
      DATA(lv_reason)    = ls_key_entry-%param-reason.

      " 3. Làm sạch dữ liệu trạng thái
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

      " 5. Kiểm tra trạng thái SUBMITTED
      IF zcl_gsp26_rule_status=>is_transition_valid_by_status(
             iv_current_status = CONV string( lv_current_status )
             iv_next_status    = zcl_gsp26_rule_status=>cv_rejected ) = abap_false AND lv_has_error = abap_false.
        lv_has_error = abap_true.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                                 severity = if_abap_behv_message=>severity-error
                                 text     = |Yêu cầu không ở trạng thái SUBMITTED (Thực tế: '{ lv_current_status }')| )
                      ) TO reported-req.
        CONTINUE.
      ENDIF.

      IF lv_has_error = abap_true. CONTINUE. ENDIF.

      " 6. Ghi Log Audit
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
        CATCH cx_root INTO DATA(lx_audit_rej).
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-warning
            text = |Audit log failed: { lx_audit_rej->get_text( ) }| ) ) TO reported-req.
      ENDTRY.

      " 7. Cập nhật vào Database
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status Reason RejectedBy RejectedAt )
        WITH VALUE #( ( %tky       = <r>-%tky
                        Status     = gc_st_rejected
                        Reason     = lv_reason
                        RejectedBy = sy-uname
                        RejectedAt = lv_now ) ).
    ENDLOOP.

    " 8. Đọc lại dữ liệu cuối cùng để trả về %param
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_final_reqs).

    result = VALUE #( FOR res IN lt_final_reqs ( %tky   = res-%tky
                                                 %param = res ) ).
  ENDMETHOD.

  METHOD submit.                                                                                                                                                                                        " Đọc headers + items 1 lần duy nhất (tránh N+1)
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req FIELDS ( ReqId Status ) WITH CORRESPONDING #( keys ) RESULT DATA(reqs)
      ENTITY Req BY \_Items FIELDS ( ReqId ) WITH CORRESPONDING #( keys ) RESULT DATA(all_items).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      IF zcl_gsp26_rule_status=>is_transition_valid_by_status(
           iv_current_status = CONV string( <r>-Status )
           iv_next_status    = zcl_gsp26_rule_status=>cv_submitted ) = abap_false.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
          severity = if_abap_behv_message=>severity-error
          text = 'Invalid status transition for Submit' ) ) TO reported-req.
        CONTINUE.
      ENDIF.

      READ TABLE all_items WITH KEY ReqId = <r>-ReqId TRANSPORTING NO FIELDS.
      IF sy-subrc <> 0.
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

      " Chấp nhận cả APPROVED và ACTIVE (mid-way promote)
      IF <r>-Status <> gc_st_approved AND <r>-Status <> gc_st_active.
        APPEND VALUE #( %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Promote chỉ được khi status là Approved hoặc Active' )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      " Xác định env tiếp theo
      DATA(lv_next_env) = CONV zde_env_id( SWITCH #( condense( <r>-EnvId )
  WHEN 'DEV' THEN 'QAS'
  WHEN 'QAS' THEN 'PRD'
  ELSE '' ) ).

      IF lv_next_env IS INITIAL.
        APPEND VALUE #( %tky = <r>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Request đã ở PRD, không thể promote tiếp.' )
        ) TO reported-req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
        CONTINUE.
      ENDIF.

      " ── Copy MM SafeStock sang next env ──
      SELECT * FROM zmmsafestock_req
        WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_ss).
      LOOP AT lt_ss ASSIGNING FIELD-SYMBOL(<ss>).
        CASE <ss>-action_type.
          WHEN 'U' OR 'C'.
            SELECT SINGLE item_id FROM zmmsafestock
              WHERE env_id = @lv_next_env
                AND plant_id = @<ss>-plant_id
                AND mat_group = @<ss>-mat_group
              INTO @DATA(lv_ss_tgt_id).
            IF sy-subrc = 0.
              UPDATE zmmsafestock SET
                min_qty = @<ss>-min_qty, version_no = version_no + 1,
                req_id = @<r>-ReqId, changed_by = @sy-uname, changed_at = @lv_now
                WHERE item_id = @lv_ss_tgt_id.
            ELSE.
              INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                client = sy-mandt  item_id = cl_system_uuid=>create_uuid_x16_static( )
                req_id = <r>-ReqId  env_id = lv_next_env
                plant_id = <ss>-plant_id  mat_group = <ss>-mat_group
                min_qty = <ss>-min_qty  version_no = 1
                created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
            ENDIF.
          WHEN 'X'.
            DELETE FROM zmmsafestock
              WHERE env_id = @lv_next_env
                AND plant_id = @<ss>-plant_id AND mat_group = @<ss>-mat_group.
        ENDCASE.
      ENDLOOP.

      " ── Copy MM Route sang next env ──
      SELECT * FROM zmmrouteconf_req
        WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_rt).
      LOOP AT lt_rt ASSIGNING FIELD-SYMBOL(<rt>).
        CASE <rt>-action_type.
          WHEN 'U' OR 'C'.
            SELECT SINGLE item_id FROM zmmrouteconf
              WHERE env_id = @lv_next_env AND plant_id = @<rt>-plant_id
              INTO @DATA(lv_rt_tgt_id).
            IF sy-subrc = 0.
              UPDATE zmmrouteconf SET
                send_wh = @<rt>-send_wh, receive_wh = @<rt>-receive_wh,
                inspector_id = @<rt>-inspector_id, trans_mode = @<rt>-trans_mode,
                is_allowed = @<rt>-is_allowed, version_no = version_no + 1,
                req_id = @<r>-ReqId, changed_by = @sy-uname, changed_at = @lv_now
                WHERE item_id = @lv_rt_tgt_id.
            ELSE.
              INSERT zmmrouteconf FROM @( VALUE zmmrouteconf(
                client = sy-mandt  item_id = cl_system_uuid=>create_uuid_x16_static( )
                req_id = <r>-ReqId  env_id = lv_next_env
                plant_id = <rt>-plant_id  send_wh = <rt>-send_wh
                receive_wh = <rt>-receive_wh  inspector_id = <rt>-inspector_id
                trans_mode = <rt>-trans_mode  is_allowed = <rt>-is_allowed
                version_no = 1
                created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
            ENDIF.
          WHEN 'X'.
            DELETE FROM zmmrouteconf
              WHERE env_id = @lv_next_env AND plant_id = @<rt>-plant_id.
        ENDCASE.
      ENDLOOP.

      " ── Copy FI Limit sang next env ──
      SELECT * FROM zfilimitreq
        WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_fi).
      LOOP AT lt_fi ASSIGNING FIELD-SYMBOL(<fi>).
        CASE <fi>-action_type.
          WHEN 'U' OR 'C'.
            SELECT SINGLE item_id FROM zfilimitconf
              WHERE env_id = @lv_next_env
                AND expense_type = @<fi>-expense_type AND gl_account = @<fi>-gl_account
              INTO @DATA(lv_fi_tgt_id).
            IF sy-subrc = 0.
              UPDATE zfilimitconf SET
                auto_appr_lim = @<fi>-auto_appr_lim, currency = @<fi>-currency,
                version_no = version_no + 1, req_id = @<r>-ReqId,
                changed_by = @sy-uname, changed_at = @lv_now
                WHERE item_id = @lv_fi_tgt_id.
            ELSE.
              INSERT zfilimitconf FROM @( VALUE zfilimitconf(
                client = sy-mandt  item_id = cl_system_uuid=>create_uuid_x16_static( )
                req_id = <r>-ReqId  env_id = lv_next_env
                expense_type = <fi>-expense_type  gl_account = <fi>-gl_account
                auto_appr_lim = <fi>-auto_appr_lim  currency = <fi>-currency
                version_no = 1
                created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
            ENDIF.
          WHEN 'X'.
            DELETE FROM zfilimitconf
              WHERE env_id = @lv_next_env
                AND expense_type = @<fi>-expense_type AND gl_account = @<fi>-gl_account.
        ENDCASE.
      ENDLOOP.

      " ── Copy SD Price sang next env ──
      SELECT * FROM zsd_price_req
        WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_sd).
      LOOP AT lt_sd ASSIGNING FIELD-SYMBOL(<sd>).
        CASE <sd>-action_type.
          WHEN 'U' OR 'C'.
            SELECT SINGLE item_id FROM zsd_price_conf
              WHERE env_id = @lv_next_env
                AND branch_id = @<sd>-branch_id AND cust_group = @<sd>-cust_group
                AND material_grp = @<sd>-material_grp
              INTO @DATA(lv_sd_tgt_id).
            IF sy-subrc = 0.
              UPDATE zsd_price_conf SET
                max_discount = @<sd>-max_discount, min_order_val = @<sd>-min_order_val,
                currency = @<sd>-currency, valid_from = @<sd>-valid_from,
                valid_to = @<sd>-valid_to, version_no = version_no + 1,
                req_id = @<r>-ReqId, changed_by = @sy-uname, changed_at = @lv_now
                WHERE item_id = @lv_sd_tgt_id.
            ELSE.
              INSERT zsd_price_conf FROM @( VALUE zsd_price_conf(
                client = sy-mandt  item_id = cl_system_uuid=>create_uuid_x16_static( )
                req_id = <r>-ReqId  env_id = lv_next_env
                branch_id = <sd>-branch_id  cust_group = <sd>-cust_group
                material_grp = <sd>-material_grp  max_discount = <sd>-max_discount
                min_order_val = <sd>-min_order_val  currency = <sd>-currency
                valid_from = <sd>-valid_from  valid_to = <sd>-valid_to
                version_no = 1
                created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
            ENDIF.
          WHEN 'X'.
            DELETE FROM zsd_price_conf
              WHERE env_id = @lv_next_env
                AND branch_id = @<sd>-branch_id AND cust_group = @<sd>-cust_group
                AND material_grp = @<sd>-material_grp.
        ENDCASE.
      ENDLOOP.

      " ── Audit log ──
      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = <r>-ConfId  iv_req_id = <r>-ReqId
            iv_mod_id   = <r>-ModuleId  iv_act_type = 'PROMOTE'
            iv_tab_name = 'ZCONFREQH'  iv_env_id = lv_next_env
            is_new_data = VALUE #( BASE <r> Status = gc_st_active EnvId = lv_next_env ) ).
        CATCH cx_root INTO DATA(lx_audit).
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-warning
            text = |Audit log skipped: { lx_audit->get_text( ) }| ) ) TO reported-req.
      ENDTRY.

      " ── Cập nhật header: EnvId + Status ──
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status EnvId ChangedBy ChangedAt )
        WITH VALUE #( ( %tky = <r>-%tky
                        Status    = gc_st_active
                        EnvId     = lv_next_env
                        ChangedBy = sy-uname
                        ChangedAt = lv_now ) ).

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
            is_new_data = VALUE #( BASE <r> Status = gc_st_rolled_back ) ).
        CATCH cx_root INTO DATA(lx_audit_rb).
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-warning
            text = |Audit log failed: { lx_audit_rb->get_text( ) }| ) ) TO reported-req.
      ENDTRY.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky      = <r>-%tky
          Status    = gc_st_rolled_back
          ChangedBy = sy-uname
          ChangedAt = lv_now
        ) ).
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.


 METHOD apply.
      DATA lv_now TYPE timestampl.
      GET TIME STAMP FIELD lv_now.

      READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(reqs).

      LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).

        IF <r>-Status <> gc_st_approved.
          APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text = 'Apply chỉ được thực hiện khi status là Approved' ) ) TO
  reported-req.
          CONTINUE.
        ENDIF.

        " ── MM Route: zmmrouteconf_req → zmmrouteconf ──
        SELECT * FROM zmmrouteconf_req
          WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_route_req).
        IF lt_route_req IS NOT INITIAL.
          LOOP AT lt_route_req ASSIGNING FIELD-SYMBOL(<rt>).
            CASE <rt>-action_type.
              WHEN 'U'.
                SELECT SINGLE @abap_true FROM zmmrouteconf
                  WHERE item_id = @<rt>-source_item_id INTO
  @DATA(lv_rt_exists).
                IF lv_rt_exists = abap_true.
                  UPDATE zmmrouteconf SET
                    env_id = @<rt>-env_id, plant_id = @<rt>-plant_id,
                    send_wh = @<rt>-send_wh, receive_wh = @<rt>-receive_wh,
                    inspector_id = @<rt>-inspector_id, trans_mode =
  @<rt>-trans_mode,
                    is_allowed = @<rt>-is_allowed, version_no =
  @<rt>-version_no,
                    req_id = @<r>-ReqId, changed_by = @sy-uname, changed_at
  = @lv_now
                  WHERE item_id = @<rt>-source_item_id.
                ENDIF.
                CLEAR lv_rt_exists.
              WHEN 'C'.
                INSERT zmmrouteconf FROM @( VALUE zmmrouteconf(
                  client = sy-mandt  item_id = <rt>-item_id  req_id =
  <r>-ReqId
                  env_id = <rt>-env_id  plant_id = <rt>-plant_id
                  send_wh = <rt>-send_wh  receive_wh = <rt>-receive_wh
                  inspector_id = <rt>-inspector_id  trans_mode =
  <rt>-trans_mode
                  is_allowed = <rt>-is_allowed  version_no = 1
                  created_by = sy-uname  created_at = lv_now
                  changed_by = sy-uname  changed_at = lv_now ) ).
              WHEN 'X'.
                DELETE FROM zmmrouteconf WHERE item_id =
  @<rt>-source_item_id.
            ENDCASE.
          ENDLOOP.
          UPDATE zmmrouteconf_req SET
            line_status = @gc_st_active, changed_by = @sy-uname, changed_at
  = @lv_now
          WHERE req_id = @<r>-ReqId.
        ENDIF.

        " ── MM Safe Stock: zmmsafestock_req → zmmsafestock ──
        SELECT * FROM zmmsafestock_req
          WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_ss_req).
        IF lt_ss_req IS NOT INITIAL.
          LOOP AT lt_ss_req ASSIGNING FIELD-SYMBOL(<ss>).
            CASE <ss>-action_type.
              WHEN 'U'.
                SELECT SINGLE @abap_true FROM zmmsafestock
                  WHERE item_id = @<ss>-source_item_id INTO
  @DATA(lv_ss_exists).
                IF lv_ss_exists = abap_true.
                  UPDATE zmmsafestock SET
                    env_id = @<ss>-env_id, plant_id = @<ss>-plant_id,
                    mat_group = @<ss>-mat_group, min_qty = @<ss>-min_qty,
                    version_no = @<ss>-version_no, req_id = @<r>-ReqId,
                    changed_by = @sy-uname, changed_at = @lv_now
                  WHERE item_id = @<ss>-source_item_id.
                ENDIF.
                CLEAR lv_ss_exists.
              WHEN 'C'.
                INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                  client = sy-mandt  item_id = <ss>-item_id  req_id =
  <r>-ReqId
                  env_id = <ss>-env_id  plant_id = <ss>-plant_id
                  mat_group = <ss>-mat_group  min_qty = <ss>-min_qty
                  version_no = 1  created_by = sy-uname  created_at = lv_now
                  changed_by = sy-uname  changed_at = lv_now ) ).
              WHEN 'X'.
                DELETE FROM zmmsafestock WHERE item_id =
  @<ss>-source_item_id.
            ENDCASE.
          ENDLOOP.
          UPDATE zmmsafestock_req SET
            line_status = @gc_st_active, changed_by = @sy-uname, changed_at
  = @lv_now
          WHERE req_id = @<r>-ReqId.
        ENDIF.

        " ── SD Price: zsd_price_req → zsd_price_conf ──
        SELECT * FROM zsd_price_req
          WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_price_req).
        IF lt_price_req IS NOT INITIAL.
          LOOP AT lt_price_req ASSIGNING FIELD-SYMBOL(<pr>).
            CASE <pr>-action_type.
              WHEN 'U'.
                SELECT SINGLE @abap_true FROM zsd_price_conf
                  WHERE item_id = @<pr>-source_item_id INTO
  @DATA(lv_pr_exists).
                IF lv_pr_exists = abap_true.
                  UPDATE zsd_price_conf SET
                    env_id = @<pr>-env_id, branch_id = @<pr>-branch_id,
                    cust_group = @<pr>-cust_group, material_grp =
  @<pr>-material_grp,
                    max_discount = @<pr>-max_discount, min_order_val =
  @<pr>-min_order_val,
                    approver_grp = @<pr>-approver_grp, currency =
  @<pr>-currency,
                    valid_from = @<pr>-valid_from, valid_to =
  @<pr>-valid_to,
                    version_no = @<pr>-version_no, req_id = @<r>-ReqId,
                    changed_by = @sy-uname, changed_at = @lv_now
                  WHERE item_id = @<pr>-source_item_id.
                ENDIF.
                CLEAR lv_pr_exists.
              WHEN 'C'.
                INSERT zsd_price_conf FROM @( VALUE zsd_price_conf(
                  client = sy-mandt  item_id = <pr>-item_id  req_id =
  <r>-ReqId
                  env_id = <pr>-env_id  branch_id = <pr>-branch_id
                  cust_group = <pr>-cust_group  material_grp =
  <pr>-material_grp
                  max_discount = <pr>-max_discount  min_order_val =
  <pr>-min_order_val
                  approver_grp = <pr>-approver_grp  currency = <pr>-currency
                  valid_from = <pr>-valid_from  valid_to = <pr>-valid_to
                  version_no = 1  created_by = sy-uname  created_at = lv_now
                  changed_by = sy-uname  changed_at = lv_now ) ).
              WHEN 'X'.
                DELETE FROM zsd_price_conf WHERE item_id =
  @<pr>-source_item_id.
            ENDCASE.
          ENDLOOP.
          UPDATE zsd_price_req SET
            line_status = @gc_st_active, changed_by = @sy-uname, changed_at
  = @lv_now
          WHERE req_id = @<r>-ReqId.
        ENDIF.

        " ── FI Limit: zfilimitreq → zfilimitconf ──
        SELECT * FROM zfilimitreq
          WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_limit_req).
        IF lt_limit_req IS NOT INITIAL.
          LOOP AT lt_limit_req ASSIGNING FIELD-SYMBOL(<fl>).
            CASE <fl>-action_type.
              WHEN 'U'.
                SELECT SINGLE @abap_true FROM zfilimitconf
                  WHERE item_id = @<fl>-source_item_id INTO
  @DATA(lv_fl_exists).
                IF lv_fl_exists = abap_true.
                  UPDATE zfilimitconf SET
                    env_id = @<fl>-env_id, expense_type =
  @<fl>-expense_type,
                    gl_account = @<fl>-gl_account, auto_appr_lim =
  @<fl>-auto_appr_lim,
                    currency = @<fl>-currency, version_no =
  @<fl>-version_no,
                    req_id = @<r>-ReqId, changed_by = @sy-uname, changed_at
  = @lv_now
                  WHERE item_id = @<fl>-source_item_id.
                ENDIF.
                CLEAR lv_fl_exists.
              WHEN 'C'.
                INSERT zfilimitconf FROM @( VALUE zfilimitconf(
                  client = sy-mandt  item_id = <fl>-item_id  req_id =
  <r>-ReqId
                  env_id = <fl>-env_id  expense_type = <fl>-expense_type
                  gl_account = <fl>-gl_account  auto_appr_lim =
  <fl>-auto_appr_lim
                  currency = <fl>-currency  version_no = 1
                  created_by = sy-uname  created_at = lv_now
                  changed_by = sy-uname  changed_at = lv_now ) ).
              WHEN 'X'.
                DELETE FROM zfilimitconf WHERE item_id =
  @<fl>-source_item_id.
            ENDCASE.
          ENDLOOP.
          UPDATE zfilimitreq SET
            line_status = @gc_st_active, changed_by = @sy-uname, changed_at
  = @lv_now
          WHERE req_id = @<r>-ReqId.
        ENDIF.

        " ── Audit Log ──
        TRY.
            zcl_gsp26_rule_writer=>log_audit_entry(
              iv_conf_id  = <r>-ConfId  iv_req_id = <r>-ReqId
              iv_mod_id   = <r>-ModuleId  iv_act_type = 'APPLY'
              iv_tab_name = 'ZCONFREQH'  iv_env_id = <r>-EnvId
              is_new_data = VALUE #( BASE <r> Status = gc_st_active ) ).
          CATCH cx_root INTO DATA(lx_audit_apply).
            APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
              severity = if_abap_behv_message=>severity-warning
              text = |Audit log failed: { lx_audit_apply->get_text( ) }| ) )
   TO reported-req.
        ENDTRY.

        " ── Cập nhật status → ACTIVE ──
        MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
          ENTITY Req UPDATE FIELDS ( Status ChangedBy ChangedAt )
          WITH VALUE #( ( %tky = <r>-%tky
            Status = gc_st_active  ChangedBy = sy-uname  ChangedAt = lv_now
  ) ).
      ENDLOOP.

      READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT
  DATA(lt_final).
    result = VALUE #( FOR ls_final IN lt_final ( %tky = ls_final-%tky
    %param = ls_final ) ).
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
      " NOTE: ZI_MM_ROUTE_CONF dùng delta model — frontend chỉ ghi các dòng
      " thực sự thay đổi vào zmmrouteconf_req, không snapshot toàn bộ.
      CASE ls_key-%param-TargetCds.

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
              line_status    = gc_st_draft
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
              line_status       = gc_st_draft
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
              line_status       = gc_st_draft
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


  METHOD updateReason.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    LOOP AT keys INTO DATA(ls_key).
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Reason ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky      = ls_key-%tky
          Reason    = ls_key-%param-reason
          ChangedBy = sy-uname
          ChangedAt = lv_now
        ) ).
    ENDLOOP.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.


ENDCLASS.

CLASS lhc_Item DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS validate_item FOR VALIDATE ON SAVE IMPORTING keys FOR Item~validate_item.
ENDCLASS.

CLASS lhc_Item IMPLEMENTATION.
  METHOD validate_item.
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Item ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_items).

    LOOP AT lt_items ASSIGNING FIELD-SYMBOL(<i>).

      IF <i>-ConfId IS INITIAL.
        APPEND VALUE #(
          %tky = <i>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'ConfId is mandatory' )
        ) TO reported-item.
        APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
      ENDIF.

      IF <i>-Action IS INITIAL.
        APPEND VALUE #(
          %tky = <i>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Action is mandatory' )
        ) TO reported-item.
        APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
      ENDIF.

      IF <i>-TargetEnvId IS INITIAL.
        APPEND VALUE #(
          %tky = <i>-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'TargetEnvId is mandatory' )
        ) TO reported-item.
        APPEND VALUE #( %tky = <i>-%tky ) TO failed-item.
      ENDIF.

    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
