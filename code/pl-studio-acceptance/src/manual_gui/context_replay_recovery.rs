//! The same isolated session is opened by three completely new native GUI processes.
use super::*;
use sea_orm::sqlx::Row;

pub(super) fn run(
    context: &RecoveryScenario<'_>,
    mut fixture: OwnedProcess,
    ready: &FixtureReady,
) -> Result<()> {
    let project = context.working.join("replay-project");
    fs::create_dir(&project)?;
    ensure!(
        Command::new("git")
            .args(["init", "-q"])
            .arg(&project)
            .status()?
            .success(),
        "failed to initialize replay project"
    );
    let mut logs = Vec::new();
    let mut lifecycles = Vec::new();
    let journey = (|| -> Result<()> {
        for (label, profile) in [
            ("http", ModelTransportProfile::responses_http()),
            ("ws", ModelTransportProfile::responses_websocket()),
            ("chat", ModelTransportProfile::chat_completions_http()),
        ] {
            let home = context.home.join(label);
            let output = context.output.join(label);
            let coord = context.working.join(label);
            fs::create_dir(&home)?;
            fs::create_dir(&output)?;
            fs::create_dir(&coord)?;
            write_config_with_profile(&home, ready, profile, false)?;
            let mut prior_context = None;
            for phase in ["first", "restart", "recheck"] {
                let gui_log = coord.join(format!("{phase}-gui.log"));
                logs.push((gui_log.clone(), output.join(format!("{phase}-gui.log"))));
                let mut gui = start_recovery_gui(context.workspace, &home, &gui_log, false)?;
                let vm_url = wait_for_vm(&gui_log, &mut gui, &mut fixture, context.interrupt)?;
                let gui_launcher_pid = gui.child.id();
                if phase != "first" {
                    wait_operator_done(
                        &format!(
                            "context-replay {label}/{phase}: reopen {}, confirm the frozen context is restored and quiet, then type done.",
                            project.display()
                        ),
                        &mut gui,
                        Some(&mut fixture),
                        context.interrupt,
                        Duration::from_secs(3_600),
                    )?;
                    let thread_id = history_owner_thread(&home)?;
                    let restored = read_context(&home, &thread_id)?;
                    ensure!(
                        Some(&restored) == prior_context.as_ref(),
                        "{label}/{phase} changed frozen context during reopen"
                    );
                    let before = plan_recovery_settled_baseline(context.status_file)?;
                    thread::sleep(Duration::from_secs(2));
                    let after = plan_recovery_read_status(context.status_file)?;
                    ensure!(
                        before.total == after.total
                            && before.consumed_steps == after.consumed_steps
                            && after.rejected == 0,
                        "{label}/{phase} issued provider work while reopening"
                    );
                    fs::write(
                        output.join(format!("{phase}-quiet.json")),
                        serde_json::to_vec_pretty(
                            &serde_json::json!({"before":before,"after":after,"contextRestored":true}),
                        )?,
                    )?;
                }
                observe_capture_exit(
                    context.app_dir,
                    &vm_url,
                    &output,
                    context.interrupt,
                    &mut gui,
                    Some(&mut fixture),
                    &format!(
                        "context-replay {label}/{phase}: open {}, complete the replay observation, then type done.",
                        project.display()
                    ),
                )?;
                let _ = wait_for_gui_exit(&mut gui, Duration::from_secs(180), phase)?;
                drop(gui);
                lifecycles.push(serde_json::json!({
                    "protocol":label, "phase":phase, "guiLauncherPid":gui_launcher_pid,
                    "shutdown":"completed",
                    "ownersReapedAt":SystemTime::now().duration_since(UNIX_EPOCH)?.as_secs()
                }));
                fs::write(
                    context.output.join("lifecycle.json"),
                    serde_json::to_vec_pretty(&lifecycles)?,
                )?;
                let frozen = read_context(&home, &history_owner_thread(&home)?)?;
                ensure!(
                    frozen.as_array().is_some_and(|rows| !rows.is_empty()),
                    "replay history is empty"
                );
                if phase == "recheck" {
                    ensure!(
                        Some(&frozen) == prior_context.as_ref(),
                        "recheck appended duplicate context"
                    );
                }
                fs::write(
                    output.join(format!("{phase}-context.json")),
                    serde_json::to_vec_pretty(&frozen)?,
                )?;
                prior_context = Some(frozen);
            }
        }
        Ok(())
    })();
    for (source, destination) in &logs {
        if source.is_file() {
            write_sanitized_log(source, destination)?;
        }
    }
    let fixture_exit = fixture.stop(context.requests_file);
    drop(fixture);
    write_fixture_log(context.fixture_log, &context.output.join("fixture.log"))?;
    let requests = if context.requests_file.is_file() {
        sanitize_requests(context.requests_file, &context.output.join("requests.json"))?;
        serde_json::from_slice::<Vec<serde_json::Value>>(&fs::read(context.requests_file)?)?
    } else {
        Vec::new()
    };
    // This scenario owns fresh homes, synthetic prompts and credential-free fixture bindings.
    // No request headers are captured. Preserve the wire bodies to audit complete/incremental prefixes.
    fs::write(
        context.output.join("replay-requests.json"),
        serde_json::to_vec_pretty(&requests)?,
    )?;
    let errors = logs
        .iter()
        .filter(|(source, _)| {
            source
                .file_name()
                .is_some_and(|name| name.to_string_lossy().ends_with("gui.log"))
        })
        .map(|(source, _)| {
            if source.is_file() {
                count_gui_errors(source)
            } else {
                Ok(0)
            }
        })
        .collect::<Result<Vec<_>>>()?
        .into_iter()
        .sum::<usize>();
    fs::write(
        context.output.join("collection.json"),
        serde_json::to_vec_pretty(&serde_json::json!({
            "scenario":"context-replay-recovery", "platform":std::env::consts::OS,
            "protocols":["responsesHttp","responsesWebSocket","chat"],
            "guiLifecycles":lifecycles.len(), "plannedGuiLifecycles":9,
            "status":if journey.is_ok() {"complete"} else {"failed"}, "error":journey.as_ref().err().map(ToString::to_string),
            "acceptedRequests":requests.iter().filter(|request| request["accepted"] == true).count(),
            "rejectedRequests":requests.iter().filter(|request| request["accepted"] == false).count(),
            "guiErrors":errors, "humanVerdict":"pending"
        }))?,
    )?;
    journey?;
    ensure!(
        fixture_exit.is_ok_and(|status| status.success())
            && errors == 0
            && requests.len() >= 18
            && requests.iter().all(|request| request["accepted"] == true),
        "replay fixture or GUI health incomplete"
    );
    println!(
        "Evidence: {} (human verdict pending)",
        context.output.display()
    );
    Ok(())
}

