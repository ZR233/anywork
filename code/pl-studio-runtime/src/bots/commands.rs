//! 会话查询、发送与入站执行。扫码注册由 `registration` owner 持有。
use super::SendAuthority;
use super::archive::ReplyIdentity;
use super::config::BotConfigFile;
use super::connect::{ClaimedSend, replay_send, send_text};
use super::inbound::{ChatKind, InboundDecision, InboundHost};
use super::occupancy::OccupancyBudget;
use super::owner::{BotRuntime, ManagedBot, RuntimeInboundHost};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::{FeishuIm, to_product_message};
use super::send::plan_text;
use super::storage::{
    FrozenInbound, InboundAdmit, InboundClaim, SendRecord, SendRecordStatus, SendSegmentFact,
};
use crate::studio::new_id;
use pl_protocol::studio::*;
use std::sync::Arc;
use std::sync::atomic::Ordering;

/// 创建调用链中“创建身份”文本的 job 持有副本峰值。
///
/// `create_thread_with_id` 的现有边界（`studio/runtime/thread_service`, `studio/store`,
/// `studio/product_event_bus`）：
/// - `register_root_thread` 返回的 Thread 同时持有 `root_thread_id`/`agent_path`/`id` 三份；
/// - `commit_directory` 的 delta 持有该 Thread 的克隆（3 份），并在跨
///   `apply_project_delta().await` 期间与本任务手里的那份 Thread（3 份）、
///   `publish_thread_delta` 放入 envelope 的 upserted Thread（3 份）同时存活；
/// - 本任务自己持有创建身份 1 份。
///
/// 合计 10。已明确交接给独立 owner、不再由本任务持有的副本：`record_directory(delta.clone())`
/// 进入写后队列，`thread_index.insert(thread.clone(), …)` 进入目录 owner，
/// `persist_directory_summaries` 的 catalog/workspace 镜像归 store owner。
const CREATE_CALL_CREATION_COPIES: usize = 10;

/// 占用区内冻结的输入。联网与凭据的只读权限核验已在占用区之前完成，
/// 任务内只做本地 Thread 创建与绑定接续，不重新获取 secret 或 token。
/// 只保留身份/标题/操作所需标量：不捕获整份配置、可信集合或 secret。
struct FrozenBinding {
    runtime: Arc<crate::studio::StudioRuntime>,
    managed: Arc<ManagedBot>,
    bot_id: String,
    chat_id: String,
    workspace_id: String,
    /// 本地 Thread 标题在进入占用区之前预生成，写入后不再临时派生。
    title: String,
    app_id: String,
    operation_id: String,
    content_hash: String,
    creation_id: String,
    owner_epoch: String,
    expected_config_revision: u64,
    expected_binding_revision: u64,
}

impl FrozenBinding {
    /// 按 UTF-8 字节数受检计权，供占用 owner 的任务/文本双预算使用。
    ///
    /// 副本峰值按占用任务内各持久 await 阶段列出（首写是 `begin/adopt_binding_operation`）：
    ///
    /// | 阶段 | operationId/bot/chat/hash | project |
    /// | --- | --- | --- |
    /// | `insert_binding_operation` 的 INSERT 参数 | 3（冻结+操作记录+SQL 参数） | 2（读行+SQL 参数） |
    /// | `bind_thread` 的 UPSERT 参数 | 3（冻结+读行+SQL 参数） | 3（冻结+读行+SQL 参数） |
    /// | `save_binding_operation` 的 INSERT 参数 | 3（冻结+最终记录+SQL 参数） | 1 |
    ///
    /// 标题：本任务 1 份全量 + Studio 目录 3 个 Thread 实例（`register_root_thread`、
    /// `commit_directory` 的 delta 克隆与 envelope、`ThreadRecord`）的 `non_empty_title`
    /// 副本；后者按 trim 后前 80 字符计。Studio 侧索引/写后队列的副本已交接给目录 owner。
    /// app/owner_epoch 只参与比较，各 1 份。创建身份由任务在首次持久写之前单独预留：
    /// 进入 job 时先计 1 份，写前补足调用链峰值（见 `CREATE_CALL_CREATION_COPIES`）。
    fn text_bytes(&self) -> Result<usize, FeishuError> {
        let base = super::occupancy::counted_text_bytes([
            (self.operation_id.as_str(), 3),
            (self.bot_id.as_str(), 3),
            (self.chat_id.as_str(), 3),
            (self.content_hash.as_str(), 3),
            (self.workspace_id.as_str(), 5),
            (self.app_id.as_str(), 1),
            (self.owner_epoch.as_str(), 1),
            (self.title.as_str(), 1),
        ])?;
        super::occupancy::counted_extra_bytes(
            base,
            [
                (self.creation_id.len(), 1),
                (studio_title_bytes(&self.title), 3),
            ],
        )
    }
}

/// 发送认领占用区冻结的材料：只含身份/授权与记录本身，不含整份配置或 secret。
struct FrozenSendClaim {
    managed: Arc<ManagedBot>,
    record: SendRecord,
    membership: ChatMembership,
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

/// `crate::studio::new_id` 形态 `前缀-微秒hex-序号hex` 的 UTF-8 上界：
/// 两段 u64 各最多 16 个十六进制字符，再加两个分隔符。
fn generated_id_bytes(prefix: &str) -> usize {
    prefix.len() + 1 + 16 + 1 + 16
}

/// Studio 目录保存的标题是 `non_empty_title` 的 owned 副本：trim 后前 80 个字符。
fn studio_title_bytes(title: &str) -> usize {
    title.trim().chars().take(80).map(char::len_utf8).sum()
}

/// 绑定投影行在后续持久写期间仍存活的字段计权。
///
/// `creation_copies` 由该路径是否把投影创建身份移入工作行字段并再克隆一次决定：
/// 创建路径只做比较（1 份），入站受理会移入 FrozenInbound 并成为 SQL 参数（2 份）。
fn projection_freeze_bytes(
    projection: &super::storage::BindingProjection,
    creation_copies: usize,
) -> Result<usize, FeishuError> {
    super::occupancy::counted_text_bytes([
        (projection.chat_id.as_str(), 1),
        (projection.workspace_id.as_str(), 1),
        (projection.creation_id.as_str(), creation_copies),
        (projection.thread_id.as_deref().unwrap_or(""), 1),
        (projection.status.as_str(), 1),
        (projection.diagnostic.as_deref().unwrap_or(""), 1),
    ])
}

/// 入站受理的冻结文本上界：按占用任务内各持久 await 阶段同时存活的 owned 副本计。
///
/// | 阶段（首写位置） | 副本峰值 |
/// | --- | --- |
/// | `claim_thread_binding` 的 INSERT 参数（首写） | chat/creation/project 各 2 份 |
/// | `admit_inbound` 的 identities/work 两条 INSERT 参数 | 身份/正文/会话/应用/项目/创建各 2 份；bot_id 3 份（入口 String+冻结字段+参数） |
/// | `observe_direct` 的单聊目录参数 | chat/open 各 2 份 |
/// | `claim_inbound_work` 的 SELECT/UPDATE 参数 | bot/chat/message 各 2 份 |
///
/// 派生身份在 admit 与 claim 各构造一次（各自带一份 SQL 参数），两次不同时存活，按 2 份计；
/// worker 身份在写入前按 `new_id` 上界计 2 份。app/project/创建身份不在事件里，由
/// `admit_decided` 在首写前追加。
fn inbound_freeze_bytes(bot_id: &str, decision: &InboundDecision) -> Result<usize, FeishuError> {
    match decision {
        InboundDecision::Ignore => Ok(0),
        InboundDecision::Pairing {
            open_id,
            chat_id,
            display_name,
            ..
        } => {
            // `record_pairing` 与 `observe_direct` 各自构造 SQL 参数，与会话/发送者原值
            // 及配对请求身份同时跨 await 存活；请求身份按 `new_id` 上界计 2 份。
            let base = super::occupancy::counted_text_bytes([
                (bot_id, 1),
                (chat_id.as_str(), 2),
                (open_id.as_str(), 2),
                (display_name.as_deref().unwrap_or(""), 2),
            ])?;
            super::occupancy::counted_extra_bytes(base, [(generated_id_bytes("pair"), 2)])
        }
        InboundDecision::Execute {
            message_id,
            chat_id,
            open_id,
            text,
            attachments,
            content_hash,
            chat_kind,
            ..
        } => {
            let kind = match chat_kind {
                ChatKind::Direct => "direct",
                ChatKind::Group => "group",
            };
            // bot_id 有三份：受理入口持有的 String、入站冻结字段、SQL 参数。
            let base = super::occupancy::counted_text_bytes([
                (bot_id, 3),
                (message_id.as_str(), 2),
                (chat_id.as_str(), 2),
                (open_id.as_str(), 2),
                (text.as_str(), 2),
                (content_hash.as_str(), 2),
                (kind, 2),
            ])?;
            super::occupancy::counted_extra_bytes(
                base,
                [
                    (
                        super::storage::inbound_identity_bytes(bot_id, chat_id, message_id)?,
                        2,
                    ),
                    (generated_id_bytes("botwork"), 2),
                    (attachments.iter().map(|item| item.frozen_bytes()).sum(), 4),
                ],
            )
        }
    }
}

/// 既有工作行返回的真实材料计权：`admit_inbound` 提交后解出的 payload 会带着进入
/// `observe_direct` 与 `enqueue_inbound`/`claim_inbound_work` 的等待，随后交回复 owner。
/// 每字段按 2 份计（payload 本体 + 各自 SQL 参数或交接克隆）；`watch_input` 无固定上限，
/// 按真实长度计，合法空串为 0 字节。
fn resume_payload_bytes(payload: &FrozenInbound) -> Result<usize, FeishuError> {
    let base = super::occupancy::counted_text_bytes([
        (payload.bot_id.as_str(), 2),
        (payload.message_id.as_str(), 2),
        (payload.chat_id.as_str(), 2),
        (payload.open_id.as_str(), 2),
        (payload.text.as_str(), 2),
        (payload.content_hash.as_str(), 2),
        (payload.chat_kind.as_str(), 2),
        (payload.app_id.as_str(), 2),
        (payload.workspace_id.as_str(), 2),
        (payload.creation_id.as_str(), 2),
        (payload.watch_input.as_str(), 2),
    ])?;
    super::occupancy::counted_extra_bytes(
        base,
        [
            (
                super::storage::inbound_identity_bytes(
                    &payload.bot_id,
                    &payload.chat_id,
                    &payload.message_id,
                )?,
                2,
            ),
            (generated_id_bytes("botwork"), 2),
            (
                payload
                    .attachments
                    .iter()
                    .map(|attachment| attachment.frozen_bytes())
                    .sum(),
                2,
            ),
        ],
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
    let base = super::occupancy::counted_text_bytes(fields)?;
    base.checked_add(facts_bytes)
        .and_then(|total| total.checked_add(body_bytes))
        .ok_or_else(super::occupancy::freeze_budget_error)
}

impl BotRuntime {
    fn reject_closed_admission(&self, managed: &ManagedBot) -> Result<(), FeishuError> {
        if managed.admission_closed.load(Ordering::Acquire)
            || managed.submitting.load(Ordering::Acquire)
            || self.inner.sealed.load(Ordering::SeqCst) != 0
        {
            Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot admission is closed",
                true,
                None,
            ))
        } else {
            Ok(())
        }
    }

