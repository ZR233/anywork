//! Delta bases contain only the last successfully delivered identities, never a second body cache.
use std::collections::{BTreeMap, BTreeSet};

use pl_protocol::products::feed::model_catalog::{
    ModelCatalogBaseline, ModelCatalogChange, ModelCatalogEvent, ModelCatalogHeader,
};
use pl_protocol::products::identity::{
    ProductCollectionRef, ProductFeedIdentity, ProductProjectionStamp, ProductResyncReason,
};
use pl_protocol::studio::{StudioError, StudioErrorCode};

use crate::config::{ModelCatalogMaterial, ModelSourceStatusFailure, ModelsSnapshot};

const MAX_DELTA_MEMBERS: usize = 100;

pub(super) enum CatalogEventError {
    Source(StudioError),
    Resync(ProductResyncReason),
}

impl From<StudioError> for CatalogEventError {
    fn from(error: StudioError) -> Self {
        Self::Source(error)
    }
}

pub(super) struct SentCatalog {
    pub(super) revision: u64,
    collection: Option<ProductCollectionRef>,
    entities: BTreeMap<u64, u64>,
}

impl SentCatalog {
    pub(super) fn capture(snapshot: &ModelsSnapshot) -> Result<Self, StudioError> {
        let material = visible_material(snapshot)?;
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

pub(super) fn validate(snapshot: &ModelsSnapshot) -> Result<(), StudioError> {
    visible_material(snapshot)?;
    if snapshot.revision == 0 {
        return Err(StudioError::new(
            StudioErrorCode::Protocol,
            "ModelCatalog has no published projection revision",
            false,
        ));
    }
    Ok(())
}

/// Both captures must succeed, independently of source availability. In particular Ready does
/// not excuse a failed business capture, and a business value cannot excuse failed metadata.
fn visible_material(
    snapshot: &ModelsSnapshot,
) -> Result<Option<&ModelCatalogMaterial>, StudioError> {
    let status = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| ModelSourceStatusFailure::diagnostic(failure))?;
    let material = snapshot
        .material
        .as_ref()
        .map_err(|failure| failure.diagnostic.clone())?;
    Ok(status.metadata().value().map(|_| material.as_ref()))
}

pub(super) fn event(
    identity: &ProductFeedIdentity,
    snapshot: &ModelsSnapshot,
    previous: Option<&SentCatalog>,
) -> Result<ModelCatalogEvent, CatalogEventError> {
    let material = visible_material(snapshot)?;
    let source = snapshot
        .source_status
        .as_ref()
        .map_err(|failure| ModelSourceStatusFailure::diagnostic(failure))?;
    let header = ModelCatalogHeader {
        source: source.header.clone(),
        catalog_revision: material.map(|_| snapshot.stamp.model_catalog_revision),
        updated_at: material.map(|_| snapshot.updated_at),
        reference: material.map(|material| material.reference),
    };
    let collection = material.map(|material| material.collection);
    let stamp = ProductProjectionStamp {
        owner_epoch: identity.owner_epoch.clone(),
        incarnation: identity.incarnation,
        revision: snapshot.revision,
    };
    let Some(previous) = previous else {
        return Ok(ModelCatalogEvent::Baseline {
            identity: identity.clone(),
            stamp,
            value: ModelCatalogBaseline { header, collection },
        });
    };
    if snapshot.revision <= previous.revision {
        return Err(CatalogEventError::Resync(ProductResyncReason::RevisionGap));
    }
    let mut upserted = Vec::new();
    let mut removed_entries = Vec::new();
    if let Some(material) = material {
        for reference in &material.entities {
            if previous.entities.get(&reference.entry) != Some(&reference.revision) {
                upserted.push(*reference);
                if upserted.len() > MAX_DELTA_MEMBERS {
                    return Err(CatalogEventError::Resync(ProductResyncReason::SourceLagged));
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
                if upserted.len() + removed_entries.len() > MAX_DELTA_MEMBERS {
                    return Err(CatalogEventError::Resync(ProductResyncReason::SourceLagged));
                }
            }
        }
    }
    // Loss of source value is availability, not a fabricated removal of every account.
    Ok(ModelCatalogEvent::Change {
        stamp,
        base_revision: previous.revision,
        value: ModelCatalogChange {
            header,
            base_collection_revision: previous.collection.map(|value| value.revision),
            collection,
            upserted,
            removed_entries,
        },
    })
}
