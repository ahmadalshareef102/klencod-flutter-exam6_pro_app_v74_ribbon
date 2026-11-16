import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'engine_api.dart';
import 'exam_store.dart';
import 'exam_summary.dart';
import 'file_delivery.dart';
import 'screens/editor_screen.dart';
import 'screens/home_screen.dart';
import 'screens/paste_sheet.dart';
import 'screens/question_tools.dart';
import 'screens/saved_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/templates_screen.dart';
import 'theme.dart';
import 'web_shell.dart';

/// بيانات المبرمج المعروضة في «حول التطبيق».
const String kDeveloperName = 'أ. أحمد داود طه شريف';
const String kDeveloperPhone = '771274134';
const String kDeveloperEmail = 'Ahmadalshareef102@gmail.com';

/// الواجهة الأصلية للتطبيق. محرك المنصة (WebView) يعمل في الخلفية:
/// يظهر فقط كسطح لورقة A4 وكسطح كتابة نص السؤال، وكل الأزرار والقوائم أصلية.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const int kHome = 0, kEditor = 1, kPaper = 2, kTemplates = 3, kSaved = 4;

  int _tab = kHome;
  WebViewController? _web;
  late final EngineApi _api = EngineApi(() => _web);
  final Future<ExamStore> _store = openAppStore();
  int _savedTick = 0, _editorTick = 0, _tplTick = 0;
  HomeStats _stats = const HomeStats();
  DateTime? _lastBack;

  String? _focusQid;
  String _focusName = '';

  bool get _focus => _focusQid != null;

  // ------------------------------------------------------------- محرك الويب

  Future<void> _js(String code) async {
    try {
      await _web?.runJavaScript(code);
    } catch (_) {}
  }

  Future<void> _refreshStats() async {
    final store = await _store;
    final saved = (await store.listIds()).length;
    final d = await _api.editorState();
    final next = d == null
        ? HomeStats(saved: saved)
        : HomeStats(
            saved: saved,
            questions: d.questions.length,
            score: d.sums.sum,
            target: d.sums.target,
            title: d.meta['title'] ?? '',
            subject: d.meta['subject'] ?? '',
            grade: d.meta['grade'] ?? '',
          );
    if (mounted) setState(() => _stats = next);
  }

  void _onWebLoaded() {
    if (!mounted) return;
    _api.ready = true;
    setState(() {
      _editorTick++;
      _tplTick++;
    });
    _refreshStats();
  }

  void _onWebNavigate(String view) {
    if (!mounted) return;
    if (view == 'home') _goTab(kHome);
    if (view == 'saved') _goTab(kSaved);
    if (view == 'settings') _openSettings();
  }

  void _onWebToast(String msg, String type) => _snack(msg, type: type);

  Future<bool> _onWebConfirm(String title, String message) =>
      _confirm(title, message);

  // ----------------------------------------------------------------- التنقل

  Future<void> _goTab(int i) async {
    if (_focus) await _exitFocus(toEditor: false);
    setState(() {
      _tab = i;
      if (i == kSaved) _savedTick++;
      if (i == kEditor) _editorTick++;
      if (i == kTemplates) _tplTick++;
    });
    if (i == kHome) _refreshStats();
    // التكبير بالقرص مسموح في الورقة فقط (لقراءة التفاصيل)
    try {
      await _web?.enableZoom(i == kPaper);
    } catch (_) {}
    if (i == kPaper) await _showPaper();
  }

  /// يعرض الورقة ويلائم عرضها مع الشاشة.
  Future<void> _showPaper() async {
    await _js('openPreview()');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await _api.fitPaper();
  }

  Future<void> _editQuestion(String qid, String name) async {
    setState(() {
      _focusQid = qid;
      _focusName = name;
    });
    final ok = await _api.focus(qid);
    if (!ok && mounted) {
      setState(() => _focusQid = null);
      _snack('تعذر فتح السؤال للتحرير', type: 'error');
    }
  }

  Future<void> _exitFocus({bool toEditor = true}) async {
    await _api.unfocus();
    if (!mounted) return;
    setState(() {
      _focusQid = null;
      if (toEditor) {
        _tab = kEditor;
        _editorTick++;
      }
    });
  }

  Future<void> _onBack() async {
    if (_focus) return _exitFocus();
    if (_tab != kHome) return _goTab(kHome);
    final now = DateTime.now();
    if (_lastBack != null &&
        now.difference(_lastBack!) < const Duration(seconds: 2)) {
      await SystemNavigator.pop();
      return;
    }
    _lastBack = now;
    _snack('اضغط مرة أخرى للخروج');
  }

  void _snack(String msg, {String type = 'success'}) {
    if (!mounted) return;
    final color = type == 'error'
        ? AppColors.danger
        : (type == 'warning' ? const Color(0xFF8A5A00) : null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ));
  }

  Future<bool> _confirm(String title, String message, {String ok = 'موافق'}) async {
    if (!mounted) return false;
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    );
    return r ?? false;
  }

  // ----------------------------------------------------------------- الإجراءات

  bool _needEngine() {
    if (_api.ready) return true;
    _snack('المحرر لم يجهز بعد، انتظر لحظة', type: 'warning');
    return false;
  }

  Future<void> _newExam() async {
    if (!_needEngine()) return;
    final ok = await _confirm('اختبار جديد',
        'سيُفرَّغ الاختبار الحالي. احفظه أولاً إن لم تفعل. هل تريد المتابعة؟',
        ok: 'اختبار جديد');
    if (!ok) return;
    await _api.newExam();
    await _goTab(kEditor);
  }

  Future<void> _paste() async {
    if (!_needEngine()) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => PasteSheet(
        api: _api,
        onDone: () {
          if (!mounted) return;
          setState(() {
            _tab = kEditor;
            _editorTick++;
          });
        },
      ),
    );
  }

  Future<void> _saveCurrent() async {
    if (!_needEngine()) return;
    await _js('saveCurrentExam()');
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _snack('تم حفظ الاختبار');
    setState(() => _savedTick++);
    _refreshStats();
  }

  Future<void> _openSaved(String id) async {
    if (!_api.ready || !isValidExamId(id)) return _snack('تعذر فتح الاختبار');
    await _js("loadSavedExam('$id')");
    await _goTab(kEditor);
  }

  Future<void> _deleteSaved(ExamSummary exam) async {
    if (!_needEngine() || !isValidExamId(exam.id)) return;
    final ok = await _confirm(
        'حذف الاختبار',
        'سيُحذف «${exam.title.trim().isEmpty ? 'اختبار بلا عنوان' : exam.title}» نهائياً.',
        ok: 'حذف');
    if (!ok) return;
    // الحذف عبر محرك الويب يزيله من IndexedDB ومن النسخة الداخلية معاً
    await _js("dbDeleteExam('${exam.id}')");
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    setState(() => _savedTick++);
    _refreshStats();
  }

  // --------------------------------------------------------------------- الصور

  Future<List<Map<String, String>>> _pickImageItems({required bool multiple}) async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: multiple,
      withData: true,
    );
    if (res == null) return const [];
    final out = <Map<String, String>>[];
    for (final f in res.files) {
      final Uint8List? bytes = f.bytes;
      if (bytes == null) continue;
      if (bytes.length > 12 * 1024 * 1024) {
        _snack('تم تجاهل صورة أكبر من 12MB', type: 'warning');
        continue;
      }
      final ext = (f.extension ?? '').toLowerCase();
      out.add({
        'b64': base64Encode(bytes),
        'mime': ext == 'png' ? 'image/png' : (ext == 'webp' ? 'image/webp' : 'image/jpeg'),
      });
    }
    return out;
  }

  Future<void> _insertQuestionImages(bool grid) async {
    final items = await _pickImageItems(multiple: grid);
    if (items.isEmpty) return;
    await _api.insertImages(items, grid ? 'grid' : 'single');
  }

  Future<void> _pickLogo() async {
    final items = await _pickImageItems(multiple: false);
    if (items.isNotEmpty) await _api.setLogo(items.first['b64']!, items.first['mime']!);
  }

  Future<void> _pickWatermark() async {
    final items = await _pickImageItems(multiple: false);
    if (items.isNotEmpty) await _api.setWatermark(items.first['b64']!, items.first['mime']!);
  }

  // ------------------------------------------------------------- نسخ واستعادة

  void _about() {
    Future<void> open(String url) async {
      try {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      } catch (_) {}
    }

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مصمم الاختبارات المدرسية'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('الإصدار V7.0 Pro Max • يعمل دون إنترنت'),
            SizedBox(height: 14),
            Text('المبرمج', style: TextStyle(color: AppColors.muted)),
            Text(kDeveloperName, style: TextStyle(fontSize: 18)),
            SizedBox(height: 8),
            Text('الهاتف', style: TextStyle(color: AppColors.muted)),
            SelectableText(kDeveloperPhone, style: TextStyle(fontSize: 17)),
            SizedBox(height: 8),
            Text('البريد الإلكتروني', style: TextStyle(color: AppColors.muted)),
            SelectableText(kDeveloperEmail,
                textDirection: TextDirection.ltr, style: TextStyle(fontSize: 15)),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => open('tel:$kDeveloperPhone'),
            icon: const Icon(Icons.call_outlined),
            label: const Text('اتصال'),
          ),
          TextButton.icon(
            onPressed: () => open('mailto:$kDeveloperEmail'),
            icon: const Icon(Icons.mail_outline),
            label: const Text('بريد'),
          ),
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(onBackup: _backup, onRestore: _restore),
    ));
  }

  Future<void> _backup() async {
    final store = await _store;
    final exams = <Object?>[];
    for (final id in await store.listIds()) {
      final raw = await store.readExam(id);
      if (raw == null) continue;
      try {
        exams.add(jsonDecode(raw));
      } catch (_) {}
    }
    if (exams.isEmpty) return _snack('لا توجد اختبارات محفوظة للنسخ');
    final backup = {
      'app': 'ExamDesignerV70',
      'version': '7.0',
      'exportedAt': DateTime.now().toIso8601String(),
      'exams': exams,
    };
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(backup)));
    final day = DateTime.now().toIso8601String().substring(0, 10);
    if (!mounted) return;
    final r = await deliverFile(context, bytes, 'ExamDesigner_Backup_$day.json');
    if (r['ok'] == true) _snack(r['message'] as String? ?? 'تمت العملية');
  }

  Future<void> _restore() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    final bytes = res?.files.single.bytes;
    if (bytes == null) return;
    List<dynamic> exams;
    try {
      final d = jsonDecode(utf8.decode(bytes));
      if (d is! Map || d['exams'] is! List) throw const FormatException();
      exams = d['exams'] as List;
    } catch (_) {
      return _snack('الملف ليس نسخة احتياطية صالحة', type: 'error');
    }
    if (!mounted) return;
    final ok = await _confirm('استعادة نسخة',
        'سيُضاف ${exams.length} اختبار إلى المحفوظات (يُستبدل ما يحمل المعرّف نفسه).',
        ok: 'استعادة');
    if (!ok) return;
    final store = await _store;
    var count = 0;
    for (final e in exams) {
      if (e is! Map) continue;
      final id = e['id'];
      if (id is! String || !isValidExamId(id)) continue;
      final json = jsonEncode(e);
      try {
        await store.saveExam(id, json);
        await _js('dbSaveExam(JSON.parse(${jsonEncode(json)}))');
        count++;
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() => _savedTick++);
    _refreshStats();
    _snack('تمت استعادة $count اختبار');
  }

  // ------------------------------------------------------------------ الواجهة

  @override
  Widget build(BuildContext context) {
    final index = _focus ? kPaper : _tab;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onBack();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: index,
            sizing: StackFit.expand,
            children: [
              HomeScreen(
                stats: _stats,
                onNewExam: _newExam,
                onPaste: _paste,
                onPreview: () => _goTab(kPaper),
                onOpenEditor: () => _goTab(kEditor),
                onOpenTemplates: () => _goTab(kTemplates),
                onOpenSaved: () => _goTab(kSaved),
                onOpenSettings: _openSettings,
                onSave: _saveCurrent,
                onAbout: _about,
              ),
              EditorScreen(
                api: _api,
                tick: _editorTick,
                onPreview: () => _goTab(kPaper),
                onPaste: _paste,
                onNewExam: _newExam,
                onEditQuestion: _editQuestion,
                onOpenTemplates: () => _goTab(kTemplates),
              ),
              Column(
                children: [
                  if (_focus)
                    _FocusBar(
                      title: _focusName,
                      onDone: _exitFocus,
                      onUndo: _api.undo,
                      onRedo: _api.redo,
                      onSave: _saveCurrent,
                    )
                  else
                    _PaperBar(
                      onLang: () async {
                        await _api.toggleLang();
                        await _showPaper();
                      },
                      onWord: _api.exportWord,
                      onPrint: _api.print,
                      onSave: _saveCurrent,
                    ),
                  Expanded(
                    child: WebShell(
                      key: const ValueKey('engine'),
                      onController: (c) => _web = c,
                      onNavigate: _onWebNavigate,
                      onToast: _onWebToast,
                      onConfirm: _onWebConfirm,
                      onLoaded: _onWebLoaded,
                    ),
                  ),
                  if (_focus)
                    QuestionRibbon(
                      api: _api,
                      onPickImages: _insertQuestionImages,
                      onMessage: (m) => _snack(m, type: 'warning'),
                    ),
                ],
              ),
              TemplatesScreen(
                api: _api,
                tick: _tplTick,
                onPickLogo: _pickLogo,
                onPickWatermark: _pickWatermark,
                onPreview: () => _goTab(kPaper),
              ),
              SavedScreen(
                store: _store,
                tick: _savedTick,
                onOpen: _openSaved,
                onDelete: _deleteSaved,
              ),
            ],
          ),
        ),
        bottomNavigationBar: _focus
            ? null
            : NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: _goTab,
                destinations: const [
                  NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home),
                      label: 'الرئيسية'),
                  NavigationDestination(
                      icon: Icon(Icons.edit_note),
                      selectedIcon: Icon(Icons.edit_note),
                      label: 'المحرر'),
                  NavigationDestination(
                      icon: Icon(Icons.description_outlined),
                      selectedIcon: Icon(Icons.description),
                      label: 'الورقة A4'),
                  NavigationDestination(
                      icon: Icon(Icons.palette_outlined),
                      selectedIcon: Icon(Icons.palette),
                      label: 'التنسيق'),
                  NavigationDestination(
                      icon: Icon(Icons.folder_open),
                      selectedIcon: Icon(Icons.folder),
                      label: 'المحفوظة'),
                ],
              ),
      ),
    );
  }
}

