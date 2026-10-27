//! Linux Git preparation and bounded evidence under the existing ManagedWorker lease.
use super::evidence::Evidence;
use anyhow::{Context, Result};
use std::path::{Path, PathBuf};

pub(super) async fn initialize_repository(
    evidence: &Evidence,
    workspace: &Path,
    scene: &super::Boundary,
) -> Result<()> {
    git_capture(
        evidence,
        workspace,
        "git/preparation/init",
        &["init"],
        scene,
    )
    .await?;
    scene.check()?;
    std::fs::write(
        workspace.join("README.md"),
        "Isolated live collaboration workspace.\n",
    )?;
    git_capture(
        evidence,
        workspace,
        "git/preparation/add",
        &["add", "README.md"],
        scene,
    )
    .await?;
    git_capture(
        evidence,
        workspace,
        "git/preparation/commit",
        &[
            "-c",
            "user.name=anywork observation",
            "-c",
            "user.email=observation@anywork.invalid",
            "-c",
            "commit.gpgsign=false",
            "commit",
            "-m",
            "chore: initialize observation workspace",
        ],
        scene,
    )
    .await?;
    Ok(())
}

pub(super) async fn git_value(
    evidence: &Evidence,
    workspace: &Path,
    prefix: &str,
    args: &[&str],
    scene: &super::Boundary,
) -> Result<Vec<u8>> {
    use tokio::io::AsyncReadExt;
    git_capture(evidence, workspace, prefix, args, scene).await?;
    let mut file = scene
        .read(async {
            Ok(tokio::fs::File::open(evidence.root().join(format!("{prefix}.stdout"))).await?)
        })
        .await?
        .take(64 * 1024 + 1);
    let mut bytes = Vec::new();
    scene
        .read(async {
            file.read_to_end(&mut bytes).await?;
            Ok(())
        })
        .await?;
    anyhow::ensure!(
        bytes.len() <= 64 * 1024,
        "Git metadata exceeds 64 KiB; complete output remains in evidence"
    );
    Ok(bytes)
}

pub async fn capture_git(
    evidence: &Evidence,
    workspace: &Path,
    stage: &str,
    budget: &super::Boundary,
) -> Result<()> {
    for (name, args) in [
        ("head", vec!["rev-parse", "--verify", "HEAD"]),
        (
            "status",
            vec!["status", "--porcelain=v1", "-z", "--untracked-files=all"],
        ),
        (
            "unstaged",
            vec!["diff", "--no-ext-diff", "--no-textconv", "--binary"],
        ),
        (
            "staged",
            vec![
                "diff",
                "--cached",
                "--no-ext-diff",
                "--no-textconv",
                "--binary",
            ],
        ),
        (
            "untracked",
            vec!["ls-files", "--others", "--exclude-standard", "-z"],
        ),
    ] {
        git_capture(
            evidence,
            workspace,
            &format!("git/{stage}/{name}"),
            &args,
            budget,
        )
        .await?;
    }
    capture_untracked(evidence, workspace, stage, budget).await
}

#[derive(Debug, Default, serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct GitReceipt<'a> {
    args: &'a [&'a str],
    status: String,
    exit_code: Option<i32>,
    signal: Option<i32>,
    success: bool,
    cancel_requested: bool,
    supervisor_pid: Option<u32>,
    pipes_present: bool,
    worker_wait_returned: bool,
    streams_settled: bool,
    streams_finished_before_worker_wait: bool,
    elapsed_millis: u128,
    worker_error: Option<String>,
    errors: Vec<String>,
}

#[cfg(not(target_os = "linux"))]
async fn git_capture(
    _: &Evidence,
    _: &Path,
    _: &str,
    _: &[&str],
    _: &super::Boundary,
) -> Result<()> {
    super::inputs::require_linux()
}

