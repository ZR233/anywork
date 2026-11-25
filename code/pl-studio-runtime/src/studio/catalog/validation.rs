//! Validate runtime directory identities, backend ownership and parent topology.

use std::collections::{HashMap, HashSet};

use anyhow::{Context, Result, ensure};

use super::CatalogDocument;
use crate::{AgentBackend, ThreadWorkspaceMode};

pub(super) fn validate(document: &CatalogDocument) -> Result<()> {
    ensure!(document.revision >= 1, "Studio catalog revision is invalid");
    let mut sessions = HashMap::with_capacity(document.sessions.len());
    for session in &document.sessions {
        ensure!(
            sessions
                .insert(session.session_id.as_str(), session)
                .is_none(),
            "Studio catalog has a duplicate session identity"
        );
        ensure!(
            !session.session_id.trim().is_empty() && !session.root_agent_id.trim().is_empty(),
            "Studio catalog session identity is incomplete"
        );
        ensure!(
            session.workspace_mode != ThreadWorkspaceMode::Worktree
                || !session.workspace_path.is_empty(),
            "Studio worktree catalog session has no workspace address"
        );
    }

    let mut agents = HashMap::with_capacity(document.agents.len());
    let mut threads = HashSet::with_capacity(document.agents.len());
    for (index, agent) in document.agents.iter().enumerate() {
        ensure!(
            !agent.agent_id.trim().is_empty() && !agent.thread_id.trim().is_empty(),
            "Studio catalog member identity is incomplete"
        );
        match &agent.backend {
            AgentBackend::Native { config, .. } => ensure!(
                config.system_instructions.is_none(),
                "Studio catalog cannot contain Native instruction bodies"
            ),
            AgentBackend::Acp { reference } => ensure!(
                !reference.account_id.trim().is_empty()
                    && !reference.acp_session_id.trim().is_empty()
                    && !reference.cwd.trim().is_empty(),
                "Studio catalog ACP reference is incomplete"
            ),
        }
        ensure!(
            agents.insert(agent.agent_id.as_str(), index).is_none(),
            "Studio catalog has a duplicate agent identity"
        );
        ensure!(
            threads.insert(agent.thread_id.as_str()),
            "Studio catalog agent identities do not map one-to-one to default threads"
        );
        ensure!(
            sessions.contains_key(agent.session_id.as_str()),
            "Studio catalog agent {} references a missing session",
            agent.agent_id
        );
    }

    for session in &document.sessions {
        let root = agents
            .get(session.root_agent_id.as_str())
            .map(|&index| &document.agents[index])
            .filter(|root| root.session_id == session.session_id && root.parent_agent_id.is_none())
            .with_context(|| {
                format!(
                    "Studio catalog session {} has no root member",
                    session.session_id
                )
            })?;
        ensure!(
            session.native_mode.is_some() == matches!(root.backend, AgentBackend::Native { .. }),
            "Studio catalog root Native mode does not match its backend"
        );
        ensure!(
            session.acp_title.is_some() == matches!(root.backend, AgentBackend::Acp { .. }),
            "Studio catalog ACP title does not match its root backend"
        );
    }

    let mut parents = Vec::with_capacity(document.agents.len());
    for agent in &document.agents {
        let parent = if let Some(parent_id) = &agent.parent_agent_id {
            let parent = agents
                .get(parent_id.as_str())
                .copied()
                .filter(|&index| document.agents[index].session_id == agent.session_id);
            ensure!(
                parent.is_some(),
                "Studio catalog agent {} has a parent outside its session",
                agent.agent_id
            );
            parent
        } else {
            let session = sessions[agent.session_id.as_str()];
            ensure!(
                agent.agent_id == session.root_agent_id,
                "Studio catalog session {} has multiple root members",
                session.session_id
            );
            None
        };
        parents.push(parent);
    }

    // Each edge is traversed at most once. Revisiting an active member means the current
    // chain contains a cycle; revisiting a verified member reuses its path to the root.
    #[derive(Clone, Copy)]
    enum Visit {
        Unseen,
        Active,
        Verified,
    }
    let mut visits = vec![Visit::Unseen; parents.len()];
    let mut path = Vec::new();
    for (start, agent) in document.agents.iter().enumerate() {
        let mut cursor = Some(start);
        while let Some(index) = cursor {
            match visits[index] {
                Visit::Verified => break,
                Visit::Active => anyhow::bail!(
                    "Studio catalog member chain from {} is cyclic",
                    agent.agent_id
                ),
                Visit::Unseen => {
                    visits[index] = Visit::Active;
                    path.push(index);
                    cursor = parents[index];
                }
            }
        }
        for index in path.drain(..) {
            visits[index] = Visit::Verified;
        }
    }
    Ok(())
}
