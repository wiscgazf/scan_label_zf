import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sensors_plus/sensors_plus.dart';

import 'hand_stability_detector.dart';
import 'label_field_parser.dart';
import 'label_ocr_service.dart';
import 'label_scan_models.dart';

class LabelScannerPage extends StatefulWidget {
  const LabelScannerPage({
    super.key,
    required this.ocrService,
    this.openFilePicker = false,
  });

  final LabelOcrService ocrService;
  final bool openFilePicker;

  @override
  State<LabelScannerPage> createState() => _LabelScannerPageState();
}

class _LabelScannerPageState extends State<LabelScannerPage> {
  late final MobileScannerController _controller;
  final LabelFieldParser _parser = LabelFieldParser();
  bool _processing = false;
  String? _error;

  // 稳手拍摄：识别到二维码后先缓存最新帧，待手机稳定后再抓帧识别。
  final HandStabilityDetector _stabilityDetector = HandStabilityDetector();
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  Timer? _sensorUnavailableTimer;
  Timer? _fallbackCaptureTimer;
  BarcodeCapture? _pendingCapture;
  String? _pendingScanKey;
  bool _steadying = false;
  bool _receivedSensorData = false;
  bool _sensorUnavailable = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: !widget.openFilePicker,
      formats: [BarcodeFormat.qrCode],
      returnImage: true,
      // Android 默认预览分辨率只有 640x480，小字 OCR 需要更高的抓帧分辨率。
      cameraResolution: const Size(1920, 1080),
    );
    if (widget.openFilePicker) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_pickFile());
      });
    } else {
      _startStabilityMonitoring();
    }
  }

  String? _extractScanKey(BarcodeCapture? capture) {
    for (final barcode in capture?.barcodes ?? <Barcode>[]) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  void _restartCamera() {
    if (mounted && !_processing) unawaited(_controller.start());
  }

  void _handleError(String message) {
    if (!mounted) return;
    setState(() {
      _processing = false;
      _error = message;
      _clearPendingCapture();
    });
    _restartCamera();
    if (!widget.openFilePicker) {
      _stopStabilityMonitoring();
      _startStabilityMonitoring();
    }
  }

  void _clearPendingCapture() {
    _pendingCapture = null;
    _pendingScanKey = null;
    _steadying = false;
  }

  void _startStabilityMonitoring() {
    _stabilityDetector.reset();
    if (_sensorUnavailable) return;

    _accelerometerSubscription ??= accelerometerEventStream().listen(
      (event) {
        _receivedSensorData = true;
        if (_processing || !mounted) return;
        final stable = _stabilityDetector.addSample(
          event.x,
          event.y,
          event.z,
          DateTime.now(),
        );
        if (stable && _pendingCapture != null) {
          unawaited(_capturePendingFrame());
        }
      },
      onError: (_) => _fallbackToTimedCapture(),
    );
    _sensorUnavailableTimer ??= Timer(const Duration(seconds: 3), () {
      // 3 秒内没有任何加速度数据，视为无传感器设备（如部分模拟器），
      // 降级为识别到二维码后定时拍摄。
      if (!_receivedSensorData) _fallbackToTimedCapture();
    });
  }

  void _stopStabilityMonitoring() {
    unawaited(_accelerometerSubscription?.cancel());
    _accelerometerSubscription = null;
    _sensorUnavailableTimer?.cancel();
    _sensorUnavailableTimer = null;
    _fallbackCaptureTimer?.cancel();
    _fallbackCaptureTimer = null;
  }

  void _fallbackToTimedCapture() {
    if (_sensorUnavailable || !mounted) return;
    _sensorUnavailable = true;
    unawaited(_accelerometerSubscription?.cancel());
    _accelerometerSubscription = null;
    _sensorUnavailableTimer?.cancel();
    _sensorUnavailableTimer = null;
    if (_pendingCapture != null && !_processing) {
      _fallbackCaptureTimer ??= Timer(
        const Duration(milliseconds: 800),
        () => unawaited(_capturePendingFrame()),
      );
    }
  }

  Future<void> _capturePendingFrame() async {
    if (_processing || !mounted) return;
    final capture = _pendingCapture;
    final scanKey = _pendingScanKey;
    final image = capture?.image;
    if (capture == null || scanKey == null || image == null) return;

    setState(() {
      _processing = true;
      _error = null;
    });
    _stopStabilityMonitoring();

    File? file;
    try {
      await _controller.stop();
      file = File(
        '${Directory.systemTemp.path}/label_scan_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await file.writeAsBytes(image, flush: true);
      await _recognizeImage(file.path, scanKey);
    } catch (error) {
      _handleError('识别失败：$error');
    } finally {
      if (file != null && await file.exists()) await file.delete();
    }
  }

  Future<void> _recognizeImage(String imagePath, String scanKey) async {
    try {
      final regions = await widget.ocrService.recognize(imagePath);
      for (final region in regions) {
        debugPrint(
          '[label_scan] "${region.text}" '
          'L${region.left.toStringAsFixed(0)} T${region.top.toStringAsFixed(0)} '
          'R${region.right.toStringAsFixed(0)} B${region.bottom.toStringAsFixed(0)}',
        );
      }
      if (!mounted) return;

      final fields = _parser.parse(regions, scanKey: scanKey);
      debugPrint(
        '[label_scan] 解析结果: ${fields.map((key, value) => MapEntry(key.label, value))}',
      );
      Navigator.of(context).pop(
        LabelScanResult(
          key: scanKey,
          fields: fields,
          companyName: _parser.extractCompanyName(regions),
        ),
      );
    } catch (error) {
      _handleError('识别失败：$error');
    }
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_processing) return;

    final scanKey = _extractScanKey(capture);
    if (scanKey == null || capture.image == null) return;

    // 只缓存最新帧，不立即识别；等手机持稳后再取帧，避免手抖拍到模糊画面。
    _pendingCapture = capture;
    _pendingScanKey = scanKey;
    if (!_steadying) {
      setState(() {
        _steadying = true;
        _error = null;
      });
    }
    if (_sensorUnavailable) {
      // 无传感器设备：识别到二维码后稍等片刻（让自动对焦完成）再拍。
      _fallbackCaptureTimer ??= Timer(
        const Duration(milliseconds: 800),
        () => unawaited(_capturePendingFrame()),
      );
    }
  }

  Future<void> _recognizeNativeFile(PlatformFile file) async {
    final imagePath = file.path;
    if (imagePath == null || imagePath.isEmpty) {
      _handleError('未获取到图片路径，请重新选择');
      return;
    }

    final capture = await _controller.analyzeImage(
      imagePath,
      formats: [BarcodeFormat.qrCode],
    );
    final scanKey = _extractScanKey(capture);
    if (scanKey == null) {
      _handleError('所选图片中未识别到二维码，请选择清晰的标签图片');
      return;
    }
    await _recognizeImage(imagePath, scanKey);
  }

  Future<void> _pickFile() async {
    if (_processing) return;

    PlatformFile? file;
    try {
      file = await FilePicker.pickFile(
        dialogTitle: '选择标签图片',
        type: FileType.image,
      );
    } catch (error) {
      _handleError('选择文件失败：$error');
      return;
    }

    if (!mounted || file == null) {
      _restartCamera();
      return;
    }

    setState(() {
      _processing = true;
      _error = null;
    });

    try {
      await _controller.stop();
      await _recognizeNativeFile(file);
    } on MobileScannerBarcodeException {
      _handleError('所选图片中未识别到二维码，请选择清晰的标签图片');
    } on UnsupportedError catch (error) {
      _handleError(error.message?.toString() ?? '当前设备不支持选择图片识别');
    } catch (error) {
      _handleError('图片识别失败：$error');
    }
  }

  @override
  void dispose() {
    _stopStabilityMonitoring();
    unawaited(_controller.dispose());
    super.dispose();
  }

  String get _hintText {
    if (_steadying) {
      return _sensorUnavailable
          ? '已识别二维码，即将自动拍摄…'
          : '请持稳手机，稳定后自动拍摄，也可点击立即识别';
    }
    return '将标签完整置于取景框内，也可点击右上角选择标签图片';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('扫描标签二维码'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            onPressed: _processing ? null : () => unawaited(_pickFile()),
            tooltip: '选择文件识别',
            icon: const Icon(Icons.upload_file_outlined),
          ),
          IconButton(
            onPressed: _processing
                ? null
                : () => unawaited(_controller.toggleTorch()),
            icon: const Icon(Icons.flashlight_on_outlined),
          ),
          IconButton(
            onPressed: _processing
                ? null
                : () => unawaited(_controller.switchCamera()),
            icon: const Icon(Icons.cameraswitch_outlined),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _handleCapture),
          IgnorePointer(
            child: Center(
              child: Container(
                width: 300,
                height: 210,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _steadying ? Colors.orangeAccent : Colors.white,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          if (_processing)
            const ColoredBox(
              color: Color(0x99000000),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '正在识别标签字段…',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            left: 20,
            right: 20,
            bottom: 28,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_steadying && !_processing)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: FilledButton.icon(
                        onPressed: () => unawaited(_capturePendingFrame()),
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('立即识别'),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _error ?? _hintText,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _error == null
                            ? Colors.white
                            : Colors.orangeAccent,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