#[cfg(target_os = "linux")]
async fn git_capture(
    evidence: &Evidence,
    workspace: &Path,
    prefix: &str,
    args: &[&str],
    budget: &super::Boundary,
) -> Result<()> {
    use pl_remote_helper::client::{ManagedWorker, ProcessCommand, ProcessTermination};
    budget.check()?;
    let stdout = evidence.create(&format!("{prefix}.stdout"), "Git stdout")?;
    let stderr = evidence.create(&format!("{prefix}.stderr"), "Git stderr")?;
    let command = ProcessCommand::new("git")
        .args([
            "--no-pager",
            "--no-optional-locks",
            "-c",
            "core.hooksPath=",
            "-c",
            "core.fsmonitor=false",
            "-c",
            "commit.gpgsign=false",
            "-c",
            "diff.submodule=short",
        ])
        .args(args.iter().copied())
        .current_dir(workspace);
    let started = std::time::Instant::now();
    let mut receipt = GitReceipt {
        args,
        ..GitReceipt::default()
    };
    // Spawn may have sent Start. Never put it inside a deadline that could abandon the lease.
    let mut worker = match ManagedWorker::spawn(Path::new("pl-remote-helper"), command).await {
        Ok(worker) => worker,
        Err(error) => {
            receipt.status = "workerBootstrapFailed".into();
            receipt.worker_error = Some(error.to_string());
            receipt.elapsed_millis = started.elapsed().as_millis();
            if let Err(error) = stdout.finish(false) {
                receipt.errors.push(format!("stdout finish: {error:#}"));
            }
            if let Err(error) = stderr.finish(false) {
                receipt.errors.push(format!("stderr finish: {error:#}"));
            }
            let mut error = anyhow::Error::new(error);
            if let Err(save) = save_git_receipt(evidence, prefix, &receipt) {
                error = error.context(format!("receipt also failed: {save:#}"));
            }
            return Err(with_git_stop(error, budget));
        }
    };
    receipt.supervisor_pid = worker.supervisor_pid();
    let control = worker.control();
    drop(worker.take_stdin());
    let out = worker.take_stdout();
    let err = worker.take_stderr();
    let pipes_present = out.is_some() && err.is_some();
    let cancel = tokio_util::sync::CancellationToken::new();
    if !pipes_present {
        cancel.cancel();
    }
    let output = async {
        tokio::join!(
            drain_git(out, stdout, &cancel),
            drain_git(err, stderr, &cancel)
        )
    };
    tokio::pin!(output);
    // This one borrowed wait future survives every output/cancellation branch. The worker also
    // retains partial control frames and supervisor exit state itself; no wrapper wait is rebuilt.
    let waited = worker.wait();
    tokio::pin!(waited);
    let mut status = None;
    let mut streams = None;
    let mut cancel_requested = false;
    let mut errors = Vec::new();
    // Control acceptance and pipe EOF are not physical closure: keep the unique worker owner
    // through its terminal control event AND supervisor exit, while both streams drain.
    while status.is_none() || streams.is_none() {
        tokio::select! {
            biased;
            _ = async { tokio::select! { _ = budget.stopped() => (), _ = cancel.cancelled() => () } }, if !cancel_requested => {
                cancel_requested = true;
                if let Err(error) = control.cancel().await { errors.push(format!("worker cancel: {error}")); control.close(); }
            }
            result = &mut waited, if status.is_none() => status = Some(result),
            result = &mut output, if streams.is_none() => {
                receipt.streams_finished_before_worker_wait = status.is_none();
                streams = Some(result);
        }
        }
    }
    let status = status.context("Git owner wait result missing after settlement")?;
    let ((stdout, out_errors), (stderr, err_errors)) =
        streams.context("Git pipe results missing after settlement")?;
    errors.extend(out_errors);
    errors.extend(err_errors);
    let complete = matches!(status, Ok(ProcessTermination::ExitCode(0)))
        && !cancel_requested
        && errors.is_empty();
    // Finish stream evidence only after the process-tree outcome is known. EOF after a forced
    // termination is a drained partial stream, not a complete Git diff.
    if let Err(error) = stdout.finish(complete) {
        errors.push(format!("stdout finish: {error:#}"));
    }
    if let Err(error) = stderr.finish(complete) {
        errors.push(format!("stderr finish: {error:#}"));
    }
    receipt.success = complete && errors.is_empty();
    receipt.status = format!("{status:?}");
    match &status {
        Ok(ProcessTermination::ExitCode(code)) => receipt.exit_code = Some(*code),
        Ok(ProcessTermination::Signal(signal)) => receipt.signal = Some(*signal),
        Err(error) => receipt.worker_error = Some(error.to_string()),
    }
    receipt.cancel_requested = cancel_requested;
    receipt.pipes_present = pipes_present;
    receipt.worker_wait_returned = true;
    receipt.streams_settled = true;
    receipt.elapsed_millis = started.elapsed().as_millis();
    receipt.errors = errors;
    save_git_receipt(evidence, prefix, &receipt)?;
    if let Err(error) = status {
        return Err(with_git_stop(anyhow::Error::new(error), budget));
    }
    budget.check()?;
    anyhow::ensure!(receipt.success, "Git evidence incomplete: {receipt:?}");
    Ok(())
}

