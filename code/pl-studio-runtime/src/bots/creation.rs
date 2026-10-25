//! Typed classification of one failed bot Thread creation attempt.
//!
//! A frozen creation identity either still has a durable future (a bounded retry) or it can
//! never be bound because the Thread that identity already owns is archived or belongs to
//! another Project. The decision uses typed state only: error text never participates, and
//! the caller never picks a new creation identity to work around a conflict.
//!
//! Every attempt that stays retryable is still bounded: the durable intent ends in a visible
//! terminal state once the retry budget is exhausted, so "retryable" never means "forever".

/// Typed facts about the Project the frozen creation identity must be created in.
///
/// The canonical Project snapshot is the same fact `create_thread_with_id` reads, but absence
/// from it is **not** proof of a deterministic failure: the snapshot is fed by directory
/// events, so a Project that was just added (or whose directory reload is still in flight)
/// can be missing for a moment. Absence therefore keeps the bounded retry, and the exhausted
/// budget owns the terminal state.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum TargetProject {
    /// The Project is in the canonical snapshot, so creation may still succeed.
    Present,
    /// The Project is not in the canonical snapshot right now. Only a retryable fact: the
    /// snapshot may simply lag behind the Project directory.
    Absent,
}

/// Typed facts about the Thread that the frozen creation identity already owns.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum CreatedThreadState {
    /// Nothing with this identity is owned, so nothing usable was created.
    Absent,
    /// The identity owns an active Thread in the frozen project.
    Usable,
    /// The identity owns a Thread that can never be bound again.
    Archived,
    /// The identity is bound to a different project.
    OtherProject,
}

/// What one failed creation attempt means for the durable binding intent.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(in crate::bots) enum CreationFailure {
    /// Deterministic for this identity: collapse to a visible needs-attention state once.
    IdentityConflict,
    /// Not a proven conflict: keep the durable intent and the existing bounded retry.
    Retryable,
}

/// Only typed state decides. An unnotarizable case stays retryable, so ambiguity never
/// destroys a durable intent; the exhausted retry budget provides the terminal state.
pub(in crate::bots) fn classify_creation_failure(
    project: TargetProject,
    thread: CreatedThreadState,
) -> CreationFailure {
    match (project, thread) {
        // 项目缺席可能只是 canonical 快照尚未追上目录（刚 add 项目后立刻发消息就是这种
        // 情形），不足以断定身份冲突：保留耐久意图与有界退避，终局由预算耗尽兜底。
        (TargetProject::Absent, _) => CreationFailure::Retryable,
        (
            TargetProject::Present,
            CreatedThreadState::Archived | CreatedThreadState::OtherProject,
        ) => CreationFailure::IdentityConflict,
        (TargetProject::Present, CreatedThreadState::Absent | CreatedThreadState::Usable) => {
            CreationFailure::Retryable
        }
    }
}

/// Typed projection of the canonical Project snapshot; the only glue over studio fields.
pub(in crate::bots) fn target_project_state(
    projects: &[crate::studio::ProjectRecord],
    project_id: &str,
) -> TargetProject {
    // 空快照无法区分「目录尚未加载」与「确实没有项目」，不能据此证明缺席：
    // 保守按存在处理，让有界退避与预算兜底承担这种情况。
    if projects.is_empty() {
        return TargetProject::Present;
    }
    if project_id.is_empty() || !projects.iter().any(|project| project.id == project_id) {
        return TargetProject::Absent;
    }
    TargetProject::Present
}

/// Typed projection of the runtime's record; the only glue over studio fields.
pub(in crate::bots) fn created_thread_state(
    record: Option<&crate::studio::ThreadRecord>,
    project_id: &str,
) -> CreatedThreadState {
    match record {
        None => CreatedThreadState::Absent,
        Some(record) if record.project_id != project_id => CreatedThreadState::OtherProject,
        Some(record) if record.visibility != crate::studio::ThreadVisibility::Active => {
            CreatedThreadState::Archived
        }
        Some(_) => CreatedThreadState::Usable,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// 分类只由 typed 事实决定：同一 identity 已存在但不可绑定的 Thread 才是不可辩驳
    /// 的身份冲突；项目缺席可能只是 canonical 快照滞后，绝不能因此收束耐久意图。
    #[test]
    fn creation_failure_classification_uses_only_typed_facts() {
        assert_eq!(
            classify_creation_failure(TargetProject::Present, CreatedThreadState::Archived),
            CreationFailure::IdentityConflict
        );
        assert_eq!(
            classify_creation_failure(TargetProject::Present, CreatedThreadState::OtherProject),
            CreationFailure::IdentityConflict
        );
        assert_eq!(
            classify_creation_failure(TargetProject::Present, CreatedThreadState::Absent),
            CreationFailure::Retryable,
            "nothing usable was created, so the durable intent must stay retryable"
        );
        assert_eq!(
            classify_creation_failure(TargetProject::Present, CreatedThreadState::Usable),
            CreationFailure::Retryable,
            "an unusable-with-usable ambiguity must never destroy a durable intent"
        );
        // 项目缺席不是身份冲突证据：canonical 快照由目录事件喂入，刚 add 项目后立刻
        // 发消息时它可能还没追上。缺席一律保留有界退避，终局由预算耗尽兜底，因此这里
        // 连“已存在但不可用”的 Thread 证据也不单独收束。
        for thread in [
            CreatedThreadState::Absent,
            CreatedThreadState::Usable,
            CreatedThreadState::Archived,
            CreatedThreadState::OtherProject,
        ] {
            assert_eq!(
                classify_creation_failure(TargetProject::Absent, thread),
                CreationFailure::Retryable,
                "a lagging Project snapshot must never collapse the creation intent"
            );
        }
    }

    /// 项目事实只认 canonical 快照的精确 id：不做前缀、名称、空字段或空快照近似。
    #[test]
    fn target_project_state_requires_an_exact_snapshot_entry() {
        let projects = vec![crate::studio::ProjectRecord {
            id: "project".to_string(),
            name: "project".to_string(),
            path: "/tmp/project".to_string(),
            ssh_alias: None,
            updated_at: 1,
        }];
        assert_eq!(
            target_project_state(&projects, "project"),
            TargetProject::Present
        );
        assert_eq!(
            target_project_state(&projects, "project-other"),
            TargetProject::Absent
        );
        assert_eq!(
            target_project_state(&projects, "proj"),
            TargetProject::Absent
        );
        assert_eq!(target_project_state(&projects, ""), TargetProject::Absent);
        assert_eq!(
            target_project_state(&[], "project"),
            TargetProject::Present,
            "an empty snapshot cannot prove absence (the directory may not be loaded yet), \
             so the bounded retry keeps owning that case"
        );
    }
}
