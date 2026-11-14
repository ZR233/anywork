//! Output directory validation, sanitized startup manifest generation, and atomic JSON writes.

use std::collections::BTreeMap;
use std::fs::{self, File};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};

use super::types::{
    BuildInfoV1, ConfigInputEntryV1, EVENTS_SCHEMA_VERSION, ExportSchemaV1, RESULT_SCHEMA_VERSION,
    RUN_MANIFEST_SCHEMA_VERSION, RunExportOptions, RunInvocationV1, RunManifestV1,
    SkillSearchManifestV1, format_utc_rfc3339,
};
use crate::config::StudioConfig;
use crate::studio::paths::StudioPaths;

const RUN_MANIFEST_FILE_NAME: &str = "run.json";
const RESULT_FILE_NAME: &str = "result.json";

/// Read-only preflight check that `--output-dir` either does not exist inside a writable
/// existing directory ancestor or is an existing empty writable non-symlink directory.
/// Does not create `output_dir` or `contents/`.
pub fn validate_output_dir_preflight(output_dir: &Path) -> Result<()> {
    match fs::symlink_metadata(output_dir) {
        Ok(meta) => {
            ensure!(
                !meta.file_type().is_symlink(),
                "output directory must not be a symlink: {}",
                output_dir.display()
            );
            ensure!(
                meta.is_dir(),
                "output path exists and is not a directory: {}",
                output_dir.display()
            );
            let mut entries = fs::read_dir(output_dir)
                .with_context(|| format!("read output directory {}", output_dir.display()))?;
            ensure!(
                entries.next().is_none(),
                "output directory must be empty: {}",
                output_dir.display()
            );
            probe_dir_writable(output_dir)?;
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            let mut ancestor = output_dir.parent();
            while let Some(dir) = ancestor {
                let probe_target = if dir.as_os_str().is_empty() {
                    Path::new(".")
                } else {
                    dir
                };
                match fs::symlink_metadata(probe_target) {
                    Ok(meta) => {
                        ensure!(
                            meta.is_dir(),
                            "output directory ancestor is not a directory: {}",
                            probe_target.display()
                        );
                        probe_dir_writable(probe_target)?;
                        return Ok(());
                    }
                    Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                        if dir.as_os_str().is_empty() {
                            break;
                        }
                        ancestor = dir.parent();
                    }
                    Err(err) => {
                        return Err(err).with_context(|| {
                            format!(
                                "inspect output directory ancestor {}",
                                probe_target.display()
                            )
                        });
                    }
                }
            }
        }
        Err(error) => {
            return Err(error)
                .with_context(|| format!("inspect output directory {}", output_dir.display()));
        }
    }
    Ok(())
}

fn probe_dir_writable(dir: &Path) -> Result<()> {
    let probe = temp_path(dir, ".write-probe");
    let res = (|| -> Result<()> {
        let mut file = File::create(&probe)
            .with_context(|| format!("verify output directory is writable: {}", dir.display()))?;
        file.write_all(b"")?;
        file.sync_all()?;
        Ok(())
    })();
    let _ = fs::remove_file(&probe);
    res
}

/// Validates that `--output-dir` does not exist or is an empty writable directory without
/// symlinks along the directory itself, creating it and `contents/` if needed.
pub fn prepare_output_dir(output_dir: &Path) -> Result<()> {
    match fs::symlink_metadata(output_dir) {
        Ok(meta) => {
            ensure!(
                !meta.file_type().is_symlink(),
                "output directory must not be a symlink: {}",
                output_dir.display()
            );
            ensure!(
                meta.is_dir(),
                "output path exists and is not a directory: {}",
                output_dir.display()
            );
            let mut entries = fs::read_dir(output_dir)
                .with_context(|| format!("read output directory {}", output_dir.display()))?;
            ensure!(
                entries.next().is_none(),
                "output directory must be empty: {}",
                output_dir.display()
            );
        }
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
            fs::create_dir_all(output_dir)
                .with_context(|| format!("create output directory {}", output_dir.display()))?;
        }
        Err(error) => {
            return Err(error)
                .with_context(|| format!("inspect output directory {}", output_dir.display()));
        }
    }
    let contents_dir = output_dir.join("contents");
    fs::create_dir_all(&contents_dir)
        .with_context(|| format!("create contents directory {}", contents_dir.display()))?;
    // Verify writability immediately at preflight before startup or mutations.
    probe_dir_writable(output_dir)?;
    Ok(())
}

