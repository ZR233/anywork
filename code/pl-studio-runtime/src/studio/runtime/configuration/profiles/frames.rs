use crate::config::{ProfilesMaterial, ProfilesSnapshot};
use pl_protocol::products::feed::agent_profiles::{
    AgentProfilesBaseline, AgentProfilesChange, AgentProfilesEvent, AgentProfilesHeader,
};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, BTreeSet};

pub(super) struct SentProfiles {
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
impl SentProfiles {
    pub(super) fn capture(snapshot: &ProfilesSnapshot) -> Result<Self, StudioError> {
        let material = visible(snapshot)?;
        Ok(Self {
            revision: snapshot.revision,
            collection: material.map(|material| material.collection),
            entities: material
                .into_iter()
                .flat_map(|material| material.entities.iter())
                .map(|reference| (reference.entry, reference.revision))
                .collect(),
        })
    }
}
fn visible(snapshot: &ProfilesSnapshot) -> Result<Option<&ProfilesMaterial>, StudioError> {
    let status = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    let material = snapshot
        .material
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    Ok(status.metadata().value().map(|_| material.as_ref()))
}
pub(super) fn validate(snapshot: &ProfilesSnapshot) -> Result<(), StudioError> {
    visible(snapshot)?;
    if snapshot.revision == 0 {
        return Err(StudioError::new(
            StudioErrorCode::Protocol,
            "Profiles projection has no published revision",
            false,
        ));
    }
    Ok(())
}
pub(super) fn event(
    identity: &ProductFeedIdentity,
    snapshot: &ProfilesSnapshot,
    previous: Option<&SentProfiles>,
) -> Result<AgentProfilesEvent, FrameError> {
    let material = visible(snapshot)?;
    let status = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    let header = AgentProfilesHeader {
        source: status.header.clone(),
        profiles_revision: material.map(|_| snapshot.profiles_revision),
        reference: material.map(|material| material.reference),
    };
    let collection = material.map(|material| material.collection);
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    };
    let Some(previous) = previous else {
        return Ok(AgentProfilesEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: AgentProfilesBaseline { header, collection },
        });
    };
    if snapshot.revision <= previous.revision {
        return Err(FrameError::Resync(ProductResyncReason::RevisionGap));
    }
    let mut upserted = Vec::new();
    let mut removed_entries = Vec::new();
    if let Some(material) = material {
        for reference in &material.entities {
            if previous.entities.get(&reference.entry) != Some(&reference.revision) {
                upserted.push(*reference);
                if upserted.len() > 100 {
                    return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
                }
            }
        }
        let current: BTreeSet<_> = material
            .entities
            .iter()
            .map(|reference| reference.entry)
            .collect();
        for entry in previous.entities.keys() {
            if !current.contains(entry) {
                removed_entries.push(*entry);
                if upserted.len() + removed_entries.len() > 100 {
                    return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
                }
            }
        }
    } else if previous.entities.len() > 100 {
        return Err(FrameError::Resync(ProductResyncReason::SourceLagged));
    } else {
        removed_entries.extend(previous.entities.keys().copied());
    }
    Ok(AgentProfilesEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: AgentProfilesChange {
            header,
            base_collection_revision: previous.collection.map(|collection| collection.revision),
            collection,
            upserted,
            removed_entries,
        },
    })
}
