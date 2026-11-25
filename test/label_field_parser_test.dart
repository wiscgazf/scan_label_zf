import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/pages/label_scan/label_field_parser.dart';
import 'package:scan_label_zf/pages/label_scan/label_scan_models.dart';

/// 构造 OCR region，top 相同即同一视觉行。
LabelOcrRegion region(
  String text,
  double left,
  double top, {
  double width = 100,
  double height = 30,
}) {
  return LabelOcrRegion(
    text: text,
    left: left,
    top: top,
    right: left + width,
    bottom: top + height,
  );
}

void main() {
  final parser = LabelFieldParser();

  group('供应商行（供应商 | 公司 | 数量 | 1）', () {
    test('全部独立 region', () {
      final fields = parser.parse([
        region('供应商', 0, 100),
        region('莆田市万盛达光电科技有限公司', 120, 100, width: 260),
        region('数量', 400, 100),
        region('1', 560, 100, width: 20),
      ]);
      expect(fields[LabelFieldKey.supplier], '莆田市万盛达光电科技有限公司');
      expect(fields[LabelFieldKey.quantity], '1');
    });

    test('公司名与右列标签合并为一个 region', () {
      final fields = parser.parse([
        region('供应商', 0, 100),
        region('莆田市万盛达光电科技有限公司 数量', 120, 100, width: 360),
        region('1', 560, 100, width: 20),
      ]);
      expect(fields[LabelFieldKey.supplier], '莆田市万盛达光电科技有限公司');
      expect(fields[LabelFieldKey.quantity], '1');
    });

    test('整行合并为一个 region', () {
      final fields = parser.parse([
        region('供应商莆田市万盛达光电科技有限公司数量', 0, 100, width: 480),
        region('1', 560, 100, width: 20),
      ]);
      expect(fields[LabelFieldKey.supplier], '莆田市万盛达光电科技有限公司');
      expect(fields[LabelFieldKey.quantity], '1');
    });

    test('值 1 漏检时供应商仍应正确', () {
      final fields = parser.parse([
        region('供应商', 0, 100),
        region('莆田市万盛达光电科技有限公司数量', 120, 100, width: 360),
      ]);
      expect(fields[LabelFieldKey.supplier], '莆田市万盛达光电科技有限公司');
      expect(fields[LabelFieldKey.quantity], '');
    });
  });

  test('订单号行为空值，整箱总数取最右列的 1', () {
    final fields = parser.parse([
      region('订单号', 0, 140),
      region('整箱总数', 400, 140),
      region('1', 560, 140, width: 20),
    ]);
    expect(fields[LabelFieldKey.orderNumber], '');
    expect(fields[LabelFieldKey.cartonCount], '1');
  });

  test('生产批次与送货日期同行', () {
    final fields = parser.parse([
      region('生产批次', 0, 180),
      region('20260805', 120, 180),
      region('送货日期', 400, 180),
      region('2026-08-05', 560, 180),
    ]);
    expect(fields[LabelFieldKey.productionBatch], '20260805');
    expect(fields[LabelFieldKey.deliveryDate], '2026-08-05');
  });

  test('常规字段与推荐仓位取小包标签', () {
    final fields = parser.parse([
      region('推荐仓位', 0, 20),
      region('小包标签', 300, 20),
      region('物料编码', 0, 60),
      region('03-XHX-254350-XX-0001', 120, 60, width: 260),
      region('名称', 0, 100),
      region('信号线插排', 120, 100),
      region('产品规格', 0, 140),
      region('XH-S2.54-2P-350mm，尾部压铆管型端子', 120, 140, width: 360),
    ]);
    expect(fields[LabelFieldKey.recommendedLocation], '小包标签');
    expect(fields[LabelFieldKey.materialCode], '03-XHX-254350-XX-0001');
    expect(fields[LabelFieldKey.name], '信号线插排');
    expect(fields[LabelFieldKey.specification], 'XH-S2.54-2P-350mm，尾部压铆管型端子');
  });

  group('公司名称提取', () {
    test('取最靠上的公司标题，忽略背景杂物与供应商公司名', () {
      final name = parser.extractCompanyName([
        region('石', 521, 43, width: 221),
        region('品', 200, 95),
        region('深圳市瑞能电源科技有限公司', 562, 795, width: 406),
        region('供应商', 411, 1004),
        region('莆田市万盛达光电科技有限公司', 490, 1008, width: 291),
      ]);
      expect(name, '深圳市瑞能电源科技有限公司');
    });

    test('无公司标题时返回空', () {
      expect(parser.extractCompanyName([region('供应商', 0, 100)]), '');
    });
  });

  test('二维码内容兜底物料编码与生产批次', () {
    final fields = parser.parse(
      const [],
      scanKey: 'RVendor#03-XHX-254350-XX-0001#260805#20260805#00001#0001',
    );
    expect(fields[LabelFieldKey.materialCode], '03-XHX-254350-XX-0001');
    expect(fields[LabelFieldKey.productionBatch], '20260805');
  });
}
