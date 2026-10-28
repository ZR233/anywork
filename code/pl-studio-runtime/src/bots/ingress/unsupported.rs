//! 不支持的纯媒体消息保留原有界辅助提示，不为提示创建 Thread 或模型输入。

use super::error::{attention, failure};
use super::owner::{IngressControl, IngressRun};
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::storage::reply::{InboundReply, ReplyBinding};
use crate::bots::{InboundWorkOutcome, SendAuthority};
use pl_protocol::studio::{BotAuthorizationPhase, BotSendStatus};

impl BotRuntime {
    pub(super) async fn unsupported_inbound(
        &self,
        managed: &ManagedBot,
        run: &IngressRun,
        control: &IngressControl,
    ) -> InboundWorkOutcome {
        let authority = match self.unsupported_authority(managed, run, control).await {
            Ok(authority) => authority,
            Err(outcome) => return outcome,
        };
        // The existing send owner keeps the network request and ledger through real settlement.
        // Do not select cancellation against it or upgrade this auxiliary proof to public output.
        match self.send_message_as(
            format!("botunsupported:{}:{}:{}", run.inbound.bot_id, run.inbound.chat_id, run.inbound.message_id),
            run.inbound.bot_id.clone(), run.inbound.chat_id.clone(),
            "此消息类型或富文本元素暂不支持原件接收。可接收文字、富文本、图片、文件及可下载音视频；贴纸和云文档分享没有对应原件下载接口，请直接发送原文件。".into(),
            "auto-reply", authority,
        ).await {
            Ok(result) if result.status == BotSendStatus::Succeeded => InboundWorkOutcome::Completed,
            Ok(_) => attention("unsupported message notice was not fully delivered"),
            Err(error) => control.stopped(self).unwrap_or_else(|| failure("unsupported input notice failed", error)),
        }
    }

    async fn unsupported_authority(
        &self,
        managed: &ManagedBot,
        run: &IngressRun,
        control: &IngressControl,
    ) -> Result<SendAuthority, InboundWorkOutcome> {
        let _admission = managed.admission.lock().await;
        self.hold_inbound_claim(managed, run, control).await?;
        self.reject_closed_admission(managed)
            .map_err(|error| failure("unsupported notice admission is closed", error))?;
        self.current_inbound_permission(
            managed,
            &run.inbound,
            &super::binding::inbound_target(&run.inbound)?,
        )
        .await?;
        let projection = managed
            .store
            .binding_for_chat(
                &run.inbound.chat_id,
                &run.inbound.bot_id,
                &run.inbound.project_id,
            )
            .await
            .map_err(|error| failure("unsupported notice route read failed", error))?;
        let binding = match projection.status.as_str() {
            "absent" if run.inbound.creation_id.is_empty() && run.inbound.binding_revision == 0 => {
                ReplyBinding::Absent
            }
            "creating"
                if super::binding::original_route(&projection, &run.inbound)
                    && projection.thread_id.is_none() =>
            {
                ReplyBinding::Creating
            }
            "bound"
                if super::binding::original_route(&projection, &run.inbound)
                    && projection.thread_id.is_some() =>
            {
                ReplyBinding::Bound
            }
            _ => {
                return Err(attention(
                    "unsupported notice cannot prove its original route expectation",
                ));
            }
        };
        let thread = projection.thread_id.unwrap_or_default();
        if !thread.is_empty() {
            let Some(scope) = managed
                .store
                .audience_scope(&thread, &run.inbound.bot_id)
                .await
                .map_err(|error| failure("unsupported notice audience read failed", error))?
            else {
                return Err(attention(
                    "unsupported notice lacks original creation proof",
                ));
            };
            if scope.origin.requires_upgrade
                || scope.head.as_ref().is_none_or(|auth| {
                    auth.intent.thread_id != thread
                        || auth.intent.authorization.bot_id != run.inbound.bot_id
                        || auth.intent.authorization.chat_id != run.inbound.chat_id
                        || auth.app_id != run.inbound.app_id
                        || auth.project_id != run.inbound.project_id
                        || auth.creation_id != run.inbound.creation_id
                        || auth.intent.binding_revision != run.inbound.binding_revision
                        || !matches!(
                            auth.phase,
                            BotAuthorizationPhase::Active | BotAuthorizationPhase::Paused
                        )
                        || auth.start.is_none()
                })
            {
                return Err(attention(
                    "unsupported notice audience is closed or not enabled",
                ));
            }
            super::admission::check_target(&scope.origin.target, &run.inbound)?;
        }
        Ok(SendAuthority::InboundReply(Box::new(InboundReply {
            source: run.source(&thread),
            worker_id: run.worker_id.clone(),
            watch_input: run.watch_input().to_string(),
            admitted_binding_revision: run.inbound.binding_revision,
            binding,
        })))
    }
}
