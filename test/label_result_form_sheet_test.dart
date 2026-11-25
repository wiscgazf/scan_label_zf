import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_models.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_page.dart';

void main() {
  testWidgets('物料编码与名称为空时红色警告，输入后恢复', (tester) async {
    // 大窗口确保列表内所有字段都被构建。
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const result = LabelScanResult(key: 'RVendor#demo', fields: {});
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: LabelResultFormSheet(result: result)),
      ),
    );
    await tester.pumpAndSettle();

    // 仅物料编码与名称两个字段出现警告。
    expect(find.byIcon(Icons.error_outline), findsNWidgets(2));
    expect(find.text('未识别到物料编码，请手动填写'), findsOneWidget);
    expect(find.text('未识别到名称，请手动填写'), findsOneWidget);

    // 手动填入物料编码后，其警告消失，名称警告保留。
    await tester.enterText(
      find.widgetWithText(TextFormField, '请输入物料编码'),
      '03-XHX-254350-XX-0001',
    );
    await tester.pump();

    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text('未识别到物料编码，请手动填写'), findsNothing);
    expect(find.text('未识别到名称，请手动填写'), findsOneWidget);
  });

  testWidgets('字段均有识别值时不显示警告', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final result = LabelScanResult(
      key: 'RVendor#demo',
      fields: {
        for (final key in LabelFieldKey.values) key: '值',
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: LabelResultFormSheet(result: result))),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.error_outline), findsNothing);
  });
}
