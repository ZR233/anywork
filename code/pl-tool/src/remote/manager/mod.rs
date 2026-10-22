//! 系统 OpenSSH 连接、逻辑 endpoint 弹性连接池、重连与 remote workspace 的本地 owner。

mod asset;
mod endpoint;
mod physical;
mod shutdown;
mod ssh;

use std::collections::{BTreeMap, HashMap, HashSet};
use std::path::PathBuf;
use std::sync::Arc;
use std::sync::atomic::{AtomicU64, Ordering};
use std::time::Duration;

use futures::FutureExt;
use pl_protocol::remote::{
    RemoteDirectoryListing, RemoteHello, RemoteRequest, RemoteResourceClass, RemoteShellDialect,
};
use serde::{Deserialize, Serialize};
use tokio::sync::{Mutex, RwLock, watch};
use tokio_util::sync::CancellationToken;
use tokio_util::task::TaskTracker;

use self::asset::file_helper_assets;
use self::physical::{Bootstrap, PhysicalConnect, connect_physical};
use self::ssh::validate_profile;
use super::ssh_config::{SshConfigEntry, SshConfigFile};
use super::{
    RemoteClientError, RemoteCommandBackend, RemoteExecutionBackend, RemoteWorkspaceFileBackend,
    RemoteWorkspaceHost, normalize_remote_absolute_path,
};
use crate::environment::{ExecutionEnvironment, ExecutionOs, ShellDialect};

pub use self::asset::{RemoteHelperAssets, RemoteHelperTarget};
pub(in crate::remote) use self::endpoint::{BindingId, Endpoint, GrowFn};

/// 打开远端 workspace 的有界等待；失败关闭并回收所属连接。
const WORKSPACE_OPEN_TIMEOUT: Duration = Duration::from_secs(15);

/// 进程内 endpoint 实例标识；代次重置不会让不同实例共享绑定身份。
static NEXT_ENDPOINT_ID: AtomicU64 = AtomicU64::new(0);

/// 不含 secret 的 SSH 服务器配置；别名即身份，对应 `~/.ssh/config` 的 Host。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshServerProfile {
    pub alias: String,
    pub host_name: String,
    pub port: u16,
    pub username: String,
    pub identity_file: Option<String>,
}

/// 单个 SSH 服务器的 canonical 连接快照。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SshConnectionSnapshot {
    pub alias: String,
    pub state: SshConnectionState,
}

/// SSH transport 与 helper bootstrap 的穷尽状态。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(
    tag = "kind",
    rename_all = "camelCase",
    rename_all_fields = "camelCase"
)]
pub enum SshConnectionState {
    Disconnected,
    Connecting,
    Ready {
        helper_version: String,
        architecture: String,
    },
    Reconnecting {
        attempt: u32,
        delay_seconds: u64,
    },
    Failed {
        code: String,
        message: String,
    },
}

#[derive(Clone, Default)]
struct SshPasswordStore(Arc<RwLock<HashMap<String, String>>>);

impl std::fmt::Debug for SshPasswordStore {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str("SshPasswordStore(..)")
    }
}

/// 系统 OpenSSH、helper bootstrap、远端 workspace 与自动重连的本地 owner。
#[derive(Debug, Clone)]
pub struct SshManager {
    servers: Arc<RwLock<HashMap<String, SshConfigEntry>>>,
    passwords: SshPasswordStore,
    ssh_config: SshConfigFile,
    helper_assets: Option<Arc<dyn RemoteHelperAssets>>,
    endpoints: Arc<Mutex<HashMap<String, Arc<Endpoint>>>>,
    admission: Arc<Mutex<bool>>,
    closing: CancellationToken,
    operations: TaskTracker,
    connection_locks: Arc<Mutex<HashMap<String, Arc<Mutex<()>>>>>,
    states: Arc<RwLock<HashMap<String, watch::Sender<SshConnectionState>>>>,
    ready_revisions: watch::Sender<BTreeMap<String, u64>>,
    desired_connections: Arc<RwLock<HashSet<String>>>,
}

impl SshManager {
    /// 使用可选的开发 helper 资产创建 manager。
    ///
    /// 每个资产仍必须带有相邻的 `.sha256` 文件；生产环境应使用
    /// [`Self::with_helper_assets`] 提供随应用分发的按需解压资产。
    pub fn new(aarch64_helper: Option<PathBuf>, x86_64_helper: Option<PathBuf>) -> Self {
        Self::with_optional_helper_assets(file_helper_assets(aarch64_helper, x86_64_helper))
    }

