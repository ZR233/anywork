//! 公共机器人 DTO 到 FRB 镜像的穷尽转换。

use crate::api::studio::convert::commands::command_receipt;
use crate::api::studio::types::*;
use pl_protocol::studio::{
    BotConnectionState, BotConversation, BotConversationKind, BotConversationPage,
    BotConversationSource, BotConversationThreadBinding, BotConversationThreadReply,
    BotConversationThreadState, BotCredentialAvailability, BotCredentialOperation, BotDiagnostic,
    BotMessage, BotMessageBody, BotMessagePage, BotPairingRequest, BotPendingCredentialOperation,
    BotPlatform, BotRegistrationAttempt, BotRegistrationStatus, BotSecretUpdate, BotSendResult,
    BotSendSegment, BotSendStatus, BotSnapshot, BotsStateSnapshot, CancelBotRegistrationRequest,
    CreateBotConversationThreadRequest, ListBotConversationsRequest, ReadBotMessagesRequest,
    RetryBotConnectionRequest, SaveBotRequest, SendBotMessageRequest, SetBotEnabledRequest,
    SetBotTrustedChatRequest, SetBotTrustedUserRequest, StartBotRegistrationRequest,
};

pub(crate) fn bridge_bots_state(value: BotsStateSnapshot) -> BridgeBotsStateSnapshot {
    BridgeBotsStateSnapshot {
        revision: value.revision,
        updated_at: value.updated_at,
        bots: value.bots.into_iter().map(bridge_bot_snapshot).collect(),
        registration: value.registration.map(bridge_registration_attempt),
        pending_credential_operations: value
            .pending_credential_operations
            .into_iter()
            .map(bridge_pending_credential)
            .collect(),
    }
}

pub(crate) fn bridge_bot_snapshot(value: BotSnapshot) -> BridgeBotSnapshot {
    BridgeBotSnapshot {
        last_activity_at: value.last_activity_at,
        model_route: value.model_route.map(|route| BridgeBotModelRoute {
            account_id: route.account_id,
            model_id: route.model_id,
            effort: route.effort,
        }),
        workspace_path: value.workspace_path,
        id: value.id,
        name: value.name,
        project_id: value.project_id,
        app_id: value.app_id,
        platform: match value.platform {
            BotPlatform::FeishuChina => BridgeBotPlatform::FeishuChina,
        },
        enabled: value.enabled,
        tools_enabled: value.tools_enabled,
        config_revision: value.config_revision,
        trusted_open_ids: value.trusted_open_ids,
        trusted_chat_ids: value.trusted_chat_ids,
        connection: bridge_connection(value.connection),
        credential: match value.credential {
            BotCredentialAvailability::Missing => BridgeBotCredentialAvailability::Missing,
            BotCredentialAvailability::SessionOnly => BridgeBotCredentialAvailability::SessionOnly,
            BotCredentialAvailability::Stored => BridgeBotCredentialAvailability::Stored,
            BotCredentialAvailability::Unavailable => BridgeBotCredentialAvailability::Unavailable,
        },
        credential_operation: bridge_credential_operation(value.credential_operation),
        pairing: value.pairing.into_iter().map(bridge_pairing).collect(),
        diagnostic: value.diagnostic.map(bridge_diagnostic),
        can_change_project: value.can_change_project,
        can_change_app_id: value.can_change_app_id,
        created_at: value.created_at,
        updated_at: value.updated_at,
    }
}

fn bridge_connection(value: BotConnectionState) -> BridgeBotConnectionState {
    match value {
        BotConnectionState::Disabled => BridgeBotConnectionState::Disabled,
        BotConnectionState::Connecting => BridgeBotConnectionState::Connecting,
        BotConnectionState::Connected => BridgeBotConnectionState::Connected,
        BotConnectionState::Reconnecting {
            next_attempt_at,
            attempt,
        } => BridgeBotConnectionState::Reconnecting {
            next_attempt_at,
            attempt,
        },
        BotConnectionState::Failed {
            code,
            message,
            retryable,
            platform_code,
        } => BridgeBotConnectionState::Failed {
            code,
            message,
            retryable,
            platform_code,
        },
    }
}

