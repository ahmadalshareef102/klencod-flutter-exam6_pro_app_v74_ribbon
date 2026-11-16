import 'package:exam6_pro_app/engine_api.dart';
import 'package:exam6_pro_app/screens/question_tools.dart';
import 'package:exam6_pro_app/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('الشريط يعرض التبويبات والمجموعات ويتنقل بينها', (tester) async {
    final msgs = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: buildTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              QuestionRibbon(
                api: EngineApi(() => null),
                onPickImages: (_) async {},
                onMessage: msgs.add,
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    for (final t in ['الرئيسية', 'تنسيق', 'إدراج', 'رياضيات', 'جدول', 'صورة']) {
      expect(find.text(t), findsWidgets, reason: t);
    }
    expect(find.text('عريض'), findsOneWidget);

    await tester.tap(find.text('رياضيات'));
    await tester.pump();
    expect(find.text('الرموز'), findsOneWidget);
    expect(find.text('قوالب سريعة'), findsOneWidget);

    await tester.tap(find.text('جدول'));
    await tester.pump();
    expect(find.text('إدراج جدول'), findsOneWidget);

    // طي الأدوات: تبقى التبويبات وتختفي الأدوات
    await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
    await tester.pumpAndSettle();
    expect(find.text('إدراج جدول'), findsNothing);
    expect(find.text('جدول'), findsWidgets);

    // تفريغ الشجرة لإيقاف المؤقت الدوري
    await tester.pumpWidget(const SizedBox());
  });
}
