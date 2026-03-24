@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Interface View - Route Configuration'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #S,
    dataClass: #MIXED
}
define root view entity ZI_MM_ROUTE_CONF
  as select from zmmrouteconf_req

  association [1..1] to ZI_ENV_DEF    as _Env      on $projection.EnvId = _Env.EnvId
  association [0..1] to ZI_PLANT_UNIT as _Plant    on $projection.PlantId = _Plant.PlantId
  association [1..1] to ZI_ENV_DEF    as _OldEnv   on $projection.OldEnvId = _OldEnv.EnvId
  association [0..1] to ZI_PLANT_UNIT as _OldPlant on $projection.OldPlantId = _OldPlant.PlantId
{
  key req_id           as ReqId,
  key req_item_id      as ReqItemId,
  key item_id          as ItemId,

      source_item_id   as SourceItemId,
      conf_id          as ConfId,
      action_type      as ActionType,

      @EndUserText.label: 'Environment'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ENV_DEF', element: 'EnvId' } }]
      env_id           as EnvId,

      @EndUserText.label: 'Plant'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_PLANT_UNIT', element: 'PlantId' } }]
      plant_id         as PlantId,

      @EndUserText.label: 'Sending Warehouse'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_VH_WAREHOUSE', element: 'WhId' } }]
      send_wh          as SendWh,

      @EndUserText.label: 'Receiving Warehouse'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_VH_WAREHOUSE', element: 'WhId' } }]
      receive_wh       as ReceiveWh,

      @EndUserText.label: 'Inspector'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_VH_INSPECTOR', element: 'UserId' } }]
      inspector_id     as InspectorId,

      @EndUserText.label: 'Transport Mode'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_VH_TRANS_MODE', element: 'TransMode' } }]
      trans_mode       as TransMode,

      @EndUserText.label: 'Allowed'
      is_allowed       as IsAllowed,

      @EndUserText.label: 'Version'
      version_no       as VersionNo,

      @EndUserText.label: 'Line Status'
      line_status      as LineStatus,

      @EndUserText.label: 'Change Note'
      change_note      as ChangeNote,

      // Old values for compare
      @EndUserText.label: 'Old Environment'
      old_env_id       as OldEnvId,

      @EndUserText.label: 'Old Plant'
      old_plant_id     as OldPlantId,

      @EndUserText.label: 'Old Sending Warehouse'
      old_send_wh      as OldSendWh,

      @EndUserText.label: 'Old Receiving Warehouse'
      old_receive_wh   as OldReceiveWh,

      @EndUserText.label: 'Old Inspector'
      old_inspector_id as OldInspectorId,

      @EndUserText.label: 'Old Transport Mode'
      old_trans_mode   as OldTransMode,

      @EndUserText.label: 'Old Allowed'
      old_is_allowed   as OldIsAllowed,

      @EndUserText.label: 'Old Version'
      old_version_no   as OldVersionNo,

      @Semantics.user.createdBy: true
      created_by       as CreatedBy,

      @Semantics.systemDateTime.createdAt: true
      created_at       as CreatedAt,

      @Semantics.user.lastChangedBy: true
      changed_by       as ChangedBy,

      @Semantics.systemDateTime.lastChangedAt: true
      changed_at       as ChangedAt,

      _Env,
      _Plant,
      _OldEnv,
      _OldPlant
}
