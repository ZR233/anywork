//! Frozen bot ownership of native sessions.

use anyhow::{Result, bail};
use pl_core::{context::OpaquePayload, thread::ThreadSnapshot};

pub(crate) const BOT_OWNER_EXTENSION: &str = "studio.bot-owner";

pub(crate) fn encode_bot_owner(bot_id: &str) -> Result<OpaquePayload> {
    Ok(OpaquePayload::new(
        "pl.studio.bot-owner",
        1,
        serde_json::to_string(bot_id)?,
    )?)
}

pub(crate) fn bot_owner(state: &ThreadSnapshot) -> Result<Option<String>> {
    state
        .extensions
        .get(BOT_OWNER_EXTENSION)
        .map(|value| {
            anyhow::ensure!(
                value.payload.format() == "pl.studio.bot-owner" && value.payload.version() == 1,
                "unsupported bot owner encoding"
            );
            Ok(serde_json::from_str(value.payload.content())?)
        })
        .transpose()
}

/// 合并运行期绑定与该会话已冻结的 owner 事实。
///
/// 两个来源都按当前格式版本解码，并用 bot 模块的 canonical 校验器验证 bot ID；两者同时
/// 存在时必须指向同一个 bot。读取失败、ID 非法或冲突都返回错误，绝不以“扩展存在”或
/// “没有绑定”推断渠道。
pub(crate) fn verified_bot_owner(
    live: Option<&str>,
    saved: Option<&ThreadSnapshot>,
) -> Result<Option<String>> {
    let frozen = saved.map(bot_owner).transpose()?.flatten();
    if let Some(bot_id) = &frozen {
        crate::bots::validate_bot_id(bot_id)
            .map_err(|error| anyhow::anyhow!("invalid saved bot ownership `{bot_id}`: {error}"))?;
    }
    if let Some(bot_id) = live {
        crate::bots::validate_bot_id(bot_id)
            .map_err(|error| anyhow::anyhow!("invalid active bot binding `{bot_id}`: {error}"))?;
    }
    match (live, frozen) {
        (Some(live), Some(frozen)) if live != frozen => {
            bail!("saved bot ownership conflicts with the active bot binding")
        }
        (Some(live), _) => Ok(Some(live.to_owned())),
        (None, frozen) => Ok(frozen),
    }
}

#[cfg(test)]
#[path = "bot_owner_tests.rs"]
mod tests;
