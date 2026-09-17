# platform/ — 平台差异适配说明

记录 iOS / Android / macOS / Windows 四端的差异与适配策略（以文档为主，平台特定配置另行补充）：

## 240fps 高帧率相机通道

- **iOS**：AVFoundation `AVCaptureDeviceFormat` 需枚举支持 240fps 的格式（通常限 Slo-mo 档位与特定分辨率），并主动设置 `activeVideoMinFrameDuration`。
- **Android**：Camera2 `CONTROL_AE_AVAILABLE_TARGET_FPS_RANGES` / 高帧率 `StreamConfigurationMap.getHighSpeedVideoSizes()`，不同机型能力差异大，需运行时探测并降级。
- **macOS / Windows**：桌面端多为外接摄像头，帧率上限取决于设备；以运行时探测为准，不假设 240fps 可用。

## BLE 差异

- **iOS/macOS**：CoreBluetooth（flutter_blue_plus 等封装），后台模式需声明 `bluetooth-central`。
- **Android**：需 BLUETOOTH_SCAN / BLUETOOTH_CONNECT（Android 12+）及定位权限（低版本），扫描策略各厂商有差异。
- **Windows**：WinRT BLE API，能力受硬件与驱动影响，配对流程与移动端不同。

各端统一以 `lib/devices` 的抽象接口对外，平台差异只在本目录记录并在实现层收敛。
