import 'dart:math' as math;
import 'dart:ui' show Rect;

import '../../data/models/course.dart';

/// MLKit 识别到的一段文字及其在原图中的位置。
class OcrTextBox {
  const OcrTextBox({required this.text, required this.box, this.confidence});

  final String text;
  final Rect box;
  final double? confidence;
}

/// 从截图像素中检测到的彩色课程块。
class CourseColorBlock {
  const CourseColorBlock(this.box);

  final Rect box;
}

class CourseImageParseResult {
  const CourseImageParseResult({
    required this.courses,
    required this.confidence,
    required this.needsConfirmation,
    this.courseIdsRequiringWeeks = const {},
    this.warnings = const [],
  });

  final List<Course> courses;
  final double confidence;
  final bool needsConfirmation;
  final Set<String> courseIdsRequiringWeeks;
  final List<String> warnings;

  bool get requiresWeekSelection => courseIdsRequiringWeeks.isNotEmpty;
}

/// 将“表头/节次 OCR + 彩色块 + 块内 OCR”归位到课程网格。
///
/// 这个类不依赖 Flutter 或 MLKit，既能在真机上复用，也能用固定坐标做
/// 快速回归测试。没有足够布局证据时会返回低置信结果，调用方必须让用户
/// 确认，绝不会把课程静默归到周一第 1 节。
class CourseImageLayoutParser {
  CourseImageParseResult parse({
    required List<OcrTextBox> textBoxes,
    required List<CourseColorBlock> colorBlocks,
  }) {
    final headerBoxes = _weekdayHeader(textBoxes);
    final weekdays = _findWeekdays(headerBoxes);
    final headerBottom = headerBoxes.fold<double>(
        0, (bottom, item) => math.max(bottom, item.box.bottom));
    final periods = _findPeriods(textBoxes, weekdays, headerBottom);
    final columnGap = _columnGap(weekdays);
    final rowGap = _medianPeriodGap(periods);
    final axisBottom = periods.isEmpty ? 0.0 : periods.last.position;
    final dayPositions = weekdays.map((point) => point.position).toList()
      ..sort();
    final usableBlocks = colorBlocks
        .map((b) => b.box)
        .where((box) =>
            dayPositions.isNotEmpty &&
            box.width >= math.max(12, columnGap * .5) &&
            box.height >= 12 &&
            box.width <= columnGap * 1.4 &&
            box.top >= headerBottom &&
            periods.isNotEmpty &&
            box.top <= axisBottom + rowGap * .5 &&
            box.center.dx >= dayPositions.first - columnGap * .5 &&
            box.center.dx <= dayPositions.last + columnGap * .5)
        .toList();

    final hasGrid = weekdays.length >= 2 && periods.length >= 2;
    final courses = <Course>[];
    final courseIdsRequiringWeeks = <String>{};
    final warnings = <String>[];
    var assigned = 0;

    void addCourse(_CourseDetail detail, int day, int start, int end) {
      final course = _course(detail, day, start, end);
      courses.add(course);
      if (!detail.hasWeeks) courseIdsRequiringWeeks.add(course.id);
      assigned++;
    }

    if (hasGrid) {
      for (final block in usableBlocks) {
        if (_isClippedAtLastRow(block, periods)) {
          warnings.add('截图底部课程可能被裁断或末节未完整显示，已跳过该色块，请补充完整截图。');
          continue;
        }
        final day = _nearestWeekday(block.center.dx, weekdays);
        final start = _nearestPeriod(block.top, periods);
        if (day == null || start == null) continue;

        final end = _endPeriod(block.bottom, start, periods);
        final text = _textForBlock(block, textBoxes);
        for (final detail in _courseDetails(text)) {
          addCourse(detail, day, start, end);
        }
      }

      // 某些截图的色块太浅而没有被检测到：仍用 OCR 做保守兜底，但标低置信，
      // 由 UI 展示确认框，而不是自动写入。
      if (usableBlocks.isEmpty) {
        for (final group in _groupGridText(textBoxes, weekdays, periods)) {
          final day = _nearestWeekday(group.box.center.dx, weekdays);
          final start = _nearestPeriod(group.box.top, periods);
          if (day == null || start == null) continue;
          final end = _endPeriod(group.box.bottom, start, periods);
          for (final detail in _courseDetails(group.text)) {
            addCourse(detail, day, start, end);
          }
        }
      }
    }

    final unique = _dedupe(courses);
    final layoutScore = ((weekdays.length / 6).clamp(0.0, 1.0) * 0.3) +
        ((periods.length / 10).clamp(0.0, 1.0) * 0.25);
    final blockScore =
        usableBlocks.isEmpty ? (courses.isEmpty ? 0.0 : 0.14) : 0.3;
    final assignmentScore = usableBlocks.isEmpty
        ? 0.0
        : (assigned / usableBlocks.length).clamp(0.0, 1.0) * 0.15;
    var confidence =
        (layoutScore + blockScore + assignmentScore).clamp(0.0, 1.0).toDouble();
    if (courseIdsRequiringWeeks.isNotEmpty) {
      warnings.insert(0, '截图没有明确周次，请在预览中选择适用周次；不会默认导入整学期。');
    }
    if (hasGrid) {
      final missingDays = Weekday.values
          .where((day) => !weekdays.any((point) => point.value == day.num))
          .map((day) => day.label)
          .join('、');
      if (missingDays.isNotEmpty) {
        warnings.add('截图未显示$missingDays，仅识别可见列，不据此判断未显示日期没有课程。');
      }
      final dateLabel = RegExp(
          r'^(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}|(?:\d{4}年)?\d{1,2}月(?:\d{1,2}日)?|\d{1,2}(?:[/.-]\d{1,2}|日)?)$');
      final dateLabels = textBoxes
          .where((item) =>
              item.box.center.dy >= headerBoxes.first.box.top - rowGap * .5 &&
              item.box.center.dy < headerBottom + rowGap * .75 &&
              dateLabel.hasMatch(item.text.replaceAll(RegExp(r'\s+'), '')))
          .map((item) => item.text.trim())
          .toSet();
      if (dateLabels.isNotEmpty) {
        warnings.add('截图日期标签：${dateLabels.join(' / ')}；未据此推断教学周次。');
      }
      final textConfidences = textBoxes
          .where((item) =>
              usableBlocks.any((block) => block.contains(item.box.center)) ||
              (usableBlocks.isEmpty &&
                  item.box.center.dy >= periods.first.position - rowGap * .5 &&
                  item.box.center.dy <= periods.last.position + rowGap))
          .map((item) => item.confidence)
          .whereType<double>()
          .where((value) => value.isFinite && value >= 0 && value <= 1)
          .toList();
      if (textConfidences.isNotEmpty) {
        final textConfidence = textConfidences.reduce(math.min);
        confidence = math.min(confidence, textConfidence);
        if (textConfidence < .7) {
          warnings.insert(0, '部分文字识别置信度较低，错字或缺字无法仅靠布局恢复，请核对课程名、教师和地点。');
        }
      }
    }

    return CourseImageParseResult(
      courses: unique,
      confidence: confidence,
      needsConfirmation: !hasGrid ||
          usableBlocks.isEmpty ||
          confidence < 0.78 ||
          warnings.isNotEmpty,
      courseIdsRequiringWeeks: courseIdsRequiringWeeks,
      warnings: warnings,
    );
  }

