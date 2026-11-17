//! Deferred State values indexed by their original publisher. Readers never own a reducer/cache.

use std::{collections::BTreeMap, sync::Arc};

use crate::studio::thread_projection::{
    CurrentEntryWrite, CurrentPositionIndex, collection_revision, page_rows,
};
use anyhow::{Result, ensure};
use pl_protocol::{
    CurrentCollectionPage, CurrentCollectionRef, CurrentContentRef, CurrentStateField, ReadDemand,
    ThreadActivity, ThreadRuntimeSnapshot,
};
use serde::Serialize;

const INLINE_FIELD_BYTES: usize = 2048;

#[derive(Clone, Default)]
struct Field {
    version: u64,
    body: Option<Arc<[u8]>>,
    rows: Option<Arc<CurrentPositionIndex>>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_removed_or_replaced_field_never_revalidates_an_old_reference() -> Result<()> {
        let mut owner = StateResources::default();
        owner.bind("run-1".into());
        let original = "原始详情".repeat(600);
        let mut value = Some(original.clone());
        let mut heads = Vec::new();
        owner.defer("state:runtime", "progress", &mut value, &mut heads)?;
        let CurrentStateField::Body {
            reference: first, ..
        } = heads.pop().unwrap()
        else {
            panic!("body field");
        };
        assert!(value.is_none());
        assert_eq!(
            serde_json::from_slice::<String>(&owner.body(&first).unwrap())?,
            original
        );

        let mut small = Some("changed to a small inline value".to_owned());
        owner.defer("state:runtime", "progress", &mut small, &mut heads)?;
        assert!(heads.is_empty());
        assert!(small.is_some());
        assert!(owner.body(&first).is_none());

        let mut returned = Some(original);
        owner.defer("state:runtime", "progress", &mut returned, &mut heads)?;
        let CurrentStateField::Body {
            reference: successor,
            ..
        } = heads.pop().unwrap()
        else {
            panic!("body field");
        };
        assert_ne!(successor.generation, first.generation);
        assert!(owner.body(&first).is_none());
        owner.bind("run-2".into());
        assert!(owner.body(&successor).is_none());
        Ok(())
    }

    #[test]
    fn large_state_lists_page_with_exact_counts_and_retire_all_old_continuations() -> Result<()> {
        let mut owner = StateResources::default();
        owner.bind("run-1".into());
        let original: Vec<String> = (0..301)
            .map(|i| format!("skill-{i}:{}", "正文".repeat(300)))
            .collect();
        let mut values = original.clone();
        let mut heads = Vec::new();
        owner.defer_collection("state:runtime", "activeSkills", &mut values, &mut heads)?;
        let CurrentStateField::Collection {
            reference, count, ..
        } = heads.pop().unwrap()
        else {
            panic!("collection");
        };
        assert_eq!(count, original.len() as u64);
        assert!(values.is_empty());
        assert!(serde_json::to_vec(&reference)?.len() < 256);
        let demand = ReadDemand {
            max_items: 7,
            max_bytes: 2048,
        };
        let mut after = None;
        let mut actual = Vec::new();
        loop {
            let page = owner
                .page(&reference, after.as_deref(), demand, Ok)?
                .unwrap();
            assert!(serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize);
            assert!(page.entries.len() <= demand.max_items as usize);
            for entry in page.entries {
                let bytes = match entry.payload {
                    pl_protocol::CurrentPayloadData::Inline { bytes } => bytes,
                    pl_protocol::CurrentPayloadData::Deferred { reference, .. } => {
                        owner.body(&reference).unwrap().to_vec()
                    }
                };
                actual.push(serde_json::from_slice::<String>(&bytes)?);
            }
            let Some(next) = page.continuation else {
                break;
            };
            after = Some(next);
        }
        assert_eq!(actual, original);

        let mut same = original.clone();
        owner.defer_collection("state:runtime", "activeSkills", &mut same, &mut heads)?;
        let CurrentStateField::Collection {
            reference: same, ..
        } = heads.pop().unwrap()
        else {
            panic!("collection");
        };
        assert_eq!(same, reference);
        let mut changed = original;
        changed[0].push_str("changed");
        owner.defer_collection("state:runtime", "activeSkills", &mut changed, &mut heads)?;
        assert!(owner.page(&reference, None, demand, Ok)?.is_none());

        let mut saved = StateResources::cold("run-1".into(), 0);
        let mut values = actual;
        saved.defer_collection("state:runtime", "activeSkills", &mut values, &mut heads)?;
        let CurrentStateField::Collection {
            reference: cold, ..
        } = heads.pop().unwrap()
        else {
            panic!("collection");
        };
        assert_ne!(
            cold.revision, reference.revision,
            "saved and live refs cannot alias under the same source run"
        );
        assert!(saved.page(&reference, None, demand, Ok)?.is_none());
        Ok(())
    }
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