    /// 使用宿主提供的按需解压资产创建 manager。
    pub fn with_helper_assets(helper_assets: Arc<dyn RemoteHelperAssets>) -> Self {
        Self::with_optional_helper_assets(Some(helper_assets))
    }

    /// 显式指定 ssh config 文件；默认使用用户 `~/.ssh/config`。
    ///
    /// 测试与启动协调器用它隔离或收敛配置写入范围。
    pub fn with_ssh_config(mut self, ssh_config: SshConfigFile) -> Self {
        self.ssh_config = ssh_config;
        self
    }

    fn with_optional_helper_assets(helper_assets: Option<Arc<dyn RemoteHelperAssets>>) -> Self {
        Self {
            servers: Arc::new(RwLock::new(HashMap::new())),
            passwords: SshPasswordStore::default(),
            ssh_config: SshConfigFile::user_default().unwrap_or_else(|error| {
                tracing::warn!(%error, "falling back to the default ssh config location");
                SshConfigFile::default_location(".ssh/config")
            }),
            helper_assets,
            endpoints: Arc::new(Mutex::new(HashMap::new())),
            admission: Arc::new(Mutex::new(true)),
            closing: CancellationToken::new(),
            operations: TaskTracker::new(),
            connection_locks: Arc::new(Mutex::new(HashMap::new())),
            states: Arc::new(RwLock::new(HashMap::new())),
            ready_revisions: watch::channel(BTreeMap::new()).0,
            desired_connections: Arc::new(RwLock::new(HashSet::new())),
        }
    }

    /// 更新或清除指定服务器别名在当前进程内的 SSH 密码租约。
    pub async fn set_server_password(&self, server_id: &str, password: Option<String>) {
        let mut passwords = self.passwords.0.write().await;
        match password.filter(|secret| !secret.is_empty()) {
            Some(secret) => {
                passwords.insert(server_id.to_string(), secret);
            }
            None => {
                passwords.remove(server_id);
            }
        }
    }

    /// 读取当前进程内缓存的服务器 SSH 密码。
    pub async fn server_password(&self, server_id: &str) -> Option<String> {
        self.passwords.0.read().await.get(server_id).cloned()
    }

    /// 判断当前进程内是否持有该服务器的非空 SSH 密码。
    pub async fn has_server_password(&self, server_id: &str) -> bool {
        self.passwords
            .0
            .read()
            .await
            .get(server_id)
            .is_some_and(|secret| !secret.is_empty())
    }

    /// 从 ssh config 文件重新加载服务器集合；文件是该数据的唯一事实源。
    pub async fn reload_servers(&self) -> Result<(), RemoteClientError> {
        let entries = self.ssh_config.read().await?;
        let mut servers = self.servers.write().await;
        servers.clear();
        for entry in entries {
            servers.insert(entry.profile.alias.clone(), entry);
        }
        Ok(())
    }

    /// 返回按别名稳定排序的服务器条目（含是否为 anywork 管理块）。
    pub async fn list_servers(&self) -> Vec<SshConfigEntry> {
        let mut servers = self
            .servers
            .read()
            .await
            .values()
            .cloned()
            .collect::<Vec<_>>();
        servers.sort_by(|left, right| left.profile.alias.cmp(&right.profile.alias));
        servers
    }

    /// 校验并把服务器配置写入 ssh config 管理块。
    ///
    /// 别名被手写条目占用、或文件写入失败时返回错误且不改变内存集合。
    pub async fn save_server(
        &self,
        profile: SshServerProfile,
    ) -> Result<SshServerProfile, RemoteClientError> {
        validate_profile(&profile)?;
        let previous = self
            .servers
            .read()
            .await
            .get(&profile.alias)
            .map(|entry| entry.profile.clone());
        self.ssh_config
            .upsert_managed(std::slice::from_ref(&profile))
            .await?;
        if previous.as_ref() != Some(&profile) {
            self.disconnect_server(&profile.alias).await?;
        }
        self.ensure_state(&profile.alias).await;
        self.servers.write().await.insert(
            profile.alias.clone(),
            SshConfigEntry {
                profile: profile.clone(),
                managed: true,
            },
        );
        Ok(profile)
    }

