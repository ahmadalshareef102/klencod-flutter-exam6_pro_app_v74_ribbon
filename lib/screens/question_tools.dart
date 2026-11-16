import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../engine_api.dart';
import '../math_data.dart';
import '../theme.dart';
import 'math_sheet.dart';

class _Tool {
  const _Tool(this.label, this.run, {this.icon, this.glyph, this.stateKey});

  final String label;
  final Future<void> Function() run;
  final IconData? icon;

  /// نص يظهر بدل الأيقونة (رموز رياضية وأحجام).
  final String? glyph;

  /// مفتاح حالة التنسيق لتظليل الزر عند تفعيله.
  final String? stateKey;
}

class _Group {
  const _Group(this.title, this.tools);
  final String title;
  final List<_Tool> tools;
}

class _TabDef {
  const _TabDef(this.title, this.groups);
  final String title;
  final List<_Group> groups;
}

/// شريط أدوات تحرير نص السؤال: تبويبات (الرئيسية، تنسيق، إدراج، رياضيات، جدول، صورة)
/// بمجموعات بعناوين، يُطوى بزر السهم، ويُظلَّل فيه التنسيق النشط عند المؤشر.
class QuestionRibbon extends StatefulWidget {
  const QuestionRibbon({
    super.key,
    required this.api,
    required this.onPickImages,
    required this.onMessage,
  });

  final EngineApi api;

  /// يختار صوراً أصلياً ويدرجها؛ grid = شبكة صور.
  final Future<void> Function(bool grid) onPickImages;
  final void Function(String message) onMessage;

  @override
  State<QuestionRibbon> createState() => _QuestionRibbonState();
}

