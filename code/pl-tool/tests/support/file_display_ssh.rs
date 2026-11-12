//! Focused opt-in SSH acceptance. All business I/O uses the production helper backend.
use super::{Media, host};
use anyhow::{Context, Result, ensure};
use pl_agent_tool::ToolHandle;
use pl_core::{
    context::{ContextContent, ContextSource, ResourceReference},
    model::{DynModelSession, ToolPresentationContract},
    thread::ThreadHandle,
};
use pl_tool::workspace_file::ExecutorWorkspaceFileBackend;
use pl_tool::{
    binding::{ToolCallPolicy, prepare_native_tool, prepare_registration},
    file_display::{
        FileDisplayOrigin, FileDisplayResult, ThreadShowFilesTool, saved_file_display_receipt,
    },
    remote::{SshConfigFile, SshConnectionState, SshManager, SshServerProfile},
    workspace_file::{WorkspaceFileBackend, WorkspaceFileReadRequest, WorkspaceFileWriteRequest},
};
use std::{
    collections::BTreeSet,
    path::{Path, PathBuf},
    sync::{Arc, Mutex},
};

fn required(name: &str) -> Result<String> {
    std::env::var(name).with_context(|| format!("{name} must be set for external SSH acceptance"))
}

/// Counts only this test process's SSH children, never another user's sessions.
fn ssh_children() -> Result<BTreeSet<String>> {
    #[cfg(target_os = "linux")]
    let mut children = BTreeSet::new();
    #[cfg(not(target_os = "linux"))]
    let children = BTreeSet::new();
    #[cfg(target_os = "linux")]
    for task in std::fs::read_dir("/proc/self/task")? {
        let path = task?.path().join("children");
        let Ok(pids) = std::fs::read_to_string(path) else {
            continue;
        };
        for pid in pids.split_whitespace() {
            if std::fs::read_link(format!("/proc/{pid}/exe"))
                .ok()
                .and_then(|path| path.file_name().map(|name| name == "ssh"))
                .unwrap_or(false)
            {
                children.insert(pid.into());
            }
        }
    }
    Ok(children)
}

fn retained_bytes(media: &Media, reference: &ResourceReference) -> Result<Vec<u8>> {
    media
        .0
        .lock()
        .unwrap()
        .iter()
        .find(|bytes| reference.verify(bytes).is_ok())
        .cloned()
        .context("resource is absent from the tool's retained originals")
}

