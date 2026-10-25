use anyhow::Result;

use crate::config::ConfigRuntime;
use crate::studio::agent_host::ThreadWriteBehindWriter;
use crate::studio::runtime_lock::RuntimeLockOwner;
use crate::studio::{ProductEventBus, StudioRuntimeState, StudioStore};
use pl_tool::mcp::{McpConnector, McpRuntime};

use super::super::StudioRuntime;
use super::super::attachment_drafts::AttachmentDraftRuntime;
use super::super::lsp_state::LspStateRuntime;
use super::super::mcp_health::McpStateRuntime;
use super::super::residency::ThreadResidency;
use super::super::{
    AccountUsageRuntime, ModelPerformanceOwner, ShutdownProgressBus, SkillCatalogRuntime,
    StudioAgentFacility, StudioExternalRuntimes, StudioUpdateRuntime,
};

impl StudioRuntime {
    pub(super) async fn assemble(
        store: StudioStore,
        config_runtime: ConfigRuntime,
        system_skills_dir: std::path::PathBuf,
        helper_source: crate::worker_assets::RemoteHelperSource,
    ) -> Result<Self> {
        let owner_epoch = crate::studio::ids::new_id("runtime");
        let (settings_updates, _) = tokio::sync::watch::channel(config_runtime.read()?);
        // Resolve the supervised local worker *before* creating any store-derived owner, so a
        // helper resolution failure can never leave partially-constructed owners (writer, updater,
        // attachment drafts, ...) behind. Resolution is deliberately non-fatal: a host with no
        // local stdio MCP server must still boot, and the connector fails loudly at connect time
        // when the supervisor is missing — there is no bare shell/PATH fallback.
        #[cfg(target_os = "linux")]
        let stdio_worker = match crate::worker_assets::local_worker(helper_source.clone()).await {
            Ok(worker) => Some(worker),
            Err(error) => {
                tracing::warn!(
                    error = %error,
                    "local MCP worker is unavailable; local stdio servers will fail to start until the helper is installed"
                );
                None
            }
        };
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
        let ssh_manager = std::sync::Arc::new(crate::worker_assets::ssh_manager(&helper_source));
        let worktrees =
            crate::studio::agent_host::worktree_lease::WorktreeLeaseOwner::new(writer.clone());
        let persistence = writer;
        let account_usage = AccountUsageRuntime::new(
            store.clone(),
            config_runtime.clone(),
            product_events.clone(),
        );
        // ACP 认证 owner 只持有身份与操作事实；构造期不启动任何外部程序，只把当前配置的
        // 连接身份登记为 `Unchecked`。
        let acp_auth = super::super::acp_auth::AcpAuthRuntime::new(
            store.clone(),
            config_runtime.clone(),
            product_events.clone(),
            helper_source.clone(),
        );
        // 安装 Settings 提交观察者并立即观察当前 canonical 快照；安装、首次观察与后续提交共用
        // 同一 Settings command 锁，因此不会有提交落在两者之间。
        acp_auth.install_settings_observer(&config_runtime)?;
        // 官方 server 准备 owner 只持有独立快照与操作槽位；构造期不读取 registry、不写文件。
        let acp_install = super::super::acp_install::AcpInstallRuntime::new(
            store.clone(),
            product_events.clone(),
        );
        let updater = StudioUpdateRuntime::new(product_events.clone())?;
        let mcp_state = McpStateRuntime::new();
        let lsp_state = LspStateRuntime::new(product_events.clone());
        let attachment_drafts = AttachmentDraftRuntime::new(store.attachment_drafts_dir())?;
        // The configuration owner established and loaded the one canonical Mode manager.
        let thread_modes = config_runtime.thread_mode_manager();
        // Linux stdio MCP servers have no unsupervised fallback: when the host resolved the same
        // supervised worker resource used by local tool exec, inject it; otherwise the connector
        // fails loud for any local stdio server (and empty MCP hosts still boot).
        #[cfg(target_os = "linux")]
        let mcp = {
            let mut connector = McpConnector::default();
            if let Some(worker) = stdio_worker {
                connector = connector.with_stdio_worker(worker);
            }
            McpRuntime::new(connector).handle()
        };
        #[cfg(not(target_os = "linux"))]
        let mcp = McpRuntime::new(McpConnector::default()).handle();
        let lsp = pl_lsp::runtime::LspRuntimeRegistry::new();
        let skills = SkillCatalogRuntime::new(product_events.clone(), system_skills_dir);
        let thread_factory = crate::studio::thread_factory::StudioThreadFactory::new(
            crate::studio::thread_factory::StudioThreadServices {
                store: store.clone(),
                worktrees: worktrees.clone(),
                product_events: product_events.clone(),
                config_runtime: config_runtime.clone(),
                mcp_runtime: mcp.clone(),
                lsp_runtime: lsp.clone(),
                skills: skills.clone(),
                thread_modes: thread_modes.clone(),
                ssh_manager: ssh_manager.clone(),
                helper_source: helper_source.clone(),
                bots: bots.clone(),
            },
        );
        let threads = crate::thread_assembler::StudioThreadAssembler::default();
        threads.set_agent_services(
            config_runtime.clone(),
            store.clone(),
            product_events.clone(),
            thread_factory.clone(),
            model_performance.clone(),
        )?;
        threads.set_child_factory(crate::thread_assembler::ConfiguredChildFactory::new(
            config_runtime.clone(),
            thread_factory.clone(),
        ))?;
        let recovery = crate::studio::StudioRecoveryRegistry::new();
        let thread_observations = super::super::thread_observation::ThreadObservations::new(
            super::super::thread_observation::ObservationServices {
                config: config_runtime.clone(),
                store: store.clone(),
                events: product_events.clone(),
                performance: model_performance.clone(),
                threads: threads.clone(),
                writer: persistence.clone(),
                recovery: recovery.clone(),
            },
        );
        let rejected_tools = super::super::rejected_tools::RejectedToolOwners::default();
        thread_observations.install(thread_factory.clone(), rejected_tools.clone())?;
        // 持久化观察在 runtime 装配完成后由 `start_persistence_observer` 启动并持有。
        let mut runtime = Self {
            owner_epoch,
            startup_recovery: None,
            persistence_observer: Default::default(),
            thread_observations,
            settings_updates,
            settings_refresh: Default::default(),
            model_catalog_tasks: Default::default(),
            tool_refresh: Default::default(),
            rejected_tools,
            tool_catalog_updates: Default::default(),
            threads,
            thread_factory,
            instance_lock: RuntimeLockOwner::new(None),
            store,
            bots,
            residency: ThreadResidency::new(),
            shutdown_progress: ShutdownProgressBus::new(),
            config_runtime,
            external_runtimes: StudioExternalRuntimes {
                mcp,
                mcp_state,
                mcp_config_watcher: Default::default(),
                mcp_health_watcher: Default::default(),
                lsp,
                lsp_state,
                lsp_state_watcher: Default::default(),
            },
            agent_facility: StudioAgentFacility {
                worktrees,
                persistence: std::sync::Arc::new(tokio::sync::Mutex::new(Some(persistence))),
                product_events: product_events.clone(),
            },
            runtime_state: StudioRuntimeState::new(),
            recovery,
            recovery_task: Default::default(),
            skills,
            thread_modes,
            account_usage,
            acp_auth,
            acp_install,
            model_performance,
            updater,
            activation: Default::default(),
            attachment_drafts,
            ssh_manager,
            service_stops: Default::default(),
            archive_task: Default::default(),
            lifecycle_lock: std::sync::Arc::new(tokio::sync::Mutex::new(())),
            shutdown_latch: Default::default(),
            shutdown_run: Default::default(),
            early_exit_issues: std::sync::Arc::new(std::sync::Mutex::new(Vec::new())),
            title_tasks: Default::default(),
            #[cfg(target_os = "linux")]
            helper_source,
            profiles_forwarder: Default::default(),
            bot_host: None,
        };
        let keep = std::sync::Arc::new(runtime.clone());
        runtime.bots.attach_host(std::sync::Arc::downgrade(&keep));
        runtime.bot_host = Some(keep);
        Ok(runtime)
    }
}
