 CLASS zcl_gsp26_rule_validator DEFINITION PUBLIC FINAL CREATE PUBLIC.                                                                                                                                 PUBLIC SECTION.
    TYPES: BEGIN OF ty_validation_error,                                                                                                                                                                           conf_id  TYPE zconfcatalog-conf_id,
               field    TYPE zconffielddef-field_name,
               message  TYPE string,
             END OF ty_validation_error,
             tt_validation_errors TYPE STANDARD TABLE OF ty_validation_error WITH EMPTY KEY.

      CLASS-METHODS check_catalog_existence IMPORTING iv_conf_id TYPE zconfcatalog-conf_id RETURNING VALUE(rv_exists) TYPE abap_bool.
      CLASS-METHODS check_catalog_active IMPORTING iv_conf_id TYPE zconfcatalog-conf_id RETURNING VALUE(rv_active) TYPE abap_bool.
      CLASS-METHODS check_required_fields IMPORTING iv_conf_id TYPE zconfcatalog-conf_id is_data TYPE any RETURNING VALUE(rt_errors) TYPE tt_validation_errors.

      CLASS-METHODS check_field_ranges IMPORTING iv_conf_id TYPE zconfcatalog-conf_id is_data TYPE any RETURNING VALUE(rt_errors) TYPE tt_validation_errors.

      CLASS-METHODS validate_request_item
        IMPORTING iv_conf_id       TYPE zconfcatalog-conf_id
                  iv_action        TYPE zde_action_type
                  iv_target_env_id TYPE zde_env_id
                  is_data          TYPE any OPTIONAL
        RETURNING VALUE(rt_errors) TYPE tt_validation_errors.
  ENDCLASS.

  CLASS zcl_gsp26_rule_validator IMPLEMENTATION.
    METHOD check_catalog_existence.
      SELECT SINGLE @abap_true FROM zconfcatalog WHERE conf_id = @iv_conf_id INTO @rv_exists.
    ENDMETHOD.

    METHOD check_catalog_active.
      SELECT SINGLE @abap_true FROM zconfcatalog WHERE conf_id = @iv_conf_id AND is_active = @abap_true INTO @rv_active.
    ENDMETHOD.

    METHOD check_required_fields.
      SELECT field_name, field_label FROM zconffielddef WHERE conf_id = @iv_conf_id AND is_required = @abap_true INTO TABLE @DATA(lt_required_fields).
      IF lt_required_fields IS INITIAL. RETURN. ENDIF.

      DATA lo_struct TYPE REF TO cl_abap_structdescr.
      lo_struct ?= cl_abap_typedescr=>describe_by_data( is_data ).
      LOOP AT lt_required_fields INTO DATA(ls_field).
        READ TABLE lo_struct->components WITH KEY name = to_upper( ls_field-field_name ) TRANSPORTING NO FIELDS.
        IF sy-subrc <> 0. CONTINUE. ENDIF.
        ASSIGN COMPONENT ls_field-field_name OF STRUCTURE is_data TO FIELD-SYMBOL(<value>).
        IF sy-subrc = 0 AND <value> IS INITIAL.
          APPEND VALUE #( conf_id = iv_conf_id field = ls_field-field_name message = |Field '{ ls_field-field_label }' is required| ) TO rt_errors.
        ENDIF.
      ENDLOOP.
    ENDMETHOD.

    METHOD check_field_ranges.
      SELECT field_name, min_val, max_val, field_label FROM zconffielddef WHERE conf_id = @iv_conf_id AND ( min_val IS NOT INITIAL OR max_val IS NOT INITIAL ) INTO TABLE @DATA(lt_range).
      IF lt_range IS INITIAL. RETURN. ENDIF.

      LOOP AT lt_range INTO DATA(ls_range).
        ASSIGN COMPONENT ls_range-field_name OF STRUCTURE is_data TO FIELD-SYMBOL(<r_val>).
        IF sy-subrc = 0 AND <r_val> IS NOT INITIAL.
          IF ( ls_range-min_val IS NOT INITIAL AND <r_val> < ls_range-min_val ) OR
             ( ls_range-max_val IS NOT INITIAL AND <r_val> > ls_range-max_val ).
            APPEND VALUE #( conf_id = iv_conf_id field = ls_range-field_name
                            message = |Trường '{ ls_range-field_label }' nằm ngoài vùng cho phép ({ ls_range-min_val } - { ls_range-max_val })| ) TO rt_errors.
          ENDIF.
        ENDIF.
      ENDLOOP.
    ENDMETHOD.

    METHOD validate_request_item.
      " Gộp 2 SELECT thành 1 — tránh N+1 query khi approve nhiều items
      SELECT SINGLE is_active FROM zconfcatalog
        WHERE conf_id = @iv_conf_id
        INTO @DATA(lv_is_active).

      IF sy-subrc <> 0.
        APPEND VALUE #( conf_id = iv_conf_id message = 'Configuration ID does not exist in catalog' ) TO rt_errors. RETURN.
      ENDIF.
      IF lv_is_active <> abap_true.
        APPEND VALUE #( conf_id = iv_conf_id message = 'Configuration is not active' ) TO rt_errors.
      ENDIF.
      IF iv_action IS INITIAL.
        APPEND VALUE #( conf_id = iv_conf_id field = 'ACTION' message = 'Action is required' ) TO rt_errors.
      ENDIF.
      IF iv_target_env_id IS INITIAL.
        APPEND VALUE #( conf_id = iv_conf_id field = 'TARGET_ENV_ID' message = 'Target Environment is required' ) TO rt_errors.
      ENDIF.

      IF is_data IS SUPPLIED AND is_data IS NOT INITIAL.
        DATA(lt_req_err) = check_required_fields( iv_conf_id = iv_conf_id is_data = is_data ).
        APPEND LINES OF lt_req_err TO rt_errors.

        DATA(lt_rng_err) = check_field_ranges( iv_conf_id = iv_conf_id is_data = is_data ).
        APPEND LINES OF lt_rng_err TO rt_errors.
      ENDIF.
    ENDMETHOD.
  ENDCLASS.
