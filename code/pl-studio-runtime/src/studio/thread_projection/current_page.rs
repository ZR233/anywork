//! Shared bounded collection selection over an owner cut, including passive checkpoint-derived cuts.
use super::CurrentState;
use anyhow::{Result, ensure};
use pl_core::chat as core;
use pl_protocol::*;

pub(in crate::studio) fn current_page(
    state: &CurrentState,
    reference: &CurrentCollectionRef,
    after: Option<&str>,
    demand: ReadDemand,
    encode: impl Fn(String) -> Result<String>,
) -> Result<CurrentCollectionPage> {
    ensure!(
        state
            .projection()
            .collections
            .iter()
            .any(|current| current == reference),
        core::ChatError::StaleContent
    );
    let boundary = after
        .map(serde_json::from_str::<(i64, String)>)
        .transpose()?;
    use std::ops::Bound::{Excluded, Included};
    let lower = match boundary {
        Some((position, id)) => Excluded((reference.collection.clone(), position, id)),
        None => Included((reference.collection.clone(), i64::MIN, String::new())),
    };
    let upper = Excluded((
        format!("{}\0", reference.collection),
        i64::MIN,
        String::new(),
    ));
    let mut page = CurrentCollectionPage {
        revision: reference.revision,
        entries: Vec::new(),
        continuation: None,
    };
    let mut selected_bytes = 0usize;
    for (_, entry) in state.by_position().range((lower, upper)) {
        if page.entries.len() == demand.max_items as usize {
            return Ok(page);
        }
        let token = encode(serde_json::to_string(&(entry.position, &entry.entry_id))?)?;
        let fixed = serde_json::to_vec(&CurrentCollectionPage {
            revision: reference.revision,
            entries: Vec::new(),
            continuation: Some(token.clone()),
        })?
        .len();
        let mut candidate = CurrentCollectionEntry {
            id: entry.entry_id.clone(),
            position: entry.position,
            payload: PayloadData::Inline { bytes: Vec::new() },
        };
        let overhead = serde_json::to_vec(&candidate)?
            .len()
            .saturating_add(usize::from(!page.entries.is_empty()));
        let inline = overhead.saturating_add(entry.payload.len().saturating_mul(4));
        if fixed.saturating_add(selected_bytes).saturating_add(inline) <= demand.max_bytes as usize
        {
            candidate.payload = PayloadData::Inline {
                bytes: entry.payload.to_vec(),
            };
        } else {
            candidate.payload = PayloadData::Deferred {
                reference: ContentRef {
                    database_id: reference.database_id.clone(),
                    target: ContentTarget::Body {
                        owner: ContentOwner::Current {
                            domain: format!("collection:{}", reference.collection),
                            id: entry.entry_id.clone(),
                            revision: reference.revision,
                        },
                        key: "entry".into(),
                    },
                },
                byte_length: entry.payload.len() as u64,
            };
        }
        let cost = serde_json::to_vec(&candidate)?
            .len()
            .saturating_add(usize::from(!page.entries.is_empty()));
        if fixed.saturating_add(selected_bytes).saturating_add(cost) > demand.max_bytes as usize {
            ensure!(
                !page.entries.is_empty(),
                core::ChatError::InvalidDemand("current envelope does not fit".into())
            );
            return Ok(page);
        }
        selected_bytes = selected_bytes.saturating_add(cost);
        page.entries.push(candidate);
        page.continuation = Some(token);
    }
    page.continuation = None;
    Ok(page)
}
