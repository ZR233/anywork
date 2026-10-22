//! 外部 Agent 的 ACP 协商与认证协议边界。
//!
//! 该 crate 只消费宿主提供的受监督双向字节流，拥有 `initialize`、`authenticate` 与探测
//! 会话（`session/new`）的类型化请求结果。它不读取产品配置与凭据、不创建进程、不持有
//! Studio 状态，也不自建 JSON-RPC 编解码：帧格式、请求路由与协议错误由官方 SDK 负责。
//!
//! 协议步骤、成功判定与取消语义见 `design/28-acp.md`；物理进程、管道消费与最终清理由
//! `pl-studio-runtime` 负责。

pub mod auth;
