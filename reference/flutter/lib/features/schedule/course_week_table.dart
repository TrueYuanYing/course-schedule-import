import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../data/models/course.dart';
import '../../core/theme/app_colors.dart';
import '../../services/course/course_periods.dart';

class CourseWeekTable extends StatefulWidget {
  const CourseWeekTable(
      {super.key,
      required this.courses,
      required this.periods,
      required this.week,
      this.weekStart,
      this.today});
  final List<Course> courses;
  final CoursePeriods periods;
  final int week;
  final DateTime? weekStart;
  final DateTime? today;
  static const rowHeight = 74.0;
  @override
  State<CourseWeekTable> createState() => _CourseWeekTableState();
}

class _CourseWeekTableState extends State<CourseWeekTable> {
  final _horizontal = ScrollController();

  @override
  void dispose() {
    _horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = theme.colorScheme;
    final titleStyle = theme.textTheme.labelMedium!
        .copyWith(fontSize: 13, height: 1.35, fontWeight: FontWeight.w700);
    final detailStyle =
        theme.textTheme.bodySmall!.copyWith(fontSize: 12, height: 1.35);
    final timeStyle = theme.textTheme.labelSmall!;
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    Size measure(String text, TextStyle style,
        {double width = double.infinity}) {
      final painter = TextPainter(
          text: TextSpan(
              text: text,
              style: MediaQuery.boldTextOf(context)
                  ? style.copyWith(fontWeight: FontWeight.bold)
                  : style),
          textScaler: scaler,
          textDirection: direction)
        ..layout(maxWidth: width);
      final size = painter.size;
      painter.dispose();
      return size;
    }

    final rows = widget.periods
        .requiredCount(
            widget.courses.fold<int>(1, (max, c) => math.max(max, c.endPeriod)))
        .clamp(1, 24);
    final visible =
        widget.courses.where((c) => c.occursInWeek(widget.week)).toList();
    final days = [
      for (final day in Weekday.values)
        _place(visible.where((c) => c.weekday == day).toList())
    ];
    var fullAxisWidth = 62.0;
    for (final slot in widget.periods.times.values) {
      fullAxisWidth = math.max(
          fullAxisWidth,
          math.max(measure(slot.start, timeStyle).width,
                  measure(slot.end, timeStyle).width) +
              10);
    }
    return RepaintBoundary(child: LayoutBuilder(builder: (context, box) {
      final fitToViewport = box.hasBoundedHeight;
      final headerHeight = fitToViewport
          ? math.min(
              box.maxHeight,
              widget.weekStart == null
                  ? (box.maxHeight < 240 ? 24.0 : 32.0)
                  : (box.maxHeight < 240 ? 32.0 : 44.0))
          : 40.0;
      final compact = fitToViewport ||
          box.maxWidth < 1020 ||
          MediaQuery.orientationOf(context) == Orientation.portrait;
      final axisWidth = compact ? 38.0 : fullAxisWidth;
      final baseWidth = math.max(136.0, (box.maxWidth - axisWidth) / 7);
      final dayWidths = [
        for (final day in days)
          compact
              ? (box.maxWidth - axisWidth) / 7
              : math.max(baseWidth,
                  136.0 * day.fold<int>(1, (n, p) => math.max(n, p.lanes)))
      ];
      final cardTitleStyle = compact
          ? titleStyle.copyWith(
              fontSize: ((dayWidths.first - 6) / 5).clamp(11.0, 13.0),
              height: 1.15)
          : titleStyle;
      final cardDetailStyle = compact
          ? detailStyle.copyWith(
              fontSize: math.min(cardTitleStyle.fontSize!, 10.5), height: 1.1)
          : detailStyle;
      final axisStyle =
          compact ? timeStyle.copyWith(fontSize: 9.5, height: 1.1) : timeStyle;
      final periodStyle = compact
          ? theme.textTheme.labelLarge!.copyWith(fontSize: 11, height: 1.1)
          : theme.textTheme.labelLarge!;
      final rowHeights = List<double>.filled(
          rows,
          fitToViewport
              ? math.max(0, (box.maxHeight - headerHeight) / rows)
              : CourseWeekTable.rowHeight);
      for (var i = 0; !fitToViewport && i < rows; i++) {
        final slot = widget.periods.times[i + 1];
        rowHeights[i] = math.max(
            rowHeights[i],
            measure('${i + 1}', periodStyle).height +
                (compact ? 8 : 12) +
                (slot == null
                    ? 0
                    : measure(slot.start, axisStyle).height +
                        measure(slot.end, axisStyle).height));
      }
      // Compact cards truncate inside their slot; long text never stretches the week.
      for (var day = 0; !compact && day < days.length; day++) {
        for (final placed in days[day]) {
          final course = placed.course;
          final textWidth = dayWidths[day] / placed.lanes - 20;
          final needed = measure(course.name, titleStyle, width: textWidth)
                  .height +
              26 +
              _details(course).fold<double>(
                  0,
                  (h, text) =>
                      h +
                      measure(text, detailStyle, width: textWidth).height +
                      2);
          final first = (course.startPeriod - 1).clamp(0, rows - 1);
          final last = course.endPeriod.clamp(first + 1, rows);
          final available =
              rowHeights.sublist(first, last).fold<double>(0, (a, b) => a + b);
          if (needed > available) {
            final extra = (needed - available) / (last - first);
            for (var row = first; row < last; row++) {
              rowHeights[row] += extra;
            }
          }
        }
      }
      final ys = _offsets(rowHeights), xs = _offsets(dayWidths);
      final grid = SizedBox(
          key: const ValueKey('course-week-grid'),
          width: xs.last,
          child: Column(children: [
            Row(children: [
              for (var day = 0; day < 7; day++)
                _dayHeading(context, day, dayWidths[day], headerHeight,
                    compact ? periodStyle : theme.textTheme.labelLarge!),
            ]),
            SizedBox(
                height: ys.last,
                child: Stack(children: [
                  Positioned.fill(
                      child: CustomPaint(
                          painter: _TableLines(ys, xs, colors.outlineVariant))),
                  for (var day = 0; day < 7; day++)
                    for (final placed in days[day])
                      _card(context, placed, xs[day], dayWidths[day], ys,
                          cardTitleStyle, cardDetailStyle, compact),
                ])),
          ]));
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
            width: axisWidth,
            child: Column(children: [
              SizedBox(
                  height: headerHeight,
                  child: Center(
                      child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('节次', style: periodStyle)))),
              for (var i = 1; i <= rows; i++)
                SizedBox(
                    height: rowHeights[i - 1],
                    child: Semantics(
                        label:
                            '$i节 ${widget.periods.times[i]?.start ?? ''} ${widget.periods.times[i]?.end ?? ''}',
                        excludeSemantics: true,
                        child: LayoutBuilder(builder: (context, cell) {
                          final periodHeight =
                              scaler.scale(periodStyle.fontSize!) * 1.2;
                          final timeHeight =
                              scaler.scale(axisStyle.fontSize!) * 1.2;
                          final slot = widget.periods.times[i];
                          return FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text('$i', style: periodStyle),
                                    if (slot != null &&
                                        cell.maxHeight >=
                                            periodHeight + timeHeight + 2)
                                      Text(slot.start, style: axisStyle),
                                    if (slot != null &&
                                        cell.maxHeight >=
                                            periodHeight + timeHeight * 2 + 2)
                                      Text(slot.end, style: axisStyle),
                                  ]));
                        }))),
            ])),
        if (compact)
          Expanded(child: grid)
        else
          Expanded(
              child: Scrollbar(
                  controller: _horizontal,
                  thumbVisibility: true,
                  scrollbarOrientation: ScrollbarOrientation.top,
                  child: SingleChildScrollView(
                      controller: _horizontal,
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.only(bottom: 12),
                      child: grid))),
      ]);
    }));
  }

  Widget _dayHeading(BuildContext context, int day, double width, double height,
      TextStyle style) {
    final colors = Theme.of(context).colorScheme;
    final start = widget.weekStart;
    final date = start == null
        ? null
        : DateTime(start.year, start.month, start.day + day);
    final now = widget.today ?? DateTime.now();
    final today = date != null &&
        date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
    final text = date == null ? '' : '${date.month}/${date.day}';
    return SizedBox(
        key: ValueKey('course-day-${day + 1}'),
        width: width,
        height: height,
        child: Semantics(
            label:
                '${Weekday.values[day].label}${date == null ? '' : '，${date.year}年${date.month}月${date.day}日'}${today ? '，今天' : ''}',
            excludeSemantics: true,
            child: Padding(
                padding: const EdgeInsets.all(2),
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: today ? colors.secondaryContainer : null,
                        borderRadius: BorderRadius.circular(8)),
                    child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 2, vertical: 2),
                        child: Center(
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(Weekday.values[day].label,
                                          style: style.copyWith(
                                              color: today
                                                  ? colors.onSecondaryContainer
                                                  : colors.onSurface,
                                              fontWeight: today
                                                  ? FontWeight.w800
                                                  : FontWeight.w600)),
                                      if (date != null)
                                        Text(today ? '今天' : text,
                                            style: style.copyWith(
                                                fontSize: 9.5,
                                                height: 1.1,
                                                color: today
                                                    ? colors
                                                        .onSecondaryContainer
                                                    : colors.onSurfaceVariant)),
                                    ]))))))));
  }

  Widget _card(
      BuildContext context,
      _PlacedCourse placed,
      double left,
      double width,
      List<double> ys,
      TextStyle titleStyle,
      TextStyle detailStyle,
      bool compact) {
    final course = placed.course, laneWidth = width / placed.lanes;
    final first = (course.startPeriod - 1).clamp(0, ys.length - 2);
    final last = course.endPeriod.clamp(first + 1, ys.length - 1);
    final theme = Theme.of(context);
    final palette = (theme.extension<CourseTableColors>() ??
            CourseTableColors.forPalette(theme.brightness, 'ocean'))
        .swatches;
    final color = palette[
        course.name.runes.fold<int>(0, (a, b) => a + b) % palette.length];
    final foreground = theme.colorScheme.onSurface;
    titleStyle = titleStyle.copyWith(color: foreground);
    detailStyle = detailStyle.copyWith(color: foreground);
    final gap = compact ? 1.5 : 3.0;
    final spanHeight = ys[last] - ys[first];
    final verticalGap = math.min(gap, spanHeight * .1);
    void showDetails() => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                scrollable: true,
                title: Text(course.name),
                content: Text(
                    '${course.weekday.label} · ${course.timeRangeLabel}\n${course.weekRangeLabel}\n${course.teacher ?? ''}\n${course.room ?? ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('关闭'))
                ]));
    return Positioned(
        left: left + placed.lane * laneWidth + gap,
        top: ys[first] + verticalGap,
        width: math.max(0, laneWidth - gap * 2),
        height: math.max(0, spanHeight - verticalGap * 2),
        child: Semantics(
            button: true,
            label:
                '${course.name}，${course.weekday.label}，${course.timeRangeLabel}，${course.weekRangeLabel}，${course.teacher ?? ''}，${course.room ?? ''}',
            excludeSemantics: true,
            onTap: showDetails,
            child: Material(
                key: ValueKey('course-card-${course.id}'),
                color: color,
                borderRadius: BorderRadius.circular(compact ? 7 : 12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                    onTap: showDetails,
                    child: Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 3 : 7,
                            vertical: compact ? (spanHeight < 48 ? 1 : 3) : 7),
                        child: compact
                            ? LayoutBuilder(builder: (context, box) {
                                final room = course.room?.trim() ?? '';
                                final teacher = course.teacher?.trim() ?? '';
                                final scaler = MediaQuery.textScalerOf(context);
                                final titleLineHeight =
                                    scaler.scale(titleStyle.fontSize!) *
                                        (titleStyle.height ?? 1.15);
                                final detailLineHeight =
                                    scaler.scale(detailStyle.fontSize!) *
                                        (detailStyle.height ?? 1.1);
                                final showTeacher = teacher.isNotEmpty &&
                                    box.maxHeight >=
                                        titleLineHeight + detailLineHeight;
                                final remainingHeight = box.maxHeight -
                                    (showTeacher ? detailLineHeight : 0);
                                final roomLines = remainingHeight >=
                                        titleLineHeight * 2 +
                                            detailLineHeight * 2 +
                                            3
                                    ? 2
                                    : 1;
                                final showRoom = room.isNotEmpty &&
                                    remainingHeight >=
                                        titleLineHeight + detailLineHeight;
                                final roomHeight = showRoom
                                    ? detailLineHeight * roomLines
                                    : 0.0;
                                final lines = ((remainingHeight - roomHeight) /
                                        titleLineHeight)
                                    .floor()
                                    .clamp(1, 32);
                                return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                          child: Align(
                                              alignment: Alignment.topLeft,
                                              child: Text(course.name,
                                                  style: titleStyle,
                                                  maxLines: lines,
                                                  overflow:
                                                      TextOverflow.ellipsis))),
                                      if (showTeacher)
                                        Text(teacher,
                                            style: detailStyle.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurfaceVariant),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                      if (showRoom)
                                        Text(room,
                                            style: detailStyle,
                                            maxLines: roomLines,
                                            overflow: TextOverflow.ellipsis),
                                    ]);
                              })
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                    Text(course.name, style: titleStyle),
                                    const SizedBox(height: 4),
                                    for (final line in _details(course))
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 2),
                                          child:
                                              Text(line, style: detailStyle)),
                                  ]))))));
  }
}

