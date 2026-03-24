CLASS lhc_Catalog DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR Catalog RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations FOR Catalog RESULT result.

    METHODS validateModuleId FOR VALIDATE ON SAVE
      IMPORTING keys FOR Catalog~validateModuleId.

    METHODS validateTargetTable FOR VALIDATE ON SAVE
      IMPORTING keys FOR Catalog~validateTargetTable.

ENDCLASS.

CLASS lhc_Catalog IMPLEMENTATION.

  METHOD get_global_authorizations.
    DATA lv_role TYPE c LENGTH 20.
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id  = @sy-uname
        AND is_active = @abap_true
      INTO @lv_role.

    DATA(lv_auth_create) = COND #(
      WHEN lv_role = 'IT ADMIN'
      THEN if_abap_behv=>auth-allowed
      ELSE if_abap_behv=>auth-unauthorized ).

    result-%create = lv_auth_create.
  ENDMETHOD.

  METHOD get_instance_authorizations.
    DATA lv_role TYPE c LENGTH 20.
    SELECT SINGLE role_level FROM zuserrole
      WHERE user_id  = @sy-uname
        AND is_active = @abap_true
      INTO @lv_role.

    DATA(lv_auth_edit) = COND #(
      WHEN lv_role = 'IT ADMIN'
      THEN if_abap_behv=>auth-allowed
      ELSE if_abap_behv=>auth-unauthorized ).

    LOOP AT keys INTO DATA(key).
      APPEND VALUE #(
        %tky         = key-%tky
        %update      = lv_auth_edit
        %delete      = lv_auth_edit
        %action-Edit = lv_auth_edit
      ) TO result.
    ENDLOOP.
  ENDMETHOD.

  METHOD validateModuleId.

    READ ENTITIES OF zi_conf_catalog IN LOCAL MODE
      ENTITY Catalog
      FIELDS ( ModuleId ConfName )
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_catalog).

    LOOP AT lt_catalog INTO DATA(ls_catalog).

      IF ls_catalog-ModuleId IS INITIAL.
        APPEND VALUE #(
          %tky = ls_catalog-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Module is required' )
          %element-ModuleId = if_abap_behv=>mk-on
        ) TO reported-catalog.

        APPEND VALUE #( %tky = ls_catalog-%tky ) TO failed-catalog.
        CONTINUE.
      ENDIF.

      SELECT SINGLE moduleid
        FROM zi_vh_module
        WHERE moduleid = @ls_catalog-ModuleId
        INTO @DATA(lv_module).

      IF sy-subrc <> 0.
        APPEND VALUE #(
          %tky = ls_catalog-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Invalid Module ID: { ls_catalog-ModuleId }| )
          %element-ModuleId = if_abap_behv=>mk-on
        ) TO reported-catalog.

        APPEND VALUE #( %tky = ls_catalog-%tky ) TO failed-catalog.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validateTargetTable.

    READ ENTITIES OF zi_conf_catalog IN LOCAL MODE
      ENTITY Catalog
      FIELDS ( ConfId TargetCds ModuleId ConfName )
      WITH CORRESPONDING #( keys )
      RESULT DATA(lt_catalog).

    LOOP AT lt_catalog INTO DATA(ls_catalog).

      IF ls_catalog-TargetCds IS INITIAL.
        APPEND VALUE #(
          %tky = ls_catalog-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Target CDS is required' )
          %element-TargetCds = if_abap_behv=>mk-on
        ) TO reported-catalog.

        APPEND VALUE #( %tky = ls_catalog-%tky ) TO failed-catalog.
        CONTINUE.
      ENDIF.

      "Check duplicate target cds in other catalog
      SELECT SINGLE conf_id
        FROM zconfcatalog
        WHERE target_cds = @ls_catalog-TargetCds
          AND conf_id   <> @ls_catalog-ConfId
        INTO @DATA(lv_other_conf).

      IF sy-subrc = 0.
        APPEND VALUE #(
          %tky = ls_catalog-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |Target CDS { ls_catalog-TargetCds } is already assigned to another catalog| )
          %element-TargetCds = if_abap_behv=>mk-on
        ) TO reported-catalog.

        APPEND VALUE #( %tky = ls_catalog-%tky ) TO failed-catalog.
      ENDIF.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.
