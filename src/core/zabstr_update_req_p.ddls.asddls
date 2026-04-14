@EndUserText.label: 'Cập nhật thông tin Request (Key User)'
define abstract entity ZABSTR_UPDATE_REQ_P
{
  @EndUserText.label: 'Tiêu đề Request'
  req_title : abap.string( 256 );

  @EndUserText.label: 'Lý do tạo Request'
  reason    : abap.string( 256 );
}
