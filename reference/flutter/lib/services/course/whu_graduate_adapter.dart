import 'package:html/parser.dart' as dom;
import 'package:webview_flutter/webview_flutter.dart';

import '../../data/models/course.dart';
import 'course_import_data.dart';
import 'jwxt_adapter.dart';
import 'jwxt_html_parser.dart';

typedef _CourseKey = ({String name, int day, String teacher, String room});
typedef _IntervalKey = ({_CourseKey course, int start, int end});

/// 武汉大学研究生综合服务平台的「教学管理 → 我的课表 → 学生课程表」。
/// 页面在同源 iframe 中把同一节课按节次重复渲染，必须按实际周、节合并。
class WhuGraduateAdapter extends JwxtAdapter {
  @override
  String get id => 'whu-graduate';

  @override
  String get name => '武汉大学研究生课表';

  @override
  bool supports(String schoolUrl) =>
      Uri.tryParse(schoolUrl)?.host.toLowerCase() == 'newyjs.whu.edu.cn';

  @override
  Future<bool> navigateToTimetablePage(WebViewController controller) async {
    final result = await controller.runJavaScriptReturningResult(r'''(() => {
      for (const frame of document.querySelectorAll('iframe')) {
        try {
          if (frame.contentDocument?.querySelector('#jsTbl_01 .arrage')) {
            return true;
          }
        } catch (_) {}
      }
      const menu = document.querySelector(
        '.lmenu-ejcd-list-app[data-appid="wdkbapp"]');
      const course = menu?.querySelector(
        '.lmenu-level-3-content[data-caidandm="xskcb"]');
      if (!menu || !course) return false;
      if (!menu.querySelector('.lmenu-sjcd-list-app.dropdown-menu-show')) {
        menu.querySelector('.lmenu-level-2-content')?.click();
      }
      course.click();
      return true;
    })()''');
    return result == true || result.toString() == 'true';
  }

  @override
  List<Course> parseHtml(String html) {
    final document = dom.parse(html);
    final cells = document
        .querySelectorAll('table.mtt_table1 td[jc][xq]')
        .where((cell) => cell.querySelector('.arrage') != null)
        .toList();
    if (cells.isEmpty) return JwxtHtmlParser.parse(html);

    final byWeek = <_CourseKey, Map<int, Set<int>>>{};
    for (final cell in cells) {
      final period = int.tryParse(cell.attributes['jc'] ?? '');
      final span = int.tryParse(cell.attributes['rowspan'] ?? '1');
      final schoolDay = int.tryParse(cell.attributes['xq'] ?? '');
      if (period == null ||
          period < 1 ||
          period > 24 ||
          span == null ||
          span < 1 ||
          period + span - 1 > 24 ||
          schoolDay == null ||
          schoolDay < 1 ||
          schoolDay > 7) {
        throw const FormatException('武汉大学课表节次或星期无法识别');
      }
      // 学校表格从星期日列开始，但 xq 属性仍是周一=1、周日=7。
      final day = schoolDay;
      for (final block in cell.querySelectorAll('.arrage')) {
        final fields =
            block.children.map((child) => child.text.trim()).toList();
        if (fields.length < 4 || fields[1].isEmpty) {
          throw const FormatException('武汉大学课表课程字段不完整');
        }
        final weeks = CourseImportData.weeks(fields[0]);
        final key = (
          name: fields[1],
          day: day,
          teacher: fields[2],
          room: fields[3],
        );
        final slots = byWeek.putIfAbsent(key, () => <int, Set<int>>{});
        for (final week in weeks) {
          final periods = slots.putIfAbsent(week, () => <int>{});
          for (var offset = 0; offset < span; offset++) {
            periods.add(period + offset);
          }
        }
      }
    }

    final intervals = <_IntervalKey, Set<int>>{};
    for (final entry in byWeek.entries) {
      for (final weekEntry in entry.value.entries) {
        final periods = weekEntry.value.toList()..sort();
        for (var index = 0; index < periods.length;) {
          final start = periods[index++];
          var end = start;
          while (index < periods.length && periods[index] == end + 1) {
            end = periods[index++];
          }
          intervals.putIfAbsent((course: entry.key, start: start, end: end),
              () => <int>{}).add(weekEntry.key);
        }
      }
    }

    final courses = <Course>[];
    for (final entry in intervals.entries) {
      final key = entry.key.course;
      courses.addAll(CourseImportData.create(
        name: key.name,
        day: key.day,
        start: entry.key.start,
        end: entry.key.end,
        weeks: entry.value.toList(),
        teacher: key.teacher.isEmpty ? null : key.teacher,
        room: key.room.isEmpty ? null : key.room,
      ));
    }
    courses.sort((a, b) {
      final day = a.weekday.num.compareTo(b.weekday.num);
      if (day != 0) return day;
      final period = a.startPeriod.compareTo(b.startPeriod);
      if (period != 0) return period;
      final name = a.name.compareTo(b.name);
      return name != 0 ? name : a.startWeek.compareTo(b.startWeek);
    });
    return CourseImportData.normalize(courses);
  }
}
