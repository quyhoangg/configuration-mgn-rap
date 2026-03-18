CLASS lhc_safestock DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.
    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR SafeStock~set_defaults.

    METHODS setAdminFields FOR DETERMINE ON MODIFY
      IMPORTING keys FOR SafeStock~setAdminFields.

    METHODS validateMandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR SafeStock~validateMandatory.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION SafeStock~approve RESULT result.

    METHODS get_instance_features FOR INSTANCE FEATURES
      IMPORTING keys REQUEST requested_features
      FOR SafeStock RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations
      FOR SafeStock RESULT result.
ENDCLASS.


CLASS lhc_safestock IMPLEMENTATION.

    METHOD set_defaults.
      READ ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
        ENTITY SafeStock ALL FIELDS WITH CORRESPONDING #( keys )
        RESULT DATA(lt_data).

      " Thu thập các record cần cập nhật ActionType/VersionNo
      DATA lt_update_base TYPE TABLE FOR UPDATE zi_mm_safe_stock\\SafeStock.

      LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r>).

        " ── GUARD: chỉ set default nếu ActionType hoặc VersionNo còn trống ──
        " Nếu đã có giá trị rồi → bỏ qua, tránh MODIFY không cần thiết
        IF <r>-ActionType IS NOT INITIAL AND <r>-VersionNo IS NOT INITIAL.
          " Không cần MODIFY ActionType/VersionNo nữa
        ELSE.
          APPEND VALUE #(
            %tky       = <r>-%tky
            ActionType = COND #( WHEN <r>-ActionType IS INITIAL THEN 'CREATE'
                                 ELSE <r>-ActionType )
            VersionNo  = COND #( WHEN <r>-VersionNo IS INITIAL THEN 1
                                 ELSE <r>-VersionNo )
          ) TO lt_update_base.
        ENDIF.

      ENDLOOP.

      " Chỉ gọi MODIFY nếu thực sự có record cần cập nhật
      IF lt_update_base IS NOT INITIAL.
        MODIFY ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
          ENTITY SafeStock
          UPDATE FIELDS ( ActionType VersionNo )
          WITH lt_update_base.
      ENDIF.

      " ── Xử lý Old values cho UPDATE/DELETE ──
      LOOP AT lt_data ASSIGNING FIELD-SYMBOL(<r2>).

        IF ( <r2>-ActionType = 'UPDATE' OR <r2>-ActionType = 'DELETE' )
          AND <r2>-SourceItemId IS NOT INITIAL
          AND <r2>-OldEnvId IS INITIAL.  " ← GUARD: chỉ load nếu chưa có

          SELECT SINGLE * FROM zmmsafestock
            WHERE item_id = @<r2>-SourceItemId
            INTO @DATA(ls_src).

          CHECK sy-subrc = 0.

          MODIFY ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
            ENTITY SafeStock
            UPDATE FIELDS ( OldEnvId OldPlantId OldMatGroup OldMinQty OldVersionNo
                            EnvId PlantId MatGroup MinQty VersionNo )
            WITH VALUE #( (
              %tky         = <r2>-%tky
              OldEnvId     = ls_src-env_id
              OldPlantId   = ls_src-plant_id
              OldMatGroup  = ls_src-mat_group
              OldMinQty    = ls_src-min_qty
              OldVersionNo = ls_src-version_no
              EnvId        = ls_src-env_id
              PlantId      = ls_src-plant_id
              MatGroup     = ls_src-mat_group
              MinQty       = ls_src-min_qty
              VersionNo    = ls_src-version_no
            ) ).

        ENDIF.
      ENDLOOP.
    ENDMETHOD.

    METHOD setAdminFields.
      DATA lv_now TYPE timestampl.
      GET TIME STAMP FIELD lv_now.

      READ ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
        ENTITY SafeStock
          FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
          WITH CORRESPONDING #( keys )
        RESULT DATA(entities).

      DATA lt_update TYPE TABLE FOR UPDATE zi_mm_safe_stock\\SafeStock.

      LOOP AT entities INTO DATA(entity).
        DATA(lv_new_created_by) = COND syuname(
          WHEN entity-CreatedBy IS INITIAL THEN sy-uname
          ELSE entity-CreatedBy ).
        DATA(lv_new_created_at) = COND timestampl(
          WHEN entity-CreatedAt IS INITIAL THEN lv_now
          ELSE entity-CreatedAt ).

        " ── GUARD: chỉ MODIFY nếu có gì đó thực sự cần thay đổi ──
        " So sánh ChangedBy: nếu đã là sy-uname và CreatedBy không đổi → bỏ qua
        IF entity-ChangedBy    = sy-uname
        AND entity-CreatedBy   = lv_new_created_by
        AND entity-CreatedAt   = lv_new_created_at.
          CONTINUE. " Không có gì thay đổi → không MODIFY → không loop
        ENDIF.

        APPEND VALUE #(
          %tky      = entity-%tky
          CreatedBy = lv_new_created_by
          CreatedAt = lv_new_created_at
          ChangedBy = sy-uname
          ChangedAt = lv_now
        ) TO lt_update.
      ENDLOOP.

      IF lt_update IS NOT INITIAL.
        MODIFY ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
          ENTITY SafeStock
            UPDATE FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt )
            WITH lt_update
          REPORTED DATA(update_reported).
        reported = CORRESPONDING #( DEEP update_reported ).
      ENDIF.
    ENDMETHOD.


  METHOD validateMandatory.
    READ ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
      ENTITY SafeStock
        FIELDS ( EnvId PlantId MatGroup MinQty )
        WITH CORRESPONDING #( keys )
      RESULT DATA(entities).

    LOOP AT entities INTO DATA(entity).
      IF entity-EnvId IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-safestock.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Environment ID is mandatory' )
                        %element-EnvId = if_abap_behv=>mk-on
        ) TO reported-safestock.
      ENDIF.

      IF entity-PlantId IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-safestock.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Plant ID is mandatory' )
                        %element-PlantId = if_abap_behv=>mk-on
        ) TO reported-safestock.
      ENDIF.

      IF entity-MatGroup IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-safestock.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Material Group is mandatory' )
                        %element-MatGroup = if_abap_behv=>mk-on
        ) TO reported-safestock.
      ENDIF.

      IF entity-MinQty IS INITIAL OR entity-MinQty <= 0.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-safestock.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Minimum Quantity must be greater than 0' )
                        %element-MinQty = if_abap_behv=>mk-on
        ) TO reported-safestock.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD approve.
    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    READ ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
      ENTITY SafeStock
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    LOOP AT lt_reqs ASSIGNING FIELD-SYMBOL(<req>).

      IF <req>-LineStatus = 'APPROVED'.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-safestock.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'This record is already approved.' )
        ) TO reported-safestock.
        CONTINUE.
      ENDIF.

      IF <req>-EnvId IS INITIAL OR <req>-PlantId IS INITIAL OR
         <req>-MatGroup IS INITIAL.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-safestock.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Cannot approve: EnvId/PlantId/MatGroup missing.' )
        ) TO reported-safestock.
        CONTINUE.
      ENDIF.

      DATA(lv_new_version) = COND i(
        WHEN <req>-OldVersionNo IS NOT INITIAL THEN <req>-OldVersionNo + 1
        ELSE 1 ).

      DATA(ls_conf) = VALUE zmmsafestock(
        client     = sy-mandt
        item_id    = COND #(
                       WHEN <req>-ConfId IS NOT INITIAL
                       THEN <req>-ConfId
                       ELSE <req>-ItemId )
        req_id     = <req>-ReqId
        env_id     = <req>-EnvId
        plant_id   = <req>-PlantId
        mat_group  = <req>-MatGroup
        min_qty    = <req>-MinQty
        version_no = lv_new_version
        created_by = COND #(
                       WHEN <req>-ActionType = 'CREATE'
                       THEN sy-uname
                       ELSE <req>-CreatedBy )
        created_at = COND #(
                       WHEN <req>-ActionType = 'CREATE'
                       THEN lv_now
                       ELSE <req>-CreatedAt )
        changed_by = sy-uname
        changed_at = lv_now
      ).

      TRY.
          CASE <req>-ActionType.

            WHEN 'DELETE'.
              " Xóa bản ghi khỏi bảng chính
              DELETE FROM zmmsafestock
                WHERE item_id = @ls_conf-item_id.

              IF sy-subrc <> 0.
                " Bản ghi không tồn tại để xóa → cảnh báo nhưng không fail
                APPEND VALUE #(
                  %tky = <req>-%tky
                  %msg = new_message_with_text(
                           severity = if_abap_behv_message=>severity-warning
                           text     = 'Bản ghi gốc không còn tồn tại để xóa.' )
                ) TO reported-safestock.
              ENDIF.

            WHEN OTHERS. " 'CREATE' và 'UPDATE'
              " Kiểm tra bản ghi đã tồn tại trong bảng chính chưa
              SELECT SINGLE @abap_true
                FROM zmmsafestock
                WHERE item_id = @ls_conf-item_id
                INTO @DATA(lv_exists).

              IF lv_exists = abap_true.
                " Đã tồn tại → UPDATE (chỉ cập nhật các trường nghiệp vụ)
                UPDATE zmmsafestock SET
                  req_id     = @ls_conf-req_id,
                  env_id     = @ls_conf-env_id,
                  plant_id   = @ls_conf-plant_id,
                  mat_group  = @ls_conf-mat_group,
                  min_qty    = @ls_conf-min_qty,
                  version_no = @ls_conf-version_no,
                  changed_by = @ls_conf-changed_by,
                  changed_at = @ls_conf-changed_at
                  WHERE item_id = @ls_conf-item_id.
              ELSE.
                " Chưa tồn tại → INSERT bản ghi mới
                INSERT zmmsafestock FROM @ls_conf.
              ENDIF.

          ENDCASE.

        CATCH cx_root INTO DATA(lx_err).
          " Lỗi DB bất ngờ → báo lỗi, bỏ qua record này
          APPEND VALUE #( %tky = <req>-%tky ) TO failed-safestock.
          APPEND VALUE #(
            %tky = <req>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |DB error: { lx_err->get_text( ) }| )
          ) TO reported-safestock.
          CONTINUE.
      ENDTRY.

      MODIFY ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
        ENTITY SafeStock
        UPDATE FIELDS ( LineStatus VersionNo ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky       = <req>-%tky
          LineStatus = 'APPROVED'
          VersionNo  = lv_new_version
          ChangedBy  = sy-uname
          ChangedAt  = lv_now
        ) ).

      APPEND VALUE #(
        %tky   = <req>-%tky
        %param = <req>
      ) TO result.

    ENDLOOP.
  ENDMETHOD.

  METHOD get_instance_features.
    " Đọc trạng thái LineStatus của từng record
    READ ENTITIES OF zi_mm_safe_stock IN LOCAL MODE
      ENTITY SafeStock
        FIELDS ( LineStatus )
        WITH CORRESPONDING #( keys )
      RESULT DATA(entities).

    result = VALUE #( FOR entity IN entities
      LET " Nếu đã APPROVED → disable nút approve, ngược lại enable
          lv_approve = COND #(
            WHEN entity-LineStatus = 'APPROVED'
            THEN if_abap_behv=>fc-o-disabled
            ELSE if_abap_behv=>fc-o-enabled )
      IN (
        %tky            = entity-%tky
        %action-approve = lv_approve
      ) ).
  ENDMETHOD.

  METHOD get_instance_authorizations.
    result = VALUE #( FOR key IN keys
      ( %tky    = key-%tky
        %update = if_abap_behv=>auth-allowed
        %delete = if_abap_behv=>auth-allowed
      ) ).
  ENDMETHOD.

ENDCLASS.