    pub async fn list_conversations(
        &self,
        bot_id: &str,
        cursor: Option<&str>,
        limit: Option<u32>,
    ) -> Result<BotConversationPage, FeishuError> {
        let managed = self.managed(bot_id).await?;
        let config = managed.config.lock().await.clone();
        let mut parsed = decode_cursor(cursor, bot_id)?;
        let page_size = limit.unwrap_or(20).clamp(1, 50);
        let directs = if parsed.kind == CursorKind::Directs {
            let rows = managed.store.list_observed_directs().await?;
            if rows.is_empty() {
                parsed = ParsedCursor {
                    kind: CursorKind::Groups,
                    token: None,
                };
            }
            rows
        } else {
            Vec::new()
        };
        let mut conversations = Vec::new();
        let next = match parsed.kind {
            CursorKind::Groups => {
                let token = self.token(&managed, &config).await?;
                let page = FeishuIm::new(self.inner.http.clone())
                    .list_chats(&token, parsed.token.as_deref(), page_size)
                    .await?;
                conversations.extend(page.chats.into_iter().map(|chat| BotConversation {
                    chat_id: chat.chat_id,
                    kind: chat.kind,
                    source: BotConversationSource::RemoteGroup,
                    name: chat.name,
                    last_observed_at: None,
                    thread_binding: None,
                }));
                if page.has_more {
                    Some(encode_cursor(
                        bot_id,
                        CursorKind::Groups,
                        page.page_token.as_deref(),
                    ))
                } else {
                    None
                }
            }
            CursorKind::Directs => {
                let start = parsed
                    .token
                    .as_deref()
                    .map(|token| {
                        token.parse::<usize>().map_err(|_| {
                            FeishuError::new(
                                FeishuErrorKind::Rejected,
                                "direct conversation cursor is not a valid page offset",
                                false,
                                None,
                            )
                        })
                    })
                    .transpose()?
                    .unwrap_or(0);
                let end = start.saturating_add(page_size as usize);
                let page = directs
                    .get(start..)
                    .unwrap_or(&[])
                    .iter()
                    .take(page_size as usize);
                let remaining = directs.len().saturating_sub(end);
                conversations.extend(page.cloned().map(|row| BotConversation {
                    chat_id: row.chat_id,
                    kind: BotConversationKind::Direct,
                    source: BotConversationSource::ObservedDirect,
                    name: row.name,
                    last_observed_at: Some(row.last_observed_at),
                    thread_binding: None,
                }));
                if remaining == 0 {
                    Some(encode_cursor(bot_id, CursorKind::Groups, None))
                } else {
                    Some(encode_cursor(
                        bot_id,
                        CursorKind::Directs,
                        Some(&end.to_string()),
                    ))
                }
            }
        };
        for conversation in &mut conversations {
            conversation.thread_binding = Some(
                self.conversation_binding(
                    &managed,
                    &config.id,
                    &config.workspace_id,
                    &conversation.chat_id,
                )
                .await?,
            );
        }
        Ok(BotConversationPage {
            bot_id: bot_id.to_string(),
            conversations,
            next_cursor: next,
        })
    }