class _QuestionRibbonState extends State<QuestionRibbon> {
  int _tab = 0;
  bool _open = true;
  Map<String, bool> _fmt = const {};
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!_open || !mounted) return;
    final r = await widget.api.formatState();
    if (!mounted || r == null) return;
    final m = {for (final e in r.entries) e.key: e.value == true};
    if (!mapEquals(m, _fmt)) setState(() => _fmt = m);
  }

  // ------------------------------------------------------------------ مساعدات

  Future<void> _cmd(String c) => widget.api.cmd(c);
  Future<void> _val(String c, String v) => widget.api.cmdVal(c, v);
  Future<void> _html(String h) => widget.api.insertHtml(h);

  Future<bool> _need(String what) async {
    final sel = await widget.api.selection();
    final has = sel != null && sel[what] == true;
    if (!has) {
      widget.onMessage(what == 'img'
          ? 'اضغط على الصورة داخل نص السؤال أولاً'
          : 'اضغط داخل خلية الجدول أولاً');
    }
    return has;
  }

  Future<void> _onImg(Future<void> Function() op) async {
    if (await _need('img')) await op();
  }

  Future<void> _onTable(Future<void> Function() op) async {
    if (await _need('table')) await op();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final t = d?.text;
    if (t == null || t.isEmpty) return widget.onMessage('الحافظة فارغة');
    await _html(esc(t).replaceAll('\n', '<br>'));
  }

  // ---------------------------------------------------------------- التبويبات

  List<_TabDef> _tabs() {
    final api = widget.api;
    MathBuilder mb(String title) => kMathBuilders.firstWhere((b) => b.title == title);
    const quick = [
      '±', '×', '÷', '≠', '≈', '≤', '≥', 'π', '∞', '°', '∠', '⊥', '∥', '△', '∈', '∪', '∩', '∴', '⇒', '٪',
    ];
    const box = 'border:1.5px solid #000;padding:8px;margin:6px 0;min-height:34px';
    return [
      _TabDef('الرئيسية', [
        _Group('التراجع', [
          _Tool('تراجع', api.undo, icon: Icons.undo),
          _Tool('إعادة', api.redo, icon: Icons.redo),
        ]),
        _Group('الحافظة', [
          _Tool('لصق', _paste, icon: Icons.content_paste),
          _Tool('نسخ', () => _cmd('copy'), icon: Icons.copy_outlined),
          _Tool('قص', () => _cmd('cut'), icon: Icons.content_cut),
          _Tool('تحديد الكل', () => _cmd('selectAll'), icon: Icons.select_all),
          _Tool('حذف', () => _cmd('delete'), icon: Icons.backspace_outlined),
        ]),
        _Group('الخط', [
          _Tool('عريض', () => _cmd('bold'), icon: Icons.format_bold, stateKey: 'bold'),
          _Tool('مائل', () => _cmd('italic'), icon: Icons.format_italic, stateKey: 'italic'),
          _Tool('تسطير', () => _cmd('underline'),
              icon: Icons.format_underlined, stateKey: 'underline'),
          _Tool('شطب', () => _cmd('strikeThrough'),
              icon: Icons.strikethrough_s, stateKey: 'strike'),
          _Tool('لون النص', () => _colors(context), icon: Icons.format_color_text),
          _Tool('تمييز', () => _val('hiliteColor', '#fff176'), icon: Icons.border_color),
          _Tool('مسح التنسيق', () => _cmd('removeFormat'), icon: Icons.format_clear),
        ]),
      ]),
      _TabDef('تنسيق', [
        _Group('المحاذاة', [
          _Tool('يمين', () => _cmd('justifyRight'),
              icon: Icons.format_align_right, stateKey: 'right'),
          _Tool('وسط', () => _cmd('justifyCenter'),
              icon: Icons.format_align_center, stateKey: 'center'),
          _Tool('يسار', () => _cmd('justifyLeft'),
              icon: Icons.format_align_left, stateKey: 'left'),
          _Tool('ضبط', () => _cmd('justifyFull'),
              icon: Icons.format_align_justify, stateKey: 'full'),
        ]),
        _Group('القوائم', [
          _Tool('ترقيم', () => _cmd('insertOrderedList'),
              icon: Icons.format_list_numbered, stateKey: 'ol'),
          _Tool('نقاط', () => _cmd('insertUnorderedList'),
              icon: Icons.format_list_bulleted, stateKey: 'ul'),
          _Tool('زيادة مسافة', () => _cmd('indent'), icon: Icons.format_indent_increase),
          _Tool('إنقاص مسافة', () => _cmd('outdent'), icon: Icons.format_indent_decrease),
        ]),
        _Group('حجم الخط', [
          _Tool('صغير', () => _val('fontSize', '2'), glyph: 'أ'),
          _Tool('عادي', () => _val('fontSize', '3'), glyph: 'أ'),
          _Tool('كبير', () => _val('fontSize', '5'), glyph: 'أ'),
          _Tool('ضخم', () => _val('fontSize', '6'), glyph: 'أ'),
        ]),
      ]),
      _TabDef('إدراج', [
        _Group('الإجابة', [
          _Tool('سطر إجابة', api.answerLine, icon: Icons.horizontal_rule),
          _Tool('نقاط تعبئة', () => _html('..................................&nbsp;'),
              icon: Icons.more_horiz),
          _Tool('قوسان', () => _html('( &nbsp;&nbsp;&nbsp; )&nbsp;'), glyph: '( )'),
          _Tool('مربع اختيار', () => _html('&#9744;&nbsp;'), glyph: '☐'),
          _Tool('صح', () => _html('&#10003;&nbsp;'), glyph: '✓'),
          _Tool('خطأ', () => _html('&#10007;&nbsp;'), glyph: '✗'),
        ]),
        _Group('عناصر', [
          _Tool('مستطيل', () => _html('<div style="$box">&nbsp;</div>'),
              icon: Icons.crop_square),
          _Tool(
              'دائرة',
              () => _html('<span style="display:inline-block;width:30px;height:30px;'
                  'border:1.5px solid #000;border-radius:50%;vertical-align:middle;'
                  'text-align:center;line-height:28px">&nbsp;</span>&nbsp;'),
              icon: Icons.circle_outlined),
          _Tool(
              'خط أفقي',
              () => _html('<hr style="border:0;border-top:1.5px solid #000;margin:8px 0">'),
              icon: Icons.remove),
        ]),
        _Group('وسائط', [
          _Tool('جدول', () => _tableDialog(context), icon: Icons.table_chart_outlined),
          _Tool('صورة', () => widget.onPickImages(false), icon: Icons.image_outlined),
          _Tool('شبكة صور', () => widget.onPickImages(true), icon: Icons.grid_view),
        ]),
      ]),
      _TabDef('رياضيات', [
        _Group('المكتبة', [
          _Tool('الرموز', () => showMathSheet(context, api), glyph: 'Σ'),
          _Tool('القوالب', () => showMathSheet(context, api, mode: MathMode.builders),
              icon: Icons.calculate_outlined),
          _Tool('القوانين', () => showMathSheet(context, api, mode: MathMode.formulas),
              icon: Icons.menu_book_outlined),
        ]),
        _Group('قوالب سريعة', [
          _Tool('كسر', () => runMathBuilder(context, api, mb('كسر')), glyph: '½'),
          _Tool('جذر', () => runMathBuilder(context, api, mb('جذر تربيعي')), glyph: '√'),
          _Tool('أس', () => runMathBuilder(context, api, mb('أس')), glyph: 'س²'),
          _Tool('دليل', () => runMathBuilder(context, api, mb('دليل سفلي')), glyph: 'س₁'),
          _Tool('مجموع', () => runMathBuilder(context, api, mb('مجموع (∑) بحدود')),
              glyph: '∑'),
          _Tool('تكامل', () => runMathBuilder(context, api, mb('تكامل محدد')), glyph: '∫'),
          _Tool('نهاية', () => runMathBuilder(context, api, mb('نهاية')), glyph: 'نهـا'),
        ]),
        _Group('رموز سريعة', [
          for (final s in quick)
            _Tool(kMathNames[s] ?? s, () => _html(esc(s)), glyph: s),
        ]),
      ]),
      _TabDef('جدول', [
        _Group('إنشاء', [
          _Tool('إدراج جدول', () => _tableDialog(context), icon: Icons.table_chart_outlined),
        ]),
        _Group('الصفوف والأعمدة', [
          _Tool('إضافة صف', () => _onTable(() => api.tableOp('addRow')),
              icon: Icons.add_box_outlined),
          _Tool('حذف صف', () => _onTable(() => api.tableOp('delRow')),
              icon: Icons.indeterminate_check_box_outlined),
          _Tool('إضافة عمود', () => _onTable(() => api.tableOp('addCol')),
              icon: Icons.view_column_outlined),
          _Tool('حذف عمود', () => _onTable(() => api.tableOp('delCol')),
              icon: Icons.remove_circle_outline),
        ]),
        _Group('الحدود', [
          _Tool('إظهار الحدود', () => _onTable(() => api.tableBorder('solid')),
              icon: Icons.border_all),
          _Tool('إخفاء الحدود', () => _onTable(() => api.tableBorder('borderless')),
              icon: Icons.border_clear),
        ]),
        _Group('حذف', [
          _Tool('حذف الجدول', () => _onTable(() => api.tableOp('delTable')),
              icon: Icons.delete_outline),
        ]),
      ]),
      _TabDef('صورة', [
        _Group('إدراج', [
          _Tool('صورة', () => widget.onPickImages(false), icon: Icons.image_outlined),
          _Tool('شبكة صور', () => widget.onPickImages(true), icon: Icons.grid_view),
        ]),
        _Group('الالتفاف', [
          _Tool('توسيط', () => _onImg(() => api.imgWrap('wrap-center')),
              icon: Icons.format_align_center),
          _Tool('بجانب النص', () => _onImg(() => api.imgWrap('wrap-inline')),
              icon: Icons.wrap_text),
          _Tool('مشدود يمين', () => _onImg(() => api.imgWrap('wrap-tight-right')),
              icon: Icons.align_horizontal_right),
          _Tool('مشدود يسار', () => _onImg(() => api.imgWrap('wrap-tight-left')),
              icon: Icons.align_horizontal_left),
          _Tool('أمام النص', () => _onImg(() => api.imgWrap('wrap-front')),
              icon: Icons.layers_outlined),
        ]),
        _Group('الحجم', [
          for (final p in const [20, 35, 50, 75, 100])
            _Tool('$p%', () => _onImg(() => api.imgSize('$p%')), glyph: '$p'),
        ]),
        _Group('الإطار', [
          _Tool('بدون', () => _onImg(() => api.imgShape('img-borderless')), glyph: '∅'),
          _Tool('مربع', () => _onImg(() => api.imgShape('img-square')), glyph: '□'),
          _Tool('حواف دائرية', () => _onImg(() => api.imgShape('img-rounded')), glyph: '▢'),
          _Tool('دائري', () => _onImg(() => api.imgShape('img-circle')), glyph: '○'),
          _Tool('مزدوج', () => _onImg(() => api.imgShape('img-double')), glyph: '▣'),
          _Tool('متقطع', () => _onImg(() => api.imgShape('img-dashed')), glyph: '┅'),
        ]),
        _Group('الأسهم', [
          _Tool('إضافة سهم', () => _onImg(() => _arrowDialog(context)),
              icon: Icons.north_east),
          _Tool('مسح الأسهم', () => _onImg(api.imgClearArrows), icon: Icons.clear_all),
        ]),
        _Group('حذف', [
          _Tool('حذف الصورة', () => _onImg(api.imgDelete), icon: Icons.delete_outline),
        ]),
      ]),
    ];
  }

  // -------------------------------------------------------------------- البناء

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs();
    final tab = tabs[_tab];
    return Material(
      color: AppColors.navBg,
      elevation: 10,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.bottomCenter,
              child: _open
                  ? SizedBox(height: 104, child: _panel(tab))
                  : const SizedBox(width: double.infinity),
            ),
            const Divider(height: 1, color: AppColors.border),
            SizedBox(
              height: 46,
              child: Row(
                children: [
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      itemCount: tabs.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 6),
                      itemBuilder: (_, i) {
                        final sel = i == _tab;
                        return GestureDetector(
                          onTap: () => setState(() {
                            _tab = i;
                            _open = true;
                          }),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: sel ? AppColors.pink : Colors.transparent,
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              tabs[i].title,
                              style: TextStyle(
                                fontSize: 14,
                                color: sel ? AppColors.maroon : AppColors.muted,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: _open ? 'طي الأدوات' : 'إظهار الأدوات',
                    onPressed: () => setState(() => _open = !_open),
                    icon: Icon(
                      _open ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                      color: AppColors.maroon,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel(_TabDef tab) {
    final children = <Widget>[];
    for (var g = 0; g < tab.groups.length; g++) {
      final group = tab.groups[g];
      if (g > 0) {
        children.add(const VerticalDivider(
            width: 20, indent: 14, endIndent: 26, color: AppColors.border));
      }
      children.add(Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final t in group.tools) _tile(t),
          ]),
          const SizedBox(height: 4),
          Text(group.title,
              style: const TextStyle(fontSize: 10.5, color: AppColors.muted)),
        ],
      ));
    }
    return ListView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      children: children,
    );
  }

  Widget _tile(_Tool t) {
    final active = t.stateKey != null && (_fmt[t.stateKey] ?? false);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        await t.run();
        _poll();
      },
      child: SizedBox(
        width: 64,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? AppColors.pink : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: active ? AppColors.maroon : AppColors.border,
                  width: active ? 1.5 : 1,
                ),
              ),
              child: t.glyph != null
                  ? Text(t.glyph!,
                      style: const TextStyle(fontSize: 19, color: AppColors.maroon))
                  : Icon(t.icon, size: 22, color: AppColors.maroon),
            ),
            const SizedBox(height: 3),
            Text(t.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11, color: AppColors.muted)),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------- لوحات وحوارات

  void _colors(BuildContext context) {
    const palette = [
      '#000000', '#dc2626', '#1d4ed8', '#166534', '#ea580c', '#7c3aed', '#8b4a5e', '#6b7280',
    ];
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: [
              for (final c in palette)
                GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    widget.api.color(c);
                  },
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.border, width: 1.5),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _tableDialog(BuildContext context) async {
    var rows = 2, cols = 2;
    var style = 'borderless-table';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إدراج جدول'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _stepper('الصفوف', rows, 1, 20, (v) => setS(() => rows = v)),
              _stepper('الأعمدة', cols, 1, 10, (v) => setS(() => cols = v)),
              DropdownButton<String>(
                value: style,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'normal', child: Text('بحدود واضحة')),
                  DropdownMenuItem(
                      value: 'borderless-table', child: Text('بدون حدود (لترتيب الصور)')),
                  DropdownMenuItem(value: 'dashed-table', child: Text('حدود متقطعة')),
                ],
                onChanged: (v) => setS(() => style = v ?? style),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('إدراج')),
          ],
        ),
      ),
    );
    if (ok == true) await widget.api.insertTable(rows, cols, style);
  }

  Widget _stepper(String label, int v, int min, int max, void Function(int) set) => Row(
        children: [
          Expanded(child: Text(label)),
          IconButton(
              onPressed: v > min ? () => set(v - 1) : null,
              icon: const Icon(Icons.remove_circle_outline)),
          Text('$v', style: const TextStyle(fontSize: 18)),
          IconButton(
              onPressed: v < max ? () => set(v + 1) : null,
              icon: const Icon(Icons.add_circle_outline)),
        ],
      );

  Future<void> _arrowDialog(BuildContext context) async {
    var dir = '⬅️';
    var color = '#dc2626';
    double x = 45, y = 45;
    final label = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('إضافة سهم على الصورة'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButton<String>(
                  value: dir,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(value: '⬅️', child: Text('⬅️ يسار')),
                    DropdownMenuItem(value: '➡️', child: Text('➡️ يمين')),
                    DropdownMenuItem(value: '⬆️', child: Text('⬆️ أعلى')),
                    DropdownMenuItem(value: '⬇️', child: Text('⬇️ أسفل')),
                    DropdownMenuItem(value: '↖️', child: Text('↖️ أعلى يسار')),
                    DropdownMenuItem(value: '↗️', child: Text('↗️ أعلى يمين')),
                    DropdownMenuItem(value: '↙️', child: Text('↙️ أسفل يسار')),
                    DropdownMenuItem(value: '↘️', child: Text('↘️ أسفل يمين')),
                  ],
                  onChanged: (v) => setS(() => dir = v ?? dir),
                ),
                Wrap(spacing: 10, children: [
                  for (final c in const ['#dc2626', '#1d4ed8', '#166534', '#000000'])
                    GestureDetector(
                      onTap: () => setS(() => color = c),
                      child: Container(
                        width: 34,
                        height: 34,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: Color(int.parse('FF${c.substring(1)}', radix: 16)),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: c == color ? AppColors.maroon : AppColors.border,
                              width: c == color ? 3 : 1),
                        ),
                      ),
                    ),
                ]),
                Text('الموضع الأفقي: ${x.round()}%'),
                Slider(value: x, min: 5, max: 90, onChanged: (v) => setS(() => x = v)),
                Text('الموضع الرأسي: ${y.round()}%'),
                Slider(value: y, min: 5, max: 90, onChanged: (v) => setS(() => y = v)),
                TextField(
                  controller: label,
                  decoration: const InputDecoration(labelText: 'تسمية (اختياري)'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true), child: const Text('إضافة')),
          ],
        ),
      ),
    );
    if (ok == true) {
      await widget.api.imgArrow(dir, color, x.round(), y.round(), label.text.trim());
    }
  }
}
