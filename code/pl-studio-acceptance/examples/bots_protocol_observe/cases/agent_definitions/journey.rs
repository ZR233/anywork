use super::{Observation, config, http, saved, sqlite, wire};
use anyhow::{Context, Result, bail, ensure};
use pl_protocol::studio::{
    AccountConnectionMode, AccountModelsPatch, AccountTextPatch, BotModelRoute, BotSecretUpdate,
    CreateThreadRequest, ModelConnectionIntent, NewThreadModelRoute, PatchAccountRequest,
    SaveBotRequest, SetAccountModelConnectionRequest, SetThreadModeRequest, SettingsFieldUpdate,
    StudioPromptInput, SubmitPromptRequest, UpdateSettingsFieldRequest,
};
use pl_protocol::{ThreadContentField, ThreadStatus, TimelineDescriptor, TurnState};
use pl_provider_fixture::{
    agent_definitions::{
        AgentPhase, CHILD_MODEL, COMPACT_MODEL, FUTURE_MODEL, ROOT_MODEL, USER_MODEL_NEW,
        USER_PROFILE,
    },
    feishu::{ChatType, DIRECT_CHAT_ID, SenderKind, TRUSTED_USER_OPEN_ID, text_event},
};
use std::time::Instant;

impl Observation<'_> {
    pub(super) async fn observe(&mut self) -> Result<()> {
        self.update_child_models(
            config::ChildAccountUpdate::InitializeCredential,
            "initialize-child-credential",
        )
        .await?;
        self.update_child_models(
            config::ChildAccountUpdate::ExecutableCatalog,
            "withdraw-unavailable-before-root-freeze",
        )
        .await?;
        let project = self
            .session
            .http()?
            .open_project(&self.session.project.to_string_lossy())
            .await?;
        let created = self
            .session
            .http()?
            .create_thread(
                &project.id,
                &CreateThreadRequest {
                    title: Some("Agent definition observation root".into()),
                    input: input(AgentPhase::MainFirst),
                    mode: "mode.simple".into(),
                    route: NewThreadModelRoute {
                        account_id: config::ROOT_ACCOUNT.into(),
                        model_id: ROOT_MODEL.into(),
                        effort: None,
                    },
                    delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                    delegation_preference: Some(pl_protocol::DelegationPreference::Balanced),
                    workspace_mode: pl_protocol::ThreadWorkspaceMode::Local,
                },
            )
            .await?;
        let main = created.thread.id;
        self.wait_complete(&main, AgentPhase::MainFirst).await?;
        self.set_base_override(
            "Synthetic config base override: CONFIG_BASE_MUST_NOT_REPLACE_AGENT.",
        )
        .await?;
        let (bot, bot_project) = self.session.ensure_trusted_direct().await?;
        ensure!(
            bot_project == project.id,
            "bot opened a different synthetic Project"
        );
        self.session.wait_connected(&bot).await?;
        self.ingress(&bot, AgentPhase::FeishuFirst).await?;
        let bindings = sqlite::thread_bindings(&self.session.home, &bot).await?;
        let direct = bindings
            .iter()
            .filter(|binding| binding.chat_id == DIRECT_CHAT_ID)
            .collect::<Vec<_>>();
        ensure!(direct.len() == 1, "Feishu root binding absent/duplicated");
        let feishu = direct[0].thread_id.clone();
        ensure!(main != feishu, "ordinary and Feishu roots were conflated");
        let main_first = self.saved(&main, "main-first").await?;
        let feishu_first = self.saved(&feishu, "feishu-first").await?;
        main_first.instructions.assert_root("root:main")?;
        feishu_first.instructions.assert_root("root:feishu")?;
        ensure!(
            main_first.instructions.base.source.kind == "modelBase"
                && main_first
                    .instructions
                    .base
                    .content
                    .contains("MODEL_BASE_MUST_NOT_REPLACE_AGENT"),
            "ordinary root did not retain its model-owned base source"
        );
        ensure!(
            feishu_first.instructions.base.source.kind == "configBaseOverride"
                && feishu_first
                    .instructions
                    .base
                    .content
                    .contains("CONFIG_BASE_MUST_NOT_REPLACE_AGENT"),
            "bot root did not retain the explicit configuration base override"
        );
        ensure!(
            main_first.instructions.blocks("agentDefinition")
                != feishu_first.instructions.blocks("agentDefinition"),
            "distinct trusted root declarations produced identical Agent sources"
        );
        self.assert_phase_sources(AgentPhase::MainFirst, &main_first)?;
        self.assert_phase_sources(AgentPhase::FeishuFirst, &feishu_first)?;
        self.evidence.push(format!(
            "public create root={main}; real peer inbound root={feishu}, binding={}",
            direct[0].creation_id
        ));

        // The executable model directory was fixed before root snapshot creation. Mutate it only
        // after the CatalogFrozen provider request is parked, proving that its schema/result keeps
        // the same generation while later requests observe the new catalog.
        self.submit(&main, AgentPhase::CatalogFrozen).await?;
        let stage = self.gate(AgentPhase::CatalogFrozen).await?;
        self.update_child_models(
            config::ChildAccountUpdate::EmptyCatalog,
            "empty-executable-catalog",
        )
        .await?;
        stage.release();
        self.wait_complete(&main, AgentPhase::CatalogFrozen).await?;
        let catalog = self.catalog(AgentPhase::CatalogFrozen)?;
        wire::assert_all_modes(&catalog)?;
        ensure!(
            !catalog.diagnostics.is_empty(),
            "unavailable Profile had no real diagnostic"
        );
        let inherited = catalog
            .profiles
            .iter()
            .find(|profile| profile.profile_id == "explorer")
            .context("system child without an explicit route is missing")?;
        ensure!(
            inherited.account_id == config::ROOT_ACCOUNT
                && inherited.model_id == ROOT_MODEL
                && inherited.effort.is_none()
                && !config::has_explicit_system_route(&self.session.home, "explorer")?,
            "missing system child route did not inherit mode.simple without persisting"
        );
        let explicit = catalog
            .profiles
            .iter()
            .find(|profile| profile.profile_id == config::EXPLICIT_SYSTEM_AGENT)
            .context("explicit system child route is missing before withdrawal")?;
        ensure!(
            explicit.account_id == config::CHILD_ACCOUNT
                && explicit.model_id == CHILD_MODEL
                && config::has_explicit_system_route(
                    &self.session.home,
                    config::EXPLICIT_SYSTEM_AGENT
                )?,
            "explicit system child route did not take precedence"
        );

        // First restore the public model catalog so Settings can bind every current system role
        // to the soon-to-be-withdrawn child model. The product's real route resolver, not this
        // fixture, then makes the executable catalog empty when that account model disappears.
        self.update_child_models(
            config::ChildAccountUpdate::ExecutableCatalog,
            "restore-before-empty-route-arming",
        )
        .await?;
        // Restore the same route/catalog generation, then execute a real spawn from the inherited
        // explorer route before applying the withdrawal controls.
        let system = self
            .delegate(&main, AgentPhase::SpawnSystem, &catalog)
            .await?;

        let roots_before = self.directory().await?;
        for phase in [
            AgentPhase::RefuseMain,
            AgentPhase::RefuseFeishu,
            AgentPhase::RefuseWritable,
            AgentPhase::RefuseReview,
        ] {
            self.submit_complete(&main, phase).await?;
            self.assert_rejected_tool(&main, phase).await?;
        }
        ensure!(
            self.directory().await? == roots_before,
            "a rejected spawn created a Thread"
        );
        self.evidence.push("actual root-only IDs and illegal mode fields were rejected by host calls; no child directory entry/model request was created".into());

        // The bot owns its selector and would reconcile a bare Mode change back
        // to its configured model. Update that existing public resource too.
        self.set_bot_model(&bot, COMPACT_MODEL).await?;
        self.mode(&main, "mode.task").await?;
        self.mode(&feishu, "mode.task").await?;
        self.submit(&main, AgentPhase::MainTask).await?;
        let gate = self.gate(AgentPhase::CompactMain).await?;
        gate.release();
        self.wait_complete(&main, AgentPhase::MainTask).await?;
        // A platform input is accepted before it completes, so emit first and
        // release the real summarizer gate before awaiting inbound completion.
        self.emit(AgentPhase::FeishuTask).await?;
        let gate = self.gate(AgentPhase::CompactFeishu).await?;
        gate.release();
        self.wait_ingress(&bot, AgentPhase::FeishuTask).await?;
        let main_task = self.saved(&main, "main-task-compacted").await?;
        let feishu_task = self.saved(&feishu, "feishu-task-compacted").await?;
        main_task
            .instructions
            .assert_mode_update_preserves_agent_and_non_model_sources(&main_first.instructions)?;
        feishu_task
            .instructions
            .assert_mode_update_preserves_agent_and_non_model_sources(&feishu_first.instructions)?;
        main_task.assert_compacted(&main_first, AgentPhase::CompactMain.marker())?;
        feishu_task.assert_compacted(&feishu_first, AgentPhase::CompactFeishu.marker())?;
        self.assert_phase_sources(AgentPhase::MainTask, &main_task)?;
        self.assert_phase_sources(AgentPhase::FeishuTask, &feishu_task)?;
        for (phase, sources) in [
            (AgentPhase::CompactMain, &main_task),
            (AgentPhase::CompactFeishu, &feishu_task),
        ] {
            self.assert_phase_sources(phase, sources)?;
        }
        self.evidence.push("both roots switched Mode, rebound models, performed real automatic TextSummary calls and committed compaction receipts/context replacements before their next model request".into());
        self.set_bot_model(&bot, ROOT_MODEL).await?;
        self.mode(&main, "mode.simple").await?;
        self.mode(&feishu, "mode.simple").await?;

        // Now verify a real empty executable catalog without changing the root's instruction
        // sources before its Mode/compaction proof above. Role bindings and account withdrawal
        // are public product mutations; restoring the account must recover the exact catalog/schema.
        let routed_roles = self.route_system_profiles_to_withdrawable_model().await?;
        self.submit_complete(&main, AgentPhase::CatalogArmed)
            .await?;
        let armed_catalog = self.catalog(AgentPhase::CatalogArmed)?;
        wire::assert_all_modes(&armed_catalog)?;
        ensure!(
            armed_catalog
                .profiles
                .iter()
                .filter(|profile| profile.system)
                .all(|profile| {
                    profile.account_id == config::CHILD_ACCOUNT && profile.model_id == CHILD_MODEL
                }),
            "public Settings route controls did not bind all executable system Profiles"
        );
        self.evidence.push(format!(
            "public Settings RoleModel mutations bound {} canonical system Profiles to the withdrawable account selector",
            routed_roles.len()
        ));

        self.update_child_models(
            config::ChildAccountUpdate::EmptyCatalog,
            "withdraw-all-executable-routes",
        )
        .await?;
        self.submit_complete(&main, AgentPhase::CatalogEmpty)
            .await?;
        let empty_catalog = self.catalog(AgentPhase::CatalogEmpty)?;
        ensure!(
            empty_catalog.profiles.is_empty(),
            "public route/account withdrawal did not produce a genuinely empty executable catalog"
        );
        ensure!(
            wire::tool(
                &self.phase_requests(AgentPhase::CatalogEmpty)?[0],
                "spawn_agent"
            )?
            .is_none(),
            "genuinely empty catalog retained the spawn tool"
        );

        self.update_child_models(
            config::ChildAccountUpdate::ExecutableCatalog,
            "restore-executable-catalog",
        )
        .await?;
        self.submit_complete(&main, AgentPhase::CatalogRestored)
            .await?;
        let restored_catalog = self.catalog(AgentPhase::CatalogRestored)?;
        ensure!(
            restored_catalog.profiles == armed_catalog.profiles,
            "restored executable catalog differs from the armed same-generation Profiles"
        );
        let armed_request = self.phase_requests(AgentPhase::CatalogArmed)?;
        let restored_request = self.phase_requests(AgentPhase::CatalogRestored)?;
        ensure!(
            wire::tool(&armed_request[0], "spawn_agent")?
                == wire::tool(&restored_request[0], "spawn_agent")?,
            "restored same-generation spawn schema differs from the armed schema"
        );
        self.write("agent-definition-catalog.json", &restored_catalog)?;
        self.evidence.push("public route bindings plus account withdrawal produced a real empty executable catalog with no spawn tool; public account restore recovered the exact armed catalog/schema".into());

        let user = self
            .delegate(&main, AgentPhase::SpawnUser, &restored_catalog)
            .await?;
        let main_before_restart = self.saved(&main, "main-before-restart").await?;
        let feishu_before_restart = self.saved(&feishu, "feishu-before-restart").await?;
        let old_server = self
            .session
            .server
            .as_ref()
            .context("server missing before cold restart")?;
        let old_pid = old_server
            .pids()
            .0
            .context("real server PID missing before cold restart")?;
        let old_binary = old_server.identity().clone();
        let restart = self
            .session
            .restart_studio_server_with_config(config::change_future_profiles)
            .await?;
        ensure!(
            restart.stopped_sigints == 1
                && restart.stopped_exit_code == Some(0)
                && restart.stopped_graceful,
            "cold restart did not observe a delivered graceful stop: {restart}"
        );
        let new_server = self
            .session
            .server
            .as_ref()
            .context("server missing after cold restart")?;
        let new_pid = new_server
            .pids()
            .0
            .context("real server PID missing after cold restart")?;
        ensure!(
            old_pid != new_pid
                && old_binary.sha256 == new_server.identity().sha256
                && old_binary.canonical_path == new_server.identity().canonical_path,
            "cold restart did not replace the real PID with the same binary"
        );
        self.evidence.push(restart.to_string());
        self.session
            .http()?
            .open_project(&self.session.project.to_string_lossy())
            .await?;
        self.submit_complete(&main, AgentPhase::ColdCatalog).await?;
        let future_catalog = self.catalog(AgentPhase::ColdCatalog)?;
        ensure!(
            !future_catalog
                .profiles
                .iter()
                .any(|profile| profile.profile_id == "explorer"),
            "disabled system Profile remains dispatchable"
        );
        let new_user = future_catalog
            .profiles
            .iter()
            .find(|profile| profile.profile_id == USER_PROFILE)
            .context("future user Profile missing")?;
        let old_user = user
            .profile
            .as_ref()
            .context("original user Profile missing")?;
        ensure!(
            new_user.revision != old_user.revision
                && new_user.model_id == USER_MODEL_NEW
                && new_user.system_instructions == config::NEW_ROLE,
            "future Profile mutation was not adopted"
        );
        let default_system = future_catalog
            .profiles
            .iter()
            .find(|profile| profile.profile_id == "executor")
            .context("future inherited system Agent missing")?;
        ensure!(
            default_system.system
                && default_system.account_id == config::ROOT_ACCOUNT
                && default_system.model_id == FUTURE_MODEL
                && !config::has_explicit_system_route(&self.session.home, "executor")?,
            "new system child did not inherit the changed mode.simple selector"
        );
        let future_system = self
            .delegate(&main, AgentPhase::SpawnDefaultSystem, &future_catalog)
            .await?;
        ensure!(
            future_system.profile.as_ref().is_some_and(|profile| {
                profile.profile_id == "executor"
                    && profile.model_id == FUTURE_MODEL
                    && profile.account_id == config::ROOT_ACCOUNT
            }),
            "new child did not freeze the changed default route"
        );
        self.evidence.push("after mode.simple changed, a new real executor spawn and provider request used the inherited new selector while the earlier explorer child remained frozen on its original route".into());
        let cold_input = format!(
            "bot:{bot}:{DIRECT_CHAT_ID}:{}",
            message_id(AgentPhase::ColdFeishu)
        );
        let before_cold = self.session.http()?.read_timeline(&feishu, 100).await?;
        ensure!(!before_cold.items.iter().any(|item| matches!(&item.descriptor, TimelineDescriptor::Turn(turn) if turn.input_id() == Some(cold_input.as_str()))), "cold platform input already existed before this inbound");
        self.ingress(&bot, AgentPhase::ColdFeishu).await?;
        let cold_bindings = sqlite::thread_bindings(&self.session.home, &bot).await?;
        let cold_binding = cold_bindings
            .iter()
            .filter(|binding| binding.chat_id == DIRECT_CHAT_ID)
            .collect::<Vec<_>>();
        ensure!(
            cold_binding.len() == 1
                && cold_binding[0].thread_id == feishu
                && cold_binding[0].creation_id == direct[0].creation_id,
            "cold inbound changed original bot/chat Thread binding"
        );
        let cold_timeline = self.session.http()?.read_timeline(&feishu, 100).await?;
        let cold_turns = cold_timeline.items.iter().filter(|item| matches!(&item.descriptor, TimelineDescriptor::Turn(turn) if turn.input_id() == Some(cold_input.as_str()) && matches!(turn.state(), TurnState::Completed(_)))).collect::<Vec<_>>();
        ensure!(
            cold_turns.len() == 1,
            "original Feishu Thread has no unique completed Turn for current platform message"
        );
        let cold_turn = &cold_turns[0].header.turn_id;
        let has_text = |channel, expected: &str| {
            cold_timeline.items.iter().any(|item| {
                item.header.turn_id == *cold_turn
                    && matches!(&item.descriptor, TimelineDescriptor::Text(text) if text.channel == channel)
                    && item.fields.iter().any(|field| field.field == ThreadContentField::Text && field.text == expected)
            })
        };
        ensure!(
            has_text(
                pl_protocol::ThreadTextChannel::User,
                AgentPhase::ColdFeishu.marker()
            ) && has_text(
                pl_protocol::ThreadTextChannel::Final,
                "Agent observation ColdFeishu complete."
            ),
            "current original-Thread input/Final does not bind the actual cold request marker"
        );
        self.write("agent-definition-cold-feishu-timeline.json", &cold_timeline)?;
        let main_cold = self.saved(&main, "main-cold").await?;
        let feishu_cold = self.saved(&feishu, "feishu-cold").await?;
        ensure!(
            feishu_cold.state_revision > feishu_before_restart.state_revision
                && feishu_cold.history_fence > feishu_before_restart.history_fence,
            "original Feishu checkpoint/history did not advance for the cold inbound"
        );
        ensure!(
            main_cold.instructions == main_before_restart.instructions
                && feishu_cold.instructions == feishu_before_restart.instructions,
            "cold root instructions were rebuilt"
        );
        self.assert_phase_sources(AgentPhase::ColdCatalog, &main_cold)?;
        self.assert_phase_sources(AgentPhase::ColdFeishu, &feishu_cold)?;
        self.resume(&main, AgentPhase::ResumeSystem, &system)
            .await?;
        self.resume(&main, AgentPhase::ResumeUser, &user).await?;
        ensure!(
            self.directory().await?.len() == roots_before.len() + 2,
            "cold resume created an extra child or grandchild"
        );
        self.evidence.push("same-home real server replacement: roots continued; current catalog disabled system and revised user body/route, while original child IDs resumed by parent send_message with their frozen Profile/route/workspace and no child spawn capability".into());
        Ok(())
    }

    pub(super) async fn submit(&self, id: &str, phase: AgentPhase) -> Result<()> {
        let snapshot = self.session.http()?.read_thread(id).await?;
        ensure!(
            snapshot.active_turn.is_none(),
            "submit {phase:?} while previous Turn is active"
        );
        let route = snapshot
            .runtime
            .as_ref()
            .and_then(|runtime| runtime.model_route.as_ref())
            .context("public root route revision missing")?;
        let reply = self
            .session
            .http()?
            .submit_prompt(
                id,
                &SubmitPromptRequest {
                    input: input(phase),
                    expected_model_route_revision: route.revision,
                },
            )
            .await?;
        ensure!(
            reply.thread_id == id && reply.input_id == input(phase).input_id && reply.cursor > 0,
            "public prompt receipt identity mismatch"
        );
        Ok(())
    }

    pub(super) async fn submit_complete(&self, id: &str, phase: AgentPhase) -> Result<()> {
        self.submit(id, phase).await?;
        self.wait_complete(id, phase).await
    }

    pub(super) async fn wait_complete(&self, id: &str, phase: AgentPhase) -> Result<()> {
        let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
        let input_id = input(phase).input_id;
        loop {
            let page = self.session.http()?.read_timeline(id, 100).await?;
            for item in &page.items {
                if let TimelineDescriptor::Turn(turn) = &item.descriptor
                    && turn.input_id() == Some(input_id.as_str())
                {
                    match turn.state() {
                        TurnState::Completed(_) => {
                            let snapshot = self.session.http()?.read_thread(id).await?;
                            if snapshot.active_turn.is_none()
                                && snapshot.thread.status == ThreadStatus::Idle
                            {
                                return Ok(());
                            }
                        }
                        state if state.is_terminal() => {
                            bail!("Agent phase {phase:?} failed: {state:?}")
                        }
                        _ => {}
                    }
                }
            }
            ensure!(
                Instant::now() < deadline,
                "no complete canonical Turn for {phase:?}"
            );
            tokio::time::sleep(http::POLL).await;
        }
    }

    pub(super) async fn saved(&self, id: &str, label: &str) -> Result<saved::SavedEvidence> {
        let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
        let value = loop {
            match saved::load(&self.session.home, id).await? {
                Some(value) => break value,
                None => {
                    ensure!(Instant::now() < deadline, "no durable checkpoint for {id}");
                    tokio::time::sleep(http::POLL).await;
                }
            }
        };
        let snapshot = self.session.http()?.read_thread(id).await?;
        self.write(
            &format!("agent-definition-{label}.json"),
            &serde_json::json!({"publicSnapshot": snapshot, "saved": &value}),
        )?;
        Ok(value)
    }

    fn assert_phase_sources(&self, phase: AgentPhase, saved: &saved::SavedEvidence) -> Result<()> {
        for request in self.phase_requests(phase)? {
            wire::assert_instructions(&request, &saved.instructions)?;
            let model = if matches!(
                phase,
                AgentPhase::MainTask
                    | AgentPhase::FeishuTask
                    | AgentPhase::CompactMain
                    | AgentPhase::CompactFeishu
            ) {
                COMPACT_MODEL
            } else {
                ROOT_MODEL
            };
            ensure!(
                request.get("model").and_then(serde_json::Value::as_str) == Some(model),
                "actual root model differs from its independent configured selector"
            );
        }
        Ok(())
    }

    pub(super) fn catalog(&self, phase: AgentPhase) -> Result<wire::Catalog> {
        let requests = self.phase_requests(phase)?;
        let catalog = wire::catalog(&requests[1], phase)?;
        wire::assert_schema(&requests[0], &catalog)?;
        Ok(catalog)
    }

    async fn update_child_models(
        &self,
        update: config::ChildAccountUpdate,
        operation: &str,
    ) -> Result<()> {
        let current = self.session.http()?.read_settings().await?;
        let (custom_models, secret) = config::account_models_patch(update);
        let model_ids = match &custom_models {
            AccountModelsPatch::Set { models } => models
                .iter()
                .map(|model| model.model_id.clone())
                .collect::<Vec<_>>(),
            _ => bail!("catalog observation must explicitly replace its synthetic models"),
        };
        let mut reply = self
            .session
            .http()?
            .patch_account(&PatchAccountRequest {
                operation_id: format!("agent-{operation}"),
                expected_revision: current.config.revision,
                account_id: config::CHILD_ACCOUNT.into(),
                authentication: pl_protocol::studio::AccountAuthenticationIntent::Keep,
                name: AccountTextPatch::Keep,
                base_url: AccountTextPatch::Keep,
                template_id: AccountTextPatch::Keep,
                protocol: AccountTextPatch::Keep,
                secret,
                custom_models,
            })
            .await?;
        ensure!(
            reply.receipt.durable && reply.snapshot.config.revision > current.config.revision,
            "account catalog update was not durably acknowledged"
        );
        // Connection selection is a separate narrow intent. Carry each real receipt's
        // revision forward; a later failure must not be reported as a rolled-back patch.
        for (index, model_id) in model_ids.into_iter().enumerate() {
            reply = self
                .session
                .http()?
                .set_model_connection(&SetAccountModelConnectionRequest {
                    operation_id: format!("agent-{operation}-connection-{index}"),
                    expected_revision: reply.snapshot.config.revision,
                    account_id: config::CHILD_ACCOUNT.into(),
                    model_id,
                    connection: ModelConnectionIntent::Set(AccountConnectionMode::Http),
                })
                .await?;
            ensure!(
                reply.receipt.durable,
                "catalog patch applied, but model connection was not durably acknowledged"
            );
        }
        Ok(())
    }

    async fn route_system_profiles_to_withdrawable_model(&self) -> Result<Vec<String>> {
        let mut current = self.session.http()?.read_settings().await?;
        let mut roles = current
            .config
            .settings
            .roles
            .iter()
            .map(|role| role.key.clone())
            .collect::<Vec<_>>();
        roles.sort();
        ensure!(!roles.is_empty(), "Settings exposed no system child roles");

        for role in &roles {
            let bound = current
                .config
                .settings
                .roles
                .iter()
                .find(|setting| setting.key == *role)
                .context("canonical system role disappeared from Settings")?;
            if bound.account_id == config::CHILD_ACCOUNT && bound.model_id == CHILD_MODEL {
                continue;
            }
            let reply = self
                .session
                .http()?
                .update_settings_field(&UpdateSettingsFieldRequest {
                    operation_id: format!("agent-empty-route-{role}"),
                    expected_revision: current.config.revision,
                    update: SettingsFieldUpdate::RoleModel {
                        role: role.clone(),
                        account_id: config::CHILD_ACCOUNT.into(),
                        model_id: CHILD_MODEL.into(),
                    },
                })
                .await?;
            ensure!(
                reply.receipt.durable,
                "public RoleModel mutation for {role} was not durable"
            );
            current = reply.snapshot;
        }
        ensure!(
            roles
                .iter()
                .all(|role| current.config.settings.roles.iter().any(|setting| {
                    setting.key == *role
                        && setting.account_id == config::CHILD_ACCOUNT
                        && setting.model_id == CHILD_MODEL
                })),
            "canonical Settings did not publish the complete withdrawable route set"
        );
        Ok(roles)
    }

    async fn set_base_override(&self, value: &str) -> Result<()> {
        let current = self.session.http()?.read_settings().await?;
        let reply = self
            .session
            .http()?
            .update_settings_field(&UpdateSettingsFieldRequest {
                operation_id: "agent-base-override".into(),
                expected_revision: current.config.revision,
                update: SettingsFieldUpdate::InstructionBaseOverride {
                    value: value.into(),
                },
            })
            .await?;
        ensure!(
            reply.receipt.durable && reply.snapshot.config.revision > current.config.revision,
            "base override was not durably acknowledged"
        );
        Ok(())
    }

    async fn mode(&self, id: &str, mode: &str) -> Result<()> {
        let previous = saved::load(&self.session.home, id)
            .await?
            .context("Mode change has no initial durable checkpoint")?;
        let operation = format!("agent-mode-{id}-{mode}");
        let reply = self
            .session
            .http()?
            .set_thread_mode(
                id,
                &SetThreadModeRequest {
                    operation_id: operation.clone(),
                    mode: mode.into(),
                },
            )
            .await?;
        // Thread commands report the in-memory commit separately from the
        // write-behind barrier. Do not mistake durable=false for a rejection,
        // or claim persistence merely because the HTTP call returned success.
        let receipt = &reply.receipt;
        ensure!(
            receipt.operation_id == operation
                && receipt.disposition == pl_protocol::studio::CommandDisposition::Applied
                && receipt.effect == pl_protocol::studio::CommandEffectPoint::Immediate
                && receipt.effective,
            "Mode change has no effective applied receipt: {receipt:?}"
        );
        let targets = receipt
            .targets
            .iter()
            .filter(|target| target.resource_key == format!("thread-state:{id}"))
            .collect::<Vec<_>>();
        ensure!(
            targets.len() == 1
                && !targets[0].owner_epoch.is_empty()
                && targets[0].revision > previous.state_revision,
            "Mode receipt has no unique newer Thread commit target"
        );
        let deadline = Instant::now() + http::PREDICATE_TIMEOUT;
        let committed = loop {
            if let Some(current) = saved::load(&self.session.home, id).await?
                && current.state_revision >= targets[0].revision
            {
                break current;
            }
            ensure!(
                Instant::now() < deadline,
                "Mode commit did not reach its durable history/checkpoint barrier"
            );
            tokio::time::sleep(http::POLL).await;
        };
        committed
            .instructions
            .assert_mode_update_preserves_agent_and_non_model_sources(&previous.instructions)?;
        let snapshot = self.session.http()?.read_thread(id).await?;
        ensure!(
            snapshot.thread.mode.as_str() == mode,
            "canonical Thread did not adopt selected Mode"
        );
        self.write(
            &format!("agent-definition-mode-{id}-{mode}.json"),
            &serde_json::json!({"reply":reply, "publicSnapshot":snapshot, "saved":committed}),
        )?;
        Ok(())
    }

    async fn set_bot_model(&self, id: &str, model: &str) -> Result<()> {
        let bot = self.session.bot(id).await?;
        self.session
            .http()?
            .save_bot(&SaveBotRequest {
                operation_id: format!("agent-bot-route-{model}"),
                bot_id: Some(id.into()),
                expected_config_revision: bot.config_revision,
                name: bot.name,
                project_id: bot.project_id,
                app_id: bot.app_id,
                secret: BotSecretUpdate::Preserve,
                enabled: bot.enabled,
                tools_enabled: bot.tools_enabled,
                model_route: Some(BotModelRoute {
                    account_id: config::ROOT_ACCOUNT.into(),
                    model_id: model.into(),
                    effort: None,
                }),
            })
            .await?;
        Ok(())
    }

    async fn emit(&self, phase: AgentPhase) -> Result<()> {
        self.session
            .control()?
            .send_event(text_event(
                message_id(phase),
                DIRECT_CHAT_ID,
                ChatType::P2p,
                SenderKind::User,
                TRUSTED_USER_OPEN_ID,
                phase.marker(),
                Vec::new(),
            ))
            .await?;
        Ok(())
    }

    async fn wait_ingress(&self, bot: &str, phase: AgentPhase) -> Result<()> {
        self.session
            .wait_inbound_completed(bot, &message_id(phase))
            .await?;
        self.session
            .wait_send_text(&format!("Agent observation {phase:?} complete."))
            .await
    }

    async fn ingress(&self, bot: &str, phase: AgentPhase) -> Result<()> {
        self.emit(phase).await?;
        self.wait_ingress(bot, phase).await
    }

    pub(super) async fn directory(&self) -> Result<Vec<String>> {
        let ids = saved::thread_ids(&self.session.home).await?;
        let mut cursor = None;
        for _ in 0..4 {
            let page = self
                .session
                .http()?
                .list_threads_page(cursor.as_deref(), 64)
                .await?;
            let data = page.state.value().context("Thread directory unavailable")?;
            ensure!(
                data.threads.iter().all(|thread| ids.contains(&thread.id)),
                "public root directory contains an unpersisted Thread"
            );
            cursor = data.next_cursor.clone();
            if cursor.is_none() {
                return Ok(ids);
            }
        }
        bail!("Agent observation Thread directory exceeded its bound")
    }

    async fn assert_rejected_tool(&self, id: &str, phase: AgentPhase) -> Result<()> {
        let requests = self.phase_requests(phase)?;
        ensure!(
            wire::tool(&requests[0], "spawn_agent")?.is_some(),
            "root lacked actual spawn capability for refusal probe"
        );
        wire::output(&requests[1], &phase.action_call())?;
        let page = self.session.http()?.read_timeline(id, 100).await?;
        let tool = page
            .items
            .iter()
            .filter_map(|item| match &item.descriptor {
                TimelineDescriptor::Tool(tool) => Some(tool),
                _ => None,
            })
            .find(|tool| tool.invocation.tool_call_id == phase.action_call())
            .context("rejected real tool item missing")?;
        ensure!(
            matches!(
                tool.state,
                pl_protocol::TimelineToolState::Failed { .. }
                    | pl_protocol::TimelineToolState::Denied { .. }
            ),
            "forbidden spawn was not rejected: {:?}",
            tool.state
        );
        Ok(())
    }
}

fn input(phase: AgentPhase) -> StudioPromptInput {
    StudioPromptInput {
        input_id: format!("agent-input-{phase:?}"),
        text: phase.marker().into(),
        attachment_draft_ids: Vec::new(),
    }
}

fn message_id(phase: AgentPhase) -> String {
    format!("om_agent_{phase:?}")
}