/// Builds and atomically writes `run.json`, returning the manifest, its UTC timestamp, and SHA-256.
pub fn write_run_manifest(options: &RunExportOptions) -> Result<(RunManifestV1, String)> {
    let started_at = format_utc_rfc3339(SystemTime::now());
    let paths = StudioPaths::resolve(Some(options.studio_home.clone()))?;
    let config_paths = paths.config_paths();
    let config_inputs = collect_config_inputs(&paths, &config_paths, options.config.as_ref());
    let (external_dirs, system_enabled, skills_enabled) = match &options.config {
        Some(config) => (
            config.skills.external_dirs.clone(),
            config.skills.system.enabled,
            config.skills.enabled,
        ),
        None => read_skills_manifest_readonly(config_paths.config_file()),
    };
    let manifest = RunManifestV1 {
        schema_version: RUN_MANIFEST_SCHEMA_VERSION,
        run_id: options.run_id.clone(),
        started_at,
        build: BuildInfoV1::current(),
        invocation: RunInvocationV1 {
            cwd: options.cwd.to_string_lossy().into_owned(),
            studio_home: options.studio_home.to_string_lossy().into_owned(),
            account_id: options.account_id.clone(),
            model_id: options.model_id.clone(),
            reasoning_effort: options.reasoning_effort.clone(),
            mode: options.mode.clone(),
            max_model_steps: options.max_model_steps,
            prompt_sha256: options.prompt_sha256.clone(),
        },
        skill_search: SkillSearchManifestV1 {
            include_default_user_dir: options.skill_search.include_default_user_dir,
            additional_dirs: options
                .skill_search
                .additional_dirs
                .iter()
                .map(|path| path.to_string_lossy().into_owned())
                .collect(),
            external_dirs,
            system_enabled,
            skills_enabled,
        },
        config_inputs,
        export_schema: ExportSchemaV1 {
            manifest: RUN_MANIFEST_SCHEMA_VERSION,
            events: EVENTS_SCHEMA_VERSION,
            result: RESULT_SCHEMA_VERSION,
            content_addressing: "sha256".to_string(),
        },
    };
    let bytes = serde_json::to_vec_pretty(&manifest).context("serialize run.json")?;
    let mut with_newline = Vec::with_capacity(bytes.len() + 1);
    with_newline.extend_from_slice(&bytes);
    with_newline.push(b'\n');
    let sha256 = sha256_hex(&with_newline);
    write_file_atomic(
        &options.output_dir.join(RUN_MANIFEST_FILE_NAME),
        &with_newline,
    )
    .context("write run.json atomically")?;
    Ok((manifest, sha256))
}

/// Atomically writes `result.json` via temporary file, sync, and rename.
pub fn write_result_atomic(output_dir: &Path, result: &super::types::ResultV1) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(result).context("serialize result.json")?;
    let mut with_newline = Vec::with_capacity(bytes.len() + 1);
    with_newline.extend_from_slice(&bytes);
    with_newline.push(b'\n');
    write_file_atomic(&output_dir.join(RESULT_FILE_NAME), &with_newline)
        .context("write result.json atomically")
}

/// Writes bytes to a unique sibling temp file, fsyncs it, and renames over `target`.
pub fn write_file_atomic(target: &Path, bytes: &[u8]) -> Result<()> {
    let parent = target
        .parent()
        .context("atomic write target has no parent directory")?;
    let name = target
        .file_name()
        .and_then(|s| s.to_str())
        .unwrap_or("artifact");
    let temp = temp_path(parent, name);
    let write_res = (|| -> Result<()> {
        let mut file = File::create(&temp)
            .with_context(|| format!("create temporary artifact {}", temp.display()))?;
        file.write_all(bytes)?;
        file.sync_all()?;
        fs::rename(&temp, target)
            .with_context(|| format!("rename {} -> {}", temp.display(), target.display()))?;
        Ok(())
    })();
    if write_res.is_err() {
        let _ = fs::remove_file(&temp);
    }
    write_res
}

pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    hex::encode(hasher.finalize())
}

fn temp_path(dir: &Path, prefix: &str) -> PathBuf {
    let pid = std::process::id();
    let nonce = uuid::Uuid::new_v4().simple();
    dir.join(format!(".{prefix}.{pid}.{nonce}.tmp"))
}

fn collect_config_inputs(
    paths: &StudioPaths,
    config_paths: &crate::config::ConfigPaths,
    loaded_config: Option<&StudioConfig>,
) -> Vec<ConfigInputEntryV1> {
    let mut entries = Vec::new();
    entries.push(inspect_config_toml(
        config_paths.config_file(),
        loaded_config,
    ));
    collect_dir_inputs(
        &mut entries,
        config_paths.agents_dir().as_path(),
        "agents",
        Some("toml"),
    );
    collect_dir_inputs(&mut entries, config_paths.acp_dir().as_path(), "acp", None);
    collect_dir_inputs(
        &mut entries,
        config_paths.modes_dir().as_path(),
        "modes",
        Some("json"),
    );
    collect_dir_inputs(&mut entries, &paths.mcp_host_dir(), "mcp/host", None);
    entries
}

fn inspect_config_toml(path: &Path, loaded: Option<&StudioConfig>) -> ConfigInputEntryV1 {
    let raw = fs::read(path).ok();
    let sha256 = raw.as_deref().map(sha256_hex);
    let summary = loaded
        .and_then(|cfg| serde_json::to_value(cfg).ok())
        .map(sanitize_json_value)
        .or_else(|| {
            raw.as_deref()
                .and_then(|bytes| parse_and_sanitize("config.toml", bytes))
        });
    ConfigInputEntryV1 {
        logical_name: crate::config::STUDIO_CONFIG_FILE_NAME.to_string(),
        present: raw.is_some(),
        sha256,
        redacted_summary: summary,
    }
}

