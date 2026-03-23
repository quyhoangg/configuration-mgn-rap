CLASS zcl_gsp26_rule_snapshot DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.

    TYPES: BEGIN OF ty_restore_result,
             success    TYPE abap_bool,
             message    TYPE string,
             table_name TYPE c LENGTH 30,
           END OF ty_restore_result.
    TYPES tt_restore_results TYPE STANDARD TABLE OF ty_restore_result WITH EMPTY KEY.

    CLASS-METHODS create_price_snapshot
      IMPORTING is_price_data TYPE zsd_price_conf.

    CLASS-METHODS restore_from_snapshot
      IMPORTING iv_req_id     TYPE sysuuid_x16
                iv_changed_by TYPE syuname
      RETURNING VALUE(rt_results) TYPE tt_restore_results.

    CLASS-METHODS create_approve_snapshot
      IMPORTING iv_req_id     TYPE sysuuid_x16
                iv_changed_by TYPE syuname
      RETURNING VALUE(rt_results) TYPE tt_restore_results.

    CLASS-METHODS increment_version
      IMPORTING iv_req_id TYPE sysuuid_x16
      RETURNING VALUE(rt_results) TYPE tt_restore_results.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.

CLASS zcl_gsp26_rule_snapshot IMPLEMENTATION.

  METHOD create_price_snapshot.
    INSERT zsd_price_conf FROM is_price_data.
  ENDMETHOD.

  METHOD increment_version.

    " 1) Increment VERSION_NO for ZSD_PRICE_CONF
    SELECT MAX( version_no ) FROM zsd_price_conf
      WHERE req_id = @iv_req_id
      INTO @DATA(lv_max_price_ver).

    IF sy-subrc = 0.
      DATA(lv_new_price_ver) = lv_max_price_ver + 1.
      UPDATE zsd_price_conf
        SET version_no = @lv_new_price_ver
        WHERE req_id = @iv_req_id.

      IF sy-dbcnt > 0.
        APPEND VALUE #( success    = abap_true
                        message    = |SD Price version incremented to { lv_new_price_ver }|
                        table_name = 'ZSD_PRICE_CONF' )
          TO rt_results.
      ENDIF.
    ENDIF.

    " 2) Increment VERSION_NO for ZMMSAFESTOCK
    SELECT MAX( version_no ) FROM zmmsafestock
      WHERE req_id = @iv_req_id
      INTO @DATA(lv_max_stock_ver).

    IF sy-subrc = 0.
      DATA(lv_new_stock_ver) = lv_max_stock_ver + 1.
      UPDATE zmmsafestock
        SET version_no = @lv_new_stock_ver
        WHERE req_id = @iv_req_id.

      IF sy-dbcnt > 0.
        APPEND VALUE #( success    = abap_true
                        message    = |MM Safe Stock version incremented to { lv_new_stock_ver }|
                        table_name = 'ZMMSAFESTOCK' )
          TO rt_results.
      ENDIF.
    ENDIF.

    IF rt_results IS INITIAL.
      APPEND VALUE #( success    = abap_false
                      message    = 'No config records found to version' )
        TO rt_results.
    ENDIF.

  ENDMETHOD.

  METHOD create_approve_snapshot.
      DATA lt_logs TYPE STANDARD TABLE OF zauditlog.
      DATA ls_log TYPE zauditlog.

      " 1) Snapshot ZSD_PRICE_CONF records
      SELECT * FROM zsd_price_conf
        WHERE req_id = @iv_req_id
        INTO TABLE @DATA(lt_price).

      LOOP AT lt_price INTO DATA(ls_price).
        CLEAR ls_log.
        TRY.
            ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            CONTINUE.
        ENDTRY.
        ls_log-req_id      = iv_req_id.
        ls_log-conf_id     = ls_price-item_id.
        ls_log-module_id   = 'SD'.
        ls_log-action_type = 'APPROVE'.
        ls_log-table_name  = 'ZSD_PRICE_CONF'.
        ls_log-env_id      = ls_price-env_id.
        ls_log-object_key  = ls_price-item_id.
        ls_log-changed_by  = iv_changed_by.
        GET TIME STAMP FIELD ls_log-changed_at.
        APPEND ls_log TO lt_logs.
      ENDLOOP.

      IF lt_price IS NOT INITIAL.
        APPEND VALUE #( success    = abap_true
                        message    = 'SD Price snapshot created'
                        table_name = 'ZSD_PRICE_CONF' )
          TO rt_results.
      ENDIF.

      " 2) Snapshot ZMMSAFESTOCK records
      SELECT * FROM zmmsafestock
        WHERE req_id = @iv_req_id
        INTO TABLE @DATA(lt_stock).

      LOOP AT lt_stock INTO DATA(ls_stock).
        CLEAR ls_log.
        TRY.
            ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
          CATCH cx_uuid_error.
            CONTINUE.
        ENDTRY.
        ls_log-req_id      = iv_req_id.
        ls_log-conf_id     = ls_stock-item_id.
        ls_log-module_id   = 'MM'.
        ls_log-action_type = 'APPROVE'.
        ls_log-table_name  = 'ZMMSAFESTOCK'.
        ls_log-env_id      = ls_stock-env_id.
        ls_log-object_key  = ls_stock-item_id.
        ls_log-changed_by  = iv_changed_by.
        GET TIME STAMP FIELD ls_log-changed_at.
        APPEND ls_log TO lt_logs.
      ENDLOOP.

      IF lt_stock IS NOT INITIAL.
        APPEND VALUE #( success    = abap_true
                        message    = 'MM Safe Stock snapshot created'
                        table_name = 'ZMMSAFESTOCK' )
          TO rt_results.
      ENDIF.

      " Batch INSERT — 1 lần thay vì từng dòng
      IF lt_logs IS NOT INITIAL.
        INSERT zauditlog FROM TABLE @lt_logs.
      ENDIF.

      IF rt_results IS INITIAL.
        APPEND VALUE #( success    = abap_false
                        message    = 'No config data found for request' )
          TO rt_results.
      ENDIF.

    ENDMETHOD.
  METHOD restore_from_snapshot.

    DATA ls_log TYPE zauditlog.

    SELECT log_id, req_id, conf_id, module_id,
           action_type, table_name,
           old_data, new_data,
           env_id, object_key
      FROM zauditlog
      WHERE req_id = @iv_req_id
        AND ( action_type = 'PROMOTE' OR action_type = 'APPROVE' )
      INTO TABLE @DATA(lt_snapshots).

    IF lt_snapshots IS INITIAL.
      APPEND VALUE #( success = abap_false
                      message = 'No snapshot found for this request' )
        TO rt_results.
      RETURN.
    ENDIF.

    LOOP AT lt_snapshots INTO DATA(ls_snap).

            CASE ls_snap-table_name.
        WHEN 'ZSD_PRICE_CONF'.
          DATA ls_price TYPE zsd_price_conf.
          IF ls_snap-old_data IS NOT INITIAL.
            /ui2/cl_json=>deserialize( EXPORTING json = ls_snap-old_data CHANGING data = ls_price ).
            MODIFY zsd_price_conf FROM @ls_price.
            APPEND VALUE #( success    = abap_true
                            message    = 'SD Price Config restored'
                            table_name = 'ZSD_PRICE_CONF' ) TO rt_results.
          ELSE.
            DELETE FROM zsd_price_conf WHERE item_id = @ls_snap-object_key.
            APPEND VALUE #( success    = abap_true
                            message    = 'SD Price Config deleted (rollback create)'
                            table_name = 'ZSD_PRICE_CONF' ) TO rt_results.
          ENDIF.

        WHEN 'ZMMSAFESTOCK'.
          DATA ls_stock TYPE zmmsafestock.
          IF ls_snap-old_data IS NOT INITIAL.
            /ui2/cl_json=>deserialize( EXPORTING json = ls_snap-old_data CHANGING data = ls_stock ).
            MODIFY zmmsafestock FROM @ls_stock.
            APPEND VALUE #( success    = abap_true
                            message    = 'MM Safe Stock restored'
                            table_name = 'ZMMSAFESTOCK' ) TO rt_results.
          ELSE.
            DELETE FROM zmmsafestock WHERE item_id = @ls_snap-object_key.
            APPEND VALUE #( success    = abap_true
                            message    = 'MM Safe Stock deleted (rollback create)'
                            table_name = 'ZMMSAFESTOCK' ) TO rt_results.
          ENDIF.

        WHEN 'ZFILIMITCONF'.
          DATA ls_limit TYPE zfilimitconf.
          IF ls_snap-old_data IS NOT INITIAL.
            /ui2/cl_json=>deserialize( EXPORTING json = ls_snap-old_data CHANGING data = ls_limit ).
            MODIFY zfilimitconf FROM @ls_limit.
            APPEND VALUE #( success    = abap_true
                            message    = 'FI Limit restored'
                            table_name = 'ZFILIMITCONF' ) TO rt_results.
          ELSE.
            DELETE FROM zfilimitconf WHERE item_id = @ls_snap-object_key.
            APPEND VALUE #( success    = abap_true
                            message    = 'FI Limit deleted (rollback create)'
                            table_name = 'ZFILIMITCONF' ) TO rt_results.
          ENDIF.

        WHEN 'ZMMROUTECONF'.
          DATA ls_route TYPE zmmrouteconf.
          IF ls_snap-old_data IS NOT INITIAL.
            /ui2/cl_json=>deserialize( EXPORTING json = ls_snap-old_data CHANGING data = ls_route ).
            MODIFY zmmrouteconf FROM @ls_route.
            APPEND VALUE #( success    = abap_true
                            message    = 'MM Route Config restored'
                            table_name = 'ZMMROUTECONF' ) TO rt_results.
          ELSE.
            DELETE FROM zmmrouteconf WHERE item_id = @ls_snap-object_key.
            APPEND VALUE #( success    = abap_true
                            message    = 'MM Route Config deleted (rollback create)'
                            table_name = 'ZMMROUTECONF' ) TO rt_results.
          ENDIF.

        WHEN OTHERS.
          APPEND VALUE #( success    = abap_false
                          message    = 'Unknown table'
                          table_name = ls_snap-table_name )
            TO rt_results.
      ENDCASE.


      CLEAR ls_log.
      TRY.
          ls_log-log_id = cl_system_uuid=>create_uuid_x16_static( ).
        CATCH cx_uuid_error.
          CONTINUE.
      ENDTRY.
      ls_log-req_id      = iv_req_id.
      ls_log-conf_id     = ls_snap-conf_id.
      ls_log-module_id   = ls_snap-module_id.
      ls_log-action_type = 'ROLLBACK'.
      ls_log-table_name  = ls_snap-table_name.
      ls_log-old_data    = ls_snap-new_data.
      ls_log-new_data    = ls_snap-old_data.
      ls_log-env_id      = ls_snap-env_id.
      ls_log-object_key  = ls_snap-object_key.
      ls_log-changed_by  = iv_changed_by.
      GET TIME STAMP FIELD ls_log-changed_at.
      INSERT zauditlog FROM @ls_log.

    ENDLOOP.

  ENDMETHOD.

ENDCLASS.

