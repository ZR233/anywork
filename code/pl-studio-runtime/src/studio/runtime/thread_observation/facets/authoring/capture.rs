use super::*;
use anyhow::{Context, Result, ensure};
use pl_core::thread::{
    ThreadSnapshot,
    cold::ThreadWrite,
    extensions::{ExtensionChange, ExtensionRecord},
};
use pl_protocol::thread_facets::authoring::*;
use pl_protocol::thread_facets::identity::{ThreadCapabilitySupport, TodoReadRef, WorkflowReadRef};

const TODO: &str = "pl.tool.todo";

struct Decoded {
    todo: Option<(ExtensionRecord, TodoSource)>,
    plan: Option<(PlanBrief, Option<AgentSessionPlanDocument>)>,
    workflow: Option<WorkflowRuntimeSnapshot>,
}
impl AuthoringProjection {
    /// The original handle's initial snapshot is the only hot baseline, never a token watch.
    pub(in crate::studio::runtime) fn seed(&self, snapshot: &ThreadSnapshot) {
        if let Err(error) = self.capture(snapshot, None) {
            self.capture_failure(Arc::new(error), true);
        }
    }
    /// Exactly one call per committed write of the existing LiveOwner, including unchanged domains.
    pub(in crate::studio::runtime) fn observe(&self, write: &ThreadWrite) {
        if self.already_captured(write.effect.sequence) {
            return;
        }
        let result = (|| {
            ensure!(
                write.effect.thread_id == self.thread_id,
                "Authoring commit belongs to another Thread"
            );
            ensure!(
                write.effect.sequence == write.checkpoint.state.commit_sequence,
                "Authoring checkpoint/effect sequence mismatch"
            );
            validate_extensions(&write.checkpoint.state, &write.effect.extensions)?;
            self.capture(&write.checkpoint.state, Some(write.effect.sequence))
        })();
        if let Err(error) = result {
            self.capture_failure(Arc::new(error), true);
        }
    }
    fn already_captured(&self, sequence: u64) -> bool {
        let state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.terminal.is_some() || state.sequence.is_some_and(|previous| sequence <= previous)
    }
    fn capture(&self, snapshot: &ThreadSnapshot, committed: Option<u64>) -> Result<()> {
        if self.already_captured(snapshot.commit_sequence) {
            return Ok(());
        }
        // Producer decoding can be nontrivial. It runs outside registry/projection locks; this
        // original LiveOwner is serial and the publication guard rechecks terminal/sequence below.
        let mut decoded = decode(snapshot)?;
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if state.terminal.is_some() {
            return Ok(());
        }
        if let Some(sequence) = state.sequence {
            if snapshot.commit_sequence <= sequence {
                return Ok(());
            }
            if committed.is_none() || sequence.checked_add(1) != Some(snapshot.commit_sequence) {
                for listener in state.listeners.iter().filter_map(Weak::upgrade) {
                    listener.request_resync(ResyncReason::RevisionGap);
                }
            }
        }
        let previous = state.current.clone();
        state.locators.retain(|_, locator| locator.material.alive());
        // A compact delivery window may retire the proof, but cannot revoke an already captured
        // identity for the exact unchanged record. Never infer a new identity from adjacent text.
        if let Some((record, todo)) = &mut decoded.todo
            && todo.call_id.is_none()
            && previous
                .as_ref()
                .is_some_and(|old| old.todo_record.as_ref() == Some(&*record))
            && let Some(old) = previous.as_ref().and_then(|old| fact_of(old, Kind::Todo))
            && let Material::Todo(source) = &*old.material
        {
            todo.call_id.clone_from(&source.call_id);
        }
        if previous
            .as_ref()
            .is_some_and(|old| unchanged(old, &decoded))
        {
            state.sequence = Some(snapshot.commit_sequence);
            state.capture_error = None;
            drop(state);
            self.changed.notify_waiters();
            return Ok(());
        }
        let revision = previous
            .as_ref()
            .map(|old| old.stamp.revision.checked_add(1).ok_or_else(exhausted))
            .transpose()?
            .unwrap_or(0);
        // Charge the original canonical source JSON, not just the small wire references. A
        // pending frame pins this capture's source; no transport gets a second pending budget.
        let source_bytes = [
            TODO,
            crate::plan_tool::PLAN_EXTENSION,
            crate::workflow_tool::WORKFLOW_EXTENSION,
        ]
        .into_iter()
        .filter_map(|key| snapshot.extensions.get(key))
        .try_fold(0usize, |total, record| {
            let bytes = crate::studio::runtime::read_budget::json_bytes(record)?;
            total.checked_add(bytes).ok_or_else(exhausted)
        })?;
        let mut facts = Vec::new();
        let todo_record = decoded.todo.as_ref().map(|(record, _)| record.clone());
        let todo = decoded
            .todo
            .map(|(_, source)| {
                let source_revision = source.revision;
                let source = Arc::new(source);
                let fact = register(
                    &mut state,
                    previous.as_deref().and_then(|old| fact_of(old, Kind::Todo)),
                    Material::Todo(source.clone()),
                    source_revision,
                    revision,
                )?;
                let value = TodoBrief {
                    reference: TodoReadRef {
                        entry: fact.entry,
                        revision: fact.revision,
                    },
                    item_count: u64::try_from(source.items.len()).map_err(|_| exhausted())?,
                    has_call_id: source.call_id.is_some(),
                };
                facts.push(fact);
                Ok::<_, StudioError>(value)
            })
            .transpose()?;
        let workflow = decoded
            .workflow
            .map(|source| {
                let source = Arc::new(source);
                let fact = register(
                    &mut state,
                    previous
                        .as_deref()
                        .and_then(|old| fact_of(old, Kind::Workflow)),
                    Material::Workflow(source.clone()),
                    source.revision,
                    revision,
                )?;
                let value = WorkflowBrief {
                    reference: WorkflowReadRef {
                        entry: fact.entry,
                        revision: fact.revision,
                    },
                    revision: source.revision,
                    has_current_run: source.current_run.is_some(),
                    lifecycle: source.current_run.as_ref().map(|run| run.lifecycle),
                    mode_deleted: source.current_run.as_ref().map(|run| run.mode_deleted),
                };
                facts.push(fact);
                Ok::<_, StudioError>(value)
            })
            .transpose()?;
        let plan = if let Some((brief, document)) = decoded.plan {
            if let Some(document) = document {
                if let Some(old) = previous
                    .as_deref()
                    .and_then(|old| fact_of(old, Kind::Document))
                    && let Material::Document(old) = &*old.material
                    && old.version == document.version
                    && old.content_hash == document.content_hash
                {
                    ensure!(
                        old.markdown == document.markdown,
                        "Original Plan version/hash names conflicting markdown"
                    );
                }
                let version = document.version;
                facts.push(register(
                    &mut state,
                    previous
                        .as_deref()
                        .and_then(|old| fact_of(old, Kind::Document)),
                    Material::Document(Arc::new(document)),
                    version,
                    revision,
                )?);
            }
            Some(brief)
        } else {
            None
        };
        let value = AuthoringBaseline {
            todo,
            plan,
            workflow,
            progress: ThreadCapabilitySupport::Unsupported,
        };
        state.sequence = Some(snapshot.commit_sequence);
        state.capture_error = None;
        if let Some(previous) = &previous {
            for old in &previous.facts {
                if !facts.iter().any(|fact| fact.entry == old.entry)
                    && let Some(locator) = state.locators.get_mut(&(old.entry, old.revision))
                {
                    locator.retired_at = Some(revision);
                }
            }
        }
        let next = Arc::new(AuthoringSnapshot {
            stamp: ThreadFacetStamp {
                runtime_epoch: self.epoch.clone(),
                incarnation: self.incarnation,
                facet: ThreadFacet::Authoring,
                revision,
            },
            value,
            facts,
            todo_record,
            source_bytes,
        });
        let change = previous
            .as_ref()
            .map(|old| (old.stamp.revision, difference(&old.value, &next.value)));
        state
            .listeners
            .retain(|listener| listener.strong_count() != 0);
        for listener in state.listeners.iter().filter_map(Weak::upgrade) {
            listener.publish(next.clone(), change.clone());
        }
        state.current = Some(next);
        drop(state);
        self.changed.notify_waiters();
        Ok(())
    }
}

