//! 飞书协议适配。租户 token 对照官方 2026-10-14 OAuth v3 文档；
//! 注册与长连接字段及编码对照官方 Node SDK 1.76.0 与仓库 revision
//! `b188be60134d409b61259546bcf69c731d2b0b7c`。
//!
//! 协议来源许可：MIT License, Copyright (c) 2022 Lark Technologies Pte. Ltd.
//! 本模块只适配所需接口，不复制整个 SDK。

pub(crate) mod addons;
pub(crate) mod content;
pub(crate) mod endpoint;
pub(crate) mod error;
pub(crate) mod frame;
pub(crate) mod http;
pub(crate) mod im;
pub(crate) mod registration;
pub(crate) mod token;
pub(crate) mod ws;

pub const FEISHU_ACCOUNTS_HOST: &str = "accounts.feishu.cn";
pub const FEISHU_OPEN_API_HOST: &str = "https://open.feishu.cn";
pub const REGISTRATION_PATH: &str = "/oauth/v1/app/registration";
pub const WS_ENDPOINT_PATH: &str = "/callback/ws/endpoint";
pub const TENANT_TOKEN_PATH: &str = "/oauth/v3/token";
pub const IM_CHATS_PATH: &str = "/open-apis/im/v1/chats";
pub const IM_MESSAGES_PATH: &str = "/open-apis/im/v1/messages";
pub const IM_FILES_PATH: &str = "/open-apis/im/v1/files";
pub const BOT_INFO_PATH: &str = "/open-apis/bot/v3/info";

/// 完整消息 HTTP JSON（包含嵌套 content 的转义和目标/UUID）的保守 UTF-8 预算。
pub const POST_CONTENT_LIMIT_BYTES: usize = 30_000;
/// 通用 stream 文件上传的保守 30 MB 上限；平台不接受空文件。
pub const FILE_UPLOAD_LIMIT_BYTES: usize = 30_000_000;
/// 分包缓存过期（毫秒），对照官方 DataCache 的 10s。
pub const FRAGMENT_TTL_MS: u64 = 10_000;
/// 单事件最大分包数。
pub const MAX_EVENT_FRAGMENTS: usize = 64;
/// 单事件合并后最大字节。
pub const MAX_EVENT_BYTES: usize = 2 * 1024 * 1024;
/// 同时缓存的未完成事件上限。
pub const MAX_PENDING_EVENTS: usize = 32;
