//! The original HistoryStore owns the RAM/durable display handoff. The pending
//! map indexes shared PreparedCurrent allocations already charged to its reliable
//! writer; it is not another queue, worker, replay log or independent publisher.
use super::*;
use pl_protocol::{ChatEntry, ChatScope, PayloadData, ContentRef, ContentTarget, ReadDemand, TIMELINE_PROJECTION_VERSION};

pub(in crate::studio) struct TimelinePage {
    pub entries: Vec<ChatEntry>,
    pub before: Option<u64>,
    pub ceiling: u64,
}
impl HistoryStore {
    pub(crate) fn timeline_publish(&self, current: std::sync::Arc<conversation::current::PreparedCurrent>) {
        self.state.timeline_pending.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .insert(current.projection.source_effect_seq,current);
    }
    pub(super) fn timeline_saved(&self, through:u64) {
        self.state.timeline_pending.lock().unwrap_or_else(std::sync::PoisonError::into_inner).retain(|seq,_|*seq>through);
    }
    pub(crate) async fn timeline_head_at(&self, scope: &ChatScope, effect_cut: u64) -> Result<u64> {
        let pending = self.state.timeline_pending.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .range(..=effect_cut).map(|(_, current)| current.clone()).collect::<Vec<_>>();
        let pending_head = pending.iter().flat_map(|current| {
            match scope {
                ChatScope::Main => current.timeline.iter().filter_map(|entry| entry.item.position).collect::<Vec<_>>(),
                ChatScope::GroupMembers { reference } => current.timeline_update.current.iter()
                    .chain(current.timeline.iter().map(|entry| &entry.item))
                    .filter(|item| item.members.as_ref() == Some(reference))
                    .filter_map(|item| item.summary.as_ref().and_then(|summary| u64::from(summary.member_count).checked_sub(1))).collect(),
                ChatScope::Children { .. } => Vec::new(),
            }
        }).max().map(|order| order + 1);
        if let Some(head) = pending_head { return Ok(head); }
        let Some(connection) = self.reader().await? else { return Ok(0); };
        let tx = connection.db.begin().await?;
        if let ChatScope::GroupMembers { reference } = scope {
            conversation::timeline::validate_members_ref(&tx, &connection.database_id, reference).await?;
        }
        let rows = conversation::timeline::page_rows(&tx, scope, None, i64::MAX as u64, effect_cut, 1).await?;
        tx.commit().await?;
        Ok(rows.first().map_or(0, |(order, _)| order + 1))
    }
    /// No IO when the captured pending suffix satisfies the requested page.
    /// Taking references before opening the read snapshot closes the save/prune
    /// race: a row is in this capture, in SQLite, or both (identity deduplicated).
    pub(crate) async fn timeline_page(&self, scope:&ChatScope,before:Option<u64>,ceiling:u64,effect_cut:u64,demand:ReadDemand,fixed:usize)->Result<TimelinePage> {
        demand.validate(fixed)?;
        let pending:Vec<_>=self.state.timeline_pending.lock().unwrap_or_else(std::sync::PoisonError::into_inner)
            .range(..=effect_cut).map(|(_,current)|current.clone()).collect();
        let mut rows=std::collections::BTreeMap::new();
        let mut member_exists=false;
        let mut member_head = None;
        let database=match scope {ChatScope::GroupMembers{reference}=>{
            ensure!(reference.projection_version==TIMELINE_PROJECTION_VERSION,ChatError::StaleContent);
            Some(reference.database_id.as_str())
        },_=>None};
        for current in &pending {
            match scope {
                ChatScope::Main=>for entry in current.timeline.iter(){
                    let item=&entry.item;
                    if let Some(position)=item.position.filter(|position|*position<ceiling && before.is_none_or(|before|*position<before)) {
                        rows.insert(position,ChatEntry::Item(Box::new(item.clone())));
                    }
                },
                ChatScope::GroupMembers{reference}=>{
                    let known=current.timeline_update.current.iter().chain(current.timeline.iter().map(|entry|&entry.item)).any(|item| item.members.as_ref()==Some(reference));
                    member_exists|=known;
                    for item in current.timeline_update.current.iter().chain(current.timeline.iter().map(|entry|&entry.item))
                        .filter(|item| item.members.as_ref() == Some(reference)) {
                        if let Some(summary) = &item.summary {
                            member_head = Some(u64::from(summary.member_count));
                        }
                    }
                    for member in &current.timeline_update.members {
                        if member.item_id!=reference.item_id || member.member_order>=ceiling || before.is_some_and(|before|member.member_order>=before){continue;}
                        let mut atom=member.atom.clone();
                        if let (Some(id),Some(bytes))=(&atom.completion_item_id,member.payload_bytes) {
                            atom.payload=Some(PayloadData::Deferred{reference:ContentRef{database_id:reference.database_id.clone(),target:ContentTarget::ItemPayload{item_id:id.clone()}},byte_length:bytes});
                        }
                        rows.insert(member.member_order,ChatEntry::Atom(Box::new(atom)));
                    }
                },
                ChatScope::Children{..}=>anyhow::bail!("children use the original atomic reader"),
            }
        }
        let choose=|rows:&std::collections::BTreeMap<u64,ChatEntry>|->Result<(Vec<(u64,ChatEntry)>,bool)> {
            let mut result=Vec::new();let mut used=fixed;let mut full=false;
            for (order,entry) in rows.iter().rev() {
                let bytes=conversation::timeline::entry_bytes(entry)?;
                if result.len()==demand.max_items as usize || used.checked_add(bytes).is_none_or(|used|used>demand.max_bytes as usize){full=true;break;}
                used+=bytes;result.push((*order,entry.clone()));
            }
            Ok((result,full))
        };
        let (selected,full)=choose(&rows)?;
        // Group updates are sparse mutations, unlike Main's append-only suffix.
        // Enough changed members alone does not prove they are the newest page.
        let pending_prefix = match scope {
            ChatScope::GroupMembers { .. } => member_head.is_some_and(|head| {
                let upper = before.unwrap_or(ceiling).min(ceiling).min(head);
                rows.last_key_value().is_some_and(|(order, _)| order.checked_add(1) == Some(upper))
                    && selected.iter().enumerate().all(|(index, (order, _))| upper.checked_sub(index as u64 + 1) == Some(*order))
            }),
            _ => true,
        };
        if pending_prefix && (full || selected.len()==demand.max_items as usize || selected.last().is_some_and(|(order,_)|*order==0)) {
            ensure!(database.is_none()||member_exists,ChatError::StaleContent);
            return finish(selected,full || rows.len()>=demand.max_items as usize,demand);
        }
        let Some(connection)=self.reader().await? else {return finish(selected,false,demand);};
        let tx=connection.db.begin().await?;
        conversation::timeline::next_position(&tx).await?;
        if let ChatScope::GroupMembers{reference}=scope {
            ensure!(reference.database_id==connection.database_id,ChatError::StaleContent);
            if !member_exists { conversation::timeline::validate_members_ref(&tx,&connection.database_id,reference).await?; }
        }
        let mut boundary=before;
        let mut exhausted=false;
        loop {
            let stored=conversation::timeline::page_rows(&tx,scope,boundary,ceiling,effect_cut,128).await?;
            if stored.is_empty(){exhausted=true;break;}
            let count=stored.len();
            boundary=stored.last().map(|(order,_)|*order);
            for (order,entry) in stored { rows.entry(order).or_insert(entry); }
            let (selected,full)=choose(&rows)?;
            if full || selected.len()==demand.max_items as usize {break;}
            if count<128 {exhausted=true;break;}
        }
        tx.commit().await?;
        let (selected,full)=choose(&rows)?;
        finish(selected,full||!exhausted,demand)
    }
}
fn finish(mut selected:Vec<(u64,ChatEntry)>,more:bool,demand:ReadDemand)->Result<TimelinePage> {
    ensure!(!selected.is_empty() || !more,ChatError::InvalidDemand("display envelope cannot fit demand".into()));
    let before=if more{selected.last().map(|(order,_)|*order).filter(|order|*order>0)}else{None};
    let ceiling = selected.first().map_or(0, |(order, _)| order + 1);
    selected.reverse();
    ensure!(selected.len()<=demand.max_items as usize,ChatError::InvalidDemand("display page exceeds demand".into()));
    Ok(TimelinePage{entries:selected.into_iter().map(|(_,entry)|entry).collect(),before,ceiling})
}
