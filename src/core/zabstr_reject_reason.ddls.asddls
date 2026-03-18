@EndUserText.label: 'Lý do từ chối'
define abstract entity ZABSTR_REJECT_REASON
{
  @EndUserText.label: 'Lý do (Reason)'
  reason : abap.string( 256 ); // Thay đổi thành 256 để hết lỗi
}
