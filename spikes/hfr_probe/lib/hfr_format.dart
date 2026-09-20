/// 高帧率采集档位描述。
///
/// 由平台通道返回：
/// - iOS：AVFoundation `AVCaptureDevice.Format` 中 maxFrameRate > 60 的格式；
/// - Android：Camera2 受约束高速录像（CONSTRAINED_HIGH_SPEED_VIDEO）支持的
///   尺寸与帧率区间组合。
class HfrFormat {
  const HfrFormat({
    required this.id,
    required this.width,
    required this.height,
    required this.minFps,
    required this.maxFps,
    required this.platform,
  });

  /// 平台侧用于回选格式的标识（索引或编码串）。
  final String id;
  final int width;
  final int height;
  final double minFps;
  final double maxFps;

  /// 'ios' 或 'android'。
  final String platform;

  String get label => '${width}x$height @ ${maxFps.round()}fps';

  factory HfrFormat.fromMap(Map<dynamic, dynamic> map) {
    return HfrFormat(
      id: map['id'] as String,
      width: (map['width'] as num).toInt(),
      height: (map['height'] as num).toInt(),
      minFps: (map['minFps'] as num).toDouble(),
      maxFps: (map['maxFps'] as num).toDouble(),
      platform: map['platform'] as String? ?? 'unknown',
    );
  }
}