    pub async fn read_messages(
        &self,
        bot_id: &str,
        chat_id: &str,
        start_time: Option<i64>,
        end_time: Option<i64>,
        cursor: Option<&str>,
        limit: Option<u32>,
    ) -> Result<BotMessagePage, FeishuError> {
        let managed = self.managed(bot_id).await?;
        let config = managed.config.lock().await.clone();
        let membership = self.prepare_chat_access(&managed, &config, chat_id).await?;
        self.authorize_chat(&config, chat_id, SendAuthority::Owner, &membership)?;
        let token = self.token(&managed, &config).await?;
        let page_token = decode_history_cursor(cursor, bot_id, chat_id, start_time, end_time)?;
        let (messages, next) = FeishuIm::new(self.inner.http.clone())
            .list_messages(
                &token,
                chat_id,
                start_time,
                end_time,
                page_token.as_deref(),
                limit.unwrap_or(20),
            )
            .await?;
        Ok(BotMessagePage {
            bot_id: bot_id.to_string(),
            chat_id: chat_id.to_string(),
            messages: messages.iter().map(to_product_message).collect(),
            next_cursor: next
                .map(|token| encode_history_cursor(bot_id, chat_id, start_time, end_time, &token)),
        })
    }

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
    pub(super) async fn send_file_as(
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
        let acquisition = managed.file_delivery.lock();
        tokio::pin!(acquisition);
        let _file_delivery = tokio::select! {
            biased;
            _ = cancel.cancelled() => return Err(file_delivery_cancelled()),
            guard = std::future::poll_fn(|cx| {
                let polled = std::future::Future::poll(acquisition.as_mut(), cx);
                // Observe a real pending acquisition, not merely a task that was spawned.
                #[cfg(test)]
                if polled.is_pending() {
                    managed.file_delivery_waiting.notify_one();
                }
                polled
            }) => guard,
        };
        if cancel.is_cancelled() {
            return Err(file_delivery_cancelled());
        }
        let initial = super::files::initial_record(operation_id, target, file)?;
        if let Some(existing) = managed.store.load_send(&initial.operation_id).await? {
            super::storage::verify_send_identity(
                &existing,
                &initial.operation_id,
                &initial.bot_id,
                &initial.chat_id,
                &initial.content_hash,
            )?;
            super::files::validate_record(&existing)?;
            self.authorize_replay_source(&managed, &SendAuthority::AutoReply)
                .await?;
            if !super::files::resumable(&existing) {
                return Ok(existing);
            }
        }
        let config = managed.config.lock().await.clone();
        let membership = self
            .prepare_chat_access(&managed, &config, &initial.chat_id)
            .await?;
        let token = self.token(&managed, &config).await?;
        let facts_bytes = super::storage::segment_facts_bytes(&initial.segments)?;
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
                super::protocol::files::FeishuFileAdapter {
                    http: self.inner.http.clone(),
                    token,
                },
            )
            .map_err(|error| super::files::local_error(error.to_string()))?;
        super::files::deliver(
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
            let content_hash = super::protocol::im::content_hash(&operation_id, &chat_id, &text);
            super::storage::verify_send_identity(
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
        let facts_bytes = super::storage::segment_facts_bytes(&initial.segments)?;
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
            self.authorize_chat(&current, &record.chat_id, authority, &membership)?;
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

    pub async fn authorized_bots(&self, workspace_id: &str) -> Vec<BotSnapshot> {
        let previous = self.snapshot().await;
        self.list_snapshots(&previous)
            .await
            .into_iter()
            .filter(|bot| bot.workspace_id == workspace_id && bot.tools_enabled)
            .collect()
    }

    async fn conversation_binding(
        &self,
        managed: &ManagedBot,
        bot_id: &str,
        workspace_id: &str,
        chat_id: &str,
    ) -> Result<BotConversationThreadBinding, FeishuError> {
        let projection = managed
            .store
            .binding_for_chat(chat_id, bot_id, workspace_id)
            .await?;
        Ok(product_binding(bot_id, workspace_id, projection))
    }

    pub async fn create_conversation_thread(
        &self,
        request: CreateBotConversationThreadRequest,
        owner_epoch: &str,
    ) -> Result<BotConversationThreadReply, FeishuError> {
        let CreateBotConversationThreadRequest {
            operation_id,
            bot_id,
            chat_id,
            expected_config_revision,
            expected_binding_revision,
        } = request;
        let managed = self.managed(&bot_id).await?;
        let content_hash = super::protocol::im::content_hash(
            &operation_id,
            &chat_id,
            &format!("{expected_binding_revision}"),
        );
        let creation_id = format!("botthread:{bot_id}:{chat_id}:{operation_id}");
        // 已持久受理的同一操作先以本地指纹识别：身份一致即继续原创建，不重复目录
        // 核验，也不让已接纳意图卡在联网或 keyring 准备上；输入不同必须显式拒绝。
        let accepted = match managed.store.load_binding_operation(&operation_id).await? {
            Some(existing) => {
                if !binding_operation_matches(
                    &existing,
                    &operation_id,
                    &bot_id,
                    &chat_id,
                    &content_hash,
                    expected_binding_revision,
                ) {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "operationId already used with different conversation Thread input",
                        false,
                        None,
                    ));
                }
                true
            }
            None => false,
        };
        // 首次受理才做联网可见性核验与过期 revision 快速拒绝；最终裁决仍在准入内。
        // 接续路径只读取所需标量，不搬运整份配置与可信集合。
        let (name, app_id, workspace_id) = if accepted {
            let current = managed.config.lock().await;
            (
                current.name.clone(),
                current.feishu().app_id.clone(),
                current.workspace_id.clone(),
            )
        } else {
            let config = managed.config.lock().await.clone();
            if config.config_revision != expected_config_revision {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "stale bot config revision",
                    true,
                    None,
                ));
            }
            let membership = self
                .prepare_chat_access(&managed, &config, &chat_id)
                .await?;
            self.authorize_chat(&config, &chat_id, SendAuthority::Owner, &membership)?;
            (
                config.name.clone(),
                config.feishu().app_id.clone(),
                config.workspace_id.clone(),
            )
        };
        // 标题与操作字段都在此预生成并计入冻结预算：首次持久写前就能判定是否放得下。
        let title = format!("{name} / {chat_id}");
        let Some(runtime) = self.studio_host() else {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "studio runtime host is unavailable",
                true,
                None,
            ));
        };
        // 首次意图的联网可见性与凭据核验已在占用区之前完成；已受理接续不重复核验，
        // 最终身份裁决仍在准入内。本地 Thread 创建与绑定接续由受管占用任务持有到真实
        // 终态，调用方取消只是不再等待回执。
        let worker = self.clone();
        let frozen = FrozenBinding {
            runtime,
            managed,
            bot_id,
            chat_id,
            workspace_id,
            title,
            app_id,
            operation_id,
            content_hash,
            creation_id,
            owner_epoch: owner_epoch.to_string(),
            expected_config_revision,
            expected_binding_revision,
        };
        let text_bytes = frozen.text_bytes()?;
        self.submit_occupancy(text_bytes, move |budget| async move {
            worker.create_binding_thread(frozen, budget).await
        })
        .await
    }

    /// 占用区内的本地创建与绑定接续；只在受管占用任务中运行。
    async fn create_binding_thread(
        &self,
        frozen: FrozenBinding,
        mut budget: OccupancyBudget,
    ) -> Result<BotConversationThreadReply, FeishuError> {
        let FrozenBinding {
            runtime,
            managed,
            bot_id,
            chat_id,
            workspace_id,
            title,
            app_id,
            operation_id,
            content_hash,
            creation_id,
            owner_epoch,
            expected_config_revision,
            expected_binding_revision,
        } = frozen;
        let frozen_creation = {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(&managed)?;
            // 身份判据在权威准入内重新核对：占用前的快速检查与联网核验都不能代替它。
            // 只做比较并取回水位标量：不克隆整份配置，也不把 guard 持到 DB await 之后。
            let (identity_ok, current_revision) = {
                let current = managed.config.lock().await;
                (
                    current.feishu().app_id == app_id && current.workspace_id == workspace_id,
                    current.config_revision,
                )
            };
            if !identity_ok {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot identity changed before conversation Thread bind",
                    true,
                    None,
                ));
            }
            // 操作记录只在确认是首次受理后才构造：接续路径不为它保留额外副本。
            if let Some(existing) = managed.store.load_binding_operation(&operation_id).await? {
                if !binding_operation_matches(
                    &existing,
                    &operation_id,
                    &bot_id,
                    &chat_id,
                    &content_hash,
                    expected_binding_revision,
                ) {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "operationId already used with different conversation Thread input",
                        false,
                        None,
                    ));
                }
                // 身份核验后只保留真正需要的已存字段，其余读出的 owned 值随解构释放，
                // 并在下一个 await 之前按实际保留长度计权。
                let super::storage::BindingOperation {
                    creation_id: existing_creation,
                    thread_id: existing_thread,
                    ..
                } = existing;
                if let Some(existing_thread) = existing_thread {
                    // 已完成操作：只保留 A 的创建身份与 Thread 身份，各按 1 份跨读取等待。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (existing_creation.as_str(), 1),
                        (existing_thread.as_str(), 1),
                    ])?)?;
                    // 在同一准入内读取当前权威投影：只有仍精确指向 A 的完成结果才算
                    // NoChange；被后继显式操作替代时明确报告已替代，不返回后继结果。
                    let projection = managed
                        .store
                        .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                        .await?;
                    if projection.status == "bound"
                        && projection.creation_id == existing_creation
                        && projection.thread_id.as_deref() == Some(existing_thread.as_str())
                    {
                        let binding = product_binding(&bot_id, &workspace_id, projection);
                        return Ok(binding_reply(
                            operation_id,
                            &owner_epoch,
                            binding,
                            CommandDisposition::NoChange,
                        ));
                    }
                    if projection.creation_id == existing_creation {
                        // 同一创建身份却不是该完成结果：持久身份自相矛盾，不默认化。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    if projection.creation_id.is_empty() {
                        // 当前行没有可比较的创建身份：无法证明是后继操作，也不猜成已替代。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    return Err(super::storage::binding_superseded());
                }
                // 已持久受理但未完成的同一操作：沿用原创建身份继续，不重复切换绑定，
                // 也不因名称、可信范围或启停等非身份配置变化重新创建。
                // 未完成的绑定还必须仍归属本创建：被后继显式操作切换过时不再写回。
                budget.reserve_more(super::occupancy::counted_text_bytes([(
                    existing_creation.as_str(),
                    1,
                )])?)?;
                let projection = managed
                    .store
                    .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                    .await?;
                if projection.creation_id != existing_creation {
                    return Err(super::storage::binding_needs_recovery());
                }
                // 接续身份与提交给创建接口的克隆、Studio 交回身份及 SQL 参数同时跨 await
                // 存活（峰值见 `CREATE_CALL_CREATION_COPIES`）：首写前补足余下份数。
                budget.reserve_more(super::occupancy::counted_extra_bytes(
                    0,
                    [(existing_creation.len(), CREATE_CALL_CREATION_COPIES - 1)],
                )?)?;
                existing_creation
            } else {
                // 首次受理：预期配置 revision 必须等于当前权威值。
                if current_revision != expected_config_revision {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Conflict,
                        "stale bot config revision",
                        true,
                        None,
                    ));
                }
                let projection = managed
                    .store
                    .binding_for_chat(&chat_id, &bot_id, &workspace_id)
                    .await?;
                let provable_partial = projection.status == "creating"
                    && !projection
                        .thread_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty())
                    && projection.creation_id == creation_id
                    && projection.workspace_id == workspace_id
                    && Some(projection.revision) == expected_binding_revision.checked_add(1);
                // 进入 job 时已按 1 份预冻结本次派生身份；首写前补足创建调用链的
                // job 持有峰值（见 `CREATE_CALL_CREATION_COPIES`），使单项放不下只会在
                // 任何持久写之前被判定。
                budget.reserve_more(super::occupancy::counted_text_bytes([(
                    creation_id.as_str(),
                    CREATE_CALL_CREATION_COPIES - 1,
                )])?)?;
                // 绑定投影行在随后的 adopt/begin 期间仍存活：按其读取到的实际字段计权。
                budget.reserve_more(projection_freeze_bytes(&projection, 1)?)?;
                let operation = super::storage::BindingOperation {
                    operation_id: operation_id.clone(),
                    bot_id: bot_id.clone(),
                    chat_id: chat_id.clone(),
                    content_hash: content_hash.clone(),
                    expected_revision: expected_binding_revision,
                    creation_id: creation_id.clone(),
                    thread_id: None,
                };
                // 操作记录字段与标题已在 FrozenBinding 的冻结预算中覆盖，
                // 因此这里不会在写入之后才发现单项放不下。
                if provable_partial {
                    // 可证明属于本请求的部分现场：只补齐缺失的操作记录，
                    // 不再次切换绑定水位，也不覆盖其他创建。
                    managed
                        .store
                        .adopt_binding_operation(
                            &chat_id,
                            expected_binding_revision,
                            &workspace_id,
                            &operation,
                        )
                        .await?;
                    self.request_publish();
                } else {
                    if projection.status == "creating"
                        && !projection
                            .thread_id
                            .as_ref()
                            .is_some_and(|id| !id.is_empty())
                    {
                        // 无法证明归属的创建中记录：保留现场并要求本机恢复，
                        // 不覆盖其他创建，也不把无接续证明的记录报告为正常进行中。
                        return Err(super::storage::binding_needs_recovery());
                    }
                    // 首次受理：绑定水位切换与操作记录在同一次提交中生效。
                    managed
                        .store
                        .begin_binding_operation(
                            &chat_id,
                            expected_binding_revision,
                            &workspace_id,
                            &operation,
                        )
                        .await?;
                    // 首次真实占用已提交：在任何后继保存 await 之前主动重建。
                    self.request_publish();
                }
                creation_id
            }
        };
        // 创建身份与预生成标题都已在首写前计入预算：这里不再追加、也不再临时派生。
        let created = runtime
            .create_thread_with_id(frozen_creation.clone(), &workspace_id, &title)
            .await
            .map_err(|error| {
                FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("failed to create bot Thread: {error}"),
                    true,
                    None,
                )
            })?;
        {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(&managed)?;
            // 只核对身份字段：名称、可信范围或启停等非身份配置变化不应把已创建的
            // 身份变成不可恢复的半状态。短锁内比较，不克隆配置。
            let identity_ok = {
                let current = managed.config.lock().await;
                current.feishu().app_id == app_id && current.workspace_id == workspace_id
            };
            if !identity_ok {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "bot identity changed before conversation Thread bind",
                    true,
                    None,
                ));
            }
            let stored = managed.store.load_binding_operation(&operation_id).await?;
            if stored
                .filter(|item| {
                    item.creation_id == frozen_creation
                        && item.bot_id == bot_id
                        && item.chat_id == chat_id
                        && item.content_hash == content_hash
                        && item.expected_revision == expected_binding_revision
                })
                .is_none()
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "conversation Thread creation is no longer owned by this operation",
                    true,
                    None,
                ));
            }
            managed
                .store
                .bind_thread(&chat_id, &created.id, &frozen_creation, &workspace_id)
                .await?;
            managed
                .store
                .save_binding_operation(&super::storage::BindingOperation {
                    operation_id: operation_id.clone(),
                    bot_id: bot_id.clone(),
                    chat_id: chat_id.clone(),
                    content_hash,
                    expected_revision: expected_binding_revision,
                    creation_id: frozen_creation,
                    thread_id: Some(created.id.clone()),
                })
                .await?;
        }
        let binding = self
            .conversation_binding(&managed, &bot_id, &workspace_id, &chat_id)
            .await?;
        Ok(binding_reply(
            operation_id,
            &owner_epoch,
            binding,
            CommandDisposition::Applied,
        ))
    }

    pub async fn shutdown(&self) -> Result<(), FeishuError> {
        if self.runtime_released() {
            return Ok(());
        }
        let previous = self
            .inner
            .sealed
            .fetch_max(super::owner::BOTS_RUNTIME_SEALED, Ordering::SeqCst);
        if previous == super::owner::BOTS_RUNTIME_RELEASED {
            return Ok(());
        }
        // 占用任务必须在取消发布器之前收束：reply_cancel.cancel() 会让 publisher
        // 自行退出，之后再等待就无法保证任务终态通知被真实发布。收束后先经既有
        // publish_gate 做一次真实重建，再冻结并关闭发布器与其余任务。
        self.drain_occupancy().await?;
        self.inner.reply_cancel.cancel();
        self.inner.publish_notify.notify_one();
        self.close_registration().await?;
        self.close_publisher().await?;
        {
            let mut slot = self.inner.recovery.lock().await;
            if let Some(recovery) = slot.as_mut() {
                let joined = std::pin::Pin::new(recovery).await;
                *slot = None;
                if let Err(error) = joined
                    && !error.is_cancelled()
                {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Unavailable,
                        "bot inbound recovery join failed",
                        true,
                        None,
                    ));
                }
            }
        }
        self.drain_replies().await?;
        self.close_operations().await?;
        self.close_connection_watches().await?;
        let records = self.inner.bots.lock().await;
        let published = records
            .values()
            .filter_map(|record| record.published.clone())
            .collect::<Vec<_>>();
        drop(records);
        for bot in published {
            if let Err(error) = bot.connection.close().await {
                // 及时上报已观察错误：不再 await 其他资源，剩余连接保持登记可重试。
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    format!("bot connection close failed: {error}"),
                    true,
                    None,
                ));
            }
        }
        self.publish().await;
        self.release_runtime_records().await;
        self.clear_host();
        Ok(())
    }

    pub(crate) async fn start_connection(
        &self,
        managed: &Arc<ManagedBot>,
        config: BotConfigFile,
        secret: String,
    ) -> Result<(), FeishuError> {
        let expected = {
            let _admission = managed.admission.lock().await;
            self.reject_closed_admission(managed)?;
            let current = managed.config.lock().await.clone();
            if current.config_revision != config.config_revision
                || current.feishu().app_id != config.feishu().app_id
                || current.workspace_id != config.workspace_id
                || current.enabled != config.enabled
                || current.tools_enabled != config.tools_enabled
                || current.feishu().trusted_open_ids != config.feishu().trusted_open_ids
                || current.feishu().trusted_chat_ids != config.feishu().trusted_chat_ids
                || current.name != config.name
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Conflict,
                    "connection start was superseded by a newer bot config",
                    true,
                    None,
                ));
            }
            if !current.enabled {
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot is disabled",
                    true,
                    None,
                ));
            }
            managed.generation.fetch_add(1, Ordering::AcqRel) + 1
        };
        let host = Arc::new(RuntimeInboundHost {
            runtime: self.clone(),
            current: managed.generation.clone(),
            expected,
        });
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Conflict,
                "connection start was superseded before launch",
                true,
                None,
            ));
        }
        managed
            .connection
            .start(self.inner.http.clone(), config, secret, host)
            .await?;
        // 先取标量再 await：不把 config guard 持到入站恢复的 DB 操作之后。
        let bot_id = managed.config.lock().await.id.clone();
        let _ = self.restore_unfinished_inbound(&bot_id).await;
        Ok(())
    }

    pub(crate) async fn prefetch_bot_open_id(
        &self,
        host: &RuntimeInboundHost,
        config: &BotConfigFile,
    ) -> Result<String, FeishuError> {
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot identity prefetch was superseded",
                true,
                None,
            ));
        }
        let managed = self.managed(&config.id).await?;
        if let Some((cached_generation, existing)) = managed.bot_open_id.lock().await.clone()
            && cached_generation == host.expected
        {
            return Ok(existing);
        }
        let token = self.token(&managed, config).await?;
        let open_id = super::protocol::im::FeishuIm::new(self.inner.http.clone())
            .bot_open_id(&token)
            .await?;
        if !host.is_current() {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot identity prefetch was superseded",
                true,
                None,
            ));
        }
        let mut cache = managed.bot_open_id.lock().await;
        *cache = Some((host.expected, open_id.clone()));
        Ok(open_id)
    }

    pub(crate) async fn token(
        &self,
        managed: &ManagedBot,
        config: &BotConfigFile,
    ) -> Result<String, FeishuError> {
        self.inner
            .http
            .policy()
            .require_synthetic_app(&config.feishu().app_id)?;
        if managed
            .token
            .identity_matches(&config.feishu().app_id)
            .await
        {
            return managed.token.access_token().await;
        }
        let owner = self.ensure_record(&config.id).await?;
        owner.read_selected_secret(config).await?;
        managed.token.access_token().await
    }

    pub(super) async fn prepare_auto_reply_token(
        &self,
        managed: &ManagedBot,
        chat_id: &str,
    ) -> Result<String, FeishuError> {
        let config = managed.config.lock().await.clone();
        let membership = self.prepare_chat_access(managed, &config, chat_id).await?;
        self.authorize_chat(&config, chat_id, SendAuthority::AutoReply, &membership)?;
        self.token(managed, &config).await
    }

    fn authorize_chat(
        &self,
        config: &BotConfigFile,
        chat_id: &str,
        authority: SendAuthority,
        membership: &ChatMembership,
    ) -> Result<(), FeishuError> {
        if matches!(authority, SendAuthority::Tool { .. }) && !config.tools_enabled {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "project tools are not enabled for this bot",
                false,
                None,
            ));
        }
        if let SendAuthority::Tool { workspace_id } = &authority
            && config.workspace_id != *workspace_id
        {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "bot is not authorized for this project",
                false,
                None,
            ));
        }
        if membership.covers(chat_id) {
            Ok(())
        } else {
            Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "chat is not an authorized group or observed direct conversation",
                false,
                None,
            ))
        }
    }

    /// 回读既有结果的本地来源授权：只读当前机器人的工具授权标量，不联网、不读 keyring。
    /// Tool 来源不得因重放绕过撤销的项目工具授权；Owner 与已受理入站回复维持其原来源语义。
    async fn authorize_replay_source(
        &self,
        managed: &ManagedBot,
        authority: &SendAuthority,
    ) -> Result<(), FeishuError> {
        let SendAuthority::Tool { workspace_id } = authority else {
            return Ok(());
        };
        let current = managed.config.lock().await;
        if !current.tools_enabled {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "project tools are not enabled for this bot",
                false,
                None,
            ));
        }
        if current.workspace_id != *workspace_id {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "bot is not authorized for this project",
                false,
                None,
            ));
        }
        Ok(())
    }

    async fn prepare_chat_access(
        &self,
        managed: &ManagedBot,
        config: &BotConfigFile,
        chat_id: &str,
    ) -> Result<ChatMembership, FeishuError> {
        let directs = managed.store.list_observed_directs().await?;
        if directs.iter().any(|row| row.chat_id == chat_id) {
            return Ok(ChatMembership {
                observed_direct: true,
                remote_group: false,
            });
        }
        let token = self.token(managed, config).await?;
        let im = FeishuIm::new(self.inner.http.clone());
        let mut page_token = None;
        loop {
            let page = im.list_chats(&token, page_token.as_deref(), 50).await?;
            if page.chats.iter().any(|chat| chat.chat_id == chat_id) {
                return Ok(ChatMembership {
                    observed_direct: false,
                    remote_group: true,
                });
            }
            if !page.has_more {
                break;
            }
            page_token = page.page_token;
            if page_token.is_none() {
                break;
            }
        }
        Ok(ChatMembership {
            observed_direct: false,
            remote_group: false,
        })
    }

    pub(crate) async fn managed(&self, bot_id: &str) -> Result<Arc<ManagedBot>, FeishuError> {
        self.inner
            .bots
            .lock()
            .await
            .get(bot_id)
            .and_then(|record| record.published.clone())
            .ok_or_else(|| {
                FeishuError::new(FeishuErrorKind::NotFound, "bot not found", false, None)
            })
    }

    pub(crate) async fn reply(
        &self,
        operation_id: String,
        changed: bool,
        owner_epoch: &str,
    ) -> BotsCommandReply {
        let snapshot = self.snapshot().await;
        BotsCommandReply {
            stamp: Some(ResourceStamp {
                resource_key: "bots".to_string(),
                owner_epoch: owner_epoch.to_string(),
                revision: snapshot.revision,
            }),
            receipt: StudioCommandReceipt {
                operation_id,
                disposition: if changed {
                    CommandDisposition::Applied
                } else {
                    CommandDisposition::NoChange
                },
                targets: vec![ResourceStamp {
                    resource_key: "bots".to_string(),
                    owner_epoch: owner_epoch.to_string(),
                    revision: snapshot.revision,
                }],
                effect: CommandEffectPoint::Immediate,
                effective: true,
                durable: true,
                requires_identity_observation: false,
            },
            snapshot,
        }
    }

    pub(crate) async fn admit_decision(
        &self,
        bot_id: &str,
        connection_generation: u64,
        decision: InboundDecision,
    ) -> Result<(), FeishuError> {
        let managed = self.managed(bot_id).await?;
        if matches!(decision, InboundDecision::Ignore) {
            // 没有持久写入：不占用受管任务，也没有需要重建的能力变化。
            return Ok(());
        }
        let bot_id = bot_id.to_string();
        let text_bytes = inbound_freeze_bytes(&bot_id, &decision)?;
        let worker = self.clone();
        // 真实受理区归受管占用任务：调用方（连接任务）取消只是不再等待回执，
        // 已提交的受理、配对、通知与入站工作登记仍由 owner 完成。
        self.submit_occupancy(text_bytes, move |budget| async move {
            worker
                .admit_decided(managed, &bot_id, connection_generation, decision, budget)
                .await
        })
        .await
    }

    /// 真实受理区（配对与执行）；只在受管占用任务中运行。
    async fn admit_decided(
        &self,
        managed: Arc<ManagedBot>,
        bot_id: &str,
        connection_generation: u64,
        decision: InboundDecision,
        mut budget: OccupancyBudget,
    ) -> Result<(), FeishuError> {
        match decision {
            InboundDecision::Ignore => Ok(()),
            InboundDecision::Pairing {
                open_id,
                chat_id,
                display_name,
                chat_kind,
            } => {
                {
                    let _admission = managed.admission.lock().await;
                    self.reject_closed_admission(&managed)?;
                    if managed.generation.load(Ordering::Acquire) != connection_generation {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            "stale inbound connection generation",
                            true,
                            None,
                        ));
                    }
                    // 配对请求身份及其 SQL 参数已在冻结预算中按 `new_id` 上界覆盖。
                    let request_id = new_id("pair");
                    managed
                        .store
                        .record_pairing(&request_id, &open_id, display_name.as_deref())
                        .await?;
                    if chat_kind == ChatKind::Direct {
                        managed
                            .store
                            .observe_direct(&chat_id, Some(&open_id), display_name.as_deref())
                            .await?;
                    }
                }
                self.request_publish();
                Ok(())
            }
            InboundDecision::Execute {
                message_id,
                chat_id,
                open_id,
                text,
                attachments,
                content_hash,
                chat_kind,
            } => {
                let admitted = {
                    let _admission = managed.admission.lock().await;
                    self.reject_closed_admission(&managed)?;
                    if managed.generation.load(Ordering::Acquire) != connection_generation {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            "stale inbound connection generation",
                            true,
                            None,
                        ));
                    }
                    // 只取本路径真正需要的配置标量，并在首次持久写之前计入预算；
                    // 不克隆整份配置，也不跨 DB await 持有 config guard。
                    let (app_id, workspace_id) = {
                        let current = managed.config.lock().await;
                        (
                            current.feishu().app_id.clone(),
                            current.workspace_id.clone(),
                        )
                    };
                    // app/project 会与工作行 INSERT 的 SQL 参数同时存活：按 2 份计。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (app_id.as_str(), 2),
                        (workspace_id.as_str(), 2),
                    ])?)?;
                    let creation_id = format!("botthread:{bot_id}:{chat_id}");
                    // 派生创建身份同时存在于 claim 的 INSERT 参数与工作行参数：按 2 份计。
                    budget.reserve_more(super::occupancy::counted_text_bytes([(
                        creation_id.as_str(),
                        2,
                    )])?)?;
                    // claim 可能写入 NoRow 新行：该行投影的会话/项目/创建身份/固定状态
                    // 在写入后必然被读取并存活到 admit，因此在其可能写入之前按完整可知
                    // 上界预留，而不是写完之后才判单项是否放得下。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (chat_id.as_str(), 1),
                        (workspace_id.as_str(), 1),
                        (creation_id.as_str(), 2),
                        ("creating", 1),
                    ])?)?;
                    // This check and the later frozen-target check run under managed.admission,
                    // the same lock permanent deletion takes before its final ledger clear.
                    self.ensure_reply_admission(&workspace_id, &creation_id)
                        .await?;
                    let claim = managed
                        .store
                        .claim_thread_binding(&chat_id, &creation_id, &workspace_id)
                        .await?;
                    // claim 落盘即把该 chat 的会话绑定写入 thread_bindings，
                    // 身份占用由空变为非空，正是 canChangeProject 的真实来源。
                    // notify_one 既不取锁也不挂起，可在受理临界区内直接把该事实交给
                    // 既有合并发布链；之后的失败、partial 写入或 ACK 前取消
                    // 都不会让 canonical 能力投影停留在旧值。
                    self.request_publish();
                    if let super::storage::ThreadBindingClaim::NeedsAttention { diagnostic } =
                        &claim
                    {
                        return Err(FeishuError::new(
                            FeishuErrorKind::Unavailable,
                            diagnostic.clone(),
                            false,
                            None,
                        ));
                    }
                    // claim 自带的身份副本在读取持久投影前释放：后续只按投影事实计权，
                    // 不把两份读出的身份同时留到 admit。
                    drop(claim);
                    // 冻结真实绑定身份与版本：以持久投影为准，不用本次临时派生
                    // 或常数水位替代既有本地上下文。
                    let projection = managed
                        .store
                        .binding_for_chat(&chat_id, bot_id, &workspace_id)
                        .await?;
                    #[cfg(test)]
                    {
                        let pause = {
                            let mut gate = self
                                .inner
                                .deletion_tests
                                .inbound
                                .lock()
                                .unwrap_or_else(std::sync::PoisonError::into_inner);
                            if gate
                                .as_ref()
                                .is_some_and(|(target, _, _)| target == &chat_id)
                            {
                                gate.take()
                            } else {
                                None
                            }
                        };
                        if let Some((_, entered, release)) = pause {
                            let _ = entered.send(());
                            let _ = release.await;
                        }
                    }
                    self.ensure_reply_admission(&workspace_id, &projection.creation_id)
                        .await?;
                    if let Some(target) = &projection.thread_id {
                        self.ensure_reply_admission(&workspace_id, target).await?;
                    }
                    if projection.creation_id.is_empty() {
                        return Err(super::storage::binding_needs_recovery());
                    }
                    if projection.workspace_id != workspace_id {
                        // 绑定归属的项目才是权威：不允许把受理写进另一项目。
                        return Err(FeishuError::new(
                            FeishuErrorKind::Conflict,
                            "bot project changed after conversation Thread binding",
                            false,
                            None,
                        ));
                    }
                    // 新行形状的投影已在上方按可知上界预留；既有行（claim 未写入）可能带
                    // 更大的历史创建身份、Thread 身份、状态与诊断，此时按其真实字段追加。
                    let new_row_projection = projection.creation_id == creation_id
                        && projection.workspace_id == workspace_id
                        && projection.chat_id == chat_id
                        && projection.thread_id.is_none()
                        && projection.status == "creating"
                        && projection.diagnostic.is_none();
                    if !new_row_projection {
                        budget.reserve_more(projection_freeze_bytes(&projection, 2)?)?;
                    }
                    let (frozen_creation, frozen_revision) =
                        (projection.creation_id, projection.revision);
                    let inbound = FrozenInbound {
                        bot_id: bot_id.to_string(),
                        message_id,
                        chat_id,
                        content_hash,
                        text,
                        attachments,
                        open_id,
                        chat_kind: match chat_kind {
                            ChatKind::Direct => "direct".to_string(),
                            ChatKind::Group => "group".to_string(),
                        },
                        app_id,
                        workspace_id,
                        creation_id: frozen_creation,
                        binding_revision: frozen_revision,
                        watch_input: String::new(),
                    };
                    // 首次受理沿用本次冻结输入本身，重复命中的续跑身份只接受持久值：
                    // 两路都不再为同一份材料额外复制一遍正文与身份。
                    // 按值移入受理：首次受理把同一份冻结输入交回，不再复制正文与身份；
                    // 重复命中的续跑身份只接受持久值。
                    let admitted = managed.store.admit_inbound(inbound).await?;
                    match &admitted {
                        InboundAdmit::DuplicateResume(payload) => {
                            // 既有工作行的真实材料（含无固定上限的 watch_input）会带着
                            // 进入 observe/enqueue 的下一次等待：按实际字段先计权。
                            budget.reserve_more(resume_payload_bytes(payload)?)?;
                            if payload.chat_kind == "direct" {
                                managed
                                    .store
                                    .observe_direct(&payload.chat_id, Some(&payload.open_id), None)
                                    .await?;
                            }
                        }
                        InboundAdmit::Fresh(payload) if payload.chat_kind == "direct" => {
                            managed
                                .store
                                .observe_direct(&payload.chat_id, Some(&payload.open_id), None)
                                .await?;
                        }
                        _ => {}
                    }
                    admitted
                };
                match admitted {
                    InboundAdmit::DuplicateCompleted => Ok(()),
                    InboundAdmit::Fresh(payload) | InboundAdmit::DuplicateResume(payload) => {
                        self.enqueue_inbound(payload).await
                    }
                }
            }
        }
    }

    async fn enqueue_inbound(&self, inbound: FrozenInbound) -> Result<(), FeishuError> {
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let worker_id = new_id("botwork");
        let managed = self.managed(&inbound.bot_id).await?;
        // Reap before acquiring budget: a finished task still owns its permit
        // until the registration owner observes its join and ledger ACK.
        let mut replies = self.inner.replies.lock().await;
        replies.reap();
        replies.retry_finishes(self, None).await?;
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let binding = managed
            .store
            .binding_for_chat(&inbound.chat_id, &inbound.bot_id, &inbound.workspace_id)
            .await?;
        // Never route a failed/attention read as an absent binding. A bound
        // Thread is authoritative; only a proven creation may use creation_id.
        let registered_thread_id = match binding.status.as_str() {
            "bound" => binding
                .thread_id
                .ok_or_else(super::storage::binding_needs_recovery)?,
            "creating"
                if binding.thread_id.is_none()
                    && binding.creation_id == inbound.creation_id
                    && binding.revision == inbound.binding_revision
                    && !inbound.creation_id.is_empty() =>
            {
                inbound.creation_id.clone()
            }
            "absent"
                if binding.thread_id.is_none()
                    && binding.revision == inbound.binding_revision
                    && inbound.binding_revision == 0
                    && !inbound.creation_id.is_empty() =>
            {
                inbound.creation_id.clone()
            }
            _ => return Err(super::storage::binding_needs_recovery()),
        };
        // Admission and registration share archive's mutex. Reject before
        // claiming, so a rejected dispatch creates no new finisher obligation.
        self.ensure_reply_admission(&inbound.workspace_id, &registered_thread_id)
            .await?;
        let Ok(permit) = self.inner.reply_slots.clone().try_acquire_owned() else {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot reply budget is full",
                true,
                None,
            ));
        };
        match managed
            .store
            .claim_inbound_work(
                &inbound.bot_id,
                &inbound.chat_id,
                &inbound.message_id,
                &worker_id,
            )
            .await?
        {
            InboundClaim::Completed => {
                drop(permit);
                return Ok(());
            }
            InboundClaim::Busy => {
                drop(permit);
                // 重复推送/重连命中的是同一持久身份下进行中的工作：
                // 受理已完成，重复消息无需再受理，也不能重复启动模型。
                return Ok(());
            }
            InboundClaim::Missing => {
                drop(permit);
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "inbound work is missing after admit",
                    true,
                    None,
                ));
            }
            InboundClaim::NeedsAttention => {
                drop(permit);
                return Ok(());
            }
            // 退避未到期：留给到期后的恢复扫描，不占 reply 槽位。
            InboundClaim::NotDue => {
                drop(permit);
                return Ok(());
            }
            InboundClaim::Claimed => {}
        }
        let runtime = self.clone();
        let cancel = self.inner.reply_cancel.child_token();
        let identity = ReplyIdentity::new(&inbound, &worker_id);
        let admission = if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ))
        } else {
            self.ensure_reply_admission(&inbound.workspace_id, &registered_thread_id)
                .await
        };
        if let Err(error) = admission {
            replies
                .finish_unstarted(self, registered_thread_id, identity, cancel, permit)
                .await?;
            return Err(error);
        }
        let dispatch_thread_id = registered_thread_id.clone();
        replies.spawn(
            registered_thread_id,
            identity.clone(),
            cancel.clone(),
            permit,
            async move {
                let outcome = runtime
                    .dispatch_prompt(inbound, &worker_id, &dispatch_thread_id, cancel)
                    .await;
                runtime.finish_reply(identity, outcome).await
            },
        );
        Ok(())
    }

    pub(crate) async fn restore_unfinished_inbound(&self, bot_id: &str) -> Result<(), FeishuError> {
        let managed = self.managed(bot_id).await?;
        // 只恢复到期工作：pending、退避到期的 failed 与租约过期的 claimed。
        // 退避未到期的工作不被固定频率重派，正常 Pending/待本地交互不耗失败预算。
        let due = managed.store.list_due_inbound(bot_id).await?;
        for inbound in due {
            if let Err(error) = self.enqueue_inbound(inbound).await {
                tracing::warn!(bot_id, %error, "failed to restore unfinished inbound work");
                *managed.diagnostic.lock().await = Some(error.diagnostic());
            }
        }
        Ok(())
    }

    pub(crate) async fn ensure_inbound_recovery(&self) -> Result<(), FeishuError> {
        if self.runtime_released() {
            return Ok(());
        }
        let mut slot = self.inner.recovery.lock().await;
        if self.runtime_released() {
            return Ok(());
        }
        if slot.as_ref().is_some_and(|handle| !handle.is_finished()) {
            return Ok(());
        }
        if let Some(handle) = slot.as_mut() {
            let joined = std::pin::Pin::new(handle).await;
            *slot = None;
            if let Err(error) = joined
                && !error.is_cancelled()
            {
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot inbound recovery join failed",
                    true,
                    None,
                ));
            }
        }
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            return Err(FeishuError::new(
                FeishuErrorKind::Unavailable,
                "bot runtime is sealed",
                true,
                None,
            ));
        }
        let runtime = self.clone();
        let cancel = self.inner.reply_cancel.clone();
        let handle = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = cancel.cancelled() => return,
                    _ = tokio::time::sleep(std::time::Duration::from_secs(5)) => {}
                }
                if runtime.inner.sealed.load(Ordering::SeqCst) != 0 {
                    return;
                }
                let bots = runtime
                    .inner
                    .bots
                    .lock()
                    .await
                    .iter()
                    .filter_map(|(id, record)| record.published.as_ref().map(|_| id.clone()))
                    .collect::<Vec<_>>();
                for bot_id in bots {
                    if let Err(error) = runtime.restore_unfinished_inbound(&bot_id).await {
                        tracing::warn!(bot_id, %error, "inbound recovery sweep failed");
                    }
                }
            }
        });
        *slot = Some(handle);
        if self.inner.sealed.load(Ordering::SeqCst) != 0 {
            self.inner.reply_cancel.cancel();
            if let Some(handle) = slot.as_mut() {
                let joined = std::pin::Pin::new(handle).await;
                *slot = None;
                if let Err(error) = joined
                    && !error.is_cancelled()
                {
                    return Err(FeishuError::new(
                        FeishuErrorKind::Unavailable,
                        "bot inbound recovery join failed",
                        true,
                        None,
                    ));
                }
            }
        }
        Ok(())
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
struct ChatMembership {
    observed_direct: bool,
    remote_group: bool,
}

