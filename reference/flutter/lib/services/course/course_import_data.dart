import 'dart:convert';
import '../../data/models/course.dart';

/// Shared validation for browser adapters and portable files. No silent weekday defaults.
class CourseImportData {
  static List<int> weeks(String text) {
    final compact = text
        .replaceAll(RegExp(r'\s|第|[()（）{}]'), '')
        .replaceAll('，', ',')
        .replaceAll('、', ',');
    const segment =
        r'(\d{1,2}(?:[-~至—]\d{1,2})?(?:,\d{1,2}(?:[-~至—]\d{1,2})?)*)(?:周)?([单双])?(?:周)?';
    final pattern = RegExp(segment);
    if (!RegExp('^(?:$segment)(?:,(?:$segment))*\$').hasMatch(compact)) {
      throw const FormatException('周次无法识别');
    }
    final matches = pattern.allMatches(compact).toList();
    if (matches.isEmpty ||
        compact.replaceAll(pattern, '').replaceAll(',', '').isNotEmpty) {
      throw const FormatException('周次无法识别');
    }
    final result = <int>{};
    for (final match in matches) {
      for (final part in match[1]!.split(',')) {
        final values = part.split(RegExp(r'[-~至—]')).map(int.parse).toList();
        final start = values.first, end = values.last;
        if (start < 1 || end > 60 || end < start) {
          throw const FormatException('周次须在 1–60 内');
        }
        for (var week = start; week <= end; week++) {
          if (match[2] == '单' && week.isEven) continue;
          if (match[2] == '双' && week.isOdd) continue;
          result.add(week);
        }
      }
    }
    if (result.isEmpty) throw const FormatException('周次为空');
    return result.toList()..sort();
  }

  static List<int> sections(String text) {
    final compact = text
        .replaceAll(RegExp(r'\s|第|[\[\]（）()]'), '')
        .replaceAll('，', ',')
        .replaceAll('、', ',')
        .replaceFirst(RegExp(r'节$'), '');
    // Sections share range expansion, but never week suffixes or parity rules.
    if (!RegExp(r'^\d{1,2}(?:[-~至—]\d{1,2})?(?:,\d{1,2}(?:[-~至—]\d{1,2})?)*$')
        .hasMatch(compact)) {
      throw const FormatException('节次无法识别');
    }
    final result = weeks(compact);
    if (result.any((n) => n > 24)) throw const FormatException('节次须在 1–24 内');
    return result;
  }

  static String identity(Course c) => jsonEncode([
        c.name.trim(),
        c.weekday.num,
        c.startPeriod,
        c.endPeriod,
        c.startWeek,
        c.endWeek,
        c.weekParity,
        c.teacher ?? '',
        c.room ?? '',
        c.note ?? '',
      ]);

  static List<Course> normalize(Iterable<Course> input) {
    final seen = <String>{};
    return input.where((c) {
      if (c.name.trim().isEmpty ||
          c.startPeriod < 1 ||
          c.endPeriod < c.startPeriod ||
          c.endPeriod > 24 ||
          c.startWeek < 1 ||
          c.endWeek > 60 ||
          c.endWeek < c.startWeek) {
        throw FormatException('课程信息无效：${c.name}');
      }
      return seen.add(identity(c));
    }).toList();
  }

  static List<Course> create(
      {required String name,
      required int day,
      required int start,
      required int end,
      required List<int> weeks,
      String? teacher,
      String? room,
      String? note}) {
    if (day < 1 || day > 7) throw const FormatException('星期须在 1–7 内');
    final ordered = weeks.toSet().toList()..sort();
    final result = <Course>[];
    // Separate discontinuous ranges instead of falsely scheduling skipped weeks.
    for (var i = 0; i < ordered.length;) {
      final first = ordered[i];
      var last = first;
      i++;
      while (i < ordered.length && ordered[i] == last + 1) {
        last = ordered[i++];
      }
      final key = jsonEncode(
          [name.trim(), day, start, end, first, last, teacher, room, note]);
      result.add(Course(
          id: 'import_${base64Url.encode(utf8.encode(key))}',
          name: name.trim(),
          weekday: Weekday.fromNum(day),
          startPeriod: start,
          endPeriod: end,
          startWeek: first,
          endWeek: last,
          teacher: teacher,
          room: room,
          note: note));
    }
    return normalize(result);
  }

