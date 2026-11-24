use anyhow::Result;

use crate::config::ConfigRuntime;
use crate::studio::runtime_lock::RuntimeLockOwner;
use crate::studio::storage::write_behind::ThreadWriteBehindWriter;
use crate::studio::{ProductEventBus, StudioRuntimeState, StudioStore};
use pl_tool::mcp::McpConnector;

use super::super::StudioRuntime;
use super::super::attachment_drafts::AttachmentDraftRuntime;
use super::super::lsp_state::LspStateRuntime;
use super::super::residency::ThreadResidency;
use super::super::{
    AccountUsageRuntime, ModelPerformanceOwner, ShutdownProgressBus, SkillCatalogRuntime,
    StudioAgentFacility, StudioExternalRuntimes, StudioUpdateRuntime,
};

/// Owners and sources required to assemble one [`StudioRuntime`].
pub(super) struct RuntimeAssemblyParts {
    pub(super) store: StudioStore,
    pub(super) config_runtime: ConfigRuntime,
    pub(super) system_skills_dir: std::path::PathBuf,
    pub(super) helper_source: crate::worker_assets::RemoteHelperSource,
    pub(super) host_mcp_source: crate::host_mcp_assets::HostMcpSource,
    pub(super) ssh_config: Option<crate::SshConfigFile>,
    pub(super) skill_search: pl_tool::skill::SkillSearchOptions,
    pub(super) run_export: Option<std::sync::Arc<super::super::run_export::RunExportCoordinator>>,
}