impl ChatMembership {
    fn covers(self, _chat_id: &str) -> bool {
        self.observed_direct || self.remote_group
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CursorKind {
    Groups,
    Directs,
}

struct ParsedCursor {
    kind: CursorKind,
    token: Option<String>,
}

fn decode_cursor(cursor: Option<&str>, bot_id: &str) -> Result<ParsedCursor, FeishuError> {
    let Some(cursor) = cursor.filter(|value| !value.is_empty()) else {
        return Ok(ParsedCursor {
            kind: CursorKind::Directs,
            token: None,
        });
    };
    let mut parts = cursor.splitn(3, ':');
    let cursor_bot = parts.next().unwrap_or_default();
    let kind = parts.next().unwrap_or_default();
    let token = parts
        .next()
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    if cursor_bot != bot_id {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "conversation cursor does not match bot",
            false,
            None,
        ));
    }
    Ok(ParsedCursor {
        kind: match kind {
            "directs" => CursorKind::Directs,
            _ => CursorKind::Groups,
        },
        token,
    })
}

fn encode_cursor(bot_id: &str, kind: CursorKind, token: Option<&str>) -> String {
    let label = match kind {
        CursorKind::Groups => "groups",
        CursorKind::Directs => "directs",
    };
    match token {
        Some(token) => format!("{bot_id}:{label}:{token}"),
        None => format!("{bot_id}:{label}:"),
    }
}