#[tokio::test]
#[ignore = "external SSH; requires explicit server/username/workspace, helper artifacts, scratch and artifacts"]
async fn show_files_archives_real_ssh_originals_and_releases_connection() -> Result<()> {
    let server = required("PURE_SSH_TEST_SERVER")?;
    // Deliberately no root/default user: the external target must be explicit.
    let username = required("PURE_SSH_TEST_USERNAME")?;
    let parent_path = required("PURE_SSH_TEST_WORKSPACE")?;
    ensure!(
        parent_path.starts_with('/'),
        "fixture parent must be an explicitly approved absolute path"
    );
    let scratch = PathBuf::from(required("PURE_SSH_TEST_SCRATCH")?);
    let artifacts = PathBuf::from(required("PURE_SSH_TEST_ARTIFACTS")?);
    ensure!(
        scratch.is_absolute() && artifacts.is_absolute(),
        "session scratch/artifacts must be absolute (Cargo runs tests from the package directory)"
    );
    std::fs::create_dir_all(&scratch)?;
    std::fs::create_dir_all(&artifacts)?;
    let local = tempfile::Builder::new()
        .prefix("ssh-show-files-")
        .tempdir_in(&scratch)?;
    let mut nonce = [0u8; 16];
    getrandom::fill(&mut nonce).map_err(|error| anyhow::anyhow!("{error}"))?;
    let nonce = hex::encode(nonce);
    let fixture = format!(".anywork-show-files-{nonce}");
    let remote_path = format!("{}/{fixture}", parent_path.trim_end_matches('/'));
    let artifacts = artifacts.join(&fixture);
    std::fs::create_dir(&artifacts)?;
    let known_hosts = std::env::var("PURE_SSH_TEST_KNOWN_HOSTS").unwrap_or_else(|_| {
        format!(
            "{}/.ssh/known_hosts",
            std::env::var("HOME").unwrap_or_default()
        )
    });
    let config = local.path().join("ssh_config");
    std::fs::write(
        &config,
        format!(
            "UserKnownHostsFile {known_hosts}\nBatchMode yes\nStrictHostKeyChecking yes\nIdentitiesOnly yes\n"
        ),
    )?;
    let aarch64 = std::env::var_os("PURE_REMOTE_HELPER_AARCH64").map(PathBuf::from);
    let x86_64 = std::env::var_os("PURE_REMOTE_HELPER_X86_64").map(PathBuf::from);
    ensure!(
        aarch64.is_some() || x86_64.is_some(),
        "provide a same-source production helper artifact"
    );
    ensure!(
        aarch64
            .iter()
            .chain(x86_64.iter())
            .all(|path| path.is_absolute()),
        "helper artifact paths must be absolute"
    );
    let manager = SshManager::new(aarch64, x86_64).with_ssh_config(SshConfigFile::at(config));
    let baseline = ssh_children()?;
    manager
        .save_server(SshServerProfile {
            alias: "show-files-external".into(),
            host_name: server.clone(),
            port: std::env::var("PURE_SSH_TEST_PORT")
                .ok()
                .map(|port| port.parse())
                .transpose()?
                .unwrap_or(22),
            username: username.clone(),
            identity_file: std::env::var("PURE_SSH_TEST_IDENTITY").ok(),
        })
        .await?;
    let mut created = false;
    let mut active_children = BTreeSet::new();
    let result = async {
        let connection = manager.test_connection("show-files-external").await?;
        ensure!(matches!(connection.state, SshConnectionState::Ready { .. }));
        println!("{}", serde_json::json!({
            "scenario":"show-files-ssh", "target":server, "user":username,
            "remoteFixture":remote_path, "connection":connection, "artifacts":artifacts,
        }));
        active_children = ssh_children()?.difference(&baseline).cloned().collect();
        #[cfg(target_os = "linux")]
        ensure!(active_children.len() == 1, "expected one production SSH business connection: {active_children:?}");
        let parent = manager.open_workspace_host("show-files-external", parent_path.clone()).await?;
        ensure!(parent.files.inspect_path(fixture.clone(), None).await?.is_none(),
            "generated fixture path already exists; refusing to reuse it");
        parent.files.create_directory(fixture.clone(), None).await?;
        created = true;
        let marker = format!("{fixture}/.show-files-owner");
        parent.files.write_bytes_atomic(marker.clone(), None, nonce.as_bytes()).await?;
        let exercised = exercise(&manager, &remote_path, &artifacts).await;
        // This scope owns the only generated directory. A conflicting/missing marker is
        // preserved for diagnosis, never recursively removed on assumptions.
        let cleaned = async {
            let owner = parent.files.read_text(WorkspaceFileReadRequest {
                path:marker, cwd:None,
            }).await?;
            ensure!(owner == nonce, "fixture ownership marker differs; cleanup refused");
            parent.files.remove_path(fixture.clone(), None, true).await?;
            ensure!(parent.files.inspect_path(fixture.clone(), None).await?.is_none(),
                "remote fixture still exists after acknowledged removal");
            println!("{}", serde_json::json!({"remoteFixture":remote_path, "markerVerified":true, "removed":true}));
            Ok::<_, anyhow::Error>(())
        }.await;
        drop(parent);
        exercised.with_context(|| format!("remote cleanup result: {cleaned:?}"))?;
        cleaned?;
        Ok::<_, anyhow::Error>(())
    }.await;
    // Always drain production transport and helper ownership, including failed assertions.
    let disconnected = manager.disconnect_server("show-files-external").await;
    let state = manager.connection_snapshot("show-files-external").await;
    let shutdown = manager.shutdown().await;
    let remaining = ssh_children()?;
    let reaped = active_children
        .iter()
        .all(|pid| !Path::new(&format!("/proc/{pid}")).exists());
    println!(
        "{}",
        serde_json::json!({
            "scenario":"show-files-ssh-cleanup", "target":server, "user":username,
            "remoteFixture":remote_path, "created":created,
            "disconnect":format!("{disconnected:?}"), "state":format!("{state:?}"),
            "shutdown":format!("{shutdown:?}"), "ownedSshPids":active_children,
            "ownedSshChildrenReaped":reaped, "additionalSshChildren":remaining.difference(&baseline).collect::<Vec<_>>(),
        })
    );
    result?;
    disconnected?;
    ensure!(matches!(state?.state, SshConnectionState::Disconnected));
    shutdown?;
    ensure!(
        remaining.is_subset(&baseline) && reaped,
        "owned SSH process was not reaped"
    );
    Ok(())
}

