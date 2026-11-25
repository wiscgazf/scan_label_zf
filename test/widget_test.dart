import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/main.dart';

void main() {
  testWidgets('首页展示标签扫一扫入口', (tester) async {
    await tester.pumpWidget(const MyApp());
    expect(find.text('标签扫一扫'), findsOneWidget);
    expect(find.text('扫一扫'), findsOneWidget);
    expect(find.text('选择文件识别'), findsOneWidget);
  });
}
