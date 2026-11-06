import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../data/models/course.dart';
import '../../services/course/course_image_parser.dart';
import '../../services/course/academic_calendar.dart';
import 'course_import_screen.dart';
import 'course_import_preview.dart';
import '../../services/course/course_import_data.dart';
import '../../services/course/academic_import_result.dart';
import '../../services/course/jwxt_html_parser.dart';
import '../study/scene_packs.dart';
import '../../services/course/course_periods.dart';
import '../../core/widgets/iko_segmented_control.dart';
import 'course_week_table.dart';
import 'course_period_editor.dart';

/// 课表页：当前周课程列表 + 手动添加 + 截图/教务导入入口。
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, this.now});

  final DateTime Function()? now;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen>
    with WidgetsBindingObserver {
  int? _selectedWeek;
  int _view = 0;
  bool get _showCalendar => _view == 2;
  late DateTime _today;
  late DateTime _selectedDate;
  late DateTime _visibleMonth;
  Timer? _midnight;
  DateTime get _now => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    _today = _now;
    _selectedDate = _today;
    _visibleMonth = DateTime(_today.year, _today.month);
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
  }

  void _refreshDate() {
    final now = _now;
    if (_sameDate(now, _today)) return;
    setState(() {
      if (_sameDate(_selectedDate, _today)) {
        _selectedDate = now;
        _visibleMonth = DateTime(now.year, now.month);
      }
      _today = now;
    });
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    final now = _now;
    _midnight =
        Timer(DateTime(now.year, now.month, now.day + 1).difference(now), () {
      if (!mounted) return;
      _refreshDate();
      _scheduleMidnight();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _midnight?.cancel();
    if (state == AppLifecycleState.resumed && mounted) {
      _refreshDate();
      _scheduleMidnight();
    }
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storeAsync = ref.watch(courseStoreProvider);

    return Scaffold(
      body: SafeArea(
        child: storeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败：$e')),
          data: (store) => _buildBody(store.courses),
        ),
      ),
    );
  }

  Widget _buildBody(List<Course> courses) {
    final calendar = ref.watch(academicCalendarProvider);
    final store = ref.watch(courseStoreProvider).valueOrNull!;
    final currentWeek = calendar.weekOf(_today);
    final selectedWeek = _selectedWeek ?? currentWeek;
    final currentCourses =
        courses.where((course) => course.occursInWeek(selectedWeek)).toList();
    final size = MediaQuery.sizeOf(context);
    final compact = size.height < 500 && size.width > size.height;
    final views = IkoSegmentedControl(labels: const [
      '表格',
      '列表',
      '日历'
    ], icons: const [
      Icons.table_chart_outlined,
      Icons.view_agenda_outlined,
      Icons.calendar_month_outlined
    ], selectedIcons: const [
      Icons.table_chart_rounded,
      Icons.view_agenda_rounded,
      Icons.calendar_month_rounded
    ], selected: _view, onChanged: (value) => setState(() => _view = value));
    final weeks = _WeekNavigator(
        selectedWeek: selectedWeek,
        currentWeek: currentWeek,
        maxImportedWeek: courses.fold<int>(30,
            (last, course) => course.endWeek > last ? course.endWeek : last),
        onChanged: (week) => _selectCalendarDate(week == currentWeek
            ? _today
            : DateTime(
                calendar.startDate.year,
                calendar.startDate.month,
                calendar.startDate.day -
                    calendar.startDate.weekday +
                    1 +
                    (week - 1) * 7)));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text('课程表',
                      style: Theme.of(context).textTheme.titleMedium))),
          IconButton(
              tooltip: '本学期开学日',
              onPressed: _setSemesterStart,
              icon: const Icon(Icons.event_available_outlined)),
          IconButton(
              tooltip: '添加课表',
              onPressed: _showAddOptions,
              icon: const Icon(Icons.add_circle_outline_rounded)),
          if (compact && (store.recoveredEntryCount > 0 || currentWeek > 60))
            IconButton(
                tooltip: '课表提示',
                icon: const Icon(Icons.info_outline_rounded),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: const Text('课表提示'),
                            content: Text(
                                '${store.recoveredEntryCount > 0 ? '有 ${store.recoveredEntryCount} 条存档无法读取，原始存档已备份。' : ''}${currentWeek > 60 ? '已超过第60周，请核对学期开学日。' : ''}'),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭'))
                            ]))),
          _courseMenu(courses),
        ]),
        if (store.semesterStart == null && !compact)
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: _setSemesterStart,
                  child: const Text('设置开学日，校准周次'))),
        if (store.recoveredEntryCount > 0 && !compact)
          Text('有 ${store.recoveredEntryCount} 条存档无法读取，原始存档已备份。',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        if (currentWeek > 60 && !compact)
          const Text('已超过第60周，请核对学期开学日。', maxLines: 2),
        LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 520
                ? Row(children: [
                    Expanded(flex: 3, child: views),
                    const SizedBox(width: 12),
                    Expanded(flex: 2, child: weeks)
                  ])
                : Column(children: [views, const SizedBox(height: 4), weeks])),
        const SizedBox(height: 6),
        Expanded(
            child: _view == 0
                ? CourseWeekTable(
                    courses: courses,
                    periods: store.periods,
                    week: selectedWeek,
                    today: _today,
                    weekStart: DateTime(
                        calendar.startDate.year,
                        calendar.startDate.month,
                        calendar.startDate.day -
                            calendar.startDate.weekday +
                            1 +
                            (selectedWeek - 1) * 7))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
                    children: [
                        if (_showCalendar)
                          _buildCalendarView(courses, calendar)
                        else ...[
                          if (courses.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              child: Text(
                                '还没有课程。点“添加课表”，从学校导入，或添加自己的课程。',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium!
                                    .copyWith(color: AppColors.secondaryLabel),
                              ),
                            )
                          else if (currentCourses.isEmpty)
                            _buildEmptyCourses(selectedWeek, courses)
                          else
                            for (final c in _sortedByWeekday(currentCourses))
                              _CourseRow(course: c, onDelete: () => _delete(c)),
                        ],
                      ])),
      ]),
    );
  }

  Widget _courseMenu(List<Course> courses) => PopupMenuButton<String>(
        tooltip: '课表管理',
        icon: const Icon(Icons.more_horiz_rounded),
        onSelected: (action) {
          if (action == 'semester') _setSemesterStart();
          if (action == 'undo') _undoImport();
          if (action == 'clear') _clearTimetable();
          if (action == 'periods') _editPeriods(courses);
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'semester', child: Text('本学期开学日')),
          const PopupMenuItem(value: 'periods', child: Text('每日节次与作息')),
          const PopupMenuItem(value: 'undo', child: Text('撤销上次操作')),
          PopupMenuItem(
            value: 'clear',
            enabled: courses.isNotEmpty,
            child: const Text('一键清空课表'),
          ),
        ],
      );

  Future<void> _editPeriods(List<Course> courses) async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    final required =
        courses.fold<int>(1, (n, c) => c.endPeriod > n ? c.endPeriod : n);
    final result = await editCoursePeriods(context, store.periods, required);
    if (result == null) return;
    try {
      await store.setPeriods(result);
      ref.invalidate(courseStoreProvider);
    } catch (e) {
      if (mounted) _toast('作息未保存，请重试。');
    }
  }

  void _showAddOptions() {
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 600),
      builder: (sheet) {
        void choose(VoidCallback action) {
          Navigator.pop(sheet);
          action();
        }

        final theme = Theme.of(sheet);
        return ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: MediaQuery.sizeOf(sheet).height * .8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('添加课表', style: theme.textTheme.titleLarge),
                const SizedBox(height: 6),
                Text('选择一种方式，导入后再核对课程。', style: theme.textTheme.bodySmall),
                const SizedBox(height: 20),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                    leading: Icon(Icons.school_outlined,
                        color: theme.colorScheme.primary),
                    title: const Text('学校导入'),
                    subtitle: const Text('搜索学校，在教务网页登录'),
                    trailing: const Icon(Icons.arrow_forward_rounded),
                    onTap: () => choose(_openJwxtImport),
                  ),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => choose(_pickAndOcr),
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('图片识别'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => choose(_openAddCourse),
                      icon: const Icon(Icons.edit_calendar_outlined),
                      label: const Text('手动添加'),
                    ),
                  ),
                ]),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: () => choose(_importFile),
                  icon: const Icon(Icons.file_open_outlined, size: 18),
                  label: const Text('从文件导入'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCalendarView(List<Course> courses, AcademicCalendar calendar) {
    final theme = Theme.of(context);
    final brightness = theme.brightness;
    final year = _visibleMonth.year;
    final month = _visibleMonth.month;
    final leading = DateTime(year, month).weekday - 1;
    final days = DateTime(year, month + 1, 0).day;
    final cells = ((leading + days + 6) ~/ 7) * 7;
    final selectedCourses = calendar.coursesOn(_selectedDate, courses);
    final today = _today;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GlassCard(
          child: Column(
            children: [
              Row(children: [
                IconButton(
                  tooltip: '上个月',
                  onPressed: () => _changeMonth(-1),
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                    child: Center(
                        child: Text('$year 年 $month 月',
                            style: theme.textTheme.titleMedium))),
                TextButton(
                  onPressed: () => _selectCalendarDate(today),
                  child: const Text('今天'),
                ),
                IconButton(
                  tooltip: '下个月',
                  onPressed: () => _changeMonth(1),
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                for (final weekday in const ['一', '二', '三', '四', '五', '六', '日'])
                  Expanded(
                      child: Center(
                          child: Text(weekday,
                              style: theme.textTheme.labelMedium))),
              ]),
              const SizedBox(height: AppSpacing.sm),
              LayoutBuilder(builder: (context, constraints) {
                final cellWidth =
                    (constraints.maxWidth - 6 * AppSpacing.xs) / 7;
                double textHeight(String text, TextStyle style) {
                  final painter = TextPainter(
                      text: TextSpan(
                          text: text,
                          style: MediaQuery.boldTextOf(context)
                              ? style.copyWith(fontWeight: FontWeight.bold)
                              : style),
                      textScaler: MediaQuery.textScalerOf(context),
                      textDirection: Directionality.of(context))
                    ..layout(maxWidth: cellWidth);
                  final result = painter.height;
                  painter.dispose();
                  return result;
                }

                var dayHeight = 0.0, weekHeight = 0.0, countHeight = 0.0;
                for (var day = 1; day <= days; day++) {
                  final date = DateTime(year, month, day);
                  final a = textHeight(
                      '$day',
                      theme.textTheme.titleSmall!
                          .copyWith(fontWeight: FontWeight.w700));
                  if (a > dayHeight) dayHeight = a;
                  if (day == 1 || date.weekday == DateTime.monday) {
                    final b = textHeight('第${calendar.weekOf(date)}周',
                        theme.textTheme.labelSmall!.copyWith(fontSize: 9));
                    if (b > weekHeight) weekHeight = b;
                  }
                  final count = calendar.coursesOn(date, courses).length;
                  if (count > 0) {
                    final c =
                        textHeight('$count 门', theme.textTheme.labelSmall!);
                    if (c > countHeight) countHeight = c;
                  }
                }
                final minimum = constraints.maxWidth < 500 ? 58.0 : 76.0;
                final measured = dayHeight + weekHeight + countHeight + 8;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: cells,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisExtent: measured > minimum ? measured : minimum,
                    mainAxisSpacing: AppSpacing.xs,
                    crossAxisSpacing: AppSpacing.xs,
                  ),
                  itemBuilder: (context, index) {
                    final day = index - leading + 1;
                    if (day < 1 || day > days) {
                      return const SizedBox.shrink();
                    }
                    final date = DateTime(year, month, day);
                    final week = calendar.weekOf(date);
                    final count = calendar.coursesOn(date, courses).length;
                    final selected = _sameDate(date, _selectedDate);
                    final isToday = _sameDate(date, today);
                    return Semantics(
                      button: true,
                      selected: selected,
                      label: '$month月$day日，第$week周，$count门课程',
                      child: Material(
                        color: selected
                            ? AppColors.selectionAccent(brightness)
                                .withValues(alpha: .19)
                            : AppColors.fill(brightness).withValues(alpha: .65),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          onTap: () => _selectCalendarDate(date),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                              border: isToday
                                  ? Border.all(
                                      color:
                                          AppColors.selectionAccent(brightness))
                                  : null,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text('$day',
                                    style: theme.textTheme.titleSmall?.copyWith(
                                      color: selected
                                          ? AppColors.selectionAccent(
                                              brightness)
                                          : null,
                                      fontWeight: selected || isToday
                                          ? FontWeight.w700
                                          : null,
                                    )),
                                if (day == 1 || date.weekday == DateTime.monday)
                                  Text('第$week周',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        fontSize: 9,
                                        color: selected
                                            ? AppColors.selectionAccent(
                                                brightness)
                                            : AppColors.secondary(brightness),
                                      )),
                                if (count > 0)
                                  Text('$count 门',
                                      style:
                                          theme.textTheme.labelSmall?.copyWith(
                                        color: AppColors.selectionAccent(
                                            brightness),
                                      )),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SectionHeader(
            '${_selectedDate.month}月${_selectedDate.day}日 · 第${calendar.weekOf(_selectedDate)}周 · ${Weekday.fromDateTime(_selectedDate).label}'),
        if (selectedCourses.isEmpty)
          _buildEmptyCourses(calendar.weekOf(_selectedDate), courses,
              dayOnly: true)
        else
          for (final course in selectedCourses) _CourseRow(course: course),
      ],
    );
  }

  Widget _buildEmptyCourses(int week, List<Course> courses,
      {bool dayOnly = false}) {
    final lastImportedWeek = courses.fold<int>(0,
        (latest, course) => course.endWeek > latest ? course.endWeek : latest);
    if (lastImportedWeek > 0 && week > lastImportedWeek) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('已导入课表截至第$lastImportedWeek周；第$week周尚无已导入的课程。',
                style: Theme.of(context).textTheme.bodyMedium),
            TextButton(
              onPressed: _openJwxtImport,
              child: const Text('重新同步教务课表'),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(dayOnly ? '当天没有课程' : '第$week周暂无课程，其他周次仍保留在课表中。',
          style: Theme.of(context).textTheme.bodyMedium),
    );
  }

  void _changeMonth(int offset) {
    final month = DateTime(_visibleMonth.year, _visibleMonth.month + offset);
    _selectCalendarDate(month);
  }

  void _selectCalendarDate(DateTime date) {
    final calendar = ref.read(academicCalendarProvider);
    setState(() {
      _visibleMonth = DateTime(date.year, date.month);
      _selectedDate = date;
      _selectedWeek = _sameDate(date, _today) ? null : calendar.weekOf(date);
    });
  }

  bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<Course> _sortedByWeekday(List<Course> courses) {
    final list = [...courses];
    list.sort((a, b) {
      if (a.weekday.num != b.weekday.num) {
        return a.weekday.num.compareTo(b.weekday.num);
      }
      return a.startPeriod.compareTo(b.startPeriod);
    });
    return list;
  }

  Future<void> _setSemesterStart() async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    final date = await showDatePicker(
      context: context,
      helpText: '本学期开学日',
      cancelText: '取消',
      confirmText: '确定',
      fieldLabelText: '开学日期',
      fieldHintText: '年/月/日',
      errorFormatText: '请按年/月/日填写',
      errorInvalidText: '请选择有效日期',
      builder: (context, child) {
        final theme = Theme.of(context);
        final landscape =
            MediaQuery.orientationOf(context) == Orientation.landscape;
        return Localizations.override(
            context: context,
            locale: const Locale('zh', 'CN'),
            delegates: GlobalMaterialLocalizations.delegates,
            child: Theme(
                data: theme.copyWith(
                    datePickerTheme: theme.datePickerTheme.copyWith(
                        headerHeadlineStyle: theme
                            .datePickerTheme.headerHeadlineStyle
                            ?.copyWith(fontSize: landscape ? 16 : 27))),
                child: child!));
      },
      initialDate: store.calendar.startDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 5, 12, 31),
    );
    if (date == null || !mounted) return;
    await store.setSemesterStart(date);
    if (!mounted) return;
    _selectCalendarDate(_today);
    ref.invalidate(courseStoreProvider);
  }

  Future<void> _delete(Course c) async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    await store.remove(c.id);
    ref.invalidate(courseStoreProvider);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 2)));
  }

  /// 本地识别截图；确认星期、节次和适用周次后才替换课表。
  Future<void> _pickAndOcr() async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    try {
      _toast('正在识别课表…');
      final result = await CourseImageParser().pickAndParseResult();
      if (!mounted) return;
      if (result == null) return; // 用户取消
      final courses = result.courses;
      if (courses.isEmpty) {
        _toast('未能识别出课程，请换一张更清晰的课表截图');
        return;
      }
      await _confirmAndSave(courses,
          warnings: [
            ...result.warnings,
            if (result.needsConfirmation) '识别结果请逐项核对'
          ],
          courseIdsRequiringWeeks: result.courseIdsRequiringWeeks);
    } catch (e) {
      if (mounted) _toast('识别失败：$e');
    }
  }

  Future<void> _openJwxtImport() async {
    final imported = await Navigator.of(context).push<AcademicImportResult>(
      MaterialPageRoute(builder: (_) => const CourseImportScreen()),
    );
    if (!mounted || imported == null || imported.courses.isEmpty) return;
    await _confirmAndSave(imported.courses,
        warnings: imported.warnings, periodTimes: imported.periodTimes);
  }

  Future<void> _confirmAndSave(List<Course> courses,
      {List<String> warnings = const [],
      Set<String> courseIdsRequiringWeeks = const {},
      Map<int, CoursePeriod> periodTimes = const {}}) async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    final schoolPeriods = store.periods.withImportedTimes(periodTimes);
    final accepted = await previewCourseImport(context, courses,
        warnings: [
          ...warnings,
          if (schoolPeriods == null) '学校作息与现有时间冲突，本次保留原作息，可在作息设置中核对。'
        ],
        courseIdsRequiringWeeks: courseIdsRequiringWeeks,
        periodTimes: periodTimes,
        useTimesDefault: periodTimes.isNotEmpty && schoolPeriods != null,
        useTimesAllowed: schoolPeriods != null);
    if (!mounted || accepted == null) return;
    await store.replaceAll(accepted.courses,
        periods: periodTimes.isNotEmpty && accepted.useImportedTimes
            ? schoolPeriods
            : null);
    ref.invalidate(courseStoreProvider);
    if (mounted) _toast('已覆盖课表 · ${accepted.courses.length} 条课程安排');
  }

  Future<void> _importFile() async {
    try {
      final file = await ScenePacks.channel
          .invokeMapMethod<String, dynamic>('pickCourse');
      if (file == null || !mounted) return;
      final text = (file['text'] as String).replaceFirst('\uFEFF', '').trim();
      final name = (file['name'] as String).toLowerCase();
      final courses = text.startsWith('<')
          ? JwxtHtmlParser.parse(text)
          : name.endsWith('.json') ||
                  text.startsWith('[') ||
                  text.startsWith('{')
              ? CourseImportData.json(text)
              : CourseImportData.csv(text);
      if (courses.isEmpty) {
        _toast('没有识别到课程，请使用教务完整课表 HTML 或标准 CSV 模板');
        return;
      }
      await _confirmAndSave(courses);
    } catch (e) {
      if (mounted) _toast('未写入课表：$e');
    }
  }

  Future<void> _clearTimetable() async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null || store.courses.isEmpty) return;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('清空全部课程？'),
              content: Text(
                  '将清空 ${store.courses.length} 条课程安排，保留开学日和其他设置。原课表会备份，可通过“撤销上次导入或清空”恢复。'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('清空课表')),
              ],
            ));
    if (confirmed != true || !mounted) return;
    try {
      await store.replaceAll(const []);
      ref.invalidate(courseStoreProvider);
      if (mounted) _toast('已清空课表，可重新导入或撤销恢复');
    } catch (error) {
      if (mounted) _toast('清空失败：$error');
    }
  }

  Future<void> _undoImport() async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('恢复上次操作前的课表？'),
                content: const Text('这会撤销上次导入或清空，以及之后的课表修改。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('恢复'))
                ]));
    if (confirm != true || !mounted) return;
    try {
      final restored = await store.undoImport();
      ref.invalidate(courseStoreProvider);
      if (mounted) _toast(restored ? '已恢复课表' : '尚无课表备份');
    } catch (e) {
      if (mounted) _toast('$e');
    }
  }

  Future<void> _openAddCourse() async {
    final store = ref.read(courseStoreProvider).valueOrNull;
    if (store == null) return;
    final course = await showModalBottomSheet<Course>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddCourseSheet(),
    );
    if (course != null) {
      await store.upsert(course);
      if (mounted) ref.invalidate(courseStoreProvider);
    }
  }
}