fn decode_history_cursor(
    cursor: Option<&str>,
    bot_id: &str,
    chat_id: &str,
    start_time: Option<i64>,
    end_time: Option<i64>,
) -> Result<Option<String>, FeishuError> {
    let Some(cursor) = cursor.filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let mut parts = cursor.splitn(6, ':');
    let cursor_bot = parts.next().unwrap_or_default();
    let kind = parts.next().unwrap_or_default();
    let cursor_chat = parts.next().unwrap_or_default();
    let cursor_start = parts.next().unwrap_or_default();
    let cursor_end = parts.next().unwrap_or_default();
    let token = parts.next().filter(|value| !value.is_empty());
    let expected_start = start_time
        .map(|value| value.to_string())
        .unwrap_or_default();
    let expected_end = end_time.map(|value| value.to_string()).unwrap_or_default();
    if cursor_bot != bot_id
        || kind != "history"
        || cursor_chat != chat_id
        || cursor_start != expected_start
        || cursor_end != expected_end
    {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "history cursor does not match bot, chat and time range",
            false,
            None,
        ));
    }
    Ok(token.map(str::to_string))
}

fn encode_history_cursor(
    bot_id: &str,
    chat_id: &str,
    start_time: Option<i64>,
    end_time: Option<i64>,
    token: &str,
) -> String {
    format!(
        "{bot_id}:history:{chat_id}:{}:{}:{token}",
        start_time
            .map(|value| value.to_string())
            .unwrap_or_default(),
        end_time.map(|value| value.to_string()).unwrap_or_default()
    )
}

