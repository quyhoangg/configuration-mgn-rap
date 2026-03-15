CLASS lhc_limitconf DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR LimitConf RESULT result.

    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR LimitConf~set_defaults.

    METHODS validate_mandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR LimitConf~validate_mandatory.

    METHODS validate_business FOR VALIDATE ON SAVE
      IMPORTING keys FOR LimitConf~validate_business.

ENDCLASS.


CLASS lhc_limitconf IMPLEMENTATION.

  METHOD get_global_authorizations.
    result = VALUE #(
      %create = if_abap_behv=>auth-allowed
      %update = if_abap_behv=>auth-allowed
      %delete = if_abap_behv=>auth-allowed ).
  ENDMETHOD.


  METHOD set_defaults.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    MODIFY ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
      UPDATE FIELDS ( VersionNo ActionType Currency )
      WITH VALUE #(
        FOR r IN lt_data (
          %tky       = r-%tky
          VersionNo  = COND i(
                         WHEN r-VersionNo IS INITIAL THEN 1
                         ELSE r-VersionNo )
          ActionType = COND #(
                         WHEN r-ActionType IS INITIAL THEN 'CREATE'
                         ELSE r-ActionType )
          Currency   = COND #(
                         WHEN r-Currency IS INITIAL THEN 'VND'
                         ELSE r-Currency )
        )
      ).
  ENDMETHOD.


  METHOD validate_mandatory.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-EnvId IS INITIAL.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Environment ID is mandatory' )
                        %element-EnvId = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF <r>-ExpenseType IS INITIAL.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Expense Type is mandatory' )
                        %element-ExpenseType = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF <r>-GlAccount IS INITIAL.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'GL Account is mandatory' )
                        %element-GlAccount = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.

      IF <r>-AutoApprLim IS INITIAL OR <r>-AutoApprLim <= 0.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Auto Approval Limit must be > 0' )
                        %element-AutoApprLim = if_abap_behv=>mk-on
        ) TO reported-limitconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate_business.
    READ ENTITIES OF zi_fi_limit_conf IN LOCAL MODE
      ENTITY LimitConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).
      IF <r>-Currency IS NOT INITIAL AND
         <r>-Currency <> 'VND' AND
         <r>-Currency <> 'USD' AND
         <r>-Currency <> 'EUR'.
        APPEND VALUE #( %tky = <r>-%tky ) TO failed-limitconf.
        APPEND VALUE #( %tky = <r>-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = |Currency { <r>-Currency } is not supported. Use VND/USD/EUR.| )
        ) TO reported-limitconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
