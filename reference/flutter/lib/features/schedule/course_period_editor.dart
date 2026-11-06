import 'package:flutter/material.dart';
import '../../services/course/course_periods.dart';

Future<CoursePeriods?> editCoursePeriods(
    BuildContext context, CoursePeriods current, int requiredCount) {
  return showDialog<CoursePeriods>(
      context: context,
      builder: (_) =>
          _PeriodEditor(current: current, requiredCount: requiredCount));
}

class _PeriodEditor extends StatefulWidget {
  const _PeriodEditor({required this.current, required this.requiredCount});
  final CoursePeriods current;
  final int requiredCount;
  @override
  State<_PeriodEditor> createState() => _PeriodEditorState();
}

class _PeriodEditorState extends State<_PeriodEditor> {
  late int count =
      widget.current.requiredCount(widget.requiredCount).clamp(1, 24);
  late final starts = [
    for (var i = 1; i <= 24; i++)
      TextEditingController(text: widget.current.times[i]?.start ?? '')
  ];
  late final ends = [
    for (var i = 1; i <= 24; i++)
      TextEditingController(text: widget.current.times[i]?.end ?? '')
  ];
  String? error;
  @override
  void dispose() {
    for (final field in [...starts, ...ends]) {
      field.dispose();
    }
    super.dispose();
  }

  void save() {
    final times = <int, CoursePeriod>{};
    int end = -1;
    for (var i = 0; i < count; i++) {
      final a = starts[i].text.trim(), b = ends[i].text.trim();
      if (a.isEmpty && b.isEmpty) continue;
      final slot = CoursePeriod.parse({'start': a, 'end': b});
      if (slot == null || CoursePeriod.minutes(a)! < end) {
        setState(() => error = '请检查第${i + 1}节的起止时间，时间使用08:00格式，节次不能重叠。');
        return;
      }
      times[i + 1] = slot;
      end = CoursePeriod.minutes(b)!;
    }
    Navigator.pop(context, CoursePeriods(count: count, times: times));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('每日节次与作息'),
          content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<int>(
                    initialValue: count,
                    decoration: const InputDecoration(labelText: '每日节数'),
                    items: [
                      for (var i = widget.requiredCount.clamp(1, 24);
                          i <= 24;
                          i++)
                        DropdownMenuItem(value: i, child: Text('$i 节'))
                    ],
                    onChanged: (value) => setState(() => count = value!)),
                const SizedBox(height: 16),
                for (var i = 0; i < count; i++)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(children: [
                        SizedBox(width: 42, child: Text('${i + 1}节')),
                        Expanded(
                            child: TextField(
                                controller: starts[i],
                                keyboardType: TextInputType.datetime,
                                decoration: const InputDecoration(
                                    labelText: '开始', hintText: '08:00'))),
                        const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 8),
                            child: Text('—')),
                        Expanded(
                            child: TextField(
                                controller: ends[i],
                                keyboardType: TextInputType.datetime,
                                decoration: const InputDecoration(
                                    labelText: '结束', hintText: '08:45'))),
                      ])),
                if (error != null)
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(onPressed: save, child: const Text('保存'))
          ]);
}