#[cfg(target_os = "linux")]
fn with_git_stop(error: anyhow::Error, budget: &super::Boundary) -> anyhow::Error {
    match budget
        .check()
        .err()
        .and_then(|stopped| stopped.downcast::<super::Stopped>().ok())
    {
        Some(stopped) => error.context(stopped),
        None => error,
    }
}

#[cfg(target_os = "linux")]
fn save_git_receipt(evidence: &Evidence, prefix: &str, receipt: &GitReceipt<'_>) -> Result<()> {
    evidence
        .json(
            &format!("{prefix}.receipt.json"),
            "actual Git exit and pipe drain",
            &receipt,
        )
        .with_context(|| format!("unable to save Git receipt: {receipt:?}"))
}

async fn drain_git(
    input: Option<impl tokio::io::AsyncRead + Unpin>,
    mut output: super::evidence::EvidenceFile,
    cancel: &tokio_util::sync::CancellationToken,
) -> (super::evidence::EvidenceFile, Vec<String>) {
    use std::io::Write;
    use tokio::io::AsyncReadExt;
    let mut buffer = [0u8; 64 * 1024];
    let mut errors = Vec::new();
    let Some(mut input) = input else {
        cancel.cancel();
        return (output, vec!["Git pipe initialization missing".into()]);
    };
    loop {
        match input.read(&mut buffer).await {
            Ok(0) => break,
            Ok(count) if errors.is_empty() => {
                if let Err(error) = output.write_all(&buffer[..count]) {
                    errors.push(format!("write: {error}"));
                    cancel.cancel();
                }
            }
            Ok(_) => (), // After a write/budget error, kill is signalled and the pipe is still drained.
            Err(error) => {
                errors.push(format!("read: {error}"));
                cancel.cancel();
                break;
            }
        }
    }
    (output, errors)
}

async fn capture_untracked(
    evidence: &Evidence,
    workspace: &Path,
    stage: &str,
    budget: &super::Boundary,
) -> Result<()> {
    use std::io::Write;
    use tokio::io::AsyncReadExt;
    let mut list = budget
        .read(async {
            Ok(tokio::fs::File::open(
                evidence
                    .root()
                    .join(format!("git/{stage}/untracked.stdout")),
            )
            .await?)
        })
        .await?;
    let mut mapping = evidence.create(
        &format!("git/{stage}/untracked.jsonl"),
        "NUL path bytes to captured content",
    )?;
    let mut pending = Vec::new();
    let mut buffer = [0u8; 8192];
    let mut index = 0usize;
    let mut unsupported = 0usize;
    let result: Result<()> = async {
        loop {
            let count = budget
                .read(async { Ok(list.read(&mut buffer).await?) })
                .await?;
            if count == 0 {
                anyhow::ensure!(pending.is_empty(), "unterminated NUL Git path");
                break;
            }
            for byte in &buffer[..count] {
                if *byte != 0 {
                    anyhow::ensure!(pending.len() < 64 * 1024, "untracked path exceeds 64 KiB");
                    pending.push(*byte);
                    continue;
                }
                budget.check()?;
                evidence.check_limit(
                    index < 10_000,
                    "untracked file count budget exceeded (10000)",
                )?;
                let relative = format!("git/{stage}/untracked/{index:05}.bin");
                let copied = copy_untracked(evidence, workspace, &pending, &relative, budget).await;
                #[derive(serde::Serialize)]
                #[serde(rename_all = "camelCase")]
                struct PathMapping<'a> {
                    path_hex: String,
                    display: String,
                    content_file: &'a str,
                    error: Option<String>,
                }
                let record = PathMapping {
                    path_hex: hex::encode(&pending),
                    display: String::from_utf8_lossy(&pending).into_owned(),
                    content_file: &relative,
                    error: copied.as_ref().err().map(|error| format!("{error:#}")),
                };
                serde_json::to_writer(&mut mapping, &record)?;
                mapping.write_all(b"\n")?;
                if copied.is_err() {
                    unsupported += 1;
                }
                pending.clear();
                index += 1;
                budget.check()?;
            }
        }
        anyhow::ensure!(
            unsupported == 0,
            "{unsupported} untracked contents missing/unsupported; see git/{stage}/untracked.jsonl"
        );
        Ok(())
    }
    .await;
    let finish = mapping.finish(result.is_ok());
    match (result, finish) {
        (Err(error), Err(finish)) => {
            Err(error.context(format!("path mapping finish also failed: {finish:#}")))
        }
        (Err(error), _) | (_, Err(error)) => Err(error),
        _ => Ok(()),
    }
}

