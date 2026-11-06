import '../../data/models/course.dart';
import 'jwxt_adapter.dart';
import 'jwxt_html_parser.dart';

/// 正方教务系统适配器（覆盖国内大量高校）。
/// 登录：WebView 打开学校正方首页 → 用户登录 → JS 注入抓取课表。
/// 课表数据通常藏在 `xkAction` 或打印课表页面的 html 里，需解析。
class ZhengFangAdapter extends JwxtAdapter {
  @override
  String get id => 'zjw';

  @override
  String get name => '正方教务';

  @override
  bool supports(String schoolUrl) =>
      schoolUrl.contains('jw') ||
      schoolUrl.contains('xsxk') ||
      schoolUrl.contains('zfjw') ||
      schoolUrl.contains('jsxsd');

  @override
  List<Course> parseHtml(String html) => JwxtHtmlParser.parse(html);
}
