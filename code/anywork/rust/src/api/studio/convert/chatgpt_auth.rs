use crate::api::studio::types::*;
use pl_protocol::studio as p;

pub(crate) fn bridge_chatgpt_login_reply(
    value: p::ChatGptLoginCommandReply,
) -> BridgeChatGptLoginCommandReply {
    BridgeChatGptLoginCommandReply {
        stamp: BridgeResourceStamp {
            resource_key: value.stamp.resource_key,
            owner_epoch: value.stamp.owner_epoch,
            revision: value.stamp.revision,
        },
        snapshot: bridge_chatgpt_login_snapshot(value.snapshot),
    }
}

impl From<p::AccountAuthenticationMethod> for BridgeAccountAuthenticationMethod {
    fn from(value: p::AccountAuthenticationMethod) -> Self {
        match value {
            p::AccountAuthenticationMethod::ApiKey => Self::ApiKey,
            p::AccountAuthenticationMethod::ChatGpt => Self::ChatGpt,
        }
    }
}

impl From<BridgeAccountAuthenticationIntent> for p::AccountAuthenticationIntent {
    fn from(value: BridgeAccountAuthenticationIntent) -> Self {
        match value {
            BridgeAccountAuthenticationIntent::Keep => Self::Keep,
            BridgeAccountAuthenticationIntent::ApiKey => Self::ApiKey,
            BridgeAccountAuthenticationIntent::ChatGpt {
                login_id,
                editor_id,
            } => Self::ChatGpt {
                login_id,
                editor_id,
            },
        }
    }
}

impl From<p::ChatGptAccountInfo> for BridgeChatGptAccountInfo {
    fn from(value: p::ChatGptAccountInfo) -> Self {
        Self {
            issuer: value.issuer,
            subject: value.subject,
            client_id: value.client_id,
            email: value.email,
            plan_usage_enabled: value.plan_usage_enabled,
        }
    }
}

pub(crate) fn bridge_chatgpt_login_snapshot(
    value: p::ChatGptLoginSnapshot,
) -> BridgeChatGptLoginSnapshot {
    BridgeChatGptLoginSnapshot {
        login_id: value.login_id,
        editor_id: value.editor_id,
        account_id: value.account_id,
        revision: value.revision,
        phase: match value.phase {
            p::ChatGptLoginPhase::Preparing => BridgeChatGptLoginPhase::Preparing,
            p::ChatGptLoginPhase::AwaitingBrowser => BridgeChatGptLoginPhase::AwaitingBrowser,
            p::ChatGptLoginPhase::ExchangingCode => BridgeChatGptLoginPhase::ExchangingCode,
            p::ChatGptLoginPhase::Succeeded => BridgeChatGptLoginPhase::Succeeded,
            p::ChatGptLoginPhase::Cancelled => BridgeChatGptLoginPhase::Cancelled,
            p::ChatGptLoginPhase::Failed => BridgeChatGptLoginPhase::Failed,
        },
        authorization_url: value.authorization_url,
        expires_at: value.expires_at,
        account: value.account.map(Into::into),
        failure: value.failure.map(|failure| BridgeChatGptLoginFailure {
            code: match failure.code {
                p::ChatGptLoginFailureCode::Network => BridgeChatGptLoginFailureCode::Network,
                p::ChatGptLoginFailureCode::AuthorizationDenied => {
                    BridgeChatGptLoginFailureCode::AuthorizationDenied
                }
                p::ChatGptLoginFailureCode::InvalidCallback => {
                    BridgeChatGptLoginFailureCode::InvalidCallback
                }
                p::ChatGptLoginFailureCode::InvalidIdentity => {
                    BridgeChatGptLoginFailureCode::InvalidIdentity
                }
                p::ChatGptLoginFailureCode::MissingPlanPermission => {
                    BridgeChatGptLoginFailureCode::MissingPlanPermission
                }
                p::ChatGptLoginFailureCode::Expired => BridgeChatGptLoginFailureCode::Expired,
                p::ChatGptLoginFailureCode::Storage => BridgeChatGptLoginFailureCode::Storage,
                p::ChatGptLoginFailureCode::TaskFailed => BridgeChatGptLoginFailureCode::TaskFailed,
            },
            retryable: failure.retryable,
        }),
    }
}
