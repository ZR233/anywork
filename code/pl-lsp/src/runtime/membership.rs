//! Bounded configuration discovery and per-server managed initialization.
use super::registry::join_task;
use super::{
    LspActivityKind, LspAvailabilityKind, LspLifecyclePhase, LspRuntimeRegistry,
    LspRuntimeServerState, LspServerSnapshot, ResolvedLspServer,
};
use crate::{
    catalog::{LspServerDocument, LspUserServerConfig, validate_server_id},
    client::{DiagnosticSink, LspClient},
    host::{LspHostBackend, LspPathStyle},
};
use std::{
    collections::BTreeMap,
    path::{Path, PathBuf},
    sync::Arc,
    time::Duration,
};
use tokio::sync::Mutex;
use tokio_util::sync::CancellationToken;

pub const MAX_LSP_CONFIGURATION_FILES: usize = 128;
pub const MAX_LSP_CONFIGURATION_BYTES: u64 = 256 * 1024;
const SCAN_TIMEOUT: Duration = Duration::from_secs(30);

struct Source {
    path: Option<String>,
    config: Result<LspUserServerConfig, String>,
}
impl LspRuntimeRegistry {
    pub(super) async fn bind_workspace(
        &self,
        root: &Path,
        host: Option<Arc<dyn LspHostBackend>>,
        defaults: BTreeMap<String, LspUserServerConfig>,
        directory: Option<PathBuf>,
    ) {
        let mut state = self.state.lock().await;
        if state.closed {
            return;
        }
        let workspace = state.workspaces.entry(root.to_owned()).or_default();
        let identity = host.as_ref().map(|host| host.identity());
        if workspace.configured
            && workspace.binding_identity == identity
            && workspace.defaults == defaults
            && workspace.defaults_directory == directory
        {
            return;
        }
        workspace.configured = true;
        if workspace.binding_identity != identity {
            for server in workspace.servers.values_mut() {
                server.cancel.cancel();
                if let Some(client) = &server.client {
                    client.cancel();
                }
                server.set_phase(
                    LspLifecyclePhase::Stopped,
                    Some("LSP execution host changed".into()),
                );
            }
        }
        workspace.host = host;
        workspace.binding_identity = identity;
        workspace.defaults = defaults;
        workspace.defaults_directory = directory;
        self.schedule_scan(&mut state, root);
    }
    /// Called by configuration mutation boundaries, never by snapshot/capability readers.
    pub async fn refresh_workspace_configuration(&self, root: impl AsRef<Path>) {
        let mut state = self.state.lock().await;
        if state.closed
            || !state
                .workspaces
                .get(root.as_ref())
                .is_some_and(|workspace| workspace.configured)
        {
            return;
        }
        self.schedule_scan(&mut state, root.as_ref());
    }

