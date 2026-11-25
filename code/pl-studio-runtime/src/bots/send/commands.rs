use super::plan::plan_text;
use super::text::{ClaimedSend, replay_send, send_text};
use crate::bots::SendAuthority;
use crate::bots::occupancy::OccupancyBudget;
use crate::bots::owner::{BotRuntime, ManagedBot};
use crate::bots::protocol::error::{FeishuError, FeishuErrorKind};
use crate::bots::query::ChatAuthorizer;
use crate::bots::storage::{SendRecord, SendRecordStatus, SendSegmentFact};
use crate::protocol::*;
use std::sync::Arc;

/// 发送认领占用区冻结的材料：只含身份/授权与记录本身，不含整份配置或 secret。
struct FrozenSendClaim {
    managed: Arc<ManagedBot>,
    record: SendRecord,
    membership: ChatAuthorizer,
    authority: SendAuthority,
    app_id: String,
    workspace_id: String,
    /// 调用方观测到的配置 revision：仅供首次认领复核，不参与回执填充。
    expected_config_revision: u64,
}

fn file_delivery_cancelled() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Unavailable,
        "file delivery cancelled before ledger admission",
        true,
        None,
    )
}

/// 首次发送认领的冻结文本上界：caller 仍持有 operationId/bot/chat/正文指纹原值，记录
/// 本身与 `load_send`/`claim_send` 的 SQL 参数各再带一份，因此峰值 3 份；逐段 uuid 同时
/// 存在于 `plan.uuids`、`planned` 与记录，编码出的 `segment_facts` JSON 再按真实编码
/// 长度计一次（含每段编码开销）。`body_bytes` 是本次 plan 的正文分段总长：`plan` 会
/// 跨越占用等待并交给统一发送 owner；raw 正文在指纹/分段确定后立即释放，不在这里重复计。
fn send_claim_freeze_bytes(
    record: &SendRecord,
    authority: &SendAuthority,
    app_id: &str,
    workspace_id: &str,
    facts_bytes: usize,
    body_bytes: usize,
) -> Result<usize, FeishuError> {
    let mut fields = vec![
        (record.operation_id.as_str(), 3),
        (record.bot_id.as_str(), 3),
        (record.chat_id.as_str(), 3),
        (record.content_hash.as_str(), 3),
        (app_id, 1),
        (workspace_id, 1),
    ];
    // 工具授权携带的项目 id 也跨 await 保留，必须单独计权。
    if let SendAuthority::Tool { workspace_id } = authority {
        fields.push((workspace_id.as_str(), 1));
    }
    for segment in &record.segments {
        fields.push((segment.uuid.as_str(), 3));
    }
    let base = crate::bots::occupancy::counted_text_bytes(fields)?;
    base.checked_add(facts_bytes)
        .and_then(|total| total.checked_add(body_bytes))
        .ok_or_else(crate::bots::occupancy::freeze_budget_error)
}

impl BotRuntime {
    pub async fn send_message(
        &self,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
        owner_epoch: &str,
    ) -> Result<BotSendResult, FeishuError> {
        self.send_message_as(
            operation_id,
            bot_id,
            chat_id,
            text,
            owner_epoch,
            SendAuthority::Owner,
        )
        .await
    }

