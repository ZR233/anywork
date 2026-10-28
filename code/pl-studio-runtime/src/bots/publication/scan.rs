//! Recover identities/order first, release every preview page, then process canonical order.

use super::worker::Cycle;
use super::{attention, tasks::IDENTITY_BYTES};
use crate::bots::protocol::error::FeishuError;
use crate::bots::storage::publication::{
    DeliveryContent, DeliveryEntity, DeliveryEntityKey, DeliveryEntityPage, DeliveryPendingPage,
};
use crate::studio::{InputChainReadLimits, TimelineContentReader, TimelineMetadataRead};
use pl_protocol::TimelinePageQuery;
use std::collections::{BTreeMap, BTreeSet};
use std::future::Future;

pub(super) const MAX_ITEMS: usize = 16_384;
const PROOF_BYTES: u64 = 8 * 1024 * 1024;

/// One recovery pass shares this ceiling with any interaction-identity page scans it needs.
pub(super) struct RecoveryBudget {
    remaining: usize,
    identity_bytes: usize,
    proof_bytes: u64,
}

/// Bytes charged to the same round, not another allowance. Consumed when returned to its owner.
#[derive(Default)]
pub(super) struct IdentityReservation {
    bytes: usize,
}

impl RecoveryBudget {
    pub fn new() -> Self {
        Self {
            remaining: MAX_ITEMS,
            identity_bytes: 0,
            proof_bytes: 0,
        }
    }

    pub fn page_limit(&self) -> Result<u32, FeishuError> {
        if self.remaining == 0 {
            return Err(attention(
                "publication recovery exceeds 16384 content items; complete coverage was not saved",
            ));
        }
        Ok(self.remaining.min(16) as u32)
    }

    pub fn inspect(&mut self, count: usize) -> Result<(), FeishuError> {
        self.remaining = self.remaining.checked_sub(count).ok_or_else(|| {
            attention(
                "publication recovery content budget exhausted; complete coverage was not saved",
            )
        })?;
        Ok(())
    }

    pub fn retain_identity(&mut self, bytes: usize) -> Result<(), FeishuError> {
        self.identity_bytes = self
            .identity_bytes
            .checked_add(bytes)
            .filter(|size| *size <= IDENTITY_BYTES)
            .ok_or_else(|| attention("publication identity recovery byte budget exhausted"))?;
        Ok(())
    }

    pub fn extend_identity(
        &mut self,
        reservation: &mut IdentityReservation,
        bytes: usize,
    ) -> Result<(), FeishuError> {
        let total = reservation
            .bytes
            .checked_add(bytes)
            .ok_or_else(|| attention("publication identity reservation overflow"))?;
        self.retain_identity(bytes)?;
        reservation.bytes = total;
        Ok(())
    }

    pub fn release_identity(
        &mut self,
        reservation: IdentityReservation,
    ) -> Result<(), FeishuError> {
        self.identity_bytes = self
            .identity_bytes
            .checked_sub(reservation.bytes)
            .ok_or_else(|| attention("publication identity reservation accounting mismatch"))?;
        Ok(())
    }

    pub fn replace_identity(
        &mut self,
        reservation: &mut IdentityReservation,
        bytes: usize,
    ) -> Result<(), FeishuError> {
        // Both old and new values still exist at replacement. Check their overlap first.
        self.retain_identity(bytes)?;
        self.release_identity(std::mem::replace(
            reservation,
            IdentityReservation { bytes },
        ))
    }

    pub async fn with_identity_bytes<T>(
        &mut self,
        bytes: usize,
        work: impl Future<Output = Result<T, FeishuError>> + Send,
    ) -> Result<T, FeishuError> {
        let mut reservation = IdentityReservation::default();
        self.extend_identity(&mut reservation, bytes)?;
        // Callers build their copies inside this future, after admission, and drop them before
        // it returns. Release on errors too; row/proof usage is never returned or reset here.
        let result = work.await;
        self.release_identity(reservation)?;
        result
    }

    pub fn proof_limits(&self) -> Result<InputChainReadLimits, FeishuError> {
        let bytes = PROOF_BYTES
            .checked_sub(self.proof_bytes)
            .filter(|bytes| *bytes > 0)
            .ok_or_else(|| attention("publication causal proof byte budget exhausted"))?;
        if self.remaining == 0 {
            return Err(attention("publication causal proof row budget exhausted"));
        }
        InputChainReadLimits::new(self.remaining as u64, bytes)
            .map_err(|error| super::content_error("prepare publication causal proof limits", error))
    }