async fn copy_untracked(
    evidence: &Evidence,
    workspace: &Path,
    bytes: &[u8],
    relative: &str,
    budget: &super::Boundary,
) -> Result<()> {
    use std::io::Write;
    use tokio::io::AsyncReadExt;
    #[cfg(unix)]
    let path = {
        use std::os::unix::ffi::OsStringExt;
        PathBuf::from(std::ffi::OsString::from_vec(bytes.to_vec()))
    };
    #[cfg(not(unix))]
    let path = PathBuf::from(
        String::from_utf8(bytes.to_vec())
            .context("non-UTF8 Git path unsupported on this platform")?,
    );
    let mut source = workspace.to_path_buf();
    anyhow::ensure!(!path.as_os_str().is_empty(), "empty Git path");
    for component in path.components() {
        let std::path::Component::Normal(name) = component else {
            anyhow::bail!("Git path must be workspace-relative ordinary components");
        };
        anyhow::ensure!(
            name != ".git" && name != ".anywork" && name != "studio-home",
            "runtime/Git directory is outside untracked capture scope"
        );
        source.push(name);
        anyhow::ensure!(
            !std::fs::symlink_metadata(&source)?.file_type().is_symlink(),
            "untracked symlink is unsupported"
        );
    }
    let before = std::fs::symlink_metadata(&source)?;
    anyhow::ensure!(
        before.is_file() && std::fs::canonicalize(&source)?.starts_with(workspace),
        "untracked entry is not a regular in-workspace file"
    );
    let opened = std::fs::File::open(&source)?;
    let opened_metadata = opened.metadata()?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::MetadataExt;
        anyhow::ensure!(
            before.dev() == opened_metadata.dev() && before.ino() == opened_metadata.ino(),
            "untracked file changed while opening"
        );
    }
    anyhow::ensure!(
        !std::fs::symlink_metadata(&source)?.file_type().is_symlink()
            && std::fs::canonicalize(&source)?.starts_with(workspace),
        "untracked path changed or escaped while opening"
    );
    let mut input = tokio::fs::File::from_std(opened);
    let mut output = evidence.create(relative, &hex::encode(bytes))?;
    let result: Result<()> = async {
        let mut buffer = [0u8; 64 * 1024];
        let mut count = 0u64;
        loop {
            let read = budget
                .read(async { Ok(input.read(&mut buffer).await?) })
                .await?;
            if read == 0 {
                break;
            }
            output.write_all(&buffer[..read])?;
            count += read as u64;
            budget.check()?;
        }
        let after = budget.read(async { Ok(input.metadata().await?) }).await?;
        anyhow::ensure!(
            count == opened_metadata.len()
                && count == after.len()
                && opened_metadata.modified()? == after.modified()?,
            "untracked file changed while streaming"
        );
        Ok(())
    }
    .await;
    let finish = output.finish(result.is_ok());
    match (result, finish) {
        (Err(error), Err(finish)) => {
            Err(error.context(format!("content finish also failed: {finish:#}")))
        }
        (Err(error), _) | (_, Err(error)) => Err(error),
        _ => Ok(()),
    }
}
