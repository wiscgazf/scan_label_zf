import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'label_ocr_service.dart';
import 'label_records.dart';
import 'label_scan_models.dart';
import 'label_scanner_page.dart';

class LabelScanPage extends StatefulWidget {
  const LabelScanPage({super.key});

  @override
  State<LabelScanPage> createState() => _LabelScanPageState();
}

class _LabelScanPageState extends State<LabelScanPage> {
  final LabelOcrService _ocrService = LabelOcrService();
  LabelScanResult? _lastResult;

  Future<void> _startScan({bool openFilePicker = false}) async {
    final result = await Navigator.of(context).push<LabelScanResult>(
      MaterialPageRoute(
        builder: (_) => LabelScannerPage(
          ocrService: _ocrService,
          openFilePicker: openFilePicker,
        ),
      ),
    );
    if (result == null || !mounted) return;

    setState(() => _lastResult = result);
    final confirmed = await showModalBottomSheet<LabelScanResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => LabelResultFormSheet(result: result),
    );
    if (confirmed == null || !mounted) return;

    setState(() => _lastResult = confirmed);
    // 确认后写入本地 SQLite，管理页可查看、编辑、删除。
    unawaited(labelRecordStore.add(LabelRecord.fromScanResult(confirmed)));
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('标签字段已确认')));
  }

  @override
  void dispose() {
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = _lastResult;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(colorScheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
              child: Column(
                children: [
                  _HomeActionCard(
                    icon: Icons.qr_code_scanner,
                    title: '扫一扫',
                    subtitle: '扫描二维码，持稳后自动拍摄识别',
                    background: colorScheme.primary,
                    foreground: colorScheme.onPrimary,
                    iconBackground: colorScheme.onPrimary.withValues(
                      alpha: 0.16,
                    ),
                    onTap: () => _startScan(),
                  ),
                  const SizedBox(height: 14),
                  _HomeActionCard(
                    icon: Icons.upload_file_outlined,
                    title: '选择文件识别',
                    subtitle: '从相册选择标签图片进行识别',
                    background: colorScheme.surfaceContainerLow,
                    foreground: colorScheme.onSurface,
                    subtitleColor: colorScheme.onSurfaceVariant,
                    iconColor: colorScheme.primary,
                    iconBackground: colorScheme.primaryContainer.withValues(
                      alpha: 0.5,
                    ),
                    onTap: () => _startScan(openFilePicker: true),
                  ),
                  if (result != null) ...[
                    const SizedBox(height: 20),
                    _buildRecentKeyCard(result, colorScheme),
                  ],
                  const SizedBox(height: 28),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.lock_outline,
                        size: 14,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '识别与存储均在本地完成，无需联网',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 渐变品牌头部：图标、标题、功能说明，右上角为管理入口。
  Widget _buildHeader(ColorScheme colorScheme) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        24,
        MediaQuery.of(context).padding.top + 20,
        16,
        28,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colorScheme.primary, colorScheme.tertiary],
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  size: 32,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: () => context.push('/records'),
                tooltip: '管理',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: 0.16),
                ),
                icon: const Icon(
                  Icons.inventory_2_outlined,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            '标签扫一扫',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '扫描标签二维码或选择标签图片后，自动识别物料、规格、供应商、数量、批次等字段。',
            style: TextStyle(
              fontSize: 13,
              height: 1.6,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  /// 最近扫描 Key 卡片，内容可选中复制。
  Widget _buildRecentKeyCard(
    LabelScanResult result,
    ColorScheme colorScheme,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: colorScheme.primary),
              const SizedBox(width: 6),
              Text(
                '最近扫描 Key',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            result.key,
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}

/// 首页功能入口卡片：圆形图标底 + 标题副标题 + 右侧箭头。
class _HomeActionCard extends StatelessWidget {
  const _HomeActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.background,
    required this.foreground,
    required this.iconBackground,
    required this.onTap,
    this.subtitleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color background;
  final Color foreground;
  final Color iconBackground;
  final VoidCallback onTap;
  final Color? subtitleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 26, color: iconColor ?? foreground),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            subtitleColor ??
                            foreground.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: (subtitleColor ?? foreground).withValues(alpha: 0.6),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 扫描结果核对弹层：底部弹出，上拉展开、下拉关闭。
class LabelResultFormSheet extends StatefulWidget {
  const LabelResultFormSheet({super.key, required this.result});

  final LabelScanResult result;

  @override
  State<LabelResultFormSheet> createState() => _LabelResultFormSheetState();
}

class _LabelResultFormSheetState extends State<LabelResultFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<LabelFieldKey, TextEditingController> _controllers;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final key in LabelFieldKey.values)
        key: TextEditingController(text: widget.result.fields[key] ?? ''),
    };
    // 物料编码、名称为空时红色高亮，手动输入后自动恢复。
    for (final key in const [LabelFieldKey.materialCode, LabelFieldKey.name]) {
      _controllers[key]!.addListener(_refresh);
    }
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  bool _needsValue(LabelFieldKey key) =>
      key == LabelFieldKey.materialCode || key == LabelFieldKey.name;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void _confirm() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      widget.result.copyWith(
        fields: {
          for (final key in LabelFieldKey.values)
            key: _controllers[key]!.text.trim(),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 键盘弹出时整体上移，避免输入框被遮挡。
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Text(
                      '核对标签信息',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (widget.result.companyName.isNotEmpty) ...[
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.result.companyName,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.4,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Form(
                  key: _formKey,
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                    children: [
                      const _FieldLabel('Key（二维码内容）'),
                      const SizedBox(height: 6),
                      _ReadOnlyFieldBox(child: SelectableText(widget.result.key)),
                      const SizedBox(height: 16),
                      for (final key in LabelFieldKey.values) ...[
                        _FieldLabel(key.label),
                        const SizedBox(height: 6),
                        _LabelTextField(
                          controller: _controllers[key]!,
                          hintText: '请输入${key.label}',
                          maxLines: key == LabelFieldKey.specification ? 2 : 1,
                          isError:
                              _needsValue(key) &&
                              _controllers[key]!.text.trim().isEmpty,
                          errorText: '未识别到${key.label}，请手动填写',
                        ),
                        const SizedBox(height: 16),
                      ],
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('取消'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _confirm,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('确认'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 字段标题：单独一行，小号次要色。
class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// 输入框：灰底圆角、无边框，聚焦时显示主题色描边；
/// [isError] 为 true 时红色描边 + 浅红底，下方显示警告小字。
class _LabelTextField extends StatelessWidget {
  const _LabelTextField({
    required this.controller,
    required this.hintText,
    this.maxLines = 1,
    this.isError = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String hintText;
  final int? maxLines;
  final bool isError;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide.none,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 15),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(fontSize: 14, color: colorScheme.outline),
            filled: true,
            fillColor: isError
                ? colorScheme.errorContainer.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            border: border,
            enabledBorder: isError
                ? OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colorScheme.error,
                      width: 1.2,
                    ),
                  )
                : border,
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(
                color: isError ? colorScheme.error : colorScheme.primary,
                width: 1.4,
              ),
            ),
          ),
        ),
        if (isError && errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  size: 14,
                  color: colorScheme.error,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    errorText!,
                    style: TextStyle(fontSize: 12, color: colorScheme.error),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 只读内容容器，与输入框同一视觉风格，内容自适应多行、可选中复制。
class _ReadOnlyFieldBox extends StatelessWidget {
  const _ReadOnlyFieldBox({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontSize: 15, height: 1.4),
        child: child,
      ),
    );
  }
}
