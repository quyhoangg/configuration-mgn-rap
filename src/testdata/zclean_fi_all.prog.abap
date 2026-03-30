 REPORT zclean_fi_all.

  DELETE FROM zfilimitconf.
  DELETE FROM zfilimitreq.

  COMMIT WORK.

  WRITE: / |Deleted { sy-dbcnt } rows. All FI data cleaned.|.
