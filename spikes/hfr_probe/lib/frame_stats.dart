import 'dart:math' as math;

/// 帧时间戳流统计。
///
/// 输入为每帧的单调时间戳（纳秒），统计实际帧率、帧间隔抖动与掉帧数。
/// 掉帧判定：帧间隔 > 1.5 × 标称帧间隔（1e9 / nominalFps 纳秒）。
class FrameStats {
  FrameStats({required this.nominalFps});

  /// 标称帧率（选定档位的目标 fps）。
  final double nominalFps;

  /// 单调递增的帧时间戳（纳秒）。
  final List<int> timestampsNs = <int>[];

  int _droppedFrames = 0;

  double get nominalIntervalNs => 1e9 / nominalFps;

  int get frameCount => timestampsNs.length;

  /// 掉帧数（帧间隔超过 1.5 倍标称间隔的帧数）。
  int get droppedFrames => _droppedFrames;

  void addFrame(int tsNs) {
    if (timestampsNs.isNotEmpty) {
      final int interval = tsNs - timestampsNs.last;
      if (interval > 1.5 * nominalIntervalNs) {
        _droppedFrames++;
      }
    }
    timestampsNs.add(tsNs);
  }

  void reset() {
    timestampsNs.clear();
    _droppedFrames = 0;
  }

  /// 帧间隔序列（毫秒）。
  List<double> get intervalsMs {
    if (timestampsNs.length < 2) return const <double>[];
    final List<double> result = List<double>.filled(timestampsNs.length - 1, 0);
    for (int i = 1; i < timestampsNs.length; i++) {
      result[i - 1] = (timestampsNs[i] - timestampsNs[i - 1]) / 1e6;
    }
    return result;
  }

  /// 实际平均帧率（基于首末帧时间差）。
  double get actualFps {
    if (timestampsNs.length < 2) return 0;
    final double elapsedSec =
        (timestampsNs.last - timestampsNs.first) / 1e9;
    if (elapsedSec <= 0) return 0;
    return (timestampsNs.length - 1) / elapsedSec;
  }

  /// 帧间隔分位数（毫秒）。q 取值 [0, 1]。
  double intervalPercentileMs(double q) {
    final List<double> intervals = intervalsMs;
    if (intervals.isEmpty) return 0;
    final List<double> sorted = List<double>.of(intervals)..sort();
    final double pos = q * (sorted.length - 1);
    final int lower = pos.floor();
    final int upper = math.min(lower + 1, sorted.length - 1);
    final double frac = pos - lower;
    return sorted[lower] * (1 - frac) + sorted[upper] * frac;
  }

  double get p50Ms => intervalPercentileMs(0.50);
  double get p95Ms => intervalPercentileMs(0.95);
  double get maxIntervalMs {
    final List<double> intervals = intervalsMs;
    if (intervals.isEmpty) return 0;
    return intervals.reduce(math.max);
  }

  /// 掉帧占比（0-1）。
  double get dropRatio =>
      frameCount > 1 ? _droppedFrames / (frameCount - 1) : 0;
}
