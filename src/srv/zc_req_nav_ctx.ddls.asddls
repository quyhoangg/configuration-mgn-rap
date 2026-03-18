define abstract entity ZC_REQ_NAV_CTX
{
  ReqId      : abap.char(36);
  ReqItemId  : abap.char(36);
  ConfId     : abap.char(36);
  ModuleId   : zde_module_id;
  TargetCds  : abap.char(30);
  TargetApp  : abap.char(30);
}
