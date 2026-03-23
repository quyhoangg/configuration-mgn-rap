 CLASS zcl_gsp26_rule_status DEFINITION PUBLIC FINAL CREATE PUBLIC.                                                                                                                                    PUBLIC SECTION.
      CONSTANTS: cv_draft       TYPE string VALUE 'DRAFT',
                 cv_submitted   TYPE string VALUE 'SUBMITTED',
                 cv_approved    TYPE string VALUE 'APPROVED',
                 cv_rejected    TYPE string VALUE 'REJECTED',
                 cv_promoted    TYPE string VALUE 'PROMOTED',
                 cv_active      TYPE string VALUE 'ACTIVE',
                 cv_rolled_back TYPE string VALUE 'ROLLED_BACK'.

      " Method cũ — giữ lại để không break code khác
      CLASS-METHODS is_transition_valid
        IMPORTING iv_req_id      TYPE sysuuid_x16
                  iv_next_status TYPE string
        RETURNING VALUE(rv_allowed) TYPE abap_bool.

      " Method mới — dùng trong RAP context (không SELECT DB)
      CLASS-METHODS is_transition_valid_by_status
        IMPORTING iv_current_status TYPE string
                  iv_next_status    TYPE string
        RETURNING VALUE(rv_allowed) TYPE abap_bool.
  ENDCLASS.

  CLASS zcl_gsp26_rule_status IMPLEMENTATION.

    METHOD is_transition_valid.
      " Lấy trạng thái từ DB rồi delegate
      SELECT SINGLE status FROM zconfreqh
        WHERE req_id = @iv_req_id
        INTO @DATA(lv_current_status).

       rv_allowed = is_transition_valid_by_status(
        iv_current_status = CONV string( lv_current_status )
        iv_next_status    = iv_next_status ).
    ENDMETHOD.

    METHOD is_transition_valid_by_status.
      rv_allowed = abap_false.

      CASE iv_current_status.
        WHEN cv_draft.
          IF iv_next_status = cv_submitted. rv_allowed = abap_true. ENDIF.

        WHEN cv_submitted.
          IF iv_next_status = cv_approved OR iv_next_status = cv_rejected.
            rv_allowed = abap_true.
          ENDIF.

        WHEN cv_approved.
          IF iv_next_status = cv_promoted OR iv_next_status = cv_active OR iv_next_status = cv_rolled_back.
            rv_allowed = abap_true.
          ENDIF.

        WHEN cv_promoted OR cv_active.
          IF iv_next_status = cv_rolled_back. rv_allowed = abap_true. ENDIF.

      ENDCASE.
    ENDMETHOD.

  ENDCLASS.