  List<OcrTextBox> _weekdayHeader(List<OcrTextBox> boxes) {
    final candidates = boxes
        .where((item) => _weekday(item.text) != null)
        .toList()
      ..sort((a, b) => a.box.top.compareTo(b.box.top));
    if (candidates.isEmpty) return const [];
    final first = candidates.first.box;
    final aligned = boxes
        .where((item) =>
            item.box.top < first.bottom && item.box.bottom > first.top)
        .toList();
    final anchors =
        aligned.map((item) => _weekday(item.text)).whereType<int>().toSet();
    return aligned
        .where((item) =>
            _weekday(item.text) != null ||
            (anchors.length >= 2 && _headerWeekday(item.text) != null))
        .toList();
  }

  int? _headerWeekday(String text) {
    final direct = _weekday(text);
    if (direct != null) return direct;
    // 仅在已有至少两个真实星期锚点的同一表头行，容忍艺术字体“周”被认成“同”。
    final match = RegExp(r'^同([一二三四五六日天])$')
        .firstMatch(text.replaceAll(RegExp(r'\s+'), ''));
    return match == null ? null : _weekdayChar(match.group(1)!);
  }

  double _columnGap(List<_AxisPoint> weekdays) {
    final positions = weekdays.map((point) => point.position).toList()..sort();
    if (positions.length < 2) return 120;
    final gaps = <double>[
      for (var i = 1; i < positions.length; i++)
        positions[i] - positions[i - 1],
    ]..sort();
    return gaps[gaps.length ~/ 2];
  }

