import 'dart:convert';

class CoursePeriod {
  const CoursePeriod({required this.start, required this.end});
  final String start, end;
  Map<String, String> toJson() => {'start': start, 'end': end};
  static int? minutes(String value) {
    final match = RegExp(r'^([01]\d|2[0-3]):([0-5]\d)$').firstMatch(value);
    return match == null
        ? null
        : int.parse(match[1]!) * 60 + int.parse(match[2]!);
  }

  static CoursePeriod? parse(Object? value) {
    if (value is! Map || value['start'] is! String || value['end'] is! String) {
      return null;
    }
    final start = value['start'] as String, end = value['end'] as String;
    final a = minutes(start), b = minutes(end);
    return a != null && b != null && b > a
        ? CoursePeriod(start: start, end: end)
        : null;
  }
}

class CoursePeriods {
  const CoursePeriods({this.count = 12, this.times = const {}});
  final int count;
  final Map<int, CoursePeriod> times;
  int requiredCount(int importedMax) =>
      count > importedMax ? count : importedMax;
  CoursePeriods? withImportedTimes(Map<int, CoursePeriod> imported) {
    final merged = {...times, ...imported};
    final valid = parseTimes(
        {for (final e in merged.entries) '${e.key}': e.value.toJson()});
    if (valid.length != merged.length) return null;
    final chosen = valid;
    return CoursePeriods(
        count: chosen.keys.fold<int>(count, (a, b) => a > b ? a : b),
        times: chosen);
  }

  String encode() => jsonEncode({
        'count': count,
        'times': {for (final e in times.entries) '${e.key}': e.value.toJson()}
      });
  static CoursePeriods decode(String? raw) {
    try {
      final value = jsonDecode(raw ?? '');
      if (value is! Map) return const CoursePeriods();
      final count = value['count'];
      if (count is! int || count < 1 || count > 24) {
        return const CoursePeriods();
      }
      return CoursePeriods(count: count, times: parseTimes(value['times']));
    } on FormatException {
      return const CoursePeriods();
    }
  }

  static Map<int, CoursePeriod> parseTimes(Object? raw) {
    if (raw is! Map || raw.length > 24) return {};
    final result = <int, CoursePeriod>{};
    int lastEnd = -1;
    final keys = raw.keys
        .map((key) => int.tryParse(key.toString()))
        .whereType<int>()
        .toList()
      ..sort();
    if (keys.length != raw.length || keys.toSet().length != keys.length) {
      return {};
    }
    for (final key in keys) {
      final slot = CoursePeriod.parse(raw[key.toString()] ?? raw[key]);
      if (key < 1 ||
          key > 24 ||
          slot == null ||
          CoursePeriod.minutes(slot.start)! < lastEnd) {
        return {};
      }
      lastEnd = CoursePeriod.minutes(slot.end)!;
      result[key] = slot;
    }
    return result;
  }
}
