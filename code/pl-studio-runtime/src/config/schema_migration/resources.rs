//! Version 2 of the existing recovery journal: each resource owns its schema identity.
use std::collections::BTreeSet;
use std::fs;
use std::path::Path;

use anyhow::{Context, Result, ensure};
use serde::{Deserialize, Serialize};

use super::{
    CANDIDATE_DIR_NAME, JOURNAL_FILE_NAME, MigrationPhase, ORIGINAL_DIR_NAME, ResourcePlan,
    ResourceWriter, atomic_write, config_resource_path, copy_credentials, digest,
    inline_tokens_from_verified_original, operation_dir, validate_profile_resource_path,
    write_protected,
};
use crate::config::credential::CredentialStore;
use crate::config::document_migration::{load_main, load_profile};
use crate::config::{
    ConfigPaths, STUDIO_CONFIG_FILE_NAME, STUDIO_CONFIG_SCHEMA_VERSION, StudioConfig,
};
use crate::toml_schema::migration_error;

pub(super) const VERSION: u32 = 2;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum DocumentFamily {
    Main,
    Profile,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Resource {
    document: DocumentFamily,
    relative_path: String,
    source_version: Option<u32>,
    target_version: u32,
    original_hash: String,
    candidate_hash: String,
    replaced: bool,
}

#[derive(Debug, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Journal {
    version: u32,
    operation_id: String,
    phase: MigrationPhase,
    /// A Profile-only operation does not replace the unchanged main document.
    unchanged_main_hash: Option<String>,
    resources: Vec<Resource>,
}

fn text<'a>(path: &Path, bytes: &'a [u8], entity: &'static str, target: u32) -> Result<&'a str> {
    std::str::from_utf8(bytes)
        .map_err(|error| migration_error(path, entity, None, target, "UTF-8", error))
}

pub(super) fn main_document(path: &Path, bytes: &[u8]) -> Result<(StudioConfig, u32, bool)> {
    let loaded = load_main(
        path,
        text(path, bytes, "studio-config", STUDIO_CONFIG_SCHEMA_VERSION)?,
    )?;
    let source = loaded.source_version;
    let config = loaded.document.into_config().map_err(|error| {
        migration_error(
            path,
            "studio-config",
            Some(source),
            STUDIO_CONFIG_SCHEMA_VERSION,
            "validate",
            error,
        )
    })?;
    Ok((config, source, loaded.migrated))
}

fn current_main(paths: &ConfigPaths) -> Result<(StudioConfig, Option<String>)> {
    let bytes = match fs::read(paths.config_file()) {
        Ok(bytes) => bytes,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            // A dangling symlink is not an absent config.
            match fs::symlink_metadata(paths.config_file()) {
                Err(metadata) if metadata.kind() == std::io::ErrorKind::NotFound => {
                    return Ok((StudioConfig::default_config()?, None));
                }
                _ => return Err(error.into()),
            }
        }
        Err(error) => return Err(error.into()),
    };
    let (config, source, _) = main_document(paths.config_file(), &bytes)?;
    ensure!(
        (27..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&source),
        "pending Profile operation requires its current main snapshot"
    );
    Ok((config, Some(digest(&bytes))))
}

fn validate_profile(
    path: &Path,
    content: &[u8],
    config: &StudioConfig,
    require_current: bool,
) -> Result<(u32, bool)> {
    let loaded = load_profile(path, text(path, content, "agent-profile", 1)?)?;
    if require_current {
        ensure!(
            !loaded.migrated,
            "Profile candidate must use the current schema"
        );
    }
    let source = loaded.source_version;
    let profile = loaded.document.into_profile().map_err(|error| {
        migration_error(path, "agent-profile", Some(source), 1, "validate", error)
    })?;
    let profile_id = path
        .file_stem()
        .and_then(|name| name.to_str())
        .context("invalid Profile filename")?;
    crate::config::agent_profile::validate_user_agent_profile_id(profile_id)?;
    crate::config::agent_profile::validate_user_profile_fields(profile_id, &profile).map_err(
        |error| migration_error(path, "agent-profile", Some(source), 1, "validate", error),
    )?;
    // Unchanged current Profiles retain editable declarations and catalog diagnostics even
    // when a normal settings command removed their route. Only migration candidates require
    // joint reference admission before commit; this also applies to disabled candidates.
    if loaded.migrated || require_current {
        config
            .models
            .route_availability(&crate::config::ModelRouteConfig {
                account_id: profile.account_id,
                model_id: profile.model_id,
                effort: profile.effort,
            })
            .map(|_| ())
            .map_err(|error| {
                migration_error(path, "agent-profile", Some(source), 1, "references", error)
            })?;
    }
    Ok((source, loaded.migrated))
}

