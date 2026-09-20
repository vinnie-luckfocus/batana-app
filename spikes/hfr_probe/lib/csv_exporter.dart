import 'frame_stats.dart';
import 'hfr_format.dart';

/// 生成采集报告 CSV：头部为摘要注释行，正文为逐帧时间戳与帧间隔。
String buildCsv({
  required HfrFormat format,
  required FrameStats stats,
  required Duration elapsed,
}) {
  final StringBuffer buf = StringBuffer();
  buf.writeln('# batana hfr_probe 采集报告');
  buf.writeln('# 档位, ${format.label} (${format.platform})');
  buf.writeln('# 采集时长(s), ${elapsed.inSeconds}');
  buf.writeln('# 帧数, ${stats.frameCount}');
  buf.writeln('# 实际帧率(fps), ${stats.actualFps.toStringAsFixed(2)}');
  buf.writeln('# 帧间隔 p50(ms), ${stats.p50Ms.toStringAsFixed(3)}');
  buf.writeln('# 帧间隔 p95(ms), ${stats.p95Ms.toStringAsFixed(3)}');
  buf.writeln('# 帧间隔 max(ms), ${stats.maxIntervalMs.toStringAsFixed(3)}');
  buf.writeln('# 掉帧数, ${stats.droppedFrames}');
  buf.writeln('# 掉帧占比, ${(stats.dropRatio * 100).toStringAsFixed(3)}%');
  buf.writeln('frame_index,timestamp_ns,interval_ms,dropped');
  final double nominalNs = stats.nominalIntervalNs;
  for (int i = 0; i < stats.timestampsNs.length; i++) {
    if (i == 0) {
      buf.writeln('0,${stats.timestampsNs[0]},,0');
      continue;
    }
    final int interval = stats.timestampsNs[i] - stats.timestampsNs[i - 1];
    final int dropped = interval > 1.5 * nominalNs ? 1 : 0;
    buf.writeln(
        '$i,${stats.timestampsNs[i]},${(interval / 1e6).toStringAsFixed(3)},$dropped');
  }
  return buf.toString();
}
