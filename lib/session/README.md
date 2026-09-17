# lib/session — 会话编排

一次打击分析会话的编排核心，串联完整链路：

1. 采集：调用 `lib/capture` 获取帧序列，并接入 `lib/devices` 的传感器数据。
2. 分析：通过 `lib/runtime` 把数据送入 batana-runtime，按 `capabilities` 契约探测可用能力。
3. 结果：接收 runtime 的分析/评价结果，产出符合 `session-schema` 契约的会话记录。
4. 持久化与同步：本地保存，并交由 `lib/sync` 上报云端。

本目录只做编排与状态机，不实现算法、不直接操作相机与网络底层。
