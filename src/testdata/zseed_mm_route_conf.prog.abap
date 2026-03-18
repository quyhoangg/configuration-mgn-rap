*&---------------------------------------------------------------------*
*& Report zseed_mm_route_conf
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zseed_mm_route_conf.
  DELETE FROM zconfreqi.
  DELETE FROM zconfreqh.
  DELETE FROM zconfreqi_d.
  DELETE FROM zconfreqh_d.

  COMMIT WORK.
