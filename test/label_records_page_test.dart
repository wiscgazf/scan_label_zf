import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/pages/label_scan/label_records.dart';
import 'package:scan_label_zf/pages/label_scan/label_records_page.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_models.dart';

/// 内存实现：与真实 store 相同的筛选行为，但不走 isolate/IO，
/// 让 widget 测试可用普通 pump 驱动。真实 SQL 由 store 测试覆盖。
class FakeLabelRecordStore extends LabelRecordStore {
  FakeLabelRecordStore(this._data);

  final List<LabelRecord> _data;

  @override
  Future<List<LabelRecord>> query({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
  }) async {
    final result = _data.where((r) {
      final day = DateTime(
        r.createdAt.year,
        r.createdAt.month,
        r.createdAt.day,
      );
      if (startDate != null) {
        final start = DateTime(
          startDate.year,
          startDate.month,
          startDate.day,
        );
        if (day.isBefore(start)) return false;
      }
      if (endDate != null) {
        final end = DateTime(endDate.year, endDate.month, endDate.day);
        if (day.isAfter(end)) return false;
      }
      if (keyword.isNotEmpty && !r.name.contains(keyword)) return false;
      return true;
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  @override
  Future<List<LabelRecord>> queryPage({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
    int limit = 30,
    int offset = 0,
  }) async {
    final all = await query(
      startDate: startDate,
      endDate: endDate,
      keyword: keyword,
    );
    return all.skip(offset).take(limit).toList();
  }

  @override
  Future<List<DuplicateGroup>> queryDuplicateGroups({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
    int limit = 10,
    int offset = 0,
  }) async {
    // query 已按录入时间倒序，按首次出现顺序建组即为组按最新时间倒序。
    final all = await query(
      startDate: startDate,
      endDate: endDate,
      keyword: keyword,
    );
    final byCode = <String, List<LabelRecord>>{};
    for (final record in all) {
      if (record.materialCode.isEmpty) continue;
      byCode.putIfAbsent(record.materialCode, () => []).add(record);
    }
    final groups = [
      for (final entry in byCode.entries)
        if (entry.value.length > 1)
          DuplicateGroup(materialCode: entry.key, records: entry.value),
    ];
    return groups.skip(offset).take(limit).toList();
  }

  /// 直接写入数据但不发通知，模拟“外部新增记录”以验证下拉刷新。
  void insertSilently(LabelRecord record) => _data.add(record);

  @override
  Future<void> delete(String id) async {
    _data.removeWhere((r) => r.id == id);
    notifyListeners();
  }
}

void main() {
  late FakeLabelRecordStore store;

  setUp(() {
    store = FakeLabelRecordStore([
      LabelRecord(
        id: '1',
        key: 'RVendor#1',
        createdAt: DateTime(2026, 11, 25, 9),
        fields: {
          LabelFieldKey.name: '信号线插排',
          LabelFieldKey.materialCode: '03-XHX-254350-XX-0001',
        },
      ),
      LabelRecord(
        id: '2',
        key: 'RVendor#2',
        createdAt: DateTime(2026, 11, 25, 10),
        fields: {
          LabelFieldKey.name: '电源线',
          LabelFieldKey.materialCode: '03-DYX-000001',
        },
      ),
    ]);
  });

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: LabelRecordsPage(store: store)));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('列表展示名称、编码、录入时间，支持名称筛选', (tester) async {
    await pumpPage(tester);

    expect(find.text('信号线插排'), findsOneWidget);
    expect(find.text('电源线'), findsOneWidget);
    expect(find.text('编码：03-XHX-254350-XX-0001'), findsOneWidget);
    expect(find.text('2026-11-25 09:00'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '搜索物料名称'),
      '信号线',
    );
    // 搜索输入有 300ms 防抖。
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
    await tester.pump();

    expect(find.text('信号线插排'), findsOneWidget);
    expect(find.text('电源线'), findsNothing);
  });

  testWidgets('删除记录需确认，确认后从列表移除', (tester) async {
    await pumpPage(tester);

    // 列表按录入时间倒序，第一条是 10:00 的“电源线”。
    await tester.tap(find.byIcon(Icons.delete_outline).first);
    await tester.pumpAndSettle();
    expect(find.text('删除记录'), findsOneWidget);
    expect(find.text('确定删除「电源线」这条标签记录吗？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('电源线'), findsNothing);
    expect(find.text('信号线插排'), findsOneWidget);
  });

  testWidgets('日期区间联动选择后筛选生效，可一键清除', (tester) async {
    await pumpPage(tester);
    expect(find.text('信号线插排'), findsOneWidget);
    expect(find.text('电源线'), findsOneWidget);

    // 打开区间选择器，选择 15 日当天作为起止区间。
    await tester.tap(find.text('日期'));
    await tester.pumpAndSettle();
    expect(find.text('选择录入日期区间'), findsOneWidget);

    await tester.tap(find.text('15').first);
    await tester.pump();
    await tester.tap(find.text('15').first);
    await tester.pump();
    await tester.tap(find.text('确定'));
    await tester.pumpAndSettle();

    // 测试数据固定在 2026-11-25，不落在任意年月的 15 日单日区间内。
    expect(find.text('没有符合条件的记录'), findsOneWidget);
    expect(find.text('信号线插排'), findsNothing);

    // 点区间按钮上的清除图标，恢复完整列表。
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('日期'), findsOneWidget);
    expect(find.text('信号线插排'), findsOneWidget);
    expect(find.text('电源线'), findsOneWidget);
  });

  testWidgets('分页加载：首屏 30 条，滚动到底部自动加载剩余并提示没有更多', (
    tester,
  ) async {
    final base = DateTime(2026, 11, 25, 8);
    store = FakeLabelRecordStore([
      for (var i = 1; i <= 35; i++)
        LabelRecord(
          id: '$i',
          key: 'RVendor#$i',
          createdAt: base.add(Duration(minutes: i)),
          fields: {
            LabelFieldKey.name: '物料$i',
            LabelFieldKey.materialCode: 'CODE-$i',
          },
        ),
    ]);
    await pumpPage(tester);

    // 首屏只有第一页（最新 30 条），最早的物料 1 尚未加载。
    expect(find.text('物料35'), findsOneWidget);
    expect(find.text('物料1'), findsNothing);

    // 持续向底部滚动，触发上拉加载更多，直到最早记录出现。
    final scrollable = find.descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byType(Scrollable),
    );
    for (var i = 0; i < 10; i++) {
      await tester.drag(scrollable, const Offset(0, -800));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('物料1').evaluate().isNotEmpty) break;
    }
    await tester.pump();
    await tester.pump();

    expect(find.text('物料1'), findsOneWidget);
    expect(find.text('没有更多了'), findsOneWidget);
  });

