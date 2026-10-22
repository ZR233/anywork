//! 机器人自动回复的持久 canonical 只读恢复边界。
//!
//! 状态流只负责唤醒观察；本模块把机器人恢复所需的 durable 事实——原始输入路由、
//! 目标 Turn 状态、交互终局——从 HistoryStore 的窄接口投影成 [`crate::bots`] 声明
//! 的 typed 契约。读取显式区分 Ready/Absent/NotReady：读、IO 与 decode 失败保持
//! `Result` 错误，不折叠成 None，也不激活执行 owner 或创建第二份历史事实源。

use anyhow::{Result, bail};
use pl_core::thread::interactions::{InteractionRecord, InteractionState};
use pl_core::thread::permissions::{PermissionRecord, PermissionState};
use pl_protocol::{InteractionRequest, InteractionStatus, ThreadItemState};

use super::StudioRuntime;
use crate::bots::{
    BotInputRead, BotInteractionFact, BotInteractionKind, BotInteractionRead, BotTurnRead,
};

impl StudioRuntime {
    /// 读取一条输入的持久路由与消费身份；不重新受理、不回放历史。
    pub(crate) async fn bot_input_fact(
        &self,
        thread_id: &str,
        input_id: &str,
    ) -> Result<BotInputRead> {
        let history = self.store.history(thread_id).await?;
        let Some(receipt) = history.input_identity(input_id).await? else {
            if self.threads.thread(thread_id).is_some_and(|thread| {
                let state = thread.snapshot();
                state
                    .inputs
                    .iter()
                    .any(|record| record.input.id == input_id)
                    || state
                        .terminal_inputs
                        .iter()
                        .any(|record| record.id == input_id)
            }) {
                return Ok(BotInputRead::NotReady);
            }
            return Ok(BotInputRead::Absent);
        };
        Ok(BotInputRead::Ready {
            delivery: receipt.entry.delivery,
            state: receipt.entry.state,
        })
    }

    /// 按 Turn 身份定点读取持久 typed 状态；不用最新终态 Turn 或整段翻页代替目标。
    pub(crate) async fn bot_turn_fact(
        &self,
        thread_id: &str,
        turn_id: &str,
    ) -> Result<BotTurnRead> {
        let history = self.store.history(thread_id).await?;
        let item_id = crate::studio::thread_projection::order::turn_id(turn_id);
        let Some(item) = history.item(&item_id).await? else {
            return Ok(BotTurnRead::Absent);
        };
        match item.state() {
            ThreadItemState::Turn(turn_item) => Ok(BotTurnRead::Ready(turn_item.state().clone())),
            _ => bail!("durable turn item {item_id} does not carry turn state"),
        }
    }

