@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'MM Route Main Table (Read-Only Display)'
@Metadata.ignorePropagatedAnnotations: true
@ObjectModel.usageType:{
    serviceQuality: #X,
    sizeCategory: #M,
    dataClass: #MIXED
}
define view entity ZC_MM_ROUTE_MAIN
  as select from zmmrouteconf
{
  key item_id      as ItemId,
      env_id       as EnvId,
      plant_id     as PlantId,
      send_wh      as SendWh,
      receive_wh   as ReceiveWh,
      inspector_id as InspectorId,
      trans_mode   as TransMode,
      is_allowed   as IsAllowed,
      version_no   as VersionNo
}
