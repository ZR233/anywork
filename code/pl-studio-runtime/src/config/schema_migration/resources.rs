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
    Mcp,
    Lsp,
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
    let (config, source, migrated) = main_document(paths.config_file(), &bytes)?;
    ensure!(
        !migrated && source == STUDIO_CONFIG_SCHEMA_VERSION,
        "pending Profile operation requires its current main snapshot"
    );
    Ok((config, Some(digest(&bytes))))
}

fn ensure_main_absent(paths: &ConfigPaths) -> Result<()> {
    match fs::read(paths.config_file()) {
        Ok(_) => Err(anyhow::anyhow!(
            "main config appeared during Profile-only migration"
        )),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            match fs::symlink_metadata(paths.config_file()) {
                Err(metadata) if metadata.kind() == std::io::ErrorKind::NotFound => Ok(()),
                Err(metadata) => Err(metadata.into()),
                Ok(_) => Err(error.into()),
            }
        }
        Err(error) => Err(error.into()),
    }
}

fn verify_profile_main_guard(paths: &ConfigPaths, expected_hash: Option<&str>) -> Result<()> {
    if let Some(expected_hash) = expected_hash {
        let bytes = fs::read(paths.config_file())?;
        ensure!(
            digest(&bytes) == expected_hash,
            "unchanged main snapshot conflicts with journal"
        );
        return Ok(());
    }
    ensure_main_absent(paths)
}

/// Decodes a main snapshot guarded by a Profile-only resource journal.
///
/// This continuation boundary may admit historical schemas only after the journal's
/// unchanged-main hash has been checked against the exact on-disk bytes.
/// Ordinary current-main reads continue to require the current schema.
fn unchanged_profile_main(
    paths: &ConfigPaths,
    expected_hash: Option<&str>,
) -> Result<StudioConfig> {
    let Some(expected_hash) = expected_hash else {
        ensure_main_absent(paths)?;
        return Ok(StudioConfig::default_config()?);
    };
    let bytes = fs::read(paths.config_file())?;
    ensure!(
        digest(&bytes) == expected_hash,
        "unchanged main snapshot conflicts with journal"
    );
    let (config, source, migrated) = main_document(paths.config_file(), &bytes)?;
    if source == crate::config::STUDIO_CONFIG_SCHEMA_VERSION && !migrated {
        let (current, hash) = current_main(paths)?;
        ensure!(
            hash.as_deref() == Some(expected_hash),
            "unchanged main snapshot conflicts with journal"
        );
        return Ok(current);
    }
    ensure!(
        (27..STUDIO_CONFIG_SCHEMA_VERSION).contains(&source) && migrated,
        "unchanged main snapshot is not an admitted Profile-journal version"
    );
    Ok(config)
}

