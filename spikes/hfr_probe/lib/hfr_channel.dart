import 'package:flutter/services.dart';

import 'hfr_format.dart';

/// 高帧率采集的平台能力抽象，便于在测试中注入 fake 实现。
abstract class HfrApi {
  /// 枚举设备支持的高帧率采集档位。
  Future<List<HfrFormat>> listFormats();

  /// 以指定档位开始采集，帧时间戳经 [frameTimestamps] 流回传。
  Future<void> startCapture(HfrFormat format, {bool record = false});

  /// 停止采集。返回平台侧摘要（帧数、录像文件路径等）。
  Future<Map<String, dynamic>> stopCapture();

  /// 帧时间戳流（纳秒，单调时钟）。
  Stream<int> frameTimestamps();
}

/// 基于 MethodChannel / EventChannel 的平台通道实现。
///
/// - iOS：AVFoundation 高帧率格式 + AVCaptureVideoDataOutput 帧回调；
/// - Android：Camera2 受约束高速采集会话，逐帧 SENSOR_TIMESTAMP 回传。
class HfrChannel implements HfrApi {
  const HfrChannel();

  static const MethodChannel _methods = MethodChannel('batana.hfr/methods');
  static const EventChannel _frames = EventChannel('batana.hfr/frames');

  @override
  Future<List<HfrFormat>> listFormats() async {
    final List<dynamic>? result =
        await _methods.invokeMethod<List<dynamic>>('listFormats');
    if (result == null) return const <HfrFormat>[];
    return result
        .map((dynamic e) => HfrFormat.fromMap(e as Map<dynamic, dynamic>))
        .toList();
  }

  @override
  Future<void> startCapture(HfrFormat format, {bool record = false}) {
    return _methods.invokeMethod<void>('startCapture', <String, dynamic>{
      'formatId': format.id,
      'targetFps': format.maxFps,
      'record': record,
    });
  }

  @override
  Future<Map<String, dynamic>> stopCapture() async {
    final Map<dynamic, dynamic>? result =
        await _methods.invokeMethod<Map<dynamic, dynamic>>('stopCapture');
    return result?.cast<String, dynamic>() ?? const <String, dynamic>{};
  }

  @override
  Stream<int> frameTimestamps() {
    return _frames.receiveBroadcastStream().map((dynamic e) {
      return (e as num).toInt();
    });
  }
}
