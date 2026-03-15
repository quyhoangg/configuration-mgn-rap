@AbapCatalog.viewEnhancementCategory: [#NONE]
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'FI Expense Limit Configuration'
@Metadata.ignorePropagatedAnnotations: true
define root view entity ZI_FI_LIMIT_CONF
  as select from zfilimitreq

  association [1..1] to ZI_ENV_DEF as _Env    on $projection.EnvId    = _Env.EnvId
  association [1..1] to ZI_ENV_DEF as _OldEnv on $projection.OldEnvId = _OldEnv.EnvId
{
  key req_id            as ReqId,
  key req_item_id       as ReqItemId,
  key item_id           as ItemId,

      source_item_id    as SourceItemId,
      conf_id           as ConfId,
      action_type       as ActionType,

      @EndUserText.label: 'Environment'
      @Consumption.valueHelpDefinition: [{ entity: { name: 'ZI_ENV_DEF', element: 'EnvId' } }]
      env_id            as EnvId,

      @EndUserText.label: 'Expense Type'
      expense_type      as ExpenseType,

      @EndUserText.label: 'G/L Account'
      gl_account        as GlAccount,

      @EndUserText.label: 'Auto Approval Limit'
      @Semantics.amount.currencyCode: 'Currency'
      auto_appr_lim     as AutoApprLim,

      @EndUserText.label: 'Currency'
      currency          as Currency,

      @EndUserText.label: 'Version'
      version_no        as VersionNo,

      @EndUserText.label: 'Line Status'
      line_status       as LineStatus,

      @EndUserText.label: 'Change Note'
      change_note       as ChangeNote,

      @EndUserText.label: 'Old Environment'
      old_env_id        as OldEnvId,

      @EndUserText.label: 'Old Expense Type'
      old_expense_type  as OldExpenseType,

      @EndUserText.label: 'Old G/L Account'
      old_gl_account    as OldGlAccount,

      @EndUserText.label: 'Old Auto Approval Limit'
      @Semantics.amount.currencyCode: 'OldCurrency'
      old_auto_appr_lim as OldAutoApprLim,

      @EndUserText.label: 'Old Currency'
      old_currency      as OldCurrency,

      @EndUserText.label: 'Old Version'
      old_version_no    as OldVersionNo,

      @Semantics.user.createdBy: true
      created_by        as CreatedBy,

      @Semantics.systemDateTime.createdAt: true
      created_at        as CreatedAt,

      @Semantics.user.lastChangedBy: true
      changed_by        as ChangedBy,

      @Semantics.systemDateTime.lastChangedAt: true
      changed_at        as ChangedAt,

      _Env,
      _OldEnv
}
