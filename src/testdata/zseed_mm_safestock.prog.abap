*&---------------------------------------------------------------------*
*& Report zseed_mm_safestock
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zseed_mm_safe_stock.

DATA: lv_ts       TYPE timestampl,
      lv_item1    TYPE sysuuid_x16,
      lv_item2    TYPE sysuuid_x16,
      lv_item3    TYPE sysuuid_x16,
      lv_req_id   TYPE sysuuid_x16.

START-OF-SELECTION.

  GET TIME STAMP FIELD lv_ts.

" ======================================================================
" BƯỚC 1 — Seed bảng chính ZMMSAFESTOCK (dữ liệu đã approved/live)
" ======================================================================
  DELETE FROM zmmsafestock.
  DELETE FROM zmmsafestock_req.

  TRY.
      lv_item1 = cl_system_uuid=>create_uuid_x16_static( ).
      lv_item2 = cl_system_uuid=>create_uuid_x16_static( ).
      lv_item3 = cl_system_uuid=>create_uuid_x16_static( ).

      DATA lt_main TYPE STANDARD TABLE OF zmmsafestock.
      lt_main = VALUE #(
        ( client     = sy-mandt  item_id    = lv_item1
          env_id     = 'DEV'     plant_id   = 'PLANT1001'
          mat_group  = 'ROHEM'   min_qty    = 500
          version_no = 1         created_by = sy-uname
          created_at = lv_ts     changed_by = sy-uname
          changed_at = lv_ts )

        ( client     = sy-mandt  item_id    = lv_item2
          env_id     = 'DEV'     plant_id   = 'PLANT1002'
          mat_group  = 'FGOOD'   min_qty    = 200
          version_no = 1         created_by = sy-uname
          created_at = lv_ts     changed_by = sy-uname
          changed_at = lv_ts )

        ( client     = sy-mandt  item_id    = lv_item3
          env_id     = 'QAS'     plant_id   = 'PLANT2001'
          mat_group  = 'ROHEM'   min_qty    = 1000
          version_no = 2         created_by = sy-uname
          created_at = lv_ts     changed_by = sy-uname
          changed_at = lv_ts )
      ).

      INSERT zmmsafestock FROM TABLE @lt_main.
      IF sy-subrc = 0.
        COMMIT WORK.
        WRITE: / |[OK] Seeded { lines( lt_main ) } row(s) into ZMMSAFESTOCK.|.
      ELSE.
        ROLLBACK WORK.
        WRITE: / '[FAIL] Insert ZMMSAFESTOCK failed.'. RETURN.
      ENDIF.

    CATCH cx_uuid_error INTO DATA(lx1).
      WRITE: / |UUID error: { lx1->get_text( ) }|. RETURN.
  ENDTRY.

" ======================================================================
" BƯỚC 1b — Tạo REQ entry APPROVED cho mỗi bản ghi bảng chính
"           → Để UI hiện dữ liệu bảng chính, old_* = giá trị hiện tại
"           → Dev dùng để so sánh khi tạo request UPDATE/DELETE
" ======================================================================
  TRY.
      lv_req_id = cl_system_uuid=>create_uuid_x16_static( ).

      DATA lt_req TYPE STANDARD TABLE OF zmmsafestock_req.
      lt_req = VALUE #(

        " APPROVED 1: mirror của PLANT1001 trong bảng chính
        ( client         = sy-mandt
          req_id         = lv_req_id
          req_item_id    = cl_system_uuid=>create_uuid_x16_static( )
          item_id        = cl_system_uuid=>create_uuid_x16_static( )
          source_item_id = lv_item1   " trỏ về bảng chính
          conf_id        = lv_item1   " ID đã confirmed
          action_type    = 'CREATE'
          " old_* = giá trị hiện tại (lần đầu tạo nên old = current)
          old_env_id     = 'DEV'      old_plant_id   = 'PLANT1001'
          old_mat_group  = 'ROHEM'    old_min_qty    = 500
          old_version_no = 1
          " current values
          env_id         = 'DEV'      plant_id       = 'PLANT1001'
          mat_group      = 'ROHEM'    min_qty        = 500
          version_no     = 1
          line_status    = 'APPROVED'
          change_note    = 'Khởi tạo cấu hình Plant 1001'
          created_by     = sy-uname   created_at     = lv_ts
          changed_by     = sy-uname   changed_at     = lv_ts )

        " APPROVED 2: mirror của PLANT1002
        ( client         = sy-mandt
          req_id         = lv_req_id
          req_item_id    = cl_system_uuid=>create_uuid_x16_static( )
          item_id        = cl_system_uuid=>create_uuid_x16_static( )
          source_item_id = lv_item2
          conf_id        = lv_item2
          action_type    = 'CREATE'
          old_env_id     = 'DEV'      old_plant_id   = 'PLANT1002'
          old_mat_group  = 'FGOOD'    old_min_qty    = 200
          old_version_no = 1
          env_id         = 'DEV'      plant_id       = 'PLANT1002'
          mat_group      = 'FGOOD'    min_qty        = 200
          version_no     = 1
          line_status    = 'APPROVED'
          change_note    = 'Khởi tạo cấu hình Plant 1002'
          created_by     = sy-uname   created_at     = lv_ts
          changed_by     = sy-uname   changed_at     = lv_ts )

        " APPROVED 3: mirror của PLANT2001
        ( client         = sy-mandt
          req_id         = lv_req_id
          req_item_id    = cl_system_uuid=>create_uuid_x16_static( )
          item_id        = cl_system_uuid=>create_uuid_x16_static( )
          source_item_id = lv_item3
          conf_id        = lv_item3
          action_type    = 'CREATE'
          old_env_id     = 'QAS'      old_plant_id   = 'PLANT2001'
          old_mat_group  = 'ROHEM'    old_min_qty    = 1000
          old_version_no = 2
          env_id         = 'QAS'      plant_id       = 'PLANT2001'
          mat_group      = 'ROHEM'    min_qty        = 1000
          version_no     = 2
          line_status    = 'APPROVED'
          change_note    = 'Khởi tạo cấu hình Plant 2001'
          created_by     = sy-uname   created_at     = lv_ts
          changed_by     = sy-uname   changed_at     = lv_ts )

