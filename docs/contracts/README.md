# docs/contracts/ — 契约文档

batana-app 消费的外部契约（权威定义在司令塔仓库 [batana](https://github.com/vinnie-luckfocus/batana)，本目录为面向本仓库的引用与说明）：

- **session-schema**：打击会话记录的数据结构（采集元数据、结果、评价），`lib/session` 产出、`lib/sync` 传输均以此为准。
- **capabilities**：runtime 能力注册表格式，`lib/runtime` 在启动时读取，决定哪些分析能力可用。
- **runtime-api**：batana-runtime 的稳定 C API（函数签名、ABI 约定、生命周期），`dart:ffi` 封装的唯一依据。
- **ble-protocol**：与 batana-cap 的 BLE 通信协议（服务/特征 UUID、数据帧格式、时间同步）。
- **sync-api**：云同步 API（认证、上传/拉取、冲突处理），`lib/sync` 的实现依据。

契约变更以司令塔仓库为准；本仓库只消费契约，不自行扩展字段。