/// 周次浏览器：支持前后切换、直接跳周和一键回到当前周。
class _WeekNavigator extends StatelessWidget {
  const _WeekNavigator({
    required this.selectedWeek,
    required this.currentWeek,
    required this.maxImportedWeek,
    required this.onChanged,
  });

  final int selectedWeek;
  final int currentWeek;
  final int maxImportedWeek;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lastWeek = [currentWeek, selectedWeek, maxImportedWeek]
        .reduce((a, b) => a > b ? a : b);
    return GlassCard(
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      child: Row(
        children: [
          IconButton(
            tooltip: '上一周',
            onPressed:
                selectedWeek > 1 ? () => onChanged(selectedWeek - 1) : null,
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: selectedWeek,
                isExpanded: true,
                alignment: Alignment.center,
                items: [
                  for (var week = 1; week <= lastWeek; week++)
                    DropdownMenuItem(
                      value: week,
                      child: Center(
                          child: FittedBox(
                              fit: BoxFit.scaleDown, child: Text('第 $week 周'))),
                    ),
                ],
                onChanged: (week) {
                  if (week != null) onChanged(week);
                },
              ),
            ),
          ),
          IconButton(
            tooltip: '下一周',
            onPressed: selectedWeek < lastWeek
                ? () => onChanged(selectedWeek + 1)
                : null,
            icon: const Icon(Icons.chevron_right_rounded),
          ),
          if (selectedWeek != currentWeek)
            TextButton(
              onPressed: () => onChanged(currentWeek),
              child: Text('本周', style: theme.textTheme.labelLarge),
            ),
        ],
      ),
    );
  }
}

