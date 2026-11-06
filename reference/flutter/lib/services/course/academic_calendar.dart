import '../../data/models/course.dart';

/// 第一教学周按开学日所在周的周一开始，具体开学日由用户按校历设置。
class AcademicCalendar {
  AcademicCalendar({DateTime? startDate})
      : startDate = startDate ?? _defaultStartDate;

  final DateTime startDate;

  static DateTime get _defaultStartDate => suggestedStartDate(DateTime.now());

  /// 未设置校历时的学期起点估算；寒假前仍属于上一年秋季学期。
  static DateTime suggestedStartDate(DateTime now) {
    if (now.month >= 8) return DateTime(now.year, 9, 1);
    if (now.month >= 3) return DateTime(now.year, 3, 1);
    return DateTime(now.year - 1, 9, 1);
  }

  /// 当前日期对应的教学周，开学日前按第 1 周处理。
  int weekOf([DateTime? date]) {
    final day = date ?? DateTime.now();
    final firstDay =
        DateTime.utc(startDate.year, startDate.month, startDate.day);
    final start = firstDay.subtract(Duration(days: firstDay.weekday - 1));
    // 使用日历日期差，避免夏令时切换让一周不足 7 个完整的 24 小时。
    final current = DateTime.utc(day.year, day.month, day.day);
    final days = current.difference(start).inDays;
    if (days <= 0) return 1;
    return days ~/ 7 + 1;
  }

  List<Course> coursesOn(DateTime date, Iterable<Course> courses) {
    final firstMonday =
        DateTime.utc(startDate.year, startDate.month, startDate.day)
            .subtract(Duration(days: startDate.weekday - 1));
    if (DateTime.utc(date.year, date.month, date.day).isBefore(firstMonday)) {
      return [];
    }
    final week = weekOf(date);
    return courses
        .where((course) =>
            course.weekday.num == date.weekday && course.occursInWeek(week))
        .toList()
      ..sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  }
}
