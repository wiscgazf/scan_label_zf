import 'dart:async';

import 'package:flutter/material.dart';

import 'label_records.dart';

/// “全部”标签页：分页加载全部记录，支持下拉刷新与上拉加载更多。
class AllRecordsTab extends StatelessWidget {
  const AllRecordsTab({
    super.key,
    required this.store,
    required this.filterKey,
    this.startDate,
    this.endDate,
    this.keyword = '',
    required this.onEdit,
    required this.onDelete,
  });

  final LabelRecordStore store;

  /// 筛选条件或外部刷新信号变化时该值改变，触发重新加载。
  final String filterKey;
  final DateTime? startDate;
  final DateTime? endDate;
  final String keyword;
  final ValueChanged<LabelRecord> onEdit;
  final ValueChanged<LabelRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final hasFilter =
        startDate != null || endDate != null || keyword.isNotEmpty;
    return _PagedRecordsView<LabelRecord>(
      filterKey: filterKey,
      pageSize: 30,
      emptyText: hasFilter ? '没有符合条件的记录' : '暂无标签记录，先去首页扫一扫',
      fetcher: (limit, offset) => store.queryPage(
        startDate: startDate,
        endDate: endDate,
        keyword: keyword,
        limit: limit,
        offset: offset,
      ),
      itemBuilder: (context, record) =>
          RecordCard(record: record, onEdit: onEdit, onDelete: onDelete),
    );
  }
}

/// “重复标签”标签页：编码一致的记录按组展示（空编码不算重复），
/// 组按最近一次录入时间倒序，按组分页。
class DuplicateRecordsTab extends StatelessWidget {
  const DuplicateRecordsTab({
    super.key,
    required this.store,
    required this.filterKey,
    this.startDate,
    this.endDate,
    this.keyword = '',
    required this.onEdit,
    required this.onDelete,
  });

  final LabelRecordStore store;
  final String filterKey;
  final DateTime? startDate;
  final DateTime? endDate;
  final String keyword;
  final ValueChanged<LabelRecord> onEdit;
  final ValueChanged<LabelRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final hasFilter =
        startDate != null || endDate != null || keyword.isNotEmpty;
    return _PagedRecordsView<DuplicateGroup>(
      filterKey: filterKey,
      pageSize: 10,
      emptyText: hasFilter ? '没有符合条件的重复记录' : '没有重复编码的记录',
      fetcher: (limit, offset) => store.queryDuplicateGroups(
        startDate: startDate,
        endDate: endDate,
        keyword: keyword,
        limit: limit,
        offset: offset,
      ),
      itemBuilder: (context, group) => _DuplicateGroupView(
        group: group,
        onEdit: onEdit,
        onDelete: onDelete,
      ),
    );
  }
}

/// 通用分页列表：首屏加载一页，滚动接近底部自动加载下一页，
/// 下拉刷新重置为第一页；数据为空时也可下拉刷新。
class _PagedRecordsView<T> extends StatefulWidget {
  const _PagedRecordsView({
    required this.filterKey,
    required this.pageSize,
    required this.emptyText,
    required this.fetcher,
    required this.itemBuilder,
  });

  final String filterKey;
  final int pageSize;
  final String emptyText;
  final Future<List<T>> Function(int limit, int offset) fetcher;
  final Widget Function(BuildContext context, T item) itemBuilder;

  @override
  State<_PagedRecordsView<T>> createState() => _PagedRecordsViewState<T>();
}

class _PagedRecordsViewState<T> extends State<_PagedRecordsView<T>>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  List<T> _items = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    unawaited(_reload());
  }

  @override
  void didUpdateWidget(covariant _PagedRecordsView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterKey != widget.filterKey) unawaited(_reload());
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.extentAfter < 300) {
      unawaited(_loadMore());
    }
  }

  Future<void> _reload() async {
    final items = await widget.fetcher(widget.pageSize, 0);
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
      _loadingMore = false;
      _hasMore = items.length == widget.pageSize;
    });
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final items = await widget.fetcher(widget.pageSize, _items.length);
    if (!mounted) return;
    setState(() {
      _items = [..._items, ...items];
      _hasMore = items.length == widget.pageSize;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              itemCount: _items.isEmpty ? 1 : _items.length + 1,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                if (_items.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 120),
                    child: Center(
                      child: Text(
                        widget.emptyText,
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  );
                }
                if (index == _items.length) return _buildFooter(colorScheme);
                return widget.itemBuilder(context, _items[index]);
              },
            ),
    );
  }

  Widget _buildFooter(ColorScheme colorScheme) {
    if (_loadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (!_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: Text(
            '没有更多了',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }
}

/// 重复分组：组头展示编码与重复次数，组内为该编码的全部记录。
class _DuplicateGroupView extends StatelessWidget {
  const _DuplicateGroupView({
    required this.group,
    required this.onEdit,
    required this.onDelete,
  });

  final DuplicateGroup group;
  final ValueChanged<LabelRecord> onEdit;
  final ValueChanged<LabelRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
          child: Row(
            children: [
              Icon(
                Icons.copy_all_outlined,
                size: 16,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  group.materialCode,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '重复 ${group.count} 次',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < group.records.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          RecordCard(
            record: group.records[i],
            onEdit: onEdit,
            onDelete: onDelete,
          ),
        ],
      ],
    );
  }
}

/// 记录卡片：名称与公司名、编码胶囊、录入时间与编辑/删除操作。
class RecordCard extends StatelessWidget {
  const RecordCard({
    super.key,
    required this.record,
    required this.onEdit,
    required this.onDelete,
  });

  final LabelRecord record;
  final ValueChanged<LabelRecord> onEdit;
  final ValueChanged<LabelRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    record.name.isEmpty ? '（未填写名称）' : record.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (record.companyName.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      record.companyName,
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '编码：${record.materialCode.isEmpty ? '-' : record.materialCode}',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  formatRecordTime(record.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                _RecordActionButton(
                  icon: Icons.edit_outlined,
                  tooltip: '编辑',
                  color: colorScheme.primary,
                  background: colorScheme.primaryContainer.withValues(
                    alpha: 0.45,
                  ),
                  onTap: () => onEdit(record),
                ),
                const SizedBox(width: 8),
                _RecordActionButton(
                  icon: Icons.delete_outline,
                  tooltip: '删除',
                  color: colorScheme.error,
                  background: colorScheme.errorContainer.withValues(alpha: 0.4),
                  onTap: () => onDelete(record),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 记录卡片右下角的操作按钮：浅色圆角底 + 小图标。
class _RecordActionButton extends StatelessWidget {
  const _RecordActionButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.background,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final Color background;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 32,
            height: 32,
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}