class _PaperBar extends StatelessWidget {
  const _PaperBar({
    required this.onLang,
    required this.onWord,
    required this.onPrint,
    required this.onSave,
  });

  final VoidCallback onLang;
  final VoidCallback onWord;
  final VoidCallback onPrint;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    Widget btn(IconData i, String tip, VoidCallback f) => IconButton(
          icon: Icon(i),
          tooltip: tip,
          color: AppColors.maroon,
          onPressed: f,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 2),
      child: Row(
        children: [
          const Expanded(
            child: Text('الورقة A4',
                style: TextStyle(fontSize: 24, color: AppColors.ink)),
          ),
          btn(Icons.translate, 'عربي / EN', onLang),
          btn(Icons.description_outlined, 'تصدير Word', onWord),
          btn(Icons.print_outlined, 'طباعة / PDF', onPrint),
          btn(Icons.save_outlined, 'حفظ', onSave),
        ],
      ),
    );
  }
}

class _FocusBar extends StatelessWidget {
  const _FocusBar({
    required this.title,
    required this.onDone,
    required this.onUndo,
    required this.onRedo,
    required this.onSave,
  });

  final String title;
  final VoidCallback onDone;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        child: Row(
          children: [
            Expanded(
              child: Text(title.isEmpty ? 'تحرير السؤال' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 19, color: AppColors.ink)),
            ),
            IconButton(
                tooltip: 'تراجع',
                onPressed: onUndo,
                icon: const Icon(Icons.undo, color: AppColors.maroon)),
            IconButton(
                tooltip: 'إعادة',
                onPressed: onRedo,
                icon: const Icon(Icons.redo, color: AppColors.maroon)),
            IconButton(
                tooltip: 'حفظ الاختبار',
                onPressed: onSave,
                icon: const Icon(Icons.save_outlined, color: AppColors.maroon)),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: onDone,
              icon: const Icon(Icons.check),
              label: const Text('تم'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.maroon,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }
}