/// 手动添加课程表单。
class _AddCourseSheet extends StatefulWidget {
  const _AddCourseSheet();

  @override
  State<_AddCourseSheet> createState() => _AddCourseSheetState();
}

class _AddCourseSheetState extends State<_AddCourseSheet> {
  final _nameCtrl = TextEditingController();
  final _teacherCtrl = TextEditingController();
  final _roomCtrl = TextEditingController();
  Weekday _weekday = Weekday.monday;
  int _startPeriod = 1;
  int _endPeriod = 2;
  int _startWeek = 1;
  int _endWeek = 20;
  int? _weekParity;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _teacherCtrl.dispose();
    _roomCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('添加课程', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: '课程名称（必填）'),
          ),
          const SizedBox(height: AppSpacing.md),
          // 星期选择
          DropdownButtonFormField<Weekday>(
            initialValue: _weekday,
            decoration: const InputDecoration(labelText: '星期'),
            items: Weekday.values
                .map((w) => DropdownMenuItem(value: w, child: Text(w.label)))
                .toList(),
            onChanged: (v) => setState(() => _weekday = v ?? _weekday),
          ),
          const SizedBox(height: AppSpacing.md),
          // 节次
          Row(
            children: [
              Expanded(
                child: _PeriodDropdown(
                  label: '开始节',
                  value: _startPeriod,
                  onChanged: (v) => setState(() => _startPeriod = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PeriodDropdown(
                  label: '结束节',
                  value: _endPeriod,
                  onChanged: (v) => setState(() => _endPeriod = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _WeekDropdown(
                  label: '开始周',
                  value: _startWeek,
                  onChanged: (v) => setState(() => _startWeek = v),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _WeekDropdown(
                  label: '结束周',
                  value: _endWeek,
                  onChanged: (v) => setState(() => _endWeek = v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<int?>(
            initialValue: _weekParity,
            decoration: const InputDecoration(labelText: '上课规律'),
            items: const [
              DropdownMenuItem<int?>(value: null, child: Text('每周')),
              DropdownMenuItem<int?>(value: 1, child: Text('单周')),
              DropdownMenuItem<int?>(value: 0, child: Text('双周')),
            ],
            onChanged: (v) => setState(() => _weekParity = v),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _teacherCtrl,
            decoration: const InputDecoration(labelText: '老师（可选）'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _roomCtrl,
            decoration: const InputDecoration(labelText: '教室（可选）'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PillButton(
            label: '保存',
            expanded: true,
            height: 50,
            onPressed: _save,
          ),
        ],
      ),
    );
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请填写课程名称')),
      );
      return;
    }
    if (_endPeriod < _startPeriod) {
      _endPeriod = _startPeriod;
    }
    final course = Course(
      id: 'c_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      weekday: _weekday,
      startPeriod: _startPeriod,
      endPeriod: _endPeriod,
      startWeek: _startWeek,
      endWeek: _endWeek < _startWeek ? _startWeek : _endWeek,
      weekParity: _weekParity,
      teacher:
          _teacherCtrl.text.trim().isEmpty ? null : _teacherCtrl.text.trim(),
      room: _roomCtrl.text.trim().isEmpty ? null : _roomCtrl.text.trim(),
    );
    Navigator.of(context).pop(course);
  }
}

class _WeekDropdown extends StatelessWidget {
  const _WeekDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (var week = 1; week <= 25; week++)
          DropdownMenuItem(value: week, child: Text('第 $week 周')),
      ],
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}

class _PeriodDropdown extends StatelessWidget {
  const _PeriodDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: List.generate(12, (i) => i + 1)
          .map((n) => DropdownMenuItem(value: n, child: Text('第 $n 节')))
          .toList(),
      onChanged: (v) => onChanged(v ?? value),
    );
  }
}

/// 单门课程行。
class _CourseRow extends StatelessWidget {
  const _CourseRow({required this.course, this.onDelete});
  final Course course;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: GlassCard(
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.tint,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(course.name, style: theme.textTheme.titleMedium),
                  Text(
                    '${course.weekday.label} ${course.timeRangeLabel}'
                    ' · ${course.weekRangeLabel}'
                    '${course.room != null ? ' · ${course.room}' : ''}'
                    '${course.teacher != null ? ' · ${course.teacher}' : ''}'
                    '${course.note != null ? ' · ${course.note}' : ''}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.pink, size: 20),
                onPressed: onDelete,
              ),
          ],
        ),
      ),
    );
  }
}