#[derive(Clone, Copy)]
enum Kind {
    Todo,
    Workflow,
    Document,
}
fn fact_of(snapshot: &AuthoringSnapshot, kind: Kind) -> Option<&Fact> {
    snapshot.facts.iter().find(|fact| {
        matches!(
            (&*fact.material, kind),
            (Material::Todo(_), Kind::Todo)
                | (Material::Workflow(_), Kind::Workflow)
                | (Material::Document(_), Kind::Document)
        )
    })
}
fn unchanged(old: &AuthoringSnapshot, next: &Decoded) -> bool {
    let todo = match (fact_of(old, Kind::Todo), next.todo.as_ref()) {
        (None, None) => true,
        (Some(fact), Some((_, value))) => {
            matches!(&*fact.material, Material::Todo(old) if old.as_ref() == value)
        }
        _ => false,
    };
    let workflow = match (fact_of(old, Kind::Workflow), next.workflow.as_ref()) {
        (None, None) => true,
        (Some(fact), Some(value)) => {
            matches!(&*fact.material, Material::Workflow(old) if old.as_ref() == value)
        }
        _ => false,
    };
    let document = match (
        fact_of(old, Kind::Document),
        next.plan.as_ref().and_then(|(_, value)| value.as_ref()),
    ) {
        (None, None) => true,
        (Some(fact), Some(value)) => {
            matches!(&*fact.material, Material::Document(old) if old.as_ref() == value)
        }
        _ => false,
    };
    todo && workflow
        && document
        && old.value.plan.as_ref() == next.plan.as_ref().map(|(brief, _)| brief)
}
fn register(
    state: &mut State,
    previous: Option<&Fact>,
    material: Material,
    revision: u64,
    born: u64,
) -> Result<Fact, StudioError> {
    if let Some(previous) = previous
        && previous.revision == revision
        && previous.material.same(&material)
    {
        return Ok(previous.clone());
    }
    let entry = state.next_entry;
    state.next_entry = entry.checked_add(1).ok_or_else(exhausted)?;
    let document = match &material {
        Material::Document(value) => Some(PlanDocumentRef {
            version: value.version,
            content_hash: value.content_hash.clone(),
        }),
        Material::Todo(_) | Material::Workflow(_) => None,
    };
    let material = Arc::new(material);
    state.locators.insert(
        (entry, revision),
        Locator {
            material: material.downgrade(),
            born,
            exposed_from: None,
            document,
            retired_at: None,
        },
    );
    Ok(Fact {
        entry,
        revision,
        material,
    })
}
fn difference(old: &AuthoringBaseline, next: &AuthoringBaseline) -> AuthoringChange {
    AuthoringChange {
        todo: if old.todo == next.todo {
            TodoReplacement::Unchanged
        } else {
            TodoReplacement::Replace {
                value: next.todo.clone(),
            }
        },
        plan: if old.plan == next.plan {
            PlanReplacement::Unchanged
        } else {
            PlanReplacement::Replace {
                value: next.plan.clone(),
            }
        },
        workflow: if old.workflow == next.workflow {
            WorkflowReplacement::Unchanged
        } else {
            WorkflowReplacement::Replace {
                value: next.workflow.clone(),
            }
        },
    }
}
fn validate_extensions(snapshot: &ThreadSnapshot, changes: &[ExtensionChange]) -> Result<()> {
    for key in [
        TODO,
        crate::plan_tool::PLAN_EXTENSION,
        crate::workflow_tool::WORKFLOW_EXTENSION,
        "studio.mode",
    ] {
        let last = changes.iter().rev().find(|change| match change {
            ExtensionChange::Put { id, .. } | ExtensionChange::Delete { id, .. } => id == key,
        });
        match last {
            Some(ExtensionChange::Put { record, .. }) => ensure!(
                snapshot.extensions.get(key) == Some(record),
                "Authoring extension/checkpoint mismatch for {key}"
            ),
            Some(ExtensionChange::Delete { .. }) => ensure!(
                !snapshot.extensions.contains_key(key),
                "Authoring deletion/checkpoint mismatch for {key}"
            ),
            None => {}
        }
    }
    Ok(())
}
fn decode(snapshot: &ThreadSnapshot) -> Result<Decoded> {
    let todo = snapshot
        .extensions
        .get(TODO)
        .map(|record| {
            let call_id = snapshot
                .deliveries
                .iter()
                .rev()
                .find(|delivery| delivery.output.payload() == &record.payload)
                .map(|delivery| delivery.call_id.clone())
                .filter(|id| !id.is_empty());
            let value =
                pl_tool::todo::saved_snapshot(&record.payload, call_id.clone().unwrap_or_default())
                    .context("decode original Todo extension")?;
            Ok::<_, anyhow::Error>((
                record.clone(),
                TodoSource {
                    revision: record.revision,
                    call_id,
                    agent_id: value.agent_id,
                    path: value.path,
                    parent_path: value.parent_path,
                    explanation: value.explanation,
                    items: value.items,
                },
            ))
        })
        .transpose()?;
    let plan = snapshot
        .extensions
        .get(crate::plan_tool::PLAN_EXTENSION)
        .map(|record| {
            let state = crate::plan_tool::decode_plan_state(&record.payload)
                .context("decode original Plan extension")?;
            if let Some(document) = &state.document {
                ensure!(
                    document.content_hash
                        == pl_core::context::content_hash(document.markdown.as_bytes()),
                    "Original Plan document hash mismatch"
                );
            }
            let brief = PlanBrief {
                revision: state.revision,
                state: state.state,
                updated_at: state.updated_at,
                document: state.document.as_ref().map(|value| PlanDocumentRef {
                    version: value.version,
                    content_hash: value.content_hash.clone(),
                }),
            };
            Ok::<_, anyhow::Error>((brief, state.document))
        })
        .transpose()?;
    let workflow = snapshot
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
        .map(|record| {
            let state = crate::workflow_tool::decode_workflow_state(&record.payload)
                .context("decode original Workflow extension")?;
            let mut value = WorkflowRuntimeSnapshot::from(&state);
            if let Some(run) = value.current_run.as_mut()
                && let Some(mode) = snapshot.extensions.get("studio.mode")
            {
                let mode = crate::mode::decode_mode_snapshot(&mode.payload)
                    .context("decode original frozen Mode metadata")?;
                // Saved Mode definitions already contain the canonical graph. A same-Thread snapshot
                // may hold a newer graph with the same Mode/state IDs; never relabel its old run.
                if mode.definition.id == run.mode_id
                    && mode.graph_revision == run.graph_revision
                    && let Some(graph) = mode.definition.workflow.as_ref()
                    && crate::hash::canonical_json_hash(
                        &serde_json::to_value(graph)
                            .context("encode original frozen Workflow graph identity")?,
                    ) == run.graph_hash
                {
                    run.mode_display_name
                        .clone_from(&mode.definition.display_name);
                    if let Some(state) = graph
                        .states
                        .iter()
                        .find(|state| state.id == run.current_state_id)
                    {
                        run.current_state_title.clone_from(&state.title);
                    }
                }
            }
            Ok::<_, anyhow::Error>(value)
        })
        .transpose()?;
    Ok(Decoded {
        todo,
        plan,
        workflow,
    })
}
