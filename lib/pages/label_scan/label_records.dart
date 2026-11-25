import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'label_scan_models.dart';

/// 一条已确认的标签记录。
class LabelRecord {
  const LabelRecord({
    required this.id,
    required this.key,
    required this.fields,
    required this.createdAt,
    this.companyName = '',
  });

  factory LabelRecord.fromScanResult(LabelScanResult result) {
    final now = DateTime.now();
    return LabelRecord(
      id: now.microsecondsSinceEpoch.toString(),
      key: result.key,
      fields: Map.of(result.fields),
      createdAt: now,
      companyName: result.companyName,
    );
  }

  factory LabelRecord.fromRow(Map<String, Object?> row) {
    final fieldsJson = jsonDecode(row['fields'] as String) as Map<String, dynamic>;
    return LabelRecord(
      id: row['id'] as String,
      key: row['scan_key'] as String,
      companyName: row['company_name'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int),
      fields: {
        for (final entry in fieldsJson.entries)
          LabelFieldKey.values.byName(entry.key): entry.value as String,
      },
    );
  }

  final String id;
  final String key;
  final Map<LabelFieldKey, String> fields;
  final DateTime createdAt;
  final String companyName;

  String get name => fields[LabelFieldKey.name] ?? '';
  String get materialCode => fields[LabelFieldKey.materialCode] ?? '';

  LabelScanResult toScanResult() {
    return LabelScanResult(key: key, fields: fields, companyName: companyName);
  }

  /// 名称、编码、录入时间冗余为独立列，供 SQL 筛选与排序；
  /// 完整字段以 JSON 存放。
  Map<String, Object?> toRow() {
    return {
      'id': id,
      'scan_key': key,
      'company_name': companyName,
      'name': name,
      'material_code': materialCode,
      'created_at': createdAt.millisecondsSinceEpoch,
      'fields': jsonEncode({
        for (final entry in fields.entries) entry.key.name: entry.value,
      }),
    };
  }
}

/// 重复编码分组：同一物料编码的全部记录。
class DuplicateGroup {
  const DuplicateGroup({required this.materialCode, required this.records});

  final String materialCode;
  final List<LabelRecord> records;

  int get count => records.length;
}

/// 本地记录仓库：SQLite 实现，纯本地、无需网络，支持上万条数据。
class LabelRecordStore extends ChangeNotifier {
  LabelRecordStore({this.dbPath});

  /// 测试可传入内存库路径（inMemoryDatabasePath）。
  final String? dbPath;
  Database? _db;