    pub fn accept_proof_usage(&mut self, rows: u64, bytes: u64) -> Result<(), FeishuError> {
        let total = self
            .proof_bytes
            .checked_add(bytes)
            .filter(|total| *total <= PROOF_BYTES)
            .ok_or_else(|| attention("publication causal proof exceeded its byte limit"))?;
        if rows > self.remaining as u64 {
            return Err(attention(
                "publication causal proof exceeded its remaining row limit",
            ));
        }
        self.inspect(rows as usize)?;
        self.proof_bytes = total;
        Ok(())
    }
}

pub(super) struct Coverage {
    pub items: Vec<(u64, String)>,
    pub entity_keys: BTreeMap<String, DeliveryEntityKey>,
    pub removed_candidates: BTreeMap<String, RemovedCandidate>,
    pub watermark: u64,
}

/// A higher source revision observed after a durable removal, not a new publishing permission.
pub(super) struct RemovedCandidate {
    pub key: DeliveryEntityKey,
    pub observed_revision: u64,
}

struct Identity {
    order: u64,
    /// Only current canonical page/metadata reads populate this, never a pending-index revision.
    observed_revision: Option<u64>,
}

pub(super) async fn recover(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    budget: &mut RecoveryBudget,
    removals: &BTreeSet<String>,
) -> Result<Coverage, FeishuError> {
    let managed = cycle.managed;
    let scope = cycle.scope;
    let old = managed
        .store
        .delivery_cursor(&scope.key)
        .await?
        .order_watermark;
    let mut identities: BTreeMap<String, Identity> = BTreeMap::new();
    let mut entity_keys = BTreeMap::new();
    let mut removed_candidates = BTreeMap::new();
    let mut before: Option<String> = None;
    let mut cursor_identity = IdentityReservation::default();
    let mut watermark = old;
    loop {
        cycle.active()?;
        // Bound the request *before* asking the reader for the next page.
        let limit = budget.page_limit()?;
        let query_bytes = before
            .as_ref()
            .map_or(0, String::len)
            .checked_add(size_of::<String>())
            .ok_or_else(|| attention("publication recovery cursor size overflow"))?;
        let page = budget
            .with_identity_bytes(query_bytes, async {
                reader
                    .page(&TimelinePageQuery {
                        before: before.clone(),
                        limit: Some(limit),
                    })
                    .await
                    .map_err(|e| super::content_error("read publication recovery page", e))
            })
            .await?;
        if page.thread_id != scope.thread_id || page.items.len() > limit as usize {
            return Err(attention(
                "publication recovery page identity/budget mismatch",
            ));
        }
        budget.inspect(page.items.len())?;
        let mut covered_old = false;
        for item in page.items {
            let shell = item.preview;
            if shell.thread_id != scope.thread_id || shell.ordinal == 0 {
                return Err(attention(
                    "publication recovery item identity is inconsistent",
                ));
            }
            watermark = watermark.max(shell.ordinal);
            if shell.ordinal <= old {
                covered_old = true;
            }
            insert(
                &mut identities,
                shell.id,
                Identity {
                    order: shell.ordinal,
                    observed_revision: Some(shell.revision),
                },
                budget,
            )?;
        }
        if !page.has_older || covered_old {
            break;
        }
        let next = page
            .before
            .filter(|s| !s.is_empty())
            .ok_or_else(|| attention("publication recovery lacks an older-page boundary"))?;
        if before.as_ref() == Some(&next) {
            return Err(attention("publication recovery cursor did not advance"));
        }
        budget.replace_identity(
            &mut cursor_identity,
            next.capacity()
                .checked_add(size_of::<String>())
                .ok_or_else(|| attention("publication recovery cursor size overflow"))?,
        )?;
        before = Some(next);
    }
    drop(before);
    budget.release_identity(std::mem::take(&mut cursor_identity))?;
    // Read pending independently first. The complete entity pass below reconciles terminal
    // removals against both this index and any identities already found in canonical pages.
    let mut after = None;
    loop {
        cycle.active()?;
        let page: DeliveryPendingPage = managed
            .store
            .delivery_pending(&scope.key, after, 16)
            .await?;
        for pending in page.pending {
            if !matches!(pending.entity, DeliveryEntityKey::LegacyFinal { .. }) {
                if !identities.contains_key(pending.entity.item_id()) {
                    budget.inspect(1)?;
                }
                if removals.contains(pending.entity.item_id()) {
                    remember_key(&mut entity_keys, &pending.entity, budget)?;
                }
                insert(
                    &mut identities,
                    pending.entity.item_id().to_owned(),
                    Identity {
                        order: pending.item_order.ok_or_else(|| {
                            attention("pending public entity lacks canonical order")
                        })?,
                        observed_revision: None,
                    },
                    budget,
                )?;
            }
        }
        budget.replace_identity(
            &mut cursor_identity,
            stored_cursor_bytes(page.next_after.as_ref())?,
        )?;
        after = page.next_after;
        if after.is_none() {
            break;
        }
    }
    budget.release_identity(std::mem::take(&mut cursor_identity))?;
    // Recheck accepted entities as well as unfinished ones. Removed is already a durable local
    // terminal: only a genuinely higher canonical revision can put it back into pending work.
    let mut after = None;
    loop {
        cycle.active()?;
        let page: DeliveryEntityPage = managed
            .store
            .delivery_entities(&scope.key, after, 1)
            .await?;
        for entity in page.entities {
            if matches!(
                entity.entity,
                DeliveryEntityKey::TextItem { .. } | DeliveryEntityKey::PublicArtifact { .. }
            ) {
                if removals.contains(entity.entity.item_id()) {
                    remember_key(&mut entity_keys, &entity.entity, budget)?;
                }
                if entity.removed
                    && matches!(&entity.state.content, DeliveryContent::Removed { .. })
                {
                    let page_revision = identities
                        .get(entity.entity.item_id())
                        .and_then(|identity| identity.observed_revision);
                    let observed = removal_source_revision(cycle, reader, &entity, budget)
                        .await?
                        .max(page_revision);
                    if let Some(revision) =
                        observed.filter(|revision| *revision > entity.revision())
                    {
                        remember_removed(
                            &mut removed_candidates,
                            &entity.entity,
                            revision,
                            budget,
                        )?;
                        insert(
                            &mut identities,
                            entity.entity.item_id().to_owned(),
                            Identity {
                                order: entity.item_order.ok_or_else(|| {
                                    attention("removed public entity lacks original order")
                                })?,
                                observed_revision: Some(revision),
                            },
                            budget,
                        )?;
                    } else {
                        // This also removes an older preview inserted by the first page pass.
                        // Missing is not the removal proof: the original durable Removed is.
                        identities.remove(entity.entity.item_id());
                    }
                    continue;
                }
                if !identities.contains_key(entity.entity.item_id()) {
                    budget.inspect(1)?;
                }
                insert(
                    &mut identities,
                    entity.entity.item_id().to_owned(),
                    Identity {
                        order: entity
                            .item_order
                            .ok_or_else(|| attention("public entity lacks canonical order"))?,
                        observed_revision: None,
                    },
                    budget,
                )?;
            }
        }
        budget.replace_identity(
            &mut cursor_identity,
            stored_cursor_bytes(page.next_after.as_ref())?,
        )?;
        after = page.next_after;
        if after.is_none() {
            break;
        }
    }
    budget.release_identity(cursor_identity)?;
    let mut items: Vec<_> = identities
        .into_iter()
        .map(|(id, identity)| (identity.order, id))
        .collect();
    items.sort_unstable();
    Ok(Coverage {
        items,
        entity_keys,
        removed_candidates,
        watermark,
    })
}

