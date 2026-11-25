import 'label_scan_models.dart';

class LabelFieldParser {
  static const _aliases = <LabelFieldKey, List<String>>{
    LabelFieldKey.recommendedLocation: ['推荐仓位'],
    LabelFieldKey.materialCode: ['物料编码'],
    LabelFieldKey.name: ['名称', '产品名称'],
    LabelFieldKey.specification: ['产品规格'],
    LabelFieldKey.supplier: ['供应商'],
    LabelFieldKey.quantity: ['数量'],
    LabelFieldKey.orderNumber: ['订单号'],
    LabelFieldKey.cartonCount: ['整箱总数'],
    LabelFieldKey.productionBatch: ['生产批次'],
    LabelFieldKey.deliveryDate: ['送货日期'],
  };

  static final _labelKeys = <String, LabelFieldKey>{
    for (final entry in _aliases.entries)
      for (final alias in entry.value) alias: entry.key,
  };

  Map<LabelFieldKey, String> parse(
    List<LabelOcrRegion> regions, {
    String scanKey = '',
  }) {
    final sorted = [...regions]
      ..sort((a, b) {
        final row = a.centerY.compareTo(b.centerY);
        return row != 0 ? row : a.left.compareTo(b.left);
      });
    final fields = <LabelFieldKey, String>{
      for (final key in LabelFieldKey.values) key: '',
    };

    for (final row in _groupRows(sorted)) {
      _parseRow(row, fields);
    }

    _applyKeyFallbacks(fields, scanKey);
    _applyTextFallbacks(fields, sorted);
    return fields;
  }

  /// 按垂直位置把 OCR region 聚成视觉行，行内按从左到右排序。
  List<List<LabelOcrRegion>> _groupRows(List<LabelOcrRegion> sorted) {
    final rows = <List<LabelOcrRegion>>[];
    for (final region in sorted) {
      if (rows.isNotEmpty && _isSameRow(rows.last.first, region)) {
        rows.last.add(region);
      } else {
        rows.add([region]);
      }
    }
    for (final row in rows) {
      row.sort((a, b) => a.left.compareTo(b.left));
    }
    return rows;
  }

  /// 把一行转成“标签/文本”序列后顺序取值：标签之后、下一标签之前的
  /// 文本即为该标签的值。标签与值合并在同一 region、右列标签与前一字段
  /// 的值合并（如“…有限公司数量”）等情况都能统一处理。
  void _parseRow(List<LabelOcrRegion> row, Map<LabelFieldKey, String> fields) {
    final tokens = <String>[
      for (final region in row) ..._splitText(_normalize(region.text)),
    ];

    for (var i = 0; i < tokens.length; i++) {
      final key = _labelKeys[tokens[i]];
      if (key == null || fields[key]!.isNotEmpty) continue;

      final value = StringBuffer();
      for (var j = i + 1; j < tokens.length; j++) {
        if (_labelKeys.containsKey(tokens[j])) break;
        final token = tokens[j];
        if (_isUsableValue(token)) value.write(token);
      }
      if (value.isNotEmpty) fields[key] = value.toString();
    }
  }

  /// 按字段别名把 region 文本切分为“标签/文本”序列，别名最长匹配优先。
  List<String> _splitText(String text) {
    final tokens = <String>[];
    final plain = StringBuffer();

    void flushPlain() {
      if (plain.isNotEmpty) {
        tokens.add(plain.toString());
        plain.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      String? matched;
      for (final aliases in _aliases.values) {
        for (final alias in aliases) {
          if (text.startsWith(alias, i) &&
              (matched == null || alias.length > matched.length)) {
            matched = alias;
          }
        }
      }
      if (matched != null) {
        flushPlain();
        tokens.add(matched);
        i += matched.length;
      } else {
        plain.write(text[i]);
        i++;
      }
    }
    flushPlain();
    return tokens;
  }

  bool _isSameRow(LabelOcrRegion first, LabelOcrRegion second) {
    final tolerance = first.height > second.height
        ? first.height
        : second.height;
    return (first.centerY - second.centerY).abs() <= tolerance * 0.65;
  }

  bool _isUsableValue(String value) {
    return value.isNotEmpty && !value.startsWith('RVendor#');
  }

  /// 提取标签标题中的公司名称：取最靠上的、以“公司”结尾且不含字段标签的文本。
  String extractCompanyName(List<LabelOcrRegion> regions) {
    final sorted = [...regions]
      ..sort((a, b) {
        final row = a.centerY.compareTo(b.centerY);
        return row != 0 ? row : a.left.compareTo(b.left);
      });
    for (final region in sorted) {
      final text = _normalize(region.text);
      if (text.endsWith('公司') && !_containsAnyLabel(text)) {
        return region.text.trim();
      }
    }
    return '';
  }

  bool _containsAnyLabel(String text) {
    for (final aliases in _aliases.values) {
      if (aliases.any(text.contains)) return true;
    }
    return false;
  }

  String _normalize(String text) {
    return text.trim().replaceAll(RegExp(r'[\s:：]'), '');
  }

  void _applyKeyFallbacks(Map<LabelFieldKey, String> fields, String scanKey) {
    final parts = scanKey.trim().split('#');
    if (parts.length < 4) return;
    if (fields[LabelFieldKey.materialCode]!.isEmpty) {
      fields[LabelFieldKey.materialCode] = parts[1];
    }
    if (fields[LabelFieldKey.productionBatch]!.isEmpty &&
        RegExp(r'^\d{8}$').hasMatch(parts[3])) {
      fields[LabelFieldKey.productionBatch] = parts[3];
    }
  }

  void _applyTextFallbacks(
    Map<LabelFieldKey, String> fields,
    List<LabelOcrRegion> regions,
  ) {
    if (fields[LabelFieldKey.deliveryDate]!.isNotEmpty) return;
    for (final region in regions) {
      final match = RegExp(r'20\d{2}[-/.]\d{1,2}[-/.]\d{1,2}')
          .firstMatch(_normalize(region.text));
      if (match != null) {
        fields[LabelFieldKey.deliveryDate] = match.group(0)!;
        return;
      }
    }
  }
}
