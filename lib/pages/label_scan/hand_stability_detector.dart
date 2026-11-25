import 'dart:math' as math;

/// 手持稳定检测：根据加速度计相邻采样的变化幅度判断手机是否持稳。
///
/// 纯逻辑实现，时间戳由外部传入，便于单元测试；
/// 扫码页在检测到二维码后，等检测器判定稳定再抓帧，避免手抖拍到模糊画面。
class HandStabilityDetector {
  HandStabilityDetector({
    this.jitterThreshold = 0.35,
    this.stableDuration = const Duration(milliseconds: 500),
  });

  /// 相邻两次加速度采样的差值模长（m/s²）超过该值视为抖动。
  final double jitterThreshold;

  /// 持续无抖动达到该时长才判定为稳定。
  final Duration stableDuration;

  double? _lastX;
  double? _lastY;
  double? _lastZ;
  DateTime? _stableSince;

  /// 喂入一次加速度采样，返回此刻是否已达到稳定。
  ///
  /// 首个样本无法计算变化量，直接返回 false；
  /// 一旦出现抖动会重新累计稳定时长。
  bool addSample(double x, double y, double z, DateTime time) {
    final lastX = _lastX;
    final lastY = _lastY;
    final lastZ = _lastZ;
    _lastX = x;
    _lastY = y;
    _lastZ = z;
    if (lastX == null) return false;

    final jitter = math.sqrt(
      math.pow(x - lastX, 2) +
          math.pow(y - lastY!, 2) +
          math.pow(z - lastZ!, 2),
    );
    if (jitter > jitterThreshold) {
      _stableSince = null;
      return false;
    }
    final since = _stableSince ??= time;
    return time.difference(since) >= stableDuration;
  }

  void reset() {
    _lastX = _lastY = _lastZ = null;
    _stableSince = null;
  }
}