fn bridge_credential_operation(value: BotCredentialOperation) -> BridgeBotCredentialOperation {
    match value {
        BotCredentialOperation::Idle => BridgeBotCredentialOperation::Idle,
        BotCredentialOperation::Preparing { operation_id } => {
            BridgeBotCredentialOperation::Preparing { operation_id }
        }
        BotCredentialOperation::CommitUncertain { operation_id } => {
            BridgeBotCredentialOperation::CommitUncertain { operation_id }
        }
        BotCredentialOperation::CleanupPending {
            operation_id,
            config_committed,
        } => BridgeBotCredentialOperation::CleanupPending {
            operation_id,
            config_committed,
        },
    }
}

fn bridge_pairing(value: BotPairingRequest) -> BridgeBotPairingRequest {
    BridgeBotPairingRequest {
        request_id: value.request_id,
        bot_id: value.bot_id,
        open_id: value.open_id,
        display_name: value.display_name,
        created_at: value.created_at,
    }
}

fn bridge_diagnostic(value: BotDiagnostic) -> BridgeBotDiagnostic {
    BridgeBotDiagnostic {
        code: value.code,
        message: value.message,
        retryable: value.retryable,
        platform_code: value.platform_code,
        guidance: value.guidance,
    }
}

pub(crate) fn bridge_registration_attempt(
    value: BotRegistrationAttempt,
) -> BridgeBotRegistrationAttempt {
    BridgeBotRegistrationAttempt {
        attempt_id: value.attempt_id,
        name: value.name,
        project_id: value.project_id,
        status: bridge_registration_status(value.status),
        completed_bot_id: value.completed_bot_id,
    }
}

fn bridge_registration_status(value: BotRegistrationStatus) -> BridgeBotRegistrationStatus {
    match value {
        BotRegistrationStatus::Idle => BridgeBotRegistrationStatus::Idle,
        BotRegistrationStatus::Preparing { attempt_id } => {
            BridgeBotRegistrationStatus::Preparing { attempt_id }
        }
        BotRegistrationStatus::Waiting {
            attempt_id,
            verification_url,
            expires_at,
            interval_seconds,
        } => BridgeBotRegistrationStatus::Waiting {
            attempt_id,
            verification_url,
            expires_at,
            interval_seconds,
        },
        BotRegistrationStatus::SlowDown {
            attempt_id,
            verification_url,
            expires_at,
            interval_seconds,
        } => BridgeBotRegistrationStatus::SlowDown {
            attempt_id,
            verification_url,
            expires_at,
            interval_seconds,
        },
        BotRegistrationStatus::Completed { attempt_id } => {
            BridgeBotRegistrationStatus::Completed { attempt_id }
        }
        BotRegistrationStatus::Committing { attempt_id, bot_id } => {
            BridgeBotRegistrationStatus::Committing { attempt_id, bot_id }
        }
        BotRegistrationStatus::Denied {
            attempt_id,
            message,
        } => BridgeBotRegistrationStatus::Denied {
            attempt_id,
            message,
        },
        BotRegistrationStatus::Expired { attempt_id } => {
            BridgeBotRegistrationStatus::Expired { attempt_id }
        }
        BotRegistrationStatus::Cancelled { attempt_id } => {
            BridgeBotRegistrationStatus::Cancelled { attempt_id }
        }
        BotRegistrationStatus::Failed {
            attempt_id,
            code,
            message,
            retryable,
        } => BridgeBotRegistrationStatus::Failed {
            attempt_id,
            code,
            message,
            retryable,
        },
    }
}

