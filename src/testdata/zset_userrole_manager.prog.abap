*&---------------------------------------------------------------------*
*& Report zset_userrole_manager
*&---------------------------------------------------------------------*
*&
*&---------------------------------------------------------------------*
REPORT zset_userrole_manager.

CONSTANTS: lc_user_id   TYPE syuname VALUE 'DEV-056',
           lc_role      TYPE zde_role_level VALUE 'KEY USER',
           lc_fullname  TYPE c LENGTH 50 VALUE 'DEV-056',
           lc_module_id TYPE zde_module_id VALUE 'ALL'.

DATA ls_role TYPE zuserrole.

" Check if the user already exists
SELECT SINGLE * FROM zuserrole
  WHERE user_id = @lc_user_id
  INTO @ls_role.

IF sy-subrc = 0.
  " User exists — update role_level and ensure is_active = true
  UPDATE zuserrole
    SET role_level = @lc_role,
        is_active  = @abap_true
    WHERE user_id = @lc_user_id.

  IF sy-subrc = 0.
    COMMIT WORK.
    WRITE: / |OK — User { lc_user_id } updated: role_level = '{ lc_role }'.|.
  ELSE.
    ROLLBACK WORK.
    WRITE: / |ERROR — UPDATE failed. sy-subrc = { sy-subrc }.|.
  ENDIF.

ELSE.
  " User does not exist — insert a new record
  ls_role-user_id    = lc_user_id.
  ls_role-fullname   = lc_fullname.
  ls_role-module_id  = lc_module_id.
  ls_role-role_level = lc_role.
  ls_role-is_active  = abap_true.
  ls_role-org_access = '*'.

  INSERT zuserrole FROM @ls_role.

  IF sy-subrc = 0.
    COMMIT WORK.
    WRITE: / |OK — User { lc_user_id } inserted with role_level = '{ lc_role }'.|.
  ELSE.
    ROLLBACK WORK.
    WRITE: / |ERROR — INSERT failed. sy-subrc = { sy-subrc }.|.
  ENDIF.
ENDIF.