    /// Explicit retry differs from a passive refresh: retry only failed/exited
    /// members, preserving healthy processes with unchanged configuration.
    pub async fn retry_workspace_configuration(&self, root: impl AsRef<Path>) {
        let root = root.as_ref();
        let mut state = self.state.lock().await;
        if state.closed {
            return;
        }
        let Some(workspace) = state.workspaces.get_mut(root) else {
            return;
        };
        if !workspace.configured {
            return;
        }
        for server in workspace.servers.values_mut() {
            if server.phase == LspLifecyclePhase::Failed
                || (server.phase == LspLifecyclePhase::Ready && !server.healthy())
            {
                server.cancel.cancel();
                if let Some(client) = &server.client {
                    client.cancel();
                }
            }
        }
        self.schedule_scan(&mut state, root);
    }
    fn schedule_scan(&self, state: &mut super::registry::LspRuntimeState, root: &Path) {
        use futures::FutureExt;
        let workspace = state.workspaces.get_mut(root).expect("bound workspace");
        workspace.tasks.retain(|task| {
            let Ok(mut task) = task.try_lock() else {
                return true;
            };
            let Some(handle) = task.as_mut() else {
                return false;
            };
            if !handle.is_finished() {
                return true;
            }
            match handle.now_or_never() {
                Some(Ok(())) => {
                    task.take();
                    false
                }
                Some(Err(error)) => {
                    tracing::warn!(%error, "LSP background task failed");
                    task.take();
                    false
                }
                None => true,
            }
        });
        workspace.retiring.retain(|_, (task, client)| {
            !(client.reclaimed()
                && task
                    .try_lock()
                    .is_ok_and(|task| task.as_ref().is_none_or(|task| task.is_finished())))
        });
        workspace.scan_cancel.cancel();
        workspace.scan_cancel = CancellationToken::new();
        workspace.scan_generation += 1;
        workspace.scan_pending = true;
        let generation = workspace.scan_generation;
        let cancel = workspace.scan_cancel.clone();
        let host = workspace.host.clone();
        let defaults = workspace.defaults.clone();
        let directory = workspace.defaults_directory.clone();
        let mut loading_changed = false;
        if !workspace.has_scanned && workspace.servers.is_empty() {
            let previous = workspace.errors.clone();
            workspace.errors = vec![configuration_error(
                "_configuration",
                None,
                LspLifecyclePhase::Loading,
                "Loading LSP configuration",
            )];
            loading_changed = previous != workspace.errors;
        }
        let registry = self.clone();
        let root = root.to_owned();
        let task = tokio::spawn(async move {
            let scan = async {
                let defaults_exceeded = defaults.len() > MAX_LSP_CONFIGURATION_FILES;
                let mut sources: BTreeMap<String, Source> = defaults
                    .into_iter()
                    .take(MAX_LSP_CONFIGURATION_FILES)
                    .map(|(id, config)| {
                        let result = validate_server_id(&id)
                            .and_then(|_| config.validate())
                            .map(|_| config)
                            .map_err(|error| error.to_string());
                        (
                            id,
                            Source {
                                path: None,
                                config: result,
                            },
                        )
                    })
                    .collect();
                let mut count = sources.len();
                let mut errors = Vec::new();
                if defaults_exceeded {
                    errors.push(configuration_error(
                        "_configuration",
                        None,
                        LspLifecyclePhase::Failed,
                        "LSP default configuration limit exceeded (128 total)",
                    ));
                }
                if let Some(directory) = directory {
                    scan_directory(&directory, None, &mut sources, &mut errors, &mut count).await;
                }
                scan_directory(
                    &root.join(".anywork/lsp"),
                    host.as_deref(),
                    &mut sources,
                    &mut errors,
                    &mut count,
                )
                .await;
                let mut members = BTreeMap::new();
                for (id, source) in sources {
                    match source.config {
                        Err(message) => errors.push(configuration_error(
                            &id,
                            source.path,
                            LspLifecyclePhase::Failed,
                            &message,
                        )),
                        Ok(config) => {
                            let matched =
                                match workspace_matches(&config.detection, &root, host.as_deref())
                                    .await
                                {
                                    Ok(matched) => matched,
                                    Err(error) => {
                                        errors.push(configuration_error(
                                            &id,
                                            source.path,
                                            LspLifecyclePhase::Failed,
                                            &error,
                                        ));
                                        continue;
                                    }
                                };
                            let config = config.render(&root);
                            let catalog = config.to_catalog_server(&id);
                            let fingerprint = serde_json::to_string(&(
                                catalog.definition.clone(),
                                matched,
                                host.as_ref().map(|host| host.identity()),
                            ))
                            .expect("serializable definition");
                            members.insert(id, (source.path, catalog, matched, fingerprint));
                        }
                    }
                }
                (members, errors)
            };
            let result = tokio::select! {
                biased;
                _ = cancel.cancelled() => return,
                result = tokio::time::timeout(SCAN_TIMEOUT, scan) => result,
            };
            let (members, errors) = match result {
                Ok(result) => result,
                Err(_) => {
                    let mut state = registry.state.lock().await;
                    if let Some(workspace) = state.workspaces.get_mut(&root)
                        && workspace.scan_generation == generation
                    {
                        workspace.has_scanned = true;
                        workspace.scan_pending = false;
                        workspace.errors = vec![configuration_error(
                            "_configuration",
                            None,
                            LspLifecyclePhase::Failed,
                            "LSP configuration scan timed out",
                        )];
                    }
                    registry.emit_update();
                    return;
                }
            };
            let mut state = registry.state.lock().await;
            if state.closed || cancel.is_cancelled() {
                return;
            }
            let Some(workspace) = state.workspaces.get_mut(&root) else {
                return;
            };
            if workspace.scan_generation != generation {
                return;
            }
            workspace.errors = errors;
            workspace.has_scanned = true;
            workspace.scan_pending = false;
            let mut old = std::mem::take(&mut workspace.servers);
            let mut tasks = Vec::new();
            for (id, (path, catalog, matched, fingerprint)) in members {
                if let Some(current) = old.get(&id)
                    && current.fingerprint == fingerprint
                    && !current.cancel.is_cancelled()
                {
                    let mut current = old.remove(&id).expect("existing member");
                    current.configuration_path = path;
                    workspace.servers.insert(id, current);
                    continue;
                }
                let previous = old.remove(&id);
                if let Some(previous) = previous {
                    previous.cancel.cancel();
                    if let Some(client) = previous.client {
                        client.cancel();
                        if let Some(task) = previous.task {
                            workspace.retiring.insert(id.clone(), (task, client));
                        }
                    }
                }
                let previous = workspace.retiring.get(&id).cloned();
                let definition = &catalog.definition;
                let command = catalog.driver.resolve_command(definition, &root);
                let resolved = ResolvedLspServer {
                    id: id.clone(),
                    display_name: definition.display_name.clone(),
                    program: command.program,
                    args: command.args,
                    env: definition.env.clone(),
                    settings: definition.settings.clone(),
                    extensions: definition.extensions.clone(),
                    language_ids: definition.language_ids.clone(),
                    operations: definition.operations.clone(),
                    workspace_root: root.clone(),
                };
                workspace.member_generation += 1;
                let member_generation = workspace.member_generation;
                let cancel = CancellationToken::new();
                let diagnostics = Arc::new(Mutex::new(std::collections::HashMap::new()));
                let mut server = LspRuntimeServerState {
                    diagnostics: diagnostics.clone(),
                    resolved: resolved.clone(),
                    fingerprint,
                    configuration_path: path,
                    phase: LspLifecyclePhase::Loading,
                    availability_kind: LspAvailabilityKind::Checking,
                    availability_message: None,
                    last_checked_at: None,
                    client: None,
                    generation: member_generation,
                    cancel: cancel.clone(),
                    task: None,
                };
                if matched {
                    let sink = DiagnosticSink::new(
                        id.clone(),
                        root.clone(),
                        diagnostics.clone(),
                        registry.updates.clone(),
                        host.as_ref()
                            .map_or(LspPathStyle::Native, |host| host.path_style()),
                    );
                    let client =
                        Arc::new(LspClient::new(resolved, catalog.driver, sink, host.clone()));
                    server.client = Some(client.clone());
                    let owner = registry.clone();
                    let root = root.clone();
                    let task = Arc::new(Mutex::new(Some(tokio::spawn(async move {
                        if let Some((task, previous)) = previous {
                            let joined = join_task(&task).await;
                            if joined.is_err() || !previous.reclaimed() {
                                owner
                                    .publish_phase(
                                        &root,
                                        &id,
                                        member_generation,
                                        LspLifecyclePhase::Failed,
                                        Some(
                                            "previous LSP process reclamation was not confirmed"
                                                .into(),
                                        ),
                                    )
                                    .await;
                                return;
                            }
                        }
                        owner
                            .run_member(root, id, member_generation, client, cancel)
                            .await;
                    }))));
                    server.task = Some(task.clone());
                    tasks.push(task);
                } else {
                    server.set_phase(
                        LspLifecyclePhase::Disabled,
                        Some("workspace does not match detection rules".into()),
                    );
                }
                workspace.servers.insert(server.resolved.id.clone(), server);
            }
            for previous in old.into_values() {
                previous.cancel.cancel();
                if let Some(client) = previous.client {
                    client.cancel();
                    if let Some(task) = previous.task {
                        workspace
                            .retiring
                            .insert(previous.resolved.id, (task, client));
                    }
                }
            }
            workspace.tasks.extend(tasks);
            // Completion also wakes explicit probes when membership is unchanged.
            registry.emit_update();
        });
        workspace.tasks.push(Arc::new(Mutex::new(Some(task))));
        if loading_changed {
            self.emit_update();
        }
    }
    async fn publish_phase(
        &self,
        root: &Path,
        id: &str,
        generation: u64,
        phase: LspLifecyclePhase,
        message: Option<String>,
    ) {
        let mut state = self.state.lock().await;
        if let Some(server) = state
            .workspaces
            .get_mut(root)
            .and_then(|workspace| workspace.servers.get_mut(id))
            && server.generation == generation
        {
            server.set_phase(phase, message);
            self.emit_update();
        }
    }
    async fn run_member(
        &self,
        root: PathBuf,
        id: String,
        generation: u64,
        client: Arc<LspClient>,
        cancel: CancellationToken,
    ) {
        if !cancel.is_cancelled() {
            self.publish_phase(&root, &id, generation, LspLifecyclePhase::Starting, None)
                .await;
            let mut stages = client.startup_updates();
            let start = client.start();
            tokio::pin!(start);
            let result = loop {
                tokio::select! {
                    result = &mut start => break result,
                    _ = cancel.cancelled() => { client.cancel(); break start.await; }
                    _ = stages.changed() => {
                        let phase = *stages.borrow_and_update();
                        self.publish_phase(&root, &id, generation, phase, None).await;
                    }
                }
            };
            match result {
                Ok(()) if !cancel.is_cancelled() => {
                    let mut updates = self.subscribe();
                    self.publish_phase(&root, &id, generation, LspLifecyclePhase::Ready, None)
                        .await;
                    loop {
                        if !client.is_ready() {
                            self.publish_phase(
                                &root,
                                &id,
                                generation,
                                LspLifecyclePhase::Failed,
                                Some("LSP connection closed".into()),
                            )
                            .await;
                            break;
                        }
                        tokio::select! { _ = cancel.cancelled() => break, _ = updates.recv() => {} }
                    }
                }
                Err(error) if !cancel.is_cancelled() => {
                    self.publish_phase(
                        &root,
                        &id,
                        generation,
                        LspLifecyclePhase::Failed,
                        Some(error.to_string()),
                    )
                    .await
                }
                _ => {}
            }
        }
        client.cancel();
        if let Err(error) = client.shutdown().await {
            if let Some(workspace) = self.state.lock().await.workspaces.get_mut(&root) {
                workspace.retired_clients.push(client);
            }
            self.publish_phase(
                &root,
                &id,
                generation,
                LspLifecyclePhase::Failed,
                Some(error.to_string()),
            )
            .await;
        } else if cancel.is_cancelled() {
            self.publish_phase(&root, &id, generation, LspLifecyclePhase::Stopped, None)
                .await;
        }
    }
}