fn stored_cursor_bytes(cursor: Option<&(i64, String)>) -> Result<usize, FeishuError> {
    cursor.map_or(Ok(0), |(_, key)| {
        key.capacity()
            .checked_add(size_of::<(i64, String)>())
            .ok_or_else(|| attention("publication stored cursor size overflow"))
    })
}

async fn removal_source_revision(
    cycle: &Cycle<'_>,
    reader: &TimelineContentReader,
    entity: &DeliveryEntity,
    budget: &mut RecoveryBudget,
) -> Result<Option<u64>, FeishuError> {
    cycle.active()?;
    budget.inspect(1)?;
    let mut reads = reader
        .read_metadata(&[entity.entity.item_id().to_owned()])
        .await
        .map_err(|e| super::content_error("recheck canonical revision after durable removal", e))?;
    if reads.len() != 1 {
        return Err(attention("removed entity metadata coverage is incomplete"));
    }
    match reads
        .pop()
        .ok_or_else(|| attention("removed entity metadata is missing"))?
    {
        TimelineMetadataRead::Missing { item_id } if item_id == entity.entity.item_id() => Ok(None),
        TimelineMetadataRead::Present(metadata)
            if metadata.shell.id == entity.entity.item_id()
                && metadata.shell.thread_id == cycle.scope.thread_id
                && Some(metadata.shell.ordinal) == entity.item_order
                && Some(metadata.shell.turn_id.as_str()) == entity.turn_id.as_deref() =>
        {
            Ok(Some(metadata.shell.revision))
        }
        _ => Err(attention(
            "removed entity canonical identity is inconsistent",
        )),
    }
}

