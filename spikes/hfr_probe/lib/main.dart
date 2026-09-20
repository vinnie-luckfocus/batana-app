import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'csv_exporter.dart';
import 'frame_stats.dart';
import 'hfr_channel.dart';
import 'hfr_format.dart';

void main() {
  runApp(const HfrProbeApp());
}

class HfrProbeApp extends StatelessWidget {
  const HfrProbeApp({super.key, HfrApi? api}) : api = api ?? const _DefaultApi();

  final HfrApi api;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HFR 采集探针',
      theme: ThemeData.dark(useMaterial3: true),
      home: FormatListPage(api: api),
    );
  }
}

class _DefaultApi extends HfrChannel {
  const _DefaultApi();
}

/// 档位列表页：枚举设备支持的高帧率格式，选择时长与是否录像后开始采集。
class FormatListPage extends StatefulWidget {
  const FormatListPage({super.key, required this.api});

  final HfrApi api;

  @override
  State<FormatListPage> createState() => _FormatListPageState();
}

class _FormatListPageState extends State<FormatListPage> {
  List<HfrFormat>? _formats;
  String? _error;
  Duration _duration = const Duration(minutes: 10);
  bool _record = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final List<HfrFormat> formats = await widget.api.listFormats();
      setState(() {
        _formats = formats;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HFR 采集探针')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                const Text('采集时长:'),
                for (final int m in <int>[1, 5, 10])
                  ChoiceChip(
                    label: Text('$m 分钟'),
                    selected: _duration.inMinutes == m,
                    onSelected: (_) =>
                        setState(() => _duration = Duration(minutes: m)),
                  ),
                FilterChip(
                  label: const Text('同时录像'),
                  selected: _record,
                  onSelected: (bool v) => setState(() => _record = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('枚举失败：$_error', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final List<HfrFormat>? formats = _formats;
    if (formats == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (formats.isEmpty) {
      return const Center(child: Text('未发现高帧率（>60fps）采集档位'));
    }
    return ListView.builder(
      itemCount: formats.length,
      itemBuilder: (BuildContext context, int i) {
        final HfrFormat f = formats[i];
        return Card(
          child: ListTile(
            title: Text(f.label),
            subtitle: Text(
                'fps 区间 ${f.minFps.round()}-${f.maxFps.round()} · ${f.platform}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CapturePage(
                  api: widget.api,
                  format: f,
                  duration: _duration,
                  record: _record,
                ),
              ));
            },
          ),
        );
      },
    );
  }
}

/// 采集页：倒计时 + 实时统计（实际帧率 / 抖动 p50·p95·max / 掉帧数）。
class CapturePage extends StatefulWidget {
  const CapturePage({
    super.key,
    required this.api,
    required this.format,
    required this.duration,
    required this.record,
  });

  final HfrApi api;
  final HfrFormat format;
  final Duration duration;
  final bool record;

  @override
  State<CapturePage> createState() => _CapturePageState();
}

class _CapturePageState extends State<CapturePage> {
  late final FrameStats _stats;
  StreamSubscription<int>? _sub;
  Timer? _ticker;
  late int _remainingSec;
  late DateTime _startedAt;
  String? _error;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _stats = FrameStats(nominalFps: widget.format.maxFps);
    _remainingSec = widget.duration.inSeconds;
    _startedAt = DateTime.now();
    _start();
  }

  Future<void> _start() async {
    try {
      _sub = widget.api.frameTimestamps().listen(
        (int ts) => _stats.addFrame(ts),
        onError: (Object e) => setState(() => _error = '$e'),
      );
      await widget.api.startCapture(widget.format, record: widget.record);
      _ticker = Timer.periodic(const Duration(seconds: 1), (Timer t) {
        if (!mounted) return;
        setState(() => _remainingSec--);
        if (_remainingSec <= 0) _finish();
      });
    } catch (e) {
      setState(() => _error = '$e');
    }
  }

  Future<void> _finish() async {
    if (_finishing) return;
    _finishing = true;
    _ticker?.cancel();
    // 先停采集再释放订阅；取消订阅不等待，避免阻塞收尾。
    final StreamSubscription<int>? sub = _sub;
    _sub = null;
    Map<String, dynamic> summary = const <String, dynamic>{};
    try {
      summary = await widget.api.stopCapture();
    } catch (_) {}
    unawaited(sub?.cancel());
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => ReportPage(
        format: widget.format,
        stats: _stats,
        elapsed: DateTime.now().difference(_startedAt),
        videoPath: summary['videoPath'] as String?,
      ),
    ));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final int mm = _remainingSec ~/ 60;
    final int ss = _remainingSec % 60;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: Text('采集中 · ${widget.format.label}')),
        body: Center(
          child: _error != null
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('采集失败：$_error', textAlign: TextAlign.center),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      '$mm:${ss.toString().padLeft(2, '0')}',
                      style: Theme.of(context).textTheme.displayLarge,
                    ),
                    const SizedBox(height: 24),
                    _stat('帧数', '${_stats.frameCount}'),
                    _stat('实际帧率',
                        '${_stats.actualFps.toStringAsFixed(1)} fps'),
                    _stat(
                        '抖动 p50 / p95 / max',
                        '${_stats.p50Ms.toStringAsFixed(2)} / '
                            '${_stats.p95Ms.toStringAsFixed(2)} / '
                            '${_stats.maxIntervalMs.toStringAsFixed(2)} ms'),
                    _stat('掉帧数', '${_stats.droppedFrames}'),
                    const SizedBox(height: 32),
                    FilledButton.tonal(
                      onPressed: _finish,
                      child: const Text('提前结束'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _stat(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text('$name：$value', style: const TextStyle(fontSize: 16)),
    );
  }
}

