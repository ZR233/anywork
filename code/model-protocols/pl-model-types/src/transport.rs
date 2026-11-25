use serde::{Deserialize, Serialize};

/// 流式完成请求使用的连接方式。
///
/// 具体线协议声明支持的连接方式。
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConnectionMode {
    WebSocket,
    #[default]
    Http,
}

impl ConnectionMode {
    pub const fn label(self) -> &'static str {
        match self {
            Self::WebSocket => "web_socket",
            Self::Http => "http",
        }
    }
}
