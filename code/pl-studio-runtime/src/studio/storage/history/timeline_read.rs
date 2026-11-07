//! The original HistoryStore owns the RAM/durable display handoff. The pending
//! map indexes shared PreparedCurrent allocations already charged to its reliable
//! writer; it is not another queue, worker, replay log or independent publisher.
use super::*;
use pl_protocol::{
    ChatEntry, ChatScope, ContentRef, ContentTarget, PayloadData, ReadDemand,
    TIMELINE_PROJECTION_VERSION,
};

pub(in crate::studio) struct TimelinePage {
    pub entries: Vec<ChatEntry>,
    pub before: Option<u64>,
    pub ceiling: u64,
    pub generation: String,
}
pub(in crate::studio) struct TimelineReadCut<'a> {
    pub ceiling: u64,
    pub effect: u64,
    pub active_heads: &'a [pl_protocol::ChatAtom],
}
impl HistoryStore {
    pub(crate) fn timeline_publish(
        &self,
        current: std::sync::Arc<conversation::current::PreparedCurrent>,
    ) {
        self.state
            .timeline_pending
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .publish(current);
    }
    pub(super) fn timeline_saved(&self, through: u64) {
        self.state
            .timeline_pending
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .saved(through);
    }
    /// No IO when the captured pending suffix satisfies the requested page.
    /// Taking references before opening the read snapshot closes the save/prune
    /// race: a row is in this capture, in SQLite, or both (identity deduplicated).
    pub(in crate::studio) async fn timeline_page(
        &self,
        scope: &ChatScope,
        before: Option<u64>,
        cut: TimelineReadCut<'_>,
        demand: ReadDemand,
        fixed: usize,
    ) -> Result<TimelinePage> {
        let TimelineReadCut {
            ceiling,
            effect: effect_cut,
            active_heads,
        } = cut;
        demand.validate(fixed)?;
        let generation = self.timeline_generation().await?;
        let database = self
            .state
            .writer
            .get()
            .or_else(|| self.state.reader.get())
            .map_or("", |connection| connection.database_id.as_str());
        if let ChatScope::GroupMembers { reference } = scope {
            ensure!(
                reference.projection_generation == generation,
                ChatError::StaleContent
            );
        }
        let (members, member_capture, main) = {
            let pending = self
                .state
                .timeline_pending
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            match scope {
                ChatScope::Main => (
                    Vec::new(),
                    None,
                    pending.main_page(before, ceiling, effect_cut, demand.max_items as usize),
                ),
                ChatScope::GroupMembers { reference } => {
                    let page = pending.member_page(
                        &reference.item_id,
                        before,
                        ceiling,
                        effect_cut,
                        demand.max_items as usize,
                    );
                    (page.members, page.head, Vec::new())
                }
                ChatScope::Children { .. } => {
                    anyhow::bail!("business children use their original reader")
                }
            }
        };
        let mut rows = std::collections::BTreeMap::new();
        tracing::debug!(
            target: "conversation_work",
            pending_main_candidates = main.len(),
            pending_member_candidates = members.len(),
            "pending timeline indexed selection"
        );
        for (index, current) in main {
            ensure!(
                current.timeline_update.generation() == generation,
                ChatError::StaleContent
            );
            let item = &current.timeline[index].item;
            conversation::timeline::validate_item(item, database, &generation)?;
            if let Some(position) = item.position {
                rows.insert(position, ChatEntry::Item(Box::new(item.clone())));
            }
        }
        let mut member_exists = false;
        let mut member_head = None;
        if let Some((is_current, index, current)) = member_capture {
            ensure!(
                current.timeline_update.generation() == generation,
                ChatError::StaleContent
            );
            let item = if is_current {
                &current.timeline_update.current()[index]
            } else {
                &current.timeline[index].item
            };
            if let ChatScope::GroupMembers { reference } = scope {
                ensure!(
                    item.members.as_ref() == Some(reference),
                    ChatError::StaleContent
                );
                member_exists = true;
                member_head = item
                    .summary
                    .as_ref()
                    .map(|summary| u64::from(summary.member_count));
            }
        }
        let member_database = match scope {
            ChatScope::GroupMembers { reference } => {
                ensure!(
                    reference.projection_version == TIMELINE_PROJECTION_VERSION,
                    ChatError::StaleContent
                );
                Some(reference.database_id.as_str())
            }
            _ => None,
        };
        for (index, current) in members {
            ensure!(
                current.timeline_update.generation() == generation,
                ChatError::StaleContent
            );
            match scope {
                ChatScope::GroupMembers { reference } => {
                    let member = &current.timeline_update.members()[index];
                    ensure!(member.item_id == reference.item_id, ChatError::StaleContent);
                    let mut atom = member.atom.clone();
                    if matches!(
                        atom.lifecycle,
                        pl_protocol::ChatAtomLifecycle::Active { .. }
                    ) && let Some(captured) = active_heads.iter().find(|head| head.id == atom.id)
                    {
                        ensure!(captured.source == atom.source, ChatError::StaleContent);
                        atom = captured.clone();
                    }
                    if let (Some(id), Some(bytes)) =
                        (&atom.completion_item_id, member.payload_bytes)
                    {
                        atom.payload = Some(PayloadData::Deferred {
                            reference: ContentRef {
                                database_id: reference.database_id.clone(),
                                target: ContentTarget::ItemPayload {
                                    item_id: id.clone(),
                                },
                            },
                            byte_length: bytes,
                        });
                    }
                    rows.insert(member.member_order, ChatEntry::Atom(Box::new(atom)));
                }
                ChatScope::Main | ChatScope::Children { .. } => {
                    anyhow::bail!("non-member scope has an unexpected member capture")
                }
            }
        }
        let choose=|rows:&std::collections::BTreeMap<u64,ChatEntry>|->Result<(Vec<(u64,ChatEntry)>,bool)> {
            let mut result=Vec::new();let mut used=fixed;let mut full=false;
            for (order,entry) in rows.iter().rev() {
                let bytes=conversation::timeline::delivery_entry_bytes(entry,(demand.max_bytes as usize).saturating_sub(used))?;
                if result.len()==demand.max_items as usize || used.checked_add(bytes).is_none_or(|used|used>demand.max_bytes as usize){full=true;break;}
                used+=bytes;result.push((*order,entry.clone()));
            }
            Ok((result,full))
        };
        let (selected, full) = choose(&rows)?;
        // Group updates are sparse mutations, unlike Main's append-only suffix.
        // Enough changed members alone does not prove they are the newest page.
        let pending_prefix = match scope {
            ChatScope::GroupMembers { .. } => member_head.is_some_and(|head| {
                let upper = before.unwrap_or(ceiling).min(ceiling).min(head);
                rows.last_key_value()
                    .is_some_and(|(order, _)| order.checked_add(1) == Some(upper))
                    && selected.iter().enumerate().all(|(index, (order, _))| {
                        upper.checked_sub(index as u64 + 1) == Some(*order)
                    })
            }),
            _ => true,
        };
        if pending_prefix
            && (full
                || selected.len() == demand.max_items as usize
                || selected.last().is_some_and(|(order, _)| *order == 0))
        {
            ensure!(
                member_database.is_none() || member_exists,
                ChatError::StaleContent
            );
            return finish(
                selected,
                full || rows.len() >= demand.max_items as usize,
                demand,
                &generation,
            );
        }
        let Some(connection) = self.reader().await? else {
            return finish(selected, false, demand, &generation);
        };
        let tx = connection.db.begin().await?;
        let head = conversation::timeline::read_state(&tx)
            .await?
            .context("initialized history is missing its timeline recovery head")?;
        ensure!(head.generation == generation, ChatError::StaleContent);
        if let ChatScope::GroupMembers { reference } = scope {
            ensure!(
                reference.database_id == connection.database_id,
                ChatError::StaleContent
            );
            if !member_exists {
                conversation::timeline::validate_members_ref(
                    &tx,
                    &connection.database_id,
                    &head.generation,
                    reference,
                )
                .await?;
            }
        }
        let mut boundary = before;
        let mut exhausted = false;
        loop {
            let stored = conversation::timeline::page_rows(
                &tx,
                scope,
                boundary,
                ceiling,
                effect_cut,
                128,
                active_heads,
            )
            .await?;
            if stored.is_empty() {
                exhausted = true;
                break;
            }
            let count = stored.len();
            boundary = stored.last().map(|(order, _)| *order);
            for (order, entry) in stored {
                if let ChatEntry::Item(item) = &entry {
                    conversation::timeline::validate_item(
                        item,
                        &connection.database_id,
                        &generation,
                    )?;
                }
                rows.entry(order).or_insert(entry);
            }
            let (selected, full) = choose(&rows)?;
            if full || selected.len() == demand.max_items as usize {
                break;
            }
            if count < 128 {
                exhausted = true;
                break;
            }
        }
        tx.commit().await?;
        let (selected, full) = choose(&rows)?;
        finish(selected, full || !exhausted, demand, &generation)
    }
}
fn finish(
    mut selected: Vec<(u64, ChatEntry)>,
    more: bool,
    demand: ReadDemand,
    generation: &str,
) -> Result<TimelinePage> {
    ensure!(
        !selected.is_empty() || !more,
        ChatError::InvalidDemand("display envelope cannot fit demand".into())
    );
    let before = if more {
        selected
            .last()
            .map(|(order, _)| *order)
            .filter(|order| *order > 0)
    } else {
        None
    };
    let ceiling = selected.first().map_or(0, |(order, _)| order + 1);
    selected.reverse();
    ensure!(
        selected.len() <= demand.max_items as usize,
        ChatError::InvalidDemand("display page exceeds demand".into())
    );
    Ok(TimelinePage {
        entries: selected.into_iter().map(|(_, entry)| entry).collect(),
        before,
        ceiling,
        generation: generation.into(),
    })
}
