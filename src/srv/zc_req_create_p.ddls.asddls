define abstract entity ZC_REQ_CREATE_P
{
  ConfId      : abap.char(36);  
  ModuleId    : zde_module_id;
  ConfName    : abap.char(100);
  TargetCds   : abap.char(30);
  ActionType  : zde_action_type;
  TargetEnvId : zde_env_id;
  Reason      : abap.char(255);
  Notes       : abap.char(255);
}
