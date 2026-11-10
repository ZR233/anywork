use crate::api::studio::types::{
    BridgeCommandDisposition, BridgeCommandEffectPoint, BridgeResourceStamp,
    BridgeSettingsCommandReply, BridgeStudioCommandReceipt,
};
use pl_protocol::studio::{
    CommandDisposition, CommandEffectPoint, SettingsCommandReply, StudioCommandReceipt,
};

pub(crate) fn command_receipt(value: StudioCommandReceipt) -> BridgeStudioCommandReceipt {
    BridgeStudioCommandReceipt {
        operation_id: value.operation_id,
        disposition: match value.disposition {
            CommandDisposition::Applied => BridgeCommandDisposition::Applied,
            CommandDisposition::NoChange => BridgeCommandDisposition::NoChange,
        },
        targets: value
            .targets
            .into_iter()
            .map(|target| BridgeResourceStamp {
                resource_key: target.resource_key,
                owner_epoch: target.owner_epoch,
                revision: target.revision,
            })
            .collect(),
        effect: match value.effect {
            CommandEffectPoint::Immediate => BridgeCommandEffectPoint::Immediate,
            CommandEffectPoint::NextTurn => BridgeCommandEffectPoint::NextTurn,
            CommandEffectPoint::FutureSession => BridgeCommandEffectPoint::FutureSession,
        },
        effective: value.effective,
        durable: value.durable,
        requires_identity_observation: value.requires_identity_observation,
    }
}

pub(crate) fn settings_command_reply(value: SettingsCommandReply) -> BridgeSettingsCommandReply {
    BridgeSettingsCommandReply {
        snapshot: super::settings::bridge_settings_snapshot(value.snapshot),
        receipt: command_receipt(value.receipt),
    }
}

pub(crate) fn rename_thread_command_reply(
    thread: pl_protocol::SessionDirectoryRow,
    receipt: StudioCommandReceipt,
) -> crate::api::studio::types::BridgeRenameThreadCommandReply {
    crate::api::studio::types::BridgeRenameThreadCommandReply {
        thread: super::thread_stream::bridge_session_row(thread),
        receipt: command_receipt(receipt),
    }
}

pub(crate) fn archive_thread_command_reply(
    archived_root_id: String,
    removed_thread_ids: Vec<String>,
    next_root: Option<pl_protocol::SessionDirectoryRow>,
    receipt: StudioCommandReceipt,
) -> crate::api::studio::types::BridgeArchiveThreadCommandReply {
    crate::api::studio::types::BridgeArchiveThreadCommandReply {
        result: crate::api::studio::types::ArchiveThreadResult {
            archived_root_id,
            removed_thread_ids,
            next_root: next_root.map(super::thread_stream::bridge_session_row),
        },
        receipt: command_receipt(receipt),
    }
}

pub(crate) fn delete_thread_command_reply(
    deleted_root_id: String,
    deleted_thread_ids: Vec<String>,
    next_root: Option<pl_protocol::SessionDirectoryRow>,
    receipt: StudioCommandReceipt,
) -> crate::api::studio::types::BridgeDeleteThreadCommandReply {
    crate::api::studio::types::BridgeDeleteThreadCommandReply {
        result: crate::api::studio::types::DeleteThreadResult {
            deleted_root_id,
            deleted_thread_ids,
            next_root: next_root.map(super::thread_stream::bridge_session_row),
        },
        receipt: command_receipt(receipt),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::studio::types::{BridgeAgentBackend, BridgeSessionDirectoryRow};
    use pl_protocol::session::{AcpSessionReference, AgentBackend};
    use pl_protocol::studio::{CommandDisposition, CommandEffectPoint, ResourceStamp};

    fn row() -> pl_protocol::SessionDirectoryRow {
        pl_protocol::SessionDirectoryRow {
            session_id: "product-session".into(),
            agent_id: "product-agent".into(),
            parent_agent_id: None,
            thread_id: "product-thread".into(),
            workspace_id: "workspace".into(),
            title: "Peer conversation".into(),
            mode: None,
            workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
            delegation_mode: pl_protocol::DelegationMode::Profile,
            delegation_preference: pl_protocol::DelegationPreference::Balanced,
            workspace_path: "/workspace path".into(),
            role: "root-profile".into(),
            backend: AgentBackend::Acp {
                reference: AcpSessionReference {
                    account_id: "actual-account".into(),
                    acp_session_id: "actual-peer-session".into(),
                    cwd: "/peer cwd".into(),
                },
            },
            created_at: 11,
            updated_at: 22,
            last_user_message_at: Some(17),
            archived: false,
        }
    }

    fn receipt() -> StudioCommandReceipt {
        StudioCommandReceipt {
            operation_id: "command-op".into(),
            disposition: CommandDisposition::Applied,
            targets: vec![ResourceStamp {
                resource_key: "thread-directory".into(),
                owner_epoch: "directory-owner".into(),
                revision: 23,
            }],
            effect: CommandEffectPoint::Immediate,
            effective: true,
            durable: false,
            requires_identity_observation: false,
        }
    }

    fn assert_acp_row(row: &BridgeSessionDirectoryRow) {
        assert_eq!(row.session_id, "product-session");
        assert_eq!(row.agent_id, "product-agent");
        assert_eq!(row.thread_id, "product-thread");
        assert_eq!(row.parent_agent_id, None);
        assert_eq!(row.mode, None);
        assert_eq!(row.title, "Peer conversation");
        assert_eq!(row.last_user_message_at, Some(17));
        let BridgeAgentBackend::Acp { reference } = &row.backend else {
            panic!("ACP directory row was projected into Native state");
        };
        assert_eq!(reference.account_id, "actual-account");
        assert_eq!(reference.acp_session_id, "actual-peer-session");
        assert_eq!(reference.cwd, "/peer cwd");
    }

    #[test]
    fn directory_command_replies_preserve_acp_rows_and_optional_next_root() {
        let renamed = rename_thread_command_reply(row(), receipt());
        assert_acp_row(&renamed.thread);
        assert_eq!(renamed.receipt.operation_id, "command-op");
        assert_eq!(renamed.receipt.targets[0].owner_epoch, "directory-owner");
        for next_root in [None, Some(row())] {
            let archived = archive_thread_command_reply(
                "archived-thread".into(),
                vec!["archived-child".into()],
                next_root.clone(),
                receipt(),
            );
            assert_eq!(archived.result.archived_root_id, "archived-thread");
            assert_eq!(archived.result.removed_thread_ids, vec!["archived-child"]);
            assert_eq!(archived.result.next_root.is_some(), next_root.is_some());
            if let Some(row) = &archived.result.next_root {
                assert_acp_row(row);
            }
            assert_eq!(archived.receipt.targets[0].revision, 23);
            let deleted = delete_thread_command_reply(
                "deleted-thread".into(),
                vec!["deleted-child".into()],
                next_root,
                receipt(),
            );
            assert_eq!(deleted.result.deleted_root_id, "deleted-thread");
            assert_eq!(deleted.result.deleted_thread_ids, vec!["deleted-child"]);
            assert_eq!(
                deleted.result.next_root.is_some(),
                archived.result.next_root.is_some()
            );
            if let Some(row) = &deleted.result.next_root {
                assert_acp_row(row);
            }
            assert_eq!(deleted.receipt.targets[0].revision, 23);
        }
    }
}
