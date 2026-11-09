/// 条款文档的一节。
///
/// 标题自带序号（「一、」「1.」），由文案决定，渲染层不再拼号——中英文的
/// 编号习惯不同，交给译者比交给代码可靠。
class TermsSection {
  const TermsSection(this.title, this.body);

  final String title;

  /// 正文。段与段之间用空行分隔，渲染时按原样保留换行。
  final String body;
}
