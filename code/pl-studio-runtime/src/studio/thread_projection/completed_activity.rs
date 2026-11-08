//! The sole mapping between real activity identities and immutable completions.
use pl_protocol::{ActivityIdentity, ChatAtom, ChatAtomKind, ChatDeliveryKind, ChatSourceId};
#[cfg(test)]
use pl_protocol::{ChatAtomLifecycle, CompletedEntry};

pub(in crate::studio) fn activity_identity(atom: &ChatAtom) -> Option<ActivityIdentity> {
    match atom.kind {
        ChatAtomKind::Text | ChatAtomKind::Reasoning if atom.attempt_id.is_some() => {
            Some(ActivityIdentity::ModelPart {
                atom_id: atom.id.clone(),
            })
        }
        ChatAtomKind::ToolCall
        | ChatAtomKind::Plan
        | ChatAtomKind::Interaction
        | ChatAtomKind::FileChange
        | ChatAtomKind::Skill => {
            let call_id = atom.tool.as_ref()?.call_id.clone();
            Some(
                if matches!(atom.source, ChatSourceId::BackgroundResult { .. }) {
                    ActivityIdentity::BackgroundTool { call_id }
                } else if atom.delivery != ChatDeliveryKind::Independent {
                    ActivityIdentity::ForegroundTool { call_id }
                } else {
                    return None;
                },
            )
        }
        ChatAtomKind::Compaction => match &atom.source {
            ChatSourceId::Operation { operation_id } => Some(ActivityIdentity::Other {
                domain: "operation".into(),
                id: operation_id.clone(),
            }),
            _ => None,
        },
        _ => None,
    }
}

#[cfg(test)]
pub(in crate::studio) fn completed_activity_identity(
    entry: &CompletedEntry,
) -> Option<ActivityIdentity> {
    if !matches!(entry.atom.lifecycle, ChatAtomLifecycle::Terminal { .. }) {
        return None;
    }
    activity_identity(&entry.atom)
}
