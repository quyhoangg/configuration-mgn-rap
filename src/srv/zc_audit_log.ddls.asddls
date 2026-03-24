@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Audit Log Projection View'
@Metadata.ignorePropagatedAnnotations: true
@Search.searchable: true
@UI: {
  headerInfo: {
    typeName: 'Audit Log Entry',
    typeNamePlural: 'Audit Log Entries',
    title: { type: #STANDARD, value: 'LogId' },
    description: { value: 'ActionType' }
  }
}
define view entity ZC_AUDIT_LOG
  as select from ZI_AUDIT_LOG
{
  @UI.facet: [
    { id: 'AuditInfo', purpose: #STANDARD, type: #IDENTIFICATION_REFERENCE, label: 'Audit Information', position: 10 },
    { id: 'DataChanges', purpose: #STANDARD, type: #FIELDGROUP_REFERENCE, targetQualifier: 'DataChangesGroup', label: 'Data Changes', position: 20 }
  ]

  @UI.identification: [{ position: 10, label: 'Log ID' }]
  @UI.lineItem: [{ position: 10, label: 'Log ID' }]
  key LogId,

  @UI.identification: [{ position: 20, label: 'Request' }]
  @UI.lineItem: [{ position: 20, label: 'Request' }]
      ReqId,

  @UI.identification: [{ position: 30, label: 'Module' }]
  @UI.lineItem: [{ position: 30, label: 'Module' }]
  @UI.selectionField: [{ position: 10 }]
  @Search.defaultSearchElement: true
      ModuleId,

  @UI.identification: [{ position: 40, label: 'Action' }]
  @UI.lineItem: [{ position: 40, label: 'Action' }]
  @UI.selectionField: [{ position: 20 }]
  @Search.defaultSearchElement: true
      ActionType,

  @UI.identification: [{ position: 50, label: 'Environment' }]
  @UI.lineItem: [{ position: 50, label: 'Environment' }]
  @UI.selectionField: [{ position: 30 }]
      EnvId,

  @UI.identification: [{ position: 60, label: 'Changed By' }]
  @UI.lineItem: [{ position: 60, label: 'Changed By' }]
  @UI.selectionField: [{ position: 40 }]
  @Search.defaultSearchElement: true
      ChangedBy,

  @UI.identification: [{ position: 70, label: 'Changed At' }]
  @UI.lineItem: [{ position: 70, label: 'Changed At' }]
  @UI.selectionField: [{ position: 50 }]
      ChangedAt,

  @UI.identification: [{ position: 80, label: 'Configuration ID' }]
      ConfId,
      
  @UI.identification: [{ position: 90, label: 'Table Name' }]
      TableName,

  @UI.fieldGroup: [{ qualifier: 'DataChangesGroup', position: 10, label: 'Old Data' }]
  @UI.multiLineText: true
      OldData,

  @UI.fieldGroup: [{ qualifier: 'DataChangesGroup', position: 20, label: 'New Data' }]
  @UI.multiLineText: true
      NewData,
      
  @UI.identification: [{ position: 100, label: 'Object Key' }]
      ObjectKey
}
// >>> THÊM MỆNH ĐỀ WHERE VÀO ĐÂY ĐỂ CHỈ HIỂN THỊ LOG DUYỆT <<<
where ActionType = 'APPROVE'
