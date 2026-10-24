//! 扫码注册 `addons` 编码。官方管道为 JSON → gzip → base64url（去 padding）。
//! 对照 `scene/registration/addons.ts`。使用 flate2，不自写压缩器。

use super::error::{FeishuError, FeishuErrorKind};
use base64::Engine;
use flate2::Compression;
use flate2::write::GzEncoder;
use serde::Serialize;
use std::io::Write;

#[derive(Serialize)]
struct RegistrationAddons<'a> {
    preset: bool,
    scopes: RegistrationScopes<'a>,
    events: RegistrationEvents<'a>,
}

#[derive(Serialize)]
struct RegistrationScopes<'a> {
    tenant: &'a [&'a str],
}

#[derive(Serialize)]
struct RegistrationEvents<'a> {
    items: RegistrationEventItems<'a>,
}

#[derive(Serialize)]
struct RegistrationEventItems<'a> {
    tenant: &'a [&'a str],
}

/// 首版最小权限模板：`preset:false` + 应用身份 tenant scopes。
/// 覆盖发送、单聊/群提及接收、会话目录与按需历史；不申请通用 `im:message`
/// 或读取全部群消息。
const TENANT_SCOPES: &[&str] = &[
    "im:message:send_as_bot",
    "im:message.p2p_msg:readonly",
    "im:message.group_at_msg:readonly",
    "im:chat:readonly",
    "im:message:readonly",
    "im:resource:upload",
];
const TENANT_EVENTS: &[&str] = &["im.message.receive_v1"];

pub fn encode_registration_addons() -> Result<String, FeishuError> {
    let payload = RegistrationAddons {
        preset: false,
        scopes: RegistrationScopes {
            tenant: TENANT_SCOPES,
        },
        events: RegistrationEvents {
            items: RegistrationEventItems {
                tenant: TENANT_EVENTS,
            },
        },
    };
    let json = serde_json::to_vec(&payload).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("failed to encode registration addons: {error}"),
            false,
            None,
        )
    })?;
    let mut encoder = GzEncoder::new(Vec::new(), Compression::default());
    encoder.write_all(&json).map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("failed to gzip registration addons: {error}"),
            false,
            None,
        )
    })?;
    let compressed = encoder.finish().map_err(|error| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            format!("failed to finish gzip registration addons: {error}"),
            false,
            None,
        )
    })?;
    Ok(base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(compressed))
}
