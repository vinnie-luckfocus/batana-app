# lib/ui — 页面与组件

Flutter 页面与可复用组件层：

- 采集页、回放/分析结果页、历史会话列表、设备管理页等页面。
- 可复用组件（挥杆轨迹可视化、评分卡片、设备状态指示等）。
- 适配 iOS / Android / macOS / Windows 四端的响应式布局。

UI 层只负责展示与交互，数据一律经由 `lib/session` / `lib/runtime` / `lib/sync` 获取，不直接触碰采集、FFI 或网络。
