import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../data/models/course.dart';
import 'course_import_data.dart';
import 'academic_calendar.dart';
import 'course_periods.dart';

/// 课表存储：用 SharedPreferences 存课程列表 JSON。
/// 简单可靠，web/移动端通用，避免 drift 在 web 平台的问题。
class CourseStore {
  CourseStore._(this._prefs, this._courses, this.recoveredEntryCount);

  final SharedPreferences _prefs;
  final List<Course> _courses;
  final int recoveredEntryCount;

  DateTime? get semesterStart =>
      DateTime.tryParse(_prefs.getString('courses.semesterStart') ?? '');
  AcademicCalendar get calendar => AcademicCalendar(startDate: semesterStart);
  CoursePeriods get periods =>
      CoursePeriods.decode(_prefs.getString('courses.periods'));
  Future<void> setPeriods(CoursePeriods periods) async {
    final saved = await _prefs.setString('courses.periods', periods.encode());
    if (!saved) throw StateError('作息未能保存，请重试。');
  }

  Future<void> setSemesterStart(DateTime date) async {
    await _prefs.setString('courses.semesterStart',
        DateTime(date.year, date.month, date.day).toIso8601String());
  }

  static const _key = 'courses';

  static Future<CourseStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    final decoded = _decode(raw);
    if (decoded.rejected > 0 && !prefs.containsKey('courses.corruptBackup')) {
      await prefs.setString('courses.corruptBackup', raw!);
    }
    return CourseStore._(prefs, decoded.courses, decoded.rejected);
  }

  static ({List<Course> courses, int rejected}) _decode(String? raw) {
    if (raw == null || raw.isEmpty) return (courses: [], rejected: 0);
    final courses = <Course>[];
    var rejected = 0;
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      for (final entry in list) {
        try {
          final row = entry as Map<String, dynamic>;
          if (row['weekday'] is! int ||
              row['weekday'] < 1 ||
              row['weekday'] > 7) {
            throw const FormatException('星期无效');
          }
          courses.addAll(CourseImportData.normalize([Course.fromJson(row)]));
        } catch (_) {
          rejected++;
        }
      }
    } catch (_) {
      rejected++;
    }
    return (courses: courses, rejected: rejected);
  }

  List<Course> get courses => List.unmodifiable(_courses);

  /// 添加或更新一门课。
  Future<void> upsert(Course c) async {
    final idx = _courses.indexWhere((x) => x.id == c.id);
    if (idx >= 0) {
      _courses[idx] = c;
    } else {
      _courses.add(c);
    }
    await _persist();
  }

  /// 删除一门课。
  Future<void> remove(String id) async {
    _courses.removeWhere((x) => x.id == id);
    await _persist();
  }

  /// 批量导入（截图/教务识别结果）。
  Future<void> addAll(List<Course> list) async {
    final incoming = CourseImportData.normalize(list);
    await _prefs.setString('courses.beforeImport', _importBackup());
    final identities = _courses.map(CourseImportData.identity).toSet();
    for (final c in incoming) {
      if (!identities.add(CourseImportData.identity(c))) continue;
      final idx = _courses.indexWhere((x) => x.id == c.id);
      if (idx >= 0) {
        _courses[idx] = c;
      } else {
        _courses.add(c);
      }
    }
    await _persist();
  }

  /// Full school timetable refresh. The previous list remains available via undoImport.
  Future<void> replaceAll(List<Course> list, {CoursePeriods? periods}) async {
    final incoming = CourseImportData.normalize(list);
    final oldCourses = _prefs.getString(_key),
        oldPeriods = _prefs.getString('courses.periods');
    bool coursesSaved = false;
    try {
      if (!await _prefs.setString('courses.beforeImport', _importBackup())) {
        throw StateError('无法备份原课表，已保留当前课表');
      }
      if (!await _prefs.setString(
          _key, jsonEncode(incoming.map((c) => c.toJson()).toList()))) {
        throw StateError('无法保存新课表，已保留当前课表');
      }
      coursesSaved = true;
      if (periods != null &&
          !await _prefs.setString('courses.periods', periods.encode())) {
        throw StateError('作息未能保存，原课表已保留，请重试。');
      }
    } catch (_) {
      if (coursesSaved) {
        try {
          if (oldCourses == null) {
            await _prefs.remove(_key);
          } else {
            await _prefs.setString(_key, oldCourses);
          }
          if (oldPeriods == null) {
            await _prefs.remove('courses.periods');
          } else {
            await _prefs.setString('courses.periods', oldPeriods);
          }
        } catch (_) {
          /* The durable beforeImport snapshot remains recoverable. */
        }
      }
      // Legacy preferences caches values before confirming platform writes.
      await _prefs.reload();
      rethrow;
    }
    _courses
      ..clear()
      ..addAll(incoming);
  }

  Future<bool> undoImport() async {
    final raw = _prefs.getString('courses.beforeImport');
    if (raw == null) return false;
    final snapshot = jsonDecode(raw);
    final restored =
        _decode(snapshot is Map ? jsonEncode(snapshot['courses']) : raw);
    if (restored.rejected > 0) throw const FormatException('导入备份损坏，已保留当前课表');
    if (snapshot is Map &&
        snapshot['periods'] != null &&
        snapshot['periods'] is! String) {
      throw const FormatException('作息备份损坏，已保留当前课表');
    }
    final previous = _prefs.getString(_key);
    var coursesSaved = false;
    try {
      if (!await _prefs.setString(
          _key, jsonEncode(restored.courses.map((c) => c.toJson()).toList()))) {
        throw StateError('撤销未能保存，请重试。');
      }
      coursesSaved = true;
      if (snapshot is Map) {
        final saved = snapshot['periods'] == null
            ? await _prefs.remove('courses.periods')
            : await _prefs.setString(
                'courses.periods', snapshot['periods'] as String);
        if (!saved) {
          throw StateError('作息尚未恢复，导入备份已保留，请重试。');
        }
      }
    } catch (_) {
      if (coursesSaved) {
        try {
          if (previous == null) {
            await _prefs.remove(_key);
          } else {
            await _prefs.setString(_key, previous);
          }
        } catch (_) {
          // The import backup remains available if the device rejects all writes.
        }
      }
      await _prefs.reload();
      rethrow;
    }
    _courses
      ..clear()
      ..addAll(restored.courses);
    await _prefs.remove('courses.beforeImport');
    return true;
  }

  String _importBackup() => jsonEncode({
        'courses': _courses.map((c) => c.toJson()).toList(),
        'periods': _prefs.getString('courses.periods'),
      });

  Future<void> _persist() => _prefs.setString(
        _key,
        jsonEncode(_courses.map((c) => c.toJson()).toList()),
      );
}
