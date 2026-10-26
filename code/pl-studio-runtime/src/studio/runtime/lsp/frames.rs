use super::source::LspSnapshot;
use pl_protocol::products::feed::lsp::{LspBaseline, LspChange, LspEvent, LspHeader};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::studio::StudioError;
use std::collections::{BTreeMap, BTreeSet};
pub(super) struct SentLsp {
    pub(super) revision: u64,
    collection: Option<ProductCollectionRef>,
    entities: BTreeMap<u64, u64>,
}
pub(super) enum FrameError {
    Source(StudioError),
    Resync(ProductResyncReason),
}
impl From<StudioError> for FrameError {
    fn from(error: StudioError) -> Self {
        Self::Source(error)
    }
}
impl SentLsp {
    pub(super) fn capture(snapshot: &LspSnapshot) -> Result<Self, StudioError> {
        Ok(Self {
            revision: snapshot.revision,
            collection: snapshot
                .material
                .as_ref()
                .map(|material| material.collection),
            entities: snapshot
                .material
                .iter()
                .flat_map(|material| &material.entities)
                .map(|entity| (entity.entry, entity.revision))
                .collect(),
        })
    }
}
pub(super) fn validate(snapshot: &LspSnapshot) -> Result<(), StudioError> {
    if snapshot.revision == 0 {
        return Err(StudioError::invalid_argument(
            "Lsp source has no original publication",
        ));
    }
    Ok(())
}
pub(super) fn event(
    identity: &ProductFeedIdentity,
    snapshot: &LspSnapshot,
    previous: Option<&SentLsp>,
) -> Result<LspEvent, FrameError> {
    let material = snapshot.material.as_ref();
    let header = LspHeader {
        source: snapshot.source_status.header.clone(),
        reference: material.map(|material| material.reference),
    };
    let collection = material.map(|material| material.collection);
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    };
    let Some(previous) = previous else {
        return Ok(LspEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: LspBaseline { header, collection },
        });
    };
    if snapshot.revision <= previous.revision {
        return Err(FrameError::Resync(ProductResyncReason::RevisionGap));
    }
    let mut upserted = Vec::new();
    let mut removed_entries = Vec::new();
    let current: BTreeSet<_> = material
        .into_iter()
        .flat_map(|material| &material.entities)
        .map(|entity| entity.entry)
        .collect();
    for reference in material.into_iter().flat_map(|material| &material.entities) {
        if previous.entities.get(&reference.entry) != Some(&reference.revision) {
            upserted.push(*reference);
        }
        if upserted.len() > 100 {
            return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
        }
    }
    for entry in previous.entities.keys() {
        if !current.contains(entry) {
            removed_entries.push(*entry);
        }
        if upserted.len() + removed_entries.len() > 100 {
            return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
        }
    }
    Ok(LspEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: LspChange {
            header,
            base_collection_revision: previous.collection.map(|collection| collection.revision),
            collection,
            upserted,
            removed_entries,
        },
    })
}
