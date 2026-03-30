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
    " 1. Đọc trạng thái (Status) hiện tại của các Yêu cầu (Request) đang hiển thị trên UI
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req FIELDS ( Status ) WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    " 2. Gán Rule Đóng/Mở các action (Enable/Disable nút) tùy thuộc vào Status
    LOOP AT lt_reqs INTO DATA(ls_req).

      " Khởi tạo: Mặc định khoá xám xịt (Disabled) toàn bộ các nút
      " CHÚ Ý CÓ DẤU CÁCH TRƯỚC VÀ SAU DẤU BẰNG
      DATA(lv_approve)  = if_abap_behv=>fc-o-disabled.
      DATA(lv_reject)   = if_abap_behv=>fc-o-disabled.
      DATA(lv_submit)   = if_abap_behv=>fc-o-disabled.
      DATA(lv_promote)  = if_abap_behv=>fc-o-disabled.
      DATA(lv_apply)    = if_abap_behv=>fc-o-disabled.
      DATA(lv_rollback) = if_abap_behv=>fc-o-disabled.

      " Kiểm tra trạng thái hiện tại để mở khoá (Enable) nút tương ứng
      CASE condense( ls_req-Status ).

        WHEN gc_st_draft OR gc_st_rolled_back.
          lv_submit  = if_abap_behv=>fc-o-enabled.

        WHEN gc_st_submitted.
          lv_approve = if_abap_behv=>fc-o-enabled.
          lv_reject  = if_abap_behv=>fc-o-enabled.

        WHEN gc_st_approved.
          lv_promote  = if_abap_behv=>fc-o-enabled.
          lv_apply    = if_abap_behv=>fc-o-enabled.
          lv_rollback = if_abap_behv=>fc-o-enabled.

        WHEN gc_st_active.
          lv_promote  = if_abap_behv=>fc-o-enabled.
          lv_rollback = if_abap_behv=>fc-o-enabled.

        WHEN gc_st_rejected.
          " Trống, mặc định tất cả action đều bị disable

      ENDCASE.

      " 3. Trả về cho UI5 Fiori kết quả đóng/mở cụ thể
      APPEND VALUE #( %tky             = ls_req-%tky
                      %action-approve  = lv_approve
                      %action-reject   = lv_reject
                      %action-submit   = lv_submit
                      %action-promote  = lv_promote
                      %action-apply    = lv_apply
                      %action-rollback = lv_rollback
                    ) TO result.

    ENDLOOP.
  ENDMETHOD.



  METHOD approve.
    DATA: lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    " Hằng số môi trường (Ép cứng ghi xuống DEV)
    CONSTANTS: lc_env_dev TYPE string VALUE 'DEV'.

    " Mảng chứa toàn bộ Log (Header + Items) để Insert 1 lần duy nhất
    DATA: lt_audit_log     TYPE STANDARD TABLE OF zauditlog,
          ls_audit_log     TYPE zauditlog,
          lv_record_exists TYPE abap_boolean. " Khai báo biến check tồn tại 1 lần duy nhất

    " Khai báo biến cho Push Notification
    DATA: lt_notifications TYPE /iwngw/if_notif_provider=>ty_t_notification,
          ls_notification  TYPE /iwngw/if_notif_provider=>ty_s_notification,
          lt_recipients    TYPE /iwngw/if_notif_provider=>ty_t_notification_recipient,
          ls_recipient     TYPE /iwngw/if_notif_provider=>ty_s_notification_recipient.

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

      " 4. Gọi Validator
      LOOP AT lt_curr_items INTO DATA(ls_item).
        DATA(lt_val_errors) = zcl_gsp26_rule_validator=>validate_request_item(
                                iv_conf_id       = ls_item-ConfId
                                iv_action        = ls_item-Action
                                iv_target_env_id = CONV #( lc_env_dev ) ). " Truyền DEV vào validator
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

      " -------------------------------------------------------------
      " 5. GHI LOG CHO HEADER VÀO INTERNAL TABLE
      " -------------------------------------------------------------
      ls_audit_log-client      = sy-mandt.
      TRY.
          ls_audit_log-log_id  = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
          " Bỏ qua nếu lỗi sinh UUID
      ENDTRY.
      ls_audit_log-req_id      = <r>-ReqId.
      ls_audit_log-conf_id     = VALUE #( lt_curr_items[ 1 ]-ConfId OPTIONAL ).
      ls_audit_log-module_id   = <r>-ModuleId.
      ls_audit_log-action_type = 'APPROVE'.
      ls_audit_log-table_name  = 'ZCONFREQH'.
      ls_audit_log-env_id      = lc_env_dev. " Ép môi trường DEV
      ls_audit_log-old_data    = |\{"REQTITLE":"","STATUS":""\}|.
      ls_audit_log-new_data    = |\{"REQTITLE":"{ <r>-ReqTitle }","STATUS":"{ gc_st_approved }"\}|.
      ls_audit_log-changed_by  = sy-uname.
      ls_audit_log-changed_at  = lv_now.
      APPEND ls_audit_log TO lt_audit_log.
      CLEAR ls_audit_log.

      " 6. Cập nhật trạng thái APPROVED cho Request Header
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ApprovedBy ApprovedAt )
        WITH VALUE #( ( %tky = <r>-%tky Status = gc_st_approved ApprovedBy = sy-uname ApprovedAt = lv_now ) ).

      DATA(lt_ver_results) = zcl_gsp26_rule_snapshot=>increment_version( iv_req_id = <r>-ReqId ).


      " -------------------------------------------------------------
      " ── WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zmmsafestock_req ──
      " -------------------------------------------------------------
      SELECT * FROM zmmsafestock_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_ss_req).
      IF lt_ss_req IS NOT INITIAL.
        LOOP AT lt_ss_req ASSIGNING FIELD-SYMBOL(<ss>).

          ls_audit_log-client      = sy-mandt.
          TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
          ls_audit_log-req_id      = <r>-ReqId.
          ls_audit_log-conf_id     = <ss>-conf_id.
          ls_audit_log-module_id   = 'MM'.
          ls_audit_log-action_type = 'APPROVE'.
          ls_audit_log-table_name  = 'Z_MM_SAFE_STOCK'.
          ls_audit_log-env_id      = lc_env_dev.
          ls_audit_log-object_key  = <ss>-item_id.
          ls_audit_log-old_data    = |\{"PLANT_ID":"{ <ss>-old_plant_id }","MAT_GROUP":"{ <ss>-old_mat_group }","MIN_QTY":"{ <ss>-old_min_qty }"\}|.
          ls_audit_log-new_data    = |\{"PLANT_ID":"{ <ss>-plant_id }","MAT_GROUP":"{ <ss>-mat_group }","MIN_QTY":"{ <ss>-min_qty }"\}|.
          ls_audit_log-changed_by  = sy-uname.
          ls_audit_log-changed_at  = lv_now.
          APPEND ls_audit_log TO lt_audit_log.
          CLEAR ls_audit_log.

          CLEAR lv_record_exists.
          CASE <ss>-action_type.
            WHEN 'UPDATE'.
              SELECT SINGLE @abap_true FROM zmmsafestock WHERE item_id = @<ss>-source_item_id INTO @lv_record_exists.
              IF lv_record_exists = abap_true.
                UPDATE zmmsafestock SET
                  env_id     = @lc_env_dev, " Ép ghi xuống DEV
                  plant_id   = @<ss>-plant_id,
                  mat_group  = @<ss>-mat_group,
                  min_qty    = @<ss>-min_qty,
                  version_no = @<ss>-version_no,
                  req_id     = @<r>-ReqId,
                  changed_by = @sy-uname,
                  changed_at = @lv_now
                WHERE item_id = @<ss>-source_item_id.
              ENDIF.
            WHEN 'CREATE'.
              INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                client     = sy-mandt
                item_id    = <ss>-item_id
                req_id     = <r>-ReqId
                env_id     = lc_env_dev " Ép ghi xuống DEV
                plant_id   = <ss>-plant_id
                mat_group  = <ss>-mat_group
                min_qty    = <ss>-min_qty
                version_no = 1
                created_at = lv_now
                changed_by = sy-uname
                changed_at = lv_now ) ).
            WHEN 'DELETE'.
              DELETE FROM zmmsafestock WHERE item_id = @<ss>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zmmsafestock_req SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
      ENDIF.


      " -------------------------------------------------------------
      " ── WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zmmrouteconf_req ──
      " -------------------------------------------------------------
      SELECT * FROM zmmrouteconf_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_route_req).
      IF lt_route_req IS NOT INITIAL.
        LOOP AT lt_route_req ASSIGNING FIELD-SYMBOL(<rt>).

          ls_audit_log-client      = sy-mandt.
          TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
          ls_audit_log-req_id      = <r>-ReqId.
          ls_audit_log-conf_id     = <rt>-conf_id.
          ls_audit_log-module_id   = 'MM'.
          ls_audit_log-action_type = 'APPROVE'.
          ls_audit_log-table_name  = 'Z_MM_ROUTE_CONF'.
          ls_audit_log-env_id      = lc_env_dev.
          ls_audit_log-object_key  = <rt>-item_id.
          ls_audit_log-old_data    = |\{"PLANT_ID":"{ <rt>-old_plant_id }","SEND_WH":"{ <rt>-old_send_wh }","RECEIVE_WH":"{ <rt>-old_receive_wh }","TRANS_MODE":"{ <rt>-old_trans_mode }"\}|.
          ls_audit_log-new_data    = |\{"PLANT_ID":"{ <rt>-plant_id }","SEND_WH":"{ <rt>-send_wh }","RECEIVE_WH":"{ <rt>-receive_wh }","TRANS_MODE":"{ <rt>-trans_mode }"\}|.
          ls_audit_log-changed_by  = sy-uname.
          ls_audit_log-changed_at  = lv_now.
          APPEND ls_audit_log TO lt_audit_log.
          CLEAR ls_audit_log.

          CLEAR lv_record_exists.
          CASE <rt>-action_type.
            WHEN 'U'.
              SELECT SINGLE @abap_true FROM zmmrouteconf WHERE item_id = @<rt>-source_item_id INTO @lv_record_exists.
              IF lv_record_exists = abap_true.
                UPDATE zmmrouteconf SET
                  env_id       = @lc_env_dev,
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
                env_id       = lc_env_dev
                plant_id     = <rt>-plant_id
                send_wh      = <rt>-send_wh
                receive_wh   = <rt>-receive_wh
                trans_mode   = <rt>-trans_mode
                is_allowed   = <rt>-is_allowed
                version_no   = 1
                created_at   = lv_now
                changed_by   = sy-uname
                changed_at   = lv_now ) ).
            WHEN 'X'.
              DELETE FROM zmmrouteconf WHERE item_id = @<rt>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zmmrouteconf_req SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
      ENDIF.


      " -------------------------------------------------------------
      " ── WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zfilimitreq ──
      " -------------------------------------------------------------
      SELECT * FROM zfilimitreq WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_fi_req).
      IF lt_fi_req IS NOT INITIAL.
        LOOP AT lt_fi_req ASSIGNING FIELD-SYMBOL(<fi>).

          ls_audit_log-client      = sy-mandt.
          TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
          ls_audit_log-req_id      = <r>-ReqId.
          ls_audit_log-conf_id     = <fi>-conf_id.
          ls_audit_log-module_id   = 'FI'.
          ls_audit_log-action_type = 'APPROVE'.
          ls_audit_log-table_name  = 'Z_FI_LIMIT_CONF'.
          ls_audit_log-env_id      = lc_env_dev.
          ls_audit_log-object_key  = <fi>-item_id.
          ls_audit_log-old_data    = |\{"EXPENSE_TYPE":"{ <fi>-old_expense_type }","GL_ACCOUNT":"{ <fi>-old_gl_account }","AUTO_APPR_LIM":"{ <fi>-old_auto_appr_lim }","CURRENCY":"{ <fi>-old_currency }"\}|.
          ls_audit_log-new_data    = |\{"EXPENSE_TYPE":"{ <fi>-expense_type }","GL_ACCOUNT":"{ <fi>-gl_account }","AUTO_APPR_LIM":"{ <fi>-auto_appr_lim }","CURRENCY":"{ <fi>-currency }"\}|.
          ls_audit_log-changed_by  = sy-uname.
          ls_audit_log-changed_at  = lv_now.
          APPEND ls_audit_log TO lt_audit_log.
          CLEAR ls_audit_log.

          CLEAR lv_record_exists.
           CASE <fi>-action_type.
              WHEN 'UPDATE' OR 'U'.
              SELECT SINGLE @abap_true FROM zfilimitconf WHERE item_id = @<fi>-source_item_id INTO @lv_record_exists.
              IF lv_record_exists = abap_true.
                UPDATE zfilimitconf SET
                  env_id        = @lc_env_dev,
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
        WHEN 'CREATE' OR 'C'.
                INSERT zfilimitconf FROM @( VALUE zfilimitconf(
                client        = sy-mandt
                item_id       = <fi>-item_id
                req_id        = <r>-ReqId
                env_id        = lc_env_dev
                expense_type  = <fi>-expense_type
                gl_account    = <fi>-gl_account
                auto_appr_lim = <fi>-auto_appr_lim
                currency      = <fi>-currency
                version_no    = 1
                created_at    = lv_now
                changed_by    = sy-uname
                changed_at    = lv_now ) ).
             WHEN 'DELETE' OR 'X'.
                DELETE FROM zfilimitconf WHERE item_id = @<fi>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zfilimitreq SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
      ENDIF.


      " -------------------------------------------------------------
      " ── WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zsd_price_req ──
      " -------------------------------------------------------------
      SELECT * FROM zsd_price_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_sd_req).
      IF lt_sd_req IS NOT INITIAL.
        LOOP AT lt_sd_req ASSIGNING FIELD-SYMBOL(<sd>).

          ls_audit_log-client      = sy-mandt.
          TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
          ls_audit_log-req_id      = <r>-ReqId.
          ls_audit_log-conf_id     = <sd>-conf_id.
          ls_audit_log-module_id   = 'SD'.
          ls_audit_log-action_type = 'APPROVE'.
          ls_audit_log-table_name  = 'Z_SD_PRICE_CONF'.
          ls_audit_log-env_id      = lc_env_dev.
          ls_audit_log-object_key  = <sd>-item_id.
          ls_audit_log-old_data    = |\{"BRANCH_ID":"{ <sd>-old_branch_id }","CUST_GROUP":"{ <sd>-old_cust_group }","MATERIAL_GRP":"{ <sd>-old_material_grp }","MAX_DISCOUNT":"{ <sd>-old_max_discount }","MIN_ORDER_VAL":"{ <sd>-old_min_order_val }"\}|.
          ls_audit_log-new_data    = |\{"BRANCH_ID":"{ <sd>-branch_id }","CUST_GROUP":"{ <sd>-cust_group }","MATERIAL_GRP":"{ <sd>-material_grp }","MAX_DISCOUNT":"{ <sd>-max_discount }","MIN_ORDER_VAL":"{ <sd>-min_order_val }"\}|.
          ls_audit_log-changed_by  = sy-uname.
          ls_audit_log-changed_at  = lv_now.
          APPEND ls_audit_log TO lt_audit_log.
          CLEAR ls_audit_log.

          CLEAR lv_record_exists.
          CASE <sd>-action_type.
            WHEN 'UPDATE'.
              SELECT SINGLE @abap_true FROM zsd_price_conf WHERE item_id = @<sd>-source_item_id INTO @lv_record_exists.
              IF lv_record_exists = abap_true.
                UPDATE zsd_price_conf SET
                  env_id        = @lc_env_dev,
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
            WHEN 'CREATE'.
              INSERT zsd_price_conf FROM @( VALUE zsd_price_conf(
                client        = sy-mandt
                item_id       = <sd>-item_id
                req_id        = <r>-ReqId
                env_id        = lc_env_dev
                branch_id     = <sd>-branch_id
                cust_group    = <sd>-cust_group
                material_grp  = <sd>-material_grp
                max_discount  = <sd>-max_discount
                min_order_val = <sd>-min_order_val
                currency      = <sd>-currency
                valid_from    = <sd>-valid_from
                valid_to      = <sd>-valid_to
                version_no    = 1
                created_at    = lv_now
                changed_by    = sy-uname
                changed_at    = lv_now ) ).
            WHEN 'DELETE'.
              DELETE FROM zsd_price_conf WHERE item_id = @<sd>-source_item_id.
          ENDCASE.
        ENDLOOP.
        UPDATE zsd_price_req SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
      ENDIF.

      " =============================================================
      " 🚀 PUSH NOTIFICATION: THÔNG BÁO CHO NGƯỜI TẠO REQUEST
      " =============================================================
      CLEAR: lt_notifications, lt_recipients, ls_notification, ls_recipient.

      " 1. Xác định Người Nhận (Gửi ngược lại cho người tạo phiếu)
      ls_recipient-id = <r>-CreatedBy.
      APPEND ls_recipient TO lt_recipients.

      " 2. Khởi tạo dữ liệu Thông báo
      TRY.
          ls_notification-id = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
      ENDTRY.

      ls_notification-type_key     = 'REQ_APPROVED'. " Khớp với Type ID định nghĩa trong Class Provider
      ls_notification-type_version = '1'.
      ls_notification-priority     = /iwngw/if_notif_provider=>gcs_priorities-low.
      ls_notification-recipients   = lt_recipients.

      " 3. Truyền giá trị cho biến {ReqTitle}
      " SỬA LỖI: Cấu trúc parameters phải lồng thêm khai báo ngôn ngữ (language)
      ls_notification-parameters = VALUE #(
        ( language = sy-langu
          parameters = VALUE #(
            ( name = 'ReqTitle' value = CONV #( <r>-ReqTitle ) type = 'Edm.String' )
          )
        )
      ).

      " 4. Navigation (Click vào quả chuông mở App)
      " LƯU Ý: Đảm bảo SemanticObject và Action khớp với manifest.json của App Manager
      ls_notification-navigation_parameters = VALUE #(
        ( name = 'SemanticObject' value = 'ConfigReq' )
        ( name = 'Action'         value = 'manage' )
        ( name = 'ReqId'          value = CONV #( <r>-ReqId ) )
      ).

      APPEND ls_notification TO lt_notifications.

      " 5. BÓP CÒ BẮN THÔNG BÁO!
      TRY.
          /iwngw/cl_notification_api=>create_notifications(
            EXPORTING
              iv_provider_id  = 'ZGSP26SAP06_REQ_NOTIF' " Đúng cái ID bạn vừa Active
              it_notification = lt_notifications
          ).
        CATCH /iwngw/cx_notification_api INTO DATA(lx_notif_error).
          " Bắt lỗi ngầm để nếu lỗi Gateway cũng không làm hỏng tiến trình Approve
      ENDTRY.
      " =============================================================

    ENDLOOP.

    " 7. INSERT TOÀN BỘ LOG XUỐNG DỮ LIỆU CHỈ TRONG 1 LẦN DUY NHẤT
    IF lt_audit_log IS NOT INITIAL.
      INSERT zauditlog FROM TABLE @lt_audit_log.
    ENDIF.

    " 8. Đọc lại để trả về %param
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

      " Chấp nhận cả APPROVED và ACTIVE
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



      INSERT zconfreqh FROM @( VALUE zconfreqh(
        client      = sy-mandt
        req_id      = <r>-ReqId
        conf_id     = <r>-ConfId
        env_id      = lv_next_env
        module_id   = <r>-ModuleId
        req_title   = <r>-ReqTitle
        description = <r>-Description
        status      = gc_st_active
        reason      = <r>-Reason
        created_by  = sy-uname
        created_at  = lv_now
        changed_by  = sy-uname
        changed_at  = lv_now
        approved_by = <r>-ApprovedBy
        approved_at = <r>-ApprovedAt ) ).

      " ── Copy MM SafeStock: luôn INSERT mới, chỉ đổi env_id và req_id ──
      SELECT * FROM zmmsafestock
        WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
        INTO TABLE @DATA(lt_ss).
      LOOP AT lt_ss ASSIGNING FIELD-SYMBOL(<ss>).
        INSERT zmmsafestock FROM @( VALUE zmmsafestock(
          client     = sy-mandt
          item_id    = cl_system_uuid=>create_uuid_x16_static( )
          req_id     = <r>-ReqId
          env_id     = lv_next_env
          plant_id   = <ss>-plant_id
          mat_group  = <ss>-mat_group
          min_qty    = <ss>-min_qty
          version_no = 1
          created_by = sy-uname  created_at = lv_now
          changed_by = sy-uname  changed_at = lv_now ) ).
      ENDLOOP.

      " ── Copy MM Route: luôn INSERT mới, chỉ đổi env_id và req_id ──
      SELECT * FROM zmmrouteconf
        WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
        INTO TABLE @DATA(lt_rt).
      LOOP AT lt_rt ASSIGNING FIELD-SYMBOL(<rt>).
        INSERT zmmrouteconf FROM @( VALUE zmmrouteconf(
          client       = sy-mandt
          item_id      = cl_system_uuid=>create_uuid_x16_static( )
          req_id       = <r>-ReqId
          env_id       = lv_next_env
          plant_id     = <rt>-plant_id
          send_wh      = <rt>-send_wh
          receive_wh   = <rt>-receive_wh
          inspector_id = <rt>-inspector_id
          trans_mode   = <rt>-trans_mode
          is_allowed   = <rt>-is_allowed
          version_no   = 1
          created_by   = sy-uname  created_at = lv_now
          changed_by   = sy-uname  changed_at = lv_now ) ).
      ENDLOOP.

      " ── Copy FI Limit: luôn INSERT mới, chỉ đổi env_id và req_id ──
      SELECT * FROM zfilimitconf
        WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
        INTO TABLE @DATA(lt_fi).
      LOOP AT lt_fi ASSIGNING FIELD-SYMBOL(<fi>).
        INSERT zfilimitconf FROM @( VALUE zfilimitconf(
          client        = sy-mandt
          item_id       = cl_system_uuid=>create_uuid_x16_static( )
          req_id        = <r>-ReqId
          env_id        = lv_next_env
          expense_type  = <fi>-expense_type
          gl_account    = <fi>-gl_account
          auto_appr_lim = <fi>-auto_appr_lim
          currency      = <fi>-currency
          version_no    = 1
          created_by    = sy-uname  created_at = lv_now
          changed_by    = sy-uname  changed_at = lv_now ) ).
      ENDLOOP.

      " ── Copy SD Price: luôn INSERT mới, chỉ đổi env_id và req_id ──
      SELECT * FROM zsd_price_conf
        WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
        INTO TABLE @DATA(lt_sd).
      LOOP AT lt_sd ASSIGNING FIELD-SYMBOL(<sd>).
        INSERT zsd_price_conf FROM @( VALUE zsd_price_conf(
          client        = sy-mandt
          item_id       = cl_system_uuid=>create_uuid_x16_static( )
          req_id        = <r>-ReqId
          env_id        = lv_next_env
          branch_id     = <sd>-branch_id
          cust_group    = <sd>-cust_group
          material_grp  = <sd>-material_grp
          max_discount  = <sd>-max_discount
          min_order_val = <sd>-min_order_val
          currency      = <sd>-currency
          valid_from    = <sd>-valid_from
          valid_to      = <sd>-valid_to
          version_no    = 1
          created_by    = sy-uname  created_at = lv_now
          changed_by    = sy-uname  changed_at = lv_now ) ).
      ENDLOOP.

      " ── Audit log ──
      TRY.
          DATA(ls_new_hdr) = VALUE zconfreqh(
            req_id      = <r>-ReqId
            env_id      = lv_next_env
            status      = gc_st_active
            module_id   = <r>-ModuleId
            req_title   = <r>-ReqTitle ).

          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = <r>-ConfId
            iv_req_id   = <r>-ReqId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'PROMOTE'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = lv_next_env
            is_new_data = VALUE #( BASE <r> Status = gc_st_active
                                   EnvId  = lv_next_env ) ).
        CATCH cx_root INTO DATA(lx_audit).
          APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-warning
            text = |Audit log skipped: { lx_audit->get_text( ) }| ) ) TO reported-req.
      ENDTRY.

      " ── Header gốc: giữ nguyên env_id, chỉ set Status = ACTIVE ──
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ChangedBy ChangedAt )
        WITH VALUE #( ( %tky      = <r>-%tky
                        Status    = gc_st_active
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
            WHEN 'UPDATE'.
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
            WHEN 'CREATE'.
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
            WHEN 'DELETE'.
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
            WHEN 'UPDATE'.
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
            WHEN 'CREATE' OR 'C'.
                INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                client = sy-mandt  item_id = <ss>-item_id  req_id =
