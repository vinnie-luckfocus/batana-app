# hfr_probe — 240fps 高帧率采集探针（M0-V3 验证 spike）

验证 batana-app 的核心前置能力：**Flutter 应用在 iOS / Android 真机上稳定进行
240fps 相机采集，持续 10 分钟**。

本工程是 spike（探针），与正式应用代码（仓根 `lib/`）隔离，允许平台特定实现。

## 功能

- 枚举设备支持的高帧率采集档位并在 UI 列出：
  - iOS：AVFoundation `AVCaptureDevice.Format` 中 `maxFrameRate > 60`
    （视机型含 1080p240 / 720p240 等）；
  - Android：Camera2 `CONSTRAINED_HIGH_SPEED_VIDEO` 能力下的高速录像尺寸
    × 帧率区间（如 1280x720 @ 120/240fps）。
- 选定档位后开始采集，倒计时结束自动停止（1 / 5 / 10 分钟可选，默认 10 分钟，
  支持提前结束）。
- 实时统计：实际帧率、帧间隔抖动 p50 / p95 / max、掉帧数
  （帧间隔 > 1.5 × 标称间隔判定为掉帧）。
- 结束后生成报告页（通过/未达标结论 + 全量统计），可导出逐帧 CSV
  （系统分享面板，可存到文件/发送）。
- 可选"同时录像"：iOS 走 `AVCaptureMovieFileOutput` 落盘 `.mov`，
  Android 高速会话本身要求 MediaRecorder Surface，不勾选时录像文件结束后删除。

## 实现路线

`camera` 插件不支持高帧率格式枚举与锁帧，因此**平台通道直连原生 API**：

- MethodChannel `batana.hfr/methods`：`listFormats` / `startCapture` /
  `stopCapture`；
- EventChannel `batana.hfr/frames`：逐帧时间戳（纳秒，单调时钟）回传 Dart 统计：
  - iOS（`ios/Runner/HfrProbePlugin.swift`）：`AVCaptureVideoDataOutput`
    回调取 `CMSampleBufferGetPresentationTimeStamp`；
  - Android（`android/.../MainActivity.kt`）：受约束高速采集会话
    `setRepeatingBurst` + `CaptureResult.SENSOR_TIMESTAMP`。
    高速会话的目标 Surface 为 MediaRecorder（预览 Surface 需要原生视图，
    探针从简）。

Dart 侧统计与 UI 为纯 Dart（`lib/frame_stats.dart`、`lib/csv_exporter.dart`、
`lib/main.dart`），可单测；平台通道经 `HfrApi` 抽象注入，widget 测试用 fake 实现。

## 构建与真机运行

前置：Flutter 3.41+（本仓开发环境为 3.41.4 / Dart 3.11.1）。

```bash
cd spikes/hfr_probe
flutter pub get
flutter analyze   # 静态检查
flutter test      # 单元 + widget 冒烟测试
```

### iOS（Personal Team 即可）

1. `flutter build ios` 或用 Xcode 打开 `ios/Runner.xcworkspace`；
2. Xcode 中 Runner target → Signing & Capabilities → 勾选
   Automatically manage signing，Team 选个人 Apple ID（Personal Team）；
3. 首次安装到 iPhone 后，在 设置 → 通用 → VPN与设备管理 中信任开发者证书；
4. `flutter run -d <设备>` 或直接 Xcode Run。需要真机（模拟器无相机）。
   相机权限描述已写入 Info.plist（`NSCameraUsageDescription`）。

### Android

```bash
flutter run -d <设备>     # 开发者选项 + USB 调试
# 或
flutter build apk --debug && adb install build/app/outputs/flutter-apk/app-debug.apk
```

首次启动枚举档位时会弹相机权限请求。

## 通过标准（对应 M0-V3）

1. 选择 240fps 档位（1080p240 优先，无则 720p240），连续采集 10 分钟；
2. **通过**：报告页实际帧率 ≥ 228fps（标称的 95%）且掉帧占比 < 1%；
3. **不达**：改测 120fps 档同样 10 分钟，并记录两档的
   实际帧率 / p95 抖动 / 掉帧占比到 M0 验证记录，评估 240fps 可行性结论。

测试时建议：电量充足（HFR 采集耗电大）、关闭低电量模式、避免机身过热
（过热会触发系统降帧，这本身也是有价值的探针结论——报告里体现为掉帧上升）。

## 已知限制

- iOS 帧时间戳为样本呈现时间戳（主机时钟），Android 为 SENSOR_TIMESTAMP
  （传感器时钟）；两者都是单调时钟，适合做帧间隔统计，但跨平台数值不可直接对比。
- EventChannel 以 240Hz 向 Dart 回传时间戳，对探针足够；正式应用应考虑
  平台侧就地统计或批量回传。
- Android 部分机型高速档位仅 120fps 封顶，或高帧率下强制关闭 OIS/HDR，
  属平台限制，枚举结果即真机能力清单。
