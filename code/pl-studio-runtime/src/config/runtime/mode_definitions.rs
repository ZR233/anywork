//! File-backed Thread Mode definitions owned by the configuration runtime.

use std::collections::BTreeMap;
use std::fs;
use std::io::ErrorKind;
use std::path::Path;

use crate::mode::{
    ThreadModeCatalogSnapshot, ThreadModeDefinitionSnapshot, ThreadModeDocument, ThreadModeId,
    ThreadModeValidationIssue,
};
use crate::{StudioError, StudioErrorCode};
use anyhow::{Context, Result};

use crate::config::fs_util::{DocumentReadError, read_optional_file, read_regular_file_bounded};
use crate::config::{ConfigPaths, ConfigRuntimeError};
use crate::mode::{
    MAX_MODE_DOCUMENT_BYTES, ThreadModeManager, ThreadModeSource, ThreadModeSourceId,
    ThreadModeSourceKind, validate_mode_document,
};

use super::ConfigRuntime;

const USER_MODE_SOURCE_ID: &str = "studio.user-modes";
const MAX_USER_MODES: usize = 128;

/// One successful Mode command before the transport builds its owner receipt.
pub(crate) struct ModeDefinitionCommandOutcome {
    pub changed: bool,
    pub catalog: ThreadModeCatalogSnapshot,
    pub definition: Option<ThreadModeDefinitionSnapshot>,
}

pub(super) fn initialize(
    paths: &ConfigPaths,
) -> Result<(
    ThreadModeManager,
    BTreeMap<ThreadModeId, ThreadModeDocument>,
)> {
    let manager = ThreadModeManager::default();
    crate::studio::thread::register_builtins(&manager).map_err(|error| {
        crate::PureError::ConfigError(format!("failed to register built-in Thread Modes: {error}"))
    })?;
    let documents = load_documents(paths)?;
    publish_documents(&manager, &documents)?;
    Ok((manager, documents))
}

impl ConfigRuntime {
    pub(crate) fn thread_mode_manager(&self) -> ThreadModeManager {
        self.modes.clone()
    }

    pub(crate) fn read_thread_mode_catalog(&self) -> ThreadModeCatalogSnapshot {
        self.modes.snapshot().catalog().clone()
    }

