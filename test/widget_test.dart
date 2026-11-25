import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/l10n/app_localizations.dart';
import 'package:scan_label_zf/main.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_page.dart';

Future<void> pumpHomeTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() => appLocaleController.setLocale(const Locale('zh')));

  testWidgets('首页默认展示中文入口和固定语言图标', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(appLocaleController.locale, const Locale('zh'));
    expect(find.text('标签扫一扫'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('选择文件识别'), findsOneWidget);
    expect(find.byTooltip('管理'), findsOneWidget);
    expect(find.byTooltip('语言'), findsOneWidget);
    expect(find.text('SCAN / OCR'), findsOneWidget);
    expect(find.text('离线就绪'), findsOneWidget);
    final languageIcon = find.descendant(
      of: find.byType(AppBar),
      matching: find.byIcon(Icons.translate),
    );
    expect(languageIcon, findsOneWidget);
    expect(tester.widget<Icon>(languageIcon).size, 20);

    final indicatorRect = tester.getRect(
      find.byKey(const ValueKey('home-offline-indicator')),
    );
    final statusRect = tester.getRect(find.text('离线就绪'));
    expect(statusRect.left - indicatorRect.right, 6);
    expect(indicatorRect.center.dy, moreOrLessEquals(statusRect.center.dy));
  });

  testWidgets('底部语言弹层可切换英文并返回中文', (tester) async {
    await tester.pumpWidget(const MyApp());
    await pumpHomeTransition(tester);

    await tester.tap(find.byTooltip('语言'));
    await pumpHomeTransition(tester);
    expect(find.text('选择语言'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);
    expect(find.text('中文'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byType(ListTile),
      ),
      findsNWidgets(2),
    );
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.translate),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('English'));
    await pumpHomeTransition(tester);
    expect(appLocaleController.locale, const Locale('en'));
    expect(find.text('Label Scan'), findsOneWidget);
    expect(find.byTooltip('Manage'), findsOneWidget);
    expect(find.text('Recognize from file'), findsOneWidget);

    await tester.tap(find.byTooltip('Language'));
    await pumpHomeTransition(tester);
    expect(find.text('Select language'), findsOneWidget);
    await tester.tap(find.text('中文'));
    await pumpHomeTransition(tester);
    expect(appLocaleController.locale, const Locale('zh'));
    expect(find.text('标签扫一扫'), findsOneWidget);
  });

  testWidgets('扫描线随时间在预览区域内往返移动', (tester) async {
    await tester.pumpWidget(const MyApp());
    final preview = find.byKey(const ValueKey('home-scan-preview'));

    double scanProgress() {
      final painter = tester.widget<CustomPaint>(preview).painter;
      return (painter! as HomeScanPainter).progress;
    }

    final initialProgress = scanProgress();
    await tester.pump(const Duration(milliseconds: 400));
    final forwardProgress = scanProgress();
    await tester.pump(const Duration(milliseconds: 2500));
    final reverseProgress = scanProgress();

    expect(forwardProgress, greaterThan(initialProgress));
    expect(reverseProgress, lessThan(forwardProgress));
    expect(tester.takeException(), isNull);
  });

  for (final size in const [Size(360, 800), Size(390, 844)]) {
    testWidgets('首页在 ${size.width.toInt()} 宽手机下无溢出且主操作完整', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      appLocaleController.setLocale(const Locale('en'));

      await tester.pumpWidget(const MyApp());
      await pumpHomeTransition(tester);

      expect(tester.takeException(), isNull);
      final scanRect = tester.getRect(
        find.widgetWithText(FilledButton, 'Scan'),
      );
      final fileRect = tester.getRect(
        find.widgetWithText(OutlinedButton, 'Recognize from file'),
      );
      expect(scanRect.height, 60);
      expect(fileRect.height, 56);
      for (final rect in [scanRect, fileRect]) {
        expect(rect.left, greaterThanOrEqualTo(0));
        expect(rect.right, lessThanOrEqualTo(size.width));
        expect(rect.bottom, lessThanOrEqualTo(size.height));
      }
    });
  }

  testWidgets('扫描确认提示距底部约 30% 并在两秒后自动消失', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showLabelScanToast(context, '标签字段已确认'),
              child: const Text('触发提示'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('触发提示'));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(tester.takeException(), isNull);
    expect(find.text('标签字段已确认'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    final toastRect = tester.getRect(
      find
          .ancestor(of: find.text('标签字段已确认'), matching: find.byType(Material))
          .first,
    );
    expect(toastRect.bottom, moreOrLessEquals(844 * 0.7, epsilon: 0.001));

    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.text('标签字段已确认'), findsNothing);
  });
}
