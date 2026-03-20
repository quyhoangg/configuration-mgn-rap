*&---------------------------------------------------------------------*
*& Report ZSEED_MANAGER_TEST
*&---------------------------------------------------------------------*
REPORT zseed_manager_test.

DATA: lt_header  TYPE STANDARD TABLE OF zconfreqh,
      lt_items   TYPE STANDARD TABLE OF zconfreqi,
      lv_ts      TYPE timestampl.

GET TIME STAMP FIELD lv_ts.

" 1. LẤY DANH SÁCH CONF_ID ĐANG CÓ TRONG CATALOG
SELECT conf_id FROM zconfcatalog INTO TABLE @DATA(lt_cat_ids).

IF lt_cat_ids IS INITIAL.
   WRITE: / 'Lỗi: Bảng Catalog đang trống, vui lòng kiểm tra lại!'.
   RETURN.
ENDIF.

" 2. DỌN DẸP DỮ LIỆU CŨ (Bao gồm cả bảng Draft để tránh lỗi Cache)
DELETE FROM zconfreqh.
DELETE FROM zconfreqi.
DELETE FROM zconfreqh_d.
DELETE FROM zconfreqi_d.
DELETE FROM zauditlog.
COMMIT WORK.

TRY.
    " --- CASE 1: REQUEST ĐỂ TEST APPROVE (Status 'S') ---
    DATA(lv_req_s1) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_s1
      req_title   = 'Maintain Warehouse Route (Test Approve)'
      module_id   = 'MM'
      env_id      = 'DEV'
      status      = 'S'
      created_by  = sy-uname
      created_at  = lv_ts
    ) TO lt_header.

    APPEND VALUE zconfreqi(
      req_item_id   = cl_system_uuid=>create_uuid_x16_static( )
      req_id        = lv_req_s1
      conf_id       = lt_cat_ids[ 1 ]-conf_id
      action        = 'INSERT'
      target_env_id = 'PRD'
    ) TO lt_items.

    " --- CASE 2: REQUEST ĐỂ TEST REJECT (Status 'S') ---
    DATA(lv_req_s2) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_s2
      req_title   = 'Safety Stock Update (Test Reject)'
      module_id   = 'MM'
      env_id      = 'DEV'
      status      = 'S'
      created_by  = sy-uname
      created_at  = lv_ts
    ) TO lt_header.

    APPEND VALUE zconfreqi(
      req_item_id   = cl_system_uuid=>create_uuid_x16_static( )
      req_id        = lv_req_s2
      conf_id       = VALUE #( lt_cat_ids[ 2 ]-conf_id OPTIONAL )
      action        = 'UPDATE'
      target_env_id = 'QAS'
    ) TO lt_items.

    " --- CASE 3: THÊM 1 REQUEST NỮA ĐỂ TEST RULE VALIDATOR (Status 'S') ---
    DATA(lv_req_s3) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_s3
      req_title   = 'Price Config Rule (Test Validator)'
      module_id   = 'SD'
      env_id      = 'DEV'
      status      = 'S'
      created_by  = sy-uname
      created_at  = lv_ts
    ) TO lt_header.

    APPEND VALUE zconfreqi(
      req_item_id   = cl_system_uuid=>create_uuid_x16_static( )
      req_id        = lv_req_s3
      conf_id       = VALUE #( lt_cat_ids[ 4 ]-conf_id OPTIONAL )
      action        = 'DELETE'
      target_env_id = 'PRD'
    ) TO lt_items.

    " --- CASE 4: REQUEST ĐÃ APPROVED (Status 'A') ĐỂ HIỆN MÀU XANH ---
    DATA(lv_req_a) = cl_system_uuid=>create_uuid_x16_static( ).
    APPEND VALUE zconfreqh(
      req_id      = lv_req_a
      req_title   = 'Update Expense Limit (Already Approved)'
      module_id   = 'FI'
      env_id      = 'QAS'
      status      = 'A'
      created_by  = sy-uname
      created_at  = lv_ts
      approved_by = 'MANAGER_A'
      approved_at = lv_ts
    ) TO lt_header.

    APPEND VALUE zconfreqi(
      req_item_id = cl_system_uuid=>create_uuid_x16_static( )
      req_id      = lv_req_a
      conf_id     = VALUE #( lt_cat_ids[ 3 ]-conf_id OPTIONAL )
      action      = 'UPDATE'
      target_env_id = 'PRD'
    ) TO lt_items.

  CATCH cx_uuid_error.
    WRITE 'Lỗi tạo UUID'. RETURN.
ENDTRY.

" 3. THỰC THI MODIFY VÀO DATABASE
MODIFY zconfreqh FROM TABLE @lt_header.
MODIFY zconfreqi FROM TABLE @lt_items.
COMMIT WORK.

WRITE: / '--- SEEDING SUCCESSFUL ---'.
WRITE: / |Đã nạp { lines( lt_header ) } Requests vào hệ thống.|.
WRITE: / 'Vui lòng nhấn F5 trên trình duyệt để kiểm tra.'.