async fn scan_directory(
    directory: &Path,
    host: Option<&dyn LspHostBackend>,
    sources: &mut BTreeMap<String, Source>,
    errors: &mut Vec<LspServerSnapshot>,
    count: &mut usize,
) {
    let names = match directory_names(directory, host).await {
        Ok(names) => names,
        Err(message) => {
            errors.push(configuration_error(
                "_configuration",
                Some(directory.display().to_string()),
                LspLifecyclePhase::Failed,
                &message,
            ));
            return;
        }
    };
    for name in names {
        let Some(id) = name.strip_suffix(".toml") else {
            continue;
        };
        *count += 1;
        if *count > MAX_LSP_CONFIGURATION_FILES {
            errors.push(configuration_error(
                "_configuration",
                Some(directory.display().to_string()),
                LspLifecyclePhase::Failed,
                "LSP configuration file limit exceeded (128 total)",
            ));
            break;
        }
        let path = directory.join(&name);
        let result = async {
            validate_server_id(id).map_err(|error| error.to_string())?;
            let bytes = read_document(&path, host).await?;
            let text = std::str::from_utf8(&bytes)
                .map_err(|_| "LSP configuration is not UTF-8".to_string())?;
            let document = LspServerDocument::parse(text).map_err(|error| error.to_string())?;
            if document.id != id {
                return Err("server id does not match configuration filename".into());
            }
            Ok(document.config)
        }
        .await;
        sources.insert(
            id.to_string(),
            Source {
                path: Some(path.display().to_string()),
                config: result,
            },
        );
    }
}
async fn directory_names(
    path: &Path,
    host: Option<&dyn LspHostBackend>,
) -> Result<Vec<String>, String> {
    let mut names = if let Some(host) = host {
        if host
            .stat(path)
            .await
            .map_err(|error| error.to_string())?
            .is_none()
        {
            return Ok(Vec::new());
        }
        host.list_directory(path, MAX_LSP_CONFIGURATION_FILES)
            .await
            .map_err(|error| error.to_string())?
    } else {
        let mut directory = match tokio::fs::read_dir(path).await {
            Ok(directory) => directory,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(error) => return Err(error.to_string()),
        };
        let mut names = Vec::new();
        while let Some(entry) = directory
            .next_entry()
            .await
            .map_err(|error| error.to_string())?
        {
            if names.len() == MAX_LSP_CONFIGURATION_FILES {
                return Err("LSP configuration directory entry limit exceeded (128)".into());
            }
            names.push(entry.file_name().to_string_lossy().into_owned());
        }
        names
    };
    names.sort();
    Ok(names)
}
async fn read_document(path: &Path, host: Option<&dyn LspHostBackend>) -> Result<Vec<u8>, String> {
    if let Some(host) = host {
        return host
            .read_file(path, MAX_LSP_CONFIGURATION_BYTES)
            .await
            .map_err(|error| error.to_string());
    }
    use tokio::io::AsyncReadExt;
    let file = tokio::fs::File::open(path)
        .await
        .map_err(|error| error.to_string())?;
    if !file
        .metadata()
        .await
        .map_err(|error| error.to_string())?
        .is_file()
    {
        return Err("LSP configuration is not a regular file".into());
    }
    let mut bytes = Vec::new();
    file.take(MAX_LSP_CONFIGURATION_BYTES + 1)
        .read_to_end(&mut bytes)
        .await
        .map_err(|error| error.to_string())?;
    if bytes.len() as u64 > MAX_LSP_CONFIGURATION_BYTES {
        return Err("LSP configuration exceeds 256 KiB".into());
    }
    Ok(bytes)
}
async fn workspace_matches(
    rules: &[String],
    root: &Path,
    host: Option<&dyn LspHostBackend>,
) -> Result<bool, String> {
    if rules.is_empty() {
        return Ok(true);
    }
    if let Some(host) = host {
        let entries = if rules.iter().any(|rule| rule.contains('*')) {
            Some(
                host.list_directory(root, 10_000)
                    .await
                    .map_err(|error| error.to_string())?,
            )
        } else {
            None
        };
        for rule in rules {
            if rule.contains('*') {
                if entries.as_ref().is_some_and(|entries| {
                    entries
                        .iter()
                        .any(|name| crate::catalog::glob_match(rule, name))
                }) {
                    return Ok(true);
                }
            } else if host
                .stat(&root.join(rule))
                .await
                .map_err(|error| error.to_string())?
                .is_some()
            {
                return Ok(true);
            }
        }
        Ok(false)
    } else {
        let mut names = Vec::new();
        if rules.iter().any(|rule| rule.contains('*')) {
            let mut directory = tokio::fs::read_dir(root)
                .await
                .map_err(|error| error.to_string())?;
            while let Some(entry) = directory
                .next_entry()
                .await
                .map_err(|error| error.to_string())?
            {
                if names.len() == 10_000 {
                    return Err("LSP detection directory exceeds 10000 entries".into());
                }
                names.push(entry.file_name().to_string_lossy().into_owned());
            }
        }
        for rule in rules {
            if rule.contains('*') {
                if names
                    .iter()
                    .any(|name| crate::catalog::glob_match(rule, name))
                {
                    return Ok(true);
                }
            } else {
                match tokio::fs::metadata(root.join(rule)).await {
                    Ok(_) => return Ok(true),
                    Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
                    Err(error) => return Err(error.to_string()),
                }
            }
        }
        Ok(false)
    }
}
fn configuration_error(
    id: &str,
    path: Option<String>,
    phase: LspLifecyclePhase,
    message: &str,
) -> LspServerSnapshot {
    LspServerSnapshot {
        id: id.into(),
        configuration_path: path,
        phase,
        display_name: id.into(),
        extensions: Vec::new(),
        language_ids: Vec::new(),
        availability_kind: if phase == LspLifecyclePhase::Loading {
            LspAvailabilityKind::Checking
        } else {
            LspAvailabilityKind::Unavailable
        },
        availability_message: Some(message.into()),
        last_checked_at: None,
        diagnostic_count: 0,
        activity_kind: LspActivityKind::Idle,
        activity_title: None,
        activity_message: None,
        activity_percentage: None,
        last_error: if phase == LspLifecyclePhase::Failed {
            Some(message.into())
        } else {
            None
        },
        last_error_at: None,
    }
}
