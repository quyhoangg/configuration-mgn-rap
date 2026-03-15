CLASS lhc_RouteConf DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS get_global_authorizations FOR GLOBAL AUTHORIZATION
      IMPORTING REQUEST requested_authorizations FOR RouteConf RESULT result.

    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR RouteConf~set_defaults.

    METHODS validate_business FOR VALIDATE ON SAVE
      IMPORTING keys FOR RouteConf~validate_business.

    METHODS validate_mandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR RouteConf~validate_mandatory.

ENDCLASS.

CLASS lhc_RouteConf IMPLEMENTATION.

  METHOD get_global_authorizations.
    result = VALUE #(
      %create = if_abap_behv=>auth-allowed
      %update = if_abap_behv=>auth-allowed
      %delete = if_abap_behv=>auth-allowed ).
  ENDMETHOD.

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
                               WHEN <r>-ActionType IS INITIAL THEN 'CREATE'
                               ELSE <r>-ActionType ).

      MODIFY ENTITIES OF zi_mm_route_conf IN LOCAL MODE
        ENTITY RouteConf
        UPDATE FIELDS ( IsAllowed VersionNo ActionType )
        WITH VALUE #(
          (
            %tky       = <r>-%tky
            IsAllowed  = lv_is_allowed
            VersionNo  = lv_version_no
            ActionType = lv_action_type
          )
        ).

      IF lv_action_type = 'UPDATE' OR lv_action_type = 'DELETE'.

        IF <r>-SourceItemId IS INITIAL.
          CONTINUE.
        ENDIF.

        SELECT SINGLE *
          FROM zmmrouteconf
          WHERE item_id = @<r>-SourceItemId
          INTO @DATA(ls_src).

        IF sy-subrc <> 0.
          CONTINUE.
        ENDIF.

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
            EnvId
            PlantId
            SendWh
            ReceiveWh
            InspectorId
            TransMode
            IsAllowed
            VersionNo
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

                  EnvId           = ls_src-env_id
                  PlantId         = ls_src-plant_id
                  SendWh          = ls_src-send_wh
                  ReceiveWh       = ls_src-receive_wh
                  InspectorId     = ls_src-inspector_id
                  TransMode       = ls_src-trans_mode
                  IsAllowed       = ls_src-is_allowed
                  VersionNo       = ls_src-version_no
            )
          ).

      ENDIF.

    ENDLOOP.

  ENDMETHOD.

  METHOD validate_mandatory.

    READ ENTITIES OF zi_mm_route_conf IN LOCAL MODE
      ENTITY RouteConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_data).

    LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).

      IF <r>-ActionType = 'CREATE'.
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

      IF ( <r>-ActionType = 'UPDATE' OR <r>-ActionType = 'DELETE' )
         AND <r>-SourceItemId IS INITIAL.

        APPEND VALUE #( %tky = <r>-%tky ) TO failed-RouteConf.

        APPEND VALUE #(
          %tky = <r>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = |SourceItemId is mandatory for UPDATE/DELETE.| ) )
          TO reported-RouteConf.
      ENDIF.

      IF ( <r>-ActionType = 'UPDATE' OR <r>-ActionType = 'DELETE' )
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

ENDCLASS.