/// 已持久绑定操作与本次请求的严格身份一致：同一 operationId 只能对应同一机器人、
/// 会话、冻结 revision 与内容指纹，否则是不同输入复用同一操作。
fn binding_operation_matches(
    existing: &super::storage::BindingOperation,
    operation_id: &str,
    bot_id: &str,
    chat_id: &str,
    content_hash: &str,
    expected_revision: u64,
) -> bool {
    existing.operation_id == operation_id
        && existing.bot_id == bot_id
        && existing.chat_id == chat_id
        && existing.content_hash == content_hash
        && existing.expected_revision == expected_revision
}

fn product_binding(
    bot_id: &str,
    fallback_project: &str,
    projection: super::storage::BindingProjection,
) -> BotConversationThreadBinding {
    let super::storage::BindingProjection {
        chat_id,
        workspace_id: stored_project,
        thread_id,
        revision,
        status,
        diagnostic,
        ..
    } = projection;
    let state = match status.as_str() {
        "bound" if thread_id.is_some() => BotConversationThreadState::Bound,
        "creating" => BotConversationThreadState::Creating,
        _ => BotConversationThreadState::NeedsAttention,
    };
    // 只有真正“没有持久行”的 Absent/rev0 才用当前请求项目兜底；
    // 持久 needs_attention 缺项目是既有事实，不能借当前请求补归属。
    let workspace_id = if stored_project.is_empty() && status == "absent" && revision == 0 {
        fallback_project.to_string()
    } else {
        stored_project
    };
    BotConversationThreadBinding {
        bot_id: bot_id.to_string(),
        chat_id,
        workspace_id,
        thread_id,
        revision,
        state,
        diagnostic: diagnostic.map(|message| BotDiagnostic {
            code: "binding".to_string(),
            message,
            retryable: false,
            platform_code: None,
            guidance: Some("recreateLocalConversation".to_string()),
        }),
    }
}

fn binding_reply(
    operation_id: String,
    owner_epoch: &str,
    binding: BotConversationThreadBinding,
    disposition: CommandDisposition,
) -> BotConversationThreadReply {
    BotConversationThreadReply {
        receipt: StudioCommandReceipt {
            operation_id,
            disposition,
            targets: vec![ResourceStamp {
                resource_key: format!("bot:{}:chat:{}", binding.bot_id, binding.chat_id),
                owner_epoch: owner_epoch.to_string(),
                revision: binding.revision,
            }],
            effect: CommandEffectPoint::Immediate,
            effective: true,
            durable: true,
            requires_identity_observation: false,
        },
        binding,
    }
}

#[cfg(test)]
pub(super) mod archive_tests {
    //! Real inbound registration and reply consumers, on isolated Studio/bot stores.
    use super::*;
    use crate::bots::InboundWorkOutcome;
    use crate::bots::storage::{MarkOutcome, WorkFinish};
    use crate::studio::bot_archive_test_host::BotArchiveTestHost;
    use crate::studio::paths::{SqliteFileMode, sqlite_file_options};
    use anyhow::Result;
    use sea_orm::{
        ConnectionTrait, Database, DatabaseBackend, DatabaseConnection, Statement, TransactionTrait,
    };
    use std::time::Duration;

    pub(in crate::bots) struct Fixture {
        pub(in crate::bots) host: BotArchiveTestHost,
        pub(in crate::bots) bots: BotRuntime,
        managed: Arc<ManagedBot>,
        workspace_id: String,
        _temp: tempfile::TempDir,
    }