fn bridge_pending_credential(
    value: BotPendingCredentialOperation,
) -> BridgeBotPendingCredentialOperation {
    BridgeBotPendingCredentialOperation {
        bot_id: value.bot_id,
        credential_operation: bridge_credential_operation(value.credential_operation),
        diagnostic: value.diagnostic.map(bridge_diagnostic),
    }
}

pub(crate) fn protocol_save_bot(value: BridgeSaveBotRequest) -> SaveBotRequest {
    SaveBotRequest {
        model_route: value
            .model_route
            .map(|route| pl_protocol::studio::BotModelRoute {
                account_id: route.account_id,
                model_id: route.model_id,
                effort: route.effort,
            }),
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        expected_config_revision: value.expected_config_revision,
        name: value.name,
        project_id: value.project_id,
        app_id: value.app_id,
        secret: match value.secret {
            BridgeBotSecretUpdate::Preserve => BotSecretUpdate::Preserve,
            BridgeBotSecretUpdate::Replace { value } => BotSecretUpdate::Replace { value },
            BridgeBotSecretUpdate::Clear => BotSecretUpdate::Clear,
        },
        enabled: value.enabled,
        tools_enabled: value.tools_enabled,
    }
}

pub(crate) fn protocol_start_registration(
    value: BridgeStartBotRegistrationRequest,
) -> StartBotRegistrationRequest {
    StartBotRegistrationRequest {
        operation_id: value.operation_id,
        name: value.name,
        project_id: value.project_id,
    }
}

pub(crate) fn protocol_cancel_registration(
    value: BridgeCancelBotRegistrationRequest,
) -> CancelBotRegistrationRequest {
    CancelBotRegistrationRequest {
        operation_id: value.operation_id,
        attempt_id: value.attempt_id,
    }
}

pub(crate) fn protocol_set_enabled(value: BridgeSetBotEnabledRequest) -> SetBotEnabledRequest {
    SetBotEnabledRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        expected_config_revision: value.expected_config_revision,
        enabled: value.enabled,
    }
}

pub(crate) fn protocol_retry_connection(
    value: BridgeRetryBotConnectionRequest,
) -> RetryBotConnectionRequest {
    RetryBotConnectionRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
    }
}

pub(crate) fn protocol_set_trusted_user(
    value: BridgeSetBotTrustedUserRequest,
) -> SetBotTrustedUserRequest {
    SetBotTrustedUserRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        expected_config_revision: value.expected_config_revision,
        open_id: value.open_id,
        trusted: value.trusted,
    }
}

pub(crate) fn protocol_set_trusted_chat(
    value: BridgeSetBotTrustedChatRequest,
) -> SetBotTrustedChatRequest {
    SetBotTrustedChatRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        expected_config_revision: value.expected_config_revision,
        chat_id: value.chat_id,
        trusted: value.trusted,
    }
}

pub(crate) fn protocol_list_conversations(
    value: BridgeListBotConversationsRequest,
) -> ListBotConversationsRequest {
    ListBotConversationsRequest {
        bot_id: value.bot_id,
        cursor: value.cursor,
        limit: value.limit,
    }
}

pub(crate) fn protocol_read_messages(
    value: BridgeReadBotMessagesRequest,
) -> ReadBotMessagesRequest {
    ReadBotMessagesRequest {
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        start_time: value.start_time,
        end_time: value.end_time,
        cursor: value.cursor,
        limit: value.limit,
    }
}

pub(crate) fn protocol_send_message(value: BridgeSendBotMessageRequest) -> SendBotMessageRequest {
    SendBotMessageRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        text: value.text,
    }
}

pub(crate) fn protocol_create_thread(
    value: BridgeCreateBotConversationThreadRequest,
) -> CreateBotConversationThreadRequest {
    CreateBotConversationThreadRequest {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        expected_config_revision: value.expected_config_revision,
        expected_binding_revision: value.expected_binding_revision,
    }
}

