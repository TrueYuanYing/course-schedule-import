import 'package:flutter/material.dart';
import '../../data/models/course.dart';
import '../../services/course/course_periods.dart';

typedef CourseImportSelection = ({
  List<Course> courses,
  bool replaceExisting,
  bool useImportedTimes
});

Future<CourseImportSelection?> previewCourseImport(
        BuildContext context, List<Course> courses,
        {List<String> warnings = const [],
        Set<String> courseIdsRequiringWeeks = const {},
        Map<int, CoursePeriod> periodTimes = const {},
        bool useTimesDefault = false,
        bool useTimesAllowed = true}) =>
    showDialog<CourseImportSelection>(
        context: context,
        builder: (_) => _Preview(
            courses: courses,
            warnings: warnings,
            courseIdsRequiringWeeks: courseIdsRequiringWeeks,
            periodTimes: periodTimes,
            useTimesDefault: useTimesDefault,
            useTimesAllowed: useTimesAllowed));

class _Preview extends StatefulWidget {
  const _Preview(
      {required this.courses,
      required this.warnings,
      required this.courseIdsRequiringWeeks,
      required this.periodTimes,
      required this.useTimesDefault,
      required this.useTimesAllowed});
  final List<Course> courses;
  final List<String> warnings;
  final Set<String> courseIdsRequiringWeeks;
  final Map<int, CoursePeriod> periodTimes;
  final bool useTimesDefault, useTimesAllowed;
  @override
  State<_Preview> createState() => _PreviewState();
}

class _PreviewState extends State<_Preview> {
  late final selected = widget.courses.map((c) => c.id).toSet();
  late bool _useTimes = widget.useTimesDefault;
  final _startWeek = TextEditingController();
  final _endWeek = TextEditingController();
  bool get _requiresWeeks =>
      selected.any(widget.courseIdsRequiringWeeks.contains);
  bool get _validWeeks {
    final start = int.tryParse(_startWeek.text),
        end = int.tryParse(_endWeek.text);
    return start != null &&
        end != null &&
        start >= 1 &&
        end >= start &&
        end <= 60;
  }

  @override
  void dispose() {
    _startWeek.dispose();
    _endWeek.dispose();
    super.dispose();
  }

  Course _confirmed(Course course) =>
      widget.courseIdsRequiringWeeks.contains(course.id)
          ? Course.fromJson({
              ...course.toJson(),
              'startWeek': int.parse(_startWeek.text),
              'endWeek': int.parse(_endWeek.text)
            })
          : course;
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text('核对课表 · ${selected.length} 条安排'),
          content: SizedBox(
              width: 560,
              height: 420,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('请核对星期、节次、周次和教室。分段周次可能显示多条安排，原课表会先备份。'),
                    if (widget.warnings.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '解析警告：${widget.warnings.take(3).join('；')}'
                          '${widget.warnings.length > 3 ? ' 等 ${widget.warnings.length} 条' : ''}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    const Text('导入将覆盖现有课表，不会追加；可用“撤销上次导入或清空”恢复。'),
                    const SizedBox(height: 12),
                    if (_requiresWeeks) ...[
                      const Text('截图未包含周次，请选择这些课程的适用周次。'),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                            child: TextField(
                                key: const ValueKey('import-start-week'),
                                controller: _startWeek,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: '开始周'),
                                onChanged: (_) => setState(() {}))),
                        const SizedBox(width: 12),
                        Expanded(
                            child: TextField(
                                key: const ValueKey('import-end-week'),
                                controller: _endWeek,
                                keyboardType: TextInputType.number,
                                decoration:
                                    const InputDecoration(labelText: '结束周'),
                                onChanged: (_) => setState(() {}))),
                      ]),
                      const SizedBox(height: 12),
                    ],
                    if (widget.periodTimes.isNotEmpty)
                      CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _useTimes,
                          title: Text(widget.useTimesAllowed
                              ? '采用学校作息 · ${widget.periodTimes.length}节'
                              : '作息时间冲突，保留现有时间'),
                          subtitle: ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 62),
                              child: SingleChildScrollView(
                                  child: Text(widget.periodTimes.entries
                                      .map((e) =>
                                          '第${e.key}节 ${e.value.start}–${e.value.end}')
                                      .join('   ')))),
                          onChanged: !widget.useTimesAllowed
                              ? null
                              : (value) =>
                                  setState(() => _useTimes = value ?? false)),
                    Expanded(
                        child: ListView.builder(
                            itemCount: widget.courses.length,
                            itemBuilder: (_, i) {
                              final c = widget.courses[i];
                              return CheckboxListTile(
                                  value: selected.contains(c.id),
                                  contentPadding: EdgeInsets.zero,
                                  title: Text(c.name),
                                  subtitle: Text(
                                      '${c.weekday.label}  ${c.timeRangeLabel}\n${widget.courseIdsRequiringWeeks.contains(c.id) ? '待确认周次' : c.weekRangeLabel}\n${c.teacher ?? ''}  ${c.room ?? ''}'
                                      '${c.note == null ? '' : '\n${c.note}'}'),
                                  onChanged: (v) => setState(() {
                                        v == true
                                            ? selected.add(c.id)
                                            : selected.remove(c.id);
                                      }));
                            })),
                  ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: selected.isEmpty || (_requiresWeeks && !_validWeeks)
                    ? null
                    : () => Navigator.pop(context, (
                          courses: widget.courses
                              .where((c) => selected.contains(c.id))
                              .map(_confirmed)
                              .toList(),
                          replaceExisting: true,
                          useImportedTimes: _useTimes,
                        )),
                child: const Text('覆盖并导入'))
          ]);
}
