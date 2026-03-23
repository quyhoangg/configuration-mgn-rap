 @AccessControl.authorizationCheck: #NOT_REQUIRED                                                                                                                                                    @EndUserText.label: 'Audit Log Projection View'                                                                                                                                                   
  @Metadata.ignorePropagatedAnnotations: true                                                                                                                                                       
  @Search.searchable: true
  define view entity ZC_AUDIT_LOG
    as select from ZI_AUDIT_LOG
  {
    @UI.lineItem: [{ position: 10, label: 'Log ID' }]
    key LogId,

    @UI.lineItem: [{ position: 20, label: 'Request' }]
        ReqId,

    @UI.lineItem: [{ position: 30, label: 'Module' }]
    @UI.selectionField: [{ position: 10 }]
    @Search.defaultSearchElement: true
        ModuleId,

    @UI.lineItem: [{ position: 40, label: 'Action' }]
    @UI.selectionField: [{ position: 20 }]
    @Search.defaultSearchElement: true
        ActionType,

    @UI.lineItem: [{ position: 50, label: 'Environment' }]
    @UI.selectionField: [{ position: 30 }]
        EnvId,

    @UI.lineItem: [{ position: 60, label: 'Changed By' }]
    @UI.selectionField: [{ position: 40 }]
    @Search.defaultSearchElement: true
        ChangedBy,

    @UI.lineItem: [{ position: 70, label: 'Changed At' }]
    @UI.selectionField: [{ position: 50 }]
        ChangedAt,

        ConfId,
        TableName,
        OldData,
        NewData,
        ObjectKey
  }
