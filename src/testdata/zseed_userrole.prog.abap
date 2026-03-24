REPORT zseed_userrole.

DATA ls_role TYPE zuserrole.

ls_role-user_id    = sy-uname.
ls_role-fullname   = 'BAO'.
ls_role-module_id  = 'ALL'.
ls_role-role_level = 'IT ADMIN'.
ls_role-is_active  = abap_true.
ls_role-org_access = '*'.

DELETE FROM zuserrole WHERE user_id = sy-uname.
INSERT zuserrole FROM @ls_role.
COMMIT WORK.

IF sy-subrc = 0.
  WRITE: / |Done. User { sy-uname } assigned KEY USER.|.
ELSE.
  WRITE: / |Error. sy-subrc = { sy-subrc }.|.
ENDIF.
