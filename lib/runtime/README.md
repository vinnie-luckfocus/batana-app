# lib/runtime — batana-runtime FFI 封装

通过 `dart:ffi` 封装 batana-runtime 的稳定 C API（契约见 `docs/contracts/runtime-api`）：

- 动态加载 runtime 原生库，管理其生命周期（初始化/释放）。
- 将 C API 包装为符合 Dart 习惯的类型安全接口，对上层（`lib/session`）隐藏 FFI 细节。
- 读取**能力注册表**（capabilities）：启动时探测 runtime 编译进哪些算法能力（如姿态估计、挥杆评价），供 UI 与会话编排按能力降级。

本目录是本仓库中唯一允许与原生代码直接交互的位置；不含任何算法实现。