    /// 删除服务器配置、连接池与进程内凭据；仅 anywork 管理块可删除。
    pub async fn delete_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        self.ssh_config.remove_managed(server_id).await?;
        self.disconnect_server(server_id).await?;
        self.passwords.0.write().await.remove(server_id);
        self.servers.write().await.remove(server_id);
        self.states.write().await.remove(server_id);
        self.connection_locks.lock().await.remove(server_id);
        Ok(())
    }

    /// 读取服务器的 canonical 连接状态。
    pub async fn connection_snapshot(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, RemoteClientError> {
        let sender = self.ensure_state(server_id).await;
        let state = sender.borrow().clone();
        Ok(SshConnectionSnapshot {
            alias: server_id.to_string(),
            state,
        })
    }

    /// 订阅服务器连接状态；订阅本身不会建立连接。
    pub async fn subscribe_state(&self, server_id: &str) -> watch::Receiver<SshConnectionState> {
        self.ensure_state(server_id).await.subscribe()
    }

    /// Subscribes to completed connections, including automatic reconnections.
    ///
    /// Revisions are local to this manager and retained across disconnects. Consumers
    /// must compare revisions, since multiple connections can complete between reads.
    /// Subscribing does not connect and carries no credentials or remote environment.
    pub fn subscribe_ready(&self) -> watch::Receiver<BTreeMap<String, u64>> {
        self.ready_revisions.subscribe()
    }

    /// 完成架构探测、helper bootstrap 与协议握手。
    pub async fn test_connection(
        &self,
        server_id: &str,
    ) -> Result<SshConnectionSnapshot, RemoteClientError> {
        self.connect_server(server_id).await?;
        self.connection_snapshot(server_id).await
    }

    /// 确保服务器已有可用端点；并发调用按服务器串行化。
    pub async fn connect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        self.desired_connections
            .write()
            .await
            .insert(server_id.to_string());
        let connection_lock = self.connection_lock(server_id).await;
        let _connection_guard = connection_lock.lock().await;
        let endpoint = self.endpoint(server_id).await?;
        if endpoint.has_healthy().await {
            // Resuming an already healthy endpoint also (re)arms its single reconnect monitor.
            self.spawn_endpoint_monitor(server_id.to_string(), endpoint);
            return Ok(());
        }
        self.set_state(server_id, SshConnectionState::Connecting)
            .await;
        let result = tokio::select! {
            biased;
            () = self.closing.cancelled() => Err(RemoteClientError::ManagerClosing),
            result = endpoint.ensure_ready() => result,
        };
        match result {
            Ok(()) => {
                self.publish_ready(server_id, &endpoint).await;
                self.spawn_endpoint_monitor(server_id.to_string(), endpoint);
                Ok(())
            }
            Err(error) => {
                let code = match &error {
                    RemoteClientError::AuthenticationFailed(_) => "sshAuthFailed",
                    _ => "sshConnectionFailed",
                };
                self.set_state(
                    server_id,
                    SshConnectionState::Failed {
                        code: code.to_string(),
                        message: error.to_string(),
                    },
                )
                .await;
                Err(error)
            }
        }
    }

    /// 关闭该服务器的连接池并取消其自动重连意图。
    ///
    /// # Errors
    /// Returns closing, transport, or process cleanup errors; failed connections remain owned.
    pub async fn disconnect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        self.desired_connections.write().await.remove(server_id);
        let connection_lock = self.connection_lock(server_id).await;
        let _connection_guard = connection_lock.lock().await;
        self.close_endpoint(server_id).await
    }

    /// 主动中断当前连接池，并保留自动重连意图。
    ///
    /// # Errors
    ///
    /// 当服务器不存在、初次连接失败或 SSH 子进程无法回收时返回错误。
    pub async fn reconnect_server(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let _operation = self.admit_connection().await?;
        self.desired_connections
            .write()
            .await
            .insert(server_id.to_string());
        {
            let connection_lock = self.connection_lock(server_id).await;
            let _connection_guard = connection_lock.lock().await;
            self.close_endpoint(server_id).await?;
        }
        self.connect_server(server_id).await
    }

    /// 浏览远端目录；该功能只用于宿主 UI，不注册给模型。
    ///
    /// 目录条目在消费端增量消费后聚合为 GUI 需要的完整 listing，wire 上仍是逐条记录。
    pub async fn browse_directories(
        &self,
        server_id: &str,
        path: Option<String>,
    ) -> Result<RemoteDirectoryListing, RemoteClientError> {
        let _operation = self.admit_connection().await?;
        self.connect_server(server_id).await?;
        let endpoint = self.endpoint(server_id).await?;
        let lease = tokio::select! {
            biased;
            () = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
            lease = endpoint.acquire_any(RemoteResourceClass::Directory) => lease?,
        };
        let mut stream = tokio::select! {
            biased;
            () = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
            stream = lease.directory(RemoteRequest::BrowseDirectories { path }) => stream?,
        };
        let metadata = stream.metadata().clone();
        let mut entries = Vec::new();
        while let Some(entry) = stream.next_entry().await? {
            entries.push(entry);
        }
        entries.sort_by(|left, right| left.name.cmp(&right.name));
        Ok(RemoteDirectoryListing {
            path: metadata.path,
            parent: metadata.parent,
            entries,
        })
    }

    /// 打开远端 workspace 并返回文件 backend。
    pub async fn open_workspace(
        &self,
        server_id: &str,
        path: String,
    ) -> Result<RemoteWorkspaceFileBackend, RemoteClientError> {
        Ok(self.open_workspace_host(server_id, path).await?.files)
    }

    /// 打开或复用远端 workspace 的完整本地 backend 集合。
    pub async fn open_workspace_host(
        &self,
        server_id: &str,
        path: String,
    ) -> Result<RemoteWorkspaceHost, RemoteClientError> {
        // 跨端入口统一归一化为 POSIX：宿主形态（含 Windows 分隔符）的同一远端目录必须映射到
        // 同一个逻辑节定点，不得因宿主路径解释产生两个绑定身份。
        let path = normalize_remote_absolute_path(&path)
            .map_err(|error| RemoteClientError::protocol(error.to_string()))?;
        let _operation = self.admit_connection().await?;
        self.connect_server(server_id).await?;
        let endpoint = self.endpoint(server_id).await?;
        // The backend captures this binding; every later operation must match it exactly.
        let binding = endpoint.binding();
        let canonical_path = tokio::select! {
            biased;
            () = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
            result = tokio::time::timeout(
                WORKSPACE_OPEN_TIMEOUT,
                endpoint.open_workspace(path, binding),
            ) => result.map_err(|_| {
                RemoteClientError::protocol("SSH workspace open timed out")
            })??,
        };
        let environment = endpoint.execution_environment().await?;
        Ok(RemoteWorkspaceHost {
            files: RemoteWorkspaceFileBackend::new(
                endpoint.clone(),
                canonical_path.clone(),
                binding,
            ),
            commands: RemoteCommandBackend::new(endpoint.clone(), canonical_path.clone(), binding),
            git: RemoteExecutionBackend::new(endpoint, canonical_path, binding),
            execution_environment: environment,
        })
    }

    async fn profile(&self, server_id: &str) -> Result<SshServerProfile, RemoteClientError> {
        self.servers
            .read()
            .await
            .get(server_id)
            .map(|entry| entry.profile.clone())
            .ok_or_else(|| RemoteClientError::protocol(format!("unknown SSH server '{server_id}'")))
    }

    /// The logical endpoint of one server alias; its pool is created on first use.
    async fn endpoint(&self, server_id: &str) -> Result<Arc<Endpoint>, RemoteClientError> {
        if let Some(endpoint) = self.endpoints.lock().await.get(server_id).cloned() {
            return Ok(endpoint);
        }
        let profile = self.profile(server_id).await?;
        let endpoint = self.build_endpoint(&profile);
        let mut endpoints = self.endpoints.lock().await;
        if let Some(existing) = endpoints.get(server_id).cloned() {
            return Ok(existing);
        }
        endpoints.insert(server_id.to_owned(), endpoint.clone());
        Ok(endpoint)
    }

    /// Builds the logical endpoint and the coalesced connection factory of one server alias.
    fn build_endpoint(&self, profile: &SshServerProfile) -> Arc<Endpoint> {
        let alias = profile.alias.clone();
        let profile = profile.clone();
        let ssh_config = self.ssh_config.clone();
        let passwords = self.passwords.0.clone();
        let helper_assets = self.helper_assets.clone();
        let bootstrap = Arc::new(Mutex::new(Bootstrap::default()));
        let generation = Arc::new(AtomicU64::new(0));
        let physical_counter = Arc::new(AtomicU64::new(0));
        // The endpoint owns its own cancellation scope: a single disconnect never stops other
        // servers, while manager shutdown closes every endpoint explicitly.
        let closing = CancellationToken::new();
        let instance = NEXT_ENDPOINT_ID.fetch_add(1, Ordering::Relaxed) + 1;
        let grow: GrowFn = {
            let alias = alias.clone();
            let profile = profile.clone();
            let ssh_config = ssh_config.clone();
            let passwords = passwords.clone();
            let helper_assets = helper_assets.clone();
            let bootstrap = bootstrap.clone();
            let generation = generation.clone();
            let physical_counter = physical_counter.clone();
            let closing = closing.clone();
            Arc::new(move || {
                let alias = alias.clone();
                let profile = profile.clone();
                let ssh_config = ssh_config.clone();
                let passwords = passwords.clone();
                let helper_assets = helper_assets.clone();
                let bootstrap = bootstrap.clone();
                let generation = generation.clone();
                let physical_counter = physical_counter.clone();
                let closing = closing.clone();
                async move {
                    // The password lease is read at connection time, never cached in a profile.
                    let password = passwords.read().await.get(&alias).cloned();
                    let physical_generation = physical_counter.fetch_add(1, Ordering::AcqRel) + 1;
                    connect_physical(PhysicalConnect {
                        profile: &profile,
                        ssh_config: &ssh_config,
                        password: password.as_deref(),
                        assets: helper_assets,
                        alias: &alias,
                        endpoint_generation: generation.load(Ordering::Acquire),
                        generation: physical_generation,
                        closing: &closing,
                        bootstrap,
                    })
                    .await
                }
                .boxed()
            })
        };
        Endpoint::new(instance, alias, generation, grow, closing)
    }

    fn spawn_endpoint_monitor(&self, server_id: String, endpoint: Arc<Endpoint>) {
        if !endpoint.claim_monitor() {
            return;
        }
        let manager = self.clone();
        // The admitting operation is still tracked while this monitor is added.
        self.operations.spawn(async move {
            loop {
                tokio::select! {
                    biased;
                    () = manager.closing.cancelled() => return,
                    () = endpoint.wait_unhealthy() => {}
                }
                if !manager
                    .desired_connections
                    .read()
                    .await
                    .contains(&server_id)
                {
                    return;
                }
                // The recovery attempt itself must observe the manager's close, not only this loop's
                // head: its backoff, connection attempt, workspace probing and old-endpoint cleanup
                // would otherwise keep this tracked operation alive after `shutdown` began. Dropping
                // the attempt never detaches what it started — the connector runs as a supervised
                // owner and every startup, connection and endpoint stays in its resource set until its
                // own confirmed release — so the endpoint close below still cancels and really
                // reclaims them, without extending the exit budget.
                let outcome = tokio::select! {
                    biased;
                    () = manager.closing.cancelled() => return,
                    outcome = manager.reconnect_endpoint(&server_id) => outcome,
                };
                match outcome {
                    Ok(()) => continue,
                    Err(RemoteClientError::ManagerClosing) => return,
                    Err(error) => {
                        tracing::warn!(alias = %server_id, %error, "SSH endpoint recovery failed");
                        continue;
                    }
                }
            }
        });
    }

    async fn reconnect_endpoint(&self, server_id: &str) -> Result<(), RemoteClientError> {
        const DELAYS: [u64; 6] = [1, 2, 4, 8, 15, 30];
        {
            // Recovery cleanup runs once under the server serialization, but the backoff wait
            // itself never blocks a user-initiated disconnect or reconnect.
            let connection_lock = self.connection_lock(server_id).await;
            let _connection_guard = connection_lock.lock().await;
            let endpoint = self.endpoint(server_id).await?;
            let _ = endpoint.reap_failed().await;
        }
        let mut attempt = 0_u32;
        loop {
            if !self.desired_connections.read().await.contains(server_id) {
                return Ok(());
            }
            attempt = attempt.saturating_add(1);
            let delay_seconds = DELAYS[(attempt as usize - 1).min(DELAYS.len() - 1)];
            self.set_state(
                server_id,
                SshConnectionState::Reconnecting {
                    attempt,
                    delay_seconds,
                },
            )
            .await;
            tokio::select! {
                biased;
                () = self.closing.cancelled() => return Err(RemoteClientError::ManagerClosing),
                () = tokio::time::sleep(Duration::from_secs(delay_seconds)) => {}
            }
            if !self.desired_connections.read().await.contains(server_id) {
                return Ok(());
            }
            let endpoint = {
                let connection_lock = self.connection_lock(server_id).await;
                let _connection_guard = connection_lock.lock().await;
                let endpoint = self.endpoint(server_id).await?;
                match endpoint.ensure_ready().await {
                    Ok(()) => endpoint,
                    Err(RemoteClientError::ManagerClosing) => {
                        return Err(RemoteClientError::ManagerClosing);
                    }
                    Err(error) => {
                        tracing::warn!(alias = %server_id, %error, "SSH reconnect attempt failed");
                        continue;
                    }
                }
            };
            self.publish_ready(server_id, &endpoint).await;
            return Ok(());
        }
    }

    async fn publish_ready(&self, server_id: &str, endpoint: &Arc<Endpoint>) {
        let (helper_version, architecture) = endpoint.hello_identity().await.unwrap_or_default();
        self.set_state(
            server_id,
            SshConnectionState::Ready {
                helper_version,
                architecture,
            },
        )
        .await;
    }

    async fn close_endpoint(&self, server_id: &str) -> Result<(), RemoteClientError> {
        let endpoint = self.endpoints.lock().await.get(server_id).cloned();
        let Some(endpoint) = endpoint else {
            self.set_state(server_id, SshConnectionState::Disconnected)
                .await;
            return Ok(());
        };
        let result = endpoint.close("disconnect").await;
        match &result {
            Ok(()) => {
                self.endpoints.lock().await.remove(server_id);
                self.set_state(server_id, SshConnectionState::Disconnected)
                    .await;
            }
            Err(error) => {
                // A failed teardown keeps the endpoint (and its SSH processes) owned.
                self.set_state(
                    server_id,
                    SshConnectionState::Failed {
                        code: "sshCleanupFailed".to_string(),
                        message: error.to_string(),
                    },
                )
                .await;
            }
        }
        result
    }

    async fn ensure_state(&self, server_id: &str) -> watch::Sender<SshConnectionState> {
        if let Some(sender) = self.states.read().await.get(server_id).cloned() {
            return sender;
        }
        let mut states = self.states.write().await;
        states
            .entry(server_id.to_string())
            .or_insert_with(|| watch::channel(SshConnectionState::Disconnected).0)
            .clone()
    }

    async fn set_state(&self, server_id: &str, state: SshConnectionState) {
        let ready = matches!(state, SshConnectionState::Ready { .. });
        self.ensure_state(server_id).await.send_replace(state);
        if ready {
            self.ready_revisions.send_modify(|revisions| {
                let revision = revisions.entry(server_id.to_owned()).or_default();
                *revision = revision.saturating_add(1);
            });
        }
    }
}

fn execution_environment_from_hello(
    hello: &RemoteHello,
) -> Result<ExecutionEnvironment, RemoteClientError> {
    let os = match hello.os.to_ascii_lowercase().as_str() {
        "windows" => ExecutionOs::Windows,
        "linux" => ExecutionOs::Linux,
        "macos" | "darwin" => ExecutionOs::Macos,
        value => ExecutionOs::Other(value.to_string()),
    };
    let shell = match hello.shell.dialect {
        RemoteShellDialect::Bash => ShellDialect::Bash,
        RemoteShellDialect::Sh => ShellDialect::Sh,
        RemoteShellDialect::Pwsh => ShellDialect::Pwsh,
        RemoteShellDialect::PowerShell => ShellDialect::PowerShell,
        RemoteShellDialect::Cmd => ShellDialect::Cmd,
    };
    if hello.shell.path.trim().is_empty() {
        return Err(RemoteClientError::protocol(
            "helper hello returned an empty shell path",
        ));
    }
    Ok(ExecutionEnvironment::for_ssh(
        os,
        shell,
        hello.shell.path.clone(),
    ))
}
