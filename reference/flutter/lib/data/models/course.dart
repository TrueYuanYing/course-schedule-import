/// 课程表相关模型。
library;

/// 星期几（1 = 周一 … 7 = 周日）。
enum Weekday {
  monday(1, '周一'),
  tuesday(2, '周二'),
  wednesday(3, '周三'),
  thursday(4, '周四'),
  friday(5, '周五'),
  saturday(6, '周六'),
  sunday(7, '周日');

  const Weekday(this.num, this.label);
  final int num;
  final String label;

  static Weekday fromNum(int i) =>
      Weekday.values.firstWhere((w) => w.num == i, orElse: () => monday);
  static Weekday fromDateTime(DateTime d) => Weekday.values[(d.weekday - 1)];
}

/// 一节课程。
class Course {
  Course({
    required this.id,
    required this.name,
    required this.weekday,
    required this.startPeriod,
    required this.endPeriod,
    this.startWeek = 1,
    this.endWeek = 20,
    this.weekParity,
    this.teacher,
    this.room,
    this.note,
    this.keywordPackId,
  });

  final String id;
  final String name;
  final Weekday weekday;

  /// 第几节开始，含。
  final int startPeriod;

  /// 第几节结束，含。
  final int endPeriod;

  /// 起始周 1~60。
  final int startWeek;

  /// 结束周 1~60。
  final int endWeek;

  /// null=每周，1=单周，0=双周。
  final int? weekParity;

  final String? teacher;
  final String? room;
  final String? note;

  /// 关联的关键词包 id（用于上课自动切包）。
  final String? keywordPackId;

  String get timeRangeLabel => '第 $startPeriod-$endPeriod 节';

  bool occursInWeek(int week) =>
      week >= startWeek &&
      week <= endWeek &&
      (weekParity == null || week % 2 == weekParity);

  String get weekRangeLabel {
    final parity = weekParity == null
        ? ''
        : weekParity == 1
            ? ' · 单周'
            : ' · 双周';
    return '第 $startWeek-$endWeek 周$parity';
  }

  Course copyWithWeekParity(int? parity) => Course(
        id: id,
        name: name,
        weekday: weekday,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        startWeek: startWeek,
        endWeek: endWeek,
        weekParity: parity,
        teacher: teacher,
        room: room,
        note: note,
        keywordPackId: keywordPackId,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'weekday': weekday.num,
        'startPeriod': startPeriod,
        'endPeriod': endPeriod,
        'startWeek': startWeek,
        'endWeek': endWeek,
        'weekParity': weekParity,
        'teacher': teacher,
        'room': room,
        'note': note,
        'keywordPackId': keywordPackId,
      };

  factory Course.fromJson(Map<String, dynamic> j) => Course(
        id: j['id'] as String,
        name: j['name'] as String,
        weekday: Weekday.fromNum(j['weekday'] as int),
        startPeriod: j['startPeriod'] as int,
        endPeriod: j['endPeriod'] as int,
        startWeek: j['startWeek'] as int? ?? 1,
        endWeek: j['endWeek'] as int? ?? 20,
        weekParity:
            (j['weekParity'] as int?) == 0 || (j['weekParity'] as int?) == 1
                ? j['weekParity'] as int
                : null,
        teacher: j['teacher'] as String?,
        room: j['room'] as String?,
        note: j['note'] as String?,
        keywordPackId: j['keywordPackId'] as String?,
      );
}
