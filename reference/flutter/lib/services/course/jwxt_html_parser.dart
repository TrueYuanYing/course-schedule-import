import 'package:html/dom.dart';
import 'package:html/parser.dart' as dom;
import '../../data/models/course.dart';
import 'course_import_data.dart';

/// DOM grid preserves weekdays across merged cells. Unknown layouts are rejected.
class JwxtHtmlParser {
  static List<Course> parse(String html) {
    if (html.length > 6 * 1024 * 1024) throw const FormatException('课表文件过大');
    final document = dom.parse(html);
    final courses = <Course>[];
    for (final table in document.querySelectorAll('table')) {
      final rows = table
          .querySelectorAll('tr')
          .where((r) => _tableOf(r) == table)
          .toList();
      final grid = <List<_Cell?>>[];
      for (var r = 0; r < rows.length && r < 256; r++) {
        while (grid.length <= r) {
          grid.add([]);
        }
        var col = 0;
        for (final element in rows[r]
            .children
            .where((e) => e.localName == 'td' || e.localName == 'th')) {
          while (col < grid[r].length && grid[r][col] != null) {
            col++;
          }
          final rs = (int.tryParse(element.attributes['rowspan'] ?? '1') ?? 1)
              .clamp(1, 48);
          final cs = (int.tryParse(element.attributes['colspan'] ?? '1') ?? 1)
              .clamp(1, 32);
          final cell = _Cell(element, r, rs);
          for (var y = r; y < r + rs; y++) {
            while (grid.length <= y) {
              grid.add([]);
            }
            while (grid[y].length < col + cs) {
              grid[y].add(null);
            }
            for (var x = col; x < col + cs; x++) {
              grid[y][x] = cell;
            }
          }
          col += cs;
        }
      }
      final listCourses = _listTable(grid);
      if (listCourses != null) {
        courses.addAll(listCourses);
        continue;
      }
      final days = <int, int>{};
      var header = -1;
      for (var r = 0; r < grid.length; r++) {
        for (var c = 0; c < grid[r].length; c++) {
          final day = _weekday(grid[r][c]?.element.text ?? '');
          if (day != null) days[c] = day;
        }
        if (days.isNotEmpty) {
          header = r;
          break;
        }
      }
      if (header < 0) continue;
      final firstDay = days.keys.reduce((a, b) => a < b ? a : b);
      final parsed = <Element>{};
      for (var r = header + 1; r < grid.length; r++) {
        final labels =
            grid[r].take(firstDay).map((c) => c?.element.text ?? '').toList();
        final rowPeriod = labels.map(_period).whereType<List<int>>().lastOrNull;
        for (final entry in days.entries) {
          if (entry.key >= grid[r].length) continue;
          final cell = grid[r][entry.key];
          if (cell == null || cell.row != r || !parsed.add(cell.element)) {
            continue;
          }
          final blocks = cell.element
              .querySelectorAll('.timetable_con, .kbcontent, .course-item');
          final sources = blocks.isEmpty
              ? [cell.element]
              : blocks
                  .where((e) => !blocks.any((p) => p != e && _isInside(p, e)))
                  .toList();
          var range = rowPeriod;
          if (rowPeriod != null && cell.rowspan > 1) {
            final last = (r + cell.rowspan - 1).clamp(0, grid.length - 1);
            final end = grid[last]
                .take(firstDay)
                .map((c) => _period(c?.element.text ?? ''))
                .whereType<List<int>>()
                .lastOrNull;
            range = [
              rowPeriod[0],
              end?.last ?? (rowPeriod[1] + cell.rowspan - 1)
            ];
          }
          for (final source in sources) {
            for (final block in _text(source)
                .split(RegExp(r'\n\s*[-—]{3,}\s*\n|\n{2,}|(?=课程名称\s*[:：])'))) {
              courses.addAll(_course(block, entry.value, range, 1));
            }
          }
        }
      }
    }
    return CourseImportData.normalize(courses);
  }