fn resource(
    plan: &ResourcePlan,
    document: DocumentFamily,
    source: Option<u32>,
    target: u32,
) -> Resource {
    Resource {
        document,
        relative_path: plan.relative_path.clone(),
        source_version: source,
        target_version: target,
        original_hash: plan.original_hash(),
        candidate_hash: plan.candidate_hash(),
        replaced: false,
    }
}

pub(super) fn prepare(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    original: Option<&[u8]>,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    let mut plans = Vec::new();
    let mut resources = Vec::new();
    let (config, unchanged_main_hash) = if let Some(original) = original {
        let (config, source, migrated) = main_document(paths.config_file(), original)?;
        if migrated {
            let candidate =
                crate::config::document_migration::MainV28::from_config(&config)?.encode()?;
            let plan = ResourcePlan {
                relative_path: STUDIO_CONFIG_FILE_NAME.into(),
                original: original.to_vec(),
                candidate: candidate.into_bytes(),
            };
            resources.push(resource(
                &plan,
                DocumentFamily::Main,
                Some(source),
                STUDIO_CONFIG_SCHEMA_VERSION,
            ));
            plans.push(plan);
            (config, None)
        } else {
            (config, Some(digest(original)))
        }
    } else {
        (StudioConfig::default_config()?, None)
    };
    let mut names = Vec::new();
    match fs::read_dir(paths.agents_dir()) {
        Ok(entries) => {
            for entry in entries {
                let path = entry?.path();
                if path.extension().and_then(|value| value.to_str()) == Some("toml") {
                    names.push(path);
                }
            }
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error.into()),
    }
    names.sort();
    for path in names {
        let original = fs::read(&path)?;
        let (_, migrated) = validate_profile(&path, &original, &config, false)?;
        if !migrated {
            continue;
        }
        let loaded = load_profile(&path, text(&path, &original, "agent-profile", 1)?)?;
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .context("invalid Profile filename")?;
        let plan = ResourcePlan {
            relative_path: format!("agents/{name}"),
            original,
            candidate: loaded.document.encode()?.into_bytes(),
        };
        resources.push(resource(&plan, DocumentFamily::Profile, None, 1));
        plans.push(plan);
    }
    if plans.is_empty() {
        return Ok(config);
    }
    for plan in &plans {
        ensure!(
            fs::read(config_resource_path(paths, &plan.relative_path))? == plan.original,
            "configuration resource changed during migration preparation"
        );
        let path = config_resource_path(paths, &plan.relative_path);
        if plan.relative_path == STUDIO_CONFIG_FILE_NAME {
            let (_, version, migrated) = main_document(&path, &plan.candidate)?;
            ensure!(
                version == STUDIO_CONFIG_SCHEMA_VERSION && !migrated,
                "invalid main candidate"
            );
        } else {
            validate_profile(&path, &plan.candidate, &config, true)?;
        }
    }
    let directory = operation_dir(paths);
    ensure!(
        !directory.join(JOURNAL_FILE_NAME).exists(),
        "pending configuration migration must be resumed first"
    );
    for plan in &plans {
        crate::config::store::write_config_backup(
            &config_resource_path(paths, &plan.relative_path),
            &plan.original,
            "migrated",
        )?;
        write_protected(&directory, ORIGINAL_DIR_NAME, plan, &plan.original)?;
        write_protected(&directory, CANDIDATE_DIR_NAME, plan, &plan.candidate)?;
    }
    let mut journal = Journal {
        version: VERSION,
        operation_id: format!("resources-{}", digest(&serde_json::to_vec(&resources)?)),
        phase: MigrationPhase::Prepared,
        unchanged_main_hash,
        resources,
    };
    write_journal(&directory, &journal)?;
    commit(paths, credentials, &mut journal, write)
}