fn read_context(home: &Path, thread_id: &str) -> Result<serde_json::Value> {
    let path = history_lock_database(home)?;
    tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()?
        .block_on(async {
            let mut connection = SqliteConnection::connect_with(
                &SqliteConnectOptions::new().filename(&path).read_only(true),
            )
            .await?;
            let owner: String =
                sea_orm::sqlx::query("SELECT thread_id FROM history_meta WHERE id=1")
                    .fetch_one(&mut connection)
                    .await?
                    .try_get("thread_id")?;
            ensure!(
                owner == thread_id,
                "restored history belongs to another Thread"
            );
            let rows = sea_orm::sqlx::query("SELECT payload FROM current_context ORDER BY ordinal")
                .fetch_all(&mut connection)
                .await?;
            let context = rows
                .into_iter()
                .map(|row| {
                    let payload: String = row.try_get("payload")?;
                    Ok(serde_json::from_str::<serde_json::Value>(&payload)?)
                })
                .collect::<Result<Vec<_>>>()?;
            for record in &context {
                if record["source"]["kind"] != "assistant" {
                    continue;
                }
                let content = record["content"]
                    .as_array()
                    .context("assistant content missing")?;
                for part in content {
                    if part["payload"]["format"] == "pl.model.assistant" {
                        let frame: serde_json::Value = serde_json::from_str(
                            part["payload"]["content"]
                                .as_str()
                                .context("assistant frame missing")?,
                        )?;
                        ensure!(
                            !frame["receipt"]["response"]["replay"].is_null(),
                            "saved new response lost frozen replay"
                        );
                    }
                }
            }
            connection.close().await?;
            Ok(serde_json::json!(context))
        })
}