pub(super) async fn removal_covers_revision(
    cycle: &Cycle<'_>,
    key: &DeliveryEntityKey,
    required_revision: u64,
    budget: &mut RecoveryBudget,
) -> Result<bool, FeishuError> {
    cycle.active()?;
    budget.inspect(1)?;
    let Some(entity) = cycle
        .managed
        .store
        .delivery_entity(&cycle.scope.key, key)
        .await?
    else {
        return Ok(false);
    };
    Ok(entity.removed
        && matches!(&entity.state.content, DeliveryContent::Removed { revision }
            if *revision >= required_revision))
}

fn remember_removed(
    candidates: &mut BTreeMap<String, RemovedCandidate>,
    key: &DeliveryEntityKey,
    observed_revision: u64,
    budget: &mut RecoveryBudget,
) -> Result<(), FeishuError> {
    if let Some(previous) = candidates.get_mut(key.item_id()) {
        if previous.key != *key {
            return Err(attention(
                "removed item maps to ambiguous delivery entities",
            ));
        }
        previous.observed_revision = previous.observed_revision.max(observed_revision);
        return Ok(());
    }
    charge_key(budget, key)?;
    candidates.insert(
        key.item_id().to_owned(),
        RemovedCandidate {
            key: key.clone(),
            observed_revision,
        },
    );
    Ok(())
}

fn remember_key(
    keys: &mut BTreeMap<String, DeliveryEntityKey>,
    key: &DeliveryEntityKey,
    budget: &mut RecoveryBudget,
) -> Result<(), FeishuError> {
    if let Some(previous) = keys.get(key.item_id()) {
        if previous != key {
            return Err(attention(
                "public item maps to multiple original delivery entities",
            ));
        }
        return Ok(());
    }
    // Charge the lookup ID, the complete typed key and its tree entry to the original 4 MiB
    // identity reservation. PublicArtifact requires its real publication_id, never a guessed key.
    charge_key(budget, key)?;
    keys.insert(key.item_id().to_owned(), key.clone());
    Ok(())
}

fn insert(
    ids: &mut BTreeMap<String, Identity>,
    id: String,
    identity: Identity,
    budget: &mut RecoveryBudget,
) -> Result<(), FeishuError> {
    if let Some(previous) = ids.get_mut(&id) {
        if previous.order != identity.order {
            return Err(attention("canonical public identity changed order"));
        }
        previous.observed_revision = previous.observed_revision.max(identity.observed_revision);
        return Ok(());
    }
    budget.retain_identity(id.len().saturating_add(160))?;
    if ids.len() >= MAX_ITEMS {
        return Err(attention(
            "publication identity recovery budget exhausted; complete coverage was not saved",
        ));
    }
    ids.insert(id, identity);
    Ok(())
}

fn charge_key(budget: &mut RecoveryBudget, key: &DeliveryEntityKey) -> Result<(), FeishuError> {
    let extra = key
        .item_id()
        .len()
        .checked_mul(2)
        .and_then(|size| size.checked_add(key.publication_id().len()))
        .and_then(|size| size.checked_add(192))
        .ok_or_else(|| attention("publication entity-key budget overflow"))?;
    budget.retain_identity(extra)
}
