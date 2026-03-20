@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Change Request Item Projection'
@Metadata.allowExtensions: true


define view entity ZC_CONF_REQ_I
  as projection on ZI_CONF_REQ_I
{
  key ReqItemId,
      ReqId,
      ConfId,
      Action,
      TargetEnvId,
      Notes,
      VersionNo,
      ConfName,

      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,

      _Header : redirected to parent ZC_CONF_REQ_H,
      _Catalog,
      _TargetEnv
}