  // Graduate systems often render one lesson per row rather than a weekly grid.
  // Only explicit column headings qualify: never infer a weekday or week range.
  static List<Course>? _listTable(List<List<_Cell?>> grid) {
    for (var r = 0; r < grid.length; r++) {
      final labels = grid[r]
          .map((c) => c?.element.text.replaceAll(RegExp(r'\s'), '') ?? '')
          .toList();
      int column(List<String> names) => labels.indexWhere(names.contains);
      final name = column(['课程名称', '课程名', '课程']);
      final day = column(['星期', '星期几', '周几', '上课星期']);
      final sections = column(['节次', '上课节次', '课节']);
      final weeks = column(['周次', '上课周次', '教学周']);
      if ([name, day, sections, weeks].any((n) => n < 0)) continue;
      final teacher = column(['教师', '任课教师', '授课教师']);
      final room = column(['教室', '上课地点', '地点']);
      final result = <Course>[];
      for (final row in grid.skip(r + 1)) {
        String value(int col) => col < 0 || col >= row.length
            ? ''
            : row[col]?.element.text.trim() ?? '';
        if (value(name).isEmpty || value(name) == labels[name]) continue;
        final exactDay = RegExp(r'^(?:(?:星期|周|礼拜)\s*)?([一二三四五六日天1-7])$')
            .firstMatch(value(day));
        final weekday = exactDay == null ? null : _weekday('周${exactDay[1]}');
        if (weekday == null) {
          throw const FormatException('列表课表未识别星期，请选择含完整上课安排的课表');
        }
        final periods = CourseImportData.sections(value(sections));
        final weekList = CourseImportData.weeks(value(weeks));
        for (var i = 0; i < periods.length;) {
          final start = periods[i++];
          var end = start;
          while (i < periods.length && periods[i] == end + 1) {
            end = periods[i++];
          }
          result.addAll(CourseImportData.create(
              name: value(name),
              day: weekday,
              start: start,
              end: end,
              weeks: weekList,
              teacher: value(teacher),
              room: value(room)));
        }
      }
      return result;
    }
    return null;
  }

  static bool _isInside(Element e, Element ancestor) {
    var p = e.parent;
    while (p != null) {
      if (p == ancestor) return true;
      p = p.parent;
    }
    return false;
  }

  static Element? _tableOf(Element e) {
    var p = e.parent;
    while (p != null && p.localName != 'table') {
      p = p.parent;
    }
    return p;
  }

  static int? _weekday(String text) {
    final match =
        RegExp(r'^(?:星期|周|礼拜)\s*([一二三四五六日天1-7])').firstMatch(text.trim());
    if (match == null) return null;
    return int.tryParse(match[1]!) ??
        (match[1] == '天' ? 7 : '一二三四五六日'.indexOf(match[1]!) + 1);
  }

  static List<int>? _period(String text) {
    final runs = _periodRuns(text);
    if (runs == null || runs.isEmpty) return null;
    return [runs.first.first, runs.last.last];
  }

  static List<List<int>>? _periodRuns(String text) {
    var value = text.trim().replaceAll(RegExp(r'\s|第|节|[\[\]（）()]'), '');
    if (RegExp(r'^[Ff]\d{1,2}$').hasMatch(value)) value = value.substring(1);
    const chinese = {
      '一': '1',
      '二': '2',
      '三': '3',
      '四': '4',
      '五': '5',
      '六': '6',
      '七': '7',
      '八': '8',
      '九': '9',
      '十': '10',
      '十一': '11',
      '十二': '12',
      '十三': '13',
      '十四': '14'
    };
    value = chinese[value] ?? value;
    if (!RegExp(r'^\d{1,2}(?:[-~至—,，]\d{1,2})*$').hasMatch(value)) return null;
    final ranges = <List<int>>[];
    for (final part in value.split(RegExp(r'[,，]'))) {
      final n = part.split(RegExp(r'[-~至—]')).map(int.parse).toList();
      if (n.length == 1) {
        if (n.first < 1 || n.first > 24) return null;
        ranges.add([n.first, n.first]);
      } else if (n.length == 2 &&
          n.first >= 1 &&
          n.last <= 24 &&
          n.last >= n.first) {
        ranges.add([n.first, n.last]);
      } else {
        return null;
      }
    }
    return ranges;
  }

