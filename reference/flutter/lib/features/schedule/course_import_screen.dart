import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/theme/app_colors.dart';
import '../../core/widgets/app_widgets.dart';
import '../../services/course/jwxt_adapter.dart';
import '../../services/course/jwxt_adapter_registry.dart';
import '../../services/course/jwxt_school_directory.dart';
import '../../services/course/school_login_entry.dart';
import '../../services/course/academic_import_result.dart';
import '../../services/course/course_page_reader.dart';
import 'school_badge.dart';

/// 课表导入引导页：选学校/教务生态 → WebView 登录 → 自动发现并抓取课表。
/// 学校目录与适配器注册表可扩展；未收录学校仍可使用通用 HTML 表格解析。
class CourseImportScreen extends StatefulWidget {
  const CourseImportScreen({super.key});

  @override
  State<CourseImportScreen> createState() => _CourseImportScreenState();
}

class _CourseImportScreenState extends State<CourseImportScreen> {
  late final TextEditingController _schoolUrlController;
  late final TextEditingController _schoolSearchController;
  String _selectedAdapter = 'generic';
  String _schoolQuery = '';
  JwxtSchoolProfile? _selectedSchool;
  bool _opening = false;
  static const _channel = MethodChannel('com.iko.study/course_import');

  @override
  void initState() {
    super.initState();
    _schoolUrlController = TextEditingController();
    _schoolSearchController = TextEditingController();
  }

  @override
  void dispose() {
    _schoolUrlController.dispose();
    _schoolSearchController.dispose();
    super.dispose();
  }