/// 报告页：汇总统计并支持导出 CSV（分享/存储）。
class ReportPage extends StatelessWidget {
  const ReportPage({
    super.key,
    required this.format,
    required this.stats,
    required this.elapsed,
    this.videoPath,
  });

  final HfrFormat format;
  final FrameStats stats;
  final Duration elapsed;
  final String? videoPath;

  bool get _passed =>
      stats.actualFps >= format.maxFps * 0.95 && stats.dropRatio < 0.01;

  Future<void> _exportCsv() async {
    final String csv =
        buildCsv(format: format, stats: stats, elapsed: elapsed);
    final String path =
        '${Directory.systemTemp.path}/hfr_report_${DateTime.now().millisecondsSinceEpoch}.csv';
    await File(path).writeAsString(csv);
    await SharePlus.instance.share(ShareParams(
      files: <XFile>[XFile(path)],
      subject: 'HFR 采集报告',
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('采集报告')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Card(
            color: _passed ? Colors.green.shade900 : Colors.red.shade900,
            child: ListTile(
              title: Text(_passed ? '通过：帧率达标且掉帧 < 1%' : '未达标：请降档复测'),
              subtitle: Text(format.label),
            ),
          ),
          const SizedBox(height: 12),
          _row('采集时长', '${elapsed.inSeconds} s'),
          _row('帧数', '${stats.frameCount}'),
          _row('实际帧率', '${stats.actualFps.toStringAsFixed(2)} fps'),
          _row('帧间隔 p50', '${stats.p50Ms.toStringAsFixed(3)} ms'),
          _row('帧间隔 p95', '${stats.p95Ms.toStringAsFixed(3)} ms'),
          _row('帧间隔 max', '${stats.maxIntervalMs.toStringAsFixed(3)} ms'),
          _row('掉帧数', '${stats.droppedFrames}'),
          _row('掉帧占比', '${(stats.dropRatio * 100).toStringAsFixed(3)} %'),
          if (videoPath != null) _row('录像文件', videoPath!),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _exportCsv,
            icon: const Icon(Icons.ios_share),
            label: const Text('导出 CSV（分享/保存）'),
          ),
        ],
      ),
    );
  }

  Widget _row(String name, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(name),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
