import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../l10n/app_localizations.dart';
import 'label_ocr_service.dart';
import 'label_records.dart';
import 'label_scan_models.dart';
import 'label_scan_theme.dart';
import 'label_scanner_page.dart';

OverlayEntry? _activeToastEntry;
Timer? _activeToastTimer;

/// 在距底部约 30% 的位置展示轻量提示，不会拦截触摸。
void showLabelScanToast(BuildContext context, String message) {
  _activeToastTimer?.cancel();
  _activeToastEntry?.remove();

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (overlayContext) {
      final colorScheme = Theme.of(overlayContext).colorScheme;
      return Positioned(
        bottom: MediaQuery.sizeOf(overlayContext).height * 0.3,
        left: 20,
        right: 20,
        child: IgnorePointer(
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 160),
            tween: Tween(begin: 0, end: 1),
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.translate(
                offset: Offset(0, 8 * (1 - value)),
                child: child,
              ),
            ),
            child: Center(
              child: Semantics(
                liveRegion: true,
                child: Material(
                  color: colorScheme.onSurface,
                  elevation: 6,
                  shadowColor: colorScheme.shadow.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 420),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: colorScheme.surface,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            message,
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.surface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
  _activeToastEntry = entry;
  Overlay.of(context, rootOverlay: true).insert(entry);
  _activeToastTimer = Timer(const Duration(seconds: 2), () {
    if (!identical(_activeToastEntry, entry)) return;
    entry.remove();
    _activeToastEntry = null;
    _activeToastTimer = null;
  });
}

class LabelScanPage extends StatefulWidget {
  const LabelScanPage({super.key});

  @override
  State<LabelScanPage> createState() => _LabelScanPageState();
}

class _LabelScanPageState extends State<LabelScanPage> {
  final LabelOcrService _ocrService = LabelOcrService();
  LabelScanResult? _lastResult;

  void _showLanguagePicker() {
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colorScheme = Theme.of(sheetContext).colorScheme;

        Widget buildLanguageTile({
          required IconData icon,
          required String label,
          required Locale locale,
        }) {
          final selected = appLocaleController.locale == locale;
          return ListTile(
            leading: Icon(
              icon,
              color: selected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: Text(label),
            trailing: selected
                ? Icon(Icons.check_circle, color: colorScheme.primary)
                : null,
            onTap: () {
              Navigator.of(sheetContext).pop();
              appLocaleController.setLocale(locale);
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    l10n.selectLanguage,
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                ),
              ),
              buildLanguageTile(
                icon: Icons.language,
                label: 'English',
                locale: const Locale('en'),
              ),
              buildLanguageTile(
                icon: Icons.translate,
                label: '中文',
                locale: const Locale('zh'),
              ),
            ],
          ),
        );
      },
    );
  }

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
    showLabelScanToast(context, AppLocalizations.of(context).fieldsConfirmed);
  }

  @override
  void dispose() {
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    final result = _lastResult;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.qr_code_scanner,
                size: 23,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.appTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => context.push('/records'),
            tooltip: l10n.manage,
            icon: const Icon(Icons.inventory_2_outlined, size: 20),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton(
              onPressed: _showLanguagePicker,
              tooltip: l10n.language,
              icon: const Icon(Icons.translate, size: 20),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final gutter = constraints.maxWidth >= 600 ? 32.0 : 20.0;
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(gutter, 32, gutter, 32),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildScanConsole(colorScheme),
                      const SizedBox(height: 24),
                      _buildWorkflowStrip(colorScheme),
                      if (result != null) ...[
                        const SizedBox(height: 24),
                        _buildRecentResultCard(result, colorScheme),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildScanConsole(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: LabelScanTheme.primaryDark.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            color: LabelScanTheme.primaryDark,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.qr_code_scanner,
                  size: 18,
                  color: LabelScanTheme.primarySoft,
                ),
                const SizedBox(width: 10),
                const Text(
                  'SCAN / OCR',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.4,
                    color: LabelScanTheme.primarySoft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        key: const ValueKey('home-offline-indicator'),
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: Color(0xFF75D6B0),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          l10n.offlineReady,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            color: colorScheme.primaryContainer.withValues(alpha: 0.22),
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const _HomeScanPreview(),
                const SizedBox(height: 20),
                SizedBox(
                  height: 60,
                  child: FilledButton.icon(
                    onPressed: () => _startScan(),
                    icon: const Icon(Icons.qr_code_scanner, size: 24),
                    label: Text(l10n.scan),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 56,
                  child: OutlinedButton.icon(
                    onPressed: () => _startScan(openFilePicker: true),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: colorScheme.surface,
                      side: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    icon: const Icon(Icons.upload_file_outlined, size: 22),
                    label: Text(l10n.chooseFile),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkflowStrip(ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: _WorkflowStep(number: '01', label: l10n.workflowPosition),
          ),
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: colorScheme.outlineVariant,
          ),
          Expanded(
            child: _WorkflowStep(number: '02', label: l10n.workflowOcr),
          ),
          Icon(
            Icons.arrow_forward,
            size: 16,
            color: colorScheme.outlineVariant,
          ),
          Expanded(
            child: _WorkflowStep(number: '03', label: l10n.workflowReview),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentResultCard(
    LabelScanResult result,
    ColorScheme colorScheme,
  ) {
    final name = result.fields[LabelFieldKey.name] ?? '';
    final code = result.fields[LabelFieldKey.materialCode] ?? '';
    return Card(
      elevation: 2,
      shadowColor: colorScheme.shadow.withValues(alpha: 0.12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: 18, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  AppLocalizations.of(context).recentScan,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              name.isEmpty
                  ? AppLocalizations.of(context).unnamedMaterial
                  : name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (code.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                code,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Text(
              AppLocalizations.of(context).rawKey,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            SelectableText(
              result.key,
              style: const TextStyle(fontSize: 13, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeScanPreview extends StatefulWidget {
  const _HomeScanPreview();

  @override
  State<_HomeScanPreview> createState() => _HomeScanPreviewState();
}

class _HomeScanPreviewState extends State<_HomeScanPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: double.infinity,
      height: 112,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) => CustomPaint(
          key: const ValueKey('home-scan-preview'),
          painter: HomeScanPainter(
            color: colorScheme.primary,
            progress: _controller.value,
          ),
          child: child,
        ),
        child: Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
            child: Icon(
              Icons.qr_code_scanner,
              size: 40,
              color: colorScheme.primary,
            ),
          ),
        ),
      ),
    );
  }
}

class HomeScanPainter extends CustomPainter {
  const HomeScanPainter({required this.color, required this.progress});

  final Color color;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = color.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var x = 0.0; x <= size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (var y = 0.0; y <= size.height; y += 24) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final frameWidth = size.width < 216 ? size.width : 216.0;
    final frame = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: frameWidth,
      height: 104,
    );
    final cornerPaint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    const length = 18.0;
    canvas
      ..drawLine(
        frame.topLeft,
        frame.topLeft + const Offset(length, 0),
        cornerPaint,
      )
      ..drawLine(
        frame.topLeft,
        frame.topLeft + const Offset(0, length),
        cornerPaint,
      )
      ..drawLine(
        frame.topRight,
        frame.topRight + const Offset(-length, 0),
        cornerPaint,
      )
      ..drawLine(
        frame.topRight,
        frame.topRight + const Offset(0, length),
        cornerPaint,
      )
      ..drawLine(
        frame.bottomLeft,
        frame.bottomLeft + const Offset(length, 0),
        cornerPaint,
      )
      ..drawLine(
        frame.bottomLeft,
        frame.bottomLeft + const Offset(0, -length),
        cornerPaint,
      )
      ..drawLine(
        frame.bottomRight,
        frame.bottomRight + const Offset(-length, 0),
        cornerPaint,
      )
      ..drawLine(
        frame.bottomRight,
        frame.bottomRight + const Offset(0, -length),
        cornerPaint,
      );

    final lineLeft = frame.left + 16;
    final lineRight = frame.right - 16;
    final lineY = frame.top + 12 + (frame.height - 24) * progress;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0.9),
          color.withValues(alpha: 0.25),
          color.withValues(alpha: 0),
        ],
        stops: const [0, 0.15, 0.5, 0.85, 1],
      ).createShader(Rect.fromLTRB(lineLeft, lineY, lineRight, lineY + 2))
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(lineLeft, lineY),
      Offset(lineRight, lineY),
      scanPaint,
    );
  }

  @override
  bool shouldRepaint(covariant HomeScanPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}

class _WorkflowStep extends StatelessWidget {
  const _WorkflowStep({required this.number, required this.label});

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            number,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colorScheme.primary,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

String _localizedFieldLabel(AppLocalizations l10n, LabelFieldKey key) {
  return switch (key) {
    LabelFieldKey.recommendedLocation => l10n.recommendedLocation,
    LabelFieldKey.materialCode => l10n.materialCode,
    LabelFieldKey.name => l10n.name,
    LabelFieldKey.specification => l10n.specification,
    LabelFieldKey.supplier => l10n.supplier,
    LabelFieldKey.quantity => l10n.quantity,
    LabelFieldKey.orderNumber => l10n.orderNumber,
    LabelFieldKey.cartonCount => l10n.cartonCount,
    LabelFieldKey.productionBatch => l10n.productionBatch,
    LabelFieldKey.deliveryDate => l10n.deliveryDate,
  };
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

  Widget _buildField(LabelFieldKey key) {
    final l10n = AppLocalizations.of(context);
    final label = _localizedFieldLabel(l10n, key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _FieldLabel(label),
          const SizedBox(height: 6),
          _LabelTextField(
            controller: _controllers[key]!,
            hintText: l10n.inputHint(label),
            maxLines: key == LabelFieldKey.specification ? 2 : 1,
            isError: _needsValue(key) && _controllers[key]!.text.trim().isEmpty,
            errorText: l10n.missingField(label),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldSection(String title, List<LabelFieldKey> keys) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldSectionTitle(title),
        const SizedBox(height: 12),
        for (final key in keys) _buildField(key),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // 键盘弹出时整体上移，避免输入框被遮挡。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.reviewTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (widget.result.companyName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.result.companyName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
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
                      _buildFieldSection(l10n.coreInfo, const [
                        LabelFieldKey.materialCode,
                        LabelFieldKey.name,
                        LabelFieldKey.specification,
                      ]),
                      const SizedBox(height: 8),
                      _buildFieldSection(l10n.supplyInventory, const [
                        LabelFieldKey.supplier,
                        LabelFieldKey.quantity,
                        LabelFieldKey.recommendedLocation,
                      ]),
                      const SizedBox(height: 8),
                      _buildFieldSection(l10n.orderBatch, const [
                        LabelFieldKey.orderNumber,
                        LabelFieldKey.cartonCount,
                        LabelFieldKey.productionBatch,
                        LabelFieldKey.deliveryDate,
                      ]),
                      const SizedBox(height: 8),
                      _FieldSectionTitle(l10n.rawQrContent),
                      const SizedBox(height: 12),
                      _ReadOnlyFieldBox(
                        child: SelectableText(widget.result.key),
                      ),
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
                          child: Text(l10n.cancel),
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
                          child: Text(l10n.confirm),
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

/// 分组标题：用短色条建立清晰的信息层级。
class _FieldSectionTitle extends StatelessWidget {
  const _FieldSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Container(
          width: 3,
          height: 16,
          decoration: BoxDecoration(
            color: colorScheme.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          text,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: colorScheme.primary,
          ),
        ),
      ],
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
                Icon(Icons.error_outline, size: 14, color: colorScheme.error),
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