  testWidgets('下拉刷新后能看到外部新增的记录', (tester) async {
    await pumpPage(tester);
    expect(find.text('信号线插排'), findsOneWidget);

    store.insertSilently(
      LabelRecord(
        id: '99',
        key: 'RVendor#99',
        createdAt: DateTime(2026, 11, 25, 12),
        fields: {
          LabelFieldKey.name: '刷新后的物料',
          LabelFieldKey.materialCode: 'CODE-99',
        },
      ),
    );
    // 未刷新前新记录不出现。
    await tester.pump();
    expect(find.text('刷新后的物料'), findsNothing);

    // 手动下拉超过刷新阈值后松手，触发 RefreshIndicator。
    final listView = find.descendant(
      of: find.byType(RefreshIndicator),
      matching: find.byType(ListView),
    );
    final gesture = await tester.startGesture(tester.getCenter(listView));
    // 下拉 overscroll 有阻尼衰减，拖足够距离确保进入 armed 状态。
    for (var i = 0; i < 20; i++) {
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('刷新后的物料'), findsOneWidget);
  });

  testWidgets('重复标签 Tab：编码一致分组展示，唯一编码与空编码不出现', (
    tester,
  ) async {
    LabelRecord record(String id, String name, String code, int minute) {
      return LabelRecord(
        id: id,
        key: 'RVendor#$id',
        createdAt: DateTime(2026, 11, 25, 8, minute),
        fields: {LabelFieldKey.name: name, LabelFieldKey.materialCode: code},
      );
    }

    store = FakeLabelRecordStore([
      record('1', '重复物料一', 'DUP-CODE', 1),
      record('2', '重复物料二', 'DUP-CODE', 2),
      record('3', '唯一物料', 'UNIQUE-CODE', 3),
      record('4', '空编码物料一', '', 4),
      record('5', '空编码物料二', '', 5),
    ]);
    await pumpPage(tester);

    await tester.tap(find.text('重复标签'));
    // 第一帧启动切换动画，第二帧推进完成，再泵两次完成数据加载。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.pump();

    expect(find.text('重复 2 次'), findsOneWidget);
    expect(find.text('DUP-CODE'), findsOneWidget);
    expect(find.text('重复物料一'), findsOneWidget);
    expect(find.text('重复物料二'), findsOneWidget);
    // 唯一编码与空编码均不进入重复列表。
    expect(find.text('唯一物料'), findsNothing);
    expect(find.text('空编码物料一'), findsNothing);
  });
}