impl StudioRuntime {
    pub(super) async fn assemble(parts: RuntimeAssemblyParts) -> Result<Self> {
        let RuntimeAssemblyParts {
            store,
            config_runtime,
            system_skills_dir,
            helper_source,
            host_mcp_source,
            ssh_config,
            skill_search,
            run_export,
        } = parts;
        let local_executor = pl_remote_helper::Executor::local()?;
        let owner_epoch = crate::studio::ids::new_id("runtime");
        let (settings_updates, _) = tokio::sync::watch::channel(config_runtime.read()?);
        // 进程级共享 writer 先于所有 owner 构造：ProductEventBus 与
        // ThreadRepository 共用同一 write-behind 队列。
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let product_events = ProductEventBus::new(store.clone(), writer.clone());
        let bots = crate::bots::BotRuntime::new(
            store.paths().clone(),
            config_runtime.clone(),
            product_events.clone(),
        )?;

        let model_performance =
            ModelPerformanceOwner::new(store.clone(), product_events.clone(), owner_epoch.clone());
        let mut ssh_manager = crate::worker_assets::ssh_manager(&helper_source);
        if let Some(config) = ssh_config {
            ssh_manager = ssh_manager.with_ssh_config(config);
        }
        let ssh_manager = std::sync::Arc::new(ssh_manager);
        let worktrees =
            crate::studio::worktree::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
        let persistence = writer;
        let account_usage = AccountUsageRuntime::new(store.clone(), config_runtime.clone());
        // ACP 认证 owner 只持有身份与操作事实；构造期不启动任何外部程序，只把当前配置的
        // 连接身份登记为 `Unchecked`。
        let acp_accounts = super::super::acp_accounts::AcpAccountRuntime::new(
            store.clone(),
            config_runtime.clone(),
            product_events.clone(),
            local_executor.clone(),
            host_mcp_source.clone(),
        );
        // 官方 server 准备 owner 只持有独立快照与操作槽位；构造期不读取 registry、不写文件。
        let acp_install = super::super::acp_install::AcpInstallRuntime::new(
            store.clone(),
            product_events.clone(),
            acp_accounts.clone(),
        );
        let acp_detection = super::super::acp_detection::AcpLocalDetectionRuntime::new(
            store.clone(),
            product_events.clone(),
            local_executor.clone(),
        );
        let updater = StudioUpdateRuntime::new(product_events.clone())?;
        let lsp_state = LspStateRuntime::new(product_events.clone());
        let attachment_drafts = AttachmentDraftRuntime::new(store.attachment_drafts_dir())?;
        // The configuration owner established and loaded the one canonical Mode manager.
        let thread_modes = config_runtime.thread_mode_manager();
        let mcp_connector = McpConnector::default().with_executor(local_executor.clone());
        let lsp = pl_lsp::runtime::LspRuntimeRegistry::new();
        let skills = SkillCatalogRuntime::new(
            product_events.clone(),
            system_skills_dir,
            local_executor.clone(),
            skill_search,
        );
        let recovery = crate::studio::StudioRecoveryRegistry::new();
        let thread_factory = crate::studio::thread_factory::StudioThreadFactory::new(
            crate::studio::thread_factory::StudioThreadServices {
                store: store.clone(),
                worktrees: worktrees.clone(),
                recovery: recovery.clone(),
                product_events: product_events.clone(),
                config_runtime: config_runtime.clone(),
                mcp_connector,
                lsp_runtime: lsp.clone(),
                local_executor: local_executor.clone(),
                skills: skills.clone(),
                thread_modes: thread_modes.clone(),
                ssh_manager: ssh_manager.clone(),
                bots: bots.clone(),
                run_export: run_export.clone(),
            },
        );
        let sessions = crate::session::SessionTable::new();
        let acp_business = super::super::acp_business::AcpBusinessOwner::new(
            thread_factory.clone(),
            config_runtime.clone(),
            store.clone(),
            product_events.clone(),
            acp_accounts.clone(),
            thread_modes.clone(),
        );
        let service_config = config_runtime.clone();
        let service_store = store.clone();
        let service_events = product_events.clone();
        let service_factory = thread_factory.clone();
        let service_performance = model_performance.clone();
        let service_recovery = recovery.clone();
        sessions.push_assignment(crate::thread_assembler::SessionAssignment::services(
            service_config,
            service_store,
            service_events,
            service_factory,
            service_performance,
            service_recovery,
            acp_business,
        ))?;
        let thread_observations = super::super::thread_observation::ThreadObservations::new(
            super::super::thread_observation::ObservationServices {
                config: config_runtime.clone(),
                settings_updates: settings_updates.subscribe(),
                store: store.clone(),
                events: product_events.clone(),
                performance: model_performance.clone(),
                sessions: sessions.downgrade(),
                writer: persistence.clone(),
                recovery: recovery.clone(),
                run_export: run_export.clone(),
            },
        );
        let rejected_tools =
            super::super::rejected_tools::RejectedToolOwners::new(sessions.downgrade());
        thread_observations.install()?;
        let observations = std::sync::Arc::new(
            super::super::observation_lifecycle::RuntimeObservationOwner::new(),
        );
        let mut runtime = Self {
            owner_epoch,
            startup_recovery: None,
            observations,
            thread_observations,
            settings_updates,
            settings_refresh: Default::default(),
            model_catalog_tasks: Default::default(),
            tool_refresh: Default::default(),
            rejected_tools,
            tool_catalog_updates: Default::default(),
            sessions,
            #[cfg(test)]
            s2_delete_publication_failure: Default::default(),
            thread_factory,
            instance_lock: RuntimeLockOwner::new(None),
            store,
            bots,
            residency: ThreadResidency::new(),
            shutdown_progress: ShutdownProgressBus::new(),
            config_runtime,
            external_runtimes: StudioExternalRuntimes { lsp, lsp_state },
            agent_facility: StudioAgentFacility {
                worktrees,
                persistence: std::sync::Arc::new(tokio::sync::Mutex::new(Some(persistence))),
                product_events: product_events.clone(),
                run_export,
            },
            runtime_state: StudioRuntimeState::new(),
            recovery,
            recovery_task: Default::default(),
            skills,
            thread_modes,
            account_usage,
            acp_accounts,
            chatgpt_auth: super::super::chatgpt_auth::ChatGptAuthRuntime::new(),
            acp_install,
            acp_detection,
            model_performance,
            updater,
            activation: Default::default(),
            attachment_drafts,
            ssh_manager,
            service_stops: Default::default(),
            thread_lifecycle_task: Default::default(),
            lifecycle_lock: std::sync::Arc::new(tokio::sync::Mutex::new(())),
            shutdown_latch: Default::default(),
            shutdown_run: Default::default(),
            early_exit_issues: std::sync::Arc::new(std::sync::Mutex::new(Vec::new())),
            title_tasks: Default::default(),
            bot_host: None,
        };
        let keep = std::sync::Arc::new(runtime.clone());
        runtime.bots.attach_host(std::sync::Arc::downgrade(&keep));
        runtime.bot_host = Some(keep);
        // An internal scheduling activation reports its failure through the runtime's single Recovery
        // registry, exactly like an explicit activation does.
        let recovering = std::sync::Arc::downgrade(
            runtime
                .bot_host
                .as_ref()
                .expect("runtime host installed above"),
        );
        runtime
            .sessions
            .install_workspace_recovery(std::sync::Arc::new(move |thread, error| {
                let recovering = recovering.clone();
                Box::pin(async move {
                    if let Some(recovering) = recovering.upgrade() {
                        recovering
                            .publish_session_workspace_issue(&thread, &error)
                            .await;
                    }
                })
            }))?;
        // Fallible assembly precedes account activation, so a failed startup cannot leave
        // eagerly started ACP processes behind. Installation and the first canonical
        // observation still share the Settings command boundary.
        runtime
            .acp_accounts
            .install_settings_observer(&runtime.config_runtime)?;
        Ok(runtime)
    }
}
