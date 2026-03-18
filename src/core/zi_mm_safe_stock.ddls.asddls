@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Interface View - Safety Stock'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZI_MM_SAFE_STOCK
  as select from zmmsafestock_req
 association [1..1] to ZI_ENV_DEF as _Env
  on $projection.EnvId = _Env.EnvId

association [1..1] to ZI_ENV_DEF as _OldEnv
  on $projection.OldEnvId = _OldEnv.EnvId
{
  key req_id        as ReqId,
  key req_item_id   as ReqItemId,
  key item_id       as ItemId,

      source_item_id as SourceItemId,
      conf_id        as ConfId,
      action_type    as ActionType,

      env_id         as EnvId,
      plant_id       as PlantId,
      mat_group      as MatGroup,
      min_qty        as MinQty,

      version_no     as VersionNo,

      line_status    as LineStatus,
      change_note    as ChangeNote,

      old_env_id     as OldEnvId,
      old_plant_id   as OldPlantId,
      old_mat_group  as OldMatGroup,
      old_min_qty    as OldMinQty,
      old_version_no as OldVersionNo,

      created_by     as CreatedBy,
      created_at     as CreatedAt,
      changed_by     as ChangedBy,
      changed_at     as ChangedAt,

      _Env,
      _OldEnv
}


