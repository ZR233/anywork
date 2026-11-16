#![cfg(feature = "live-tests")]
//! Explicit real-account/project acceptance; never part of ordinary offline tests.
use anyhow::{Context, Result, ensure};
use pl_model::config::{AccountId, ModelRouteConfig, ReasoningEffort};
use pl_studio_runtime::{ConfigPaths, ConfigStore, ResultV2, export_sha256_hex, history::*};
use sea_orm::{Database, TransactionTrait};
use std::{
    path::{Path, PathBuf},
    process::Stdio,
};
use tokio::io::AsyncWriteExt;

fn input(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("explicit live input {name} is required"))
}

#[tokio::test]
#[ignore = "requires explicit user authorization, account, project, prompt and an isolated output root"]
async fn real_account_project_exports_and_converts_its_history() -> Result<()> {
    let account_id = input("ANYWK_HISTORY_LIVE_ACCOUNT")?;
    let model_id = input("ANYWK_HISTORY_LIVE_MODEL")?;
    let effort = std::env::var("ANYWK_HISTORY_LIVE_EFFORT").ok();
    let project = PathBuf::from(input("ANYWK_HISTORY_LIVE_PROJECT")?).canonicalize()?;
    let prompt = std::fs::read(input("ANYWK_HISTORY_LIVE_PROMPT")?)?;
    let output = PathBuf::from(input("ANYWK_HISTORY_LIVE_OUTPUT")?);
    ensure!(
        output.is_absolute() && !output.exists(),
        "live output must be a new absolute directory"
    );
    let source = ConfigStore::default_app()?;
    let source_path = source.paths().config_file();
    let before = std::fs::read(source_path)?;
    let mut config = source.load()?;
    let selected = config
        .models
        .accounts
        .get(&AccountId::new(&account_id)?)
        .context("live account is not configured")?;
    let secret = selected
        .bearer_token
        .clone()
        .or_else(|| {
            selected
                .bearer_token_env
                .as_deref()
                .and_then(|name| std::env::var(name).ok())
        })
        .context("selected live account has no readable credential")?;
    let selected_route = ModelRouteConfig {
        account_id: AccountId::new(&account_id)?,
        model_id: model_id.clone(),
        effort: effort.clone().map(ReasoningEffort::new),
    };
    let role = config
        .models
        .routes
        .keys()
        .next()
        .cloned()
        .context("configured model route")?;
    config.models.resolve_route(role, &selected_route)?;
    config
        .models
        .accounts
        .retain(|id, _| id.as_str() == account_id);
    for account in config.models.accounts.values_mut() {
        account.bearer_token = None;
        account.bearer_token_env = Some("ANYWK_HISTORY_LIVE_SECRET".into());
    }
    for route in config
        .models
        .routes
        .values_mut()
        .chain(config.mode_model_routes.values_mut())
    {
        *route = selected_route.clone();
    }
    config.runtime.tool_capabilities.mcp = false;
    config.skills.auto_learn = false;
    config.skills.external_dirs.clear();
    config.skills.system.enabled = false;
    std::fs::create_dir_all(&output)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&output, std::fs::Permissions::from_mode(0o700))?;
    }
    let home = output.join("home");
    ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
    let archive = output.join("export");
    let mut command = tokio::process::Command::new(env!("CARGO_BIN_EXE_anywk"));
    command
        .args(["exec", "--studio-home"])
        .arg(&home)
        .arg("--cwd")
        .arg(&project)
        .args([
            "--account",
            &account_id,
            "--model",
            &model_id,
            "--prompt-file",
            "-",
            "--max-model-steps",
            "32",
            "--no-default-user-skills",
            "--output-dir",
        ])
        .arg(&archive)
        .env("ANYWK_HISTORY_LIVE_SECRET", &secret)
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .kill_on_drop(true);
    if let Some(effort) = &effort {
        command.args(["--reasoning-effort", effort]);
    }
    let mut child = command.spawn()?;
    child
        .stdin
        .take()
        .context("live CLI stdin")?
        .write_all(&prompt)
        .await?;
    let result = child.wait_with_output().await?;
    // Raw credentials remain solely in memory and the child environment. Preserve sanitized
    // product diagnostics and verify the source config even when the real run fails.
    std::fs::write(
        output.join("stdout.txt"),
        String::from_utf8_lossy(&result.stdout).replace(&secret, "[REDACTED]"),
    )?;
    std::fs::write(
        output.join("stderr.txt"),
        String::from_utf8_lossy(&result.stderr).replace(&secret, "[REDACTED]"),
    )?;
    ensure!(
        std::fs::read(source_path)? == before,
        "live source config changed"
    );
    ensure!(
        result.status.success(),
        "real project execution failed: {:?}; sanitized evidence: {}",
        result.status.code(),
        output.display()
    );
    let result: ResultV2 = serde_json::from_slice(&std::fs::read(archive.join("result.json"))?)?;
    let thread = result
        .root_thread_id
        .context("real run has no root Thread")?;
    let histories = histories(&home.join("data/workspaces"))?;
    ensure!(
        !histories.is_empty(),
        "real run produced no history database"
    );
    let mut originals = 0usize;
    let mut bytes = 0u64;
    let mut metadata_bytes = 0u64;
    // This stage exercises conversion primitives and canonical byte integrity. Rewriting product
    // refs, Timeline imports and enabling schema 25 in production remain issue #470.
    for (index, history) in histories.iter().enumerate() {
        let mut options = sea_orm::ConnectOptions::new("sqlite:");
        let history_path = history.clone();
        options
            .map_sqlx_sqlite_opts(move |options| options.filename(&history_path).read_only(true));
        let db = Database::connect(options).await?;
        use sea_orm::ConnectionTrait;
        let row = db
            .query_one_raw(sea_orm::Statement::from_string(
                sea_orm::DatabaseBackend::Sqlite,
                "SELECT thread_id FROM history_meta WHERE id=1",
            ))
            .await?
            .context("real history identity")?;
        let thread_id: String = row.try_get("", "thread_id")?;
        db.close().await?;
        let source = V24HistorySource::open(history, &thread_id).await?;
        let target = output.join(format!("history-{index}.sqlite"));
        let store = HistoryStore::open(&target, &thread_id, HistoryLimits::default()).await?;
        let database_id = store.database_id().to_owned();
        store.close().await?;
        let mut options = sea_orm::ConnectOptions::new("sqlite:");
        let target_path = target.clone();
        options
            .map_sqlx_sqlite_opts(move |options| options.filename(&target_path).foreign_keys(true));
        let db = Database::connect(options).await?;
        let tx = db.begin().await?;
        let mut importer = HistoryImport::new(&tx, database_id).await?;
        let mut after = 0;
        let mut local = 0;
        loop {
            let page = source.originals_page(after, 128).await?;
            if page.is_empty() {
                break;
            }
            for original in page {
                after = original.seq;
                let payload = source
                    .body(V24Body::Payload {
                        item_id: original.item_id.clone(),
                    })
                    .await?;
                let reference = importer
                    .copy_body(
                        HistoryImportBody {
                            body_id: uuid::Uuid::new_v4().to_string(),
                            owner_event_id: original.item_id.clone(),
                            ordinal: 0,
                            body_key: "canonical".into(),
                            role: HistoryBodyRole::CanonicalPayload,
                            media_type: Some("application/json".into()),
                        },
                        &payload,
                    )
                    .await?;
                let metadata = source
                    .body(V24Body::Metadata {
                        item_id: original.item_id.clone(),
                    })
                    .await?;
                importer
                    .copy_body(
                        HistoryImportBody {
                            body_id: uuid::Uuid::new_v4().to_string(),
                            owner_event_id: original.item_id.clone(),
                            ordinal: 1,
                            body_key: "canonical_metadata".into(),
                            role: HistoryBodyRole::CanonicalMetadata,
                            media_type: Some("application/json".into()),
                        },
                        &metadata,
                    )
                    .await?;
                let recorded_at = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)?
                    .as_millis()
                    .try_into()?;
                let mut event = HistoryEvent::new(
                    original.item_id,
                    HistoryEventKind::LegacyObserved,
                    recorded_at,
                );
                event.payload_body_id = Some(reference.body_id);
                importer.insert_event(event).await?;
                bytes += payload.byte_length();
                metadata_bytes += metadata.byte_length();
                originals += 1;
                local += 1;
            }
        }
        importer.finish().await?;
        tx.commit().await?;
        db.close().await?;
        source.close().await?;
        let store = HistoryStore::open(&target, &thread_id, HistoryLimits::default()).await?;
        let reader = store.reader();
        let mut cursor = None;
        let mut loaded = 0;
        loop {
            let page = reader
                .events_page(
                    HistoryEventsQuery::AllEvents,
                    None,
                    cursor.take(),
                    HistoryDemand::default(),
                )
                .await?;
            for event in &page.entries {
                ensure!(event.payload_ref.is_some(), "imported payload");
                let bodies = reader
                    .list_bodies(
                        event.header.event_id.clone(),
                        None,
                        HistoryDemand::default(),
                    )
                    .await?;
                ensure!(
                    bodies.entries.len() == 2 && bodies.next.is_none(),
                    "real canonical body list differs"
                );
                for body in bodies.entries {
                    reader.verify_body(body.reference).await?;
                }
            }
            loaded += page.entries.len();
            cursor = page.next;
            if cursor.is_none() {
                break;
            }
        }
        ensure!(loaded == local, "imported real originals differ");
        reader.close().await;
        store.close().await?;
    }
    ensure!(originals != 0, "real run has no canonical originals");
    std::fs::write(
        output.join("verification.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "model":model_id,"effort":effort,"account":account_id,"rootThread":thread,"sourceConfigSha256":export_sha256_hex(&before),"sourceConfigUnchanged":true,
            "historyDatabases":histories.len(),"convertedOriginals":originals,"verifiedPayloadBytes":bytes,"verifiedMetadataBytes":metadata_bytes,"productionSchema":24,"independentTargetSchema":25
        }))?,
    )?;
    println!("real project acceptance: {}", output.display());
    Ok(())
}

fn histories(root: &Path) -> Result<Vec<PathBuf>> {
    let mut result = Vec::new();
    for workspace in std::fs::read_dir(root)? {
        let sessions = workspace?.path().join("sessions");
        if !sessions.is_dir() {
            continue;
        }
        for session in std::fs::read_dir(sessions)? {
            let history = session?.path().join("history.sqlite");
            if history.is_file() {
                result.push(history);
            }
        }
    }
    Ok(result)
}
