*&---------------------------------------------------------------------*
*& Report ZSEED_MANAGER_TEST
*&---------------------------------------------------------------------*
REPORT zseed_manager_test.

DATA: lt_header  TYPE STANDARD TABLE OF zconfreqh,
      lt_items   TYPE STANDARD TABLE OF zconfreqi,
      lv_ts      TYPE timestampl.

GET TIME STAMP FIELD lv_ts.

" 1. LẤY DANH SÁCH CONF_ID ĐANG CÓ TRONG CATALOG CỦA BẠN
SELECT conf_id FROM zconfcatalog INTO TABLE @DATA(lt_cat_ids).

IF lt_cat_ids IS INITIAL.
   WRITE: / 'Lỗi: Bảng Catalog đang trống, vui lòng kiểm tra lại!'.
   RETURN.
ENDIF.

" 2. DỌN DẸP DỮ LIỆU CŨ Ở BẢNG REQ
DELETE FROM zconfreqh.
DELETE FROM zconfreqi.
DELETE FROM zauditlog.

TRY.
    " --- CASE 1: TRẠNG THÁI 'S' (SUBMITTED) ĐỂ TEST APPROVE ---
    DATA(lv_req_s) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_s
      req_title   = 'Maintain Warehouse Route'
      module_id   = 'MM'
      env_id      = 'DEV'
      status      = 'S'
      created_by  = sy-uname
      created_at  = lv_ts
    ) TO lt_header.

    " Lấy UUID đầu tiên từ Catalog của bạn để gán vào Item
    APPEND VALUE zconfreqi(
      req_item_id   = cl_system_uuid=>create_uuid_x16_static( )
      req_id        = lv_req_s
      conf_id       = lt_cat_ids[ 1 ]-conf_id " Dùng UUID thực tế từ Catalog
      action        = 'INSERT'
      target_env_id = 'PRD'
    ) TO lt_items.

    " --- CASE 2: TRẠNG THÁI 'A' (APPROVED) ĐỂ HIỆN MÀU XANH ---
    DATA(lv_req_a) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_a
      req_title   = 'Update Expense Limit'
      module_id   = 'FI'
      env_id      = 'QAS'
      status      = 'A'
      created_by  = sy-uname
      created_at  = lv_ts
      approved_by = 'MANAGER'
      approved_at = lv_ts
    ) TO lt_header.

    " Lấy UUID thứ ba từ Catalog của bạn
    APPEND VALUE zconfreqi(
      req_item_id = cl_system_uuid=>create_uuid_x16_static( )
      req_id      = lv_req_a
      conf_id     = VALUE #( lt_cat_ids[ 3 ]-conf_id OPTIONAL )
      action      = 'UPDATE'
      target_env_id = 'PRD'
    ) TO lt_items.

  CATCH cx_uuid_error.
    WRITE 'Lỗi UUID'. RETURN.
ENDTRY.

" 3. DÙNG MODIFY THAY VÌ INSERT ĐỂ TRÁNH DUMP (DUPLICATE KEY)
MODIFY zconfreqh FROM TABLE @lt_header.
MODIFY zconfreqi FROM TABLE @lt_items.
COMMIT WORK.

WRITE: / '--- SEEDING SUCCESSFUL (Khớp với Catalog) ---'.
WRITE: / |Đã tạo { lines( lt_header ) } Header và { lines( lt_items ) } Item dựa trên dữ liệu Catalog thật.|.
