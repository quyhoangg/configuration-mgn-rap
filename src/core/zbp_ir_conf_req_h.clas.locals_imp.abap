CLASS lhc_Req DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

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

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION Req~approve RESULT result.

    METHODS reject FOR MODIFY
      IMPORTING keys FOR ACTION Req~reject RESULT result.

    METHODS submit FOR MODIFY
      IMPORTING keys FOR ACTION Req~submit RESULT result.

    "  METHODS set_default_and_admin_fields FOR DETERMINE ON MODIFY
    "    IMPORTING keys FOR Req~set_default_and_admin_fields.

    METHODS validate_before_save FOR VALIDATE ON SAVE
      IMPORTING keys FOR Req~validate_before_save.
    METHODS promote FOR MODIFY IMPORTING keys FOR ACTION Req~promote RESULT result.

    METHODS createFromCatalog FOR MODIFY
      IMPORTING keys FOR ACTION Req~createFromCatalog RESULT result.

ENDCLASS.

CLASS lhc_Req IMPLEMENTATION.

  METHOD get_instance_authorizations.
  ENDMETHOD.

  METHOD get_instance_features.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req
        FIELDS ( Status )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    DATA lv_role TYPE c LENGTH 20.
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id  = @sy-uname
        AND is_active = @abap_true
      INTO @lv_role.

    LOOP AT lt_reqs INTO DATA(ls_req).

      DATA(lv_update) = COND #(
        WHEN ls_req-Status = gc_st_draft OR ls_req-Status IS INITIAL
        THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_submit) = COND #(
        WHEN ls_req-Status = gc_st_draft
        THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_approve) = COND #(
        WHEN ls_req-Status = gc_st_submitted AND lv_role = gc_role_manager
        THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_reject) = COND #(
        WHEN ls_req-Status = gc_st_submitted AND lv_role = gc_role_manager
        THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      DATA(lv_promote) = COND #(
        WHEN ls_req-Status = gc_st_approved AND lv_role = gc_role_itadmin
        THEN if_abap_behv=>fc-o-enabled
        ELSE if_abap_behv=>fc-o-disabled ).

      APPEND VALUE #(
        %tky            = ls_req-%tky
        %update         = lv_update
        %action-submit  = lv_submit
        %action-approve = lv_approve
        %action-reject  = lv_reject
        %action-promote = lv_promote
      ) TO result.

    ENDLOOP.

  ENDMETHOD.

  METHOD approve.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(reqs).

    " Đọc các Item bên trong để ném cho Validator
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req BY \_Items ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(items).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      " 1. Check Status của bạn
      IF <r>-Status <> gc_st_submitted.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Approve allowed only when status = { gc_st_submitted }| ) ) TO reported-Req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-Req.
        CONTINUE.
      ENDIF.

      DATA(lv_has_error) = abap_false.
      DATA(lt_current_items) = items.
      DELETE lt_current_items WHERE ReqId <> <r>-ReqId.

      " =========================================================
      " 2. GỌI RULE VALIDATOR (Check Range, Mandatory của từng Item)
      " =========================================================
      LOOP AT lt_current_items INTO DATA(ls_item).
        DATA(lt_val_errors) = zcl_gsp26_rule_validator=>validate_request_item(
                                iv_conf_id       = ls_item-ConfId
                                iv_action        = ls_item-Action
                                iv_target_env_id = ls_item-TargetEnvId
                              ).
        IF lt_val_errors IS NOT INITIAL.
          lv_has_error = abap_true.
          APPEND VALUE #( %tky = <r>-%tky ) TO failed-Req.
          LOOP AT lt_val_errors INTO DATA(ls_err).
            APPEND VALUE #( %tky = <r>-%tky
                            %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                          text     = |Item { ls_item-ConfId }: { ls_err-message }| ) ) TO reported-Req.
          ENDLOOP.
        ENDIF.
      ENDLOOP.

      IF lv_has_error = abap_true. CONTINUE. ENDIF. " Có lỗi cấu hình -> Bỏ qua Approve

      " =========================================================
      " 3. GỌI RULE WRITER (Lưu JSON Audit Trail)
      " =========================================================
      TRY.
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = VALUE #( lt_current_items[ 1 ]-ConfId OPTIONAL )
            iv_req_id   = <r>-ReqId
            iv_mod_id   = <r>-ModuleId
            iv_act_type = 'APPROVE'
            iv_tab_name = 'ZCONFREQH'
            iv_env_id   = <r>-EnvId
            is_new_data = <r>
          ).
        CATCH cx_root.
      ENDTRY.

      " =========================================================
      " 4. APPROVED CỦA BẠN (Cập nhật Status, User, Time)
      " =========================================================
      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status ApprovedBy ApprovedAt )
        WITH VALUE #( ( %tky = <r>-%tky
                        Status     = gc_st_approved
                        ApprovedBy = sy-uname
                        ApprovedAt = lv_now ) ).
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.

  METHOD reject.

    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-Status <> gc_st_submitted.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Reject allowed only when status = { gc_st_submitted }| )
        ) TO reported-Req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-Req.
        CONTINUE.
      ENDIF.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status RejectedBy RejectedAt )
        WITH VALUE #(
          ( %tky = <r>-%tky
            Status     = gc_st_rejected
            RejectedBy = sy-uname
            RejectedAt = lv_now ) ).

    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).

  ENDMETHOD.

  METHOD submit.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
    ENTITY Req
    ALL FIELDS WITH CORRESPONDING #( keys )
    RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-Status <> gc_st_draft.
        CONTINUE.
      ENDIF.

      "Check items exist
      READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req BY \_Items
        ALL FIELDS WITH VALUE #( ( %tky = <r>-%tky ) )
        RESULT DATA(items).

      IF items IS INITIAL.
        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Request must contain at least one item before submit' )
        ) TO reported-Req.
        CONTINUE.
      ENDIF.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status )
        WITH VALUE #( ( %tky = <r>-%tky Status = gc_st_submitted ) ).

    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).

  ENDMETHOD.

  " METHOD set_default_and_admin_fields.

  "     DATA lv_now TYPE timestampl.
  "    GET TIME STAMP FIELD lv_now.

  "Read current instances
  "    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
  "      ENTITY Req
  "      ALL FIELDS WITH CORRESPONDING #( keys )
  "    RESULT DATA(reqs).

  "    MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
  "    ENTITY Req
  "     UPDATE FIELDS ( Status CreatedBy CreatedAt ChangedBy ChangedAt )
  "     WITH VALUE #(
  "       FOR r IN reqs
  "       ( %tky      = r-%tky
  "       Status    = COND #( WHEN r-Status    IS INITIAL THEN gc_st_draft ELSE r-Status )
  "          CreatedBy = COND #( WHEN r-CreatedBy IS INITIAL THEN sy-uname    ELSE r-CreatedBy )
  "           CreatedAt = COND #( WHEN r-CreatedAt IS INITIAL THEN lv_now      ELSE r-CreatedAt )
  "      ChangedBy = sy-uname
  "        ChangedAt = lv_now ) ).

  "  ENDMETHOD.

  METHOD validate_before_save.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(reqs).

    "1) Header rule: ACTIVE/REJECTED
    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-Status = gc_st_approved OR <r>-Status = gc_st_rejected.

        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Completed request cannot be changed' )
        ) TO reported-Req.

        APPEND VALUE #( %tky = <r>-%tky ) TO failed-Req.

      ENDIF.

    ENDLOOP.

    "2) Item rule: mandatory ConfId/TargetEnvId/Action
    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req BY \_Items
      ALL FIELDS WITH VALUE #( FOR r IN reqs ( %tky = r-%tky ) )
      RESULT DATA(items).

    DATA(lv_item_error) = abap_false.

    LOOP AT items ASSIGNING FIELD-SYMBOL(<i>).
      IF <i>-ConfId IS INITIAL OR <i>-TargetEnvId IS INITIAL OR <i>-Action IS INITIAL.
        lv_item_error = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    IF lv_item_error = abap_true.

      "Report errors on header saved
      LOOP AT reqs ASSIGNING FIELD-SYMBOL(<rh>).
        APPEND VALUE #(
          %tky = <rh>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Item validation failed: ConfId/TargetEnvId/Action are required' )
        ) TO reported-Req.

        APPEND VALUE #( %tky = <rh>-%tky ) TO failed-Req.
      ENDLOOP.

    ENDIF.

  ENDMETHOD.

  METHOD promote.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zir_conf_req_h IN LOCAL MODE
      ENTITY Req ALL FIELDS WITH CORRESPONDING #( keys ) RESULT DATA(reqs).

    LOOP AT reqs ASSIGNING FIELD-SYMBOL(<r>).
      " Promote chỉ chạy khi đã Approved
      IF <r>-Status <> gc_st_approved.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text( severity = if_abap_behv_message=>severity-error
                                                      text     = |Promote allowed only when status = { gc_st_approved }| ) ) TO reported-Req.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-Req.
        CONTINUE.
      ENDIF.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req UPDATE FIELDS ( Status )
        WITH VALUE #( ( %tky = <r>-%tky Status = 'PROMOTED' ) ). " Hoặc dùng gc_st_active của bạn
    ENDLOOP.

    result = VALUE #( FOR r IN reqs ( %tky = r-%tky ) ).
  ENDMETHOD.


  METHOD createFromCatalog.

    LOOP AT keys INTO DATA(ls_key).

      DATA: lv_req_id      TYPE sysuuid_x16,
            lv_req_item_id TYPE sysuuid_x16,
            lv_cid_req     TYPE string,
            lv_target_app  TYPE string.

      lv_req_id      = cl_system_uuid=>create_uuid_x16_static( ).
      lv_req_item_id = cl_system_uuid=>create_uuid_x16_static( ).
      lv_cid_req     = |REQ_{ sy-tabix }|.

      CASE ls_key-%param-TargetCds.
        WHEN 'ZI_MM_ROUTE_CONF'.
          lv_target_app = 'MM_ROUTE_REQ'.
        WHEN 'ZI_MM_SAFE_STOCK'.
          lv_target_app = 'MM_SAFE_REQ'.
        WHEN 'ZI_SD_PRICE_CONF'.
          lv_target_app = 'SD_PRICE_REQ'.
        WHEN 'ZI_FI_LIMIT_CONF'.
          lv_target_app = 'FI_LIMIT_REQ'.
        WHEN OTHERS.
          lv_target_app = 'CONF_REQ'.
      ENDCASE.

      MODIFY ENTITIES OF zir_conf_req_h IN LOCAL MODE
        ENTITY Req
          CREATE FIELDS ( ReqId ModuleId ReqTitle Description Status Reason )
          WITH VALUE #(
            ( %cid        = lv_cid_req
              ReqId       = lv_req_id
              ModuleId    = ls_key-%param-ModuleId
              ReqTitle    = |Maintain { ls_key-%param-ConfName }|
              Description = |Auto-created from catalog|
              Status      = gc_st_draft
              Reason      = ls_key-%param-Reason
            )
          )
        ENTITY Req
          CREATE BY \_Items
          FIELDS ( ReqItemId ConfId Action TargetEnvId Notes VersionNo )
          WITH VALUE #(
            ( %cid_ref = lv_cid_req
              %target  = VALUE #(
                ( ReqItemId   = lv_req_item_id
                  ConfId      = ls_key-%param-ConfId
                  Action      = ls_key-%param-ActionType
                  TargetEnvId = ls_key-%param-TargetEnvId
                  Notes       = ls_key-%param-Notes
                  VersionNo   = 1
                )
              )
            )
          )
        FAILED   DATA(lt_failed_req)
        REPORTED DATA(lt_reported_req)
        MAPPED   DATA(lt_mapped_req).

      IF lt_failed_req IS NOT INITIAL.
        CONTINUE.
      ENDIF.

      APPEND VALUE #(
        %param-ReqId     = lv_req_id
        %param-ReqItemId = lv_req_item_id
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

    METHODS validate_item FOR VALIDATE ON SAVE
      IMPORTING keys FOR Item~validate_item.

ENDCLASS.

CLASS lhc_Item IMPLEMENTATION.

  METHOD validate_item.
    "No logic here - validated in header validation
  ENDMETHOD.

ENDCLASS.