    /// 读取一条交互的 canonical 事实：驻留/checkpoint 提供 pending 与新近记录，
    /// durable 回执是终局与 continuation 身份的权威。
    ///
    /// 回执按交互自身的每个已提交 revision 落库（创建即写入 Pending revision，
    /// resolve/cancel 追加更高 revision），`latest_fact_receipt` 取最高 revision，
    /// 因此 Pending 回执是合法的已持久等待事实，不是读取故障。合成选取依据：
    /// 持久 terminal 回执最优先（revision 只增，驻留快照短暂滞后不能覆盖已提交
    /// 终局）；持久层无终局而驻留已终局时为 NotReady——旧 Pending 不能被当成
    /// 无 continuation；其余 Pending 事实一律保持等待，不消耗重试预算。
    pub(crate) async fn bot_interaction_fact(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<BotInteractionRead> {
        let resident = self.bot_resident_interaction(thread_id, local_id).await?;
        let receipt = self.bot_interaction_receipt(thread_id, local_id).await?;
        if let Some(fact) = receipt
            .as_ref()
            .filter(|fact| interaction_status_terminal(fact.status))
        {
            return Ok(BotInteractionRead::Ready(fact.clone()));
        }
        match (resident, receipt) {
            (Some(interaction), _) if interaction.status() != InteractionStatus::Pending => {
                // 驻留已终局而持久终局未可读（回执缺失或仍停留在旧 Pending
                // revision）：事实未定，不解释为取消或无 continuation。
                Ok(BotInteractionRead::NotReady)
            }
            // 持久 Pending 回执是合法等待事实（驻留同为 Pending 或无驻留均等待）。
            (_, Some(fact)) => Ok(BotInteractionRead::Ready(fact)),
            // 无回执但驻留 Pending：effect 尚未提交的窗口，同样保持等待。
            (Some(interaction), None) => Ok(BotInteractionRead::Ready(BotInteractionFact {
                kind: bot_interaction_kind(&interaction),
                status: InteractionStatus::Pending,
                continuation_input: None,
            })),
            (None, None) => Ok(BotInteractionRead::Absent),
        }
    }

    /// 驻留或冷 checkpoint 的产品投影；不激活执行 owner。
    async fn bot_resident_interaction(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<InteractionRequest>> {
        if let Some(handle) = self.threads.thread(thread_id) {
            let snapshot = handle.snapshot();
            return crate::thread_assembler::project_thread_interaction(
                thread_id, local_id, &snapshot,
            )
            .map_err(anyhow::Error::from);
        }
        let thread = self.read_protocol_thread(thread_id).await?;
        let checkpoint =
            crate::studio::thread_factory::recovery::load_checkpoint(&self.store, &thread).await?;
        checkpoint
            .and_then(|checkpoint| {
                crate::thread_assembler::project_thread_interaction(
                    thread_id,
                    local_id,
                    &checkpoint.state,
                )
                .transpose()
            })
            .transpose()
            .map_err(anyhow::Error::from)
    }

    /// durable 终局回执；interaction 与 permission 分别按同一 receipt 身份读取。
    async fn bot_interaction_receipt(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<BotInteractionFact>> {
        let history = self.store.history(thread_id).await?;
        for kind in ["interaction", "permission"] {
            let Some(receipt) = history
                .latest_fact_receipt(&crate::studio::thread_projection::order::receipt_id(
                    kind, local_id,
                ))
                .await?
            else {
                continue;
            };
            if receipt.kind != kind {
                continue;
            }
            return match kind {
                "interaction" => {
                    let record: InteractionRecord = serde_json::from_str(&receipt.payload)?;
                    let status = match &record.state {
                        InteractionState::Resolved(_) => InteractionStatus::Resolved,
                        InteractionState::Cancelled => InteractionStatus::Cancelled,
                        // 交互创建（Pending revision 1）随 effect 事务提交即落回执：
                        // 合法的已持久等待事实，读取方保持等待而不是报错。
                        InteractionState::Pending => InteractionStatus::Pending,
                    };
                    Ok(Some(BotInteractionFact {
                        kind: BotInteractionKind::UserInput,
                        status,
                        continuation_input: record.continuation_id,
                    }))
                }
                _ => {
                    let record: PermissionRecord = serde_json::from_str(&receipt.payload)?;
                    let status = match record.state {
                        PermissionState::Allowed | PermissionState::Denied => {
                            InteractionStatus::Resolved
                        }
                        PermissionState::Cancelled => InteractionStatus::Cancelled,
                        // 权限创建同样先落 Pending revision；保持与交互一致的等待语义。
                        PermissionState::Pending => InteractionStatus::Pending,
                    };
                    Ok(Some(BotInteractionFact {
                        kind: BotInteractionKind::Permission,
                        status,
                        continuation_input: None,
                    }))
                }
            };
        }
        Ok(None)
    }
}

fn bot_interaction_kind(interaction: &InteractionRequest) -> BotInteractionKind {
    match interaction.kind() {
        pl_protocol::InteractionKind::UserInput => BotInteractionKind::UserInput,
        pl_protocol::InteractionKind::ToolApproval => BotInteractionKind::Permission,
    }
}

fn interaction_status_terminal(status: InteractionStatus) -> bool {
    !matches!(status, InteractionStatus::Pending)
}