  /// Standard IKO JSON and field-based Zhengfang / Qiangzhi / Wisedu exports.
  static List<Course> json(String text) {
    dynamic data = jsonDecode(text);
    for (var depth = 0; depth < 6 && data is Map; depth++) {
      final map = data;
      data = map['courses'] ??
          map['activities'] ??
          map['kbList'] ??
          map['rows'] ??
          map['data'] ??
          map['datas'] ??
          map['xsxkcx'] ??
          map['xskcb'];
    }
    if (data is! List || data.length > 2000) {
      throw const FormatException('未识别的课表 JSON 格式');
    }
    final result = <Course>[];
    for (final raw in data) {
      if (raw is! Map) throw const FormatException('课程必须为对象');
      String field(List<String> keys) {
        for (final key in keys) {
          if (raw[key] != null) return '${raw[key]}';
        }
        return '';
      }

      int? integer(List<String> keys) {
        for (final key in keys) {
          final value = raw[key];
          if (value == null) continue;
          final number = int.tryParse('$value'.trim());
          if (number == null) throw FormatException('$key 必须为整数');
          return number;
        }
        return null;
      }

      final nameValue =
          raw['name'] ?? raw['kcmc'] ?? raw['KCM'] ?? raw['courseName'];
      if (nameValue is! String || nameValue.trim().isEmpty) {
        throw const FormatException('缺少可识别的课程名称');
      }
      final name = nameValue.trim();
      final day = integer(['weekday', 'xqj', 'XQJ', 'day', 'dayOfWeek']);
      final periods = field(['jcs', 'JC', 'sections']);
      final start = integer(['startPeriod', 'startNode', 'startUnit']);
      final endValue = integer(['endPeriod', 'endUnit']);
      final step = integer(['step']);
      final end = endValue ?? (start == null ? null : start + (step ?? 1) - 1);
      if (step != null && step < 1 ||
          start == null && (end != null || step != null) ||
          start != null && (start < 1 || end! < start || end > 24)) {
        throw FormatException('节次须在 1–24 内且起止有序：$name');
      }
      final sectionList = start != null
          ? [for (var p = start; p <= end!; p++) p]
          : (periods.isEmpty ? <int>[] : sections(periods));
      final weekText = field(['zcd', 'ZC', 'weeks', 'weekText', 'weekIndexes']);
      final parity = integer(['weekParity']);
      if (parity != null && parity != 0 && parity != 1) {
        throw const FormatException('单双周须为 0、1 或 null');
      }
      final startWeek = integer(['startWeek']);
      final endWeek = integer(['endWeek']);
      final standardCourse = raw['name'] is String && raw['weekday'] != null;
      if (weekText.trim().isEmpty &&
          startWeek == null &&
          endWeek == null &&
          !standardCourse) {
        throw FormatException('未识别课程周次：$name；请导出含周次的完整课表');
      }
      final explicitWeeks = raw['weeks'] ?? raw['weekIndexes'];
      var weekList = explicitWeeks is List
          ? explicitWeeks.map((e) => int.parse('$e')).toList()
          : weeks(weekText.isNotEmpty
              ? weekText
              : '${startWeek ?? 1}-${endWeek ?? 20}周${parity == 1 ? '单' : parity == 0 ? '双' : ''}');
      if (parity == 0 || parity == 1) {
        weekList = weekList.where((w) => w % 2 == parity).toList();
      }
      if (day == null || sectionList.isEmpty || weekList.isEmpty) {
        throw FormatException('缺少星期或节次：$name');
      }
      for (var i = 0; i < sectionList.length;) {
        final first = sectionList[i++];
        var last = first;
        while (i < sectionList.length && sectionList[i] == last + 1) {
          last = sectionList[i++];
        }
        result.addAll(create(
            name: name,
            day: day,
            start: first,
            end: last,
            weeks: weekList,
            teacher: raw['teacherNames'] is List &&
                    (raw['teacherNames'] as List).every((v) => v is String)
                ? (raw['teacherNames'] as List).join('、')
                : field(['teacher', 'xm', 'jsxm', 'JSXM']),
            room: field(['room', 'cdmc', 'jsmc', 'JASMC', 'roomName']),
            note: field(['note'])));
      }
    }
    return normalize(result);
  }

  /// Quoted UTF-8 CSV, including WakeUp's public column names.
  static List<Course> csv(String source) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var quoted = false;
    final text = source.replaceFirst('\uFEFF', '').replaceAll('\r\n', '\n');
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (c == '"') {
        if (quoted && i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = !quoted;
        }
      } else if (!quoted && (c == ',' || c == '\n')) {
        row.add(field.toString().trim());
        field = StringBuffer();
        if (c == '\n') {
          if (row.any((e) => e.isNotEmpty)) rows.add(row);
          row = [];
        }
      } else {
        field.write(c);
      }
    }
    if (quoted) throw const FormatException('CSV 引号未闭合');
    row.add(field.toString().trim());
    if (row.any((e) => e.isNotEmpty)) rows.add(row);
    if (rows.length < 2) throw const FormatException('CSV 为空');
    final header = rows.removeAt(0);
    final objects = rows.map((values) {
      String get(List<String> names, [String fallback = '']) {
        for (final name in names) {
          final n = header.indexOf(name);
          if (n >= 0 && n < values.length) return values[n];
        }
        return fallback;
      }

      final week = get(['周次', 'weeks']);
      return {
        'name': get(['课程名称', '课程名', 'name']),
        'weekday': get(['星期', '星期几', 'weekday']),
        'startPeriod': get(['开始节数', '开始节次', 'startPeriod']),
        'endPeriod': get(['结束节数', '结束节次', 'endPeriod']),
        'weekParity': switch (get(['单双周', 'weekParity'])) {
          '单' || '单周' || '1' => 1,
          '双' || '双周' || '0' => 0,
          '' || '每周' || '全部' => null,
          _ => throw const FormatException('单双周无法识别，请使用单周、双周或每周'),
        },
        'zcd': week.isNotEmpty
            ? week
            : '${get(['开始周', 'startWeek'], '1')}-${get([
                    '结束周',
                    'endWeek'
                  ], '20')}周',
        'teacher': get(['教师', '老师', 'teacher']),
        'room': get(['教室', '地点', 'room'])
      };
    }).toList();
    return json(jsonEncode(objects));
  }
}
