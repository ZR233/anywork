//! ConfigRuntime-owned ACP resource. Queries are cache-only; mutations are serialized by its command lock.
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use tokio::sync::watch;

use super::acp::{AcpServiceDefinition, validate_acp_account_id};
use super::{ConfigPaths, document_revision};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcpDefinitionEntry {
    pub definition: AcpServiceDefinition,
    pub document_revision: u64,
    pub connection_revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcpDefinitionDiagnostic {
    pub path: PathBuf,
    pub id: Option<String>,
    pub message: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AcpDefinitionsSnapshot {
    pub revision: u64,
    pub definitions: BTreeMap<String, AcpDefinitionEntry>,
    pub diagnostics: Vec<AcpDefinitionDiagnostic>,
}

#[derive(Debug, thiserror::Error)]
pub enum AcpDefinitionError {
    #[error("ACP definition is unavailable")]
    Unavailable,
    #[error("ACP connection revision is stale")]
    StaleConnection,
    #[error("ACP document revision is stale")]
    StaleDocument,
    #[error("invalid ACP definition: {0}")]
    Invalid(String),
    #[error("ACP file operation failed ({0})")]
    Io(#[source] std::io::Error),
}

impl From<std::io::Error> for AcpDefinitionError {
    fn from(error: std::io::Error) -> Self {
        // Preserve the typed OS cause and code, never a caller-supplied error payload.
        Self::Io(error.raw_os_error().map_or_else(
            || std::io::Error::from(error.kind()),
            std::io::Error::from_raw_os_error,
        ))
    }
}

impl AcpDefinitionsSnapshot {
    /// Clone at admission to freeze the definition for the full lifetime of a business instance.
    /// Later reload, disable or delete does not mutate this value or terminate its consumer.
    pub fn resolve(
        &self,
        id: &str,
        expected_connection_revision: u64,
    ) -> Result<AcpServiceDefinition, AcpDefinitionError> {
        let entry = self
            .definitions
            .get(id)
            .ok_or(AcpDefinitionError::Unavailable)?;
        if !entry.definition.enabled {
            return Err(AcpDefinitionError::Unavailable);
        }
        if entry.connection_revision != expected_connection_revision {
            return Err(AcpDefinitionError::StaleConnection);
        }
        Ok(entry.definition.clone())
    }
}

struct State {
    snapshot: AcpDefinitionsSnapshot,
    // Kept after deletion: re-adding an id cannot revive a previously admitted revision.
    next_connection_revision: u64,
}

#[derive(Clone)]
pub struct AcpDefinitionsResource {
    state: Arc<Mutex<State>>,
    updates: Arc<watch::Sender<u64>>,
}

impl AcpDefinitionsResource {
    pub(crate) fn new(paths: &ConfigPaths) -> Self {
        let (updates, _) = watch::channel(0);
        let resource = Self {
            state: Arc::new(Mutex::new(State {
                snapshot: AcpDefinitionsSnapshot::default(),
                next_connection_revision: 0,
            })),
            updates: Arc::new(updates),
        };
        resource.reload(paths);
        resource
    }

    pub fn read(&self) -> AcpDefinitionsSnapshot {
        self.state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .snapshot
            .clone()
    }

    pub fn subscribe(&self) -> watch::Receiver<u64> {
        self.updates.subscribe()
    }

    pub fn resolve(
        &self,
        id: &str,
        expected_connection_revision: u64,
    ) -> Result<AcpServiceDefinition, AcpDefinitionError> {
        self.read().resolve(id, expected_connection_revision)
    }

    pub(crate) fn reload(&self, paths: &ConfigPaths) -> AcpDefinitionsSnapshot {
        self.adopt_snapshot(scan(paths))
    }

    fn adopt_snapshot(&self, mut scanned: AcpDefinitionsSnapshot) -> AcpDefinitionsSnapshot {
        let mut state = self
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        for (id, entry) in &mut scanned.definitions {
            if let Some(previous) = state.snapshot.definitions.get(id)
                && previous.definition.same_connection(&entry.definition)
            {
                entry.connection_revision = previous.connection_revision;
            } else {
                state.next_connection_revision = state
                    .next_connection_revision
                    .checked_add(1)
                    .expect("ACP connection revision exhausted");
                entry.connection_revision = state.next_connection_revision;
            }
        }
        scanned.revision = state.snapshot.revision;
        if scanned != state.snapshot || scanned.revision == 0 {
            scanned.revision = scanned
                .revision
                .checked_add(1)
                .expect("ACP resource revision exhausted");
            state.snapshot = scanned;
            self.updates.send_replace(state.snapshot.revision);
        }
        state.snapshot.clone()
    }

    pub(crate) fn save(
        &self,
        paths: &ConfigPaths,
        definition: &AcpServiceDefinition,
        expected: Option<u64>,
    ) -> Result<AcpDefinitionsSnapshot, AcpDefinitionError> {
        definition
            .validate()
            .map_err(|error| AcpDefinitionError::Invalid(error.to_string()))?;
        let path = paths.acp_dir().join(format!("{}.toml", definition.id));
        ensure_regular_directory(&paths.acp_dir())?;
        check_revision(&path, &definition.id, expected)?;
        let content = definition
            .encode()
            .map_err(|error| AcpDefinitionError::Invalid(error.to_string()))?;
        fs::create_dir_all(paths.acp_dir())?;
        pl_tool::workspace::write_file_atomically(&path, content.as_bytes())
            .map_err(AcpDefinitionError::from)?;
        // A single-document command adopts only its own durable bytes. Unrelated external
        // edits, additions and diagnostics remain unpublished until explicit reload.
        let mut next = self.read();
        next.diagnostics
            .retain(|diagnostic| diagnostic.path != path);
        if next
            .diagnostics
            .iter()
            .any(|diagnostic| diagnostic.id.as_deref() == Some(definition.id.as_str()))
        {
            // A previously published foreign file still claims this id. Saving the target
            // must not silently give it precedence over that cached conflict.
            next.definitions.remove(&definition.id);
            next.diagnostics.push(AcpDefinitionDiagnostic {
                path,
                id: Some(definition.id.clone()),
                message: "conflicting ACP definition id; no file takes precedence".into(),
            });
        } else {
            next.definitions.insert(
                definition.id.clone(),
                AcpDefinitionEntry {
                    definition: definition.clone(),
                    document_revision: document_revision(
                        &format!("acp/{}.toml", definition.id),
                        content.as_bytes(),
                    ),
                    connection_revision: 0,
                },
            );
        }
        Ok(self.adopt_snapshot(next))
    }

    pub(crate) fn delete(
        &self,
        paths: &ConfigPaths,
        id: &str,
        expected: u64,
    ) -> Result<AcpDefinitionsSnapshot, AcpDefinitionError> {
        validate_acp_account_id(id)
            .map_err(|error| AcpDefinitionError::Invalid(error.to_string()))?;
        ensure_regular_directory(&paths.acp_dir())?;
        let path = paths.acp_dir().join(format!("{id}.toml"));
        check_revision(&path, id, Some(expected))?;
        fs::remove_file(&path)?;
        let mut next = self.read();
        next.definitions.remove(id);
        next.diagnostics
            .retain(|diagnostic| diagnostic.path != path);
        Ok(self.adopt_snapshot(next))
    }
}

fn ensure_regular_directory(path: &Path) -> Result<(), AcpDefinitionError> {
    match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_dir() && !metadata.file_type().is_symlink() => Ok(()),
        Ok(_) => Err(AcpDefinitionError::Invalid(
            "ACP directory must be a regular directory".into(),
        )),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error.into()),
    }
}

fn check_revision(path: &Path, id: &str, expected: Option<u64>) -> Result<(), AcpDefinitionError> {
    let actual = match fs::symlink_metadata(path) {
        Ok(metadata) if metadata.is_file() && !metadata.file_type().is_symlink() => Some(
            document_revision(&format!("acp/{id}.toml"), &fs::read(path)?),
        ),
        Ok(_) => {
            return Err(AcpDefinitionError::Invalid(
                "ACP document must be a regular file".into(),
            ));
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => None,
        Err(error) => return Err(error.into()),
    };
    if actual != expected {
        return Err(AcpDefinitionError::StaleDocument);
    }
    Ok(())
}

/// Startup/reload scanner. No recursion, workspace search or implicit command preparation.
pub(crate) fn scan(paths: &ConfigPaths) -> AcpDefinitionsSnapshot {
    let mut snapshot = AcpDefinitionsSnapshot::default();
    let directory = paths.acp_dir();
    let mut diagnose = |path, id, message| {
        snapshot
            .diagnostics
            .push(AcpDefinitionDiagnostic { path, id, message });
    };
    if let Err(error) = ensure_regular_directory(&directory) {
        diagnose(directory, None, error.to_string());
        return snapshot;
    }
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return snapshot,
        Err(error) => {
            diagnose(directory, None, AcpDefinitionError::from(error).to_string());
            return snapshot;
        }
    };
    let mut paths = Vec::new();
    for entry in entries {
        match entry {
            Ok(entry) => paths.push(entry.path()),
            Err(error) => diagnose(
                directory.clone(),
                None,
                AcpDefinitionError::from(error).to_string(),
            ),
        }
    }
    paths.sort();
    let mut claims: BTreeMap<String, Vec<PathBuf>> = BTreeMap::new();
    for path in paths {
        if path.extension().and_then(|s| s.to_str()) != Some("toml") {
            continue;
        }
        let id = path.file_stem().and_then(|s| s.to_str()).map(str::to_owned);
        let parsed = (|| {
            let id = id
                .as_deref()
                .ok_or_else(|| AcpDefinitionError::Invalid("non-UTF-8 ACP filename".into()))?;
            validate_acp_account_id(id).map_err(|e| AcpDefinitionError::Invalid(e.to_string()))?;
            let metadata = fs::symlink_metadata(&path)?;
            if !metadata.is_file() || metadata.file_type().is_symlink() {
                return Err(AcpDefinitionError::Invalid(
                    "ACP document must be a regular file".into(),
                ));
            }
            let bytes = fs::read(&path)?;
            let content = std::str::from_utf8(&bytes)
                .map_err(|_| AcpDefinitionError::Invalid("ACP document is not UTF-8".into()))?;
            if let Ok(raw) = toml::from_str::<toml::Value>(content)
                && let Some(claim) = raw.get("id").and_then(toml::Value::as_str)
                && validate_acp_account_id(claim).is_ok()
            {
                claims.entry(claim.into()).or_default().push(path.clone());
            }
            let definition = AcpServiceDefinition::decode(content, id)
                .map_err(|e| AcpDefinitionError::Invalid(e.to_string()))?;
            Ok((
                id.to_owned(),
                AcpDefinitionEntry {
                    definition,
                    document_revision: document_revision(&format!("acp/{id}.toml"), &bytes),
                    connection_revision: 0,
                },
            ))
        })();
        match parsed {
            Ok((id, entry)) => {
                snapshot.definitions.insert(id, entry);
            }
            Err(error) => snapshot.diagnostics.push(AcpDefinitionDiagnostic {
                path,
                id: id.filter(|value| validate_acp_account_id(value).is_ok()),
                message: error.to_string(),
            }),
        }
    }
    for (id, paths) in claims {
        if paths.len() < 2 {
            continue;
        }
        snapshot.definitions.remove(&id);
        for path in paths {
            snapshot.diagnostics.push(AcpDefinitionDiagnostic {
                path,
                id: Some(id.clone()),
                message: "conflicting ACP definition id; no file takes precedence".into(),
            });
        }
    }
    snapshot
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::config::{AcpLaunch, ConfigRuntime, ConfigRuntimeError, ConfigStore};

    fn command(id: &str) -> AcpServiceDefinition {
        AcpServiceDefinition {
            id: id.into(),
            display_name: id.into(),
            enabled: true,
            launch: AcpLaunch::Command {
                command: "synthetic-agent".into(),
                args: vec!["literal $HOME".into()],
            },
            env: BTreeMap::from([("SYNTHETIC_SECRET".into(), "not-for-diagnostics".into())]),
        }
    }

    #[test]
    fn api_errors_keep_categories_and_safe_typed_io_sources() {
        use pl_protocol::studio::StudioErrorCode;
        for (error, expected) in [
            (
                AcpDefinitionError::StaleDocument,
                StudioErrorCode::StaleRevision,
            ),
            (
                AcpDefinitionError::StaleConnection,
                StudioErrorCode::StaleRevision,
            ),
            (AcpDefinitionError::Unavailable, StudioErrorCode::NotFound),
            (
                AcpDefinitionError::Invalid("safe validation reason".into()),
                StudioErrorCode::InvalidArgument,
            ),
            (
                AcpDefinitionError::from(std::io::Error::new(
                    std::io::ErrorKind::PermissionDenied,
                    "private-env-sentinel",
                )),
                StudioErrorCode::Storage,
            ),
        ] {
            let error = anyhow::Error::new(ConfigRuntimeError::from(error));
            assert_eq!(
                crate::error_mapping::studio_error_from_anyhow_ref(&error).code,
                expected
            );
            assert!(!format!("{error:#} {error:?}").contains("private-env-sentinel"));
        }
        let error = AcpDefinitionError::from(std::io::Error::from_raw_os_error(13));
        let source = std::error::Error::source(&error).expect("typed IO source retained");
        assert_eq!(
            source
                .downcast_ref::<std::io::Error>()
                .unwrap()
                .raw_os_error(),
            Some(13)
        );
    }

    #[test]
    fn queries_are_pure_and_only_explicit_reload_reads_user_directory() {
        let temp = tempfile::tempdir().unwrap();
        let home = temp.path().join("home");
        let runtime =
            ConfigRuntime::initialize(ConfigStore::new(ConfigPaths::from_config_dir(&home)))
                .unwrap();
        let mut changes = runtime.subscribe_acp_definitions();
        let initial = runtime.read_acp_definitions();
        assert!(initial.definitions.is_empty());
        assert!(!home.join("acp").exists());
        // Definitions in workspace/parent trees are never searched.
        fs::create_dir_all(temp.path().join("acp")).unwrap();
        fs::write(
            temp.path().join("acp/ignored.toml"),
            command("ignored").encode().unwrap(),
        )
        .unwrap();
        fs::create_dir_all(home.join("acp")).unwrap();
        fs::write(
            home.join("acp/healthy.toml"),
            command("healthy").encode().unwrap(),
        )
        .unwrap();
        fs::write(home.join("acp/bad.toml"), "schema_version=1\nid='bad'\ncommand='agent'\nenv={ token = [ 'not-for-diagnostics' ] }").unwrap();
        assert_eq!(runtime.read_acp_definitions(), initial);
        assert!(!changes.has_changed().unwrap());
        let published = runtime.reload_acp_definitions().unwrap().acp;
        assert!(changes.has_changed().unwrap());
        changes.borrow_and_update();
        assert_eq!(
            published.definitions.keys().collect::<Vec<_>>(),
            vec!["healthy"]
        );
        assert_eq!(published.diagnostics.len(), 1);
        assert!(!format!("{:?}", published.diagnostics).contains("not-for-diagnostics"));
        runtime.reload_acp_definitions().unwrap();
        assert!(!changes.has_changed().unwrap());
    }

    #[test]
    fn document_cas_connection_identity_and_frozen_admission_are_independent() {
        let temp = tempfile::tempdir().unwrap();
        let runtime =
            ConfigRuntime::initialize(ConfigStore::new(ConfigPaths::from_config_dir(temp.path())))
                .unwrap();
        let first = command("stable");
        let saved = runtime
            .save_acp_definition(runtime.read().unwrap().revision, &first, None)
            .unwrap();
        let entry = saved.acp.definitions["stable"].clone();
        let frozen = runtime
            .resolve_acp_definition("stable", entry.connection_revision)
            .unwrap();
        let mut renamed = first.clone();
        renamed.display_name = "Renamed".into();
        let renamed_state = runtime
            .save_acp_definition(saved.revision, &renamed, Some(entry.document_revision))
            .unwrap();
        let renamed_entry = &renamed_state.acp.definitions["stable"];
        assert_eq!(renamed_entry.connection_revision, entry.connection_revision);
        assert_ne!(renamed_entry.document_revision, entry.document_revision);
        // External edits are not silently overwritten even when the published resource is unchanged.
        let path = temp.path().join("acp/stable.toml");
        let external = format!("# external\n{}", renamed.encode().unwrap());
        fs::write(&path, &external).unwrap();
        assert!(matches!(
            runtime.save_acp_definition(
                renamed_state.revision,
                &renamed,
                Some(renamed_entry.document_revision)
            ),
            Err(ConfigRuntimeError::AcpDefinition(
                AcpDefinitionError::StaleDocument
            ))
        ));
        assert_eq!(fs::read_to_string(&path).unwrap(), external);
        let current = runtime.reload_acp_definitions().unwrap();
        let mut changed = renamed;
        changed
            .env
            .insert("SYNTHETIC_SECRET".into(), "new-value".into());
        let next = runtime
            .save_acp_definition(
                current.revision,
                &changed,
                Some(current.acp.definitions["stable"].document_revision),
            )
            .unwrap();
        assert_ne!(
            next.acp.definitions["stable"].connection_revision,
            entry.connection_revision
        );
        assert!(matches!(
            runtime.resolve_acp_definition("stable", entry.connection_revision),
            Err(AcpDefinitionError::StaleConnection)
        ));
        assert_eq!(frozen, first);
        let revision = next.acp.definitions["stable"].connection_revision;
        let deleted = runtime
            .delete_acp_definition(
                next.revision,
                "stable",
                next.acp.definitions["stable"].document_revision,
            )
            .unwrap();
        assert!(runtime.resolve_acp_definition("stable", revision).is_err());
        let readded = runtime
            .save_acp_definition(deleted.revision, &first, None)
            .unwrap();
        assert!(readded.acp.definitions["stable"].connection_revision > revision);
        assert_eq!(frozen, first);
        assert!(
            !fs::read_to_string(path)
                .unwrap()
                .contains("connection_revision")
        );
        assert!(!temp.path().join("config.toml").exists());
    }

    #[test]
    fn duplicate_ids_have_no_precedence_and_do_not_hide_other_services() {
        let temp = tempfile::tempdir().unwrap();
        let paths = ConfigPaths::from_config_dir(temp.path());
        fs::create_dir_all(paths.acp_dir()).unwrap();
        let healthy = command("healthy").encode().unwrap();
        fs::write(paths.acp_dir().join("healthy.toml"), &healthy).unwrap();
        fs::write(paths.acp_dir().join("conflicting.toml"), &healthy).unwrap();
        fs::write(
            paths.acp_dir().join("independent.toml"),
            command("independent").encode().unwrap(),
        )
        .unwrap();
        let snapshot = AcpDefinitionsResource::new(&paths).read();
        assert!(!snapshot.definitions.contains_key("healthy"));
        assert!(snapshot.definitions.contains_key("independent"));
        assert!(
            snapshot
                .diagnostics
                .iter()
                .any(|d| d.id.as_deref() == Some("healthy"))
        );
    }

    #[test]
    fn document_shape_is_strict_and_safe() {
        for id in ["", ".", "..", "space id", "../escape", "非ASCII"] {
            assert!(validate_acp_account_id(id).is_err(), "{id}");
        }
        let minimal = "schema_version=1\nid='user.one-2_3'\ncommand='agent'";
        let decoded = AcpServiceDefinition::decode(minimal, "user.one-2_3").unwrap();
        assert!(decoded.enabled);
        assert_eq!(decoded.display_name, decoded.id);
        for extra in [
            "cwd='/secret'",
            "provider='vendor'",
            "models=['secret']",
            "template='antigravity'",
            "schema=999",
        ] {
            let error =
                AcpServiceDefinition::decode(&format!("{minimal}\n{extra}"), "user.one-2_3")
                    .unwrap_err();
            assert!(!error.to_string().contains("secret"));
        }
        assert!(
            AcpServiceDefinition::decode(
                "schema_version=1\nid='x'\ntemplate='antigravity'\nargs=[]",
                "x"
            )
            .is_err()
        );
        assert!(
            AcpServiceDefinition::decode("schema_version=2\nid='x'\ncommand='agent'", "x").is_err()
        );
        assert!(AcpServiceDefinition::decode("schema_version=1\nid='x'", "x").is_err());
    }

    #[test]
    fn single_document_commands_preserve_unreloaded_definitions_and_diagnostics() {
        for external_change in ["edit", "delete", "corrupt"] {
            let temp = tempfile::tempdir().unwrap();
            let paths = ConfigPaths::from_config_dir(temp.path());
            fs::create_dir_all(paths.acp_dir()).unwrap();
            let b = command("b");
            let b_path = paths.acp_dir().join("b.toml");
            fs::write(&b_path, b.encode().unwrap()).unwrap();
            let diagnostic_path = paths.acp_dir().join("repair-later.toml");
            fs::write(&diagnostic_path, "invalid TOML [").unwrap();
            let runtime = ConfigRuntime::initialize(ConfigStore::new(paths.clone())).unwrap();
            let original = runtime.read_acp_definitions();
            let b_entry = original.definitions["b"].clone();
            assert_eq!(original.diagnostics.len(), 1);
            let a = command("a");
            let created = runtime
                .save_acp_definition(runtime.read().unwrap().revision, &a, None)
                .unwrap();
            let old_a_connection = created.acp.definitions["a"].connection_revision;

            let mut edited_b = b.clone();
            edited_b.env.insert("CHANGED".into(), "external".into());
            match external_change {
                "edit" => fs::write(&b_path, edited_b.encode().unwrap()).unwrap(),
                "delete" => fs::remove_file(&b_path).unwrap(),
                "corrupt" => fs::write(&b_path, "invalid TOML [").unwrap(),
                _ => unreachable!(),
            }
            // Neither new healthy files nor repaired diagnostics may publish as a side
            // effect of a command on A.
            fs::write(
                paths.acp_dir().join("new.toml"),
                command("new").encode().unwrap(),
            )
            .unwrap();
            fs::write(&diagnostic_path, command("repair-later").encode().unwrap()).unwrap();
            let mut renamed_a = a.clone();
            renamed_a.display_name = "Renamed A".into();
            let saved = runtime
                .save_acp_definition(
                    created.revision,
                    &renamed_a,
                    Some(created.acp.definitions["a"].document_revision),
                )
                .unwrap();
            assert_eq!(
                saved.acp.definitions["a"].connection_revision,
                old_a_connection
            );
            assert_eq!(saved.acp.definitions["b"], b_entry, "{external_change}");
            assert_eq!(saved.acp.diagnostics, original.diagnostics);
            assert!(!saved.acp.definitions.contains_key("new"));
            assert!(!saved.acp.definitions.contains_key("repair-later"));
            assert_eq!(runtime.read_acp_definitions(), saved.acp);
            let deleted = runtime
                .delete_acp_definition(
                    saved.revision,
                    "a",
                    saved.acp.definitions["a"].document_revision,
                )
                .unwrap();
            assert_eq!(deleted.acp.definitions["b"], b_entry, "{external_change}");
            assert_eq!(deleted.acp.diagnostics, original.diagnostics);
            assert!(!deleted.acp.definitions.contains_key("new"));
            assert!(!deleted.acp.definitions.contains_key("repair-later"));
            assert!(!deleted.acp.definitions.contains_key("a"));
            assert_eq!(runtime.read_acp_definitions(), deleted.acp);
            let readded = runtime
                .save_acp_definition(deleted.revision, &a, None)
                .unwrap();
            assert!(readded.acp.definitions["a"].connection_revision > old_a_connection);
            assert_eq!(readded.acp.definitions["b"], b_entry, "{external_change}");
            assert_eq!(readded.acp.diagnostics, original.diagnostics);
            let repaired = runtime
                .save_acp_definition(
                    readded.revision,
                    &command("repair-later"),
                    Some(document_revision(
                        "acp/repair-later.toml",
                        &fs::read(&diagnostic_path).unwrap(),
                    )),
                )
                .unwrap();
            assert_eq!(repaired.acp.definitions["b"], b_entry, "{external_change}");
            assert!(repaired.acp.diagnostics.is_empty());
            assert!(repaired.acp.definitions.contains_key("repair-later"));
            assert!(!repaired.acp.definitions.contains_key("new"));

            let reloaded = runtime.reload_acp_definitions().unwrap();
            assert!(reloaded.acp.definitions.contains_key("new"));
            assert!(reloaded.acp.definitions.contains_key("repair-later"));
            match external_change {
                "edit" => {
                    assert_eq!(reloaded.acp.definitions["b"].definition, edited_b);
                    assert_ne!(
                        reloaded.acp.definitions["b"].connection_revision,
                        b_entry.connection_revision
                    );
                    assert!(reloaded.acp.diagnostics.is_empty());
                }
                "delete" => {
                    assert!(!reloaded.acp.definitions.contains_key("b"));
                    assert!(reloaded.acp.diagnostics.is_empty());
                }
                "corrupt" => {
                    assert!(!reloaded.acp.definitions.contains_key("b"));
                    assert_eq!(reloaded.acp.diagnostics.len(), 1);
                    assert_eq!(reloaded.acp.diagnostics[0].path, b_path);
                }
                _ => unreachable!(),
            }
        }
    }
}
