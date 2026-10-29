//! One direct child at a time: real parent tool → receipt → child gate → real
//! parent wait → child terminal report. The same sequence resumes original IDs
//! after the production process and future Profile configuration have changed.
use super::{Observation, config, http, saved, wire};
use anyhow::{Context, Result, ensure};
use pl_protocol::{AgentProfileSnapshot, AgentWorkspaceMode, ThreadStatus, ThreadWaitState};
use pl_provider_fixture::agent_definitions::{AgentPhase, FUTURE_MODEL, ROOT_MODEL, USER_PROFILE};
use std::time::Instant;

impl Observation<'_> {
    pub(super) async fn delegate(
        &mut self,
        parent: &str,
        phase: AgentPhase,
        catalog: &wire::Catalog,
    ) -> Result<saved::SavedEvidence> {
        let profile_id = phase.profile().context("delegation Profile missing")?;
        let profile = catalog
            .profiles
            .iter()
            .find(|profile| profile.profile_id == profile_id)
            .context("delegation Profile not in real catalog")?;
        match phase {
            AgentPhase::SpawnSystem => ensure!(
                profile.system
                    && profile.profile_id == "explorer"
                    && profile.account_id == config::ROOT_ACCOUNT
                    && profile.model_id == ROOT_MODEL
                    && !config::has_explicit_system_route(&self.session.home, &profile.profile_id)?,
                "explorer catalog entry did not inherit the actual mode.simple route"
            ),
            AgentPhase::SpawnDefaultSystem => ensure!(
                profile.system
                    && profile.profile_id == "executor"
                    && profile.account_id == config::ROOT_ACCOUNT
                    && profile.model_id == FUTURE_MODEL
                    && !config::has_explicit_system_route(&self.session.home, &profile.profile_id)?,
                "executor catalog entry did not inherit the updated mode.simple route"
            ),
            _ => {}
        }
        let before = self.directory().await?;
        self.submit(parent, phase).await?;
        let child_phase = phase
            .child_phase()
            .context("delegation child phase missing")?;
        let gate = self.gate(child_phase).await?;
        self.wait_parent_wait(parent, phase).await?;
        let child = self.control.child_id(profile_id)?;
        let initial = self
            .saved(&child, &format!("child-{profile_id}-initial"))
            .await?;
        initial.assert_child(profile)?;
        let child_turn = self
            .assert_child_request(parent, &child, child_phase, profile, &initial)
            .await?;
        self.control
            .expect_child_turn(child_phase, &child, &child_turn)?;
        let workspace = initial
            .workspace
            .as_ref()
            .context("child workspace receipt missing")?;
        if profile_id == USER_PROFILE {
            ensure!(
                profile.system_instructions == config::OLD_ROLE
                    && workspace.mode == AgentWorkspaceMode::Directory,
                "synthetic user Profile was not the original directory Agent"
            );
            let root = std::path::Path::new(&workspace.root);
            let expected = vec![root.join("owned").to_string_lossy().into_owned()];
            ensure!(
                workspace.writable_paths.as_ref() == Some(&expected),
                "directory write policy was not frozen from spawn arguments"
            );
        } else {
            ensure!(
                workspace.mode == profile.workspace_mode && workspace.writable_paths.is_none(),
                "system child workspace changed"
            );
        }
        gate.release();
        self.wait_complete(parent, phase).await?;
        self.assert_child_completed(&child, &child_turn).await?;
        let requests = self.phase_requests(phase)?;
        wire::assert_delegation(&requests[2], phase, &child, &child_turn)?;
        wire::assert_schema(&requests[0], catalog)?;
        let mut expected = before;
        expected.push(child.clone());
        expected.sort();
        ensure!(
            self.directory().await? == expected,
            "spawn did not create exactly one direct child"
        );
        let complete = self
            .saved(&child, &format!("child-{profile_id}-complete"))
            .await?;
        ensure!(
            complete.instructions == initial.instructions
                && complete.profile == initial.profile
                && complete.workspace == initial.workspace,
            "child facts changed during its first Turn"
        );
        self.evidence.push(format!("actual spawn {profile_id} → {child}, parent={parent}; gated child request, canonical parent wait and original terminal report observed"));
        Ok(complete)
    }

    pub(super) async fn resume(
        &mut self,
        parent: &str,
        phase: AgentPhase,
        previous: &saved::SavedEvidence,
    ) -> Result<()> {
        let profile = previous
            .profile
            .as_ref()
            .context("original child Profile missing")?;
        let original = self.control.child_id(&profile.profile_id)?;
        ensure!(
            original == previous.thread_id,
            "resume target differs from original spawn"
        );
        let before = self.directory().await?;
        self.submit(parent, phase).await?;
        let child_phase = phase.child_phase().context("resume child phase missing")?;
        let gate = self.gate(child_phase).await?;
        self.wait_parent_wait(parent, phase).await?;
        let restored = self
            .saved(&original, &format!("child-{}-resumed", profile.profile_id))
            .await?;
        restored.assert_child(profile)?;
        ensure!(
            restored.profile == previous.profile
                && restored.instructions == previous.instructions
                && restored.workspace == previous.workspace,
            "original child was rebuilt from future configuration"
        );
        let child_turn = self
            .assert_child_request(parent, &original, child_phase, profile, &restored)
            .await?;
        self.control
            .expect_child_turn(child_phase, &original, &child_turn)?;
        gate.release();
        self.wait_complete(parent, phase).await?;
        self.assert_child_completed(&original, &child_turn).await?;
        let requests = self.phase_requests(phase)?;
        wire::assert_delegation(&requests[2], phase, &original, &child_turn)?;
        ensure!(
            self.directory().await? == before,
            "send_message cold recovery created a new child/grandchild"
        );
        self.evidence.push(format!("parent real send_message resumed original {original}; frozen Profile revision={}, model={}, workspace unchanged", profile.revision, profile.model_id));
        Ok(())
    }

    async fn assert_child_request(
        &self,
        parent: &str,
        child: &str,
        phase: AgentPhase,
        profile: &AgentProfileSnapshot,
        saved: &saved::SavedEvidence,
    ) -> Result<String> {
        let snapshot = self.session.http()?.read_thread(child).await?;
        let turn_id = snapshot
            .active_turn
            .as_ref()
            .context("gated child has no active Turn")?
            .id
            .clone();
        ensure!(
            snapshot.thread.parent_thread_id.as_deref() == Some(parent)
                && snapshot.thread.root_thread_id == parent
                && snapshot.thread.role == profile.profile_id,
            "child direct-parent/root/role association changed"
        );
        let route = snapshot
            .runtime
            .as_ref()
            .and_then(|runtime| runtime.model_route.as_ref())
            .context("child public route missing")?;
        ensure!(
            route.available
                && route.account_id == profile.account_id
                && route.model_id == profile.model_id
                && route.effort == profile.effort,
            "child public route differs from frozen Profile"
        );
        for request in self.phase_requests(phase)? {
            wire::assert_instructions(&request, &saved.instructions)?;
            ensure!(
                request.get("model").and_then(serde_json::Value::as_str)
                    == Some(profile.model_id.as_str()),
                "child actual provider route changed"
            );
            ensure!(
                wire::tool(&request, "spawn_agent")?.is_none(),
                "child has real spawn capability"
            );
            let tools = request
                .get("tools")
                .and_then(serde_json::Value::as_array)
                .context("child tools missing")?;
            ensure!(
                tools.iter().all(|tool| tool
                    .get("name")
                    .and_then(serde_json::Value::as_str)
                    .is_none_or(
                        |name| !name.starts_with("plan_") && !name.starts_with("workflow_")
                    )),
                "child acquired root Plan/workflow tools"
            );
        }
        Ok(turn_id)
    }

    async fn assert_child_completed(&self, child: &str, turn_id: &str) -> Result<()> {
        let page = self.session.http()?.read_timeline(child, 100).await?;
        ensure!(
            page.items.iter().any(|item| {
                item.header.turn_id.as_deref() == Some(turn_id)
                    && matches!(
                        &item.descriptor,
                        pl_protocol::TimelineDescriptor::Turn(turn)
                            if matches!(
                                &turn.outcome,
                                pl_protocol::TimelineTurnOutcome::Completed(_)
                            )
                    )
            }),
            "original child Turn {turn_id} did not complete successfully"
        );
        Ok(())
    }

    async fn wait_parent_wait(&self, parent: &str, phase: AgentPhase) -> Result<()> {
        let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
        let call_id = phase.wait_call();
        loop {
            let snapshot = self.session.http()?.read_thread(parent).await?;
            ensure!(
                snapshot.thread.status != ThreadStatus::Faulted,
                "parent failed before its real child wait"
            );
            let page = self.session.http()?.read_timeline(parent, 100).await?;
            if page
                .items
                .iter()
                .filter_map(|item| match &item.descriptor {
                    pl_protocol::TimelineDescriptor::Tool(tool) => Some(tool),
                    _ => None,
                })
                .any(|tool| {
                    tool.invocation.tool_call_id == call_id
                        && tool
                            .wait
                            .as_ref()
                            .is_some_and(|wait| wait.state() == ThreadWaitState::Waiting)
                })
            {
                return Ok(());
            }
            ensure!(
                Instant::now() < deadline,
                "parent wait {call_id} never became canonical before child release"
            );
            tokio::time::sleep(http::POLL).await;
        }
    }
}
