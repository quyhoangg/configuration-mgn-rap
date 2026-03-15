*&---------------------------------------------------------------------*
*& Report zseed_mm_route_conf
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zseed_mm_route_conf.

DATA: lt_data TYPE STANDARD TABLE OF zmmrouteconf,
      ls_data TYPE zmmrouteconf,
      lv_uuid TYPE sysuuid_x16.

DEFINE add_row.
  lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).

  CLEAR ls_data.
  ls_data-client       = sy-mandt.
  ls_data-item_id      = lv_uuid.
  ls_data-req_id       = ''.
  ls_data-env_id       = &1.
  ls_data-plant_id     = &2.
  ls_data-send_wh      = &3.
  ls_data-receive_wh   = &4.
  ls_data-inspector_id = &5.
  ls_data-trans_mode   = &6.
  ls_data-is_allowed   = &7.
  ls_data-version_no   = &8.
  ls_data-created_by   = sy-uname.
  GET TIME STAMP FIELD ls_data-created_at.
  ls_data-changed_by   = sy-uname.
  GET TIME STAMP FIELD ls_data-changed_at.

  APPEND ls_data TO lt_data.
END-OF-DEFINITION.

START-OF-SELECTION.

  DELETE FROM zmmrouteconf.

  add_row 'DEV'  'PLANT1001' 'WH-A01' 'WH-B01' 'DEV-056' 'TRUCK' 'X' 1.
  add_row 'DEV'  'PLANT1001' 'WH-A02' 'WH-B02' 'DEV-056' 'VAN'   'X' 1.
  add_row 'DEV'  'PLANT1002' 'WH-A01' 'WH-C01' 'DEV-056' 'SHIP'  ''  1.
  add_row 'TEST' 'PLANT2001' 'WH-T01' 'WH-T02' 'DEV-056' 'TRUCK' 'X' 1.
  add_row 'PRD'  'PLANT3001' 'WH-P01' 'WH-P02' 'DEV-056' 'AIR'   'X' 1.

  INSERT zmmrouteconf FROM TABLE @lt_data.

  IF sy-subrc = 0.
    COMMIT WORK.
    WRITE: / 'Table reset and seed completed:', lines( lt_data ), 'records.'.
  ELSE.
    ROLLBACK WORK.
    WRITE: / 'Seed failed.'.
  ENDIF.
