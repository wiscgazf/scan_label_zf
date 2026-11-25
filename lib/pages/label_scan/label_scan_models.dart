enum LabelFieldKey {
  recommendedLocation,
  materialCode,
  name,
  specification,
  supplier,
  quantity,
  orderNumber,
  cartonCount,
  productionBatch,
  deliveryDate,
}

extension LabelFieldKeyText on LabelFieldKey {
  String get label => switch (this) {
    LabelFieldKey.recommendedLocation => '推荐仓位',
    LabelFieldKey.materialCode => '物料编码',
    LabelFieldKey.name => '名称',
    LabelFieldKey.specification => '产品规格',
    LabelFieldKey.supplier => '供应商',
    LabelFieldKey.quantity => '数量',
    LabelFieldKey.orderNumber => '订单号',
    LabelFieldKey.cartonCount => '整箱总数',
    LabelFieldKey.productionBatch => '生产批次',
    LabelFieldKey.deliveryDate => '送货日期',
  };
}

class LabelOcrRegion {
  const LabelOcrRegion({
    required this.text,
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.confidence = 0,
  });

  final String text;
  final double left;
  final double top;
  final double right;
  final double bottom;
  final double confidence;

  double get width => right - left;
  double get height => bottom - top;
  double get centerY => (top + bottom) / 2;
}

class LabelScanResult {
  const LabelScanResult({
    required this.key,
    required this.fields,
    this.companyName = '',
  });

  /// 二维码内容，与标签最后一行的 RVendor#... 字符串一致。
  final String key;
  final Map<LabelFieldKey, String> fields;

  /// 标签标题中的公司名称，未识别到时为空。
  final String companyName;

  LabelScanResult copyWith({Map<LabelFieldKey, String>? fields}) {
    return LabelScanResult(
      key: key,
      fields: fields ?? this.fields,
      companyName: companyName,
    );
  }
}
