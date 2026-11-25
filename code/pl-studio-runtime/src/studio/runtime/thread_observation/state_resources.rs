//! Deferred State values indexed by their original publisher. Readers never own a reducer/cache.

use std::{collections::BTreeMap, sync::Arc};

use crate::studio::thread_projection::{
    CurrentEntryWrite, CurrentPositionIndex, collection_revision, page_rows,
};
use crate::{
    CurrentCollectionPage, CurrentCollectionRef, CurrentContentRef, CurrentStateField, ReadDemand,
    ThreadActivity, ThreadRuntimeSnapshot,
};
use anyhow::{Result, ensure};
use serde::Serialize;

const INLINE_FIELD_BYTES: usize = 2048;

#[derive(Clone, Default)]
struct Field {
    version: u64,
    body: Option<Arc<[u8]>>,
    rows: Option<Arc<CurrentPositionIndex>>,
}

#[derive(Clone, Default)]
pub(in crate::studio::runtime) struct StateResources {
    owner_id: String,
    cold_revision: Option<u64>,
    fields: BTreeMap<(&'static str, &'static str), Field>,
}

impl StateResources {
    pub fn bind(&mut self, owner_id: String) {
        if self.owner_id != owner_id || self.cold_revision.is_some() {
            self.owner_id = owner_id;
            self.cold_revision = None;
            self.fields.clear();
        }
    }

    pub fn cold(owner_id: String, revision: u64) -> Self {
        Self {
            owner_id,
            cold_revision: Some(revision),
            fields: BTreeMap::new(),
        }
    }

    /// Cold current projection shared by the reader and the state feed.
    ///
    /// The resources keep deferred body bytes. Callers that only need the runtime snapshot
    /// drop the resources after taking the second value.
    pub fn project_cold(
        owner_id: String,
        revision: u64,
        thread_id: &str,
        state: &pl_core::thread::ThreadSnapshot,
        updated_at: i64,
        summary: &pl_core::thread::UsageSummary,
    ) -> Result<(Self, ThreadRuntimeSnapshot)> {
        let projected = crate::studio::thread_projection::project_cold_runtime(
            thread_id, state, updated_at, summary,
        )?;
        let mut resources = Self::cold(owner_id, revision);
        let runtime = resources.runtime(projected)?;
        Ok((resources, runtime))
    }

    fn generation(&self, version: u64) -> String {
        match self.cold_revision {
            Some(revision) => format!("cold:{revision}:{version}"),
            None => version.to_string(),
        }
    }