  JwxtAdapter get _adapter => JwxtAdapterRegistry.forId(_selectedAdapter);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('学校导入')),
      body: SafeArea(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('找到你的学校',
                      style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 6),
                  const Text('在学校网页登录，打开完整课表后导入。'),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _schoolSearchController,
                    decoration: const InputDecoration(
                      labelText: '搜索学校',
                      hintText: '如 武汉大学、WHU、清华',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setState(() => _schoolQuery = value),
                  ),
                  if (_schoolQuery.trim().isNotEmpty ||
                      _selectedSchool == null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _SchoolSearchResults(
                      query: _schoolQuery,
                      onSelected: _selectSchool,
                    ),
                  ],
                  if (_selectedSchool != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    GlassCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: 10),
                      child: Row(
                        children: [
                          SchoolBadge(name: _selectedSchool!.name),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              '${_selectedSchool!.name}  ·  ${_selectedSchool!.adapterLabel}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: '清除学校选择',
                            onPressed: () => setState(() {
                              _selectedSchool = null;
                              _schoolUrlController.clear();
                            }),
                            icon: const Icon(Icons.close_rounded, size: 18),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _selectedSchool!.entryNote ?? '导入前请核对学期、周次和节次。',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text('找不到学校？'),
                    subtitle: const Text('填写学校官网公布的教务地址'),
                    children: [
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.sm,
                        children: [
                          for (final id in const [
                            'zjw',
                            'qz',
                            'qg',
                            'urp',
                            'wisedu',
                            'nanruan',
                            'chaoxing',
                            'eams',
                            'generic',
                          ])
                            ChoiceChip(
                              label: Text(JwxtAdapterRegistry.forId(id).name),
                              selected: _selectedAdapter == id,
                              onSelected: (_) => setState(() {
                                _selectedAdapter = id;
                                _selectedSchool = null;
                              }),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _schoolUrlController,
                        decoration: const InputDecoration(
                          labelText: '教务系统登录地址',
                          hintText: '如 https://jwxt.example.edu.cn',
                        ),
                        onChanged: (value) => setState(() {
                          if (_selectedSchool == null) {
                            _selectedAdapter =
                                JwxtAdapterRegistry.detect(value).id;
                          }
                        }),
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],
                  ),
                  PillButton(
                    label: _opening ? '正在打开教务…' : '登录并导入',
                    expanded: true,
                    onPressed:
                        _opening || _schoolUrlController.text.trim().isEmpty
                            ? null
                            : () => _openWebView(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
            Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text('只在本机登录学校网页。读取后先预览，确认后才替换课表。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                )),
          ],
        ),
      ),
    );
  }

  void _selectSchool(JwxtSchoolProfile profile) {
    setState(() {
      _selectedSchool = profile;
      _selectedAdapter = profile.adapterId;
      _schoolQuery = '';
      _schoolSearchController.clear();
      // 每次选校都先清掉上一个学校的地址。否则没有固定入口的学校会
      // 误用上一所学校的 URL（例如清华被带到武汉大学研究生入口）。
      _schoolUrlController
        ..clear()
        ..text = profile.loginUrl ?? '';
    });
  }

  Future<void> _openWebView(BuildContext context) async {
    if (_opening) return;
    final rawUrl = _schoolUrlController.text.trim();
    final parsed = Uri.tryParse(rawUrl);
    if (parsed == null ||
        parsed.host.isEmpty ||
        parsed.authority.contains('@') ||
        (parsed.scheme != 'http' && parsed.scheme != 'https')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入有效的教务系统网址')),
      );
      return;
    }
    final uri = schoolStudentLoginEntry(parsed);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _opening = true);
    try {
      if (!kIsWeb && Theme.of(context).platform == TargetPlatform.android) {
        String? raw;
        try {
          final theme = Theme.of(context);
          raw = await _channel.invokeMethod<String>('start', {
            'url': uri.toString(),
            'school': _selectedSchool?.name ?? '自定义学校',
            'desktop': _selectedSchool?.preferDesktop ?? false,
            'alternativeUrls':
                _selectedSchool?.alternativeUrls ?? const <String>[],
            'hostPicker': true,
            'dark': theme.brightness == Brightness.dark,
            'background': AppColors.background(theme.brightness).toARGB32(),
            'surface': AppColors.card(theme.brightness).toARGB32(),
            'foreground': AppColors.label(theme.brightness).toARGB32(),
            'accent': theme.colorScheme.primary.toARGB32(),
            'onAccent': theme.colorScheme.onPrimary.toARGB32(),
          });
        } on MissingPluginException {
          if (mounted) await _openCompatibility(uri);
          return;
        } on PlatformException catch (error) {
          if (error.code == 'MIN_SDK' || error.code == 'IMPORT_START') {
            if (mounted) await _openCompatibility(uri);
            return;
          }
          rethrow;
        }
        if (!mounted || raw == null) return;
        final response = jsonDecode(raw);
        if (response is Map && response['kind'] == 'compatibility') {
          final next = Uri.tryParse(response['url'] as String? ?? '');
          if (next == null ||
              !['https', 'http'].contains(next.scheme) ||
              next.host.isEmpty ||
              next.userInfo.isNotEmpty) {
            throw const FormatException('学校网页地址无效');
          }
          await _openCompatibility(next);
        } else {
          final result = AcademicImportResult.parse(raw);
          if (context.mounted) Navigator.pop(context, result);
        }
      } else {
        await _openCompatibility(uri);
      }
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('未写入课表：$error')),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _openCompatibility(Uri uri) async {
    final timetableUri = _selectedSchool?.timetableUrl == null
        ? null
        : Uri.tryParse(_selectedSchool!.timetableUrl!);
    final result = await Navigator.of(context).push<AcademicImportResult>(
      MaterialPageRoute(
        builder: (_) => _JwxtWebViewScreen(
          adapter: _adapter,
          initialUri: schoolStudentLoginEntry(uri),
          timetableUri: timetableUri,
          alternativeUris: [
            for (final value in _selectedSchool?.alternativeUrls ?? <String>[])
              Uri.parse(value),
          ],
          school: _selectedSchool?.name ?? '自定义学校',
        ),
      ),
    );
    if (!mounted || result == null || result.courses.isEmpty) return;
    Navigator.pop(context, result);
  }
}

class _SchoolSearchResults extends StatelessWidget {
  const _SchoolSearchResults({required this.query, required this.onSelected});

  final String query;
  final ValueChanged<JwxtSchoolProfile> onSelected;

