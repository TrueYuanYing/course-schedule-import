import 'dart:convert';

import '../../data/models/course.dart';
import 'course_import_data.dart';
import 'course_periods.dart';

/// Maps the confirmed jwimport v1 result without filling missing weeks or periods.
class AcademicImportResult {
  AcademicImportResult({
    required this.school,
    required this.adapter,
    required this.courses,
    required this.warnings,
    this.periodTimes=const {},
  });

  final String school;
  final String adapter;
  final List<Course> courses;
  final List<String> warnings;
  final Map<int,CoursePeriod> periodTimes;

  static AcademicImportResult parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map || decoded['schemaVersion'] != 1) {
      throw const FormatException('教务导入结果版本无效');
    }
    final rows = decoded['courses'];
    if (rows is! List || rows.isEmpty || rows.length > 5000) {
      throw const FormatException('教务导入课程数量无效');
    }
    final rawWarnings = decoded['warnings'];
    if (rawWarnings is! List || rawWarnings.length > 1000) {
      throw const FormatException('教务导入警告列表无效');
    }
    final courses = <Course>[];
    for (final row in rows) {
      if (row is! Map ||
          row['name'] is! String ||
          (row['name'] as String).trim().isEmpty ||
          row['day'] is! int) {
        throw const FormatException('教务导入课程字段无效');
      }
      final sections = _ordered(row['sections'], 24, '节次');
      final weeks = _ordered(row['weeks'], 60, '周次');
      for (var index = 0; index < sections.length;) {
        final first = sections[index++];
        var last = first;
        while (index < sections.length && sections[index] == last + 1) {
          last = sections[index++];
        }
        courses.addAll(CourseImportData.create(
          name: row['name'] as String,
          day: row['day'] as int,
          start: first,
          end: last,
          weeks: weeks,
          teacher: _optional(row['teacher']),
          room: _optional(row['room']),
          note: _optional(row['note']),
        ));
        if (courses.length > 5000) {
          throw const FormatException('教务导入展开后的课程数量过多');
        }
      }
    }
    return AcademicImportResult(
      school: _optional(decoded['school']) ?? '',
      adapter: _optional(decoded['adapter']) ?? '',
      courses: CourseImportData.normalize(courses),
      periodTimes:CoursePeriods.parseTimes(decoded['periodTimes']),
      warnings: [
        for (final warning in rawWarnings)
          if (warning is Map && warning['message'] is String)
            [warning['name'], warning['message']]
                .whereType<String>()
                .where((part) => part.trim().isNotEmpty)
                .join('：'),
      ],
    );
  }

  static List<int> _ordered(Object? value, int max, String label) {
    if (value is! List || value.isEmpty || value.length > max) {
      throw FormatException('$label列表无效');
    }
    final ordered = <int>[];
    for (final part in value) {
      if (part is! int ||
          part < 1 ||
          part > max ||
          ordered.isNotEmpty && part <= ordered.last) {
        throw FormatException('$label列表须递增且在 1–$max 内');
      }
      ordered.add(part);
    }
    return ordered;
  }

  static String? _optional(Object? value) {
    if (value == null) return null;
    if (value is! String || value.length > 1000) {
      throw const FormatException('教务导入文字字段无效');
    }
    return value.trim().isEmpty ? null : value.trim();
  }
}
