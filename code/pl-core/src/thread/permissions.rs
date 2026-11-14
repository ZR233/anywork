//! Typed execution decisions bound to a live tool call; business prompts remain opaque.
use super::*;

/// Explicit host decision, never derived from business payload fields.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionDecision {
    Allow,
    Deny,
}

/// Saved permission state. A historical Allow is not a reusable executor capability.
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum PermissionState {
    Pending,
    Allowed,
    Denied,
    Cancelled,
}

/// Original approval prompt and its exact framework association.
#[derive(Debug, Clone, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct PermissionRecord {
    pub created_at: i64,
    pub updated_at: i64,
    pub response: Option<OpaquePayload>,
    pub id: String,
    pub task_id: String,
    pub call_id: String,
    pub turn_id: String,
    pub tool_id: String,
    pub revision: u64,
    pub payload: OpaquePayload,
    pub state: PermissionState,
}

/// Revision-checked decision supplied through a trusted host command.
#[derive(Debug, Clone)]
pub struct PermissionResolution {
    pub id: String,
    pub expected_revision: u64,
    pub decision: PermissionDecision,
    pub payload: Option<OpaquePayload>,
}

impl Owner {
    pub(super) fn request_execution_permission(
        &mut self,
        caller: String,
        authority: crate::tool::opaque::ExecutionAuthority,
        payload: OpaquePayload,
    ) -> Result<PermissionRecord, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        let task = self
            .state
            .tasks
            .get(&caller)
            .ok_or(ThreadError::InvalidIdentity)?;
        if task.status != task::TaskStatus::Running
            || task.cancel_requested
            || self
                .executions
                .token(&caller)
                .is_none_or(|token| token.is_cancelled())
        {
            return Err(ThreadError::TaskAccessExpired);
        }
        if !authority.remains_authorized(&self.tools) {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        let id = format!("permission:{}", task.call_id);
        if let Some(previous) = self.state.permissions.get(&id) {
            return if previous.payload == payload && self.permission_leases.contains_key(&id) {
                Ok(previous.clone())
            } else {
                Err(ThreadError::InvalidIdentity)
            };
        }
        // The call already settled its permission identity when any committed permission record for
        // this call is still inside the bounded live effect window; a second prompt for the same call
        // must not mint a fresh pending revision or a new execution lease.
        if recent_effect_fact(&self.effect_window, |effect| {
            effect
                .permissions
                .iter()
                .rev()
                .find(|record| record.id == id)
                .cloned()
        })
        .is_some()
        {
            return Err(ThreadError::InvalidIdentity);
        }
        let now = crate::time::unix_seconds();
        let record = PermissionRecord {
            created_at: now,
            updated_at: now,
            response: None,
            id: id.clone(),
            task_id: caller,
            call_id: task.call_id.clone(),
            turn_id: task.turn_id.clone(),
            tool_id: task.tool_id.clone(),
            revision: 1,
            payload,
            state: PermissionState::Pending,
        };
        let mut permissions = self.state.permissions.clone();
        permissions.insert(id.clone(), record.clone());
        self.state.interaction_collection_revision_for(
            &self.published,
            &self.state.interactions,
            &permissions,
        )?;
        self.permission_leases.insert(id, authority);
        record_change(&mut self.state, record.clone());
        self.publish()?;
        Ok(record)
    }

