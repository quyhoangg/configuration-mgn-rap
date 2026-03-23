*&---------------------------------------------------------------------*
*& Report zseed_mm_route_conf
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zseed_mm_route_conf.

UPDATE zmmrouteconf
  SET env_id = 'DEV'
  WHERE env_id IN ('TEST', 'QAS', 'PRD').

COMMIT WORK.

IF sy-subrc = 0.
  WRITE: / |Done. { sy-dbcnt } rows updated to ENV_ID = 'DEV'.|.
ELSE.
  WRITE: / |Error. sy-subrc = { sy-subrc }.|.
ENDIF.
