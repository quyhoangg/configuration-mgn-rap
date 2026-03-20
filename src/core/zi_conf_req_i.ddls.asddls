@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Conf Req Item (Interface)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define view entity ZI_CONF_REQ_I
  as select from zconfreqi
  association        to parent ZIR_CONF_REQ_H as _Header    on $projection.ReqId = _Header.ReqId

  association [1..1] to ZI_CONF_CATALOG       as _Catalog   on $projection.ConfId = _Catalog.ConfId

  association [1..1] to ZI_ENV_DEF            as _TargetEnv on $projection.TargetEnvId = _TargetEnv.EnvId
{
  key req_item_id       as ReqItemId,

      req_id            as ReqId,
      conf_id           as ConfId,
      action            as Action,
      target_env_id     as TargetEnvId,
      notes             as Notes,
      version_no        as VersionNo,
      _Catalog.ConfName as ConfName,

      @Semantics.user.createdBy: true
      created_by        as CreatedBy,

      @Semantics.systemDateTime.createdAt: true
      created_at        as CreatedAt,

      @Semantics.user.lastChangedBy: true
      changed_by        as ChangedBy,

      @Semantics.systemDateTime.lastChangedAt: true
      changed_at        as ChangedAt,

      _Header,
      _Catalog,
      _TargetEnv
}
