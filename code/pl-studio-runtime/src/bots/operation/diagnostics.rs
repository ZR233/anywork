use crate::BotDiagnostic;
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};

/// 凭据/提交状态无法核实时的固定安全诊断文案。
const CREDENTIAL_STATE_UNVERIFIED: &str =
    "bot credential state could not be verified; retry the operation to continue";
/// 已确定未写入配置、但操作没有完成的固定安全诊断文案。
const CREDENTIAL_OPERATION_INCOMPLETE: &str =
    "bot credential operation did not complete; no configuration was written";
/// 已确定保存后配对清理未完成的独立诊断文案。
pub(super) const PAIRING_CLEANUP_PENDING: &str = "pairing request cleanup did not finish, saved trust is unchanged and submitting \
     the same trust value again finishes cleanup";
/// 合法 safe-id 目录读取失败时的固定安全诊断文案。
pub(super) const BOT_DIRECTORY_UNREADABLE: &str =
    "bot directory could not be read; local data is retained for retry";

pub(super) fn unverified_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        CREDENTIAL_STATE_UNVERIFIED,
        true,
        None,
    )
    .diagnostic()
}

pub(super) fn incomplete_diagnostic() -> BotDiagnostic {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        CREDENTIAL_OPERATION_INCOMPLETE,
        true,
        None,
    )
    .diagnostic()
}

/// Store independent recovery facts. Flatten only when producing the existing
/// public DTO, which carries one diagnostic per bot.
#[derive(Clone, Default)]
pub(in crate::bots) struct BotDiagnosticSet {
    connection: Option<BotDiagnostic>,
    pairing: Option<BotDiagnostic>,
    directory: Option<BotDiagnostic>,
    credential: Option<BotDiagnostic>,
}

pub(in crate::bots) enum DiagnosticSlot {
    Connection,
    Pairing,
    Directory,
    Credential,
}

impl BotDiagnosticSet {
    pub(in crate::bots) fn set(&mut self, slot: DiagnosticSlot, value: Option<BotDiagnostic>) {
        *match slot {
            DiagnosticSlot::Connection => &mut self.connection,
            DiagnosticSlot::Pairing => &mut self.pairing,
            DiagnosticSlot::Directory => &mut self.directory,
            DiagnosticSlot::Credential => &mut self.credential,
        } = value;
    }

    pub(in crate::bots) fn projection(&self) -> Option<BotDiagnostic> {
        self.project_with_pairing_read(None)
    }

    pub(in crate::bots) fn project_with_pairing_read(
        &self,
        read: Option<BotDiagnostic>,
    ) -> Option<BotDiagnostic> {
        let mut entries = [
            self.credential.as_ref(),
            self.connection.as_ref(),
            self.directory.as_ref(),
            self.pairing.as_ref(),
            read.as_ref(),
        ]
        .into_iter()
        .flatten();
        let mut primary = entries.next()?.clone();
        for diagnostic in entries {
            primary.message.push_str("; ");
            primary.message.push_str(&diagnostic.message);
            primary.retryable &= diagnostic.retryable;
        }
        Some(primary)
    }
}