pub(crate) fn bridge_conversation_page(value: BotConversationPage) -> BridgeBotConversationPage {
    BridgeBotConversationPage {
        bot_id: value.bot_id,
        conversations: value
            .conversations
            .into_iter()
            .map(bridge_conversation)
            .collect(),
        next_cursor: value.next_cursor,
    }
}

fn bridge_conversation(value: BotConversation) -> BridgeBotConversation {
    BridgeBotConversation {
        chat_id: value.chat_id,
        kind: match value.kind {
            BotConversationKind::Group => BridgeBotConversationKind::Group,
            BotConversationKind::Direct => BridgeBotConversationKind::Direct,
        },
        source: match value.source {
            BotConversationSource::RemoteGroup => BridgeBotConversationSource::RemoteGroup,
            BotConversationSource::ObservedDirect => BridgeBotConversationSource::ObservedDirect,
        },
        name: value.name,
        last_observed_at: value.last_observed_at,
        thread_binding: value.thread_binding.map(bridge_thread_binding),
    }
}

fn bridge_thread_binding(
    value: BotConversationThreadBinding,
) -> BridgeBotConversationThreadBinding {
    BridgeBotConversationThreadBinding {
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        project_id: value.project_id,
        thread_id: value.thread_id,
        revision: value.revision,
        state: match value.state {
            BotConversationThreadState::Creating => BridgeBotConversationThreadState::Creating,
            BotConversationThreadState::Bound => BridgeBotConversationThreadState::Bound,
            BotConversationThreadState::NeedsAttention => {
                BridgeBotConversationThreadState::NeedsAttention
            }
        },
        diagnostic: value.diagnostic.map(bridge_diagnostic),
    }
}

pub(crate) fn bridge_conversation_thread_reply(
    value: BotConversationThreadReply,
) -> BridgeBotConversationThreadReply {
    BridgeBotConversationThreadReply {
        binding: bridge_thread_binding(value.binding),
        receipt: command_receipt(value.receipt),
    }
}

pub(crate) fn bridge_message_page(value: BotMessagePage) -> BridgeBotMessagePage {
    BridgeBotMessagePage {
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        messages: value.messages.into_iter().map(bridge_message).collect(),
        next_cursor: value.next_cursor,
    }
}

fn bridge_message(value: BotMessage) -> BridgeBotMessage {
    BridgeBotMessage {
        message_id: value.message_id,
        chat_id: value.chat_id,
        sender_open_id: value.sender_open_id,
        created_at: value.created_at,
        body: match value.body {
            BotMessageBody::Text { text } => BridgeBotMessageBody::Text { text },
            BotMessageBody::Post { text } => BridgeBotMessageBody::Post { text },
            BotMessageBody::Unsupported { msg_type, notice } => {
                BridgeBotMessageBody::Unsupported { msg_type, notice }
            }
        },
    }
}

pub(crate) fn bridge_send_result(value: BotSendResult) -> BridgeBotSendResult {
    BridgeBotSendResult {
        operation_id: value.operation_id,
        bot_id: value.bot_id,
        chat_id: value.chat_id,
        status: bridge_send_status(value.status),
        segments: value
            .segments
            .into_iter()
            .map(bridge_send_segment)
            .collect(),
        receipt: command_receipt(value.receipt),
    }
}

fn bridge_send_segment(value: BotSendSegment) -> BridgeBotSendSegment {
    BridgeBotSendSegment {
        index: value.index,
        status: bridge_send_status(value.status),
        platform_message_id: value.platform_message_id,
        diagnostic: value.diagnostic.map(bridge_diagnostic),
    }
}

fn bridge_send_status(value: BotSendStatus) -> BridgeBotSendStatus {
    match value {
        BotSendStatus::Succeeded => BridgeBotSendStatus::Succeeded,
        BotSendStatus::Partial => BridgeBotSendStatus::Partial,
        BotSendStatus::Rejected => BridgeBotSendStatus::Rejected,
        BotSendStatus::Unknown => BridgeBotSendStatus::Unknown,
    }
}