    #[derive(Debug, thiserror::Error)]
    #[error("{0}")]
    struct PrivateBotBackendCause(&'static str);

    #[tokio::test]
    async fn studio_bot_tools_keep_backend_causes_private() -> Result<()> {
        use pl_agent_tool::Tool;
        use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
        use pl_tool::bots::{BotToolKind, ThreadBotTool};
        use std::error::Error;
        const PRIVATE_MARKER: &str = "PRIVATE_BACKEND_SENTINEL";
        let fixture = Fixture::new().await?;
        let host = Arc::new(crate::bots::StudioBotSessionHost {
            runtime: fixture.bots.clone(),
        });
        let result = async {
            let config = fixture.managed.config.lock().await.clone();
            fixture
                .host
                .runtime
                .save_bot(SaveBotRequest {
                    operation_id: "allow-private-cause-test".into(),
                    bot_id: Some(config.id.clone()),
                    expected_config_revision: config.config_revision,
                    name: config.name,
                    workspace_id: config.workspace_id,
                    app_id: "cli_archive_fixture".into(),
                    secret: BotSecretUpdate::Preserve,
                    enabled: false,
                    tools_enabled: true,
                    model_route: None,
                })
                .await?;
            let injected = FeishuError::new(
                FeishuErrorKind::Transport,
                "safe outer bot failure",
                true,
                None,
            )
            .with_source(PrivateBotBackendCause(PRIVATE_MARKER));
            let public_diagnostic = injected.to_string();
            for (kind, arguments) in [
                (
                    BotToolKind::ListConversations,
                    serde_json::json!({"botId": config.id}),
                ),
                (
                    BotToolKind::ReadMessages,
                    serde_json::json!({"botId": config.id, "chatId":"chat"}),
                ),
                (
                    BotToolKind::SendMessage,
                    serde_json::json!({"botId": config.id, "chatId":"chat", "text":"do not send"}),
                ),
            ] {
                let tool = ThreadBotTool::new(
                    host.clone(),
                    kind,
                    fixture.workspace_id.clone(),
                    kind.declaration(),
                );
                let context = CallContext {
                    thread_id: "private-bot-error".into(),
                    turn_id: "turn".into(),
                    call_id: "frozen-send-operation".into(),
                    cancellation: Default::default(),
                    extensions: Default::default(),
                    catalog: Arc::from([]),
                    extension_sequence: 0,
                    grant: Default::default(),
                    context: Default::default(),
                    history_fence: 0,
                    model_projection: None,
                    tasks: None,
                };
                let error = crate::bots::host::with_service_failure(
                    injected.clone(),
                    tool.execute(
                        OpaquePayload::new("application/json", 1, arguments.to_string())?,
                        context,
                    ),
                )
                .await
                .unwrap_err();
                let serialized = serde_json::to_string(&error)?;
                anyhow::ensure!(
                    !serialized.contains(PRIVATE_MARKER),
                    "public tool error serialization leaked the private backend cause",
                );
                anyhow::ensure!(serialized.contains(&public_diagnostic));
                anyhow::ensure!(!format!("{error:?}").contains(PRIVATE_MARKER));
                let mut source: Option<&(dyn Error + 'static)> = Some(&error);
                let mut frames = 0;
                while let Some(frame) = source {
                    anyhow::ensure!(!frame.to_string().contains(PRIVATE_MARKER));
                    anyhow::ensure!(!format!("{frame:?}").contains(PRIVATE_MARKER));
                    frames += 1;
                    anyhow::ensure!(
                        frames <= 2,
                        "the public chain crossed the host error boundary"
                    );
                    source = frame.source();
                }
                let adapter = error
                    .source
                    .downcast_ref::<crate::bots::host::BotToolError>()
                    .expect("the Studio host must provide its safe error boundary");
                anyhow::ensure!(adapter.to_string() == public_diagnostic);
                anyhow::ensure!(adapter.source().is_none());
                anyhow::ensure!(adapter.original().kind() == FeishuErrorKind::Transport);
                let original_cause = adapter.original().source().expect("trusted backend cause");
                let private = original_cause
                    .downcast_ref::<PrivateBotBackendCause>()
                    .expect("the original typed backend cause must not be flattened");
                anyhow::ensure!(private.0 == PRIVATE_MARKER);
            }
            Ok::<(), anyhow::Error>(())
        }
        .await;
        let shutdown = fixture.host.runtime.shutdown_runtime().await;
        result?;
        shutdown?;
        Ok(())
    }

    #[tokio::test]
    async fn independent_bot_tools_use_studio_authorization_and_reject_cross_project_access()
    -> Result<()> {
        use pl_agent_tool::Tool;
        use pl_core::{context::OpaquePayload, tool::opaque::CallContext};
        use pl_tool::bots::{BotToolKind, ThreadBotTool};
        let fixture = Fixture::new().await?;
        let host = Arc::new(crate::bots::StudioBotSessionHost {
            runtime: fixture.bots.clone(),
        });
        let context = || CallContext {
            thread_id: "bot-tools".into(),
            turn_id: "turn".into(),
            call_id: "call".into(),
            cancellation: Default::default(),
            extensions: Default::default(),
            catalog: Arc::from([]),
            extension_sequence: 0,
            grant: Default::default(),
            context: Default::default(),
            history_fence: 0,
            model_projection: None,
            tasks: None,
        };
        let result = async {
            let kind = BotToolKind::ListBots;
            let list = ThreadBotTool::new(
                host.clone(),
                kind,
                fixture.workspace_id.clone(),
                kind.declaration(),
            );
            let output = list
                .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
                .await?;
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(output.payload().content())?,
                serde_json::json!([])
            );
            let config = fixture.managed.config.lock().await.clone();
            fixture
                .host
                .runtime
                .save_bot(SaveBotRequest {
                    operation_id: "allow-domain-tools".into(),
                    bot_id: Some(config.id.clone()),
                    expected_config_revision: config.config_revision,
                    name: config.name,
                    workspace_id: config.workspace_id,
                    app_id: "cli_archive_fixture".into(),
                    secret: BotSecretUpdate::Preserve,
                    enabled: false,
                    tools_enabled: true,
                    model_route: None,
                })
                .await?;
            let output = list
                .execute(OpaquePayload::new("application/json", 1, "{}")?, context())
                .await?;
            let bots: serde_json::Value = serde_json::from_str(output.payload().content())?;
            assert_eq!(bots[0]["id"], config.id);
            assert_eq!(bots[0]["toolsEnabled"], true);
            assert!(bots[0].get("appId").is_none());
            for (kind, arguments) in [
                (
                    BotToolKind::ListConversations,
                    serde_json::json!({"botId":config.id}),
                ),
                (
                    BotToolKind::ReadMessages,
                    serde_json::json!({"botId":config.id,"chatId":"chat"}),
                ),
                (
                    BotToolKind::SendMessage,
                    serde_json::json!({"botId":config.id,"chatId":"chat","text":"do not send"}),
                ),
            ] {
                let tool = ThreadBotTool::new(
                    host.clone(),
                    kind,
                    "other-project".into(),
                    kind.declaration(),
                );
                let error = tool
                    .execute(
                        OpaquePayload::new("application/json", 1, arguments.to_string())?,
                        context(),
                    )
                    .await
                    .unwrap_err();
                assert_eq!(
                    error
                        .source
                        .downcast_ref::<crate::bots::host::BotToolError>()
                        .expect("safe Studio authorization error")
                        .original()
                        .kind(),
                    FeishuErrorKind::Permission
                );
            }
            Ok::<(), anyhow::Error>(())
        }
        .await;
        let shutdown = fixture.host.runtime.shutdown_runtime().await;
        result?;
        shutdown?;
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_bot_ledger_removes_only_the_bound_tree_and_retains_neighbor()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let deleted = fixture.inbound("deleted", true).await?;
        let neighbor = fixture.inbound("neighbor", true).await?;
        fixture
            .host
            .runtime
            .delete_thread("delete-bot-tree".into(), deleted.creation_id.clone())
            .await?
            .expect("root deletion");
        assert!(
            fixture
                .bots
                .config_for_thread(&deleted.creation_id)
                .await?
                .is_none()
        );
        assert!(
            fixture
                .bots
                .config_for_thread(&neighbor.creation_id)
                .await?
                .is_some()
        );
        let due = fixture
            .managed
            .store
            .list_due_inbound(&deleted.bot_id)
            .await?;
        assert_eq!(due.len(), 1);
        assert_eq!(due[0], neighbor);
        let db = fixture.ledger_probe().await?;
        assert!(
            db.query_one_raw(Statement::from_sql_and_values(
                DatabaseBackend::Sqlite,
                "SELECT 1 FROM inbound_identities WHERE bot_id=? AND chat_id=? AND message_id=?",
                [
                    deleted.bot_id.into(),
                    deleted.chat_id.into(),
                    deleted.message_id.into()
                ]
            ))
            .await?
            .is_none()
        );
        assert!(!fixture.bots.runtime_released());
        db.close().await?;
        fixture.shutdown().await?;
        Ok(())
    }

    #[tokio::test]
    async fn permanent_delete_waits_for_frozen_bot_admission_and_rejects_late_body_before_write()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let deleted = fixture.inbound("frozen-deleted", true).await?;
        let neighbor = fixture.inbound("frozen-neighbor", true).await?;
        let (inbound_entered, inbound_ready) = tokio::sync::oneshot::channel();
        let (release_inbound, inbound_release) = tokio::sync::oneshot::channel();
        *fixture.bots.inner.deletion_tests.inbound.lock().unwrap() =
            Some((deleted.chat_id.clone(), inbound_entered, inbound_release));
        let (delete_attempt, delete_waiting) = tokio::sync::oneshot::channel();
        *fixture
            .bots
            .inner
            .deletion_tests
            .admission_attempt
            .lock()
            .unwrap() = Some(delete_attempt);
        let (clear_entered, mut clear_ready) = tokio::sync::oneshot::channel();
        let (release_clear, clear_release) = tokio::sync::oneshot::channel();
        *fixture
            .bots
            .inner
            .deletion_tests
            .ledger_clear
            .lock()
            .unwrap() = Some((clear_entered, clear_release));
        let generation = fixture.managed.generation.load(Ordering::Acquire);
        let inbound = tokio::spawn({
            let bots = fixture.bots.clone();
            let bot_id = deleted.bot_id.clone();
            let chat_id = deleted.chat_id.clone();
            async move {
                bots.admit_decision(
                    &bot_id,
                    generation,
                    InboundDecision::Execute {
                        message_id: "late-frozen-message".into(),
                        chat_id,
                        open_id: "fixture-user".into(),
                        text: "late text must never be reinserted".into(),
                        attachments: vec![crate::bots::inbound::InboundAttachment::File {
                            key: "late-private-file".into(),
                            filename: "private.txt".into(),
                        }],
                        content_hash: "late-frozen-hash".into(),
                        chat_kind: ChatKind::Direct,
                    },
                )
                .await
            }
        });
        tokio::time::timeout(Duration::from_secs(10), inbound_ready).await??;
        let deletion = tokio::spawn({
            let runtime = fixture.host.runtime.clone();
            let target = deleted.creation_id.clone();
            async move {
                runtime
                    .delete_thread("delete-frozen-inbound".into(), target)
                    .await
            }
        });
        tokio::time::timeout(Duration::from_secs(20), delete_waiting).await??;
        // On this current-thread runtime, the delete worker polls from its synchronous attempt
        // notification until the admission wait. Crossing that wait would reach clear_ready in the
        // same poll; no wall-clock delay or scheduler race is used to establish the interleaving.
        let crossed_admission = clear_ready.try_recv().is_ok();
        assert!(!deletion.is_finished());
        release_inbound.send(()).unwrap();
        let inbound_result = tokio::time::timeout(Duration::from_secs(10), inbound).await??;
        if !crossed_admission {
            tokio::time::timeout(Duration::from_secs(10), &mut clear_ready).await??;
        }
        let db = fixture.ledger_probe().await?;
        let late = db
        .query_one_raw(Statement::from_sql_and_values(
            DatabaseBackend::Sqlite,
            "SELECT 1 FROM inbound_identities WHERE bot_id=? AND message_id='late-frozen-message'",
            [deleted.bot_id.clone().into()],
        ))
        .await?;
        let rejected_before_write = late.is_none();
        release_clear.send(()).unwrap();
        tokio::time::timeout(Duration::from_secs(20), deletion)
            .await???
            .expect("delete reply");
        assert!(
            !crossed_admission,
            "ledger deletion crossed an original frozen inbound admission"
        );
        assert!(
            inbound_result.is_err(),
            "the frozen target must be revalidated before persistence"
        );
        assert!(
            rejected_before_write,
            "late inbound body/identity was inserted before enqueue rejected it"
        );
        assert_eq!(
            fixture
                .managed
                .store
                .list_due_inbound(&deleted.bot_id)
                .await?,
            vec![neighbor.clone()]
        );
        db.close().await?;
        fixture.shutdown().await?;
        let restarted = fixture.host.restart().await?;
        let bots = restarted.bots();
        let managed = bots.managed(&deleted.bot_id).await?;
        assert_eq!(
            managed.store.list_due_inbound(&deleted.bot_id).await?,
            vec![neighbor.clone()]
        );
        assert!(
            bots.config_for_thread(&deleted.creation_id)
                .await?
                .is_none()
        );
        assert!(
            bots.config_for_thread(&neighbor.creation_id)
                .await?
                .is_some()
        );
        let probe = fixture.ledger_probe().await?;
        assert!(
            probe
                .query_one_raw(Statement::from_sql_and_values(
                    DatabaseBackend::Sqlite,
                    "SELECT 1 FROM inbound_identities WHERE bot_id=? AND chat_id=?",
                    [deleted.bot_id.into(), deleted.chat_id.into()]
                ))
                .await?
                .is_none()
        );
        probe.close().await?;
        restarted.runtime.shutdown_runtime().await?;
        Ok(())
    }

    impl Fixture {
        pub(in crate::bots) async fn new() -> Result<Self> {
            Self::new_with_optional_file_input(false).await
        }

        pub(in crate::bots) async fn new_with_file_input() -> Result<Self> {
            Self::new_with_optional_file_input(true).await
        }

        async fn new_with_optional_file_input(file_input: bool) -> Result<Self> {
            let temp = tempfile::tempdir()?;
            let home = temp.path().join("home");
            let host = if file_input {
                BotArchiveTestHost::new_with_file_input(&home).await?
            } else {
                BotArchiveTestHost::new(&home).await?
            };
            let workspace = temp.path().join("workspace");
            tokio::fs::create_dir_all(&workspace).await?;
            let project = host.runtime.open_project(&workspace).await?;
            let bots = host.bots();
            // Keep the periodic recovery worker out of controlled interleavings.
            // All tested recovery calls below use the real enqueue implementation.
            if let Some(recovery) = bots.inner.recovery.lock().await.take() {
                recovery.abort();
                assert!(recovery.await.unwrap_err().is_cancelled());
            }
            host.runtime
                .save_bot(SaveBotRequest {
                    operation_id: "archive-fixture-save".into(),
                    bot_id: Some("archive-fixture".into()),
                    expected_config_revision: 0,
                    name: "Archive fixture".into(),
                    workspace_id: project.id.clone(),
                    app_id: "cli_archive_fixture".into(),
                    secret: BotSecretUpdate::Clear,
                    enabled: false,
                    tools_enabled: false,
                    model_route: None,
                })
                .await?;
            let managed = bots.managed("archive-fixture").await?;
            Ok(Self {
                host,
                bots,
                managed,
                workspace_id: project.id,
                _temp: temp,
            })
        }

        pub(in crate::bots) async fn inbound(
            &self,
            chat_id: &str,
            bound: bool,
        ) -> Result<FrozenInbound> {
            self.inbound_with_attachments(chat_id, bound, Vec::new())
                .await
        }

        pub(in crate::bots) async fn inbound_with_attachments(
            &self,
            chat_id: &str,
            bound: bool,
            attachments: Vec<crate::bots::inbound::InboundAttachment>,
        ) -> Result<FrozenInbound> {
            let creation_id = format!("archive-thread-{chat_id}");
            self.managed
                .store
                .claim_thread_binding(chat_id, &creation_id, &self.workspace_id)
                .await?;
            if bound {
                let thread = self
                    .host
                    .runtime
                    .create_thread_with_id(creation_id.clone(), &self.workspace_id, "Archive")
                    .await?;
                self.managed
                    .store
                    .bind_thread(chat_id, &thread.id, &creation_id, &self.workspace_id)
                    .await?;
            }
            let projection = self
                .managed
                .store
                .binding_for_chat(chat_id, "archive-fixture", &self.workspace_id)
                .await?;
            let inbound = FrozenInbound {
                bot_id: "archive-fixture".into(),
                message_id: format!("message-{chat_id}"),
                chat_id: chat_id.into(),
                content_hash: format!("hash-{chat_id}"),
                text: format!("original frozen text for {chat_id}"),
                attachments,
                open_id: "fixture-user".into(),
                chat_kind: "direct".into(),
                app_id: "cli_archive_fixture".into(),
                workspace_id: self.workspace_id.clone(),
                creation_id,
                binding_revision: projection.revision,
                watch_input: String::new(),
            };
            assert!(matches!(
                self.managed.store.admit_inbound(inbound.clone()).await?,
                InboundAdmit::Fresh(_)
            ));
            Ok(inbound)
        }