pub(super) fn resume(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    bytes: &[u8],
) -> Result<StudioConfig> {
    let mut journal: Journal = serde_json::from_slice(bytes)?;
    commit(paths, credentials, &mut journal, &atomic_write)
}

fn validate_resources(journal: &Journal) -> Result<()> {
    ensure!(
        journal.version == VERSION,
        "unsupported resource migration journal"
    );
    ensure!(
        !journal.resources.is_empty(),
        "empty resource migration journal"
    );
    let mut seen = BTreeSet::new();
    for resource in &journal.resources {
        ensure!(
            seen.insert(&resource.relative_path),
            "duplicate migration resource"
        );
        match resource.document {
            DocumentFamily::Main => {
                ensure!(
                    resource.relative_path == STUDIO_CONFIG_FILE_NAME,
                    "invalid main resource path"
                );
                ensure!(
                    resource
                        .source_version
                        .is_some_and(|source| (18..resource.target_version).contains(&source))
                        && (27..=STUDIO_CONFIG_SCHEMA_VERSION).contains(&resource.target_version),
                    "invalid main resource versions"
                );
            }
            DocumentFamily::Profile => {
                validate_profile_resource_path(&resource.relative_path)?;
                ensure!(
                    resource.source_version.is_none() && resource.target_version == 1,
                    "invalid Profile resource versions"
                );
            }
        }
    }
    if journal
        .resources
        .iter()
        .any(|resource| resource.document == DocumentFamily::Main)
    {
        ensure!(
            journal.unchanged_main_hash.is_none(),
            "a replaced main cannot also be an unchanged guard"
        );
    }
    Ok(())
}

fn commit(
    paths: &ConfigPaths,
    credentials: &dyn CredentialStore,
    journal: &mut Journal,
    write: ResourceWriter<'_>,
) -> Result<StudioConfig> {
    validate_resources(journal)?;
    let directory = operation_dir(paths);
    let mut verified = Vec::with_capacity(journal.resources.len());
    for resource in &journal.resources {
        let original = fs::read(
            directory
                .join(ORIGINAL_DIR_NAME)
                .join(&resource.relative_path),
        )?;
        let candidate = fs::read(
            directory
                .join(CANDIDATE_DIR_NAME)
                .join(&resource.relative_path),
        )?;
        ensure!(
            digest(&original) == resource.original_hash,
            "preserved original digest conflict"
        );
        ensure!(
            digest(&candidate) == resource.candidate_hash,
            "candidate digest conflict"
        );
        let disk = fs::read(config_resource_path(paths, &resource.relative_path))?;
        let hash = digest(&disk);
        ensure!(
            hash == resource.original_hash || hash == resource.candidate_hash,
            "resource changed outside the pending migration"
        );
        verified.push(ResourcePlan {
            relative_path: resource.relative_path.clone(),
            original,
            candidate,
        });
    }
    let main = journal
        .resources
        .iter()
        .position(|resource| resource.document == DocumentFamily::Main);
    let (config, main_guard) = if let Some(index) = main {
        let plan = &verified[index];
        let path = paths.config_file();
        let (_, source, _) = main_document(path, &plan.original)?;
        ensure!(
            Some(source) == journal.resources[index].source_version,
            "main source version conflicts with journal"
        );
        let (config, target, _) = main_document(path, &plan.candidate)?;
        ensure!(
            target == journal.resources[index].target_version,
            "invalid main candidate version"
        );
        (config, None)
    } else {
        let (config, hash) = current_main(paths)?;
        ensure!(
            hash == journal.unchanged_main_hash,
            "unchanged main snapshot conflicts with journal"
        );
        (config, hash)
    };
    for (entry, plan) in journal.resources.iter().zip(&verified) {
        if entry.document == DocumentFamily::Profile {
            let path = config_resource_path(paths, &entry.relative_path);
            let (source, migrated) = validate_profile(&path, &plan.original, &config, false)?;
            ensure!(
                source == 0 && migrated,
                "Profile original contradicts import journal"
            );
            validate_profile(&path, &plan.candidate, &config, true)?;
        }
    }
    if journal.phase == MigrationPhase::Prepared {
        if let Some(index) = main
            && journal.resources[index]
                .source_version
                .is_some_and(|source| source <= 22)
        {
            // The verified original is the sole source of the credential import intent.
            let tokens = inline_tokens_from_verified_original(&verified[index].original);
            copy_credentials(credentials, &config, &tokens)?;
        }
        journal.phase = MigrationPhase::Credentials;
        write_journal(&directory, journal)?;
    }
    if journal.phase == MigrationPhase::Credentials {
        for (index, plan) in verified.iter().enumerate() {
            let entry = &mut journal.resources[index];
            let path = config_resource_path(paths, &entry.relative_path);
            let hash = digest(&fs::read(&path)?);
            ensure!(
                hash == entry.original_hash || hash == entry.candidate_hash,
                "resource changed during pending commit"
            );
            if hash != entry.candidate_hash {
                write(&path, &plan.candidate)?;
            }
            entry.replaced = true;
            // A write may have succeeded before its acknowledgement failed; recovery uses bytes.
            write_journal(&directory, journal)?;
        }
        journal.phase = MigrationPhase::Committing;
        write_journal(&directory, journal)?;
    }
    for entry in &journal.resources {
        ensure!(
            digest(&fs::read(config_resource_path(
                paths,
                &entry.relative_path
            ))?) == entry.candidate_hash,
            "resource did not reach its verified candidate"
        );
    }
    if main.is_none() {
        let (_, final_hash) = current_main(paths)?;
        ensure!(
            final_hash == main_guard,
            "main snapshot changed before migration confirmation"
        );
    }
    // Cleanup is after final confirmation; its failure does not invalidate committed bytes.
    if let Err(error) = fs::remove_dir_all(&directory) {
        tracing::warn!(%error, "configuration migration journal cleanup failed");
    }
    Ok(config)
}