fn validate_profile(
    path: &Path,
    content: &[u8],
    config: &StudioConfig,
    require_current: bool,
) -> Result<(u32, bool)> {
    let loaded = load_profile(path, text(path, content, "agent-profile", 2)?)?;
    if require_current {
        ensure!(
            !loaded.migrated,
            "Profile candidate must use the current schema"
        );
    }
    let source = loaded.source_version;
    let profile = loaded.document.into_profile().map_err(|error| {
        migration_error(path, "agent-profile", Some(source), 2, "validate", error)
    })?;
    let profile_id = path
        .file_stem()
        .and_then(|name| name.to_str())
        .context("invalid Profile filename")?;
    crate::config::agent_profile::validate_user_agent_profile_id(profile_id)?;
    crate::config::agent_profile::validate_user_profile_fields(profile_id, &profile).map_err(
        |error| migration_error(path, "agent-profile", Some(source), 2, "validate", error),
    )?;
    // Unchanged current Profiles retain editable declarations and catalog diagnostics even
    // when a normal settings command removed their route. Only migration candidates require
    // joint reference admission before commit; this also applies to disabled candidates.
    if loaded.migrated || require_current {
        let references = match &profile.binding {
            pl_protocol::AgentBinding::Native(native) => {
                let route = native
                    .route
                    .as_ref()
                    .context("Native Profile route is required")?;
                config
                    .models
                    .route_availability(&crate::config::ModelRouteConfig {
                        account_id: crate::config::AccountId::new(route.account_id.clone())?,
                        model_id: route.model_id.clone(),
                        effort: route
                            .effort
                            .clone()
                            .map(crate::config::ReasoningEffort::new),
                    })
                    .map(|_| ())
            }
            pl_protocol::AgentBinding::Acp(_) => {
                crate::config::agent_profile::validate_user_profile(profile_id, &profile, config)
            }
        };
        references.map_err(|error| {
            migration_error(path, "agent-profile", Some(source), 2, "references", error)
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

fn read_resource_disk_bytes(
    paths: &ConfigPaths,
    document: DocumentFamily,
    relative_path: &str,
) -> Result<Vec<u8>> {
    let path = config_resource_path(paths, relative_path);
    match document {
        DocumentFamily::Main | DocumentFamily::Profile => Ok(fs::read(path)?),
        DocumentFamily::Mcp | DocumentFamily::Lsp => match fs::symlink_metadata(&path) {
            Ok(meta) => {
                ensure!(
                    !meta.file_type().is_symlink() && meta.is_file(),
                    "MCP migration resource {relative_path} is not a regular file"
                );
                Ok(fs::read(&path)?)
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(Vec::new()),
            Err(error) => Err(error.into()),
        },
    }
}

fn validate_lsp_disk_state(paths: &ConfigPaths, resource: &Resource) -> Result<()> {
    if resource.document != DocumentFamily::Lsp {
        return Ok(());
    }
    ensure_lsp_parent_dirs(paths)?;
    let path = config_resource_path(paths, &resource.relative_path);
    match fs::symlink_metadata(&path) {
        Ok(metadata) => {
            ensure!(
                !metadata.file_type().is_symlink() && metadata.is_file(),
                "LSP migration resource {} is not a regular file",
                resource.relative_path
            );
            ensure!(
                digest(&fs::read(path)?) == resource.candidate_hash,
                "existing LSP migration resource conflicts with its candidate"
            );
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            ensure!(
                resource.original_hash == digest(&[]),
                "LSP migration original state is invalid"
            );
        }
        Err(error) => return Err(error.into()),
    }
    Ok(())
}

fn ensure_lsp_parent_dirs(paths: &ConfigPaths) -> Result<()> {
    let lsp_dir = paths.config_dir().join("lsp");
    let host_dir = lsp_dir.join("host");
    for directory in [&lsp_dir, &host_dir] {
        match fs::symlink_metadata(directory) {
            Ok(metadata) => ensure!(
                metadata.is_dir() && !metadata.file_type().is_symlink(),
                "LSP migration directory {} is not a regular directory",
                directory.display()
            ),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
            Err(error) => return Err(error.into()),
        }
    }
    Ok(())
}

fn validate_mcp_resource_path(relative_path: &str) -> Result<()> {
    let Some(file_name) = relative_path.strip_prefix("mcp/host/") else {
        anyhow::bail!("invalid MCP migration resource path `{relative_path}`");
    };
    let Some(stem) = file_name.strip_suffix(".toml") else {
        anyhow::bail!("invalid MCP migration resource path `{relative_path}`");
    };
    ensure!(
        stem.len() == 64
            && stem
                .bytes()
                .all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase()),
        "invalid MCP migration resource filename `{file_name}`"
    );
    Ok(())
}

fn validate_lsp_id(id: &str) -> bool {
    !id.is_empty()
        && id != "."
        && id != ".."
        && id
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
}

fn validate_lsp_resource_path(relative_path: &str) -> Result<&str> {
    let Some(file_name) = relative_path.strip_prefix("lsp/host/") else {
        anyhow::bail!("invalid LSP migration resource path `{relative_path}`");
    };
    let Some(id) = file_name.strip_suffix(".toml") else {
        anyhow::bail!("invalid LSP migration resource path `{relative_path}`");
    };
    ensure!(
        validate_lsp_id(id),
        "invalid LSP migration resource filename `{file_name}`"
    );
    Ok(id)
}

fn validate_lsp_candidate(path: &Path, relative_path: &str, content: &[u8]) -> Result<()> {
    let expected_id = validate_lsp_resource_path(relative_path)?;
    let raw = text(path, content, "lsp-document", 1)?;
    let document = pl_lsp::catalog::LspServerDocument::parse(raw)
        .map_err(|error| migration_error(path, "lsp-document", None, 1, "validate", error))?;
    ensure!(
        document.schema_version == 1,
        "LSP candidate must have schema_version = 1"
    );
    ensure!(
        document.id == expected_id,
        "LSP candidate id must match its filename"
    );
    Ok(())
}

fn validate_mcp_candidate(path: &Path, content: &[u8]) -> Result<()> {
    let raw = text(path, content, "mcp-document", 1)?;
    let table: toml::Table = toml::from_str(raw)
        .map_err(|error| migration_error(path, "mcp-document", None, 1, "parse", error))?;
    let version = table
        .get("schema_version")
        .and_then(toml::Value::as_integer)
        .context("MCP candidate missing schema_version")?;
    ensure!(version == 1, "MCP candidate must have schema_version = 1");
    let id = table
        .get("id")
        .and_then(toml::Value::as_str)
        .context("MCP candidate missing id")?;
    ensure!(!id.is_empty(), "MCP candidate id must not be empty");
    Ok(())
}

fn encode_fallback_legacy_mcp_server(
    id: &str,
    transport: pl_tool::mcp::config::McpServerTransport,
    server: &pl_tool::mcp::config::McpServerConfig,
) -> Result<String> {
    let mut table = toml::Table::new();
    table.insert("schema_version".into(), toml::Value::Integer(1));
    table.insert("id".into(), toml::Value::String(id.to_owned()));
    table.insert("kind".into(), toml::Value::String("server".into()));
    table.insert("enabled".into(), toml::Value::Boolean(server.enabled));
    table.insert(
        "transport".into(),
        toml::Value::String(transport.as_str().to_owned()),
    );
    if let Some(command) = &server.command {
        table.insert("command".into(), toml::Value::String(command.clone()));
    }
    if !server.args.is_empty() {
        table.insert(
            "args".into(),
            toml::Value::Array(
                server
                    .args
                    .iter()
                    .cloned()
                    .map(toml::Value::String)
                    .collect(),
            ),
        );
    }
    if !server.env.is_empty() {
        let mut env_table = toml::Table::new();
        for (k, v) in &server.env {
            env_table.insert(k.clone(), toml::Value::String(v.clone()));
        }
        table.insert("env".into(), toml::Value::Table(env_table));
    }
    if let Some(cwd) = &server.cwd {
        table.insert("cwd".into(), toml::Value::String(cwd.clone()));
    }
    if let Some(url) = &server.url {
        table.insert("url".into(), toml::Value::String(url.clone()));
    }
    if let Some(var) = &server.bearer_token_env_var {
        table.insert(
            "bearer_token_env_var".into(),
            toml::Value::String(var.clone()),
        );
    }
    if !server.headers.is_empty() {
        let mut headers = toml::Table::new();
        for (k, v) in &server.headers {
            headers.insert(k.clone(), toml::Value::String(v.clone()));
        }
        table.insert("headers".into(), toml::Value::Table(headers));
    }
    if let Some(secs) = server.startup_timeout_secs
        && let Ok(v) = i64::try_from(secs)
    {
        table.insert("startup_timeout_secs".into(), toml::Value::Integer(v));
    }
    if let Some(secs) = server.tool_timeout_secs
        && let Ok(v) = i64::try_from(secs)
    {
        table.insert("tool_timeout_secs".into(), toml::Value::Integer(v));
    }
    if let Some(enabled_tools) = &server.enabled_tools {
        table.insert(
            "enabled_tools".into(),
            toml::Value::Array(
                enabled_tools
                    .iter()
                    .cloned()
                    .map(toml::Value::String)
                    .collect(),
            ),
        );
    }
    if !server.disabled_tools.is_empty() {
        table.insert(
            "disabled_tools".into(),
            toml::Value::Array(
                server
                    .disabled_tools
                    .iter()
                    .cloned()
                    .map(toml::Value::String)
                    .collect(),
            ),
        );
    }
    Ok(toml::to_string_pretty(&table)?)
}

fn prepare_legacy_mcp_plans(
    paths: &ConfigPaths,
    original_main: &[u8],
    plans: &mut Vec<ResourcePlan>,
    resources: &mut Vec<Resource>,
) -> Result<()> {
    let raw_main = text(
        paths.config_file(),
        original_main,
        "studio-config",
        STUDIO_CONFIG_SCHEMA_VERSION,
    )?;
    let Some(legacy_mcp) = crate::config::document_migration::extract_legacy_mcp_from_main(
        paths.config_file(),
        raw_main,
    )?
    else {
        return Ok(());
    };
    let host_base_cwd =
        std::env::current_dir().context("failed to resolve current directory for MCP migration")?;
    let host_base_cwd_str = host_base_cwd
        .to_str()
        .context("current directory is not valid UTF-8 for MCP migration")?
        .to_owned();

    let mut target_files: std::collections::BTreeMap<String, Vec<u8>> =
        std::collections::BTreeMap::new();

    for builtin_id in crate::config::mcp::builtin_mcp_server_ids() {
        let enabled = legacy_mcp
            .builtin_servers
            .get(builtin_id)
            .is_none_or(|state| state.enabled);
        let cwd = (builtin_id == crate::config::mcp::ZHIPU_VISION_MCP_ID)
            .then(|| host_base_cwd_str.clone());
        let doc = crate::config::mcp_document::McpFileV1::new_builtin(builtin_id, enabled, cwd);
        let candidate = doc.encode()?.into_bytes();
        let filename = crate::config::mcp_resource::canonical_mcp_filename(builtin_id)?;
        let relative_path = format!("mcp/host/{filename}");
        target_files.insert(relative_path, candidate);
    }

    for (server_id, wire_server) in &legacy_mcp.servers {
        let mut domain_server: pl_tool::mcp::config::McpServerConfig = wire_server.clone().into();
        match domain_server.transport {
            pl_tool::mcp::config::McpServerTransport::Stdio => {
                domain_server.url = None;
                domain_server.bearer_token_env_var = None;
                domain_server.headers.clear();
                match domain_server.cwd.take() {
                    None => {
                        domain_server.cwd = Some(host_base_cwd_str.clone());
                    }
                    Some(raw) if raw.trim().is_empty() => {
                        domain_server.cwd = Some(raw);
                    }
                    Some(raw) => {
                        let p = Path::new(&raw);
                        if p.is_relative() {
                            let joined = host_base_cwd.join(p);
                            let joined_str = joined
                                .to_str()
                                .context("joined MCP cwd is not valid UTF-8")?
                                .to_owned();
                            domain_server.cwd = Some(joined_str);
                        } else {
                            domain_server.cwd = Some(raw);
                        }
                    }
                }
            }
            pl_tool::mcp::config::McpServerTransport::StreamableHttp => {
                domain_server.command = None;
                domain_server.args.clear();
                domain_server.env.clear();
                domain_server.cwd = None;
            }
        }
        let encoded = match crate::config::mcp_document::McpFileV1::new_server(
            server_id.clone(),
            domain_server.clone(),
        )
        .encode()
        {
            Ok(encoded) => encoded,
            Err(_) => encode_fallback_legacy_mcp_server(
                server_id,
                domain_server.transport,
                &domain_server,
            )?,
        };
        let key = crate::studio::paths::storage_key(server_id, "MCP server")?;
        let relative_path = format!("mcp/host/{key}.toml");
        ensure!(
            !target_files.contains_key(&relative_path),
            "conflicting legacy MCP server id `{server_id}` at `{relative_path}`"
        );
        target_files.insert(relative_path, encoded.into_bytes());
    }

    for (relative_path, candidate) in target_files {
        let original = read_resource_disk_bytes(paths, DocumentFamily::Mcp, &relative_path)?;
        if !original.is_empty() {
            ensure!(
                original == candidate,
                "existing MCP document `{relative_path}` conflicts with migration candidate"
            );
        }
        let plan = ResourcePlan {
            relative_path,
            original,
            candidate,
        };
        resources.push(resource(&plan, DocumentFamily::Mcp, None, 1));
        plans.push(plan);
    }

    Ok(())
}

fn prepare_legacy_lsp_plans(
    paths: &ConfigPaths,
    original_main: &[u8],
    plans: &mut Vec<ResourcePlan>,
    resources: &mut Vec<Resource>,
) -> Result<()> {
    let raw_main = text(
        paths.config_file(),
        original_main,
        "studio-config",
        STUDIO_CONFIG_SCHEMA_VERSION,
    )?;
    let documents = crate::config::document_migration::extract_legacy_lsp_from_main(
        paths.config_file(),
        raw_main,
    )?;
    for (id, candidate) in documents {
        ensure!(validate_lsp_id(&id), "invalid legacy LSP server id `{id}`");
        let relative_path = format!("lsp/host/{id}.toml");
        ensure_lsp_parent_dirs(paths)?;
        let target = config_resource_path(paths, &relative_path);
        match fs::symlink_metadata(&target) {
            Ok(metadata) => {
                ensure!(
                    !metadata.file_type().is_symlink() && metadata.is_file(),
                    "existing LSP document `{relative_path}` is not a regular file"
                );
                ensure!(
                    fs::read(&target)? == candidate,
                    "existing LSP document `{relative_path}` conflicts with migration candidate"
                );
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => return Err(error.into()),
        }
        let plan = ResourcePlan {
            relative_path,
            original: Vec::new(),
            candidate,
        };
        resources.push(resource(&plan, DocumentFamily::Lsp, None, 1));
        plans.push(plan);
    }
    Ok(())
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
                crate::config::document_migration::MainV32::from_config(&config)?.encode()?;
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
            prepare_legacy_mcp_plans(paths, original, &mut plans, &mut resources)?;
            prepare_legacy_lsp_plans(paths, original, &mut plans, &mut resources)?;
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
        let (source, migrated) = validate_profile(&path, &original, &config, false)?;
        if !migrated {
            continue;
        }
        let loaded = load_profile(&path, text(&path, &original, "agent-profile", 2)?)?;
        let name = path
            .file_name()
            .and_then(|name| name.to_str())
            .context("invalid Profile filename")?;
        let plan = ResourcePlan {
            relative_path: format!("agents/{name}"),
            original,
            candidate: loaded.document.encode()?.into_bytes(),
        };
        resources.push(resource(
            &plan,
            DocumentFamily::Profile,
            (source != 0).then_some(source),
            2,
        ));
        plans.push(plan);
    }
    if plans.is_empty() {
        return Ok(config);
    }
    for (plan, entry) in plans.iter().zip(&resources) {
        ensure!(
            read_resource_disk_bytes(paths, entry.document, &plan.relative_path)? == plan.original,
            "configuration resource changed during migration preparation"
        );
        let path = config_resource_path(paths, &plan.relative_path);
        match entry.document {
            DocumentFamily::Main => {
                let (_, version, migrated) = main_document(&path, &plan.candidate)?;
                ensure!(
                    version == STUDIO_CONFIG_SCHEMA_VERSION && !migrated,
                    "invalid main candidate"
                );
            }
            DocumentFamily::Profile => {
                validate_profile(&path, &plan.candidate, &config, true)?;
            }
            DocumentFamily::Mcp => {
                validate_mcp_candidate(&path, &plan.candidate)?;
            }
            DocumentFamily::Lsp => {
                validate_lsp_candidate(&path, &plan.relative_path, &plan.candidate)?;
            }
        }
    }
    let directory = operation_dir(paths);
    ensure!(
        !directory.join(JOURNAL_FILE_NAME).exists(),
        "pending configuration migration must be resumed first"
    );
    for (plan, entry) in plans.iter().zip(&resources) {
        if !(matches!(entry.document, DocumentFamily::Mcp | DocumentFamily::Lsp)
            && plan.original.is_empty())
        {
            crate::config::store::write_config_backup(
                &config_resource_path(paths, &plan.relative_path),
                &plan.original,
                "migrated",
            )?;
        }
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
                    (resource.target_version == 1 && resource.source_version.is_none())
                        || (resource.target_version == 2
                            && resource.source_version.is_none_or(|source| source == 1)),
                    "invalid Profile resource versions"
                );
            }
            DocumentFamily::Mcp => {
                validate_mcp_resource_path(&resource.relative_path)?;
                ensure!(
                    resource.source_version.is_none() && resource.target_version == 1,
                    "invalid MCP resource versions"
                );
            }
            DocumentFamily::Lsp => {
                validate_lsp_resource_path(&resource.relative_path)?;
                ensure!(
                    resource.source_version.is_none() && resource.target_version == 1,
                    "invalid LSP resource versions"
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
        validate_lsp_disk_state(paths, resource)?;
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
        let disk = read_resource_disk_bytes(paths, resource.document, &resource.relative_path)?;
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
        let (config, target, migrated) = main_document(path, &plan.candidate)?;
        ensure!(
            target == journal.resources[index].target_version
                && migrated == (target != STUDIO_CONFIG_SCHEMA_VERSION),
            "invalid main candidate version"
        );
        (config, None)
    } else {
        let hash = journal.unchanged_main_hash.as_deref();
        (
            unchanged_profile_main(paths, hash)?,
            hash.map(str::to_owned),
        )
    };
    for (entry, plan) in journal.resources.iter().zip(&verified) {
        let path = config_resource_path(paths, &entry.relative_path);
        match entry.document {
            DocumentFamily::Main => {}
            DocumentFamily::Profile => {
                let (source, migrated) = validate_profile(&path, &plan.original, &config, false)?;
                ensure!(
                    source == entry.source_version.unwrap_or(0) && migrated,
                    "Profile original contradicts import journal"
                );
                if entry.target_version == 1 {
                    // Finish an already protected V1 import, then the next scan upgrades it to V2.
                    let (candidate_source, _) =
                        validate_profile(&path, &plan.candidate, &config, false)?;
                    ensure!(
                        candidate_source == 1,
                        "invalid protected V1 Profile candidate"
                    );
                } else {
                    validate_profile(&path, &plan.candidate, &config, true)?;
                }
            }
            DocumentFamily::Mcp => {
                if !plan.original.is_empty() {
                    ensure!(
                        plan.original == plan.candidate,
                        "MCP original contradicts migration journal"
                    );
                }
                validate_mcp_candidate(&path, &plan.candidate)?;
            }
            DocumentFamily::Lsp => {
                ensure!(
                    plan.original.is_empty(),
                    "LSP migration resource must not replace an existing file"
                );
                validate_lsp_candidate(&path, &entry.relative_path, &plan.candidate)?;
            }
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
            validate_lsp_disk_state(paths, entry)?;
            let path = config_resource_path(paths, &entry.relative_path);
            let hash = digest(&read_resource_disk_bytes(
                paths,
                entry.document,
                &entry.relative_path,
            )?);
            ensure!(
                hash == entry.original_hash || hash == entry.candidate_hash,
                "resource changed during pending commit"
            );
            if hash != entry.candidate_hash {
                if main.is_none() {
                    verify_profile_main_guard(paths, main_guard.as_deref())?;
                }
                if matches!(entry.document, DocumentFamily::Mcp | DocumentFamily::Lsp)
                    && let Some(parent) = path.parent()
                {
                    fs::create_dir_all(parent)?;
                }
                write(&path, &plan.candidate)?;
                if main.is_none() {
                    verify_profile_main_guard(paths, main_guard.as_deref())?;
                }
            }
            entry.replaced = true;
            // A write may have succeeded before its acknowledgement failed; recovery uses bytes.
            write_journal(&directory, journal)?;
        }
        journal.phase = MigrationPhase::Committing;
        write_journal(&directory, journal)?;
    }
    for entry in &journal.resources {
        validate_lsp_disk_state(paths, entry)?;
        ensure!(
            digest(&read_resource_disk_bytes(
                paths,
                entry.document,
                &entry.relative_path,
            )?) == entry.candidate_hash,
            "resource did not reach its verified candidate"
        );
    }
    if main.is_none() {
        verify_profile_main_guard(paths, main_guard.as_deref())?;
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

    fn schema_31_with_lsp(store: &ConfigStore) -> Vec<u8> {
        schema_31_with_lsp_operations(store, None)
    }

    fn schema_31_with_lsp_operations(store: &ConfigStore, operations: Option<&[&str]>) -> Vec<u8> {
        let mut main: toml::Value =
            toml::from_str(&fs::read_to_string(store.paths().config_file()).unwrap()).unwrap();
        main["schema_version"] = toml::Value::Integer(31);
        let mut server = toml::Table::new();
        server.insert("command".into(), "language-server".into());
        server.insert(
            "args".into(),
            toml::Value::Array(vec!["--stdio".into(), "--verbose".into()]),
        );
        server.insert(
            "language_ids".into(),
            toml::Value::Array(vec!["rust".into(), "toml".into()]),
        );
        server.insert(
            "detection".into(),
            toml::Value::Array(vec!["Cargo.toml".into()]),
        );
        server.insert(
            "extensions".into(),
            toml::Value::Array(vec![".rs".into(), ".toml".into()]),
        );
        server.insert("display_name".into(), "Custom language service".into());
        if let Some(operations) = operations {
            server.insert(
                "operations".into(),
                toml::Value::Array(
                    operations
                        .iter()
                        .map(|operation| toml::Value::String((*operation).to_owned()))
                        .collect(),
                ),
            );
        }
        let mut servers = toml::Table::new();
        servers.insert("rust.custom-server".into(), toml::Value::Table(server));
        let mut lsp = toml::Table::new();
        lsp.insert("servers".into(), toml::Value::Table(servers));
        main.as_table_mut()
            .unwrap()
            .insert("lsp".into(), toml::Value::Table(lsp));
        toml::to_string(&main).unwrap().into_bytes()
    }

    fn remove_post_27_authentication(main: &mut toml::Value) {
        if let Some(accounts) = main
            .get_mut("models")
            .and_then(|models| models.get_mut("accounts"))
            .and_then(toml::Value::as_table_mut)
        {
            for (_, account) in accounts.iter_mut() {
                let account = account.as_table_mut().unwrap();
                account.remove("authentication");
                account.remove("chatgpt_account");
            }
        }
    }

    #[test]
    fn schema_31_lsp_servers_are_extracted_and_removed_without_losing_fields() {
        let (_directory, store) = fixture();
        let original = schema_31_with_lsp(&store);
        fs::write(store.paths().config_file(), &original).unwrap();

        let migrated = store.load_for_startup().unwrap();

        let document_path = store
            .paths()
            .config_dir()
            .join("lsp/host/rust.custom-server.toml");
        let document: toml::Value =
            toml::from_str(&fs::read_to_string(document_path).unwrap()).unwrap();
        assert_eq!(document["schema_version"].as_integer(), Some(1));
        assert_eq!(document["id"].as_str(), Some("rust.custom-server"));
        assert_eq!(document["command"].as_str(), Some("language-server"));
        assert_eq!(document["args"][0].as_str(), Some("--stdio"));
        assert_eq!(document["args"][1].as_str(), Some("--verbose"));
        assert_eq!(document["language_ids"][0].as_str(), Some("rust"));
        assert_eq!(document["language_ids"][1].as_str(), Some("toml"));
        assert_eq!(document["detection"][0].as_str(), Some("Cargo.toml"));
        assert_eq!(document["extensions"][0].as_str(), Some(".rs"));
        assert_eq!(
            document["display_name"].as_str(),
            Some("Custom language service")
        );

        let main: toml::Value =
            toml::from_str(&fs::read_to_string(store.paths().config_file()).unwrap()).unwrap();
        assert_eq!(main["schema_version"].as_integer(), Some(32));
        assert!(main.get("lsp").is_none());
        assert_eq!(migrated.schema_version, 32);
        assert!(migrated.validate_declarations().is_ok());
        assert!(!operation_dir(store.paths()).exists());
        let backups: Vec<_> = fs::read_dir(store.paths().config_dir())
            .unwrap()
            .map(|entry| entry.unwrap().path())
            .filter(|path| {
                path.file_name()
                    .and_then(|name| name.to_str())
                    .is_some_and(|name| name.contains(".migrated."))
            })
            .collect();
        assert_eq!(backups.len(), 1);
        assert_eq!(fs::read(&backups[0]).unwrap(), original);
    }

    #[test]
    fn schema_31_lsp_operations_keep_legacy_effective_catalog_behavior() {
        for operations in [None, Some(&[][..]), Some(&["hover"][..])] {
            let (_directory, store) = fixture();
            let original = schema_31_with_lsp_operations(&store, operations);
            let original_main: toml::Value =
                toml::from_str(std::str::from_utf8(&original).unwrap()).unwrap();
            let old_lsp: crate::config::document_migration::wire::StudioLspConfig =
                original_main["lsp"].clone().try_into().unwrap();
            let old_config = &old_lsp.servers["rust.custom-server"];
            let expected_effective = if old_config.operations.is_empty() {
                pl_lsp::query::LspQueryOperation::all().to_vec()
            } else {
                old_config
                    .operations
                    .iter()
                    .map(|operation| {
                        serde_json::from_value(serde_json::to_value(operation).unwrap()).unwrap()
                    })
                    .collect()
            };
            fs::write(store.paths().config_file(), &original).unwrap();

            store.load_for_startup().unwrap();

            let path = store
                .paths()
                .config_dir()
                .join("lsp/host/rust.custom-server.toml");
            let migrated_source = fs::read_to_string(path).unwrap();
            let migrated = pl_lsp::catalog::LspServerDocument::parse(&migrated_source).unwrap();
            let actual_effective = migrated
                .config
                .to_catalog_server("rust.custom-server")
                .definition
                .operations;
            assert_eq!(actual_effective, expected_effective);
            match operations {
                None | Some([]) => assert!(!migrated_source.contains("operations")),
                Some(_) => assert!(migrated_source.contains("operations")),
            }
        }
    }

    #[test]
    fn schema_31_lsp_conflict_does_not_overwrite_existing_file_or_main() {
        let (_directory, store) = fixture();
        let original = schema_31_with_lsp(&store);
        fs::write(store.paths().config_file(), &original).unwrap();
        let target = store
            .paths()
            .config_dir()
            .join("lsp/host/rust.custom-server.toml");
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        let conflict = b"local user document\n";
        fs::write(&target, conflict).unwrap();

        assert!(store.load_for_startup().is_err());

        assert_eq!(fs::read(store.paths().config_file()).unwrap(), original);
        assert_eq!(fs::read(target).unwrap(), conflict);
    }

    #[test]
    fn schema_31_lsp_migration_resumes_after_main_candidate_was_written() {
        let (_directory, store) = fixture();
        let original = schema_31_with_lsp(&store);
        fs::write(store.paths().config_file(), &original).unwrap();
        let lsp_target = store
            .paths()
            .config_dir()
            .join("lsp/host/rust.custom-server.toml");
        let credentials = MemoryCredentialStore::default();
        let failed = prepare(
            store.paths(),
            &credentials,
            Some(&original),
            &|path, bytes| {
                if path == lsp_target {
                    return Err(PureError::ConfigError(
                        "simulated interruption before LSP resource write".into(),
                    ));
                }
                atomic_write(path, bytes)
            },
        );
        assert!(failed.is_err());
        assert!(!lsp_target.exists());
        assert_eq!(
            toml::from_str::<toml::Value>(
                &fs::read_to_string(store.paths().config_file()).unwrap()
            )
            .unwrap()["schema_version"]
                .as_integer(),
            Some(32)
        );
        assert!(
            operation_dir(store.paths())
                .join(JOURNAL_FILE_NAME)
                .exists()
        );

        super::super::resume_for_startup(store.paths(), &credentials).unwrap();

        assert!(lsp_target.exists());
        assert!(!operation_dir(store.paths()).exists());
        let current: toml::Value =
            toml::from_str(&fs::read_to_string(store.paths().config_file()).unwrap()).unwrap();
        assert!(current.get("lsp").is_none());
    }

    fn write_profile_only_journal(
        store: &ConfigStore,
        main_schema: Option<u32>,
    ) -> (Option<Vec<u8>>, Vec<u8>, Vec<u8>, Vec<u8>) {
        let paths = store.paths();
        let main_bytes = if let Some(schema) = main_schema {
            let mut main: toml::Value =
                toml::from_str(&fs::read_to_string(paths.config_file()).unwrap()).unwrap();
            main["schema_version"] = schema.into();
            if schema < 28 {
                remove_post_27_authentication(&mut main);
            }
            let bytes = toml::to_string(&main).unwrap().into_bytes();
            fs::write(paths.config_file(), &bytes).unwrap();
            Some(bytes)
        } else {
            fs::remove_file(paths.config_file()).unwrap();
            None
        };

        let profile_path = paths.agents_dir().join("saved.toml");
        let profile_original = IMPORT.as_bytes().to_vec();
        let profile_document = load_profile(
            &profile_path,
            std::str::from_utf8(&profile_original).unwrap(),
        )
        .unwrap();
        let profile_candidate = profile_document.document.encode().unwrap().into_bytes();
        fs::write(&profile_path, &profile_original).unwrap();

        let plan = ResourcePlan {
            relative_path: "agents/saved.toml".into(),
            original: profile_original.clone(),
            candidate: profile_candidate.clone(),
        };
        let directory = operation_dir(paths);
        write_protected(&directory, ORIGINAL_DIR_NAME, &plan, &plan.original).unwrap();
        write_protected(&directory, CANDIDATE_DIR_NAME, &plan, &plan.candidate).unwrap();
        let journal = Journal {
            version: VERSION,
            operation_id: format!("schema-{}-profile-only", main_schema.unwrap_or_default()),
            phase: MigrationPhase::Prepared,
            unchanged_main_hash: main_bytes.as_deref().map(digest),
            resources: vec![resource(&plan, DocumentFamily::Profile, None, 2)],
        };
        write_journal(&directory, &journal).unwrap();
        let journal_bytes = fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap();
        (
            main_bytes,
            profile_original,
            profile_candidate,
            journal_bytes,
        )
    }

    #[test]
    fn historical_profile_only_journal_resumes_then_upgrades_main_to_current() {
        for schema in [27, 28] {
            let (_directory, store) = fixture();
            let paths = store.paths();
            let (Some(main_before), _profile_original, profile_candidate, _journal_bytes) =
                write_profile_only_journal(&store, Some(schema))
            else {
                unreachable!("schema-27 fixture must include a main document");
            };

            let loaded = store.load_for_startup().unwrap();

            assert_eq!(
                loaded.schema_version,
                crate::config::STUDIO_CONFIG_SCHEMA_VERSION
            );
            assert_eq!(
                toml::from_str::<toml::Value>(&fs::read_to_string(paths.config_file()).unwrap())
                    .unwrap()["schema_version"],
                crate::config::STUDIO_CONFIG_SCHEMA_VERSION.into()
            );
            assert_ne!(fs::read(paths.config_file()).unwrap(), main_before);
            assert_eq!(
                fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
                profile_candidate
            );
            assert!(!operation_dir(paths).exists());
            assert_eq!(store.load_for_startup().unwrap(), loaded);
            assert!(!operation_dir(paths).exists());
        }
    }

    #[test]
    fn schema27_profile_only_journal_preserves_resources_on_external_main_edit() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let (_main_before, profile_original, profile_candidate, journal_before) =
            write_profile_only_journal(&store, Some(27));
        let external_main = {
            let mut bytes = fs::read(paths.config_file()).unwrap();
            bytes.extend_from_slice(b"\n# concurrent external edit\n");
            bytes
        };
        fs::write(paths.config_file(), &external_main).unwrap();

        assert!(store.load_for_startup().is_err());

        assert_eq!(fs::read(paths.config_file()).unwrap(), external_main);
        assert_eq!(
            fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
            profile_original
        );
        let directory = operation_dir(paths);
        assert_eq!(
            fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap(),
            journal_before
        );
        assert_eq!(
            fs::read(directory.join(CANDIDATE_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_candidate
        );
        assert_eq!(
            fs::read(directory.join(ORIGINAL_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_original
        );
    }

    #[test]
    fn missing_main_profile_only_journal_resumes_without_creating_main() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let (main_before, profile_original, profile_candidate, _journal_before) =
            write_profile_only_journal(&store, None);
        assert!(main_before.is_none());
        assert!(!paths.config_file().exists());

        let loaded = store.load_for_startup().unwrap();

        assert_eq!(
            loaded.schema_version,
            crate::config::STUDIO_CONFIG_SCHEMA_VERSION
        );
        assert_eq!(
            fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
            profile_candidate
        );
        assert_ne!(
            fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
            profile_original
        );
        assert!(!paths.config_file().exists());
        assert!(!operation_dir(paths).exists());
        assert_eq!(store.load_for_startup().unwrap(), loaded);
        assert!(!paths.config_file().exists());
        assert!(!operation_dir(paths).exists());
    }

    #[test]
    fn missing_main_profile_only_journal_rejects_main_created_during_recovery() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let (_, profile_original, profile_candidate, journal_before) =
            write_profile_only_journal(&store, None);
        let appeared_main = toml::to_string(&StudioConfig::default_config().unwrap())
            .unwrap()
            .into_bytes();
        fs::write(paths.config_file(), &appeared_main).unwrap();

        assert!(store.load_for_startup().is_err());

        assert_eq!(fs::read(paths.config_file()).unwrap(), appeared_main);
        assert_eq!(
            fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
            profile_original
        );
        let directory = operation_dir(paths);
        assert_eq!(
            fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap(),
            journal_before
        );
        assert_eq!(
            fs::read(directory.join(CANDIDATE_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_candidate
        );
        assert_eq!(
            fs::read(directory.join(ORIGINAL_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_original
        );
    }

    #[cfg(unix)]
    #[test]
    fn missing_main_profile_only_journal_rejects_dangling_main_link() {
        use std::os::unix::fs::symlink;

        let (_directory, store) = fixture();
        let paths = store.paths();
        let (_, profile_original, profile_candidate, journal_before) =
            write_profile_only_journal(&store, None);
        symlink("missing-main-target", paths.config_file()).unwrap();

        assert!(store.load_for_startup().is_err());

        assert!(
            fs::symlink_metadata(paths.config_file())
                .unwrap()
                .file_type()
                .is_symlink()
        );
        assert_eq!(
            fs::read(paths.agents_dir().join("saved.toml")).unwrap(),
            profile_original
        );
        let directory = operation_dir(paths);
        assert_eq!(
            fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap(),
            journal_before
        );
        assert_eq!(
            fs::read(directory.join(CANDIDATE_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_candidate
        );
        assert_eq!(
            fs::read(directory.join(ORIGINAL_DIR_NAME).join("agents/saved.toml")).unwrap(),
            profile_original
        );
    }

    #[test]
    fn recorded_schema_27_resource_candidate_is_committed_byte_for_byte() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let mut current = toml::Value::try_from(StudioConfig::default_config().unwrap()).unwrap();
        remove_post_27_authentication(&mut current);
        let mut original = current.clone();
        original["schema_version"] = 26.into();
        let original = toml::to_string(&original).unwrap().into_bytes();
        current["schema_version"] = 27.into();
        current
            .as_table_mut()
            .unwrap()
            .entry("skills")
            .or_insert_with(|| toml::Value::Table(toml::Table::new()));
        current["skills"]
            .as_table_mut()
            .unwrap()
            .insert("user_dir".into(), "~/.anywork/skills".into());
        let candidate = toml::to_string(&current).unwrap().into_bytes();
        fs::write(paths.config_file(), &original).unwrap();

        let plan = ResourcePlan {
            relative_path: STUDIO_CONFIG_FILE_NAME.into(),
            original,
            candidate,
        };
        let resource = resource(&plan, DocumentFamily::Main, Some(26), 27);
        let directory = operation_dir(paths);
        write_protected(&directory, ORIGINAL_DIR_NAME, &plan, &plan.original).unwrap();
        write_protected(&directory, CANDIDATE_DIR_NAME, &plan, &plan.candidate).unwrap();
        let journal = Journal {
            version: VERSION,
            operation_id: "historical-26-to-27".into(),
            phase: MigrationPhase::Prepared,
            unchanged_main_hash: None,
            resources: vec![resource],
        };
        write_journal(&directory, &journal).unwrap();
        let journal_bytes = fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap();

        let recovered = resume(paths, &MemoryCredentialStore::default(), &journal_bytes).unwrap();

        assert_eq!(
            recovered.schema_version,
            crate::config::STUDIO_CONFIG_SCHEMA_VERSION
        );
        assert_eq!(fs::read(paths.config_file()).unwrap(), plan.candidate);
        assert_eq!(digest(&plan.candidate), journal.resources[0].candidate_hash);
        assert!(!directory.exists());
    }

    #[test]
    fn recorded_schema_28_candidate_is_committed_before_next_migration() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let mut candidate = toml::Value::try_from(StudioConfig::default_config().unwrap()).unwrap();
        candidate["schema_version"] = 28.into();
        candidate
            .as_table_mut()
            .unwrap()
            .entry("skills")
            .or_insert_with(|| toml::Value::Table(toml::Table::new()));
        candidate["skills"]
            .as_table_mut()
            .unwrap()
            .insert("user_dir".into(), "~/.anywork/skills".into());
        let mut original = candidate.clone();
        original["schema_version"] = 27.into();
        remove_post_27_authentication(&mut original);
        let plan = ResourcePlan {
            relative_path: STUDIO_CONFIG_FILE_NAME.into(),
            original: toml::to_string(&original).unwrap().into_bytes(),
            candidate: toml::to_string(&candidate).unwrap().into_bytes(),
        };
        fs::write(paths.config_file(), &plan.original).unwrap();
        let directory = operation_dir(paths);
        write_protected(&directory, ORIGINAL_DIR_NAME, &plan, &plan.original).unwrap();
        write_protected(&directory, CANDIDATE_DIR_NAME, &plan, &plan.candidate).unwrap();
        let journal = Journal {
            version: VERSION,
            operation_id: "historical-27-to-28".into(),
            phase: MigrationPhase::Prepared,
            unchanged_main_hash: None,
            resources: vec![resource(&plan, DocumentFamily::Main, Some(27), 28)],
        };
        write_journal(&directory, &journal).unwrap();
        let journal_bytes = fs::read(directory.join(JOURNAL_FILE_NAME)).unwrap();
        resume(paths, &MemoryCredentialStore::default(), &journal_bytes).unwrap();
        assert_eq!(fs::read(paths.config_file()).unwrap(), plan.candidate);
        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert_eq!(store.load_for_startup().unwrap(), loaded);
        assert!(!directory.exists());
    }

    #[test]
    fn current_main_imports_later_profile_without_replacing_main_and_resumes_after_lost_ack() {
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
        assert_eq!(journal.resources[0].target_version, 2);
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
            let pl_protocol::AgentBinding::Native(native) = &mut profile.binding else {
                panic!("imported Profile must be Native");
            };
            let route = native.route.as_mut().expect("imported Native route");
            route.account_id = account_id.to_string();
            profile.enabled = enabled;
            route.effort = Some("high".into());
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
                    .find(|profile| profile.definition.definition_id == "saved")
                    .expect("unavailable Profile stays in the editable settings catalog");
                let pl_protocol::AgentBinding::Native(native) = &saved.binding else {
                    panic!("saved Profile must be Native");
                };
                assert_eq!(
                    native
                        .route
                        .as_ref()
                        .expect("saved Native route")
                        .account_id,
                    "profile-only"
                );
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
                        .any(|profile| profile.definition.definition_id == "saved")
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

            let pl_protocol::AgentBinding::Native(native) = &mut profile.binding else {
                panic!("saved Profile must be Native");
            };
            native
                .route
                .as_mut()
                .expect("saved Native route")
                .account_id = "deepseek".into();
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
                .find(|profile| profile.definition.definition_id == "saved")
                .unwrap();
            let pl_protocol::AgentBinding::Native(native) = &saved.binding else {
                panic!("repaired Profile must be Native");
            };
            assert_eq!(
                native
                    .route
                    .as_ref()
                    .expect("repaired Native route")
                    .account_id,
                "deepseek"
            );
            assert_eq!(saved.enabled, enabled);
            assert_eq!(saved.definition.description, profile.description);
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

    #[test]
    fn schema_30_migrates_mcp_servers_and_builtins_to_single_files_and_rejects_mcp_in_v31() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let mut table: toml::Table =
            toml::from_str(&fs::read_to_string(paths.config_file()).unwrap()).unwrap();
        table.insert("schema_version".into(), 30.into());
        let mcp_table: toml::Value = toml::from_str(
            r#"
[builtin_servers.zhipu_search]
enabled = false

[servers.git_tools]
enabled = true
transport = "stdio"
command = "uvx"
args = ["mcp-server-git"]
cwd = "sub/dir"
"#,
        )
        .unwrap();
        table.insert("mcp".into(), mcp_table);
        let v30_bytes = toml::to_string_pretty(&table).unwrap().into_bytes();
        fs::write(paths.config_file(), &v30_bytes).unwrap();

        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);

        let migrated_main: toml::Table =
            toml::from_str(&fs::read_to_string(paths.config_file()).unwrap()).unwrap();
        assert_eq!(
            migrated_main
                .get("schema_version")
                .and_then(toml::Value::as_integer),
            Some(i64::from(STUDIO_CONFIG_SCHEMA_VERSION))
        );
        assert!(!migrated_main.contains_key("mcp"));

        let catalog = crate::config::McpCatalogResource::new(paths, &loaded.models);
        let host_snapshot = catalog
            .read_catalog(paths, &loaded.models, &pl_protocol::McpScope::Host)
            .unwrap();
        let git_entry = host_snapshot
            .entries
            .iter()
            .find(|e| e.id == "git_tools")
            .expect("migrated git_tools server must exist in Host catalog");
        assert_eq!(
            git_entry.config_status,
            pl_protocol::McpConfigStatusKind::Enabled
        );
        assert_eq!(
            git_entry.effective_source,
            pl_protocol::McpEffectiveSource::HostServer
        );
        let search_entry = host_snapshot
            .entries
            .iter()
            .find(|e| e.id == "zhipu_search")
            .expect("migrated zhipu_search builtin must exist in Host catalog");
        assert_eq!(
            search_entry.config_status,
            pl_protocol::McpConfigStatusKind::Disabled
        );

        // Verify the current schema rejects legacy [mcp] tables (no dual-read).
        let mut v31_with_mcp = migrated_main;
        v31_with_mcp.insert("mcp".into(), toml::Value::Table(toml::Table::new()));
        fs::write(
            paths.config_file(),
            toml::to_string_pretty(&v31_with_mcp).unwrap(),
        )
        .unwrap();
        assert!(store.load_for_startup().is_err());
    }

    #[test]
    fn schema_30_mcp_and_v1_profile_migration_recovers_idempotently_after_interrupted_commit() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let mut table: toml::Table =
            toml::from_str(&fs::read_to_string(paths.config_file()).unwrap()).unwrap();
        table.insert("schema_version".into(), 30.into());
        let mcp_table: toml::Value = toml::from_str(
            r#"
[servers.alpha]
enabled = true
transport = "streamableHttp"
url = "https://example.com/mcp"
"#,
        )
        .unwrap();
        table.insert("mcp".into(), mcp_table);
        let v30_bytes = toml::to_string_pretty(&table).unwrap().into_bytes();
        fs::write(paths.config_file(), &v30_bytes).unwrap();

        let profile_path = paths.agents_dir().join("saved.toml");
        let profile_v1 = format!(
            "schema_version = 1\n{}",
            IMPORT
                .replace("provider =", "account_id =")
                .replace("model =", "model_id =")
        );
        fs::write(&profile_path, profile_v1).unwrap();

        let credentials = MemoryCredentialStore::default();
        let writes = std::cell::Cell::new(0usize);
        let interrupted = prepare(paths, &credentials, Some(&v30_bytes), &|path, bytes| {
            writes.set(writes.get() + 1);
            atomic_write(path, bytes)?;
            if writes.get() == 2 {
                return Err(PureError::Io(std::io::Error::other(
                    "interrupted mid-MCP-migration",
                )));
            }
            Ok(())
        });
        assert!(interrupted.is_err());
        assert!(operation_dir(paths).join(JOURNAL_FILE_NAME).exists());

        let recovered = store.load_for_startup().unwrap();
        assert_eq!(recovered.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        assert!(!operation_dir(paths).exists());

        let catalog = crate::config::McpCatalogResource::new(paths, &recovered.models);
        let snapshot = catalog
            .read_catalog(paths, &recovered.models, &pl_protocol::McpScope::Host)
            .unwrap();
        let mcp_document = snapshot
            .entries
            .iter()
            .find(|entry| entry.id == "alpha")
            .and_then(|entry| entry.document.as_ref())
            .expect("migrated server must retain its document identity");

        let profile_bytes = fs::read_to_string(&profile_path).unwrap();
        let loaded_profile = load_profile(&profile_path, &profile_bytes).unwrap();
        assert_eq!(loaded_profile.source_version, 2);
        assert!(!loaded_profile.migrated);
        let profile = loaded_profile.document.into_profile().unwrap();
        assert!(!profile.enabled);
        let pl_protocol::AgentBinding::Native(native) = profile.binding else {
            panic!("migrated Profile must retain its Native binding");
        };
        let route = native.route.unwrap();
        assert_eq!(route.account_id, "deepseek");
        assert_eq!(route.model_id, "deepseek-flash");
        assert_eq!(
            native.system_instructions.as_deref(),
            Some("Saved instructions")
        );

        let main_bytes = fs::read(paths.config_file()).unwrap();
        let mcp_path = crate::config::resolve_document_path(paths, mcp_document).unwrap();
        let mcp_bytes = fs::read(&mcp_path).unwrap();
        assert_eq!(store.load_for_startup().unwrap(), recovered);
        assert_eq!(fs::read(paths.config_file()).unwrap(), main_bytes);
        assert_eq!(fs::read_to_string(profile_path).unwrap(), profile_bytes);
        assert_eq!(fs::read(mcp_path).unwrap(), mcp_bytes);
        assert!(!operation_dir(paths).exists());
    }

    #[test]
    fn schema_30_invalid_disabled_legacy_mcp_server_migrates_to_diagnostic_file() {
        let (_directory, store) = fixture();
        let paths = store.paths();
        let mut table: toml::Table =
            toml::from_str(&fs::read_to_string(paths.config_file()).unwrap()).unwrap();
        table.insert("schema_version".into(), 30.into());
        let mcp_table: toml::Value = toml::from_str(
            r#"
[servers.broken_disabled]
enabled = false
transport = "stdio"
"#,
        )
        .unwrap();
        table.insert("mcp".into(), mcp_table);
        let v30_bytes = toml::to_string_pretty(&table).unwrap().into_bytes();
        fs::write(paths.config_file(), &v30_bytes).unwrap();

        let loaded = store.load_for_startup().unwrap();
        assert_eq!(loaded.schema_version, STUDIO_CONFIG_SCHEMA_VERSION);
        let catalog = crate::config::McpCatalogResource::new(paths, &loaded.models);
        let snapshot = catalog
            .read_catalog(paths, &loaded.models, &pl_protocol::McpScope::Host)
            .unwrap();
        let broken = snapshot
            .entries
            .iter()
            .find(|e| e.id == "broken_disabled")
            .expect("broken_disabled should surface as InvalidDocument entry");
        assert_eq!(
            broken.config_status,
            pl_protocol::McpConfigStatusKind::InvalidDocument
        );
        assert!(
            snapshot
                .diagnostics
                .iter()
                .any(|d| d.id.as_deref() == Some("broken_disabled"))
        );
    }
}
