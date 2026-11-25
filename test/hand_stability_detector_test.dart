import 'package:flutter_test/flutter_test.dart';
import 'package:scan_label_zf/pages/label_scan/hand_stability_detector.dart';

void main() {
  final t0 = DateTime(2026, 11, 25, 10);

  test('首个样本无法判断，不视为稳定', () {
    final detector = HandStabilityDetector();
    expect(detector.addSample(0, 0, 9.8, t0), isFalse);
  });

  test('持续低抖动达到稳定时长后判定稳定', () {
    final detector = HandStabilityDetector();
    detector.addSample(0, 0, 9.8, t0);
    // 300ms 时还未到 500ms，不稳定。
    expect(
      detector.addSample(
        0.01,
        0,
        9.8,
        t0.add(const Duration(milliseconds: 100)),
      ),
      isFalse,
    );
    expect(
      detector.addSample(
        0,
        0.01,
        9.8,
        t0.add(const Duration(milliseconds: 300)),
      ),
      isFalse,
    );
    // 稳定时长从第一次低抖动（100ms）起算，600ms 时满足 500ms。
    expect(
      detector.addSample(
        0.01,
        0,
        9.81,
        t0.add(const Duration(milliseconds: 600)),
      ),
      isTrue,
    );
    // 持续稳定则持续返回 true。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 700))),
      isTrue,
    );
  });

  test('稳定前出现抖动会重新累计时长', () {
    final detector = HandStabilityDetector();
    detector.addSample(0, 0, 9.8, t0);
    detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 100)));
    // 400ms 时猛一晃（差值模长 > 0.35）。
    expect(
      detector.addSample(
        1.5,
        0.5,
        9.8,
        t0.add(const Duration(milliseconds: 400)),
      ),
      isFalse,
    );
    // 500ms 是晃动到静止的过渡帧，与上一帧差值仍大，视为抖动。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 500))),
      isFalse,
    );
    // 800ms 起持续低抖动，开始累计稳定时长。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 800))),
      isFalse,
    );
    // 1200ms 时累计 400ms 未满，仍不稳定。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 1200))),
      isFalse,
    );
    // 1400ms 时累计 600ms 已满 500ms，稳定。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 1400))),
      isTrue,
    );
  });

  test('稳定后再次抖动会变为不稳定', () {
    final detector = HandStabilityDetector(
      stableDuration: const Duration(milliseconds: 100),
    );
    detector.addSample(0, 0, 9.8, t0);
    // 200ms 首次低抖动，开始累计；350ms 时累计 150ms 已满 100ms。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 200))),
      isFalse,
    );
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(milliseconds: 350))),
      isTrue,
    );
    expect(
      detector.addSample(2, 0, 9.8, t0.add(const Duration(milliseconds: 400))),
      isFalse,
    );
  });

  test('自定义阈值与时长生效，reset 后重新累计', () {
    final detector = HandStabilityDetector(
      jitterThreshold: 2.0,
      stableDuration: const Duration(milliseconds: 50),
    );
    detector.addSample(0, 0, 9.8, t0);
    // 差值模长约 1.0 < 阈值 2.0，不视为抖动，60ms 起累计稳定时长。
    expect(
      detector.addSample(1, 0, 9.8, t0.add(const Duration(milliseconds: 60))),
      isFalse,
    );
    // 120ms 时累计 60ms 已满 50ms。
    expect(
      detector.addSample(1, 0, 9.8, t0.add(const Duration(milliseconds: 120))),
      isTrue,
    );

    detector.reset();
    // reset 后首个样本重新作为基准，不直接稳定。
    expect(
      detector.addSample(0, 0, 9.8, t0.add(const Duration(seconds: 1))),
      isFalse,
    );
  });
}
