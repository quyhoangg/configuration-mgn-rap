 REPORT zcheck_fi_reqid.

  WRITE: / '=== ZCONFREQH (FI APPROVED) ==='.
  SELECT req_id, status, module_id FROM zconfreqh
    WHERE module_id = 'FI' AND status = 'APPROVED'
    INTO TABLE @DATA(lt_h).
  LOOP AT lt_h INTO DATA(ls_h).
    WRITE: / ls_h-req_id, ls_h-status, ls_h-module_id.
  ENDLOOP.

  WRITE: / ''.
  WRITE: / '=== ZFILIMITREQ (DISTINCT REQ_ID) ==='.
  SELECT DISTINCT req_id FROM zfilimitreq INTO TABLE @DATA(lt_r).
  LOOP AT lt_r INTO DATA(ls_r).
    WRITE: / ls_r-req_id.
  ENDLOOP.

  WRITE: / ''.
  WRITE: / '=== MATCH CHECK ==='.
  LOOP AT lt_h INTO ls_h.
    READ TABLE lt_r WITH KEY req_id = ls_h-req_id TRANSPORTING NO FIELDS.
    IF sy-subrc = 0.
      WRITE: / 'MATCH:', ls_h-req_id.
    ELSE.
      WRITE: / 'NO MATCH:', ls_h-req_id.
    ENDIF.
  ENDLOOP.
