use pl_protocol::products::feed::configuration::{
    ConfigurationBaseline, ConfigurationChange, ConfigurationEvent, ConfigurationHeader,
};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};
use std::collections::{BTreeMap, BTreeSet};

use crate::config::{ConfigurationMaterial, ConfigurationSnapshot};

pub(super) struct SentConfiguration {
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

impl SentConfiguration {
    pub(super) fn capture(snapshot: &ConfigurationSnapshot) -> Result<Self, StudioError> {
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

pub(super) fn validate(snapshot: &ConfigurationSnapshot) -> Result<(), StudioError> {
    visible(snapshot)?;
    if snapshot.revision == 0 {
        return Err(StudioError::new(
            StudioErrorCode::Protocol,
            "Configuration projection has no published revision",
            false,
        ));
    }
    Ok(())
}

fn visible(
    snapshot: &ConfigurationSnapshot,
) -> Result<Option<&ConfigurationMaterial>, StudioError> {
    let status = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    let material = snapshot
        .material
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    snapshot
        .pair
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    Ok(status.metadata().value().map(|_| material.as_ref()))
}

pub(super) fn event(
    identity: &ProductFeedIdentity,
    snapshot: &ConfigurationSnapshot,
    previous: Option<&SentConfiguration>,
) -> Result<ConfigurationEvent, FrameError> {
    let material = visible(snapshot)?;
    let status = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    let pair = snapshot
        .pair
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    let header = ConfigurationHeader {
        source: status.header.clone(),
        configuration_revision: material.map(|_| snapshot.stamp.settings_revision),
        updated_at: material.map(|_| snapshot.updated_at),
        reference: material.map(|material| material.reference),
        role_read: material.map(|_| pair.target.clone()),
    };
    let collection = material.map(|material| material.collection);
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    };
    let Some(previous) = previous else {
        return Ok(ConfigurationEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: ConfigurationBaseline { header, collection },
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
    Ok(ConfigurationEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: ConfigurationChange {
            header,
            base_collection_revision: previous.collection.map(|collection| collection.revision),
            collection,
            upserted,
            removed_entries,
        },
    })
}
