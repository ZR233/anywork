//! Observes execution-side session directories, pool ignore, and host transfer scratch.
//!
//! Uses public `pl-tool` / `FileResourceStore` APIs. It does not read user provider
//! configuration or credentials. Optional SSH observation reuses the already-authorized
//! isolated helper environment.
use anyhow::{Context, Result, ensure};
use pl_studio_runtime::resource_store::FileResourceStore;
use pl_tool::workspace::{
    POOL_GITIGNORE, SessionFiles, WORKTREES_POOL, prepare_session_files, prepare_worktree_pool,
};
use pl_tool::workspace_file::LocalWorkspaceFileBackend;
use std::path::{Path, PathBuf};
use std::process::Command;

#[tokio::main]
async fn main() -> Result<()> {
    let artifacts = match std::env::args_os().nth(1) {
        Some(path) => PathBuf::from(path),
        None => tempfile::Builder::new()
            .prefix("anywork-session-layout-")
            .tempdir()?
            .keep(),
    };
    std::fs::create_dir_all(&artifacts)?;
    let workspace = artifacts.join("workspace");
    std::fs::create_dir_all(&workspace)?;
    initialize_repository(&workspace)?;

    let thread_id = "observe-thread";
    let files = SessionFiles::new(thread_id);
    let backend = LocalWorkspaceFileBackend::new(workspace.clone(), false).await?;
    prepare_worktree_pool(&backend).await?;
    prepare_session_files(&backend, &files).await?;

    let scratch = workspace.join(files.scratch());
    let artifacts_dir = workspace.join(files.artifacts());
    let commands = workspace.join(files.commands());
    ensure!(scratch.is_dir(), "scratch was not created");
    ensure!(artifacts_dir.is_dir(), "artifacts was not created");
    ensure!(commands.is_dir(), "commands was not created");
    ensure!(
        files.thread_key().len() == 64,
        "SessionFiles must hash the original Thread id once"
    );

    ensure_pool_ignore(&workspace.join(".anywork/sessions/.gitignore"))?;
    ensure_pool_ignore(&workspace.join(WORKTREES_POOL).join(".gitignore"))?;
    std::fs::write(scratch.join("probe.txt"), b"scratch probe")?;
    let status = git_status(&workspace)?;
    ensure!(
        !status.contains(".anywork/sessions") && !status.contains(".anywork/worktrees"),
        "git status listed run-pool files:\n{status}"
    );

    let host_scratch = artifacts.join("host-scratch");
    std::fs::create_dir_all(&host_scratch)?;
    let resources = artifacts.join("thread-resources");
    let store = FileResourceStore::new(resources.clone());
    let named = host_scratch.join("named-capture.log");
    std::fs::write(&named, b"captured remote bytes\n")?;
    let retained = store.retain_command_capture(&named).await?;
    std::fs::remove_file(&named)?;
    ensure!(retained.byte_len() == 22, "retained capture length");
    ensure!(
        resources
            .read_dir()?
            .filter_map(Result::ok)
            .any(|entry| entry.path().is_file()),
        "content-addressed resource was not published"
    );

    if let Some(report) = observe_remote_if_configured(&files).await? {
        std::fs::write(artifacts.join("remote-report.txt"), report)?;
    }

    std::fs::write(
        artifacts.join("report.txt"),
        format!(
            "workspace={}\nthread_key={}\nscratch={}\nartifacts={}\ncommands={}\n",
            workspace.display(),
            files.thread_key(),
            files.scratch().display(),
            files.artifacts().display(),
            files.commands().display(),
        ),
    )?;
    println!("{}", artifacts.display());
    Ok(())
}

fn initialize_repository(path: &Path) -> Result<()> {
    run(path, ["git", "init", "-q"])?;
    run(
        path,
        ["git", "config", "user.email", "observe@example.test"],
    )?;
    run(
        path,
        ["git", "config", "user.name", "Session Layout Observe"],
    )?;
    std::fs::write(path.join("README.md"), b"session layout observe\n")?;
    run(path, ["git", "add", "README.md"])?;
    run(path, ["git", "commit", "-q", "-m", "init"])?;
    Ok(())
}

fn ensure_pool_ignore(path: &Path) -> Result<()> {
    let bytes = std::fs::read_to_string(path)
        .with_context(|| format!("read pool ignore {}", path.display()))?;
    ensure!(
        bytes == POOL_GITIGNORE,
        "unexpected pool ignore at {}",
        path.display()
    );
    Ok(())
}

fn git_status(path: &Path) -> Result<String> {
    let output = Command::new("git")
        .args(["status", "--porcelain=v1", "--untracked-files=all"])
        .current_dir(path)
        .output()?;
    ensure!(output.status.success(), "git status failed");
    Ok(String::from_utf8(output.stdout)?)
}

fn run(path: &Path, args: impl IntoIterator<Item = &'static str>) -> Result<()> {
    let args: Vec<_> = args.into_iter().collect();
    let status = Command::new(args[0])
        .args(&args[1..])
        .current_dir(path)
        .status()?;
    ensure!(status.success(), "command failed: {args:?}");
    Ok(())
}

async fn observe_remote_if_configured(files: &SessionFiles) -> Result<Option<String>> {
    let Ok(host_name) = std::env::var("PURE_SSH_TEST_SERVER") else {
        return Ok(None);
    };
    let workspace = std::env::var("PURE_SSH_TEST_WORKSPACE")?;
    let aarch64 = std::env::var_os("PURE_REMOTE_HELPER_AARCH64").map(PathBuf::from);
    let x86_64 = std::env::var_os("PURE_REMOTE_HELPER_X86_64").map(PathBuf::from);
    ensure!(
        aarch64.is_some() || x86_64.is_some(),
        "provide a remote helper artifact for optional SSH observation"
    );
    let isolated_config = tempfile::tempdir()?;
    let ssh_config_path = isolated_config.path().join("ssh_config");
    let known_hosts = std::env::var("PURE_SSH_TEST_KNOWN_HOSTS").unwrap_or_else(|_| {
        format!(
            "{}/.ssh/known_hosts",
            std::env::var("HOME").unwrap_or_default()
        )
    });
    std::fs::write(
        &ssh_config_path,
        format!("UserKnownHostsFile {known_hosts}\nIdentitiesOnly yes\n"),
    )?;
    let manager = pl_tool::remote::SshManager::new(aarch64, x86_64)
        .with_ssh_config(pl_tool::remote::SshConfigFile::at(ssh_config_path));
    let profile = pl_tool::remote::SshServerProfile {
        alias: "observe".to_string(),
        host_name,
        port: 22,
        username: std::env::var("PURE_SSH_TEST_USERNAME")
            .or_else(|_| std::env::var("USERNAME"))
            .unwrap_or_else(|_| "runner".to_string()),
        identity_file: std::env::var("PURE_SSH_TEST_IDENTITY")
            .or_else(|_| std::env::var("IDENTITY"))
            .ok(),
    };
    manager.save_server(profile).await?;
    let host = manager.open_workspace_host("observe", workspace).await?;
    prepare_worktree_pool(&host.files).await?;
    prepare_session_files(&host.files, files).await?;
    Ok(Some(format!(
        "remote session files prepared under {}\n",
        host.files.canonical_path()
    )))
}
