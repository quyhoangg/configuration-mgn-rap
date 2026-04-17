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
        " 1. Kiểm tra từng role riêng biệt — ZUSERROLE có compound key (USER_ID + MODULE_ID)
        "    nên SELECT SINGLE không MODULE_ID sẽ trả về row bất kỳ → BUG.
        "    Thay bằng: check EXISTS cho từng role level.
        DATA: lv_has_manager TYPE abap_bool,
              lv_has_itadmin TYPE abap_bool,
              lv_has_keyuser TYPE abap_bool.

        SELECT SINGLE @abap_true FROM zuserrole
          WHERE user_id   = @sy-uname
            AND role_level = @gc_role_manager
            AND is_active  = @abap_true
          INTO @lv_has_manager.

        SELECT SINGLE @abap_true FROM zuserrole
          WHERE user_id   = @sy-uname
            AND role_level = @gc_role_itadmin
            AND is_active  = @abap_true
          INTO @lv_has_itadmin.

        SELECT SINGLE @abap_true FROM zuserrole
          WHERE user_id   = @sy-uname
            AND role_level = @gc_role_keyuser
            AND is_active  = @abap_true
          INTO @lv_has_keyuser.

        " 2. Đọc các record đang xử lý
        READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
          ENTITY Req FIELDS ( Status ) WITH CORRESPONDING #( keys )
          RESULT DATA(lt_reqs).

        " 3. Map phân quyền theo role:
        "    auth-unauthorized → NÚT ẨN HOÀN TOÀN trên UI
        "    auth-allowed      → nút hiện (visibility do features kiểm soát tiếp)

        " Mọi user có bất kỳ role nào đều được submit
        DATA(lv_auth_submit) = COND #(
          WHEN lv_has_manager = abap_true OR lv_has_itadmin = abap_true OR lv_has_keyuser = abap_true
          THEN if_abap_behv=>auth-allowed
          ELSE if_abap_behv=>auth-unauthorized ).

        " Chỉ MANAGER thấy Approve / Reject
        DATA(lv_auth_manager) = COND #(
          WHEN lv_has_manager = abap_true
          THEN if_abap_behv=>auth-allowed
          ELSE if_abap_behv=>auth-unauthorized ).

        " Chỉ IT ADMIN thấy Promote / Rollback / Apply
        DATA(lv_auth_itadmin) = COND #(
          WHEN lv_has_itadmin = abap_true
          THEN if_abap_behv=>auth-allowed
          ELSE if_abap_behv=>auth-unauthorized ).

        " Edit (draft) và Delete chỉ KEY USER và MANAGER thấy
        " (IT ADMIN không cần tạo/xóa request)
        DATA(lv_auth_edit_del) = COND #(
          WHEN lv_has_keyuser = abap_true OR lv_has_manager = abap_true
          THEN if_abap_behv=>auth-allowed
          ELSE if_abap_behv=>auth-unauthorized ).

        " 4. Áp dụng kết quả cho từng Item
        LOOP AT lt_reqs INTO DATA(ls_req).
          APPEND VALUE #( %tky                 = ls_req-%tky
                          %update              = lv_auth_edit_del
                          %delete              = lv_auth_edit_del
                          %action-Edit         = lv_auth_edit_del
                          %action-submit       = lv_auth_submit
                          %action-approve      = lv_auth_manager
                          %action-reject       = lv_auth_manager
                          %action-updatereason = lv_auth_submit
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
          DATA(lv_update)   = if_abap_behv=>fc-o-disabled.
          DATA(lv_delete)   = if_abap_behv=>fc-o-disabled.

          " Kiểm tra trạng thái hiện tại để mở khoá (Enable) nút tương ứng
          CASE condense( ls_req-Status ).

            WHEN gc_st_draft OR gc_st_rolled_back.
              lv_submit  = if_abap_behv=>fc-o-enabled.
              lv_update  = if_abap_behv=>fc-o-enabled.
              lv_delete  = if_abap_behv=>fc-o-enabled.

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
              " Trống, mặc định tất cả action đều bị disable (kể cả edit/delete)

          ENDCASE.

          " 3. Trả về cho UI5 Fiori kết quả đóng/mở cụ thể
          APPEND VALUE #( %tky             = ls_req-%tky
                          %update          = lv_update
                          %delete          = lv_delete
                          %action-Edit     = lv_update
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
              lv_record_exists TYPE abap_boolean, " Khai báo biến check tồn tại 1 lần duy nhất
              lv_new_version   TYPE i.

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

          " =============================================================
          " Phase 2: PRE-WRITE VALIDATIONS (before any DB change)
          " Covers: required fields, duplicate business key in DEV,
          "         duplicate within same request, orphaned source_item_id
          " =============================================================

          " MMSS
          SELECT * FROM zmmsafestock_req
            WHERE req_id = @<r>-ReqId
            INTO TABLE @DATA(lt_ss_pre).

          DATA lt_ss_bkeys TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
          CLEAR lt_ss_bkeys.

          LOOP AT lt_ss_pre INTO DATA(ls_ss_pre).
            DATA(lv_ss_bkey) = |{ ls_ss_pre-plant_id }\|{ ls_ss_pre-mat_group }|.

            CASE ls_ss_pre-action_type.
              WHEN 'C' OR 'CREATE'.
                " 1. Required fields
                IF ls_ss_pre-plant_id IS INITIAL OR ls_ss_pre-mat_group IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MMSS CREATE: PlantId and MatGroup are required| ) ) TO reported-req.
                ENDIF.
                " 2. Duplicate within same request
                READ TABLE lt_ss_bkeys WITH KEY table_line = lv_ss_bkey TRANSPORTING NO FIELDS.
                IF sy-subrc = 0.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MMSS CREATE: Duplicate key Plant={ ls_ss_pre-plant_id } MatGrp={ ls_ss_pre-mat_group } in same request| ) ) TO reported-req.
                ELSE.
                  APPEND lv_ss_bkey TO lt_ss_bkeys.
                ENDIF.
                " 3. Already exists in DEV main table
                SELECT SINGLE @abap_true FROM zmmsafestock
                  WHERE env_id    = @lc_env_dev
                    AND plant_id  = @ls_ss_pre-plant_id
                    AND mat_group = @ls_ss_pre-mat_group
                  INTO @DATA(lv_ss_dup).
                IF lv_ss_dup = abap_true.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MMSS CREATE: Config Plant={ ls_ss_pre-plant_id } MatGrp={ ls_ss_pre-mat_group } already exists in DEV| ) ) TO reported-req.
                ENDIF.
              WHEN 'U' OR 'UPDATE' OR 'X' OR 'DELETE'.
                " 4. source_item_id must exist
                IF ls_ss_pre-source_item_id IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MMSS { ls_ss_pre-action_type }: source_item_id missing| ) ) TO reported-req.
                ELSE.
                  SELECT SINGLE @abap_true FROM zmmsafestock
                    WHERE item_id = @ls_ss_pre-source_item_id
                    INTO @DATA(lv_ss_src).
                  IF lv_ss_src <> abap_true.
                    lv_has_error = abap_true.
                    APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                      severity = if_abap_behv_message=>severity-error
                      text     = |MMSS { ls_ss_pre-action_type }: source row not found in DEV (may have been deleted)| ) ) TO reported-req.
                  ENDIF.
                ENDIF.
            ENDCASE.
          ENDLOOP.

          " MM Routes
          SELECT * FROM zmmrouteconf_req
            WHERE req_id = @<r>-ReqId
            INTO TABLE @DATA(lt_rt_pre).

          DATA lt_rt_bkeys TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
          CLEAR lt_rt_bkeys.

          LOOP AT lt_rt_pre INTO DATA(ls_rt_pre).
            DATA(lv_rt_bkey) = |{ ls_rt_pre-plant_id }\|{ ls_rt_pre-send_wh }\|{ ls_rt_pre-receive_wh }|.

            CASE ls_rt_pre-action_type.
              WHEN 'C' OR 'CREATE'.
                " 1. Required fields
                IF ls_rt_pre-plant_id IS INITIAL OR ls_rt_pre-send_wh IS INITIAL OR ls_rt_pre-receive_wh IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MM Route CREATE: PlantId, SendWh, ReceiveWh are required| ) ) TO reported-req.
                ENDIF.
                " 2. Duplicate within same request
                READ TABLE lt_rt_bkeys WITH KEY table_line = lv_rt_bkey TRANSPORTING NO FIELDS.
                IF sy-subrc = 0.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MM Route CREATE: Duplicate key Plant={ ls_rt_pre-plant_id } SendWh={ ls_rt_pre-send_wh } RecvWh={ ls_rt_pre-receive_wh } in same request| ) ) TO reported-req.
                ELSE.
                  APPEND lv_rt_bkey TO lt_rt_bkeys.
                ENDIF.
                " 3. Already exists in DEV main table
                SELECT SINGLE @abap_true FROM zmmrouteconf
                  WHERE env_id     = @lc_env_dev
                    AND plant_id   = @ls_rt_pre-plant_id
                    AND send_wh    = @ls_rt_pre-send_wh
                    AND receive_wh = @ls_rt_pre-receive_wh
                  INTO @DATA(lv_rt_dup).
                IF lv_rt_dup = abap_true.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MM Route CREATE: Route Plant={ ls_rt_pre-plant_id } SendWh={ ls_rt_pre-send_wh } RecvWh={ ls_rt_pre-receive_wh } already exists in DEV| ) ) TO reported-req.
                ENDIF.
              WHEN 'U' OR 'X'.
                " 4. source_item_id must exist
                IF ls_rt_pre-source_item_id IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |MM Route { ls_rt_pre-action_type }: source_item_id missing| ) ) TO reported-req.
                ELSE.
                  SELECT SINGLE @abap_true FROM zmmrouteconf
                    WHERE item_id = @ls_rt_pre-source_item_id
                    INTO @DATA(lv_rt_src).
                  IF lv_rt_src <> abap_true.
                    lv_has_error = abap_true.
                    APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                      severity = if_abap_behv_message=>severity-error
                      text     = |MM Route { ls_rt_pre-action_type }: source row not found in DEV (may have been deleted)| ) ) TO reported-req.
                  ENDIF.
                ENDIF.
            ENDCASE.
          ENDLOOP.

          " FI Limit
          SELECT * FROM zfilimitreq
            WHERE req_id = @<r>-ReqId
            INTO TABLE @DATA(lt_fi_pre).

          DATA lt_fi_bkeys TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
          CLEAR lt_fi_bkeys.

          LOOP AT lt_fi_pre INTO DATA(ls_fi_pre).
            DATA(lv_fi_bkey) = |{ ls_fi_pre-expense_type }\|{ ls_fi_pre-gl_account }|.

            CASE ls_fi_pre-action_type.
              WHEN 'C' OR 'CREATE'.
                " 1. Required fields
                IF ls_fi_pre-expense_type IS INITIAL OR ls_fi_pre-gl_account IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |FI Limit CREATE: ExpenseType and GlAccount are required| ) ) TO reported-req.
                ENDIF.
                " 2. Duplicate within same request
                READ TABLE lt_fi_bkeys WITH KEY table_line = lv_fi_bkey TRANSPORTING NO FIELDS.
                IF sy-subrc = 0.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |FI Limit CREATE: Duplicate key ExpType={ ls_fi_pre-expense_type } GlAcc={ ls_fi_pre-gl_account } in same request| ) ) TO reported-req.
                ELSE.
                  APPEND lv_fi_bkey TO lt_fi_bkeys.
                ENDIF.
                " 3. Already exists in DEV main table
                SELECT SINGLE @abap_true FROM zfilimitconf
                  WHERE env_id       = @lc_env_dev
                    AND expense_type = @ls_fi_pre-expense_type
                    AND gl_account   = @ls_fi_pre-gl_account
                  INTO @DATA(lv_fi_dup).
                IF lv_fi_dup = abap_true.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |FI Limit CREATE: Config ExpType={ ls_fi_pre-expense_type } GlAcc={ ls_fi_pre-gl_account } already exists in DEV| ) ) TO reported-req.
                ENDIF.
              WHEN 'U' OR 'X'.
                " 4. source_item_id must exist
                IF ls_fi_pre-source_item_id IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |FI Limit { ls_fi_pre-action_type }: source_item_id missing| ) ) TO reported-req.
                ELSE.
                  SELECT SINGLE @abap_true FROM zfilimitconf
                    WHERE item_id = @ls_fi_pre-source_item_id
                    INTO @DATA(lv_fi_src).
                  IF lv_fi_src <> abap_true.
                    lv_has_error = abap_true.
                    APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                      severity = if_abap_behv_message=>severity-error
                      text     = |FI Limit { ls_fi_pre-action_type }: source row not found in DEV (may have been deleted)| ) ) TO reported-req.
                  ENDIF.
                ENDIF.
            ENDCASE.
          ENDLOOP.

          "  SD Price
          SELECT * FROM zsd_price_req
            WHERE req_id = @<r>-ReqId
            INTO TABLE @DATA(lt_sd_pre).

          DATA lt_sd_bkeys TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
          CLEAR lt_sd_bkeys.

          LOOP AT lt_sd_pre INTO DATA(ls_sd_pre).
            DATA(lv_sd_bkey) = |{ ls_sd_pre-branch_id }\|{ ls_sd_pre-cust_group }\|{ ls_sd_pre-material_grp }|.

            CASE ls_sd_pre-action_type.
              WHEN 'C' OR 'CREATE'.
                " 1. Required fields
                IF ls_sd_pre-branch_id IS INITIAL OR ls_sd_pre-cust_group IS INITIAL OR ls_sd_pre-material_grp IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |SD Price CREATE: BranchId, CustGroup, MaterialGrp are required| ) ) TO reported-req.
                ENDIF.
                " 2. Duplicate within same request
                READ TABLE lt_sd_bkeys WITH KEY table_line = lv_sd_bkey TRANSPORTING NO FIELDS.
                IF sy-subrc = 0.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |SD Price CREATE: Duplicate key Branch={ ls_sd_pre-branch_id } CustGrp={ ls_sd_pre-cust_group } MatGrp={ ls_sd_pre-material_grp } in same request| ) ) TO reported-req.
                ELSE.
                  APPEND lv_sd_bkey TO lt_sd_bkeys.
                ENDIF.
                " 3. Already exists in DEV main table
                SELECT SINGLE @abap_true FROM zsd_price_conf
                  WHERE env_id       = @lc_env_dev
                    AND branch_id    = @ls_sd_pre-branch_id
                    AND cust_group   = @ls_sd_pre-cust_group
                    AND material_grp = @ls_sd_pre-material_grp
                  INTO @DATA(lv_sd_dup).
                IF lv_sd_dup = abap_true.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |SD Price CREATE: Config Branch={ ls_sd_pre-branch_id } CustGrp={ ls_sd_pre-cust_group } MatGrp={ ls_sd_pre-material_grp } already exists in DEV| ) ) TO reported-req.
                ENDIF.
              WHEN 'U' OR 'X'.
                " 4. source_item_id must exist
                IF ls_sd_pre-source_item_id IS INITIAL.
                  lv_has_error = abap_true.
                  APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                    severity = if_abap_behv_message=>severity-error
                    text     = |SD Price { ls_sd_pre-action_type }: source_item_id missing| ) ) TO reported-req.
                ELSE.
                  SELECT SINGLE @abap_true FROM zsd_price_conf
                    WHERE item_id = @ls_sd_pre-source_item_id
                    INTO @DATA(lv_sd_src).
                  IF lv_sd_src <> abap_true.
                    lv_has_error = abap_true.
                    APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                      severity = if_abap_behv_message=>severity-error
                      text     = |SD Price { ls_sd_pre-action_type }: source row not found in DEV (may have been deleted)| ) ) TO reported-req.
                  ENDIF.
                ENDIF.
            ENDCASE.
          ENDLOOP.

          " Gate: abort if any pre-write validation failed
          IF lv_has_error = abap_true.
            APPEND VALUE #( %tky = <r>-%tky ) TO failed-req.
            CONTINUE.
          ENDIF.

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

          " WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zmmsafestock_req
          SELECT * FROM zmmsafestock_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_ss_req).
          IF lt_ss_req IS NOT INITIAL.
            LOOP AT lt_ss_req ASSIGNING FIELD-SYMBOL(<ss>).

              ls_audit_log-client      = sy-mandt.
              TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
              ls_audit_log-req_id      = <r>-ReqId.
              ls_audit_log-conf_id     = <ss>-conf_id.
              ls_audit_log-module_id   = 'MM'.
              ls_audit_log-action_type = 'APPROVE'.
              ls_audit_log-table_name  = 'ZMMSAFESTOCK'.
              ls_audit_log-env_id      = lc_env_dev.
              ls_audit_log-object_key  = COND #( WHEN <ss>-action_type = 'C' OR <ss>-action_type = 'CREATE'
                                                 THEN <ss>-item_id
                                                 ELSE <ss>-source_item_id ).
              ls_audit_log-old_data    = |\{"PLANT_ID":"{ <ss>-old_plant_id }","MAT_GROUP":"{ <ss>-old_mat_group }","MIN_QTY":"{ <ss>-old_min_qty }"\}|.
              ls_audit_log-new_data    = |\{"PLANT_ID":"{ <ss>-plant_id }","MAT_GROUP":"{ <ss>-mat_group }","MIN_QTY":"{ <ss>-min_qty }"\}|.
              ls_audit_log-changed_by  = sy-uname.
              ls_audit_log-changed_at  = lv_now.
              APPEND ls_audit_log TO lt_audit_log.
              CLEAR ls_audit_log.

              CLEAR lv_record_exists.
              CASE <ss>-action_type.
                WHEN 'UPDATE' OR 'U'.
                  " Update only value fields on the DEV row — do NOT change env_id.
                  " The row already belongs to DEV (source_item_id points to the DEV row).
                  SELECT SINGLE @abap_true FROM zmmsafestock
                    WHERE item_id = @<ss>-source_item_id INTO @lv_record_exists.
                  IF lv_record_exists = abap_true.
                    lv_new_version = <ss>-version_no + 1.
                    UPDATE zmmsafestock SET
                      min_qty    = @<ss>-min_qty,
                      version_no = @lv_new_version,
                      req_id     = @<r>-ReqId,
                      changed_by = @sy-uname,
                      changed_at = @lv_now
                    WHERE item_id = @<ss>-source_item_id.
                  ENDIF.


                WHEN 'CREATE' OR 'C'.
                  INSERT zmmsafestock FROM @( VALUE zmmsafestock(
                    client     = sy-mandt
                    item_id    = <ss>-item_id
                    req_id     = <r>-ReqId
                    env_id     = lc_env_dev
                    plant_id   = <ss>-plant_id
                    mat_group  = <ss>-mat_group
                    min_qty    = <ss>-min_qty
                    version_no = 1
                    created_by = <ss>-created_by
                    created_at = lv_now
                    changed_by = sy-uname
                    changed_at = lv_now ) ).
                WHEN 'DELETE' OR 'X'.
                  DELETE FROM zmmsafestock WHERE item_id = @<ss>-source_item_id.
              ENDCASE.
            ENDLOOP.
            UPDATE zmmsafestock_req SET
              line_status = @gc_st_approved,
              changed_by  = @sy-uname,
              changed_at  = @lv_now
            WHERE req_id = @<r>-ReqId.
          ENDIF.

          " WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zmmrouteconf_req
          SELECT * FROM zmmrouteconf_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_route_req).
          IF lt_route_req IS NOT INITIAL.
            LOOP AT lt_route_req ASSIGNING FIELD-SYMBOL(<rt>).

              ls_audit_log-client      = sy-mandt.
              TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
              ls_audit_log-req_id      = <r>-ReqId.
              ls_audit_log-conf_id     = <rt>-conf_id.
              ls_audit_log-module_id   = 'MM'.
              ls_audit_log-action_type = 'APPROVE'.
              ls_audit_log-table_name  = 'ZMMROUTECONF'.
              ls_audit_log-env_id      = lc_env_dev.
              ls_audit_log-object_key  = COND #( WHEN <rt>-action_type = 'C'
                                                 THEN <rt>-item_id
                                                 ELSE <rt>-source_item_id ).
              ls_audit_log-old_data    = |\{"PLANT_ID":"{ <rt>-old_plant_id }","SEND_WH":"{ <rt>-old_send_wh }","RECEIVE_WH":"{ <rt>-old_receive_wh }","TRANS_MODE":"{ <rt>-old_trans_mode }"\}|.
              ls_audit_log-new_data    = |\{"PLANT_ID":"{ <rt>-plant_id }","SEND_WH":"{ <rt>-send_wh }","RECEIVE_WH":"{ <rt>-receive_wh }","TRANS_MODE":"{ <rt>-trans_mode }"\}|.
              ls_audit_log-changed_by  = sy-uname.
              ls_audit_log-changed_at  = lv_now.
              APPEND ls_audit_log TO lt_audit_log.
              CLEAR ls_audit_log.

              CLEAR lv_record_exists.
              CASE <rt>-action_type.
                WHEN 'U'.
                  " Update only value fields on the DEV row — do NOT change env_id.
                  SELECT SINGLE @abap_true FROM zmmrouteconf WHERE item_id = @<rt>-source_item_id INTO @lv_record_exists.
                  IF lv_record_exists = abap_true.
                    UPDATE zmmrouteconf SET
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

          " WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zfilimitreq
          SELECT * FROM zfilimitreq WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_fi_req).
          IF lt_fi_req IS NOT INITIAL.
            LOOP AT lt_fi_req ASSIGNING FIELD-SYMBOL(<fi>).

              ls_audit_log-client      = sy-mandt.
              TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
              ls_audit_log-req_id      = <r>-ReqId.
              ls_audit_log-conf_id     = <fi>-conf_id.
              ls_audit_log-module_id   = 'FI'.
              ls_audit_log-action_type = 'APPROVE'.
              ls_audit_log-table_name  = 'ZFILIMITCONF'.
              ls_audit_log-env_id      = lc_env_dev.
              ls_audit_log-object_key  = COND #( WHEN <fi>-action_type = 'C'
                                                 THEN <fi>-item_id
                                                 ELSE <fi>-source_item_id ).
              ls_audit_log-old_data    = |\{"EXPENSE_TYPE":"{ <fi>-old_expense_type }","GL_ACCOUNT":"{ <fi>-old_gl_account }","AUTO_APPR_LIM":"{ <fi>-old_auto_appr_lim }","CURRENCY":"{ <fi>-old_currency }"\}|.
              ls_audit_log-new_data    = |\{"EXPENSE_TYPE":"{ <fi>-expense_type }","GL_ACCOUNT":"{ <fi>-gl_account }","AUTO_APPR_LIM":"{ <fi>-auto_appr_lim }","CURRENCY":"{ <fi>-currency }"\}|.
              ls_audit_log-changed_by  = sy-uname.
              ls_audit_log-changed_at  = lv_now.
              APPEND ls_audit_log TO lt_audit_log.
              CLEAR ls_audit_log.

              CLEAR lv_record_exists.
              CASE <fi>-action_type.
                WHEN 'U'.
                  " Update only value fields on the DEV row — do NOT change env_id.
                  SELECT SINGLE @abap_true FROM zfilimitconf WHERE item_id = @<fi>-source_item_id INTO @lv_record_exists.
                  IF lv_record_exists = abap_true.
                    UPDATE zfilimitconf SET
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
                    env_id        = lc_env_dev
                    expense_type  = <fi>-expense_type
                    gl_account    = <fi>-gl_account
                    auto_appr_lim = <fi>-auto_appr_lim
                    currency      = <fi>-currency
                    version_no    = 1
                    created_at    = lv_now
                    changed_by    = sy-uname
                    changed_at    = lv_now ) ).
                WHEN 'X'.
                  DELETE FROM zfilimitconf WHERE item_id = @<fi>-source_item_id.
              ENDCASE.
            ENDLOOP.
            UPDATE zfilimitreq SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
          ENDIF.

          "  WRITE-BACK VÀ GHI LOG CHI TIẾT ITEM: zsd_price_req
          SELECT * FROM zsd_price_req WHERE req_id = @<r>-ReqId INTO TABLE @DATA(lt_sd_req).
          IF lt_sd_req IS NOT INITIAL.
            LOOP AT lt_sd_req ASSIGNING FIELD-SYMBOL(<sd>).

              ls_audit_log-client      = sy-mandt.
              TRY. ls_audit_log-log_id = cl_system_uuid=>create_uuid_x16_static( ). CATCH cx_uuid_error. ENDTRY.
              ls_audit_log-req_id      = <r>-ReqId.
              ls_audit_log-conf_id     = <sd>-conf_id.
              ls_audit_log-module_id   = 'SD'.
              ls_audit_log-action_type = 'APPROVE'.
              ls_audit_log-table_name  = 'ZSD_PRICE_CONF'.
              ls_audit_log-env_id      = lc_env_dev.
              ls_audit_log-object_key  = COND #( WHEN <sd>-action_type = 'C'
                                                 THEN <sd>-item_id
                                                 ELSE <sd>-source_item_id ).
              ls_audit_log-old_data    = |\{"BRANCH_ID":"{ <sd>-old_branch_id }","CUST_GROUP":"{ <sd>-old_cust_group }","MATERIAL_GRP":"{ <sd>-old_material_grp }","MAX_DISCOUNT":"{ <sd>-old_max_discount }","MIN_ORDER_VAL":"{ <sd>-old_min_order_val }"\}|.
              ls_audit_log-new_data    = |\{"BRANCH_ID":"{ <sd>-branch_id }","CUST_GROUP":"{ <sd>-cust_group }","MATERIAL_GRP":"{ <sd>-material_grp }","MAX_DISCOUNT":"{ <sd>-max_discount }","MIN_ORDER_VAL":"{ <sd>-min_order_val }"\}|.
              ls_audit_log-changed_by  = sy-uname.
              ls_audit_log-changed_at  = lv_now.
              APPEND ls_audit_log TO lt_audit_log.
              CLEAR ls_audit_log.

              CLEAR lv_record_exists.
              CASE <sd>-action_type.
                WHEN 'U'.
                  " Update only value fields on the DEV row — do NOT change env_id.
                  SELECT SINGLE @abap_true FROM zsd_price_conf WHERE item_id = @<sd>-source_item_id INTO @lv_record_exists.
                  IF lv_record_exists = abap_true.
                    UPDATE zsd_price_conf SET
                      max_discount  = @<sd>-max_discount,
                      min_order_val = @<sd>-min_order_val,
                      approver_grp  = @<sd>-approver_grp,
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
                WHEN 'X'.
                  DELETE FROM zsd_price_conf WHERE item_id = @<sd>-source_item_id.
              ENDCASE.
            ENDLOOP.
            UPDATE zsd_price_req SET line_status = @gc_st_approved, changed_by = @sy-uname, changed_at = @lv_now WHERE req_id = @<r>-ReqId.
          ENDIF.

          " THÔNG BÁO CHO NGƯỜI TẠO REQUEST
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
                is_new_data = VALUE #( BASE <r> Status = gc_st_rejected RejectReason = lv_reason )
              ).
            CATCH cx_root INTO DATA(lx_audit_rej).
              APPEND VALUE #( %tky = <r>-%tky %msg = new_message_with_text(
                severity = if_abap_behv_message=>severity-warning
                text = |Audit log failed: { lx_audit_rej->get_text( ) }| ) ) TO reported-req.
          ENDTRY.

          " 7. Cập nhật vào Database
          MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
            ENTITY Req UPDATE FIELDS ( Status RejectReason RejectedBy RejectedAt )
            WITH VALUE #( ( %tky         = <r>-%tky
                            Status       = gc_st_rejected
                            RejectReason = lv_reason
                            RejectedBy   = sy-uname
                            RejectedAt   = lv_now ) ).

          " PUSH NOTIFICATION: THÔNG BÁO TỪ CHỐI CHO NGƯỜI TẠO REQUEST
          DATA: lt_notif_rej TYPE /iwngw/if_notif_provider=>ty_t_notification,
                ls_notif_rej TYPE /iwngw/if_notif_provider=>ty_s_notification,
                lt_recip_rej TYPE /iwngw/if_notif_provider=>ty_t_notification_recipient,
                ls_recip_rej TYPE /iwngw/if_notif_provider=>ty_s_notification_recipient.

          ls_recip_rej-id = <r>-CreatedBy.
          APPEND ls_recip_rej TO lt_recip_rej.

          TRY.
              ls_notif_rej-id = cl_system_uuid=>create_uuid_x16_static( ).
            CATCH cx_uuid_error.
          ENDTRY.

          ls_notif_rej-type_key     = 'REQ_REJECTED'.
          ls_notif_rej-type_version = '1'.
          ls_notif_rej-priority     = /iwngw/if_notif_provider=>gcs_priorities-high.
          ls_notif_rej-recipients   = lt_recip_rej.
          ls_notif_rej-parameters   = VALUE #(
            ( language   = sy-langu
              parameters = VALUE #(
                ( name = 'ReqTitle' value = CONV #( <r>-ReqTitle ) type = 'Edm.String' )
              )
            )
          ).
          ls_notif_rej-navigation_parameters = VALUE #(
            ( name = 'SemanticObject' value = 'ConfigReq' )
            ( name = 'Action'         value = 'manage' )
            ( name = 'ReqId'          value = CONV #( <r>-ReqId ) )
          ).
          APPEND ls_notif_rej TO lt_notif_rej.

          TRY.
              /iwngw/cl_notification_api=>create_notifications(
                EXPORTING
                  iv_provider_id  = 'ZGSP26SAP06_REQ_NOTIF'
                  it_notification = lt_notif_rej
              ).
            CATCH /iwngw/cx_notification_api.
          ENDTRY.
          " =============================================================

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

        DATA lv_ver_ss TYPE i.
        DATA lv_ver_rt TYPE i.
        DATA lv_ver_fi TYPE i.
        DATA lv_ver_sd TYPE i.

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

          " ── Lấy version toàn cục của module ở PRD ──
          IF lv_next_env = 'PRD'.
            SELECT MAX( version_no ) FROM zmmsafestock  WHERE env_id = 'PRD' INTO @lv_ver_ss.
            lv_ver_ss = lv_ver_ss + 1.

            SELECT MAX( version_no ) FROM zmmrouteconf   WHERE env_id = 'PRD' INTO @lv_ver_rt.
            lv_ver_rt = lv_ver_rt + 1.

            SELECT MAX( version_no ) FROM zfilimitconf   WHERE env_id = 'PRD' INTO @lv_ver_fi.
            lv_ver_fi = lv_ver_fi + 1.

            SELECT MAX( version_no ) FROM zsd_price_conf WHERE env_id = 'PRD' INTO @lv_ver_sd.
            lv_ver_sd = lv_ver_sd + 1.
          ENDIF.



          " ── MM SafeStock: UPDATE the existing target-env row (same business key) ──
          " Source: DEV row (req_id + env_id = current env).
          " Target: row in next_env with same plant_id + mat_group.
          DATA lv_ver_new TYPE i.
          SELECT * FROM zmmsafestock
            WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
            INTO TABLE @DATA(lt_ss).
          LOOP AT lt_ss ASSIGNING FIELD-SYMBOL(<ss>).
            DATA lv_ss_target_id TYPE sysuuid_x16.
            SELECT SINGLE item_id FROM zmmsafestock
              WHERE env_id   = @lv_next_env
                AND plant_id = @<ss>-plant_id
                AND mat_group = @<ss>-mat_group
              INTO @lv_ss_target_id.
            IF sy-subrc = 0.
              " COND not allowed in UPDATE SET — compute version into a variable first
              lv_ver_new = COND #( WHEN lv_next_env = 'PRD' THEN lv_ver_ss ELSE <ss>-version_no ).
              UPDATE zmmsafestock SET
                min_qty    = @<ss>-min_qty,
                version_no = @lv_ver_new,
                req_id     = @<r>-ReqId,
                changed_by = @sy-uname,
                changed_at = @lv_now
              WHERE item_id = @lv_ss_target_id.
            ENDIF.
            CLEAR lv_ss_target_id.
          ENDLOOP.

          " ── MM Route: UPDATE the existing target-env row (same business key) ──
          SELECT * FROM zmmrouteconf
            WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
            INTO TABLE @DATA(lt_rt).
          LOOP AT lt_rt ASSIGNING FIELD-SYMBOL(<rt>).
            DATA lv_rt_target_id TYPE sysuuid_x16.
            SELECT SINGLE item_id FROM zmmrouteconf
              WHERE env_id     = @lv_next_env
                AND plant_id   = @<rt>-plant_id
                AND send_wh    = @<rt>-send_wh
                AND receive_wh = @<rt>-receive_wh
              INTO @lv_rt_target_id.
            IF sy-subrc = 0.
              lv_ver_new = COND #( WHEN lv_next_env = 'PRD' THEN lv_ver_rt ELSE <rt>-version_no ).
              UPDATE zmmrouteconf SET
                inspector_id = @<rt>-inspector_id,
                trans_mode   = @<rt>-trans_mode,
                is_allowed   = @<rt>-is_allowed,
                version_no   = @lv_ver_new,
                req_id       = @<r>-ReqId,
                changed_by   = @sy-uname,
                changed_at   = @lv_now
              WHERE item_id = @lv_rt_target_id.
            ENDIF.
            CLEAR lv_rt_target_id.
          ENDLOOP.

          " ── FI Limit: UPDATE the existing target-env row (same business key) ──
          SELECT * FROM zfilimitconf
            WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
            INTO TABLE @DATA(lt_fi).
          LOOP AT lt_fi ASSIGNING FIELD-SYMBOL(<fi>).
            DATA lv_fi_target_id TYPE sysuuid_x16.
            SELECT SINGLE item_id FROM zfilimitconf
              WHERE env_id       = @lv_next_env
                AND expense_type = @<fi>-expense_type
                AND gl_account   = @<fi>-gl_account
              INTO @lv_fi_target_id.
            IF sy-subrc = 0.
              lv_ver_new = COND #( WHEN lv_next_env = 'PRD' THEN lv_ver_fi ELSE <fi>-version_no ).
              UPDATE zfilimitconf SET
                auto_appr_lim = @<fi>-auto_appr_lim,
                currency      = @<fi>-currency,
                version_no    = @lv_ver_new,
                req_id        = @<r>-ReqId,
                changed_by    = @sy-uname,
                changed_at    = @lv_now
              WHERE item_id = @lv_fi_target_id.
            ENDIF.
            CLEAR lv_fi_target_id.
          ENDLOOP.

          " ── SD Price: UPDATE the existing target-env row (same business key) ──
          SELECT * FROM zsd_price_conf
            WHERE req_id = @<r>-ReqId AND env_id = @<r>-EnvId
            INTO TABLE @DATA(lt_sd).
          LOOP AT lt_sd ASSIGNING FIELD-SYMBOL(<sd>).
            DATA lv_sd_target_id TYPE sysuuid_x16.
            SELECT SINGLE item_id FROM zsd_price_conf
              WHERE env_id      = @lv_next_env
                AND branch_id   = @<sd>-branch_id
                AND cust_group  = @<sd>-cust_group
                AND material_grp = @<sd>-material_grp
              INTO @lv_sd_target_id.
            IF sy-subrc = 0.
              lv_ver_new = COND #( WHEN lv_next_env = 'PRD' THEN lv_ver_sd ELSE <sd>-version_no ).
              UPDATE zsd_price_conf SET
                max_discount  = @<sd>-max_discount,
                min_order_val = @<sd>-min_order_val,
                approver_grp  = @<sd>-approver_grp,
                currency      = @<sd>-currency,
                valid_from    = @<sd>-valid_from,
                valid_to      = @<sd>-valid_to,
                version_no    = @lv_ver_new,
                req_id        = @<r>-ReqId,
                changed_by    = @sy-uname,
                changed_at    = @lv_now
              WHERE item_id = @lv_sd_target_id.
            ENDIF.
            CLEAR lv_sd_target_id.
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

          " ── Update request header: move env_id to next env ──
          " EnvId is a RAP key field — cannot change via MODIFY ENTITIES UPDATE.
          " Use direct SQL to shift the row's env_id (DEV→QAS or QAS→PRD).
          " Status = ACTIVE only when reaching PRD (config is fully live).
          " Status stays APPROVED while still promoting through intermediate envs.
          DATA lv_new_status TYPE zde_requ_status.
          lv_new_status = COND #( WHEN lv_next_env = 'PRD'
                                  THEN gc_st_active
                                  ELSE gc_st_approved ).
          UPDATE zconfreqh
            SET env_id     = @lv_next_env,
                status     = @lv_new_status,
                changed_by = @sy-uname,
                changed_at = @lv_now
            WHERE req_id = @<r>-ReqId
              AND env_id  = @<r>-EnvId.

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
                    version_no = 1  created_by = <ss>-created_by  created_at = lv_now
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
            ENTITY Req UPDATE FIELDS ( Reason ReqTitle ChangedBy ChangedAt )
            WITH VALUE #( (
              %tky      = ls_key-%tky
              Reason    = ls_key-%param-reason
              ReqTitle  = ls_key-%param-req_title
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
        METHODS get_instance_features FOR INSTANCE FEATURES
          IMPORTING keys REQUEST requested_features FOR Item RESULT result.
        METHODS validate_item FOR VALIDATE ON SAVE IMPORTING keys FOR Item~validate_item.
    ENDCLASS.

    CLASS lhc_Item IMPLEMENTATION.
      METHOD get_instance_features.
        " Đọc Status của Header cha thông qua association _Header
        READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
          ENTITY Item BY \_Header
            FIELDS ( Status )
            WITH CORRESPONDING #( keys )
          RESULT DATA(lt_headers).

        LOOP AT keys ASSIGNING FIELD-SYMBOL(<key>).
          " Tìm header cha tương ứng
          READ TABLE lt_headers ASSIGNING FIELD-SYMBOL(<hdr>)
            WITH KEY %tky-%key = <key>-%key BINARY SEARCH.
          IF sy-subrc <> 0.
            READ TABLE lt_headers INDEX 1 ASSIGNING <hdr>.
          ENDIF.

          DATA(lv_status) = COND zde_requ_status( WHEN <hdr> IS ASSIGNED THEN condense( <hdr>-Status ) ELSE '' ).

          " Chỉ cho phép edit/delete item khi Header đang ở DRAFT hoặc ROLLED_BACK
          DATA(lv_upd_del) = COND #(
            WHEN lv_status = 'DRAFT' OR lv_status = 'ROLLED_BACK'
              THEN if_abap_behv=>fc-o-enabled
              ELSE if_abap_behv=>fc-o-disabled ).

          APPEND VALUE #(
            %tky    = <key>-%tky
            %update = lv_upd_del
            %delete = lv_upd_del
          ) TO result.
        ENDLOOP.
      ENDMETHOD.

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
