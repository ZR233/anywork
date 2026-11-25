//! ACP 根标题的来源优先级与权威目录提交。

use super::*;

fn active_acp_member<'a>(
    index: &'a ThreadDirectoryIndex,
    thread_id: &str,
    reference: &crate::AcpSessionReference,
) -> Option<(&'a SessionDirectoryRecord, &'a AgentDirectoryRecord)> {
    let (session, agent) = index.directory_facts(thread_id)?;
    (!session.archived
        && !agent.explicitly_closed
        && matches!(&agent.backend, crate::AgentBackend::Acp { reference: actual } if actual == reference))
        .then_some((session, agent))
}

impl ProductEventBus {
    /// An accepted input is already a fact. Update the directory and enqueue its
    /// persistence together, so a write failure cannot re-arm the first-input label.
    pub(in crate::studio) async fn record_acp_first_input_title(
        &self,
        thread_id: &str,
        reference: &crate::AcpSessionReference,
        title: String,
    ) {
        self.observe_acp_root_title(thread_id, reference, |session, metadata| {
            if metadata.label != AcpTitleLabel::AwaitingInput {
                return false;
            }
            metadata.label = AcpTitleLabel::Fallback;
            session.title = title;
            true
        })
        .await;
    }

    pub(in crate::studio) async fn record_acp_pushed_title(
        &self,
        thread_id: &str,
        reference: &crate::AcpSessionReference,
        peer: AcpPeerTitle,
    ) {
        self.observe_acp_root_title(thread_id, reference, |_, metadata| {
            if metadata.peer.as_ref() == Some(&peer) {
                return false;
            }
            metadata.peer = Some(peer);
            true
        })
        .await;
    }

    pub(super) async fn observe_acp_root_title(
        &self,
        thread_id: &str,
        reference: &crate::AcpSessionReference,
        apply: impl FnOnce(&mut SessionDirectoryRecord, &mut AcpDirectoryTitle) -> bool,
    ) {
        let _command = self.directory_commands.lock().await;
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let Some((session, agent)) = active_acp_member(&index, thread_id, reference) else {
            return;
        };
        if !agent.is_root_agent() {
            return;
        }
        let mut session = session.clone();
        let Some(mut metadata) = session.acp_title.take() else {
            return;
        };
        if apply(&mut session, &mut metadata) {
            session.acp_title = Some(metadata);
            self.publish_acp_title_facts(&mut index, vec![session]);
        }
    }

    /// An explicit external-list page only supplies titles to already-associated roots.
    /// It can neither create membership nor outrank a push, even a push that cleared it.
    pub(in crate::studio) async fn record_acp_list_titles(
        &self,
        source_thread_id: &str,
        source: &crate::AcpSessionReference,
        listed: &[crate::acp_schema::SessionInfo],
    ) {
        let titles: HashMap<_, _> = listed
            .iter()
            .filter_map(|item| {
                let title = item.title.as_deref()?.trim();
                (item.cwd.to_str() == Some(source.cwd.as_str()) && !title.is_empty())
                    .then_some((item.session_id.0.as_ref(), title))
            })
            .collect();
        if titles.is_empty() {
            return;
        }
        let _command = self.directory_commands.lock().await;
        let mut index = self
            .thread_index
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if active_acp_member(&index, source_thread_id, source).is_none() {
            return;
        }
        let sessions = index
            .sessions
            .values()
            .filter_map(|entry| {
                let root = entry.root_agent()?;
                let crate::AgentBackend::Acp { reference } = &root.backend else {
                    return None;
                };
                if entry.session.archived
                    || root.explicitly_closed
                    || reference.account_id != source.account_id
                    || reference.cwd != source.cwd
                {
                    return None;
                }
                let title = *titles.get(reference.acp_session_id.as_str())?;
                let metadata = entry.session.acp_title.as_ref()?;
                match &metadata.peer {
                    Some(AcpPeerTitle::Pushed { .. }) => return None,
                    Some(AcpPeerTitle::Listed { title: previous }) if previous == title => {
                        return None;
                    }
                    _ => {}
                }
                let mut session = entry.session.clone();
                session.acp_title.as_mut()?.peer = Some(AcpPeerTitle::Listed {
                    title: title.to_owned(),
                });
                Some(session)
            })
            .collect::<Vec<_>>();
        self.publish_acp_title_facts(&mut index, sessions);
    }

    /// Publish the same directory rows as other observed facts; a hidden title
    /// update still persists but doesn't advance the visible directory revision.
    pub(super) fn publish_acp_title_facts(
        &self,
        index: &mut ThreadDirectoryIndex,
        sessions: Vec<SessionDirectoryRecord>,
    ) {
        if sessions.is_empty() {
            return;
        }
        let mut rows = Vec::new();
        for session in &sessions {
            if let Some(previous) = index.get_session(&session.session_id)
                && previous.display_title() != session.display_title()
            {
                rows.extend(
                    index
                        .agents_of(&session.session_id)
                        .into_iter()
                        .filter(|agent| agent.title.is_none())
                        .map(|agent| row_projection(session, &agent)),
                );
            }
        }
        let before_agents = (!rows.is_empty())
            .then(|| index.agent_directory_members(rows.iter().map(|row| row.agent_id.clone())));
        for session in &sessions {
            index.insert_session(session.clone());
        }
        self.writer.record_directory(DirectoryDelta {
            session_upserts: sessions,
            ..Default::default()
        });
        if let Some(before_agents) = before_agents {
            self.publish_agent_directory_locked(index, before_agents);
            self.emit_thread_delta_locked(index, rows, Vec::new());
        }
    }

    pub(in crate::studio) async fn rename_acp_root_title(
        &self,
        thread_id: &str,
        title: String,
    ) -> Result<(StudioProductEventEnvelope, bool)> {
        let _command = self.directory_commands.lock().await;
        let (mut session, agent) = self
            .directory_facts(thread_id)
            .context("ACP session is missing")?;
        anyhow::ensure!(
            agent.is_root_agent()
                && !session.archived
                && matches!(&agent.backend, crate::AgentBackend::Acp { .. }),
            "ACP root cannot be renamed"
        );
        let metadata = session
            .acp_title
            .as_mut()
            .context("ACP title metadata is missing")?;
        let changed = session.title != title || metadata.label != AcpTitleLabel::Alias;
        metadata.label = AcpTitleLabel::Alias;
        session.title = title;
        session.updated_at = crate::studio::unix_seconds();
        let event = self
            .commit_directory_locked(
                DirectoryDelta {
                    session_upserts: vec![session],
                    ..Default::default()
                },
                DirectoryBaselines::default(),
            )
            .await?;
        Ok((event, changed))
    }
}
