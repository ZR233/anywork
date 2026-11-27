//! Projects the admitted thread's runtime facts for model context construction.
use pl_core::thread::context_preparation::ContextPreparationRequest;

use super::compaction::receipt_error;

pub(super) fn append_preview_facts(
    records: &mut Vec<pl_core::context::ContextRecord>,
    facts: &[pl_core::thread::RuntimeFact],
    sequence: u64,
) {
    use pl_core::context::{ContextRecord, ContextSource};
    for fact in facts {
        let source = ContextSource::RuntimeFact {
            source_id: fact.source_id.clone(),
        };
        if !records
            .iter()
            .rev()
            .find(|record| record.source == source)
            .is_some_and(|record| record.content == fact.content)
        {
            records.push(ContextRecord {
                tool_data: Default::default(),
                id: format!("preview:{sequence}:{}", fact.source_id),
                turn_id: None,
                source,
                content: fact.content.clone(),
                tool_calls: vec![],
            });
        }
    }
}

/// Each projection consumes only this Thread's frozen extensions, never a parent's state.
pub(super) fn current_facts(
    request: &ContextPreparationRequest,
    mode: Option<&crate::mode::RegisteredThreadMode>,
) -> Result<Vec<pl_core::thread::RuntimeFact>, pl_core::model::ModelError> {
    use pl_core::{context::ContextContent, thread::RuntimeFact};
    let mut facts = request
        .current_facts
        .iter()
        .filter(|fact| {
            !matches!(
                fact.source_id.as_str(),
                "studio.plan" | "studio.plan.document" | "studio.workflow" | "studio.workspace"
            ) && !fact.source_id.starts_with("studio.instructions:")
        })
        .cloned()
        .map(|fact| (fact.source_id.clone(), fact))
        .collect::<std::collections::BTreeMap<_, _>>();
    let mut put = |source_id: &str, content: String| {
        facts.insert(
            source_id.into(),
            RuntimeFact {
                source_id: source_id.into(),
                content: vec![ContextContent::Text {
                    text: content.into(),
                }],
            },
        );
    };
    if let Some(record) = request.extensions.get(crate::plan_tool::PLAN_EXTENSION) {
        let state = crate::plan_tool::decode_plan_state(&record.payload).map_err(receipt_error)?;
        let section =
            crate::plan_tool::plan_model_context_section(&state).map_err(receipt_error)?;
        let mut metadata: serde_json::Value =
            serde_json::from_str(&section.content).map_err(receipt_error)?;
        if let Some(document) = &state.plan.document {
            put("studio.plan.document", serde_json::to_string(&serde_json::json!({"version":document.revision,"contentHash":document.hash,"markdown":document.content})).map_err(receipt_error)?);
            if let Some(document) = metadata
                .get_mut("document")
                .and_then(serde_json::Value::as_object_mut)
            {
                document.remove("markdown");
            }
        } else {
            put(
                "studio.plan.document",
                "Previous plan document is no longer current.".into(),
            );
        }
        put(
            "studio.plan",
            serde_json::to_string(&metadata).map_err(receipt_error)?,
        );
    }
    if let Some(record) = request
        .extensions
        .get(crate::workflow_tool::WORKFLOW_EXTENSION)
    {
        let state =
            crate::workflow_tool::decode_workflow_state(&record.payload).map_err(receipt_error)?;
        if state.current_run.is_some() {
            let mode = mode.ok_or_else(|| {
                receipt_error(std::io::Error::other(
                    "current workflow Mode snapshot is unavailable",
                ))
            })?;
            let section = crate::workflow_tool::workflow_model_context_section(
                &state,
                mode.workflow_binding(),
            )
            .map_err(receipt_error)?
            .ok_or_else(|| {
                receipt_error(std::io::Error::other(
                    "current workflow state does not match its registered graph",
                ))
            })?;
            put("studio.workflow", section.content);
        }
    }
    if let Some(record) = request.extensions.get("studio.workspace") {
        put(
            "studio.workspace",
            format!("Assigned workspace:\n{}", record.payload.content()),
        );
    }
    if let Some(record) = request
        .extensions
        .get(crate::instruction::INSTRUCTIONS_EXTENSION)
    {
        let snapshot =
            crate::instruction::decode_snapshot(&record.payload).map_err(receipt_error)?;
        for record in snapshot.context_records(&request.model.thread_id) {
            if let pl_core::context::ContextSource::RuntimeFact { source_id } = record.source {
                facts.insert(
                    source_id.clone(),
                    RuntimeFact {
                        source_id,
                        content: record.content,
                    },
                );
            }
        }
    }
    Ok(facts.into_values().collect())
}