fn write_journal(directory: &Path, journal: &Journal) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(journal)?;
    atomic_write(&directory.join(JOURNAL_FILE_NAME), &bytes)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::PureError;
    use crate::config::ConfigStore;
    use crate::config::credential::MemoryCredentialStore;

    const IMPORT: &str = r#"
enabled = false
display_name = "Saved"
description = "Saved description"
when_to_use = "Saved usage"
system_instructions = "Saved instructions"
provider = "deepseek"
model = "deepseek-flash"
workspace_mode = "directory"
"#;

    fn fixture() -> (tempfile::TempDir, ConfigStore) {
        let directory = tempfile::tempdir().unwrap();
        let store = ConfigStore::new(ConfigPaths::from_config_dir(directory.path()));
        store
            .save(&StudioConfig::default_config().unwrap())
            .unwrap();
        fs::create_dir_all(store.paths().agents_dir()).unwrap();
        (directory, store)
    }

    #[test]
    fn main_27_imports_later_profile_without_replacing_main_and_resumes_after_lost_ack() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let profile_path = paths.agents_dir().join("saved.toml");
        fs::write(&profile_path, IMPORT).unwrap();
        let main_before = fs::read(paths.config_file()).unwrap();
        let credentials = MemoryCredentialStore::default();
        let result = prepare(paths, &credentials, Some(&main_before), &|path, bytes| {
            assert_eq!(path, profile_path);
            atomic_write(path, bytes)?;
            Err(PureError::Io(std::io::Error::other(
                "lost replacement acknowledgement",
            )))
        });
        assert!(result.is_err());
        let candidate = fs::read(&profile_path).unwrap();
        let journal_path = operation_dir(paths).join(JOURNAL_FILE_NAME);
        let journal_bytes = fs::read(&journal_path).unwrap();
        let journal: Journal = serde_json::from_slice(&journal_bytes).unwrap();
        assert_eq!(journal.version, VERSION);
        assert_eq!(journal.resources.len(), 1);
        assert_eq!(journal.resources[0].document, DocumentFamily::Profile);
        assert_eq!(journal.resources[0].source_version, None);
        assert_eq!(journal.resources[0].target_version, 1);
        assert_eq!(journal.unchanged_main_hash, Some(digest(&main_before)));
        assert_eq!(fs::read(paths.config_file()).unwrap(), main_before);
        let recovered = resume(paths, &credentials, &journal_bytes).unwrap();
        assert_eq!(recovered.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_eq!(fs::read(&profile_path).unwrap(), candidate);
        assert_eq!(fs::read(paths.config_file()).unwrap(), main_before);
        assert!(!operation_dir(paths).exists());
        let profile =
            load_profile(&profile_path, std::str::from_utf8(&candidate).unwrap()).unwrap();
        assert!(!profile.migrated);
        assert!(!profile.document.into_profile().unwrap().enabled);
        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_eq!(fs::read(&profile_path).unwrap(), candidate);
        assert_eq!(fs::read(paths.config_file()).unwrap(), main_before);
    }

    #[test]
    fn current_documents_are_byte_noops_including_comments() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let imported = load_profile(Path::new("saved.toml"), IMPORT).unwrap();
        let profile = format!(
            "# keep Profile comment\n{}",
            imported.document.encode().unwrap()
        );
        let profile_path = paths.agents_dir().join("saved.toml");
        fs::write(&profile_path, &profile).unwrap();
        let main = format!(
            "# keep main comment\n{}",
            fs::read_to_string(paths.config_file()).unwrap()
        );
        fs::write(paths.config_file(), &main).unwrap();
        for _ in 0..2 {
            store.load_for_startup().unwrap();
            assert_eq!(fs::read_to_string(paths.config_file()).unwrap(), main);
            assert_eq!(fs::read_to_string(&profile_path).unwrap(), profile);
            assert!(!operation_dir(paths).exists());
        }
        let entries: Vec<_> = fs::read_dir(paths.config_dir())
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert!(
            !entries
                .iter()
                .any(|name| name.to_string_lossy().ends_with(".bak"))
        );
    }

    #[tokio::test]
    async fn removing_profile_only_account_keeps_current_profiles_editable_after_restart() {
        for enabled in [true, false] {
            let (_directory, store) = fixture();
            let paths = store.paths();
            let mut config = store.load().unwrap();
            for account in config.models.accounts.values_mut() {
                account.bearer_token = Some("profile-route-regression-test-token".into());
            }
            let account_id = crate::config::AccountId::new("profile-only").unwrap();
            let account = config.models.accounts.values().next().unwrap().clone();
            config.models.accounts.insert(account_id.clone(), account);
            store.save(&config).unwrap();
            let runtime = crate::config::ConfigRuntime::initialize(store.clone()).unwrap();
            let mut profile = load_profile(Path::new("saved.toml"), IMPORT)
                .unwrap()
                .document
                .into_profile()
                .unwrap();
            profile.account_id = account_id.clone();
            profile.enabled = enabled;
            profile.effort = Some(crate::config::ReasoningEffort::new("high"));
            let (saved, _) = runtime
                .save_user_agent_profile(runtime.read().unwrap().revision, "saved", &profile)
                .unwrap();
            let profile_path = paths.agents_dir().join("saved.toml");
            let profile_bytes = fs::read(&profile_path).unwrap();
            assert!(
                !runtime
                    .agent_profiles_snapshot()
                    .unwrap()
                    .catalog
                    .diagnostics
                    .iter()
                    .any(|diagnostic| diagnostic.path == profile_path)
            );
            let removed = runtime
                .update(saved.revision, |current| {
                    crate::config_editor::remove_account(current, "profile-only", None)
                })
                .unwrap();
            assert!(!removed.config.models.accounts.contains_key(&account_id));
            let assert_unavailable = |owner: &crate::config::ConfigRuntime| {
                let snapshot = owner.agent_profiles_snapshot().unwrap();
                let saved = snapshot
                    .catalog
                    .profiles
                    .iter()
                    .find(|profile| profile.profile_id == "saved")
                    .expect("unavailable Profile stays in the editable settings catalog");
                assert_eq!(saved.account_id, "profile-only");
                assert_eq!(saved.enabled, enabled);
                assert!(
                    snapshot
                        .catalog
                        .diagnostics
                        .iter()
                        .any(|diagnostic| diagnostic.path == profile_path)
                );
                assert!(
                    !owner
                        .agent_profiles()
                        .unwrap()
                        .profiles
                        .iter()
                        .any(|profile| profile.profile_id == "saved")
                );
            };
            assert_unavailable(&runtime);
            let main_bytes = fs::read(paths.config_file()).unwrap();
            drop(runtime);

            let restarted = crate::config::ConfigRuntime::initialize(store.clone())
                .expect("a current unavailable Profile does not block app startup");
            assert_unavailable(&restarted);
            assert_eq!(fs::read(paths.config_file()).unwrap(), main_bytes);
            assert_eq!(fs::read(&profile_path).unwrap(), profile_bytes);
            assert!(!operation_dir(paths).exists());
            let profile_files: Vec<_> = fs::read_dir(paths.agents_dir())
                .unwrap()
                .map(|entry| entry.unwrap().path())
                .collect();
            assert!(profile_files.iter().all(|path| {
                !path
                    .file_name()
                    .unwrap()
                    .to_string_lossy()
                    .starts_with("saved.toml.migrated.")
            }));

            profile.account_id = crate::config::AccountId::new("deepseek").unwrap();
            profile.description = "Repaired after account deletion".into();
            let (_, changed) = restarted
                .save_user_agent_profile(restarted.read().unwrap().revision, "saved", &profile)
                .expect("the retained Profile can be repaired through the normal editor");
            assert!(changed);
            let repaired = restarted.agent_profiles_snapshot().unwrap();
            assert!(
                !repaired
                    .catalog
                    .diagnostics
                    .iter()
                    .any(|diagnostic| diagnostic.path == profile_path)
            );
            let saved = repaired
                .catalog
                .profiles
                .iter()
                .find(|profile| profile.profile_id == "saved")
                .unwrap();
            assert_eq!(saved.account_id, "deepseek");
            assert_eq!(saved.enabled, enabled);
            assert_eq!(saved.description, profile.description);
        }
    }

    #[test]
    fn current_main_keeps_an_unreferenced_empty_model_account_without_rewriting() {
        let (_directory, store) = fixture();
        let mut config = store.load().unwrap();
        let account_id = crate::config::AccountId::new("unfinished").unwrap();
        config.models.accounts.insert(
            account_id.clone(),
            pl_model::config::AccountConfig::from_explicit_models(
                pl_model::protocol::ProtocolEndpoint::compatible(
                    "Unfinished account",
                    "http://127.0.0.1:1",
                ),
                Vec::new(),
            ),
        );
        store.save(&config).unwrap();
        let path = store.paths().config_file();
        let original = fs::read_to_string(path).unwrap();

        let loaded = store.load_for_startup().unwrap();
        assert!(
            loaded.models.accounts[&account_id]
                .effective_catalog(None)
                .unwrap()
                .is_empty()
        );
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_eq!(fs::read_to_string(path).unwrap(), original);
        assert!(
            store
                .load()
                .unwrap()
                .models
                .accounts
                .contains_key(&account_id)
        );
        assert_eq!(fs::read_to_string(path).unwrap(), original);
    }

    #[test]
    fn current_config_keeps_the_existing_retired_ui_key_read_policy() {
        let (_directory, store) = fixture();
        let path = store.paths().config_file();
        let mut table: toml::Table = toml::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        let ui = table
            .entry("ui")
            .or_insert_with(|| toml::Value::Table(toml::Table::new()))
            .as_table_mut()
            .unwrap();
        ui.insert("follow_system_theme".into(), true.into());
        let original = toml::to_string_pretty(&table).unwrap();
        fs::write(path, &original).unwrap();

        let config = store.load_for_startup().unwrap();
        assert_eq!(fs::read_to_string(path).unwrap(), original);
        assert!(config.ui.follow_active_turn);
        store.save(&config).unwrap();
        let saved: toml::Table = toml::from_str(&fs::read_to_string(path).unwrap()).unwrap();
        assert!(
            saved
                .get("ui")
                .and_then(toml::Value::as_table)
                .is_none_or(|ui| !ui.contains_key("follow_system_theme"))
        );
    }

    #[test]
    fn current_profiles_still_validate_structure_and_fields_before_becoming_noops() {
        let current = load_profile(Path::new("saved.toml"), IMPORT)
            .unwrap()
            .document
            .encode()
            .unwrap();
        let mut empty_field: toml::Table = toml::from_str(&current).unwrap();
        empty_field.insert("description".into(), "".into());
        let mut wrong_type: toml::Table = toml::from_str(&current).unwrap();
        wrong_type.insert("model_id".into(), 7.into());
        for invalid in [
            format!("{current}\nunknown_profile_field=true\n"),
            toml::to_string(&empty_field).unwrap(),
            toml::to_string(&wrong_type).unwrap(),
        ] {
            let (_directory, store) = fixture();
            let paths = store.paths();
            let main_bytes = fs::read(paths.config_file()).unwrap();
            let profile_path = paths.agents_dir().join("saved.toml");
            fs::write(&profile_path, &invalid).unwrap();
            let error = store
                .load_for_startup()
                .expect_err("current format is still validated");
            let crate::config::ConfigRuntimeError::Migration(error) = error else {
                panic!("invalid current Profile must retain migration context");
            };
            assert!(error.is::<crate::toml_schema::DocumentMigrationFailed>());
            assert_eq!(fs::read(paths.config_file()).unwrap(), main_bytes);
            assert_eq!(fs::read_to_string(profile_path).unwrap(), invalid);
            assert!(!operation_dir(paths).exists());
        }
    }

    #[test]
    fn imported_profiles_still_require_joint_references_even_when_disabled() {
        for enabled in [true, false] {
            let (_directory, store) = fixture();
            let paths = store.paths();
            let main_bytes = fs::read(paths.config_file()).unwrap();
            let profile_path = paths.agents_dir().join("saved.toml");
            let invalid = IMPORT
                .replace("enabled = false", &format!("enabled = {enabled}"))
                .replace("provider = \"deepseek\"", "provider = \"removed\"");
            fs::write(&profile_path, &invalid).unwrap();
            let error = store
                .load_for_startup()
                .expect_err("import requires valid references");
            let crate::config::ConfigRuntimeError::Migration(error) = error else {
                panic!("invalid import references must retain migration context");
            };
            assert!(error.is::<crate::toml_schema::DocumentMigrationFailed>());
            assert_eq!(fs::read(paths.config_file()).unwrap(), main_bytes);
            assert_eq!(fs::read_to_string(profile_path).unwrap(), invalid);
            assert!(!operation_dir(paths).exists());
        }
    }

    #[test]
    fn profile_only_recovery_rejects_changed_main_guard_and_candidate_digest() {
        for tamper_main in [false, true] {
            let (_directory, store) = fixture();
            let paths = store.paths();
            let profile_path = paths.agents_dir().join("saved.toml");
            fs::write(&profile_path, IMPORT).unwrap();
            let main = fs::read(paths.config_file()).unwrap();
            let credentials = MemoryCredentialStore::default();
            prepare(paths, &credentials, Some(&main), &|_, _| {
                Err(PureError::Io(std::io::Error::other("interrupted")))
            })
            .unwrap_err();
            let journal_path = operation_dir(paths).join(JOURNAL_FILE_NAME);
            let journal = fs::read(&journal_path).unwrap();
            if tamper_main {
                let mut changed = main.clone();
                changed.extend_from_slice(b"\n# external edit\n");
                fs::write(paths.config_file(), changed).unwrap();
            } else {
                fs::write(
                    operation_dir(paths)
                        .join(CANDIDATE_DIR_NAME)
                        .join("agents/saved.toml"),
                    b"changed",
                )
                .unwrap();
            }
            assert!(resume(paths, &credentials, &journal).is_err());
            assert_eq!(fs::read(&profile_path).unwrap(), IMPORT.as_bytes());
            assert_eq!(fs::read(&journal_path).unwrap(), journal);
        }
    }

    #[test]
    fn invalid_later_import_is_migration_error_without_any_replacement() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let main = fs::read(paths.config_file()).unwrap();
        let profile_path = paths.agents_dir().join("saved.toml");
        let invalid = format!("schema_version=0\n{IMPORT}");
        fs::write(&profile_path, &invalid).unwrap();
        let error = store.load_for_startup().unwrap_err();
        let crate::config::ConfigRuntimeError::Migration(error) = error else {
            panic!("document error must retain its migration source");
        };
        assert!(error.is::<crate::toml_schema::DocumentMigrationFailed>());
        assert_eq!(fs::read(paths.config_file()).unwrap(), main);
        assert_eq!(fs::read_to_string(profile_path).unwrap(), invalid);
        assert!(!operation_dir(paths).exists());
    }
}