    pub(crate) fn read_thread_mode_definition(
        &self,
        mode_id: &ThreadModeId,
    ) -> Result<ThreadModeDefinitionSnapshot> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| mode_config_error("ConfigRuntime command lock is poisoned"))?;
        let snapshot = self.modes.snapshot();
        let mode = snapshot
            .mode(mode_id)
            .ok_or_else(|| thread_mode_not_found(mode_id))?;
        let descriptor = mode.descriptor();
        let document = if descriptor.read_only {
            ThreadModeDocument::from_parts(mode.definition(), Default::default())
        } else {
            self.mode_documents
                .read()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .get(mode_id)
                .cloned()
                .ok_or_else(|| thread_mode_not_found(mode_id))?
        };
        Ok(ThreadModeDefinitionSnapshot {
            revision: document_revision(&document)?,
            document,
            read_only: descriptor.read_only,
        })
    }

    pub(crate) fn save_thread_mode_definition(
        &self,
        expected_revision: u64,
        document: ThreadModeDocument,
    ) -> Result<ModeDefinitionCommandOutcome> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| mode_config_error("ConfigRuntime command lock is poisoned"))?;
        self.ensure_mode_command_open()?;
        let current = self.modes.snapshot();
        let mode_id = document.id.clone();
        if current
            .mode(&mode_id)
            .is_some_and(|mode| mode.descriptor().read_only)
        {
            return Err(StudioError::new(
                StudioErrorCode::PermissionDenied,
                format!("Thread Mode `{mode_id}` is built in and read-only"),
                false,
            )
            .into());
        }
        let canonical = validate_mode_document(document).map_err(validation_error)?;
        let mut documents = self
            .mode_documents
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        let creating = !documents.contains_key(&mode_id);
        if creating && documents.len() >= MAX_USER_MODES {
            return Err(mode_config_error(format!(
                "at most {MAX_USER_MODES} user Thread Modes are supported"
            )));
        }
        let unchanged = documents.get(&mode_id) == Some(&canonical);
        documents.insert(mode_id.clone(), canonical.clone());
        let path = mode_path(self.store.paths(), &mode_id)?;
        let bytes = serde_json::to_vec_pretty(&canonical)
            .context("failed to serialize Thread Mode document")?;
        if bytes.len() > MAX_MODE_DOCUMENT_BYTES {
            return Err(mode_config_error(format!(
                "Thread Mode document exceeds the {MAX_MODE_DOCUMENT_BYTES} byte limit"
            )));
        }
        let previous = read_optional_file(&path)?;
        fs::create_dir_all(self.store.paths().modes_dir())?;
        check_document_version(&path, previous.as_deref(), expected_revision)?;
        if previous.as_deref() != Some(bytes.as_slice()) {
            pl_tool::workspace::write_file_atomically(&path, &bytes)?;
        }
        if unchanged {
            return Ok(ModeDefinitionCommandOutcome {
                changed: false,
                catalog: current.catalog().clone(),
                definition: Some(ThreadModeDefinitionSnapshot {
                    revision: document_revision(&canonical)?,
                    document: canonical,
                    read_only: false,
                }),
            });
        }
        if let Err(error) = self.replace_user_modes(&documents) {
            if let Err(restore) = restore_file(&path, previous.as_deref()) {
                return Err(restore.context(format!(
                    "failed to restore Thread Mode file after publish error: {error}"
                )));
            }
            return Err(error);
        }
        *self
            .mode_documents
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = documents;
        let catalog = self.modes.snapshot().catalog().clone();
        Ok(ModeDefinitionCommandOutcome {
            changed: true,
            definition: Some(ThreadModeDefinitionSnapshot {
                revision: document_revision(&canonical)?,
                document: canonical,
                read_only: false,
            }),
            catalog,
        })
    }

    pub(crate) fn delete_thread_mode_definition(
        &self,
        expected_revision: u64,
        mode_id: &ThreadModeId,
    ) -> Result<ModeDefinitionCommandOutcome> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| mode_config_error("ConfigRuntime command lock is poisoned"))?;
        self.ensure_mode_command_open()?;
        let current = self.modes.snapshot();
        let mode = current
            .mode(mode_id)
            .ok_or_else(|| thread_mode_not_found(mode_id))?;
        if mode.descriptor().read_only {
            return Err(StudioError::new(
                StudioErrorCode::PermissionDenied,
                format!("Thread Mode `{mode_id}` is built in and read-only"),
                false,
            )
            .into());
        }
        let mut documents = self
            .mode_documents
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .clone();
        if documents.remove(mode_id).is_none() {
            return Err(thread_mode_not_found(mode_id));
        }
        let path = mode_path(self.store.paths(), mode_id)?;
        let previous = read_optional_file(&path)?;
        check_document_version(&path, previous.as_deref(), expected_revision)?;
        match fs::remove_file(&path) {
            Ok(()) => {}
            Err(error) if error.kind() == ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        if let Err(error) = self.replace_user_modes(&documents) {
            if let Err(restore) = restore_file(&path, previous.as_deref()) {
                return Err(restore.context(format!(
                    "failed to restore Thread Mode file after publish error: {error}"
                )));
            }
            return Err(error);
        }
        *self
            .mode_documents
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = documents;
        Ok(ModeDefinitionCommandOutcome {
            changed: true,
            catalog: self.modes.snapshot().catalog().clone(),
            definition: None,
        })
    }

    pub(crate) fn reload_thread_mode_definitions(
        &self,
        expected_revision: u64,
    ) -> Result<ModeDefinitionCommandOutcome> {
        let _command = self
            .command_lock
            .lock()
            .map_err(|_| mode_config_error("ConfigRuntime command lock is poisoned"))?;
        self.ensure_mode_command_open()?;
        let current_catalog = self.modes.snapshot().catalog().clone();
        ensure_mode_revision(expected_revision, current_catalog.revision)?;
        // Decode and fully validate every file before changing either the
        // published manager or the editor-document cache.
        let documents = load_documents(self.store.paths())?;
        let unchanged = *self
            .mode_documents
            .read()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            == documents;
        if unchanged {
            return Ok(ModeDefinitionCommandOutcome {
                changed: false,
                catalog: current_catalog,
                definition: None,
            });
        }
        self.replace_user_modes(&documents)?;
        *self
            .mode_documents
            .write()
            .unwrap_or_else(std::sync::PoisonError::into_inner) = documents;
        Ok(ModeDefinitionCommandOutcome {
            changed: true,
            catalog: self.modes.snapshot().catalog().clone(),
            definition: None,
        })
    }

    fn ensure_mode_command_open(&self) -> Result<()> {
        let state = self
            .state
            .read()
            .map_err(|_| mode_config_error("ConfigRuntime state lock is poisoned"))?;
        if state.closing {
            return Err(mode_config_error("configuration owner is closing"));
        }
        Ok(())
    }

    fn replace_user_modes(
        &self,
        documents: &BTreeMap<ThreadModeId, ThreadModeDocument>,
    ) -> Result<()> {
        publish_documents(&self.modes, documents)
    }
}

fn publish_documents(
    manager: &ThreadModeManager,
    documents: &BTreeMap<ThreadModeId, ThreadModeDocument>,
) -> Result<()> {
    let source_id = ThreadModeSourceId::new(USER_MODE_SOURCE_ID)?;
    if documents.is_empty() {
        manager.remove_source(&source_id);
        return Ok(());
    }
    manager
        .replace_source(
            ThreadModeSource {
                id: source_id,
                kind: ThreadModeSourceKind::External,
            },
            documents
                .values()
                .map(|document| document.clone().into_parts().0),
        )
        .context("failed to publish user Thread Modes")?;
    Ok(())
}

