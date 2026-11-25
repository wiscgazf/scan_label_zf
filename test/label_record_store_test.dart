import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/pages/label_scan/label_records.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_models.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late LabelRecordStore store;

  setUp(() {
    store = LabelRecordStore(dbPath: inMemoryDatabasePath);
  });

  LabelRecord record(String id, String name, DateTime createdAt) {
    return LabelRecord(
      id: id,
      key: 'RVendor#$id',
      companyName: '深圳市瑞能电源科技有限公司',
      createdAt: createdAt,
      fields: {
        LabelFieldKey.name: name,
        LabelFieldKey.materialCode: 'CODE-$id',
      },
    );
  }

  test('增删改查与字段序列化', () async {
    await store.add(record('1', '信号线插排', DateTime(2026, 11, 25, 10, 30)));

    var all = await store.query();
    expect(all.single.name, '信号线插排');
    expect(all.single.materialCode, 'CODE-1');
    expect(all.single.key, 'RVendor#1');
    expect(all.single.companyName, '深圳市瑞能电源科技有限公司');
    expect(all.single.createdAt, DateTime(2026, 11, 25, 10, 30));
    expect(all.single.toScanResult().fields[LabelFieldKey.name], '信号线插排');

    await store.update(record('1', '改名后的物料', DateTime(2026, 11, 25, 10, 30)));
    all = await store.query();
    expect(all.single.name, '改名后的物料');

    await store.delete('1');
    expect(await store.query(), isEmpty);
  });

  test('按日期、名称与编码筛选，录入时间倒序', () async {
    await store.add(record('1', '信号线插排', DateTime(2026, 11, 25, 9)));
    await store.add(record('2', '电源线', DateTime(2026, 11, 25, 10)));
    await store.add(record('3', '信号线端子', DateTime(2026, 11, 24, 10)));

    final all = await store.query();
    expect(all.map((r) => r.id), ['2', '1', '3']);

    final today = await store.query(startDate: DateTime(2026, 11, 25));
    expect(today.map((r) => r.id), ['2', '1']);

    final byName = await store.query(keyword: '信号线');
    expect(byName.map((r) => r.id).toSet(), {'1', '3'});

    final byCode = await store.query(keyword: 'CODE-2');
    expect(byCode.single.id, '2');

    final both = await store.query(
      startDate: DateTime(2026, 11, 25),
      keyword: '信号线',
    );
    expect(both.single.id, '1');

    // 编码匹配的记录仍须落在指定日期范围内。
    final codeAndDate = await store.query(
      startDate: DateTime(2026, 11, 25),
      endDate: DateTime(2026, 11, 25),
      keyword: 'CODE-2',
    );
    expect(codeAndDate.single.id, '2');
    expect(
      await store.query(startDate: DateTime(2026, 11, 26), keyword: 'CODE-2'),
      isEmpty,
    );

    expect(await store.query(keyword: '不存在的物料'), isEmpty);
    expect(await store.query(startDate: DateTime(2027, 1, 1)), isEmpty);
  });

  test('日期区间筛选：起止均可留空，含起止当天', () async {
    await store.add(record('1', '信号线插排', DateTime(2026, 11, 25, 9)));
    await store.add(record('2', '电源线', DateTime(2026, 11, 25, 10)));
    await store.add(record('3', '信号线端子', DateTime(2026, 11, 24, 10)));

    // 完整区间：两天都包含。
    final range = await store.query(
      startDate: DateTime(2026, 11, 24),
      endDate: DateTime(2026, 11, 25),
    );
    expect(range.map((r) => r.id), ['2', '1', '3']);

    // 起止同一天等价于按单日筛选。
    final singleDay = await store.query(
      startDate: DateTime(2026, 11, 24),
      endDate: DateTime(2026, 11, 24),
    );
    expect(singleDay.single.id, '3');

    // 仅结束日期：包含结束当天及之前。
    final untilOnly = await store.query(endDate: DateTime(2026, 11, 24));
    expect(untilOnly.single.id, '3');

    // 仅开始日期：包含开始当天及之后。
    final fromOnly = await store.query(startDate: DateTime(2026, 11, 25));
    expect(fromOnly.map((r) => r.id), ['2', '1']);
  });

  test('日期区间边界：开始当天 0 点与结束当天 23:59:59.999 均包含', () async {
    await store.add(record('1', '零点物料', DateTime(2026, 11, 24)));
    await store.add(
      record('2', '深夜物料', DateTime(2026, 11, 25, 23, 59, 59, 999)),
    );
    await store.add(record('3', '次日物料', DateTime(2026, 11, 26)));

    final range = await store.query(
      startDate: DateTime(2026, 11, 24),
      endDate: DateTime(2026, 11, 25),
    );
    expect(range.map((r) => r.id), ['2', '1']);
  });

  test('queryPage 分页：按时间倒序逐页返回，越界返回空', () async {
    for (var i = 1; i <= 5; i++) {
      await store.add(record('$i', '信号线插排$i', DateTime(2026, 11, 25, i)));
    }

    final page1 = await store.queryPage(limit: 2);
    expect(page1.map((r) => r.id), ['5', '4']);
    final page2 = await store.queryPage(limit: 2, offset: 2);
    expect(page2.map((r) => r.id), ['3', '2']);
    final page3 = await store.queryPage(limit: 2, offset: 4);
    expect(page3.map((r) => r.id), ['1']);
    expect(await store.queryPage(limit: 2, offset: 6), isEmpty);

    // 筛选条件同样生效。
    final filtered = await store.queryPage(keyword: '插排3', limit: 2);
    expect(filtered.single.id, '3');
  });

  test('queryDuplicateGroups：编码一致为重复，空编码排除，组与组内均倒序', () async {
    LabelRecord withCode(String id, String code, int hour) {
      return LabelRecord(
        id: id,
        key: 'RVendor#$id',
        createdAt: DateTime(2026, 11, 25, hour),
        fields: {LabelFieldKey.name: '物料$id', LabelFieldKey.materialCode: code},
      );
    }

    await store.add(withCode('1', 'DUP', 10));
    await store.add(withCode('2', 'DUP', 11));
    await store.add(withCode('3', 'DUP2', 9));
    await store.add(withCode('4', 'DUP2', 12));
    await store.add(withCode('5', 'UNIQUE', 13));
    await store.add(withCode('6', '', 14));
    await store.add(withCode('7', '', 15));

    final groups = await store.queryDuplicateGroups();
    // 唯一编码与空编码（即使多条）均不成组；组按最新录入时间倒序。
    expect(groups.map((g) => g.materialCode), ['DUP2', 'DUP']);
    expect(groups[0].records.map((r) => r.id), ['4', '3']);
    expect(groups[0].count, 2);
    expect(groups[1].records.map((r) => r.id), ['2', '1']);
  });

  test('queryDuplicateGroups：按组分页与筛选', () async {
    LabelRecord withCode(String id, String name, String code, int hour) {
      return LabelRecord(
        id: id,
        key: 'RVendor#$id',
        createdAt: DateTime(2026, 11, 25, hour),
        fields: {LabelFieldKey.name: name, LabelFieldKey.materialCode: code},
      );
    }

    await store.add(withCode('1', '信号线插排', 'DUP', 10));
    await store.add(withCode('2', '信号线插排', 'DUP', 11));
    await store.add(withCode('3', '电源线', 'DUP2', 12));
    await store.add(withCode('4', '电源线', 'DUP2', 13));

    final page1 = await store.queryDuplicateGroups(limit: 1);
    expect(page1.single.materialCode, 'DUP2');
    final page2 = await store.queryDuplicateGroups(limit: 1, offset: 1);
    expect(page2.single.materialCode, 'DUP');
    expect(await store.queryDuplicateGroups(limit: 1, offset: 2), isEmpty);

    // 名称筛选后 DUP2 组不再匹配，只剩 DUP 组。
    final filtered = await store.queryDuplicateGroups(keyword: '信号线');
    expect(filtered.single.materialCode, 'DUP');
    expect(filtered.single.records.length, 2);

    final filteredByCode = await store.queryDuplicateGroups(keyword: 'DUP2');
    expect(filteredByCode.single.materialCode, 'DUP2');
    expect(filteredByCode.single.records.length, 2);
  });
}
