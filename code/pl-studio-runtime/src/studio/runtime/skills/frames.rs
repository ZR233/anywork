use super::source::SkillsSnapshot;
use pl_protocol::products::feed::skills::{
    SkillsBaseline, SkillsChange, SkillsEvent, SkillsHeader,
};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::studio::StudioError;
use std::collections::{BTreeMap, BTreeSet};
pub(super) struct SentSkills {
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
impl SentSkills {
    pub(super) fn capture(snapshot: &SkillsSnapshot) -> Result<Self, StudioError> {
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
pub(super) fn validate(snapshot: &SkillsSnapshot) -> Result<(), StudioError> {
    if snapshot.revision == 0 {
        return Err(StudioError::invalid_argument(
            "Skills source has no original publication",
        ));
    }
    Ok(())
}
pub(super) fn event(
    identity: &ProductFeedIdentity,
    snapshot: &SkillsSnapshot,
    previous: Option<&SentSkills>,
) -> Result<SkillsEvent, FrameError> {
    let material = snapshot.material.as_ref();
    let header = SkillsHeader {
        source: snapshot.source_status.header.clone(),
        reference: material.map(|material| material.reference),
        catalog_revision: material.map(|material| material.value.catalog_revision),
        complete: material.map(|material| material.value.catalog.complete),
    };
    let collection = material.map(|material| material.collection);
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    };
    let Some(previous) = previous else {
        return Ok(SkillsEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: SkillsBaseline { header, collection },
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
    Ok(SkillsEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: SkillsChange {
            header,
            base_collection_revision: previous.collection.map(|collection| collection.revision),
            collection,
            upserted,
            removed_entries,
        },
    })
}
