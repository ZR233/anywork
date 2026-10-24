//! Minimal reliable user originals retained independently of a provider's compaction output.
use super::super::attachment::{self, Attachment, invalid};
use pl_core::{
    context::{ContextContent, ContextRecord, ContextSource},
    model::{ModelError, ModelRequest},
};
use std::collections::HashSet;

const USER_FILES: &str = "model.user-files";

pub(super) struct RetainedContext {
    pub instructions: Vec<ContextRecord>,
    pub inventory: Option<ContextRecord>,
    pub active: Vec<ContextRecord>,
}

pub(super) fn prepare(request: &ModelRequest) -> Result<RetainedContext, ModelError> {
    let snapshot = request
        .context
        .records
        .iter()
        .rev()
        .find(|record| matches!(record.source, ContextSource::InstructionSnapshot { .. }));
    let instructions = if let Some(record) = snapshot {
        vec![record.clone()]
    } else {
        request
            .context
            .records
            .iter()
            .filter(|record| record.source == ContextSource::Instruction)
            .cloned()
            .collect()
    };
    // Keep the same immediate execution proof and delegated-input policy. Inventories are
    // rebuilt below, even if their old record happened to follow the last tool batch.
    let latest_batch = request.context.records.iter().rposition(|record| {
        record.source == ContextSource::Assistant
            && record.turn_id.as_deref() == Some(request.turn_id.as_str())
            && !record.tool_calls.is_empty()
    });
    let active = request.context.records.iter().enumerate().filter(|(index, record)| {
        !is_inventory(record) && (
            (record.source == ContextSource::User && record.turn_id.as_deref() == Some(request.turn_id.as_str()))
            || matches!(&record.source, ContextSource::AgentMessage { purpose, .. } if *purpose != pl_core::context::AgentMessageKind::Report)
            || (latest_batch.is_some_and(|start| *index >= start) && !matches!(record.source, ContextSource::Instruction | ContextSource::InstructionSnapshot { .. } | ContextSource::RuntimeFact { .. }))
        )
    }).map(|(_, record)| record).cloned().collect::<Vec<_>>();
    let mut carried = HashSet::new();
    for attachment in user_files(&active)? {
        carried.insert(identity(&attachment));
    }
    let mut content = Vec::new();
    for attachment in user_files(&request.context.records)? {
        if !carried.insert(identity(&attachment)) {
            continue;
        }
        let Attachment::UserFile {
            reference,
            modality,
            filename,
        } = attachment
        else {
            continue;
        };
        content.push(attachment::user_attachment_content(
            reference, modality, filename,
        )?);
    }
    let inventory = (!content.is_empty()).then(|| ContextRecord {
        id: format!("compaction-user-files:{}", request.attempt_id),
        turn_id: None,
        source: ContextSource::Runtime {
            source_id: USER_FILES.into(),
        },
        content,
        tool_calls: Vec::new(),
    });
    Ok(RetainedContext {
        instructions,
        inventory,
        active,
    })
}

fn is_inventory(record: &ContextRecord) -> bool {
    matches!(&record.source, ContextSource::Runtime { source_id } if source_id == USER_FILES)
}

fn user_files(records: &[ContextRecord]) -> Result<Vec<Attachment>, ModelError> {
    let mut files = Vec::new();
    for record in records {
        let inventory = is_inventory(record);
        if inventory && (record.turn_id.is_some() || !record.tool_calls.is_empty()) {
            return Err(invalid("invalid user file inventory envelope"));
        }
        for content in &record.content {
            let ContextContent::Opaque { payload } = content else {
                if inventory {
                    return Err(invalid("user file inventory requires typed attachments"));
                }
                continue;
            };
            if payload.format() != attachment::FORMAT {
                if inventory {
                    return Err(invalid("unknown user file inventory content"));
                }
                continue;
            }
            let attachment = attachment::decode(payload, Some(&record.source))?;
            if matches!(attachment, Attachment::UserFile { .. }) {
                files.push(attachment);
            } else if inventory {
                return Err(invalid("native tool media cannot be a user file inventory"));
            }
        }
    }
    Ok(files)
}

fn identity(
    attachment: &Attachment,
) -> (
    String,
    crate::completion::AttachmentModality,
    Option<String>,
) {
    // Common encoding still validates the complete, unchanged input and rejects conflicting
    // metadata for an ID before provider IO. An admitted ID therefore identifies one original.
    (
        attachment.reference().id().to_owned(),
        attachment.modality(),
        attachment.filename().map(str::to_owned),
    )
}