  List<_AxisPoint> _findWeekdays(List<OcrTextBox> boxes) {
    final found = <int, _AxisPoint>{};
    for (final item in boxes) {
      final matches = RegExp(r'(?:星期|周)\s*([一二三四五六日天])')
          .allMatches(item.text.replaceAll(' ', ''))
          .toList();
      if (matches.length > 1) {
        for (final match in matches) {
          final value = _weekdayChar(match.group(1)!);
          final ratio = ((match.start + match.end) / 2) /
              math.max(1, item.text.replaceAll(' ', '').length);
          found[value] = _AxisPoint(
            value,
            item.box.left + item.box.width * ratio,
          );
        }
      } else {
        final value = _headerWeekday(item.text);
        if (value != null) {
          found[value] = _AxisPoint(value, item.box.center.dx);
        }
      }
    }
    return found.values.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  List<_AxisPoint> _findPeriods(
      List<OcrTextBox> boxes, List<_AxisPoint> weekdays, double headerBottom) {
    final found = <int, _AxisPoint>{};
    if (weekdays.isEmpty) return const [];
    final leftEdge = weekdays.map((point) => point.position).reduce(math.min) -
        _columnGap(weekdays) * .35;
    for (final item in boxes) {
      if (item.box.center.dx >= leftEdge ||
          item.box.center.dy <= headerBottom) {
        continue;
      }
      final compact = item.text.replaceAll(RegExp(r'\s+'), '');
      final arabic = RegExp(r'(?:^|\n)0?(\d{1,2})(?:节)?(?:$|\n)')
          .allMatches(compact)
          .toList();
      final chinese =
          RegExp(r'第([一二三四五六七八九十百零〇两]{1,4})节').allMatches(compact).toList();
      final matches = <int>[];
      for (final match in arabic) {
        final value = int.tryParse(match.group(1)!);
        if (value != null) matches.add(value);
      }
      for (final match in chinese) {
        final value = _chineseNumber(match.group(1)!);
        if (value != null) matches.add(value);
      }
      if (matches.length == 1 && matches.single >= 1 && matches.single <= 16) {
        found[matches.single] = _AxisPoint(matches.single, item.box.center.dy);
      } else if (matches.length > 1) {
        for (var i = 0; i < matches.length; i++) {
          final value = matches[i];
          if (value >= 1 && value <= 16) {
            found[value] = _AxisPoint(
              value,
              item.box.top + item.box.height * ((i + .5) / matches.length),
            );
          }
        }
      }
    }
    return found.values.toList()..sort((a, b) => a.value.compareTo(b.value));
  }

  int? _weekday(String text) {
    final t = text.replaceAll(' ', '').trim();
    if (!t.contains('周') && !t.contains('星期')) return null;
    final match = RegExp(r'(?:星期|周)([一二三四五六日天])').firstMatch(t);
    if (match != null) return _weekdayChar(match.group(1)!);
    return null;
  }

  int _weekdayChar(String value) {
    const chars = ['一', '二', '三', '四', '五', '六'];
    final index = chars.indexOf(value);
    return index >= 0 ? index + 1 : 7;
  }

  int? _chineseNumber(String value) {
    const digits = <String, int>{
      '零': 0,
      '〇': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };
    if (value == '十') return 10;
    if (value.startsWith('十')) {
      return 10 + (digits[value.substring(1)] ?? 0);
    }
    if (value.contains('十')) {
      final parts = value.split('十');
      return (digits[parts.first] ?? 0) * 10 + (digits[parts.last] ?? 0);
    }
    return digits[value];
  }

  int? _nearestWeekday(double x, List<_AxisPoint> weekdays) {
    if (weekdays.isEmpty) return null;
    final point = weekdays.reduce(
      (a, b) => (x - a.position).abs() < (x - b.position).abs() ? a : b,
    );
    return point.value;
  }

  int? _nearestPeriod(double y, List<_AxisPoint> periods) {
    if (periods.isEmpty) return null;
    final point = periods.reduce(
      (a, b) => (y - a.position).abs() < (y - b.position).abs() ? a : b,
    );
    return point.value;
  }

  int _endPeriod(double bottom, int start, List<_AxisPoint> periods) {
    var end = start;
    for (final period in periods) {
      if (period.value > start && bottom > period.position) end = period.value;
    }
    return end;
  }

  bool _isClippedAtLastRow(Rect block, List<_AxisPoint> periods) {
    if (periods.length < 2) return true;
    final lastCenter = periods.last.position;
    final gap = _medianPeriodGap(periods);
    // 最后一行不足以覆盖其中心以下的有效区域，或超出已知节次轴，
    // 都不能用最近节次猜一个完整末节。
    return (block.bottom >= lastCenter &&
            block.bottom < lastCenter + gap * .3) ||
        block.bottom > lastCenter + gap;
  }

  List<_GridTextGroup> _groupGridText(
    List<OcrTextBox> boxes,
    List<_AxisPoint> weekdays,
    List<_AxisPoint> periods,
  ) {
    final byDay = <int, List<OcrTextBox>>{};
    final rowGap = _medianPeriodGap(periods);
    final positions = weekdays.map((point) => point.position).toList()..sort();
    for (final box in boxes) {
      if (box.box.center.dy < periods.first.position - rowGap * .5 ||
          box.box.center.dy > periods.last.position + rowGap ||
          box.box.center.dx < positions.first - _columnGap(weekdays) * .5 ||
          box.box.center.dx > positions.last + _columnGap(weekdays) * .5) {
        continue;
      }
      if (_isLayoutLabel(box.text, weekdays, periods)) continue;
      final compact = box.text.replaceAll(RegExp(r'\s+'), '');
      if (_isTimeLabel(compact) || compact == '节次/星期' || compact == '节次') {
        continue;
      }
      final day = _nearestWeekday(box.box.center.dx, weekdays);
      if (day != null) (byDay[day] ??= []).add(box);
    }

    final groups = <_GridTextGroup>[];
    for (final items in byDay.values) {
      items.sort((a, b) => a.box.top.compareTo(b.box.top));
      var current = <OcrTextBox>[];
      for (final item in items) {
        if (current.isNotEmpty) {
          final previous = current.last.box;
          final gap = item.box.top - previous.bottom;
          final startsAnotherWeek = _hasWeekMarker(item.text) &&
              current.any((box) => _hasWeekMarker(box.text));
          final tooFar = gap > math.max(18, rowGap * .42);
          if (startsAnotherWeek || tooFar) {
            groups.add(_makeGroup(current));
            current = <OcrTextBox>[];
          }
        }
        current.add(item);
      }
      if (current.isNotEmpty) groups.add(_makeGroup(current));
    }
    return groups;
  }

  double _medianPeriodGap(List<_AxisPoint> periods) {
    if (periods.length < 2) return 42;
    final gaps = <double>[];
    for (var i = 1; i < periods.length; i++) {
      gaps.add(periods[i].position - periods[i - 1].position);
    }
    gaps.sort();
    return gaps[gaps.length ~/ 2].abs();
  }

  _GridTextGroup _makeGroup(List<OcrTextBox> boxes) {
    final left = boxes.map((box) => box.box.left).reduce(math.min);
    final top = boxes.map((box) => box.box.top).reduce(math.min);
    final right = boxes.map((box) => box.box.right).reduce(math.max);
    final bottom = boxes.map((box) => box.box.bottom).reduce(math.max);
    final text = boxes
        .map((box) => box.text.trim())
        .where((value) => value.isNotEmpty)
        .join('\n');
    return _GridTextGroup(
        text: text, box: Rect.fromLTRB(left, top, right, bottom));
  }

  String _textForBlock(Rect block, List<OcrTextBox> boxes) {
    final matching =
        boxes.where((item) => block.contains(item.box.center)).toList()
          ..sort((a, b) {
            final y = a.box.top.compareTo(b.box.top);
            return y == 0 ? a.box.left.compareTo(b.box.left) : y;
          });
    return matching
        .map((item) => item.text.trim())
        .where((t) => t.isNotEmpty)
        .join('\n');
  }

  bool _isLayoutLabel(
    String text,
    List<_AxisPoint> weekdays,
    List<_AxisPoint> periods,
  ) =>
      _weekday(text) != null ||
      RegExp(r'^\s*0?\d{1,2}\s*(?:节)?\s*$').hasMatch(text) ||
      RegExp(r'^\s*第[一二三四五六七八九十百零〇两]{1,4}节\s*$')
          .hasMatch(text.replaceAll(' ', ''));

  bool _isTimeLabel(String text) =>
      RegExp(r'^\d{1,2}:\d{2}(?:[-~至]\d{1,2}:\d{2})?$').hasMatch(text);

  bool _hasWeekMarker(String text) => RegExp(
        r'(?:\d{1,2}\s*[-~至—～]\s*\d{1,2}\s*周|\d{1,2}\s*周)',
      ).hasMatch(text.replaceAll(' ', ''));

  List<_CourseDetail> _courseDetails(String raw) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const [];
    final groups = <List<String>>[];
    var current = <String>[];
    for (final line in lines) {
      if (current.isNotEmpty &&
          _hasWeekMarker(line) &&
          current.any(_hasWeekMarker)) {
        groups.add(current);
        current = <String>[];
      }
      current.add(line);
    }
    if (current.isNotEmpty) groups.add(current);
    return groups
        .map((group) => _courseDetail(group.join('\n')))
        .whereType<_CourseDetail>()
        .toList();
  }