fn load_documents(paths: &ConfigPaths) -> Result<BTreeMap<ThreadModeId, ThreadModeDocument>> {
    let directory = paths.modes_dir();
    let entries = match fs::read_dir(&directory) {
        Ok(entries) => entries,
        Err(error) if error.kind() == ErrorKind::NotFound => return Ok(BTreeMap::new()),
        Err(error) => return Err(error.into()),
    };
    let mut paths = entries
        .map(|entry| entry.map(|entry| entry.path()))
        .collect::<std::io::Result<Vec<_>>>()?;
    paths.retain(|path| path.extension().and_then(|value| value.to_str()) == Some("json"));
    paths.sort();
    anyhow::ensure!(
        paths.len() <= MAX_USER_MODES,
        "at most {MAX_USER_MODES} user Thread Mode files are supported"
    );
    let mut documents = BTreeMap::new();
    for path in paths {
        let bytes =
            read_regular_file_bounded(&path, MAX_MODE_DOCUMENT_BYTES as u64).map_err(|error| {
                match error {
                    DocumentReadError::NotFound(error) | DocumentReadError::Io(error) => {
                        anyhow::Error::new(error)
                    }
                    DocumentReadError::Symlink | DocumentReadError::NotRegularFile => {
                        anyhow::anyhow!("Thread Mode path {} is not a regular file", path.display())
                    }
                    DocumentReadError::TooLarge { limit } => anyhow::anyhow!(
                        "Thread Mode file {} exceeds the {limit} byte limit",
                        path.display()
                    ),
                }
            })?;
        let json = String::from_utf8(bytes)?;
        let crate::mode::ThreadModeValidationResult { document, issues } =
            crate::mode::validate_mode_json(&json);
        let document = document.ok_or_else(|| mode_file_validation_error(&path, issues))?;
        let mode_id = document.id.clone();
        let expected_name = mode_file_name(&mode_id)?;
        anyhow::ensure!(
            path.file_name().and_then(|value| value.to_str()) == Some(expected_name.as_str()),
            "Thread Mode file {} must be named {expected_name} for `{mode_id}`",
            path.display()
        );
        anyhow::ensure!(
            documents.insert(mode_id.clone(), document).is_none(),
            "duplicate Thread Mode `{mode_id}` in {}",
            directory.display()
        );
    }
    Ok(documents)
}

fn mode_path(paths: &ConfigPaths, mode_id: &ThreadModeId) -> Result<std::path::PathBuf> {
    Ok(paths.modes_dir().join(mode_file_name(mode_id)?))
}

fn mode_file_name(mode_id: &ThreadModeId) -> Result<String> {
    let id = ThreadModeId::new(mode_id.as_str())?;
    anyhow::ensure!(
        !id.as_str().contains('/')
            && !id.as_str().contains('\\')
            && id.as_str() != "."
            && id.as_str() != "..",
        "Thread Mode ID cannot be used as a file name"
    );
    Ok(format!("{}.json", id.as_str()))
}

fn restore_file(path: &Path, previous: Option<&[u8]>) -> Result<()> {
    match previous {
        Some(bytes) => pl_tool::workspace::write_file_atomically(path, bytes)?,
        None => match fs::remove_file(path) {
            Ok(()) => {}
            Err(error) if error.kind() == ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        },
    }
    Ok(())
}

fn document_revision(document: &ThreadModeDocument) -> Result<u64> {
    // The JSON API also serves JavaScript clients. Keep the opaque version exactly representable.
    Ok(
        (crate::config::document_revision(document.id.as_str(), &serde_json::to_vec(document)?)
            & ((1_u64 << 53) - 1))
            .max(1),
    )
}

fn check_document_version(path: &Path, previous: Option<&[u8]>, expected: u64) -> Result<()> {
    let actual = match previous {
        None => 0,
        Some(bytes) => {
            let json = std::str::from_utf8(bytes)?;
            let result = crate::mode::validate_mode_json(json);
            document_revision(
                &result
                    .document
                    .ok_or_else(|| mode_file_validation_error(path, result.issues))?,
            )?
        }
    };
    ensure_mode_revision(expected, actual)
}

fn ensure_mode_revision(expected: u64, actual: u64) -> Result<()> {
    if expected == actual {
        return Ok(());
    }
    Err(anyhow::Error::new(ConfigRuntimeError::StaleRevision {
        expected,
        actual,
    }))
}

fn validation_error(issues: Vec<ThreadModeValidationIssue>) -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::InvalidArgument,
        "Thread Mode definition is invalid",
        false,
    )
    .with_details(serde_json::json!({ "issues": issues }))
    .into()
}

fn thread_mode_not_found(mode_id: &ThreadModeId) -> anyhow::Error {
    StudioError::new(
        StudioErrorCode::NotFound,
        format!("Thread Mode `{mode_id}` was not found"),
        false,
    )
    .into()
}

fn mode_config_error(message: impl Into<String>) -> anyhow::Error {
    crate::PureError::ConfigError(message.into()).into()
}

fn mode_file_validation_error(
    path: &Path,
    issues: Vec<ThreadModeValidationIssue>,
) -> anyhow::Error {
    let summary = issues
        .iter()
        .map(|issue| format!("{} at {}: {}", issue.code, issue.path, issue.message))
        .collect::<Vec<_>>()
        .join("; ");
    mode_config_error(format!(
        "invalid Thread Mode file {}: {summary}",
        path.display()
    ))
}
