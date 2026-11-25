import 'dart:async';

import 'package:flutter/material.dart';

import 'label_records.dart';
import 'label_records_tabs.dart';
import 'label_scan_models.dart';
import 'label_scan_page.dart';

/// 标签管理页：全部 / 重复标签双 Tab（可左右滑动），
/// 顶部搜索与日期区间筛选对两个 Tab 同时生效；
/// 列表支持下拉刷新、上拉加载更多，记录支持编辑与删除。
class LabelRecordsPage extends StatefulWidget {
  const LabelRecordsPage({super.key, this.store});

  /// 测试可注入内存库；默认使用全局单例。
  final LabelRecordStore? store;

  @override
  State<LabelRecordsPage> createState() => _LabelRecordsPageState();
}

class _LabelRecordsPageState extends State<LabelRecordsPage> {
  late final LabelRecordStore _store = widget.store ?? labelRecordStore;
  final _searchController = TextEditingController();

  DateTimeRange? _filterRange;
  String _keyword = '';
  Timer? _debounce;

  /// 每次筛选变化或数据变动（增删改）自增，驱动两个 Tab 重新加载。
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _store.addListener(_refresh);
  }

  @override
  void dispose() {
    _store.removeListener(_refresh);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  String get _filterKey =>
      '$_reloadToken|${_filterRange?.start}|${_filterRange?.end}|$_keyword';

  void _refresh() {
    if (!mounted) return;
    setState(() => _reloadToken++);
  }

  void _onKeywordChanged(String value) {
    _keyword = value.trim();
    // 输入停顿 300ms 后再查询，避免每次击键都访问数据库。
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), _refresh);
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: _filterRange,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year, now.month, now.day),
      helpText: '选择录入日期区间',
      cancelText: '取消',
      saveText: '确定',
    );
    if (picked == null) return;
    setState(() => _filterRange = picked);
    _refresh();
  }

  void _clearDateRange() {
    setState(() => _filterRange = null);
    _refresh();
  }

  String _formatRange(DateTimeRange range) {
    String short(DateTime d) =>
        '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    if (range.start.year != range.end.year) {
      return '${formatRecordDate(range.start)}~${formatRecordDate(range.end)}';
    }
    if (range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day) {
      return short(range.start);
    }
    return '${short(range.start)}~${short(range.end)}';
  }

  /// 紧凑的日期区间筛选按钮：未选时显示“日期”，
  /// 已选时高亮显示区间并附带清除按钮。
  Widget _buildDateFilterButton(ColorScheme colorScheme) {
    final range = _filterRange;
    final selected = range != null;
    final foreground = selected
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurfaceVariant;
    return Material(
      color: selected
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: _pickDateRange,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          height: 40,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 10),
              Icon(Icons.calendar_month_outlined, size: 18, color: foreground),
              const SizedBox(width: 6),
              Text(
                selected ? _formatRange(range) : '日期',
                style: TextStyle(fontSize: 13, color: foreground),
              ),
              if (selected)
                GestureDetector(
                  onTap: _clearDateRange,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, size: 16, color: foreground),
                  ),
                )
              else
                const SizedBox(width: 10),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(LabelRecord record) async {
    final confirmed = await showModalBottomSheet<LabelScanResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LabelResultFormSheet(result: record.toScanResult()),
    );
    if (confirmed == null) return;
    await _store.update(
      LabelRecord(
        id: record.id,
        key: confirmed.key,
        fields: confirmed.fields,
        createdAt: record.createdAt,
        companyName: confirmed.companyName,
      ),
    );
  }

  Future<void> _delete(LabelRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除记录'),
        content: Text('确定删除「${record.name}」这条标签记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.delete(record.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('标签管理'),
          bottom: const TabBar(
            tabs: [Tab(text: '全部'), Tab(text: '重复标签')],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              // 搜索与日期筛选合并为一行，把空间留给列表。
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onKeywordChanged,
                        style: const TextStyle(fontSize: 14),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: '搜索物料名称',
                          hintStyle: TextStyle(
                            fontSize: 14,
                            color: colorScheme.outline,
                          ),
                          prefixIcon: const Icon(Icons.search, size: 20),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          // 默认 48 的图标约束会把输入框撑高，
                          // 收紧以保持与右侧日期按钮同为 40 高。
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          suffixIcon: _keyword.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _onKeywordChanged('');
                                  },
                                  icon: const Icon(Icons.clear, size: 18),
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildDateFilterButton(colorScheme),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AllRecordsTab(
                    store: _store,
                    filterKey: _filterKey,
                    startDate: _filterRange?.start,
                    endDate: _filterRange?.end,
                    keyword: _keyword,
                    onEdit: (record) => unawaited(_edit(record)),
                    onDelete: (record) => unawaited(_delete(record)),
                  ),
                  DuplicateRecordsTab(
                    store: _store,
                    filterKey: _filterKey,
                    startDate: _filterRange?.start,
                    endDate: _filterRange?.end,
                    keyword: _keyword,
                    onEdit: (record) => unawaited(_edit(record)),
                    onDelete: (record) => unawaited(_delete(record)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
