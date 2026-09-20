import 'package:flutter_test/flutter_test.dart';
import 'package:hfr_probe/frame_stats.dart';

void main() {
  test('理想 240fps 流：无掉帧、实际帧率达标', () {
    final FrameStats stats = FrameStats(nominalFps: 240);
    const int nominalNs = 1000000000 ~/ 240;
    // 模拟 10 分钟 240fps = 144000 帧
    for (int i = 0; i < 144000; i++) {
      stats.addFrame(1000000 + i * nominalNs);
    }
    expect(stats.frameCount, 144000);
    expect(stats.droppedFrames, 0);
    expect(stats.actualFps, closeTo(240, 0.1));
    expect(stats.p50Ms, closeTo(1000 / 240, 0.2));
    expect(stats.maxIntervalMs, closeTo(1000 / 240, 0.2));
  });

  test('掉帧判定：帧间隔 > 1.5 倍标称间隔', () {
    final FrameStats stats = FrameStats(nominalFps: 240);
    const int nominalNs = 1000000000 ~/ 240;
    stats.addFrame(0);
    stats.addFrame(nominalNs); // 正常
    stats.addFrame(nominalNs * 3); // 间隔 2× 标称 → 掉帧
    stats.addFrame(nominalNs * 4); // 正常
    expect(stats.droppedFrames, 1);
    expect(stats.maxIntervalMs, closeTo(2 * nominalNs / 1e6, 0.01));
  });

  test('空流与单帧流不崩溃', () {
    final FrameStats stats = FrameStats(nominalFps: 240);
    expect(stats.actualFps, 0);
    expect(stats.p95Ms, 0);
    stats.addFrame(42);
    expect(stats.actualFps, 0);
    expect(stats.droppedFrames, 0);
  });
}
