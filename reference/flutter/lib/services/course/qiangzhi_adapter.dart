import '../../data/models/course.dart';
import 'jwxt_adapter.dart';
import 'jwxt_html_parser.dart';

/// 强智教务系统适配器。
/// 覆盖另一批高校。课表数据通常通过 `getKbcx`/`kbcx_xs` 接口返回。
class QiangZhiAdapter extends JwxtAdapter {
  @override
  String get id => 'qz';

  @override
  String get name => '强智教务';

  @override
  bool supports(String schoolUrl) =>
      schoolUrl.contains('jsxsd') ||
      schoolUrl.contains('jwxt') ||
      schoolUrl.contains('qzh') ||
      schoolUrl.contains('xk');

  @override
  List<Course> parseHtml(String html) => JwxtHtmlParser.parse(html);
}