  static String _text(Element element) {
    final copy = element.clone(true);
    copy.querySelectorAll('script,style,.sr-only').forEach((e) => e.remove());
    for (final node in copy.querySelectorAll('[title]')) {
      final title = node.attributes['title'] ?? '';
      if (RegExp(r'教师|老师|教室|地点|周次|节次').hasMatch(title) &&
          !node.text.contains('：')) {
        node.nodes.insert(0, Text('$title：'));
      }
    }
    var html = copy.innerHtml
        .replaceAll(RegExp(r'\r?\n'), ' ')
        .replaceAll(RegExp(r'>\s+<'), '><');
    if (!copy.classes.contains('course-item') &&
        !copy.classes.contains('timetable_con')) {
      html = html.replaceAll(
          RegExp(r'<br\s*/?>\s*<br\s*/?>', caseSensitive: false), '\n---\n');
    }
    final value = html
        .replaceAll(RegExp(r'<hr\b[^>]*>', caseSensitive: false), '\n---\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</(?:div|p|li|h\d)>', caseSensitive: false), '\n');
    return (dom.parseFragment(value).text ?? '')
        .replaceAll(RegExp(r'\n[ \t]*\n+'), '\n');
  }

  static List<Course> _course(
      String text, int day, List<int>? rowPeriod, int span) {
    final lines = text
        .split(RegExp(r'\n|[;；]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (lines.isEmpty) return [];
    // Graduate weekly cells can hold several independent inline records. Keep
    // each teacher/week pair separate; never union their weeks into one course.
    if (rowPeriod != null) {
      final inline = RegExp(
          r'([^\[\]【】\n]+?)\s*[\[【]\s*([^\]】]*周[^\]】]*)[\]】]\s*([^\[\]【】\n]*?)\s*[\[【]([^\]】]+)[\]】]');
      final matches = inline.allMatches(text).toList();
      if (matches.isNotEmpty && text.replaceAll(inline, '').trim().isEmpty) {
        return [
          for (final match in matches)
            ...CourseImportData.create(
                name: match[1]!.trim(),
                day: day,
                start: rowPeriod[0],
                end: rowPeriod[1],
                weeks: CourseImportData.weeks(match[2]!),
                teacher: match[3]!.trim(),
                room: match[4]!.trim())
        ];
      }
    }
    final weekPattern = RegExp(
        r'(?:第)?\d{1,2}(?:\s*[-~至—]\s*\d{1,2})?(?:\s*[,，、]\s*\d{1,2}(?:\s*[-~至—]\s*\d{1,2})?)*\s*[（(]?周[）)]?\s*(?:[（(]?[单双]周?[）)]?)?');
    final weekMatches = weekPattern.allMatches(text).map((m) => m[0]!).toList();
    final explicitPeriod =
        RegExp(r'(\d{1,2}(?:\s*[-~至—,，]\s*\d{1,2})*)\s*[\]）)]?\s*节')
            .firstMatch(text);
    final periodRuns = explicitPeriod == null
        ? (rowPeriod == null ? null : <List<int>>[rowPeriod])
        : _periodRuns(explicitPeriod[1]!);
    if (periodRuns == null || periodRuns.isEmpty) return [];
    final name = lines.first
        .replaceAll(weekPattern, '')
        .replaceFirst(RegExp(r'^课程(?:名称)?\s*[:：]'), '')
        .trim();
    if (name.isEmpty ||
        RegExp(r'^(无课|教师|老师|教室|地点|星期|节次|\d+$)').hasMatch(name)) {
      return [];
    }
    String? teacher, room;
    for (final line in lines.skip(1)) {
      if (weekPattern.hasMatch(line) ||
          RegExp(r'节|课程性质|学分|学时|班级').hasMatch(line)) {
        continue;
      }
      final value = line.replaceFirst(RegExp(r'^.*?[:：]\s*'), '');
      if (RegExp(r'教师|老师|讲师').hasMatch(line)) {
        teacher = value;
      } else if (RegExp(r'教室|地点|教学楼|[A-Za-z]\d{2,}|\d{3,}|室|楼|栋')
          .hasMatch(line)) {
        room = value;
      } else {
        teacher ??= value;
      }
    }
    if (weekMatches.isEmpty) {
      throw FormatException('缺少明确课程周次：$name；请打开或导出含完整周次的学期课表');
    }
    final weeks = CourseImportData.weeks(weekMatches.join(','));
    final result = <Course>[];
    for (final run in periodRuns) {
      final end = explicitPeriod == null && run[0] == run[1]
          ? run[0] + span - 1
          : run[1];
      result.addAll(CourseImportData.create(
          name: name,
          day: day,
          start: run[0],
          end: end,
          weeks: weeks,
          teacher: teacher,
          room: room));
    }
    return result;
  }
}

class _Cell {
  _Cell(this.element, this.row, this.rowspan);
  final Element element;
  final int row, rowspan;
}
