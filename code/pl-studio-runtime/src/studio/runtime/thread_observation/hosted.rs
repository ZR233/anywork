//! Read-only child facts captured by the host's existing execution projection.
use std::collections::BTreeMap;
use std::sync::Arc;

use anyhow::{Context, Result, ensure};
use pl_protocol::{InteractionRequest, InteractionStatus};

use super::{LiveEvent, ObservationServices};

pub(super) async fn collect(
    services: &ObservationServices,
    host: &str,
    previous: &[Arc<InteractionRequest>],
) -> Result<(Vec<Arc<InteractionRequest>>, Vec<LiveEvent>)> {
    let threads = services.threads.upgrade()?;
    let mut states = BTreeMap::new();
    for record in services.store.read_directory_tree(host).await? {
        if record.parent_thread_id.as_deref() != Some(host)
            || record.visibility != crate::studio::ThreadVisibility::Active
        {
            continue;
        }
        let state = match threads.thread(&record.id) {
            Some(thread) => thread.snapshot(),
            None => {
                let thread = pl_protocol::Thread::from(record.clone());
                let Some(checkpoint) = crate::studio::thread_factory::recovery::load_checkpoint_read_only(
                    &services.store, &thread,
                ).await? else {
                    continue;
                };
                checkpoint.state
            }
        };
        states.insert(record.id, state);
    }
    let mut pending = Vec::new();
    for (child, state) in &states {
        for local in state.interactions.keys().chain(state.permissions.keys()) {
            if state.interactions.get(local).is_some_and(|record| {
                record.request.payload.format() == crate::plan_tool::PLAN_CONFIRMATION_FORMAT
            }) {
                continue;
            }
            let interaction = crate::thread_assembler::project_thread_interaction(child, local, state)?
                .context("child interaction source disappeared")?;
            if interaction.status() == InteractionStatus::Pending {
                pending.push(Arc::new(interaction));
            }
        }
    }
    let mut terminal = Vec::new();
    for old in previous {
        if pending.iter().any(|value| value.interaction_id == old.interaction_id) {
            continue;
        }
        let (child, local) = crate::thread_assembler::decode_interaction_key(&old.interaction_id)?;
        let Some(state) = states.get(child) else {
            // Directory removal is not a decision. It only removes this index member.
            continue;
        };
        let current = crate::thread_assembler::project_thread_interaction(child, local, state)?;
        let current = match current {
            Some(value) => Some(value),
            None => {
                let kind = match old.kind() {
                    pl_protocol::InteractionKind::UserInput => "interaction",
                    pl_protocol::InteractionKind::ToolApproval => "permission",
                };
                let key = crate::studio::thread_projection::order::receipt_id(kind, local);
                let receipt = services.store.history(child).await?.latest_fact_receipt(&key).await?;
                receipt.map(|receipt| {
                    ensure!(receipt.kind == kind, "child decision receipt kind mismatch");
                    super::super::StudioRuntime::project_interaction_receipt(child, local, receipt)
                }).transpose()?
            }
        };
        match current {
            Some(value) if value.status() != InteractionStatus::Pending => {
            terminal.push(LiveEvent::Interaction(Box::new(value)));
        }
            _ => {
                // A pruned live record whose terminal receipt has not arrived is not evidence of
                // removal or decision. Preserve the last exposed fact until real saved progress
                // lets the same host source capture that terminal; never manufacture success.
                pending.push(old.clone());
            }
        }
    }
    Ok((pending, terminal))
}
