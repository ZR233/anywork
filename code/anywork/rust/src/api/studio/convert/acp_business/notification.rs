use super::*;
use json::opt_meta;

pub(super) fn notification(v: s::SessionNotification) -> R<BridgeAcpSessionNotification> {
    Ok(BridgeAcpSessionNotification {
        session_id: BridgeAcpRemoteSessionId {
            value: v.session_id.to_string(),
        },
        update: update(v.update)?,
        meta: opt_meta(v.meta)?,
    })
}
fn chunk(v: s::ContentChunk) -> R<BridgeAcpContentChunk> {
    Ok(BridgeAcpContentChunk {
        content: content(v.content)?,
        message_id: v.message_id.map(|v| v.to_string()),
        meta: opt_meta(v.meta)?,
    })
}
fn string_field<T: ToString>(v: Option<Option<&T>>) -> BridgeAcpStringField {
    match v {
        None => BridgeAcpStringField::Undefined,
        Some(None) => BridgeAcpStringField::Null,
        Some(Some(v)) => BridgeAcpStringField::Value {
            value: v.to_string(),
        },
    }
}
fn content_field(v: Option<Option<&Vec<s::ContentBlock>>>) -> R<BridgeAcpContentField> {
    Ok(match v {
        None => BridgeAcpContentField::Undefined,
        Some(None) => BridgeAcpContentField::Null,
        Some(Some(v)) => BridgeAcpContentField::Value {
            value: many(v.clone(), content)?,
        },
    })
}
fn meta_field(v: Option<Option<&s::Meta>>) -> R<BridgeAcpMetaField> {
    Ok(match v {
        None => BridgeAcpMetaField::Undefined,
        Some(None) => BridgeAcpMetaField::Null,
        Some(Some(v)) => BridgeAcpMetaField::Value {
            value: json::meta(v.clone())?,
        },
    })
}
fn update(v: s::SessionUpdate) -> R<BridgeAcpSessionUpdate> {
    Ok(match v {
        s::SessionUpdate::UserMessageChunk(v) => {
            BridgeAcpSessionUpdate::UserMessageChunk { chunk: chunk(v)? }
        }
        s::SessionUpdate::AgentMessageChunk(v) => {
            BridgeAcpSessionUpdate::AgentMessageChunk { chunk: chunk(v)? }
        }
        s::SessionUpdate::AgentThoughtChunk(v) => {
            BridgeAcpSessionUpdate::AgentThoughtChunk { chunk: chunk(v)? }
        }
        s::SessionUpdate::ToolCall(v) => BridgeAcpSessionUpdate::ToolCall {
            call: tool_call(v)?,
        },
        s::SessionUpdate::ToolCallUpdate(v) => BridgeAcpSessionUpdate::ToolCallUpdate {
            update: tool_update(v)?,
        },
        s::SessionUpdate::Plan(v) => BridgeAcpSessionUpdate::Plan {
            entries: many(v.entries, plan_entry)?,
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::AvailableCommandsUpdate(v) => BridgeAcpSessionUpdate::AvailableCommands {
            commands: many(v.available_commands, |v| {
                Ok(BridgeAcpAvailableCommand {
                    name: v.name,
                    description: v.description,
                    input: v
                        .input
                        .map(|v| {
                            Ok(match v {
                                s::AvailableCommandInput::Unstructured(v) => {
                                    BridgeAcpCommandInput {
                                        hint: v.hint,
                                        meta: opt_meta(v.meta)?,
                                    }
                                }
                                _ => return Err(unsupported("AvailableCommandInput")),
                            })
                        })
                        .transpose()?,
                    meta: opt_meta(v.meta)?,
                })
            })?,
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::CurrentModeUpdate(v) => BridgeAcpSessionUpdate::CurrentMode {
            mode_id: BridgeAcpModeId {
                value: v.current_mode_id.to_string(),
            },
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::ConfigOptionUpdate(v) => BridgeAcpSessionUpdate::ConfigOptions {
            config_options: many(v.config_options, config::config)?,
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::SessionInfoUpdate(v) => BridgeAcpSessionUpdate::SessionInfo {
            title: string_field(v.title.as_opt_ref()),
            updated_at: string_field(v.updated_at.as_opt_ref()),
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::UsageUpdate(v) => BridgeAcpSessionUpdate::Usage {
            used: v.used,
            size: v.size,
            cost: v
                .cost
                .map(|v| -> R<BridgeAcpCost> {
                    Ok(BridgeAcpCost {
                        amount: v.amount,
                        currency: v.currency,
                        meta: opt_meta(v.meta)?,
                    })
                })
                .transpose()?,
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::Notice(v) => BridgeAcpSessionUpdate::Notice {
            severity: match v.severity {
                s::NoticeSeverity::Info => BridgeAcpNoticeSeverity::Info,
                s::NoticeSeverity::Warning => BridgeAcpNoticeSeverity::Warning,
                s::NoticeSeverity::Error => BridgeAcpNoticeSeverity::Error,
                s::NoticeSeverity::Other(value) => BridgeAcpNoticeSeverity::Other { value },
                _ => return Err(unsupported("NoticeSeverity")),
            },
            title: v.title,
            description: v.description,
            meta: opt_meta(v.meta)?,
        },
        s::SessionUpdate::CompactionUpdate(v) => BridgeAcpSessionUpdate::Compaction {
            compaction_id: v.compaction_id.to_string(),
            status: match v.status {
                s::CompactionStatus::InProgress => BridgeAcpCompactionStatus::InProgress,
                s::CompactionStatus::Completed => BridgeAcpCompactionStatus::Completed,
                s::CompactionStatus::Failed => BridgeAcpCompactionStatus::Failed,
                s::CompactionStatus::Cancelled => BridgeAcpCompactionStatus::Cancelled,
                s::CompactionStatus::Other(value) => BridgeAcpCompactionStatus::Other { value },
                _ => return Err(unsupported("CompactionStatus")),
            },
            summary: content_field(v.summary.as_opt_ref())?,
            error: string_field(v.error.as_opt_ref()),
            meta: meta_field(v.meta.as_opt_ref())?,
        },
        s::SessionUpdate::CompactionSummaryChunk(v) => BridgeAcpSessionUpdate::CompactionSummary {
            compaction_id: v.compaction_id.to_string(),
            content: content(v.content)?,
            meta: opt_meta(v.meta)?,
        },
        _ => return Err(unsupported("SessionUpdate")),
    })
}
fn tool_kind(v: s::ToolKind) -> R<BridgeAcpToolKind> {
    Ok(match v {
        s::ToolKind::Read => BridgeAcpToolKind::Read,
        s::ToolKind::Edit => BridgeAcpToolKind::Edit,
        s::ToolKind::Delete => BridgeAcpToolKind::Delete,
        s::ToolKind::Move => BridgeAcpToolKind::Move,
        s::ToolKind::Search => BridgeAcpToolKind::Search,
        s::ToolKind::Execute => BridgeAcpToolKind::Execute,
        s::ToolKind::Think => BridgeAcpToolKind::Think,
        s::ToolKind::Fetch => BridgeAcpToolKind::Fetch,
        s::ToolKind::SwitchMode => BridgeAcpToolKind::SwitchMode,
        s::ToolKind::Other => BridgeAcpToolKind::Other,
        _ => return Err(unsupported("ToolKind")),
    })
}
fn tool_status(v: s::ToolCallStatus) -> R<BridgeAcpToolStatus> {
    Ok(match v {
        s::ToolCallStatus::Pending => BridgeAcpToolStatus::Pending,
        s::ToolCallStatus::InProgress => BridgeAcpToolStatus::InProgress,
        s::ToolCallStatus::Completed => BridgeAcpToolStatus::Completed,
        s::ToolCallStatus::Failed => BridgeAcpToolStatus::Failed,
        _ => return Err(unsupported("ToolCallStatus")),
    })
}
fn tool_content(v: s::ToolCallContent) -> R<BridgeAcpToolContent> {
    Ok(match v {
        s::ToolCallContent::Content(v) => BridgeAcpToolContent::Content {
            content: Box::new(content(v.content)?),
            meta: opt_meta(v.meta)?,
        },
        s::ToolCallContent::Diff(v) => BridgeAcpToolContent::Diff {
            path: path(v.path)?,
            old_text: v.old_text,
            new_text: v.new_text,
            meta: opt_meta(v.meta)?,
        },
        s::ToolCallContent::Terminal(v) => BridgeAcpToolContent::Terminal {
            terminal_id: v.terminal_id.to_string(),
            meta: opt_meta(v.meta)?,
        },
        _ => return Err(unsupported("ToolCallContent")),
    })
}
fn location(v: s::ToolCallLocation) -> R<BridgeAcpToolLocation> {
    Ok(BridgeAcpToolLocation {
        path: path(v.path)?,
        line: v.line,
        meta: opt_meta(v.meta)?,
    })
}
fn tool_call(v: s::ToolCall) -> R<BridgeAcpToolCall> {
    Ok(BridgeAcpToolCall {
        tool_call_id: v.tool_call_id.to_string(),
        title: v.title,
        name: v.name,
        kind: tool_kind(v.kind)?,
        status: tool_status(v.status)?,
        content: many(v.content, tool_content)?,
        locations: many(v.locations, location)?,
        raw_input: v.raw_input.map(json::json).transpose()?,
        raw_output: v.raw_output.map(json::json).transpose()?,
        meta: opt_meta(v.meta)?,
    })
}
fn tool_update(v: s::ToolCallUpdate) -> R<BridgeAcpToolCallUpdate> {
    let f = v.fields;
    Ok(BridgeAcpToolCallUpdate {
        tool_call_id: v.tool_call_id.to_string(),
        kind: f.kind.map(tool_kind).transpose()?,
        status: f.status.map(tool_status).transpose()?,
        title: f.title,
        name: f.name,
        content: f.content.map(|v| many(v, tool_content)).transpose()?,
        locations: f.locations.map(|v| many(v, location)).transpose()?,
        raw_input: f.raw_input.map(json::json).transpose()?,
        raw_output: f.raw_output.map(json::json).transpose()?,
        meta: opt_meta(v.meta)?,
    })
}
fn plan_entry(v: s::PlanEntry) -> R<BridgeAcpPlanEntry> {
    Ok(BridgeAcpPlanEntry {
        content: v.content,
        priority: match v.priority {
            s::PlanEntryPriority::High => BridgeAcpPlanPriority::High,
            s::PlanEntryPriority::Medium => BridgeAcpPlanPriority::Medium,
            s::PlanEntryPriority::Low => BridgeAcpPlanPriority::Low,
            _ => return Err(unsupported("PlanEntryPriority")),
        },
        status: match v.status {
            s::PlanEntryStatus::Pending => BridgeAcpPlanStatus::Pending,
            s::PlanEntryStatus::InProgress => BridgeAcpPlanStatus::InProgress,
            s::PlanEntryStatus::Completed => BridgeAcpPlanStatus::Completed,
            _ => return Err(unsupported("PlanEntryStatus")),
        },
        meta: opt_meta(v.meta)?,
    })
}
pub(super) fn permission(v: s::RequestPermissionRequest) -> R<BridgeAcpPermissionRequest> {
    Ok(BridgeAcpPermissionRequest {
        session_id: BridgeAcpRemoteSessionId {
            value: v.session_id.to_string(),
        },
        tool_call: tool_update(v.tool_call)?,
        options: many(v.options, |v| {
            Ok(BridgeAcpPermissionOption {
                option_id: BridgeAcpPermissionOptionId {
                    value: v.option_id.to_string(),
                },
                name: v.name,
                kind: match v.kind {
                    s::PermissionOptionKind::AllowOnce => BridgeAcpPermissionKind::AllowOnce,
                    s::PermissionOptionKind::AllowAlways => BridgeAcpPermissionKind::AllowAlways,
                    s::PermissionOptionKind::RejectOnce => BridgeAcpPermissionKind::RejectOnce,
                    s::PermissionOptionKind::RejectAlways => BridgeAcpPermissionKind::RejectAlways,
                    _ => return Err(unsupported("PermissionOptionKind")),
                },
                meta: opt_meta(v.meta)?,
            })
        })?,
        meta: opt_meta(v.meta)?,
    })
}
