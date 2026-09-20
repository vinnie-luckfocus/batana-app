import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hfr_probe/hfr_channel.dart';
import 'package:hfr_probe/hfr_format.dart';
import 'package:hfr_probe/main.dart';

/// 假平台通道：不触达原生层，直接喂固定档位与理想 240fps 帧流。
class FakeHfrApi implements HfrApi {
  final StreamController<int> frames = StreamController<int>();

  static const HfrFormat format240 = HfrFormat(
    id: '0',
    width: 1280,
    height: 720,
    minFps: 120,
    maxFps: 240,
    platform: 'test',
  );

  @override
  Future<List<HfrFormat>> listFormats() async => const <HfrFormat>[format240];

  @override
  Future<void> startCapture(HfrFormat format, {bool record = false}) async {
    const int nominalNs = 1000000000 ~/ 240;
    for (int i = 0; i < 2400; i++) {
      frames.add(i * nominalNs);
    }
  }

  @override
  Future<Map<String, dynamic>> stopCapture() async => <String, dynamic>{};

  @override
  Stream<int> frameTimestamps() => frames.stream;
}

void main() {
  testWidgets('冒烟：档位列表 → 采集 → 报告', (WidgetTester tester) async {
    final FakeHfrApi api = FakeHfrApi();
    await tester.pumpWidget(HfrProbeApp(api: api));
    await tester.pumpAndSettle();

    // 档位列表
    expect(find.text('1280x720 @ 240fps'), findsOneWidget);

    // 进入采集页（注意：采集页有周期计时器，期间不能用 pumpAndSettle）
    await tester.tap(find.text('1280x720 @ 240fps'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining('采集中'), findsOneWidget);

    // 等待帧流进入并刷新统计
    await tester.pump(const Duration(seconds: 2));
    expect(find.textContaining('实际帧率'), findsOneWidget);

    // 提前结束 → 报告页（先推进若干帧完成收尾与转场，再 settle）
    await tester.tap(find.text('提前结束'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(find.text('采集报告'), findsOneWidget);
    expect(find.textContaining('fps'), findsWidgets);

    // 注意：不能 await frames.close()——其完成经 FakeAsync 域内微任务/定时器调度，
    // 测试体内裸 await 且不再 pump 会永久挂起（fake-async 死锁）。关闭仅作清理，不等待。
    unawaited(api.frames.close());
  });
}
