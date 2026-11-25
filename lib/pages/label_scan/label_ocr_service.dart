import 'package:paddle_ocr_native/paddle_ocr_native.dart';

import 'label_scan_models.dart';

class LabelOcrService {
  final PaddleOcr _ocr = PaddleOcr();
  bool _initialized = false;

  Future<List<LabelOcrRegion>> recognize(String imagePath) async {
    if (!_initialized) {
      await _ocr.init(
        // 扫码返回的是完整相机帧，提高检测边长以保留标签上的小字；
        // 降低检测阈值，召回行尾单字符等弱得分的小字（如数量列的“1”）。
        config: const PaddleOcrConfig(
          detLimitSideLen: 1920,
          detThresh: 0.2,
          detBoxThresh: 0.3,
        ),
        engine: const EngineConfig(numThreads: 4),
      );
      _initialized = true;
    }

    final run = await _ocr.recognize(imagePath);
    return run.results.map((result) {
      final box = result.boundingBox;
      return LabelOcrRegion(
        text: result.text,
        left: box.left,
        top: box.top,
        right: box.right,
        bottom: box.bottom,
        confidence: result.confidence,
      );
    }).toList();
  }

  Future<void> dispose() => _ocr.dispose();
}
