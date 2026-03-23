@AbapCatalog.viewEnhancementCategory: [#NONE]                                                                                                                                                       @AccessControl.authorizationCheck: #NOT_REQUIRED                                                                                                                                                  
  @EndUserText.label: 'Audit Log Interface View'                                                                                                                                                      @Metadata.ignorePropagatedAnnotations: true                                                                                                                                                       
  define view entity ZI_AUDIT_LOG
    as select from zauditlog
  {
    key log_id      as LogId,
        req_id      as ReqId,
        conf_id     as ConfId,
        module_id   as ModuleId,
        action_type as ActionType,
        table_name  as TableName,
        old_data    as OldData,
        new_data    as NewData,
        env_id      as EnvId,
        object_key  as ObjectKey,
        changed_by  as ChangedBy,
        changed_at  as ChangedAt
  }
