CLASS lhc_RouteConf DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR RouteConf~set_defaults.

    METHODS setAdminFields FOR DETERMINE ON MODIFY
      IMPORTING keys FOR RouteConf~setAdminFields.

    METHODS validate_business FOR VALIDATE ON SAVE
      IMPORTING keys FOR RouteConf~validate_business.

    METHODS validate_mandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR RouteConf~validate_mandatory.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION RouteConf~approve RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features
      FOR RouteConf RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations
      FOR RouteConf RESULT result.

ENDCLASS.


CLASS lhc_RouteConf IMPLEMENTATION.

  METHOD set_defaults.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).

      DATA(lv_is_allowed) = COND abap_boolean(
                              WHEN <r>-IsAllowed IS INITIAL THEN abap_true
                              ELSE <r>-IsAllowed ).

      DATA(lv_version_no) = COND i(
                              WHEN <r>-VersionNo IS INITIAL THEN 1
                              ELSE <r>-VersionNo ).

      DATA(lv_action_type) = COND zde_action_type(
                               WHEN <r>-ActionType IS INITIAL THEN 'C'
                               ELSE <r>-ActionType ).

      " NOTE: ActionType bị xóa khỏi UPDATE FIELDS để tránh vòng lặp vô hạn.
      " Trigger của determination là { field SourceItemId, ActionType } — nếu
      " MODIFY này ghi lại ActionType thì sẽ tự trigger lại chính nó → RAISE_SHORTDUMP.
      " Frontend luôn gửi ActionType đúng ('U'/'C'/'X') nên không cần default ở đây.
      MODIFY ENTITIES OF zi_mm_route_conf IN LOCAL MODE
        ENTITY RouteConf
        UPDATE FIELDS ( IsAllowed VersionNo )
        WITH VALUE #(
          (
            %tky      = <r>-%tky
            IsAllowed = lv_is_allowed
            VersionNo = lv_version_no
          )
        ).

      " ── For U/X rows: populate OldXxx only if frontend didn't send them ──
      " NOTE: Do NOT overwrite new values (EnvId/PlantId/...) — frontend sends
      "       the user's intended changes. Only fill OldXxx as a fallback.
      IF lv_action_type = 'U' OR lv_action_type = 'X'.

        IF <r>-SourceItemId IS INITIAL.
          CONTINUE.
        ENDIF.

        " Skip if frontend already sent all Old snapshot fields
        IF <r>-OldEnvId IS NOT INITIAL OR <r>-OldPlantId IS NOT INITIAL.
          CONTINUE.
        ENDIF.

        SELECT SINGLE *
          FROM zmmrouteconf
          WHERE item_id = @<r>-SourceItemId
          INTO @DATA(ls_src).

        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

        " Populate only OldXxx — never touch the new value fields
        MODIFY ENTITIES OF zi_mm_route_conf IN LOCAL MODE
          ENTITY RouteConf
          UPDATE FIELDS (
            OldEnvId
            OldPlantId
            OldSendWh
            OldReceiveWh
            OldInspectorId
            OldTransMode
            OldIsAllowed
            OldVersionNo
          )
          WITH VALUE #(
            (
              %tky            = <r>-%tky
              OldEnvId        = ls_src-env_id
              OldPlantId      = ls_src-plant_id
              OldSendWh       = ls_src-send_wh
              OldReceiveWh    = ls_src-receive_wh
              OldInspectorId  = ls_src-inspector_id
              OldTransMode    = ls_src-trans_mode
              OldIsAllowed    = ls_src-is_allowed
              OldVersionNo    = ls_src-version_no
            )
          ).

      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  METHOD setAdminFields.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
        FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
        WITH CORRESPONDING #( keys )
      RESULT DATA(entities).

    DATA lt_update TYPE TABLE FOR UPDATE zi_mm_route_conf\\RouteConf.

    LOOP AT entities INTO DATA(entity).
      DATA(lv_new_created_by) = COND syuname(
        WHEN entity-CreatedBy IS INITIAL THEN sy-uname
        ELSE entity-CreatedBy ).
      DATA(lv_new_created_at) = COND timestampl(
        WHEN entity-CreatedAt IS INITIAL THEN lv_now
        ELSE entity-CreatedAt ).

      IF entity-ChangedBy   = sy-uname
      AND entity-CreatedBy  = lv_new_created_by
      AND entity-CreatedAt  = lv_new_created_at.
        CONTINUE.
      ENDIF.

      APPEND VALUE #(
        %tky      = entity-%tky
        CreatedBy = lv_new_created_by
        CreatedAt = lv_new_created_at
        ChangedBy = sy-uname
        ChangedAt = lv_now
      ) TO lt_update.
    ENDLOOP.

    IF lt_update IS NOT INITIAL.
      MODIFY ENTITIES OF zi_mm_route_conf IN LOCAL MODE
        ENTITY RouteConf
          UPDATE FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
          WITH lt_update
        REPORTED DATA(update_reported).
      reported = CORRESPONDING #( DEEP update_reported ).
    ENDIF.
  ENDMETHOD.


  METHOD validate_mandatory.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-ActionType = 'C'.
        IF <r>-ReqId IS INITIAL OR
           <r>-EnvId IS INITIAL OR
           <r>-PlantId IS INITIAL OR
           <r>-SendWh IS INITIAL OR
           <r>-ReceiveWh IS INITIAL OR
           <r>-TransMode IS INITIAL.

          APPEND VALUE #( %tky = <r>-%tky ) TO failed-RouteConf.

          APPEND VALUE #(
            %tky = <r>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |Mandatory fields missing for CREATE.| ) )
            TO reported-RouteConf.
        ENDIF.
      ENDIF.

      IF ( <r>-ActionType = 'U' OR <r>-ActionType = 'X' )
         AND <r>-SourceItemId IS INITIAL.

        APPEND VALUE #( %tky = <r>-%tky ) TO failed-RouteConf.

        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |SourceItemId is mandatory for UPDATE/DELETE.| ) )
          TO reported-RouteConf.
      ENDIF.

      IF ( <r>-ActionType = 'U' OR <r>-ActionType = 'X' )
         AND <r>-SourceItemId IS NOT INITIAL.

        SELECT SINGLE item_id
          FROM zmmrouteconf
          WHERE item_id = @<r>-SourceItemId
          INTO @DATA(lv_item_id).

        IF sy-subrc <> 0.
          APPEND VALUE #( %tky = <r>-%tky ) TO failed-RouteConf.

          APPEND VALUE #(
            %tky = <r>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |Source route line not found in active configuration.| ) )
            TO reported-RouteConf.
        ENDIF.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validate_business.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-SendWh IS NOT INITIAL AND
         <r>-ReceiveWh IS NOT INITIAL AND
         <r>-SendWh = <r>-ReceiveWh.

        APPEND VALUE #( %tky = <r>-%tky ) TO failed-RouteConf.

        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Send Warehouse must be different from Receive Warehouse.| ) )
          TO reported-RouteConf.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.


  METHOD approve.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    LOOP AT lt_reqs ASSIGNING FIELD-SYMBOL(<req>).

      " Chặn approve lại record đã approved
      IF <req>-LineStatus = 'APPROVED'.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-routeconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'This record is already approved.' )
        ) TO reported-routeconf.
        CONTINUE.
      ENDIF.

      " Check mandatory
      IF <req>-EnvId IS INITIAL OR <req>-PlantId IS INITIAL OR
         <req>-SendWh IS INITIAL OR <req>-ReceiveWh IS INITIAL.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-routeconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Cannot approve: mandatory fields missing.' )
        ) TO reported-routeconf.
        CONTINUE.
      ENDIF.

      " Tính version mới
      DATA(lv_new_version) = COND i(
        WHEN <req>-OldVersionNo IS NOT INITIAL THEN <req>-OldVersionNo + 1
        ELSE 1 ).

      " Chuẩn bị data ghi vào bảng chính
      DATA(ls_conf) = VALUE zmmrouteconf(
        client       = sy-mandt
        item_id      = COND #(
                         WHEN <req>-ConfId IS NOT INITIAL
                         THEN <req>-ConfId
                         ELSE <req>-ItemId )
        req_id       = <req>-ReqId
        env_id       = <req>-EnvId
        plant_id     = <req>-PlantId
        send_wh      = <req>-SendWh
        receive_wh   = <req>-ReceiveWh
        inspector_id = <req>-InspectorId
        trans_mode   = <req>-TransMode
        is_allowed   = <req>-IsAllowed
        version_no   = lv_new_version
        created_by   = COND #(
                         WHEN <req>-ActionType = 'C'
                         THEN sy-uname
                         ELSE <req>-CreatedBy )
        created_at   = COND #(
                         WHEN <req>-ActionType = 'C'
                         THEN lv_now
                         ELSE <req>-CreatedAt )
        changed_by   = sy-uname
        changed_at   = lv_now
      ).

      " Lấy dữ liệu CŨ trước khi thay đổi để làm Rollback Snapshot
      DATA ls_old_route TYPE zmmrouteconf.
      CLEAR ls_old_route.
      IF <req>-ActionType = 'U' OR <req>-ActionType = 'X'.
        SELECT SINGLE * FROM zmmrouteconf WHERE item_id = @ls_conf-item_id INTO @ls_old_route.
      ENDIF.
      TRY.
          " Ghi log audit snapshot (serialize JSON tự động)
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = ls_conf-item_id
            iv_req_id   = <req>-ReqId
            iv_mod_id   = 'MM'
            iv_act_type = 'APPROVE'
            iv_tab_name = 'ZMMROUTECONF'
            iv_env_id   = <req>-EnvId
            is_old_data = ls_old_route
            is_new_data = ls_conf ).
        CATCH cx_root.
          " Nếu lỗi ghi log thì bỏ qua vẫn chạy tiếp
      ENDTRY.

      " Xử lý theo ActionType
      TRY.
          CASE <req>-ActionType.

            WHEN 'X'.
              DELETE FROM zmmrouteconf
                WHERE item_id = @ls_conf-item_id.

              IF sy-subrc <> 0.
                APPEND VALUE #(
                  %tky = <req>-%tky
                  %msg = new_message_with_text(
                           severity = if_abap_behv_message=>severity-warning
                           text     = 'Record not found in config table.' )
                ) TO reported-routeconf.
              ENDIF.

            WHEN OTHERS. " CREATE / UPDATE
              SELECT SINGLE @abap_true
                FROM zmmrouteconf
                WHERE item_id = @ls_conf-item_id
                INTO @DATA(lv_exists).

              IF lv_exists = abap_true.
                UPDATE zmmrouteconf SET
                  req_id       = @ls_conf-req_id,
                  env_id       = @ls_conf-env_id,
                  plant_id     = @ls_conf-plant_id,
                  send_wh      = @ls_conf-send_wh,
                  receive_wh   = @ls_conf-receive_wh,
                  inspector_id = @ls_conf-inspector_id,
                  trans_mode   = @ls_conf-trans_mode,
                  is_allowed   = @ls_conf-is_allowed,
                  version_no   = @ls_conf-version_no,
                  changed_by   = @ls_conf-changed_by,
                  changed_at   = @ls_conf-changed_at
                  WHERE item_id = @ls_conf-item_id.
              ELSE.
                INSERT zmmrouteconf FROM @ls_conf.
              ENDIF.

          ENDCASE.

        CATCH cx_root INTO DATA(lx_err).
          APPEND VALUE #( %tky = <req>-%tky ) TO failed-routeconf.
          APPEND VALUE #(
            %tky = <req>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |DB error: { lx_err->get_text( ) }| )
          ) TO reported-routeconf.
          CONTINUE.
      ENDTRY.

      " Cập nhật request: LineStatus = APPROVED
      MODIFY ENTITIES OF zi_mm_route_conf IN LOCAL MODE
        ENTITY RouteConf
        UPDATE FIELDS ( LineStatus VersionNo ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky       = <req>-%tky
          LineStatus = 'APPROVED'
          VersionNo  = lv_new_version
          ChangedBy  = sy-uname
          ChangedAt  = lv_now
        ) ).

      " Trả kết quả
      APPEND VALUE #(
        %tky   = <req>-%tky
        %param = <req>
      ) TO result.

    ENDLOOP.
  ENDMETHOD.


  METHOD get_instance_features.
    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
        FIELDS ( LineStatus )
        WITH CORRESPONDING #( keys )
      RESULT DATA(entities).

    result = VALUE #( FOR entity IN entities
      LET lv_approve = COND #(
        WHEN entity-LineStatus = 'APPROVED'
        THEN if_abap_behv=>fc-o-disabled
        ELSE if_abap_behv=>fc-o-enabled )
      IN (
        %tky            = entity-%tky
        %action-approve = lv_approve
      ) ).
  ENDMETHOD.


  METHOD get_instance_authorizations.
    result = VALUE #( FOR key IN keys
      ( %tky    = key-%tky
        %update = if_abap_behv=>auth-allowed
        %delete = if_abap_behv=>auth-allowed
      ) ).
  ENDMETHOD.

ENDCLASS.
