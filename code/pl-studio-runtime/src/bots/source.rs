//! Current identity/trust checks shared by retained finite replies and auxiliary inbound notices.
//! The obsolete source-only model file capability is gone; these checks do not grant frontend
//! authority, which is independently fenced by the audience owner.

use super::config::BotConfigFile;
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::send::SendSource;

/// A finite legacy reply may have distinct creation and Thread IDs. Its actual binding and worker
/// lease are fenced separately at intent; app/project/trust must still be current for every write.
pub(super) fn authorize_source_identity(
    config: &BotConfigFile,
    chat_id: &str,
    source: &SendSource,
) -> Result<(), FeishuError> {
    if !config.enabled
        || config.id != source.bot_id
        || config.feishu().app_id != source.app_id
        || config.project_id != source.project_id
        || chat_id != source.chat_id
    {
        return Err(denied(
            "bot source identity is disabled, changed or no longer applicable",
        ));
    }
    let trusted = match source.chat_kind.as_str() {
        "direct" => config.feishu().trusted_open_ids.contains(&source.open_id),
        "group" => config.feishu().trusted_chat_ids.contains(&source.chat_id),
        _ => false,
    };
    if !trusted {
        return Err(denied("the original bot source trust has been revoked"));
    }
    Ok(())
}

fn denied(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Permission, message, false, None)
}
