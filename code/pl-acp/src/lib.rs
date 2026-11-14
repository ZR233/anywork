//! 外部 Agent 的 ACP 认证与业务会话协议边界。
//!
//! 该 crate 只消费宿主提供的受监督双向字节流，使用官方类型化请求、结果和回调。认证探测
//! 与业务会话租用宿主持有的同一连接。它不读取产品配置与凭据、不创建进程、不持有 Studio 产品表，
//! 不保存 transcript，也不自建 JSON-RPC 编解码：帧格式、路由与协议错误由官方 SDK 负责。
//!
//! 协议步骤、成功判定与取消语义见 `design/28-acp.md`；物理进程、管道消费与最终清理由
//! `pl-studio-runtime` 负责。

pub mod auth;
pub mod connection;
pub mod session;
