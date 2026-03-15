CLASS lhc_priceconf DEFINITION INHERITING FROM cl_abap_behavior_handler.
  PRIVATE SECTION.

    METHODS set_defaults FOR DETERMINE ON MODIFY
      IMPORTING keys FOR PriceConf~set_defaults.

    METHODS validate_mandatory FOR VALIDATE ON SAVE
      IMPORTING keys FOR PriceConf~validate_mandatory.

    METHODS validate_dates FOR VALIDATE ON SAVE
      IMPORTING keys FOR PriceConf~validate_dates.

    METHODS validate_business FOR VALIDATE ON SAVE
      IMPORTING keys FOR PriceConf~validate_business.

    METHODS approve FOR MODIFY
      IMPORTING keys FOR ACTION PriceConf~approve RESULT result.

    METHODS get_instance_authorizations FOR INSTANCE AUTHORIZATION
      IMPORTING keys REQUEST requested_authorizations
      FOR PriceConf RESULT result.

ENDCLASS.


CLASS lhc_priceconf IMPLEMENTATION.

  METHOD set_defaults.
    " Gán giá trị mặc định khi tạo record mới
    DATA lv_timestamp TYPE timestampl.
    GET TIME STAMP FIELD lv_timestamp.

    READ ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
        FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt ActionType VersionNo )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    MODIFY ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
        UPDATE FIELDS ( CreatedBy CreatedAt ChangedBy ChangedAt ActionType VersionNo )
        WITH VALUE #( FOR entity IN lt_entities
          ( %tky       = entity-%tky
            CreatedBy  = COND #( WHEN entity-CreatedBy IS INITIAL
                                 THEN sy-uname
                                 ELSE entity-CreatedBy )
            CreatedAt  = COND #( WHEN entity-CreatedAt IS INITIAL
                                 THEN lv_timestamp
                                 ELSE entity-CreatedAt )
            ChangedBy  = sy-uname
            ChangedAt  = lv_timestamp
            ActionType = COND #( WHEN entity-ActionType IS INITIAL
                                 THEN 'CREATE'
                                 ELSE entity-ActionType )
            VersionNo  = COND i( WHEN entity-VersionNo IS INITIAL
                                 THEN 1
                                 ELSE entity-VersionNo )
          ) )
      REPORTED DATA(update_reported).

    reported = CORRESPONDING #( DEEP update_reported ).
  ENDMETHOD.


  METHOD validate_mandatory.
    " Kiểm tra các trường bắt buộc
    READ ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
        FIELDS ( EnvId BranchId CustGroup )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    LOOP AT lt_entities INTO DATA(entity).
      IF entity-EnvId IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Environment ID is mandatory' )
                        %element-EnvId = if_abap_behv=>mk-on
        ) TO reported-priceconf.
      ENDIF.

      IF entity-BranchId IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Branch ID is mandatory' )
                        %element-BranchId = if_abap_behv=>mk-on
        ) TO reported-priceconf.
      ENDIF.

      IF entity-CustGroup IS INITIAL.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
        APPEND VALUE #( %tky = entity-%tky
                        %msg = new_message_with_text(
                          severity = if_abap_behv_message=>severity-error
                          text     = 'Customer Group is mandatory' )
                        %element-CustGroup = if_abap_behv=>mk-on
        ) TO reported-priceconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate_dates.
    " Kiểm tra ValidTo >= ValidFrom
    READ ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
        FIELDS ( ValidFrom ValidTo )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    LOOP AT lt_entities INTO DATA(entity).
      IF entity-ValidFrom IS NOT INITIAL AND entity-ValidTo IS NOT INITIAL.
        IF entity-ValidTo < entity-ValidFrom.
          APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
          APPEND VALUE #( %tky = entity-%tky
                          %msg = new_message_with_text(
                            severity = if_abap_behv_message=>severity-error
                            text     = 'Valid To must be after Valid From' )
                          %element-ValidTo = if_abap_behv=>mk-on
          ) TO reported-priceconf.
        ENDIF.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD validate_business.
    " Kiểm tra logic nghiệp vụ: MaxDiscount và MinOrderVal không âm
    READ ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
        FIELDS ( MaxDiscount MinOrderVal )
        WITH CORRESPONDING #( keys )
      RESULT DATA(lt_entities).

    LOOP AT lt_entities INTO DATA(entity).
      IF entity-MaxDiscount IS NOT INITIAL AND entity-MaxDiscount < 0.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
        APPEND VALUE #(
          %tky = entity-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Max Discount cannot be negative' )
          %element-MaxDiscount = if_abap_behv=>mk-on
        ) TO reported-priceconf.
      ENDIF.

      IF entity-MinOrderVal IS NOT INITIAL AND entity-MinOrderVal < 0.
        APPEND VALUE #( %tky = entity-%tky ) TO failed-priceconf.
        APPEND VALUE #(
          %tky = entity-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Min Order Value cannot be negative' )
          %element-MinOrderVal = if_abap_behv=>mk-on
        ) TO reported-priceconf.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD approve.
    " =======================================================
    " ACTION APPROVE - Logic cốt lõi Maker-Checker
    " Chuyển dữ liệu MỚI từ bảng request (zsd_price_req)
    " vào bảng chính (zsd_price_conf)
    " =======================================================

    DATA lv_now TYPE timestampl.
    GET TIME STAMP FIELD lv_now.

    " 1. Đọc tất cả request records cần approve
    READ ENTITIES OF zi_sd_price_conf IN LOCAL MODE
      ENTITY PriceConf
      ALL FIELDS WITH CORRESPONDING #( keys )
      RESULT DATA(lt_reqs).

    LOOP AT lt_reqs ASSIGNING FIELD-SYMBOL(<req>).

      " 2. Chỉ approve khi chưa APPROVED
      IF <req>-LineStatus = 'APPROVED'.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-priceconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'This record is already approved.' )
        ) TO reported-priceconf.
        CONTINUE.
      ENDIF.

      " 3. Kiểm tra mandatory fields
      IF <req>-EnvId IS INITIAL OR <req>-BranchId IS INITIAL OR
         <req>-CustGroup IS INITIAL.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-priceconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Cannot approve: EnvId/BranchId/CustGroup missing.' )
        ) TO reported-priceconf.
        CONTINUE.
      ENDIF.

      " 4. Kiểm tra ngày hợp lệ
      IF <req>-ValidFrom IS NOT INITIAL AND <req>-ValidTo IS NOT INITIAL
         AND <req>-ValidTo < <req>-ValidFrom.
        APPEND VALUE #( %tky = <req>-%tky ) TO failed-priceconf.
        APPEND VALUE #(
          %tky = <req>-%tky
          %msg = new_message_with_text(
                   severity = if_abap_behv_message=>severity-error
                   text     = 'Cannot approve: Valid To < Valid From.' )
        ) TO reported-priceconf.
        CONTINUE.
      ENDIF.

      " 5. Tính version mới
      DATA(lv_new_version) = COND i(
        WHEN <req>-OldVersionNo IS NOT INITIAL THEN <req>-OldVersionNo + 1
        ELSE 1 ).

      " 6. Chuẩn bị dữ liệu ghi vào bảng chính zsd_price_conf
      DATA(ls_conf) = VALUE zsd_price_conf(
        client        = sy-mandt
        item_id       = COND #(
                          WHEN <req>-ConfId IS NOT INITIAL
                          THEN <req>-ConfId
                          ELSE <req>-ItemId )
        req_id        = <req>-ReqId
        branch_id     = <req>-BranchId
        env_id        = <req>-EnvId
        cust_group    = <req>-CustGroup
        material_grp  = <req>-MaterialGrp
        max_discount  = <req>-MaxDiscount
        min_order_val = <req>-MinOrderVal
        approver_grp  = <req>-ApproverGrp
        currency      = <req>-Currency
        valid_from    = <req>-ValidFrom
        valid_to      = <req>-ValidTo
        version_no    = lv_new_version
        created_by    = COND #(
                          WHEN <req>-ActionType = 'CREATE'
                          THEN sy-uname
                          ELSE <req>-CreatedBy )
        created_at    = COND #(
                          WHEN <req>-ActionType = 'CREATE'
                          THEN lv_now
                          ELSE <req>-CreatedAt )
        changed_by    = sy-uname
        changed_at    = lv_now
      ).

      " 7. Kiểm tra record tồn tại → UPDATE hoặc INSERT
      DATA lv_exists TYPE abap_boolean.
      CLEAR lv_exists.

      SELECT SINGLE @abap_true FROM zsd_price_conf
        WHERE item_id = @ls_conf-item_id
        INTO @lv_exists.

      TRY.
          IF lv_exists = abap_true.
            UPDATE zsd_price_conf SET
              req_id        = @ls_conf-req_id,
              branch_id     = @ls_conf-branch_id,
              env_id        = @ls_conf-env_id,
              cust_group    = @ls_conf-cust_group,
              material_grp  = @ls_conf-material_grp,
              max_discount  = @ls_conf-max_discount,
              min_order_val = @ls_conf-min_order_val,
              approver_grp  = @ls_conf-approver_grp,
              currency      = @ls_conf-currency,
              valid_from    = @ls_conf-valid_from,
              valid_to      = @ls_conf-valid_to,
              version_no    = @ls_conf-version_no,
              changed_by    = @ls_conf-changed_by,
              changed_at    = @ls_conf-changed_at
              WHERE item_id = @ls_conf-item_id.
          ELSE.
            INSERT zsd_price_conf FROM @ls_conf.
          ENDIF.

        CATCH cx_root INTO DATA(lx_err).
          APPEND VALUE #( %tky = <req>-%tky ) TO failed-priceconf.
          APPEND VALUE #(
            %tky = <req>-%tky
            %msg = new_message_with_text(
                     severity = if_abap_behv_message=>severity-error
                     text     = |DB error: { lx_err->get_text( ) }| )
          ) TO reported-priceconf.
          CONTINUE.
      ENDTRY.

      " 8. Cập nhật request: LineStatus = APPROVED
      MODIFY ENTITIES OF zi_sd_price_conf IN LOCAL MODE
        ENTITY PriceConf
        UPDATE FIELDS ( LineStatus VersionNo ChangedBy ChangedAt )
        WITH VALUE #( (
          %tky       = <req>-%tky
          LineStatus = 'APPROVED'
          VersionNo  = lv_new_version
          ChangedBy  = sy-uname
          ChangedAt  = lv_now
        ) ).

      " 9. Trả kết quả thành công
      APPEND VALUE #(
        %tky   = <req>-%tky
        %param = <req>
      ) TO result.

    ENDLOOP.
  ENDMETHOD.


  METHOD get_instance_authorizations.
    result = VALUE #( FOR key IN keys
      ( %tky    = key-%tky
        %update = if_abap_behv=>auth-allowed
        %delete = if_abap_behv=>auth-allowed
      ) ).
  ENDMETHOD.

ENDCLASS.
