import '../../data/models/course.dart';
import 'jwxt_adapter.dart';
import 'jwxt_html_parser.dart';
import 'qiangzhi_adapter.dart';
import 'zhengfang_adapter.dart';
import 'whu_graduate_adapter.dart';
import 'jwxt_system_family.dart';

/// 教务系统适配器注册表。
///
/// 学校目录只选择教务生态，真正的登录页仍由用户在 WebView 中完成；
/// 未收录学校使用通用表格适配器，避免把学校入口硬编码到课程页面。
class JwxtAdapterRegistry {
  const JwxtAdapterRegistry._();

  static final List<JwxtAdapter> all = <JwxtAdapter>[
    WhuGraduateAdapter(),
    ZhengFangAdapter(),
    QiangZhiAdapter(),
    GenericJwxtAdapter(id: 'eams', name: '树维 / EAMS 教务'),
    GenericJwxtAdapter(id: 'qg', name: '青果教务'),
    GenericJwxtAdapter(id: 'urp', name: 'URP 教务'),
    GenericJwxtAdapter(id: 'wisedu', name: '金智教务'),
    GenericJwxtAdapter(id: 'nanruan', name: '南软教务'),
    GenericJwxtAdapter(id: 'chaoxing', name: '超星教务'),
    GenericJwxtAdapter(id: 'generic', name: '通用表格解析'),
  ];

  static JwxtAdapter forId(String id) {
    for (final adapter in all) {
      if (adapter.id == id) return adapter;
    }
    return all.last;
  }

  static JwxtAdapter detect(String schoolUrl) {
    final value = schoolUrl.toLowerCase();
    if (value.contains('newyjs.whu.edu.cn')) {
      return forId('whu-graduate');
    }
    final explicitFamily = knownJwxtSystemFamily(schoolUrl);
    if (explicitFamily != null) return forId(explicitFamily);
    if (value.contains('eams') || value.contains('jxglstu.hfut.edu.cn')) {
      return forId('eams');
    }
    if (value.contains('/gmis') || value.contains('gmsstu.hfut.edu.cn')) {
      return forId('nanruan');
    }
    if (value.contains('gsapp/sys/') || value.contains('yjsemaphome')) {
      return forId('wisedu');
    }
    if (value.contains('qz') ||
        value.contains('qiangzhi') ||
        value.contains('jsxsd')) {
      return forId('qz');
    }
    if (value.contains('zfjw') ||
        value.contains('zhengfang') ||
        value.contains('xsxk')) {
      return forId('zjw');
    }
    if (value.contains('urp')) return forId('urp');
    if (value.contains('qingguo') || value.contains('qg')) {
      return forId('qg');
    }
    if (value.contains('wisedu') || value.contains('jinke')) {
      return forId('wisedu');
    }
    if (value.contains('nanruan')) return forId('nanruan');
    if (value.contains('chaoxing')) return forId('chaoxing');
    if (value.contains('jwxt') || value.contains('edu.cn')) {
      return forId('generic');
    }
    return forId('generic');
  }
}

/// 对常见教务生态提供同一套安全的 DOM 表格兜底解析。
/// 复杂的学校变体仍可在注册表中替换成独立 Adapter，不影响调用方。
class GenericJwxtAdapter extends JwxtAdapter {
  GenericJwxtAdapter({required this.id, required this.name});

  @override
  final String id;

  @override
  final String name;

  @override
  bool supports(String schoolUrl) => true;

  @override
  List<Course> parseHtml(String html) => JwxtHtmlParser.parse(html);
}