fn read_skills_manifest_readonly(path: &Path) -> (Vec<String>, bool, bool) {
    let Ok(text) = fs::read_to_string(path) else {
        return (Vec::new(), true, true);
    };
    let Ok(doc) = toml::from_str::<toml::Value>(&text) else {
        return (Vec::new(), true, true);
    };
    let Some(skills) = doc.get("skills").and_then(toml::Value::as_table) else {
        return (Vec::new(), true, true);
    };
    let enabled = skills
        .get("enabled")
        .and_then(toml::Value::as_bool)
        .unwrap_or(true);
    let system_enabled = skills
        .get("system")
        .and_then(toml::Value::as_table)
        .and_then(|system| system.get("enabled"))
        .and_then(toml::Value::as_bool)
        .unwrap_or(true);
    let external_dirs = skills
        .get("external_dirs")
        .and_then(toml::Value::as_array)
        .map(|items| {
            items
                .iter()
                .filter_map(|item| item.as_str().map(str::to_string))
                .collect()
        })
        .unwrap_or_default();
    (external_dirs, system_enabled, enabled)
}

fn collect_dir_inputs(
    out: &mut Vec<ConfigInputEntryV1>,
    dir: &Path,
    logical_prefix: &str,
    expected_ext: Option<&str>,
) {
    let Ok(read_dir) = fs::read_dir(dir) else {
        return;
    };
    let mut files: Vec<(String, PathBuf)> = Vec::new();
    for entry in read_dir.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        if let Some(ext) = expected_ext
            && path.extension().and_then(|s| s.to_str()) != Some(ext)
        {
            continue;
        }
        if let Some(name) = path.file_name().and_then(|s| s.to_str()) {
            files.push((format!("{logical_prefix}/{name}"), path));
        }
    }
    files.sort_by(|left, right| left.0.cmp(&right.0));
    for (logical_name, path) in files {
        let raw = fs::read(&path).ok();
        let sha256 = raw.as_deref().map(sha256_hex);
        let summary = raw
            .as_deref()
            .and_then(|bytes| parse_and_sanitize(&logical_name, bytes));
        out.push(ConfigInputEntryV1 {
            logical_name,
            present: true,
            sha256,
            redacted_summary: summary,
        });
    }
}

fn parse_and_sanitize(logical_name: &str, bytes: &[u8]) -> Option<serde_json::Value> {
    let text = std::str::from_utf8(bytes).ok()?;
    if logical_name.ends_with(".json") {
        let value: serde_json::Value = serde_json::from_str(text).ok()?;
        return Some(sanitize_json_value(value));
    }
    if logical_name.ends_with(".toml") {
        let value: toml::Value = toml::from_str(text).ok()?;
        let json = serde_json::to_value(value).ok()?;
        return Some(sanitize_json_value(json));
    }
    None
}

/// Strips inline secrets while keeping non-secret metadata and env var references.
pub fn sanitize_json_value(value: serde_json::Value) -> serde_json::Value {
    match value {
        serde_json::Value::Object(map) => {
            let mut out = serde_json::Map::with_capacity(map.len());
            let mut entries: BTreeMap<String, serde_json::Value> = map.into_iter().collect();
            for (key, val) in std::mem::take(&mut entries) {
                if is_secret_header_map_key(&key) {
                    if let serde_json::Value::Object(headers) = val {
                        let keys: Vec<serde_json::Value> = headers
                            .keys()
                            .map(|k| serde_json::Value::String(k.clone()))
                            .collect();
                        out.insert(key, serde_json::json!({ "redactedHeaderNames": keys }));
                    } else {
                        out.insert(key, serde_json::Value::String("[REDACTED]".to_string()));
                    }
                    continue;
                }
                if is_secret_value_key(&key) {
                    if !val.is_null() {
                        out.insert(key, serde_json::Value::String("[REDACTED]".to_string()));
                    } else {
                        out.insert(key, serde_json::Value::Null);
                    }
                    continue;
                }
                out.insert(key, sanitize_json_value(val));
            }
            serde_json::Value::Object(out)
        }
        serde_json::Value::Array(items) => {
            serde_json::Value::Array(items.into_iter().map(sanitize_json_value).collect())
        }
        other => other,
    }
}

fn is_secret_header_map_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    lower == "http_headers" || lower == "httpheaders" || lower == "headers" || lower == "env"
}

fn is_secret_value_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    // Preserve explicit environment variable *name* references while redacting inline values.
    if lower.ends_with("_env")
        || key.ends_with("Env")
        || lower.ends_with("_env_var")
        || lower.ends_with("envvar")
    {
        return false;
    }
    lower.contains("bearer_token")
        || lower.contains("bearertoken")
        || lower.contains("api_key")
        || lower.contains("apikey")
        || lower.contains("secret")
        || lower.contains("password")
        || lower.contains("private_key")
        || lower.contains("privatekey")
        || lower.contains("credentials")
        || lower == "token"
        || lower == "authorization"
        || lower == "chatgpt_session"
        || lower == "chatgptsession"
        || lower == "chatgpt_credentials"
        || lower == "chatgptcredentials"
}
