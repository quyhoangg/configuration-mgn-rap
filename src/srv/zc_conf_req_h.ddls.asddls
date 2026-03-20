@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Change Request Header Projection'
@Metadata.allowExtensions: true

define root view entity ZC_CONF_REQ_H
  provider contract transactional_query
  as projection on ZIR_CONF_REQ_H
{
  key ReqId,
      ConfId,
      EnvId,
      ModuleId,
      ReqTitle,
      Description,
      Status,
      StatusCriticality,
      Reason,

      CreatedBy,
      CreatedAt,
      ChangedBy,
      ChangedAt,
      ApprovedBy,
      ApprovedAt,
      RejectedBy,
      RejectedAt,

      _Items : redirected to composition child ZC_CONF_REQ_I,
      _Env,
      ConfName,
      TargetCds
}