<r>-ReqId
                env_id = <ss>-env_id  plant_id = <ss>-plant_id
                mat_group = <ss>-mat_group  min_qty = <ss>-min_qty
                version_no = 1  created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
             WHEN 'DELETE' OR 'X'.
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
            WHEN 'UPDATE'.
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
            WHEN 'CREATE'.
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
            WHEN 'DELETE'.
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
            WHEN 'UPDATE'.
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
            WHEN 'CREATE'.
              INSERT zfilimitconf FROM @( VALUE zfilimitconf(
                client = sy-mandt  item_id = <fl>-item_id  req_id =
<r>-ReqId
                env_id = <fl>-env_id  expense_type = <fl>-expense_type
                gl_account = <fl>-gl_account  auto_appr_lim =
<fl>-auto_appr_lim
                currency = <fl>-currency  version_no = 1
                created_by = sy-uname  created_at = lv_now
                changed_by = sy-uname  changed_at = lv_now ) ).
            WHEN 'DELETE'.
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

    IF keys IS INITIAL. RETURN. ENDIF.

    LOOP AT keys INTO DATA(ls_key).

      CLEAR: lv_now, lv_conf_id_x16, lv_uuid_c36, lv_env,
             lv_req_id_x16, lv_req_item_id_x16, lv_req_id_c36,
             lv_target_app, lv_conf_id_c36.

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