" ======================================================================
" BƯỚC 2 — Tạo PENDING request để test luồng Maker-Checker
"          old_* lấy từ bảng chính → dev thấy rõ đang thay đổi gì
" ======================================================================

        " PENDING 1: CREATE mới Plant 1003 (chưa có trong bảng chính)
        ( client      = sy-mandt
          req_id      = lv_req_id
          req_item_id = cl_system_uuid=>create_uuid_x16_static( )
          item_id     = cl_system_uuid=>create_uuid_x16_static( )
          action_type = 'CREATE'
          env_id      = 'DEV'         plant_id    = 'PLANT1003'
          mat_group   = 'ROHEM'       min_qty     = 300
          version_no  = 1
          line_status = ''
          change_note = 'Tạo mới cấu hình cho Plant 1003'
          created_by  = sy-uname      created_at  = lv_ts
          changed_by  = sy-uname      changed_at  = lv_ts )

        " PENDING 2: UPDATE Plant 1001 — tăng MinQty 500 → 750
        "            old_* = snapshot từ bảng chính để dev so sánh
        ( client         = sy-mandt
          req_id         = lv_req_id
          req_item_id    = cl_system_uuid=>create_uuid_x16_static( )
          item_id        = cl_system_uuid=>create_uuid_x16_static( )
          source_item_id = lv_item1   conf_id        = lv_item1
          action_type    = 'UPDATE'
          old_env_id     = 'DEV'      old_plant_id   = 'PLANT1001'
          old_mat_group  = 'ROHEM'    old_min_qty    = 500
          old_version_no = 1
          env_id         = 'DEV'      plant_id       = 'PLANT1001'
          mat_group      = 'ROHEM'    min_qty        = 750
          version_no     = 1
          line_status    = ''
          change_note    = 'Tăng MinQty từ 500 lên 750'
          created_by     = sy-uname   created_at     = lv_ts
          changed_by     = sy-uname   changed_at     = lv_ts )

        " PENDING 3: DELETE Plant 1002
        ( client         = sy-mandt
          req_id         = lv_req_id
          req_item_id    = cl_system_uuid=>create_uuid_x16_static( )
          item_id        = cl_system_uuid=>create_uuid_x16_static( )
          source_item_id = lv_item2   conf_id        = lv_item2
          action_type    = 'DELETE'
          old_env_id     = 'DEV'      old_plant_id   = 'PLANT1002'
          old_mat_group  = 'FGOOD'    old_min_qty    = 200
          old_version_no = 1
          env_id         = 'DEV'      plant_id       = 'PLANT1002'
          mat_group      = 'FGOOD'    min_qty        = 200
          version_no     = 1
          line_status    = ''
          change_note    = 'Xoá cấu hình Plant 1002'
          created_by     = sy-uname   created_at     = lv_ts
          changed_by     = sy-uname   changed_at     = lv_ts )
      ).

      INSERT zmmsafestock_req FROM TABLE @lt_req.
      IF sy-subrc = 0.
        COMMIT WORK.
        WRITE: / |[OK] Seeded { lines( lt_req ) } row(s) into ZMMSAFESTOCK_REQ.|.
      ELSE.
        ROLLBACK WORK.
        WRITE: / '[FAIL] Insert ZMMSAFESTOCK_REQ failed.'. RETURN.
      ENDIF.

    CATCH cx_uuid_error INTO DATA(lx2).
      WRITE: / |UUID error: { lx2->get_text( ) }|. RETURN.
  ENDTRY.

  WRITE: / ''.
  WRITE: / '=== Seed hoàn tất ==='.
  WRITE: / '  3 dòng APPROVED  : mirror dữ liệu bảng chính (Plant1001/1002/2001)'.
  WRITE: / '  3 dòng PENDING   : request chờ approve (CREATE/UPDATE/DELETE)'.
  WRITE: / '  → Mở ZUI_MM_SAFE_STOCK → Preview → thấy 6 dòng.'.
