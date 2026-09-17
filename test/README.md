# test/ — 测试

Flutter/Dart 测试目录：

- 单元测试：session 状态机、协议编解码、FFI 封装的 Dart 侧逻辑。
- Widget 测试：`lib/ui` 的关键页面与组件。
- 契约测试：针对 `docs/contracts/` 中各契约的本地桩（runtime C API、sync-api、ble-protocol）做模拟验证。

测试一律使用契约的模拟实现，不依赖真实硬件、真实 runtime 二进制或真实云端。
