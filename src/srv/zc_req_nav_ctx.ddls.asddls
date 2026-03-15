@EndUserText.label: 'Request Navigation Context'
define abstract entity ZC_REQ_NAV_CTX
{
  ReqId      : sysuuid_x16;
  ReqItemId  : sysuuid_x16;
  ConfId     : sysuuid_x16;
  ModuleId   : zde_module_id;
  TargetCds  : abap.char(30);
  TargetApp  : abap.char(30);
}