  @override
  Widget build(BuildContext context) {
    final matches = searchJwxtSchools(query)
        .where((school) => query.trim().isNotEmpty || school.loginUrl != null)
        .toList(growable: false);
    if (matches.isEmpty) {
      return Text('没有找到学校，可直接选择“其他高校”并粘贴官方教务地址。',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return GlassCard(
      padding: EdgeInsets.zero,
      child: SizedBox(
        height: matches.length > 4 ? 360 : matches.length * 94.0,
        child: ListView.separated(
          key: ValueKey('school-results-$query'),
          primary: false,
          itemCount: matches.length,
          separatorBuilder: (_, __) => const Divider(height: .5),
          itemBuilder: (context, i) => ListTile(
            dense: true,
            leading: SchoolBadge(name: matches[i].name),
            title: Text(matches[i].name),
            subtitle: Text(matches[i].loginUrl == null
                ? '请填写学校官方教务网址'
                : matches[i].entryStatusLabel),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => onSelected(matches[i]),
          ),
        ),
      ),
    );
  }
}

class _JwxtWebViewScreen extends StatefulWidget {
  const _JwxtWebViewScreen({
    required this.adapter,
    required this.initialUri,
    this.timetableUri,
    this.alternativeUris = const [],
    required this.school,
  });

  final JwxtAdapter adapter;
  final Uri initialUri;
  final Uri? timetableUri;
  final List<Uri> alternativeUris;
  final String school;

  @override
  State<_JwxtWebViewScreen> createState() => _JwxtWebViewScreenState();
}

class _JwxtWebViewScreenState extends State<_JwxtWebViewScreen>
    with WidgetsBindingObserver {
  late final WebViewController _controller;
  String _currentUrl = '';
  String? _pageError;
  bool _loading = true;
  bool _importing = false;
  bool _discovering = false;
  Timer? _autoTimer;
  bool _probing = false;
  String _autoSignature = '';
  int _pageGeneration = 0;

  bool get _visible =>
      mounted &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed &&
      (ModalRoute.of(context)?.isCurrent ?? false);

  void _startAutomaticRead() {
    _autoTimer?.cancel();
    _autoTimer = Timer.periodic(const Duration(milliseconds: 1600), (_) async {
      if (!_visible || _loading || _importing || _discovering || _probing) {
        return;
      }
      _probing = true;
      final generation = _pageGeneration;
      try {
        final signature = await CoursePageReader.signature(_controller);
        if (!_visible ||
            generation != _pageGeneration ||
            _importing ||
            signature.isEmpty ||
            signature == _autoSignature) {
          return;
        }
        _autoSignature = signature;
        await _import(automatic: true);
      } catch (_) {
        // The login page remains usable when a frame is not readable yet.
      } finally {
        _probing = false;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startAutomaticRead();
    } else {
      _autoTimer?.cancel();
      if (_importing) _autoSignature = '';
    }
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onNavigationRequest: (request) {
          final uri = Uri.tryParse(request.url);
          return uri != null && ['https', 'http', 'about'].contains(uri.scheme)
              ? NavigationDecision.navigate
              : NavigationDecision.prevent;
        },
        onPageStarted: (url) {
          if (!mounted) return;
          _pageGeneration++;
          _autoSignature = '';
          setState(() {
            _currentUrl = url;
            _loading = true;
            _pageError = null;
          });
        },
        onPageFinished: (url) {
          if (!mounted) return;
          setState(() {
            _currentUrl = url;
            _loading = false;
          });
          // Keep school target=_blank / window.open login links inside this
          // authenticated WebView, without exporting cookies to another app.
          _controller.runJavaScript(r'''(() => {
            if (window.__ikoSameWindow) return;
            window.__ikoSameWindow = true;
            window.open = function(raw) {
              try { const u = new URL(raw, location.href);
                if (/^https?:$/.test(u.protocol)) location.href = u.href;
              } catch (_) {} return null;
            };
            document.addEventListener('click', function(e) {
              const a = e.target.closest?.('a[target="_blank"]');
              if (a && /^https?:/.test(a.href)) {
                e.preventDefault(); location.href = a.href;
              }
            }, true);
          })()''').catchError((_) {});
        },
        onWebResourceError: (error) {
          if (!mounted || error.isForMainFrame != true) return;
          setState(() {
            _loading = false;
            _pageError = '页面加载失败（${error.errorCode}）：${error.description}';
          });
        },
      ))
      ..loadRequest(widget.initialUri);
    _startAutomaticRead();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.adapter.name),
        actions: [
          IconButton(
              tooltip: '返回上一页',
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () async {
                if (await _controller.canGoBack()) await _controller.goBack();
              }),
          PopupMenuButton<Uri>(
            tooltip: '切换教务入口',
            icon: const Icon(Icons.link_rounded),
            onSelected: _loadEntry,
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: widget.initialUri, child: const Text('重新打开登录入口')),
              for (final uri in widget.alternativeUris)
                PopupMenuItem(
                    value: uri,
                    child: Text(schoolStudentLoginEntry(uri) != uri
                        ? '统一身份认证（备用）'
                        : '备用入口 · ${uri.host}')),
            ],
          ),
          if (widget.timetableUri != null)
            IconButton(
              tooltip: '打开该校课表页',
              onPressed: _loading ? null : _openKnownTimetable,
              icon: const Icon(Icons.event_note_rounded),
            ),
          IconButton(
            tooltip: '自动发现课表',
            onPressed: _discovering ? null : _discover,
            icon: const Icon(Icons.manage_search_rounded),
          ),
          IconButton(
            tooltip: '导入当前页面课表',
            onPressed: _importing ? null : _import,
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_pageError != null)
            MaterialBanner(
              content: Text(
                '${_pageError!}\n可重新打开登录入口，或稍后重试。',
              ),
              leading: const Icon(Icons.warning_amber_rounded),
              actions: [
                TextButton(
                  onPressed: () => _loadEntry(widget.initialUri),
                  child: const Text('重新打开登录入口'),
                ),
                TextButton(
                  onPressed: () => _controller.reload(),
                  child: const Text('重试'),
                ),
              ],
            ),
          Expanded(child: WebViewWidget(controller: _controller)),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg, 6, AppSpacing.lg, AppSpacing.sm),
              child: Column(
                children: [
                  Text(
                    _currentUrl.isEmpty
                        ? '正在打开登录页面…'
                        : '打开完整课表后自动读取；先预览，确认后才替换',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: PillButton(
                          label: _importing ? '正在读取课表…' : '读取当前课表',
                          expanded: true,
                          onPressed: _importing ? null : _import,
                        ),
                      ),
                      if (widget.timetableUri != null) ...[
                        const SizedBox(width: AppSpacing.xs),
                        TextButton.icon(
                          onPressed: _loading ? null : _openKnownTimetable,
                          icon: const Icon(Icons.event_note_rounded),
                          label: const Text('直达课表'),
                        ),
                      ],
                      const SizedBox(width: AppSpacing.sm),
                      IconButton.filledTonal(
                        tooltip: '自动发现课表',
                        onPressed: _discovering ? null : _discover,
                        icon: _discovering
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.manage_search_rounded),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadEntry(Uri uri) async {
    setState(() {
      _loading = true;
      _pageError = null;
    });
    await _controller.loadRequest(uri);
  }

  Future<bool> _discover({bool quiet = false}) async {
    if (_discovering) return false;
    setState(() => _discovering = true);
    try {
      final opened = await widget.adapter.navigateToTimetablePage(_controller);
      if (!mounted) return false;
      if (!opened && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('当前页面没有可直达的菜单链接。已看到课表时，请点“读取当前课表”。')),
        );
      }
      if (!opened) return false;
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已找到课表入口，正在等待页面加载')),
        );
      }
      return true;
    } catch (e) {
      if (mounted && !quiet) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('寻找课表入口失败：$e')),
        );
      }
      return false;
    } finally {
      if (mounted) setState(() => _discovering = false);
    }
  }

  Future<void> _openKnownTimetable() async {
    final uri = widget.timetableUri;
    if (uri == null) return;
    await _controller.loadRequest(uri);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已打开学校课表页，加载完整后会自动读取')),
      );
    }
  }

  Future<void> _import({bool automatic = false}) async {
    if (_importing) return;
    var generation = _pageGeneration;
    setState(() => _importing = true);
    try {
      Future<AcademicImportResult> read() => CoursePageReader.read(_controller,
          school: widget.school,
          isActive: () => _visible && generation == _pageGeneration);
      AcademicImportResult result;
      try {
        result = await read();
      } on CoursePageReadException catch (error) {
        // Do not navigate away from an already-visible timetable merely because
        // its layout is unsupported. Discovery is only for an empty landing page.
        if (automatic ||
            error.hasTimetable ||
            error.frameUrls.isNotEmpty ||
            !mounted ||
            !await _discover(quiet: true)) {
          rethrow;
        }
        await Future<void>.delayed(const Duration(milliseconds: 1000));
        if (!mounted) return;
        generation = _pageGeneration;
        result = await read();
      }
      if (!mounted || !_visible || generation != _pageGeneration) return;
      Navigator.of(context).pop<AcademicImportResult>(result);
    } on CoursePageReadException catch (error) {
      if (!mounted || automatic) return;
      if (error.frameUrls.isNotEmpty) {
        await _openFrame(error.frameUrls);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${error.hasTimetable ? '已找到课表，当前布局尚未完整读取：' : ''}${error.message}'),
        ));
      }
    } catch (e) {
      if (mounted && !automatic) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('读取课表失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _openFrame(List<Uri> frames) async {
    final selected = await showModalBottomSheet<Uri>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
        const ListTile(
            title: Text('打开课表子页面'),
            subtitle: Text('学校将内容放在独立子页面中。可在当前教务窗口正常打开后继续读取，登录状态会保留。')),
        for (final uri in frames)
          ListTile(
              leading: const Icon(Icons.open_in_new_rounded),
              title: Text(uri.host),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(context, uri)),
      ])),
    );
    if (selected != null && mounted) await _controller.loadRequest(selected);
  }
}