    pub(super) fn resolve_execution_permission(
        &mut self,
        resolution: PermissionResolution,
    ) -> Result<PermissionRecord, ThreadError> {
        if self.state.lifecycle != ThreadLifecycle::Open || self.interrupt.is_closing() {
            return Err(ThreadError::Closed);
        }
        let state = match resolution.decision {
            PermissionDecision::Allow => PermissionState::Allowed,
            PermissionDecision::Deny => PermissionState::Denied,
        };
        let live = self.state.permissions.get(&resolution.id).cloned();
        let settled = live.is_none();
        let previous = match live {
            Some(previous) => previous,
            None => recent_effect_fact(&self.effect_window, |effect| {
                effect
                    .permissions
                    .iter()
                    .rev()
                    .find(|record| record.id == resolution.id)
                    .cloned()
            })
            .ok_or(ThreadError::InvalidIdentity)?,
        };
        if previous.state == state
            && previous.response == resolution.payload
            && resolution.expected_revision.checked_add(1) == Some(previous.revision)
        {
            return Ok(previous.clone());
        }
        if settled {
            // A settled permission only ever replays the decision recorded in its receipt; it no
            // longer owns a lease, so a differing retry can never grant new execution.
            return Err(ThreadError::InvalidIdentity);
        }
        let authority = self
            .permission_leases
            .get(&resolution.id)
            .ok_or(ThreadError::ToolPermissionRevoked)?;
        if !authority.remains_authorized(&self.tools) {
            return Err(ThreadError::ToolPermissionRevoked);
        }
        let task = self
            .state
            .tasks
            .get(&previous.task_id)
            .ok_or(ThreadError::InvalidIdentity)?;
        if task.status != task::TaskStatus::Running
            || task.cancel_requested
            || self
                .executions
                .token(&previous.task_id)
                .is_none_or(|token| token.is_cancelled())
        {
            return Err(ThreadError::TaskAccessExpired);
        }
        if previous.state != PermissionState::Pending
            || previous.revision != resolution.expected_revision
        {
            return Err(ThreadError::InvalidIdentity);
        }
        let mut record = previous.clone();
        record.revision = record
            .revision
            .checked_add(1)
            .ok_or(ThreadError::RevisionExhausted)?;
        record.state = state;
        record.response = resolution.payload;
        record.updated_at = crate::time::unix_seconds();
        let mut permissions = self.state.permissions.clone();
        permissions.insert(record.id.clone(), record.clone());
        self.state.interaction_collection_revision_for(
            &self.published,
            &self.state.interactions,
            &permissions,
        )?;
        record_change(&mut self.state, record.clone());
        self.publish()?;
        Ok(record)
    }

    pub(super) fn revoke_stale_permissions(&mut self) -> Result<(), ThreadError> {
        let stale = self
            .permission_leases
            .iter()
            .filter(|(_, authority)| !authority.remains_authorized(&self.tools))
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        let mut permissions = self.state.permissions.clone();
        let mut changes = Vec::new();
        for id in &stale {
            if let Some(previous) = permissions.get(id)
                && let Some(record) = cancelled_record(previous)?
            {
                permissions.insert(id.clone(), record.clone());
                changes.push(record);
            }
        }
        self.state.interaction_collection_revision_for(
            &self.published,
            &self.state.interactions,
            &permissions,
        )?;
        for record in changes {
            record_change(&mut self.state, record);
        }
        for id in stale {
            self.permission_leases.remove(&id);
        }
        Ok(())
    }

    pub(super) fn settle_execution_permission(&mut self, call_id: &str) -> Result<(), ThreadError> {
        let id = format!("permission:{call_id}");
        cancel_pending(&mut self.state, &id)?;
        Ok(())
    }
}

pub(super) fn cancel_pending(state: &mut ThreadSnapshot, id: &str) -> Result<(), ThreadError> {
    if let Some(previous) = state.permissions.get(id)
        && let Some(record) = cancelled_record(previous)?
    {
        record_change(state, record);
    }
    Ok(())
}

fn cancelled_record(previous: &PermissionRecord) -> Result<Option<PermissionRecord>, ThreadError> {
    if previous.state != PermissionState::Pending {
        return Ok(None);
    }
    let mut record = previous.clone();
    record.revision = record
        .revision
        .checked_add(1)
        .ok_or(ThreadError::RevisionExhausted)?;
    record.state = PermissionState::Cancelled;
    record.updated_at = crate::time::unix_seconds();
    Ok(Some(record))
}

fn record_change(state: &mut ThreadSnapshot, record: PermissionRecord) {
    state.permissions.insert(record.id.clone(), record.clone());
    let mut changes = state.permission_changes.to_vec();
    changes.push(record);
    state.permission_changes = changes.into();
}
