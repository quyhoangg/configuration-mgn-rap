@AbapCatalog.sqlViewName: 'ZCURRENTUSERROLE'
@AbapCatalog.compiler.compareFilter: true
@AbapCatalog.preserveKey: true
@AccessControl.authorizationCheck: #NOT_REQUIRED
@EndUserText.label: 'Current User Role Info'

define view ZI_CURRENT_USER_ROLE
  as select from zuserrole
{
  key user_id    as UserId,
  key module_id  as ModuleId,
      role_level as RoleLevel,
      is_active  as IsActive,
      org_access as OrgAccess
}
