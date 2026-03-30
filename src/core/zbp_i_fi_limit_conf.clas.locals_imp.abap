CLASS lhc_LimitConf DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR LimitConf~set_defaults.

    METHODS setAdminFields FOR DETERMINE ON MODIFY
      IMPORTING keys FOR LimitConf~setAdminFields.

    METHODS validate_mandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR LimitConf~validate_mandatory.

    METHODS validate_business FOR VALIDATE ON SAVE
      IMPORTING keys FOR LimitConf~validate_business.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION LimitConf~approve RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features
      FOR LimitConf RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations
      FOR LimitConf RESULT result.

ENDCLASS.


CLASS lhc_LimitConf IMPLEMENTATION.

  METHOD set_defaults.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    " ── Phần 1: Set ActionType + VersionNo mặc định ──
    DATA lt_update_base TYPE TABLE FOR UPDATE zi_fi_limit_conf\\LimitConf.

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-ActionType IS NOT INITIAL AND <r>-VersionNo IS NOT INITIAL.
        " Đã có giá trị → bỏ qua
      ELSE.
        APPEND VALUE #(
          %tky       = <r>-%tky
          ActionType = COND #( WHEN <r>-ActionType IS INITIAL THEN 'C'
                               ELSE <r>-ActionType )
          VersionNo  = COND i( WHEN <r>-VersionNo IS INITIAL THEN 1
                               ELSE <r>-VersionNo )
        ) TO lt_update_base.
      ENDIF.
    ENDLOOP.

    IF lt_update_base IS NOT INITIAL.
      MODIFY ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
        ENTITY LimitConf
        UPDATE FIELDS ( ActionType VersionNo )
        WITH lt_update_base.
    ENDIF.

    " ── Phần 2: Load Old values cho UPDATE/DELETE ──
    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r2>).
      IF ( <r2>-ActionType = 'U' OR <r2>-ActionType = 'X' )
        AND <r2>-SourceItemId IS NOT INITIAL
        AND <r2>-OldEnvId IS INITIAL.

        SELECT SINGLE * FROM zfilimitconf
          WHERE item_id = @<r2>-SourceItemId
          INTO @DATA(ls_src).

        CHECK sy-subrc = 0.

        MODIFY ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
          ENTITY LimitConf
          UPDATE FIELDS ( OldEnvId OldExpenseType OldGlAccount
                          OldAutoApprLim OldCurrency OldVersionNo
                          EnvId ExpenseType GlAccount
                          AutoApprLim Currency VersionNo )
          WITH VALUE #( (
            %tky           = <r2>-%tky
            OldEnvId       = ls_src-env_id
            OldExpenseType = ls_src-expense_type
            OldGlAccount   = ls_src-gl_account
            OldAutoApprLim = ls_src-auto_appr_lim
            OldCurrency    = ls_src-currency
            OldVersionNo   = ls_src-version_no
            EnvId          = ls_src-env_id
            ExpenseType    = ls_src-expense_type
            GlAccount      = ls_src-gl_account
            AutoApprLim    = ls_src-auto_appr_lim
            Currency       = ls_src-currency
            VersionNo      = ls_src-version_no
          ) ).

      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD setAdminFields.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
        FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
        WITH CORRESPONDING #( keys )
      RESULT DATA(entities).

    DATA lt_update TYPE TABLE FOR UPDATE zi_fi_limit_conf\\LimitConf.

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
      MODIFY ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
        ENTITY LimitConf
          UPDATE FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
          WITH lt_update
        REPORTED DATA(update_reported).
      reported = CORRESPONDING #( DEEP update_reported ).
    ENDIF.
  ENDMETHOD.


  METHOD validate_mandatory.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
        FIELDS ( EnvId ExpenseType GlAccount AutoApprLim )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    LOOP AT lt_entities INTO DATA(entity).
      IF entity-EnvId IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = entity-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Environment ID is mandatory' )
          %element-EnvId = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF entity-ExpenseType IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = entity-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Expense Type is mandatory' )
          %element-ExpenseType = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF entity-GlAccount IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = entity-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'G/L Account is mandatory' )
          %element-GlAccount = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF entity-AutoApprLim IS INITIAL OR entity-AutoApprLim <= 0.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = entity-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Auto Approval Limit must be greater than 0' )
          %element-AutoApprLim = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate_business.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
        FIELDS ( Currency )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    LOOP AT lt_entities INTO DATA(entity).
      IF entity-Currency IS NOT INITIAL
        AND entity-Currency <> 'VND'
        AND entity-Currency <> 'USD'
        AND entity-Currency <> 'EUR'.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = entity-%tky
          %msg = new_message_with_text(
            severity = if_abap_behv_message=>severity-error
            text     = 'Currency must be VND, USD or EUR' )
          %element-Currency = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD approve.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    LOOP AT lt_reqs ASSIGNING FIELD-SYMBOL(<req>).

      IF <req>-LineStatus = 'APPROVED'.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-limitconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'This record is already approved.' )
        ) TO reported-limitconf.
        CONTINUE.
      ENDIF.

      IF <req>-EnvId IS INITIAL OR <req>-ExpenseType IS INITIAL OR
         <req>-GlAccount IS INITIAL.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-limitconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Cannot approve: EnvId/ExpenseType/GlAccount missing.' )
        ) TO reported-limitconf.
        CONTINUE.
      ENDIF.

      DATA(lv_new_version) = COND i(
        WHEN <req>-OldVersionNo IS NOT INITIAL THEN <req>-OldVersionNo + 1
        ELSE 1 ).

      DATA(ls_conf) = VALUE zfilimitconf(
        client        = sy-mandt
        item_id       = COND #(
                          WHEN <req>-ConfId IS NOT INITIAL
                          THEN <req>-ConfId
                          ELSE <req>-ItemId )
        req_id        = <req>-ReqId
        env_id        = <req>-EnvId
        expense_type  = <req>-ExpenseType
        gl_account    = <req>-GlAccount
        auto_appr_lim = <req>-AutoApprLim
        currency      = <req>-Currency
        version_no    = lv_new_version
        created_by    = COND #(
                          WHEN <req>-ActionType = 'C'
                          THEN sy-uname
                          ELSE <req>-CreatedBy )
        created_at    = COND #(
                          WHEN <req>-ActionType = 'C'
                          THEN lv_now
                          ELSE <req>-CreatedAt )
        changed_by    = sy-uname
        changed_at    = lv_now
      ).

            " Lấy dữ liệu CŨ trước khi thay đổi để làm Rollback Snapshot
      DATA ls_old_limit TYPE zfilimitconf.
      CLEAR ls_old_limit.
      IF <req>-ActionType = 'U' OR <req>-ActionType = 'X'.
        SELECT SINGLE * FROM zfilimitconf WHERE item_id = @ls_conf-item_id INTO @ls_old_limit.
      ENDIF.

      TRY.
          " Ghi log audit snapshot (serialize JSON tự động)
          zcl_gsp26_rule_writer=>log_audit_entry(
            iv_conf_id  = ls_conf-item_id
            iv_req_id   = <req>-ReqId
            iv_mod_id   = 'FI'
            iv_act_type = 'APPROVE'
            iv_tab_name = 'ZFILIMITCONF'
            iv_env_id   = <req>-EnvId
            is_old_data = ls_old_limit
            is_new_data = ls_conf ).
        CATCH cx_root.
      ENDTRY.

      " 6. Xử lý theo ActionType

      TRY.
          CASE <req>-ActionType.

            WHEN 'X'.
              DELETE FROM zfilimitconf
                WHERE item_id = @ls_conf-item_id.

              IF sy-subrc <> 0.
                APPEND VALUE #(
                  %tky = <req>-%tky
                  %msg = new_message_with_text(
                           severity = if_abap_behv_message=>severity-warning
                           text     = 'Record not found in config table.' )
                ) TO reported-limitconf.
              ENDIF.

            WHEN OTHERS.
              SELECT SINGLE @abap_true
                FROM zfilimitconf
                WHERE item_id = @ls_conf-item_id
                INTO @DATA(lv_exists).

              IF lv_exists = abap_true.
                UPDATE zfilimitconf SET
                  req_id        = @ls_conf-req_id,
                  env_id        = @ls_conf-env_id,
                  expense_type  = @ls_conf-expense_type,
                  gl_account    = @ls_conf-gl_account,
                  auto_appr_lim = @ls_conf-auto_appr_lim,
                  currency      = @ls_conf-currency,
                  version_no    = @ls_conf-version_no,
                  changed_by    = @ls_conf-changed_by,
                  changed_at    = @ls_conf-changed_at
                  WHERE item_id = @ls_conf-item_id.
              ELSE.
                INSERT zfilimitconf FROM @ls_conf.
              ENDIF.

          ENDCASE.

        CATCH cx_root INTO DATA(lx_err).
          APPEND VALUE #( %tky = <req>-%tky ) TO failed-limitconf.
          APPEND VALUE #(
            %tky = <req>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |DB error: { lx_err->get_text( ) }| )
          ) TO reported-limitconf.
          CONTINUE.
      ENDTRY.

      MODIFY ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
        ENTITY LimitConf
        UPDATE FIELDS ( LineStatus VersionNo ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky       = <req>-%tky
          LineStatus = 'APPROVED'
          VersionNo  = lv_new_version
          ChangedBy  = sy-uname
          ChangedAt  = lv_now
        ) ).

      APPEND VALUE #(
        %tky   = <req>-%tky
        %param = <req>
      ) TO result.

    ENDLOOP.
  ENDMETHOD.


  METHOD get_instance_features.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
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