    /// Feishu binding implementation detail: credentials, authorization and its
    /// existing send ledger. Generic channel dispatch must use ChannelOutputBinding.
    pub(in crate::bots) async fn send_file_as(
        &self,
        operation_id: String,
        target: crate::channel_output::ChannelTarget,
        file: crate::channel_output::FileDelivery,
        bytes: Vec<u8>,
        cancel: &tokio_util::sync::CancellationToken,
    ) -> Result<SendRecord, FeishuError> {
        use crate::channel_output::ChannelRegistry;
        let managed = self.managed(&target.account_id).await?;
        // The shared ManagedBot survives config updates and overlapping reply leases.
        // A successor must read the ledger only after its predecessor has drained.
        let _file_delivery = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Err(file_delivery_cancelled()),
            guard = managed.file_delivery.lock() => guard,
        };
        if cancel.is_cancelled() {
            return Err(file_delivery_cancelled());
        }
        let initial = crate::bots::files::initial_record(operation_id, target, file)?;
        if let Some(existing) = managed.store.load_send(&initial.operation_id).await? {
            crate::bots::storage::verify_send_identity(
                &existing,
                &initial.operation_id,
                &initial.bot_id,
                &initial.chat_id,
                &initial.content_hash,
            )?;
            crate::bots::files::validate_record(&existing)?;
            self.authorize_replay_source(&managed, &SendAuthority::AutoReply)
                .await?;
            if !crate::bots::files::resumable(&existing) {
                return Ok(existing);
            }
        }
        let config = managed.config.lock().await.clone();
        let membership = self
            .prepare_chat_access(&managed, &config, &initial.chat_id)
            .await?;
        let token = self.token(&managed, &config).await?;
        let facts_bytes = crate::bots::storage::segment_facts_bytes(&initial.segments)?;
        let frozen_bytes = send_claim_freeze_bytes(
            &initial,
            &SendAuthority::AutoReply,
            &config.feishu().app_id,
            &config.workspace_id,
            facts_bytes,
            0,
        )?;
        let frozen = FrozenSendClaim {
            managed: managed.clone(),
            record: initial.clone(),
            membership,
            authority: SendAuthority::AutoReply,
            app_id: config.feishu().app_id.clone(),
            workspace_id: config.workspace_id,
            expected_config_revision: config.config_revision,
        };
        let worker = self.clone();
        let (existing, _) = self
            .submit_occupancy(frozen_bytes, move |budget| async move {
                worker.claim_send_owned(frozen, budget).await
            })
            .await?;
        let record = existing.unwrap_or(initial);
        let mut registry = ChannelRegistry::default();
        // Platform assembly only. The delivery driver and tool know no platform names.
        registry
            .register(
                "feishu".into(),
                crate::bots::protocol::files::FeishuFileAdapter {
                    http: self.inner.http.clone(),
                    token,
                },
            )
            .map_err(|error| crate::bots::files::local_error(error.to_string()))?;
        crate::bots::files::deliver(
            &registry,
            &managed.store,
            record,
            bytes,
            &managed.send_rate,
            cancel,
        )
        .await
    }

    pub(crate) async fn send_message_as(
        &self,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
        owner_epoch: &str,
        authority: SendAuthority,
    ) -> Result<BotSendResult, FeishuError> {
        let managed = self.managed(&bot_id).await?;
        // 已持久同操作的本地回读：只核对持久指纹与当前来源权限，不联网、不刷新 token、
        // 不读 keyring；不同正文或会话命中同一 operationId 必须显式拒绝。
        if let Some(existing) = managed.store.load_send(&operation_id).await? {
            let content_hash =
                crate::bots::protocol::im::content_hash(&operation_id, &chat_id, &text);
            crate::bots::storage::verify_send_identity(
                &existing,
                &operation_id,
                &bot_id,
                &chat_id,
                &content_hash,
            )?;
            self.authorize_replay_source(&managed, &authority).await?;
            let revision = managed.config.lock().await.config_revision;
            let mut result = replay_send(existing, &operation_id, &bot_id, &chat_id);
            result.receipt.targets = vec![ResourceStamp {
                resource_key: format!("bot:{bot_id}"),
                owner_epoch: owner_epoch.to_string(),
                revision,
            }];
            return Ok(result);
        }
        // 首次意图：真实来源授权、目标实时可见性与 token 准备都在此完成。
        let config = managed.config.lock().await.clone();
        let membership = self
            .prepare_chat_access(&managed, &config, &chat_id)
            .await?;
        let token = self.token(&managed, &config).await?;
        let plan = plan_text(&operation_id, &bot_id, &chat_id, &text)?;
        // 指纹与分段已由 plan 固定：raw 正文不再保留，避免与 plan 分段同时跨占用等待。
        drop(text);
        let planned = plan
            .uuids
            .iter()
            .enumerate()
            .map(|(index, uuid)| SendSegmentFact {
                index: index as u32,
                uuid: uuid.clone(),
                status: SendRecordStatus::Unknown,
                platform_message_id: None,
                diagnostic: None,
                file_delivery: None,
            })
            .collect::<Vec<_>>();
        let initial = SendRecord {
            operation_id: operation_id.clone(),
            bot_id: bot_id.clone(),
            chat_id: chat_id.clone(),
            content_hash: plan.content_hash.clone(),
            status: SendRecordStatus::Unknown,
            platform_message_ids: Vec::new(),
            segments: planned.clone(),
            facts_complete: true,
        };
        // 首次发送认领是持久占用写入：交给受管占用任务持有到真实终态并主动重建。
        // 联网/逐段发送仍在统一发送服务中，由调用方持有，不搬入不可取消队列。
        let app_id = config.feishu().app_id.clone();
        let workspace_id = config.workspace_id;
        let expected_config_revision = config.config_revision;
        // 首次认领会把分段事实编码成 SQL 参数：按与持久化同一实现的真实长度计权。
        let facts_bytes = crate::bots::storage::segment_facts_bytes(&initial.segments)?;
        // plan 分段会跨占用等待并交给统一发送 owner：按实际 UTF-8 段总长计入首次预算。
        let body_bytes = plan.segments.iter().map(String::len).sum::<usize>();
        let text_bytes = send_claim_freeze_bytes(
            &initial,
            &authority,
            &app_id,
            &workspace_id,
            facts_bytes,
            body_bytes,
        )?;
        let worker = self.clone();
        // 任务持有一份 Arc；调用方仍需要 store 继续统一发送服务。
        let frozen = FrozenSendClaim {
            managed: managed.clone(),
            record: initial,
            membership,
            authority,
            app_id,
            workspace_id,
            expected_config_revision,
        };
        let (claimed, config_revision) = self
            .submit_occupancy(text_bytes, move |budget| async move {
                worker.claim_send_owned(frozen, budget).await
            })
            .await?;
        let mut result = if let Some(existing) = claimed {
            replay_send(existing, &operation_id, &bot_id, &chat_id)
        } else {
            send_text(ClaimedSend {
                http: &self.inner.http,
                token: &token,
                bot_id: &bot_id,
                chat_id: &chat_id,
                operation_id: &operation_id,
                store: &managed.store,
                plan,
                facts: planned,
                rate: &managed.send_rate,
            })
            .await?
        };
        result.receipt.targets = vec![ResourceStamp {
            resource_key: format!("bot:{bot_id}"),
            owner_epoch: owner_epoch.to_string(),
            revision: config_revision,
        }];
        Ok(result)
    }

    /// 发送认领的受管占用区：只在占用任务内运行。
    ///
    /// 首次认领把发送事实写成 AppIdentity 占用；调用方取消只是不再等待回执，
    /// 提交结果、通知与失败收束都由本任务完成。联网与逐段发送不在这里。
    async fn claim_send_owned(
        &self,
        frozen: FrozenSendClaim,
        _budget: OccupancyBudget,
    ) -> Result<(Option<SendRecord>, u64), FeishuError> {
        let FrozenSendClaim {
            managed,
            record,
            membership,
            authority,
            app_id,
            workspace_id,
            expected_config_revision,
        } = frozen;
        let _admission = managed.admission.lock().await;
        self.reject_closed_admission(&managed)?;
        // 短锁内核对身份与授权后立即释放，不克隆整份配置、不跨 DB await 持有 guard。
        let config_revision = {
            let current = managed.config.lock().await;
            if current.feishu().app_id != app_id || current.workspace_id != workspace_id {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot app or project changed before send claim",
                    true,
                    None,
                ));
            }
            self.authorize_chat(&current, authority, &membership)?;
            current.config_revision
        };
        // 已持久同操作允许非身份配置变化后原样重放（不重发、不抹旧结果）；
        // 真正首次认领才要求预期 revision 等于当前权威值，且在任何写入之前判定。
        // 只查存在性：不在此处解码整条已存事实，避免其长材料跨后续等待。
        let persisted = managed.store.send_exists(&record.operation_id).await?;
        if !persisted && config_revision != expected_config_revision {
            return Err(FeishuError::new(
                FeishuErrorKind::Conflict,
                "stale bot config revision before send claim",
                true,
                None,
            ));
        }
        let claimed = managed.store.claim_send(&record).await?;
        // 首次认领已提交：主动重建能力投影（业务 Err/异常终止另由 owner 终态通知覆盖）。
        self.request_publish();
        Ok((claimed, config_revision))
    }
}