  Future<Database> _database() async {
    final existing = _db;
    if (existing != null) return existing;
    final path = dbPath ?? '${await getDatabasesPath()}/label_records.db';
    final db = await openDatabase(
      path,
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE label_records(
            id TEXT PRIMARY KEY,
            scan_key TEXT NOT NULL,
            company_name TEXT NOT NULL DEFAULT '',
            name TEXT NOT NULL DEFAULT '',
            material_code TEXT NOT NULL DEFAULT '',
            created_at INTEGER NOT NULL,
            fields TEXT NOT NULL
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_label_records_created_at ON label_records(created_at)',
        );
        await db.execute(
          'CREATE INDEX idx_label_records_name ON label_records(name)',
        );
        await db.execute(
          'CREATE INDEX idx_label_records_material_code ON label_records(material_code)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // 重复编码分组查询按 material_code 聚合，补充索引。
          await db.execute(
            'CREATE INDEX IF NOT EXISTS idx_label_records_material_code ON label_records(material_code)',
          );
        }
      },
    );
    _db = db;
    return db;
  }

  /// 应用启动时预热，避免首次打开管理页等待建库。
  Future<void> open() => _database();

  /// 按录入日期区间（含起止当天，均可留空）与物料名称（模糊）筛选，
  /// 录入时间倒序。
  Future<List<LabelRecord>> query({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
  }) async {
    final db = await _database();
    final filter = _RecordFilter(
      startDate: startDate,
      endDate: endDate,
      keyword: keyword,
    );
    final rows = await db.query(
      'label_records',
      where: filter.whereClause,
      whereArgs: filter.args,
      orderBy: 'created_at DESC',
    );
    return rows.map(LabelRecord.fromRow).toList();
  }

  /// 分页查询：按录入时间倒序，offset 超过总数时返回空列表。
  Future<List<LabelRecord>> queryPage({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
    int limit = 30,
    int offset = 0,
  }) async {
    final db = await _database();
    final filter = _RecordFilter(
      startDate: startDate,
      endDate: endDate,
      keyword: keyword,
    );
    final rows = await db.query(
      'label_records',
      where: filter.whereClause,
      whereArgs: filter.args,
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return rows.map(LabelRecord.fromRow).toList();
  }

  /// 查询重复编码分组（编码一致即重复，空编码不参与）。
  /// 每组包含该编码的全部记录（组内按录入时间倒序），
  /// 组按最近一次录入时间倒序，按组分页。
  Future<List<DuplicateGroup>> queryDuplicateGroups({
    DateTime? startDate,
    DateTime? endDate,
    String keyword = '',
    int limit = 10,
    int offset = 0,
  }) async {
    final db = await _database();
    final filter = _RecordFilter(
      startDate: startDate,
      endDate: endDate,
      keyword: keyword,
    );
    final extra = filter.whereClause == null
        ? ''
        : ' AND ${filter.whereClause}';
    final groupRows = await db.rawQuery(
      '''
      SELECT material_code, COUNT(*) AS cnt, MAX(created_at) AS latest
      FROM label_records
      WHERE material_code != ''$extra
      GROUP BY material_code
      HAVING cnt > 1
      ORDER BY latest DESC
      LIMIT ? OFFSET ?
      ''',
      [...filter.args, limit, offset],
    );
    if (groupRows.isEmpty) return [];
    final codes = groupRows
        .map((row) => row['material_code'] as String)
        .toList();
    final placeholders = List.filled(codes.length, '?').join(', ');
    final recordRows = await db.rawQuery(
      '''
      SELECT * FROM label_records
      WHERE material_code IN ($placeholders)$extra
      ORDER BY created_at DESC
      ''',
      [...codes, ...filter.args],
    );
    final byCode = <String, List<LabelRecord>>{};
    for (final row in recordRows) {
      final record = LabelRecord.fromRow(row);
      byCode.putIfAbsent(record.materialCode, () => []).add(record);
    }
    return [
      for (final code in codes)
        DuplicateGroup(materialCode: code, records: byCode[code]!),
    ];
  }

  Future<void> add(LabelRecord record) async {
    final db = await _database();
    await db.insert(
      'label_records',
      record.toRow(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  Future<void> update(LabelRecord record) async {
    final db = await _database();
    await db.update(
      'label_records',
      record.toRow(),
      where: 'id = ?',
      whereArgs: [record.id],
    );
    notifyListeners();
  }

  Future<void> delete(String id) async {
    final db = await _database();
    await db.delete('label_records', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }
}

/// 日期区间与名称关键字的筛选条件，供各查询方法复用。
class _RecordFilter {
  _RecordFilter({DateTime? startDate, DateTime? endDate, String keyword = ''}) {
    final where = <String>[];
    final whereArgs = <Object?>[];
    if (startDate != null) {
      final start = DateTime(startDate.year, startDate.month, startDate.day);
      where.add('created_at >= ?');
      whereArgs.add(start.millisecondsSinceEpoch);
    }
    if (endDate != null) {
      // 结束日期包含当天，取次日 0 点为开区间上界。
      final end = DateTime(
        endDate.year,
        endDate.month,
        endDate.day,
      ).add(const Duration(days: 1));
      where.add('created_at < ?');
      whereArgs.add(end.millisecondsSinceEpoch);
    }
    if (keyword.isNotEmpty) {
      final escaped = keyword
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      where.add("name LIKE ? ESCAPE '\\'");
      whereArgs.add('%$escaped%');
    }
    whereClause = where.isEmpty ? null : where.join(' AND ');
    args = whereArgs;
  }

  late final String? whereClause;
  late final List<Object?> args;
}

/// 全局单例：首页保存与管理页共用。
final labelRecordStore = LabelRecordStore();

String formatRecordTime(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${formatRecordDate(time)} ${two(time.hour)}:${two(time.minute)}';
}

String formatRecordDate(DateTime time) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${time.year}-${two(time.month)}-${two(time.day)}';
}
