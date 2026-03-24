*&---------------------------------------------------------------------*
*& Report zseed_mm_route_conf
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zseed_mm_route_conf.

DELETE FROM zmmrouteconf_req WHERE 1 = 1.

COMMIT WORK.

IF sy-subrc = 0.
  WRITE: / |Done. { sy-dbcnt } rows deleted from ZMMROUTECONF_REQ.|.
ELSE.
  WRITE: / |Error. sy-subrc = { sy-subrc }.|.
ENDIF.
