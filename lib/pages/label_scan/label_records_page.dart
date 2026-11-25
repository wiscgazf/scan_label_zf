import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
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
    final picked = await showModalBottomSheet<DateTimeRange>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => _DateRangeFilterSheet(initialRange: _filterRange),
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
      return '${formatRecordDate(range.start)} ~ ${formatRecordDate(range.end)}';
    }
    if (range.start.year == range.end.year &&
        range.start.month == range.end.month &&
        range.start.day == range.end.day) {
      return short(range.start);
    }
    return '${short(range.start)} ~ ${short(range.end)}';
  }

  /// 未筛选时只显示日历图标；筛选后日期和清除入口共享一个紧凑标签。
  Widget _buildDateFilterAction(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    final range = _filterRange;
    if (range == null) {
      return IconButton(
        tooltip: l10n.dateFilter,
        onPressed: _pickDateRange,
        icon: const Icon(Icons.calendar_month_outlined, size: 20),
      );
    }
    return Material(
      key: const ValueKey('selected-date-filter-tag'),
      color: colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: l10n.editDateFilter,
            child: InkWell(
              onTap: _pickDateRange,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 4, 2, 4),
                  child: Text(
                    _formatRange(range),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Tooltip(
            message: l10n.clearDateFilter,
            child: InkWell(
              onTap: _clearDateRange,
              child: SizedBox(
                width: 32,
                height: 32,
                child: Icon(Icons.close, size: 14, color: colorScheme.primary),
              ),
            ),
          ),
        ],
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
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteRecordTitle),
        content: Text(l10n.deleteRecordMessage(record.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed == true) await _store.delete(record.id);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.recordsTitle),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _buildDateFilterAction(colorScheme),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.all),
              Tab(text: l10n.duplicates),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _searchController,
                  onChanged: _onKeywordChanged,
                  style: const TextStyle(fontSize: 14),
                  textAlignVertical: TextAlignVertical.center,
                  decoration: InputDecoration(
                    hintText: l10n.searchHint,
                    hintStyle: TextStyle(
                      fontSize: 14,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 40,
                    ),
                    suffixIconConstraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 40,
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
                    fillColor: colorScheme.surface,
                    isDense: true,
                    isCollapsed: true,
                    contentPadding: EdgeInsets.zero,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: colorScheme.primary,
                        width: 1.3,
                      ),
                    ),
                  ),
                ),
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

/// 轻量月历底部弹层：点击两次形成区间，也可只选一天后直接确定。
class _DateRangeFilterSheet extends StatefulWidget {
  const _DateRangeFilterSheet({this.initialRange});

  final DateTimeRange? initialRange;

  @override
  State<_DateRangeFilterSheet> createState() => _DateRangeFilterSheetState();
}

class _DateRangeFilterSheetState extends State<_DateRangeFilterSheet> {
  static final DateTime _firstDate = DateTime(2020);

  late final DateTime _lastDate = _day(DateTime.now());
  late DateTime _visibleMonth;
  late final PageController _monthController;
  DateTime? _start;
  DateTime? _end;