List<String> _details(Course course) => [
      if (course.room?.trim().isNotEmpty == true) course.room!.trim(),
      if (course.teacher?.trim().isNotEmpty == true) course.teacher!.trim(),
      course.weekRangeLabel,
    ];

List<double> _offsets(List<double> sizes) {
  final result = <double>[0];
  for (final size in sizes) {
    result.add(result.last + size);
  }
  return result;
}

class _PlacedCourse {
  const _PlacedCourse(this.course, this.lane, this.lanes);
  final Course course;
  final int lane, lanes;
}

List<_PlacedCourse> _place(List<Course> courses) {
  courses.sort((a, b) => a.startPeriod.compareTo(b.startPeriod));
  final groups = <List<Course>>[];
  var end = 0;
  for (final course in courses) {
    if (groups.isEmpty || course.startPeriod > end) {
      groups.add([]);
      end = 0;
    }
    groups.last.add(course);
    end = math.max(end, course.endPeriod);
  }
  return [for (final group in groups) ..._placeGroup(group)];
}

List<_PlacedCourse> _placeGroup(List<Course> group) {
  final ends = <int>[], lanes = <int>[];
  for (final course in group) {
    var lane = ends.indexWhere((end) => end < course.startPeriod);
    if (lane < 0) {
      lane = ends.length;
      ends.add(0);
    }
    ends[lane] = course.endPeriod;
    lanes.add(lane);
  }
  return [
    for (var i = 0; i < group.length; i++)
      _PlacedCourse(group[i], lanes[i], ends.length)
  ];
}

class _TableLines extends CustomPainter {
  const _TableLines(this.ys, this.xs, this.color);
  final List<double> ys, xs;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final pen = Paint()
      ..color = color
      ..strokeWidth = .6;
    for (final y in ys) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), pen);
    }
    for (final x in xs) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), pen);
    }
  }

  @override
  bool shouldRepaint(covariant _TableLines old) =>
      !listEquals(old.ys, ys) || !listEquals(old.xs, xs) || old.color != color;
}