        pub(in crate::bots) async fn ledger_probe(&self) -> Result<DatabaseConnection> {
            let path = self
                .bots
                .inner
                .paths
                .bot_dir("archive-fixture")
                .join("state.sqlite");
            Ok(Database::connect(
                sqlite_file_options(&path, SqliteFileMode::ReadWrite, |options| options).await?,
            )
            .await?)
        }

        pub(in crate::bots) async fn shutdown(&self) -> Result<()> {
            self.host.runtime.shutdown_runtime().await?;
            Ok(())
        }

        pub(in crate::bots) async fn enqueue(&self, inbound: FrozenInbound) -> Result<()> {
            Ok(self.bots.enqueue_inbound(inbound).await?)
        }
    }

    #[tokio::test]
    async fn idle_bound_bot_quiesces_without_releasing_runtime_and_keeps_frozen_inbound()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let inbound = fixture.inbound("idle", true).await?;
        assert!(
            fixture
                .bots
                .config_for_thread(&inbound.creation_id)
                .await?
                .is_some()
        );
        assert!(!fixture.bots.runtime_released());
        let guard = fixture
            .bots
            .quiesce_archive_threads(std::slice::from_ref(&inbound.creation_id))
            .await?;
        assert!(!fixture.bots.runtime_released());
        assert!(fixture.bots.enqueue_inbound(inbound.clone()).await.is_err());
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
        assert_eq!(
            fixture
                .managed
                .store
                .list_due_inbound(&inbound.bot_id)
                .await?,
            vec![inbound]
        );
        drop(guard);
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn enqueue_reaps_finished_replies_before_trying_the_bounded_budget() -> Result<()> {
        let fixture = Fixture::new().await?;
        let mut inbound = fixture.inbound("budget", true).await?;
        // A changed app is a real dispatch terminal path before any network work.
        // Hold its config read so all 32 owners are registered before any finish.
        inbound.app_id = "cli_old_frozen_app".into();
        let config = fixture.managed.config.lock().await;
        for index in 0..32 {
            inbound.message_id = format!("budget-{index}");
            inbound.content_hash = format!("budget-hash-{index}");
            fixture.managed.store.admit_inbound(inbound.clone()).await?;
            fixture.bots.enqueue_inbound(inbound.clone()).await?;
        }
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 0);
        drop(config);
        let probe = fixture.ledger_probe().await?;
        tokio::time::timeout(Duration::from_secs(5), async {
            loop {
                let finished: i64 = probe
                    .query_one_raw(Statement::from_string(
                        DatabaseBackend::Sqlite,
                        "SELECT COUNT(*) AS n FROM inbound_work WHERE status='needs_attention'",
                    ))
                    .await?
                    .expect("count row")
                    .try_get("", "n")?;
                if finished == 32 {
                    break;
                }
                tokio::task::yield_now().await;
            }
            anyhow::Ok(())
        })
        .await??;
        // Ledger ACK precedes task return. Give the same owned tasks their final
        // poll; permits intentionally remain held until enqueue observes joins.
        tokio::task::yield_now().await;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 0);
        inbound.message_id = "budget-next".into();
        inbound.content_hash = "budget-hash-next".into();
        fixture.managed.store.admit_inbound(inbound.clone()).await?;
        fixture.bots.enqueue_inbound(inbound.clone()).await?;
        let guard = fixture
            .bots
            .quiesce_archive_threads(&[inbound.creation_id])
            .await?;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
        drop(guard);
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn cancelled_unstarted_finisher_retains_original_budget_and_ledger_retry() -> Result<()> {
        let fixture = Fixture::new().await?;
        let inbound = fixture.inbound("unstarted", true).await?;
        let worker = "unstarted-worker";
        assert_eq!(
            fixture
                .managed
                .store
                .claim_inbound_work(
                    &inbound.bot_id,
                    &inbound.chat_id,
                    &inbound.message_id,
                    worker,
                )
                .await?,
            InboundClaim::Claimed,
        );
        let probe = fixture.ledger_probe().await?;
        let writer = probe.begin().await?;
        writer
            .execute_unprepared("UPDATE inbound_work SET updated_at=updated_at")
            .await?;
        let mut replies = fixture.bots.inner.replies.lock().await;
        let permit = fixture
            .bots
            .inner
            .reply_slots
            .clone()
            .acquire_owned()
            .await?;
        assert!(
            tokio::time::timeout(
                Duration::from_millis(50),
                replies.finish_unstarted(
                    &fixture.bots,
                    inbound.creation_id.clone(),
                    ReplyIdentity::new(&inbound, worker),
                    fixture.bots.inner.reply_cancel.child_token(),
                    permit,
                ),
            )
            .await
            .is_err()
        );
        assert_eq!(
            fixture.bots.inner.reply_slots.available_permits(),
            31,
            "canceling a ledger wait must leave its owner and permit registered",
        );
        writer.rollback().await?;
        replies.retry_finishes(&fixture.bots, None).await?;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
        assert_eq!(
            fixture
                .managed
                .store
                .list_due_inbound(&inbound.bot_id)
                .await?,
            vec![inbound],
        );
        drop(replies);
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn quiesce_waits_for_real_finisher_and_retry_joins_original_without_canceling_neighbor()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let target = fixture.inbound("target", false).await?;
        let neighbor = fixture.inbound("neighbor", false).await?;
        let lifecycle = fixture.host.lifecycle_lock().lock().await;
        fixture.bots.enqueue_inbound(target.clone()).await?;
        fixture.bots.enqueue_inbound(neighbor.clone()).await?;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 30);

        // Real ledger writes cannot ACK while this independent SQLite writer holds
        // the lock. Canceling the archive waiter must not detach its reply owner.
        let probe = fixture.ledger_probe().await?;
        let writer = probe.begin().await?;
        writer
            .execute_unprepared("UPDATE inbound_work SET updated_at=updated_at")
            .await?;
        assert!(
            tokio::time::timeout(
                Duration::from_millis(50),
                fixture
                    .bots
                    .quiesce_archive_threads(std::slice::from_ref(&target.creation_id))
            )
            .await
            .is_err()
        );
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 30);
        assert!(!fixture.bots.inner.reply_cancel.is_cancelled());
        writer.rollback().await?;
        let guard = tokio::time::timeout(
            Duration::from_secs(5),
            fixture
                .bots
                .quiesce_archive_threads(std::slice::from_ref(&target.creation_id)),
        )
        .await??;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 31);
        assert_eq!(
            fixture
                .managed
                .store
                .list_due_inbound(&target.bot_id)
                .await?,
            vec![target.clone()],
            "the neighbor still owns its claim and producer"
        );
        drop(guard);
        let neighbor_guard = tokio::time::timeout(
            Duration::from_secs(5),
            fixture
                .bots
                .quiesce_archive_threads(std::slice::from_ref(&neighbor.creation_id)),
        )
        .await??;
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
        assert!(!fixture.bots.inner.reply_cancel.is_cancelled());
        drop(neighbor_guard);
        drop(lifecycle);
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn durable_seal_and_archived_catalog_reject_actual_enqueue_without_changing_identity()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let sealed = fixture.inbound("sealed", true).await?;
        let archived = fixture.inbound("archived", true).await?;
        fixture.host.seal_thread(&sealed.creation_id).await?;
        assert!(fixture.bots.enqueue_inbound(sealed.clone()).await.is_err());
        fixture
            .host
            .runtime
            .archive_thread("archive-bound-fixture".into(), archived.creation_id.clone())
            .await?
            .expect("bound bot Thread is archived");
        assert!(
            fixture
                .bots
                .enqueue_inbound(archived.clone())
                .await
                .is_err()
        );
        assert_eq!(fixture.bots.inner.reply_slots.available_permits(), 32);
        let due = fixture
            .managed
            .store
            .list_due_inbound(&sealed.bot_id)
            .await?;
        assert_eq!(due.len(), 2);
        assert!(due.contains(&sealed));
        assert!(due.contains(&archived));
        fixture.shutdown().await
    }

    #[tokio::test]
    async fn reply_resolution_wait_is_cancellable_and_mismatched_registration_never_dispatches()
    -> Result<()> {
        let fixture = Fixture::new().await?;
        let creating = fixture.inbound("creating", false).await?;
        assert_eq!(
            fixture
                .managed
                .store
                .claim_inbound_work(
                    &creating.bot_id,
                    &creating.chat_id,
                    &creating.message_id,
                    "fixture-worker"
                )
                .await?,
            InboundClaim::Claimed
        );
        let lifecycle = fixture.host.lifecycle_lock().lock().await;
        let cancellation = fixture.bots.inner.reply_cancel.child_token();
        let reply = fixture.bots.dispatch_prompt(
            creating.clone(),
            "fixture-worker",
            &creating.creation_id,
            cancellation.clone(),
        );
        tokio::pin!(reply);
        assert!(futures::poll!(&mut reply).is_pending());
        cancellation.cancel();
        assert_eq!(
            tokio::time::timeout(Duration::from_secs(5), reply).await?,
            InboundWorkOutcome::Interrupted
        );
        drop(lifecycle);
        assert_eq!(
            fixture
                .managed
                .store
                .finish_inbound_work(
                    &creating.bot_id,
                    &creating.chat_id,
                    &creating.message_id,
                    "fixture-worker",
                    WorkFinish::Interrupted
                )
                .await?,
            MarkOutcome::Applied
        );

        let bound = fixture.inbound("mismatch", true).await?;
        assert_eq!(
            fixture
                .managed
                .store
                .claim_inbound_work(
                    &bound.bot_id,
                    &bound.chat_id,
                    &bound.message_id,
                    "fixture-worker"
                )
                .await?,
            InboundClaim::Claimed
        );
        let outcome = fixture
            .bots
            .dispatch_prompt(
                bound.clone(),
                "fixture-worker",
                "different-thread",
                fixture.bots.inner.reply_cancel.child_token(),
            )
            .await;
        assert!(
            matches!(outcome, InboundWorkOutcome::NeedsAttention { diagnostic }
        if diagnostic.contains("registered reply owner"))
        );
        assert!(
            fixture
                .host
                .runtime
                .bot_input_fact(
                    &bound.creation_id,
                    &format!(
                        "bot:{}:{}:{}",
                        bound.bot_id, bound.chat_id, bound.message_id
                    ),
                )
                .await?
                .eq(&crate::bots::BotInputRead::Absent)
        );
        fixture
            .managed
            .store
            .finish_inbound_work(
                &bound.bot_id,
                &bound.chat_id,
                &bound.message_id,
                "fixture-worker",
                WorkFinish::Interrupted,
            )
            .await?;
        fixture.shutdown().await
    }
}
