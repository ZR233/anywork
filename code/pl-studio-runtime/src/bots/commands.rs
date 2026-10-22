//! 会话查询、发送与入站执行。扫码注册由 `registration` owner 持有。
use super::SendAuthority;
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
    project_id: String,
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
            (self.project_id.as_str(), 5),
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
    project_id: String,
    /// 调用方观测到的配置 revision：仅供首次认领复核，不参与回执填充。
    expected_config_revision: u64,
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
        (projection.project_id.as_str(), 1),
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
        (payload.project_id.as_str(), 2),
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
    project_id: &str,
    facts_bytes: usize,
    body_bytes: usize,
) -> Result<usize, FeishuError> {
    let mut fields = vec![
        (record.operation_id.as_str(), 3),
        (record.bot_id.as_str(), 3),
        (record.chat_id.as_str(), 3),
        (record.content_hash.as_str(), 3),
        (app_id, 1),
        (project_id, 1),
    ];
    // 工具授权携带的项目 id 也跨 await 保留，必须单独计权。
    if let SendAuthority::Tool { project_id } = authority {
        fields.push((project_id.as_str(), 1));
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
                    &config.project_id,
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
        let project_id = config.project_id;
        let expected_config_revision = config.config_revision;
        // 首次认领会把分段事实编码成 SQL 参数：按与持久化同一实现的真实长度计权。
        let facts_bytes = super::storage::segment_facts_bytes(&initial.segments)?;
        // plan 分段会跨占用等待并交给统一发送 owner：按实际 UTF-8 段总长计入首次预算。
        let body_bytes = plan.segments.iter().map(String::len).sum::<usize>();
        let text_bytes = send_claim_freeze_bytes(
            &initial,
            &authority,
            &app_id,
            &project_id,
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
            project_id,
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
            project_id,
            expected_config_revision,
        } = frozen;
        let _admission = managed.admission.lock().await;
        self.reject_closed_admission(&managed)?;
        // 短锁内核对身份与授权后立即释放，不克隆整份配置、不跨 DB await 持有 guard。
        let config_revision = {
            let current = managed.config.lock().await;
            if current.feishu().app_id != app_id || current.project_id != project_id {
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

    pub async fn authorized_bots(&self, project_id: &str) -> Vec<BotSnapshot> {
        let previous = self.snapshot().await;
        self.list_snapshots(&previous)
            .await
            .into_iter()
            .filter(|bot| bot.project_id == project_id && bot.tools_enabled)
            .collect()
    }

    async fn conversation_binding(
        &self,
        managed: &ManagedBot,
        bot_id: &str,
        project_id: &str,
        chat_id: &str,
    ) -> Result<BotConversationThreadBinding, FeishuError> {
        let projection = managed
            .store
            .binding_for_chat(chat_id, bot_id, project_id)
            .await?;
        Ok(product_binding(bot_id, project_id, projection))
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
        let (name, app_id, project_id) = if accepted {
            let current = managed.config.lock().await;
            (
                current.name.clone(),
                current.feishu().app_id.clone(),
                current.project_id.clone(),
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
                config.project_id.clone(),
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
            project_id,
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
            project_id,
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
                    current.feishu().app_id == app_id && current.project_id == project_id,
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
                        .binding_for_chat(&chat_id, &bot_id, &project_id)
                        .await?;
                    if projection.status == "bound"
                        && projection.creation_id == existing_creation
                        && projection.thread_id.as_deref() == Some(existing_thread.as_str())
                    {
                        let binding = product_binding(&bot_id, &project_id, projection);
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
                    .binding_for_chat(&chat_id, &bot_id, &project_id)
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
                    .binding_for_chat(&chat_id, &bot_id, &project_id)
                    .await?;
                let provable_partial = projection.status == "creating"
                    && !projection
                        .thread_id
                        .as_ref()
                        .is_some_and(|id| !id.is_empty())
                    && projection.creation_id == creation_id
                    && projection.project_id == project_id
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
                            &project_id,
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
                            &project_id,
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
            .create_thread_with_id(frozen_creation.clone(), &project_id, &title)
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
                current.feishu().app_id == app_id && current.project_id == project_id
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
                .bind_thread(&chat_id, &created.id, &frozen_creation, &project_id)
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
            .conversation_binding(&managed, &bot_id, &project_id, &chat_id)
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
        {
            let mut replies = self.inner.replies.lock().await;
            while let Some(joined) = replies.join_next().await {
                if joined.is_err() {
                    // 取出当刻写入 owner 事实：之后等待其他句柄或关闭被取消都不会丢。
                    self.inner.reply_fault.store(true, Ordering::SeqCst);
                }
            }
            drop(replies);
            // 排空完成后无额外 await 地消费一次；已直接返回 Err 视为上报一次。
            if self.inner.reply_fault.swap(false, Ordering::SeqCst) {
                return Err(FeishuError::new(
                    FeishuErrorKind::Unavailable,
                    "bot reply join failed: task(s) terminated abnormally",
                    true,
                    None,
                ));
            }
        }
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
                || current.project_id != config.project_id
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
        if let SendAuthority::Tool { project_id } = &authority
            && config.project_id != *project_id
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
        let SendAuthority::Tool { project_id } = authority else {
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
        if current.project_id != *project_id {
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
                    let (app_id, project_id) = {
                        let current = managed.config.lock().await;
                        (current.feishu().app_id.clone(), current.project_id.clone())
                    };
                    // app/project 会与工作行 INSERT 的 SQL 参数同时存活：按 2 份计。
                    budget.reserve_more(super::occupancy::counted_text_bytes([
                        (app_id.as_str(), 2),
                        (project_id.as_str(), 2),
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
                        (project_id.as_str(), 1),
                        (creation_id.as_str(), 2),
                        ("creating", 1),
                    ])?)?;
                    let claim = managed
                        .store
                        .claim_thread_binding(&chat_id, &creation_id, &project_id)
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
                        .binding_for_chat(&chat_id, bot_id, &project_id)
                        .await?;
                    if projection.creation_id.is_empty() {
                        return Err(super::storage::binding_needs_recovery());
                    }
                    if projection.project_id != project_id {
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
                        && projection.project_id == project_id
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
                        project_id,
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
        let cancel = self.inner.reply_cancel.clone();
        // 交接给回复 owner 的两份材料：派发按值移动、收束用 finisher。不再克隆第三份，
        // 使峰值与冻结预算表一致。
        let finisher = inbound.clone();
        self.inner.replies.lock().await.spawn(async move {
            let outcome = runtime.dispatch_prompt(inbound, &worker_id, cancel).await;
            if let Ok(managed) = runtime.managed(&finisher.bot_id).await {
                let finish = match &outcome {
                    super::InboundWorkOutcome::Completed => {
                        Some(super::storage::WorkFinish::Completed)
                    }
                    super::InboundWorkOutcome::Interrupted => {
                        Some(super::storage::WorkFinish::Interrupted)
                    }
                    super::InboundWorkOutcome::Recoverable { diagnostic } => {
                        Some(super::storage::WorkFinish::Retryable(diagnostic.as_str()))
                    }
                    super::InboundWorkOutcome::NeedsAttention { diagnostic } => Some(
                        super::storage::WorkFinish::NeedsAttention(diagnostic.as_str()),
                    ),
                    // 失租：后继持有者已接管，本持有者的收束被账本拒绝，不能假 Completed。
                    super::InboundWorkOutcome::LostClaim => None,
                };
                if let Some(finish) = finish
                    && !matches!(
                        managed
                            .store
                            .finish_inbound_work(
                                &finisher.bot_id,
                                &finisher.chat_id,
                                &finisher.message_id,
                                &worker_id,
                                finish,
                            )
                            .await,
                        Ok(super::storage::MarkOutcome::Applied)
                    )
                {
                    tracing::warn!(
                        bot_id = %finisher.bot_id,
                        message_id = %finisher.message_id,
                        "inbound work finish lost its claim fence"
                    );
                }
            }
            drop(permit);
            outcome
        });
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
        project_id: stored_project,
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
    let project_id = if stored_project.is_empty() && status == "absent" && revision == 0 {
        fallback_project.to_string()
    } else {
        stored_project
    };
    BotConversationThreadBinding {
        bot_id: bot_id.to_string(),
        chat_id,
        project_id,
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