async fn exercise(manager: &SshManager, remote_path: &str, artifacts: &Path) -> Result<()> {
    let workspace = manager
        .open_workspace_host("show-files-external", remote_path.into())
        .await?;
    let files = Arc::new(workspace.files.clone());
    let md = b"# remote original\n\nChinese: \xe4\xb8\xad\xe6\x96\x87\n".to_vec();
    let mut png = std::io::Cursor::new(Vec::new());
    image::DynamicImage::new_rgba8(3, 2).write_to(&mut png, image::ImageFormat::Png)?;
    let png = png.into_inner();
    let binary = vec![0, 255, 17, 128, 3, 0, 222, 173, 190, 239];
    for (name, bytes) in [
        ("report.md", &md),
        ("valid.png", &png),
        ("opaque.bin", &binary),
    ] {
        files.write_bytes_atomic(name.into(), None, bytes).await?;
    }
    let media = Arc::new(Media::default());
    let prepared =
        prepare_native_tool::<ThreadShowFilesTool<ExecutorWorkspaceFileBackend, Media>>()?;
    let registration = prepare_registration(
        "show_files",
        prepared.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    let requests = Arc::new(Mutex::new(Vec::new()));
    let thread = ThreadHandle::start(
        "ssh-file-display".into(),
        DynModelSession::new(host::Calls {
            calls: [(
                "show_files".into(),
                serde_json::json!({
                    "caption":" remote originals ", "files":[
                        {"kind":"workspace","path":"report.md"},
                        {"kind":"workspace","path":"valid.png"},
                        {"kind":"workspace","path":"missing.txt"},
                        {"kind":"workspace","path":"opaque.bin"},
                        {"kind":"workspace","path":"report.md"}
                    ]
                })
                .to_string(),
            )]
            .into(),
            requests: requests.clone(),
        }),
    )?;
    let tested = async {
        thread.register_tools(vec![registration
            .attach(ToolHandle::new(prepared.attach(ThreadShowFilesTool::new(files.clone(), media.clone()))))
            .with_presentation_contract(ToolPresentationContract::new("builtin.show_files@1"))
            .foreground_coexisting()]).await?;
        thread.run_turn(host::turn("ssh-display")).await?;
        let effects = thread.effects().await?;
        let deliveries = effects.iter().flat_map(|effect| effect.deliveries.iter()).collect::<Vec<_>>();
        ensure!(deliveries.len() == 1, "expected exactly one actual Thread tool delivery");
        let delivery = deliveries[0];
        let receipt = saved_file_display_receipt(delivery.output.payload())?.context("show_files receipt")?;
        ensure!(receipt.caption.as_deref() == Some("remote originals") && receipt.files.len() == 5);
        ensure!(matches!(&receipt.files[2], FileDisplayResult::Failed { filename, .. } if filename == "missing.txt"));
        ensure!(delivery.delivered_context.iter().all(|content| !matches!(content, ContextContent::Opaque { .. })),
            "display injected model media despite a model without image input");
        ensure!(requests.lock().unwrap().iter().flat_map(|request| request.context.records.iter())
            .filter(|record| matches!(record.source, ContextSource::ToolResult { .. }))
            .flat_map(|record| &record.content)
            .all(|content| !matches!(content, ContextContent::Opaque { .. })));
        ensure!(media.0.lock().unwrap().len() == 4, "missing source retained bytes or duplicates were dropped");
        std::fs::write(artifacts.join("receipt.json"), serde_json::to_vec_pretty(delivery.output.payload())?)?;
        // Remove/change actual remote sources before downloading through retained resource identities.
        files.write_text(WorkspaceFileWriteRequest {
            mode:pl_tool::workspace::WriteMode::Overwrite, path:"report.md".into(), cwd:None,
            content:"changed remote source, not the archived bytes".into(),
        }).await?;
        files.remove_path("valid.png".into(), None, false).await?;
        files.remove_path("opaque.bin".into(), None, false).await?;
        let shadow = artifacts.join("local-shadow");
        std::fs::create_dir(&shadow)?;
        std::fs::write(shadow.join("report.md"), b"unrelated local namesake")?;
        let mut evidence = Vec::new();
        for (index, name, expected, modality) in [
            (0, "report.md", &md, pl_protocol::AttachmentModality::File),
            (1, "valid.png", &png, pl_protocol::AttachmentModality::Image),
            (3, "opaque.bin", &binary, pl_protocol::AttachmentModality::File),
            (4, "report.md", &md, pl_protocol::AttachmentModality::File),
        ] {
            let FileDisplayResult::Ready { resource, filename, modality:actual, origin } = &receipt.files[index]
                else { anyhow::bail!("expected success at index {index}: {:?}", receipt.files[index]); };
            ensure!(filename == name && *actual == modality && matches!(origin, FileDisplayOrigin::Remote),
                "remote result lost order/name/modality or exposed a local path");
            ensure!(serde_json::to_value(origin)? == serde_json::json!({"kind":"remote"}));
            resource.verify(expected)?;
            let bytes = retained_bytes(&media, resource)?;
            ensure!(&bytes == expected, "download did not use the archived original");
            let download = artifacts.join(format!("{index}-{name}"));
            std::fs::write(&download, &bytes)?;
            resource.verify(&std::fs::read(&download)?)?;
            let item = serde_json::json!({"index":index,"filename":filename,"resource":resource,
                "download":download,"bytes":bytes.len(),"origin":origin,"originalHashVerified":true});
            println!("{item}");
            evidence.push(item);
        }
        std::fs::write(artifacts.join("resources.json"), serde_json::to_vec_pretty(&evidence)?)?;
        Ok::<_, anyhow::Error>(())
    }.await;
    let closed = thread.close().await;
    drop(thread);
    drop(files);
    drop(workspace);
    tested.with_context(|| format!("Thread close result: {closed:?}"))?;
    closed?;
    Ok(())
}