    fn defer<T: Serialize + Default>(
        &mut self,
        domain: &'static str,
        name: &'static str,
        value: &mut T,
        heads: &mut Vec<CurrentStateField>,
    ) -> Result<()> {
        ensure!(
            !self.owner_id.is_empty(),
            "State publisher has no Current owner"
        );
        let bytes = serde_json::to_vec(value)?;
        let field = self.fields.entry((domain, name)).or_default();
        if bytes.len() <= INLINE_FIELD_BYTES {
            field.body = None;
            return Ok(());
        }
        if field.body.as_deref() != Some(bytes.as_slice()) {
            field.version = field
                .version
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("State field generation exhausted"))?;
            field.body = Some(bytes.into());
        }
        let version = field.version;
        let byte_length = field.body.as_ref().map_or(0, |body| body.len() as u64);
        heads.push(CurrentStateField::Body {
            field: name.into(),
            reference: CurrentContentRef {
                owner_id: self.owner_id.clone(),
                domain: domain.into(),
                entity_id: "state".into(),
                content_key: name.into(),
                generation: self.generation(version),
            },
            byte_length,
        });
        *value = T::default();
        Ok(())
    }

    fn defer_collection<T: Serialize>(
        &mut self,
        domain: &'static str,
        name: &'static str,
        values: &mut Vec<T>,
        heads: &mut Vec<CurrentStateField>,
    ) -> Result<()> {
        ensure!(
            !self.owner_id.is_empty(),
            "State publisher has no Current owner"
        );
        let collection = format!("{domain}:{name}");
        let rows = values
            .iter()
            .enumerate()
            .map(|(index, value)| {
                let position = i64::try_from(index)?;
                let id = index.to_string();
                let entry = Arc::new(CurrentEntryWrite {
                    collection: collection.clone(),
                    position,
                    entry_id: id.clone(),
                    payload: Arc::from(serde_json::to_vec(value)?),
                });
                Ok(((collection.clone(), position, id), entry))
            })
            .collect::<Result<CurrentPositionIndex>>()?;
        let encoded_bytes = rows.values().fold(2usize, |sum, entry| {
            sum.saturating_add(entry.payload.len()).saturating_add(1)
        });
        let field = self.fields.entry((domain, name)).or_default();
        if encoded_bytes <= INLINE_FIELD_BYTES {
            field.rows = None;
            return Ok(());
        }
        let unchanged = field.rows.as_ref().is_some_and(|old| {
            old.len() == rows.len()
                && old
                    .iter()
                    .zip(rows.iter())
                    .all(|((key, old), (new_key, new))| {
                        key == new_key && old.payload == new.payload
                    })
        });
        if !unchanged {
            field.version = field
                .version
                .checked_add(1)
                .ok_or_else(|| anyhow::anyhow!("State collection version exhausted"))?;
            field.rows = Some(Arc::new(rows));
        }
        let version = self.cold_revision.unwrap_or(field.version);
        let reference = CurrentCollectionRef {
            owner_id: self.owner_id.clone(),
            collection,
            revision: collection_revision(version, self.cold_revision.is_some())?,
        };
        heads.push(CurrentStateField::Collection {
            field: name.into(),
            reference,
            count: values.len() as u64,
        });
        values.clear();
        Ok(())
    }

    fn collection(
        &self,
        reference: &CurrentCollectionRef,
    ) -> Result<Option<&Arc<CurrentPositionIndex>>> {
        if reference.owner_id != self.owner_id {
            return Ok(None);
        }
        for ((domain, name), field) in &self.fields {
            if reference.collection == format!("{domain}:{name}")
                && reference.revision
                    == collection_revision(
                        self.cold_revision.unwrap_or(field.version),
                        self.cold_revision.is_some(),
                    )?
            {
                return Ok(field.rows.as_ref());
            }
        }
        Ok(None)
    }

    pub fn page(
        &self,
        reference: &CurrentCollectionRef,
        after: Option<&str>,
        demand: ReadDemand,
        encode: impl Fn(String) -> Result<String>,
    ) -> Result<Option<CurrentCollectionPage>> {
        self.collection(reference)?
            .map(|rows| page_rows(rows, reference, after, demand, encode))
            .transpose()
    }

    pub fn runtime(&mut self, mut runtime: ThreadRuntimeSnapshot) -> Result<ThreadRuntimeSnapshot> {
        ensure!(
            runtime.deferred.is_empty(),
            "State runtime was deferred twice"
        );
        let heads = &mut runtime.deferred;
        self.defer("state:runtime", "todo", &mut runtime.todo, heads)?;
        self.defer_collection(
            "state:runtime",
            "activeSkills",
            &mut runtime.active_skills,
            heads,
        )?;
        self.defer_collection(
            "state:runtime",
            "activeMcpServers",
            &mut runtime.active_mcp_servers,
            heads,
        )?;
        self.defer_collection(
            "state:runtime",
            "activeLspServers",
            &mut runtime.active_lsp_servers,
            heads,
        )?;
        self.defer("state:runtime", "progress", &mut runtime.progress, heads)?;
        self.defer("state:runtime", "mcpHealth", &mut runtime.mcp_health, heads)?;
        self.defer("state:runtime", "workflow", &mut runtime.workflow, heads)?;
        self.defer("state:runtime", "plan", &mut runtime.plan, heads)?;
        Ok(runtime)
    }

    pub fn activity(&mut self, activity: Option<ThreadActivity>) -> Result<Option<ThreadActivity>> {
        let Some(mut activity) = activity else {
            for ((domain, _), field) in &mut self.fields {
                if *domain == "state:activity" {
                    field.body = None;
                    field.rows = None;
                }
            }
            return Ok(None);
        };
        ensure!(
            activity.deferred.is_empty(),
            "State activity was deferred twice"
        );
        self.defer_collection(
            "state:activity",
            "tools.active",
            &mut activity.tools.active,
            &mut activity.deferred,
        )?;
        self.defer(
            "state:activity",
            "tools.latestStarted",
            &mut activity.tools.latest_started,
            &mut activity.deferred,
        )?;
        self.defer(
            "state:activity",
            "thinkingSummary",
            &mut activity.thinking_summary,
            &mut activity.deferred,
        )?;
        Ok(Some(activity))
    }

    pub fn body(&self, reference: &CurrentContentRef) -> Option<Arc<[u8]>> {
        if let Some(collection) = reference.domain.strip_prefix("collection:state:") {
            if reference.content_key != "entry" {
                return None;
            }
            let revision = reference.generation.parse().ok()?;
            let head = CurrentCollectionRef {
                owner_id: reference.owner_id.clone(),
                collection: format!("state:{collection}"),
                revision,
            };
            let position: i64 = reference.entity_id.parse().ok()?;
            if position.to_string() != reference.entity_id {
                return None;
            }
            return self
                .collection(&head)
                .ok()??
                .get(&(
                    head.collection.clone(),
                    position,
                    reference.entity_id.clone(),
                ))
                .map(|entry| entry.payload.clone());
        }
        if reference.owner_id != self.owner_id || reference.entity_id != "state" {
            return None;
        }
        self.fields.iter().find_map(|((domain, name), field)| {
            (*domain == reference.domain
                && *name == reference.content_key
                && self.generation(field.version) == reference.generation)
                .then(|| field.body.clone())
                .flatten()
        })
    }
}

#[cfg(test)]
#[path = "state_resources_tests.rs"]
mod tests;