  _CourseDetail? _courseDetail(String raw) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split(RegExp(r'\n+'))
        .map((line) => line.replaceAll(RegExp(r'\s+'), ' ').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    var startWeek = 1;
    var endWeek = 1;
    var hasWeeks = false;
    for (final line in lines) {
      final compact = line.replaceAll(' ', '');
      final range = RegExp(r'(\d{1,2})[-~至—～](\d{1,2})周').firstMatch(compact);
      if (range != null) {
        startWeek = int.parse(range.group(1)!);
        endWeek = int.parse(range.group(2)!);
        hasWeeks = true;
      } else {
        final single = RegExp(r'(\d{1,2})周').firstMatch(compact);
        if (single != null) {
          startWeek = int.parse(single.group(1)!);
          endWeek = startWeek;
          hasWeeks = true;
        }
      }
    }
    final weekLabel = RegExp(
        r'(?:第)?\s*\d{1,2}(?:\s*[-~至—～]\s*\d{1,2})?\s*周(?:\s*[（(]?[单双]周?[）)]?)?');
    final contentLines = lines
        .map((line) => line.replaceAll(weekLabel, '').trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (contentLines.isEmpty) return null;

    final weekParity = lines.any((line) => line.contains('单周'))
        ? 1
        : lines.any((line) => line.contains('双周'))
            ? 0
            : null;
    final joined = contentLines
        .map((line) => line.replaceFirst(RegExp(r'^[|｜]+\s*'), ''))
        .join('');
    final at = joined.indexOf(RegExp(r'[@＠]'));
    if (at > 0) {
      final separator = joined.substring(0, at).indexOf(RegExp(r'[-－—]'));
      if (separator > 0) {
        final name = joined.substring(0, separator).trim();
        final teacher = joined.substring(separator + 1, at).trim();
        final room = joined
            .substring(at + 1)
            .replaceFirst(RegExp(r'[-－—]+$'), '')
            .trim();
        if (name.isNotEmpty) {
          return _CourseDetail(
            name: name,
            teacher: teacher.isEmpty ? null : teacher,
            room: room.isEmpty ? null : room,
            startWeek: startWeek,
            endWeek: endWeek,
            hasWeeks: hasWeeks,
            weekParity: weekParity,
          );
        }
      }
    }

    var name = contentLines.first
        .replaceFirst(RegExp(r'^课程(?:名称)?\s*[:：]\s*'), '')
        .trim();
    if (name.isEmpty || _looksLikeMetadata(name)) return null;

    String? teacher;
    String? room;
    for (final line in contentLines.skip(1)) {
      final value = line.replaceFirst(RegExp(r'^.*?[:：]\s*'), '').trim();
      if (line.contains('老师') || line.contains('教师') || line.contains('讲师')) {
        teacher = value;
      } else if (_looksLikeRoom(line)) {
        room = value;
      } else {
        final hadTeacher = teacher != null;
        teacher ??= line;
        if (hadTeacher) {
          room ??= line;
        }
      }
    }
    name = name.replaceFirst(RegExp(r'\s*[（(].*?[）)]\s*$'), '').trim();
    return _CourseDetail(
      name: name,
      teacher: teacher,
      room: room,
      startWeek: startWeek,
      endWeek: endWeek,
      hasWeeks: hasWeeks,
      weekParity: weekParity,
    );
  }

  bool _looksLikeMetadata(String line) =>
      line.contains('老师') || line.contains('教师') || line.contains('教室');

  bool _looksLikeRoom(String line) =>
      line.contains('教室') ||
      line.contains('楼') ||
      line.contains('栋') ||
      line.contains('室') ||
      RegExp(r'\d').hasMatch(line);

  Course _course(_CourseDetail detail, int day, int start, int end) => Course(
        id: 'c_import_${day}_${start}_${end}_${detail.startWeek}_'
            '${detail.endWeek}_${detail.weekParity}_${_stableHash(detail.name)}',
        name: detail.name,
        weekday: Weekday.fromNum(day),
        startPeriod: start,
        endPeriod: end,
        startWeek: detail.startWeek,
        endWeek: detail.endWeek,
        weekParity: detail.weekParity,
        teacher: detail.teacher,
        room: detail.room,
      );

  List<Course> _dedupe(List<Course> courses) {
    final seen = <String>{};
    return courses.where((course) {
      final key =
          '${course.weekday.num}-${course.startPeriod}-${course.endPeriod}-${course.startWeek}-${course.endWeek}-${course.name}';
      return seen.add(key);
    }).toList();
  }

  int _stableHash(String value) =>
      value.codeUnits.fold(17, (hash, code) => hash * 31 + code);
}

class _AxisPoint {
  const _AxisPoint(this.value, this.position);

  final int value;
  final double position;
}

class _CourseDetail {
  const _CourseDetail({
    required this.name,
    this.teacher,
    this.room,
    this.startWeek = 1,
    this.endWeek = 1,
    this.hasWeeks = false,
    this.weekParity,
  });

  final String name;
  final String? teacher;
  final String? room;
  final int startWeek;
  final int endWeek;
  final bool hasWeeks;
  final int? weekParity;
}

class _GridTextGroup {
  const _GridTextGroup({required this.text, required this.box});

  final String text;
  final Rect box;
}
