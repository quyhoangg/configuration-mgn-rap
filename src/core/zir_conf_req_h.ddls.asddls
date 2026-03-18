@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Conf Req Header (Interface)'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZIR_CONF_REQ_H
  as select from zconfreqh

  composition [0..*] of ZI_CONF_REQ_I   as _Items

  association [0..1] to ZI_ENV_DEF      as _Env     on $projection.EnvId = _Env.EnvId

  association [0..1] to ZI_CONF_CATALOG as _Catalog on $projection.ConfId = _Catalog.ConfId
{

  key req_id            as ReqId,
      conf_id           as ConfId,
      env_id            as EnvId,
      module_id         as ModuleId,
      req_title         as ReqTitle,
      description       as Description,
      status            as Status,
      case status
        when 'S' then 2 -- Màu vàng: Chờ duyệt (Submitted)
        when 'A' then 3 -- Màu xanh lá: Đã duyệt (Approved)
        when 'R' then 1 -- Màu đỏ: Từ chối (Rejected)
        else 0          -- Không màu/Xám: Nháp (Draft)
      end               as StatusCriticality,
      reason            as Reason,

      _Catalog.ConfName as ConfName,

      /* Admin */
      @Semantics.user.createdBy: true
      created_by        as CreatedBy,

      @Semantics.systemDateTime.createdAt: true
      created_at        as CreatedAt,

      @Semantics.user.lastChangedBy: true
      changed_by        as ChangedBy,

      @Semantics.systemDateTime.lastChangedAt: true
      changed_at        as ChangedAt,

      approved_by       as ApprovedBy,
      approved_at       as ApprovedAt,

      rejected_by       as RejectedBy,
      rejected_at       as RejectedAt,

      _Items,
      _Env
}
