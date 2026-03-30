REPORT zclean_fi_req.

  DELETE FROM zfilimitreq.
  DELETE FROM zfi_limit_d.

  COMMIT WORK.

  WRITE: / 'Deleted all rows from ZFILIMITREQ and ZFI_LIMIT_D.'.
