//! 交互读取、收束与重启后的 pending 交互恢复。

use anyhow::{Context, Result};

use crate::{InteractionRequest, InteractionResolution, InteractionStatus};

use super::super::{StudioResolveInteractionResponse, StudioRuntime};

/// Keeps the source's durability when the same projected facts are used for validation and replies.
pub(in crate::studio::runtime) struct InteractionForResolve {
    pub(in crate::studio::runtime) interaction: InteractionRequest,
    durable: bool,
}

impl StudioRuntime {
    pub async fn resolve_interaction(
        &self,
        operation_id: String,
        interaction_id: String,
        resolution: InteractionResolution,
    ) -> Result<StudioResolveInteractionResponse> {
        Self::validate_operation_id(&operation_id)?;
        let _lifecycle_guard = self.lifecycle_lock.lock().await;
        let current = self
            .read_interaction_for_resolve(&interaction_id)
            .await?
            .context("interaction not found")?;
        let interaction = current.interaction;
        // A durable receipt can only acknowledge a terminal decision, never admit new work from
        // an old pending revision that has already left the owner and its checkpoint.
        if current.durable || interaction.status() != InteractionStatus::Pending {
            anyhow::ensure!(
                interaction.resolution().as_ref() == Some(&resolution),
                "interaction already has a different terminal resolution"
            );
            return Ok(self.interaction_command_reply(
                operation_id,
                interaction,
                false,
                current.durable,
            ));
        }
        self.ensure_thread_owner(&interaction.scope.thread_id)
            .await?;
        // 到达这里的决议一定来自 Pending 交互，真实受理路径只有 UserInput 决议：
        // 权限决议（ToolApproval）不是用户消息，重复决议在上方已终结短路或持久回执
        // 路径返回，不产生新的受理事实（design/17 §17.1）。
        let user_answered = matches!(resolution, InteractionResolution::UserInput(_));
        let interaction = self
            .threads
            .resolve_product_interaction(&interaction_id, resolution)
            .await?;
        if user_answered {
            self.agent_facility
                .product_events
                .record_user_message(&interaction.scope.thread_id, crate::studio::unix_seconds());
        }
        Ok(self.interaction_command_reply(operation_id, interaction, true, false))
    }

    fn interaction_command_reply(
        &self,
        operation_id: String,
        interaction: InteractionRequest,
        changed: bool,
        durable: bool,
    ) -> StudioResolveInteractionResponse {
        let mut receipt = self.command_receipt(
            operation_id,
            changed,
            vec![self.resource_stamp(
                format!("interaction:{}", interaction.interaction_id),
                interaction.revision,
            )],
            pl_protocol::studio::CommandEffectPoint::Immediate,
            durable,
        );
        receipt.requires_identity_observation = true;
        StudioResolveInteractionResponse {
            thread_id: interaction.scope.thread_id.clone(),
            interaction,
            receipt,
        }
    }

    /// Reads the original interaction and decision from the exact committed core receipt.
    ///
    /// The same product projection supplies the original questions/request to callers and the
    /// terminal resolution to the canonical decision boundary, without activating an owner.
    async fn read_durable_interaction_for_resolve(
        &self,
        thread_id: &str,
        local_id: &str,
    ) -> Result<Option<InteractionForResolve>> {
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
            let mut state = pl_core::thread::ThreadSnapshot::default();
            match receipt.kind.as_str() {
                "interaction" => {
                    state
                        .interactions
                        .insert(local_id.to_owned(), serde_json::from_str(&receipt.payload)?);
                }
                "permission" => {
                    state
                        .permissions
                        .insert(local_id.to_owned(), serde_json::from_str(&receipt.payload)?);
                }
                _ => continue,
            }
            let projected =
                crate::thread_assembler::project_thread_interaction(thread_id, local_id, &state)?
                    .context("durable interaction receipt cannot be projected")?;
            return Ok(Some(InteractionForResolve {
                interaction: projected,
                durable: true,
            }));
        }
        Ok(None)
    }

    /// 内存优先读取交互：pending 交互必须来自驻留 actor 的权威快照；
    /// 冷 checkpoint 也已不再保留时，读取 durable 原始交互与决定供终态重放核对。
    pub(in crate::studio::runtime) async fn read_interaction_for_resolve(
        &self,
        interaction_id: &str,
    ) -> Result<Option<InteractionForResolve>> {
        if let Some(interaction) = self.threads.read_product_interaction(interaction_id)? {
            return Ok(Some(InteractionForResolve {
                interaction,
                durable: false,
            }));
        }
        let (thread_id, local_id) =
            crate::thread_assembler::decode_interaction_key(interaction_id)?;
        let thread = self.read_protocol_thread(thread_id).await?;
        if let Some(checkpoint) =
            crate::studio::thread_factory::recovery::load_checkpoint(&self.store, &thread).await?
            && let Some(interaction) = crate::thread_assembler::project_thread_interaction(
                thread_id,
                local_id,
                &checkpoint.state,
            )?
        {
            return Ok(Some(InteractionForResolve {
                interaction,
                durable: false,
            }));
        }
        self.read_durable_interaction_for_resolve(thread_id, local_id)
            .await
    }
}
