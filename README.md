<p align="center">
  <img src="https://raw.githubusercontent.com/vinnie-luckfocus/batana/main/assets/logo.png" width="150" alt="Batana Logo">
</p>

# batana-app

**Batana 生态的跨平台移动 / 桌面应用**，覆盖 iOS / Android / macOS / Windows 四端，是棒球打击动作捕捉、分析与评价生态系统中面向用户的交互入口。

## 定位

- 跨平台移动 / 桌面应用：iOS、Android、macOS、Windows。
- 负责相机高帧率采集（目标 240fps）、BLE 连接 batana-cap、局域网发现 batana-pi、会话编排、结果展示与云同步。

## 边界

- **只做交互与编排**：采集调度、设备连接、UI、同步。
- **算法一律走 batana-runtime**：通过 `dart:ffi` 调用 runtime 的稳定 C API，本仓库不含任何算法实现。
- **不做服务端逻辑**：云端行为一律由 `sync-api` 契约定义，本仓库只实现客户端。

## 技术栈

- **Flutter 3.x / Dart 3.x**：一套代码覆盖四端。
- **dart:ffi**：调用 batana-runtime 的稳定 C API，并在启动时读取能力注册表（capabilities）按需降级。
- 选择 Flutter 的原因：相机高帧率通道与 BLE 生态在各端均较成熟，适合采集类应用。

## 与 batana-gui 的分工

| 仓库 | 定位 | 技术栈 |
| --- | --- | --- |
| **batana-app**（本仓库） | 移动 / 桌面跨平台应用（iOS / Android / macOS / Windows） | Flutter |
| [batana-gui](https://github.com/vinnie-luckfocus/batana-gui) | 嵌入式 GUI，配合 batana-pi 显示屏 | Qt6 |

## 消费的契约

本仓库消费以下契约（权威定义见司令塔仓库，本地说明见 `docs/contracts/`）：

- **session-schema**：打击会话记录数据结构
- **capabilities**：runtime 能力注册表
- **runtime-api**：batana-runtime 稳定 C API
- **ble-protocol**：与 batana-cap 的 BLE 通信协议
- **sync-api**：云同步 API

## 目录结构

```
lib/
  capture/    相机采集与编排（高帧率通道）
  session/    会话编排：采集 → runtime → 结果
  devices/    BLE 连接 batana-cap、局域网发现 batana-pi
  runtime/    dart:ffi 封装 batana-runtime C API、能力注册表读取
  sync/       云同步客户端（sync-api）
  ui/         页面与组件
platform/     平台差异适配说明（240fps 高帧率通道、BLE 差异）
spikes/       技术验证 spike（与正式代码隔离）
  hfr_probe/  M0-V3：240fps 高帧率采集探针（iOS/Android 真机）
test/         测试
docs/
  contracts/  契约文档
```

## 变更记录

| 版本 | 日期 | 变更内容 | 同步 |
| --- | --- | --- | --- |
| 0.1-draft | 2026-09-20 | 新增 M0-V3 验证 spike `spikes/hfr_probe/`：平台通道直连 AVFoundation/Camera2 枚举高帧率档位、10 分钟采集统计（实际帧率/抖动 p50·p95·max/掉帧）、报告页 + CSV 导出；本机 `flutter test` 5 项全绿、`flutter analyze` 无问题；真机 240fps 实测待手机验证 | 待同步司令塔 repos.yaml |

## 生态与司令塔

batana-app 是 Batana 多仓库生态的一员，司令塔仓库：[vinnie-luckfocus/batana](https://github.com/vinnie-luckfocus/batana)

- 总体架构：[docs/architecture.md](https://github.com/vinnie-luckfocus/batana/blob/main/docs/architecture.md)
- 路线图：[docs/roadmap.md](https://github.com/vinnie-luckfocus/batana/blob/main/docs/roadmap.md)

## 许可证

见 [LICENSE](LICENSE)。
