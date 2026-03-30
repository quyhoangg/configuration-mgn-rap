@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'SD Price Main Table (Read-Only Display)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define view entity ZC_SD_PRICE_MAIN
  as select from zsd_price_conf
{
  key item_id       as ItemId,
      req_id        as ReqId,
      env_id        as EnvId,
      branch_id     as BranchId,
      cust_group    as CustGroup,
      material_grp  as MaterialGrp,

      @Semantics.amount.currencyCode: 'Currency'
      max_discount  as MaxDiscount,

      min_order_val as MinOrderVal,
      approver_grp  as ApproverGrp,
      currency      as Currency,
      valid_from    as ValidFrom,
      valid_to      as ValidTo,
      version_no    as VersionNo,
        created_by    as CreatedBy,
        created_at    as CreatedAt
}
