import 'dart:convert';

import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/course.dart';
import 'course_import_data.dart';

/// 教务系统适配器接口。
/// 不同院校教务系统（正方/强智/青果/URP…）实现各自登录与抓课表逻辑，
/// 通过统一的 [Course] 输出课程列表。第一版内置正方 + 强智。
abstract class JwxtAdapter {
  /// 适配器标识（zjw / qz / qg ...）。
  String get id;

  /// 适配器显示名。
  String get name;

  /// 是否支持该校（通过学校域名/登录页特征判断）。
  bool supports(String schoolUrl);

  /// 在已登录页面进入课程表。学校 SPA 可覆盖此方法直接点击内部菜单。
  Future<bool> navigateToTimetablePage(WebViewController controller) async {
    final uri = await discoverTimetablePage(controller);
    if (uri == null) return false;
    await controller.loadRequest(uri);
    return true;
  }

  /// 登录后抓取课表。返回解析后的课程。
  Future<List<Course>> fetchTimetable(WebViewController controller) async {
    final html = await readPageHtml(controller);
    FormatException? parseError;
    try {
      final courses = CourseImportData.normalize(parseHtml(html));
      if (courses.isNotEmpty) return courses;
    } on FormatException catch (error) {
      parseError = error;
    }
    // Read only known timetable data already loaded by the user's authenticated page.
    // No password capture, guessed API calls, or remote adapter scripts.
    final value = await controller.runJavaScriptReturningResult(r'''(() => {
      const candidates = [];
      const seen = new Set();
      function collect(win) {
        if (seen.has(win)) return; seen.add(win);
        try {
          for (const key of ['kbList','courseList','kcbData','activities']) {
            const value = win[key];
            if (Array.isArray(value) && value.length <= 2000) candidates.push(value);
          }
          const pre = win.document.querySelector('pre');
          if (pre && pre.textContent.length < 2000000) {
            try { candidates.push(JSON.parse(pre.textContent)); } catch (_) {}
          }
          for (const frame of win.document.querySelectorAll('iframe,frame')) collect(frame.contentWindow);
        } catch (_) {}
      }
      collect(window);
      return JSON.stringify(candidates);
    })()''');
    dynamic decoded = value;
    for (var i = 0; i < 2 && decoded is String; i++) {
      decoded = jsonDecode(decoded);
    }
    if (decoded is List) {
      for (final candidate in decoded) {
        try {
          final parsed = CourseImportData.json(jsonEncode(candidate));
          if (parsed.isNotEmpty) return parsed;
        } on FormatException catch (error) {
          parseError ??= error;
          continue;
        }
      }
    }
    if (parseError != null) throw parseError;
    return [];
  }

  /// 从登录后的当前页面寻找可能的课表入口。不同学校的菜单命名很多，
  /// 这里只做低风险的同页入口发现，不提交表单、不读取密码、不跨域抓取。
  Future<Uri?> discoverTimetablePage(WebViewController controller) async {
    final value = await controller.runJavaScriptReturningResult(
      r'''(() => {
        const pattern = /课表|课程表|教学安排|timetable|schedule|kbcx|kcb/i;
        const sameOrigin = href => {
          try {
            return new URL(href, location.href).origin === location.origin;
          } catch (_) {
            return false;
          }
        };
        const nodes = document.querySelectorAll(
          'a,button,[role="button"],[data-url],[data-href],[routerlink],'
          '[data-route],[data-target],[ng-href]'
        );
        for (const anchor of nodes) {
          const text = [
            anchor.innerText || '',
            anchor.getAttribute('href') || '',
            anchor.getAttribute('onclick') || '',
            anchor.getAttribute('data-url') || '',
            anchor.getAttribute('data-href') || '',
            anchor.getAttribute('routerlink') || '',
            anchor.getAttribute('data-route') || '',
            anchor.getAttribute('data-target') || '',
            anchor.getAttribute('ng-href') || '',
          ].join(' ');
          if (pattern.test(text)) {
            const href = anchor.href ||
              anchor.getAttribute('data-url') ||
              anchor.getAttribute('data-href') ||
              anchor.getAttribute('routerlink') ||
              anchor.getAttribute('data-route') ||
              anchor.getAttribute('data-target') ||
              anchor.getAttribute('ng-href') ||
              '';
            if (href && sameOrigin(href)) return new URL(href, location.href).href;
          }
        }
        // XHR URLs are not navigation targets: opening them can discard SPA state.
        return '';
      })()''',
    );
    var raw = value.toString();
    if (raw.length >= 2 && raw.startsWith('"') && raw.endsWith('"')) {
      try {
        raw = jsonDecode(raw) as String;
      } catch (_) {
        // Some WebView implementations return a plain string.
      }
    }
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.host.isEmpty) return null;
    return uri;
  }

  /// 将当前页面 HTML 转成课程，便于不同学校在子类中覆盖。
  List<Course> parseHtml(String html);

  /// 读取 WebView 当前页面，兼容返回 JSON 字符串的实现。
  Future<String> readPageHtml(WebViewController controller) async {
    final value = await controller.runJavaScriptReturningResult(
      r'''(() => {
        const pages = [];
        const collect = root => {
          const html = root.documentElement?.outerHTML || root.innerHTML || '';
          if (html) pages.push(html);
          const nodes = root.querySelectorAll ? root.querySelectorAll('*') : [];
          for (const node of nodes) {
            if (node.shadowRoot?.innerHTML) pages.push(node.shadowRoot.innerHTML);
          }
        };
        const seen = new Set();
        const visit = root => {
          if (!root || seen.has(root) || seen.size >= 16) return;
          seen.add(root); collect(root);
          for (const frame of root.querySelectorAll('iframe,frame')) {
            try { visit(frame.contentDocument); } catch (_) {}
          }
        };
        visit(document);
        return JSON.stringify(pages.join('\n'));
      })()''',
    );
    var html = value.toString();
    // The script JSON-encodes the HTML and Android WebView may encode the
    // JavaScript string result again. Stop as soon as the value is no longer
    // a quoted JSON string; decoding only once leaves literal \t and \n.
    for (var depth = 0; depth < 2; depth++) {
      if (html.length < 2 || !html.startsWith('"') || !html.endsWith('"')) {
        break;
      }
      try {
        html = jsonDecode(html) as String;
      } catch (_) {
        break;
      }
    }
    return html;
  }
}