  static DateTime _day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static bool _isSameDay(DateTime? a, DateTime? b) =>
      a != null &&
      b != null &&
      a.year == b.year &&
      a.month == b.month &&
      a.day == b.day;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRange;
    _start = initial == null ? null : _day(initial.start);
    _end = initial == null ? null : _day(initial.end);
    final anchor = _start ?? _lastDate;
    _visibleMonth = DateTime(anchor.year, anchor.month);
    _monthController = PageController(initialPage: _monthIndex(_visibleMonth));
  }

  @override
  void dispose() {
    _monthController.dispose();
    super.dispose();
  }

  int get _monthCount =>
      (_lastDate.year - _firstDate.year) * 12 +
      _lastDate.month -
      _firstDate.month +
      1;

  int _monthIndex(DateTime month) =>
      (month.year - _firstDate.year) * 12 + month.month - _firstDate.month;

  DateTime _monthAt(int index) =>
      DateTime(_firstDate.year, _firstDate.month + index);

  bool get _canGoBack =>
      _visibleMonth.isAfter(DateTime(_firstDate.year, _firstDate.month));

  bool get _canGoForward =>
      _visibleMonth.isBefore(DateTime(_lastDate.year, _lastDate.month));

  String get _selectionText {
    final l10n = AppLocalizations.of(context);
    final start = _start;
    if (start == null) return l10n.selectStartDate;
    final end = _end;
    if (end == null) {
      return '${formatRecordDate(start)} · ${l10n.selectEndDate}';
    }
    if (_isSameDay(start, end)) return formatRecordDate(start);
    return '${formatRecordDate(start)} ${l10n.dateRangeTo} ${formatRecordDate(end)}';
  }

  void _moveMonth(int offset) {
    final target = _monthIndex(_visibleMonth) + offset;
    if (target < 0 || target >= _monthCount) return;
    _monthController.animateToPage(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  void _selectDay(DateTime day) {
    if (day.isBefore(_firstDate) || day.isAfter(_lastDate)) return;
    setState(() {
      final start = _start;
      if (start == null || _end != null) {
        _start = day;
        _end = null;
      } else if (day.isBefore(start)) {
        _start = day;
        _end = null;
      } else {
        _end = day;
      }
    });
  }

  void _confirm() {
    final start = _start;
    if (start == null) return;
    Navigator.of(context).pop(DateTimeRange(start: start, end: _end ?? start));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return FractionallySizedBox(
      // 预留完整六行日期与固定操作区，常见手机无需纵向滚动。
      heightFactor: 0.80,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.selectDateRange,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _selectionText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _start == null
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: l10n.previousMonth,
                          onPressed: _canGoBack ? () => _moveMonth(-1) : null,
                          icon: const Icon(Icons.chevron_left),
                        ),
                        Expanded(
                          child: Text(
                            l10n.monthTitle(_visibleMonth),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: l10n.nextMonth,
                          onPressed: _canGoForward ? () => _moveMonth(1) : null,
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        for (final weekday in l10n.weekdays)
                          Expanded(
                            child: Center(
                              child: Text(
                                weekday,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          // 常规屏幕保持 48dp 行高；较矮屏幕等比压缩六行，
                          // 保证月末日期完整可见且不需要纵向滚动。
                          final calendarHeight = constraints.maxHeight < 288
                              ? constraints.maxHeight
                              : 288.0;
                          final rowHeight = calendarHeight / 6;
                          return Align(
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              height: calendarHeight,
                              // builder 按需构建月份，每页最多 42 个日期格，
                              // 避免打开弹层时一次性生成全部月份。
                              child: PageView.builder(
                                controller: _monthController,
                                itemCount: _monthCount,
                                onPageChanged: (index) {
                                  setState(
                                    () => _visibleMonth = _monthAt(index),
                                  );
                                },
                                itemBuilder: (context, index) =>
                                    _buildCalendarGrid(
                                      _monthAt(index),
                                      colorScheme,
                                      rowHeight,
                                    ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 48,
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: Text(l10n.cancel),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _start == null ? null : _confirm,
                        child: Text(l10n.done),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarGrid(
    DateTime month,
    ColorScheme colorScheme,
    double rowHeight,
  ) {
    final firstOfMonth = DateTime(month.year, month.month);
    final leadingDays = (firstOfMonth.weekday - DateTime.monday) % 7;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    return GridView.builder(
      key: ValueKey('calendar-${month.year}-${month.month}'),
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: 42,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 7,
        mainAxisExtent: rowHeight,
      ),
      itemBuilder: (context, index) {
        final dayNumber = index - leadingDays + 1;
        if (dayNumber < 1 || dayNumber > daysInMonth) {
          return const SizedBox.shrink();
        }
        final day = DateTime(month.year, month.month, dayNumber);
        return _buildDayCell(day, colorScheme);
      },
    );
  }

  Widget _buildDayCell(DateTime day, ColorScheme colorScheme) {
    final disabled = day.isBefore(_firstDate) || day.isAfter(_lastDate);
    final isStart = _isSameDay(day, _start);
    final isEnd = _isSameDay(day, _end);
    final selected = isStart || isEnd;
    final start = _start;
    final end = _end;
    final inRange =
        start != null &&
        end != null &&
        !day.isBefore(start) &&
        !day.isAfter(end);
    final isToday = _isSameDay(day, _lastDate);
    final background = selected
        ? colorScheme.primary
        : inRange
        ? colorScheme.primaryContainer.withValues(alpha: 0.65)
        : Colors.transparent;
    final foreground = disabled
        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.35)
        : selected
        ? colorScheme.onPrimary
        : inRange
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return Semantics(
      button: true,
      enabled: !disabled,
      selected: selected,
      child: InkWell(
        onTap: disabled ? null : () => _selectDay(day),
        borderRadius: BorderRadius.circular(10),
        child: Center(
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(10),
              border: isToday && !selected
                  ? Border.all(color: colorScheme.primary, width: 1.2)
                  : null,
            ),
            child: Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
