import 'package:flutter_test/flutter_test.dart';
import 'package:hfr_probe/csv_exporter.dart';
import 'package:hfr_probe/frame_stats.dart';
import 'package:hfr_probe/hfr_format.dart';

void main() {
  test('CSV 包含摘要与逐帧行', () {
    const HfrFormat format = HfrFormat(
      id: '0',
      width: 1280,
      height: 720,
      minFps: 120,
      maxFps: 240,
      platform: 'ios',
    );
    final FrameStats stats = FrameStats(nominalFps: 240);
    const int nominalNs = 1000000000 ~/ 240;
    for (int i = 0; i < 100; i++) {
      stats.addFrame(i * nominalNs);
    }
    final String csv =
        buildCsv(format: format, stats: stats, elapsed: const Duration(seconds: 1));
    expect(csv, contains('实际帧率(fps)'));
    expect(csv, contains('frame_index,timestamp_ns,interval_ms,dropped'));
    // 100 帧 → 100 行数据
    final int rows = csv
        .split('\n')
        .where((String l) => l.isNotEmpty && !l.startsWith('#'))
        .length -
        1;
    expect(rows, 100);
  });
}
