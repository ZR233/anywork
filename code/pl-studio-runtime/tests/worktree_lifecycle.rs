use anyhow::{Context, Result, ensure};
use pl_studio_runtime::agent::worktree::{
    LocalWorktreeBackend, WorktreeCleanupPolicy, WorktreeCreateSpec, WorktreeError,
    WorktreeManager, WorktreeOwnership,
};
use std::{path::Path, process::Command, sync::Arc};

fn git(path: &Path, args: &[&str]) -> Result<String> {
    let output = Command::new("git")
        .arg("-C")
        .arg(path)
        .args(args)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()?;
    ensure!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(String::from_utf8(output.stdout)?.trim().to_owned())
}

#[tokio::test]
async fn managed_worktrees_are_detached_and_keep_every_branch() -> Result<()> {
    let temp = tempfile::tempdir()?;
    let repo = temp.path().join("repo");
    std::fs::create_dir(&repo)?;
    git(&repo, &["init", "-b", "main"])?;
    let manager = WorktreeManager::new(repo.clone(), Arc::new(LocalWorktreeBackend::default()));
    assert!(
        matches!(
            manager.resolve_head(&repo).await,
            Err(WorktreeError::MissingHead)
        ),
        "an unborn repository requires an initial commit before worktree creation"
    );
    assert!(!repo.join(".anywork/worktrees").exists());
    assert!(
        matches!(
            manager.resolve_head(&temp.path().join("missing")).await,
            Err(WorktreeError::GitLaunchFailed { .. })
        ),
        "real execution failures must not be mislabeled as a missing initial commit"
    );
    git(&repo, &["config", "user.name", "Worktree Test"])?;
    git(&repo, &["config", "user.email", "worktree@example.invalid"])?;
    std::fs::write(repo.join("file.txt"), "initial\n")?;
    git(&repo, &["add", "."])?;
    git(&repo, &["commit", "-m", "initial"])?;
    let base = git(&repo, &["rev-parse", "HEAD"])?;
    std::fs::write(
        repo.join("file.txt"),
        "project HEAD moved after admission\n",
    )?;
    git(
        &repo,
        &["commit", "-am", "advance project after fixed base"],
    )?;
    assert_ne!(git(&repo, &["rev-parse", "HEAD"])?, base);
    for ownership in [
        WorktreeOwnership::Session {
            thread_id: "root".into(),
        },
        WorktreeOwnership::Child {
            child_id: "child".into(),
        },
    ] {
        let relative_creation = matches!(&ownership, WorktreeOwnership::Child { .. });
        git(
            &repo,
            &[
                "config",
                "worktree.useRelativePaths",
                if relative_creation { "true" } else { "false" },
            ],
        )?;
        let handle = manager
            .create(WorktreeCreateSpec {
                repo_root: repo.clone(),
                root_thread_id: "root".into(),
                ownership,
                base_commit: base.clone(),
            })
            .await?;
        manager.verify(&handle).await.context(
            "new worktree links must retain identity with absolute or configured relative paths",
        )?;
        git(
            &repo,
            &[
                "worktree",
                "repair",
                "--relative-paths",
                handle.path.to_str().context("UTF-8 path")?,
            ],
        )?;
        manager.verify(&handle).await.context(
            "Git repair to relative links must not change the managed checkout identity",
        )?;
        let created = manager.preview(&handle).await?;
        assert_eq!(
            created.head, base,
            "creation must consume the caller's fixed commit, not the current Project HEAD"
        );
        assert_eq!(
            created.branch, None,
            "new managed checkout must be detached"
        );
        git(&handle.path, &["switch", "-c", "business"])?;
        std::fs::write(handle.path.join("file.txt"), "advanced\n")?;
        git(&handle.path, &["commit", "-am", "advance"])?;
        let advanced = manager.preview(&handle).await?;
        assert_ne!(advanced.head, base);
        assert_eq!(advanced.branch.as_deref(), Some("business"));
        git(&handle.path, &["branch", "-m", "renamed"])?;
        git(&handle.path, &["switch", "--detach"])?;
        git(&repo, &["branch", "-D", "renamed"])?;
        git(&repo, &["branch", "pure-agent-legacy"])?;
        let branches = git(
            &repo,
            &["for-each-ref", "refs/heads", "--format=%(refname)"],
        )?;
        manager
            .cleanup(&handle, WorktreeCleanupPolicy::Discard)
            .await?;
        assert!(!handle.path.exists());
        assert!(
            !git(&repo, &["worktree", "list", "--porcelain"])?
                .contains(handle.path.to_str().context("UTF-8 path")?)
        );
        assert_eq!(
            git(
                &repo,
                &["for-each-ref", "refs/heads", "--format=%(refname)"]
            )?,
            branches
        );
        git(&repo, &["branch", "-D", "pure-agent-legacy"])?;
    }
    Ok(())
}

struct Repository {
    _temp: tempfile::TempDir,
    path: std::path::PathBuf,
    manager: WorktreeManager,
    base: String,
}

impl Repository {
    fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("repo");
        std::fs::create_dir(&path)?;
        git(&path, &["init", "-b", "main"])?;
        git(&path, &["config", "user.name", "Worktree Test"])?;
        git(&path, &["config", "user.email", "worktree@example.invalid"])?;
        std::fs::write(path.join("file.txt"), "initial\n")?;
        std::fs::write(path.join(".gitignore"), "ignored.txt\n.anywork/\n")?;
        git(&path, &["add", "."])?;
        git(&path, &["commit", "-m", "initial"])?;
        let base = git(&path, &["rev-parse", "HEAD"])?;
        let manager = WorktreeManager::new(path.clone(), Arc::new(LocalWorktreeBackend::default()));
        Ok(Self {
            _temp: temp,
            path,
            manager,
            base,
        })
    }

    async fn create(
        &self,
        child: &str,
    ) -> Result<pl_studio_runtime::agent::worktree::WorktreeHandle> {
        Ok(self
            .manager
            .create(WorktreeCreateSpec {
                repo_root: self.path.clone(),
                root_thread_id: "root".into(),
                ownership: WorktreeOwnership::Child {
                    child_id: child.into(),
                },
                base_commit: self.base.clone(),
            })
            .await?)
    }
}

#[tokio::test]
async fn cleanup_preserves_dirty_content_and_git_locks_until_explicit_discard() -> Result<()> {
    let repo = Repository::new()?;
    let handle = repo.create("dirty").await?;
    std::fs::write(handle.path.join("file.txt"), "dirty\n")?;
    std::fs::write(handle.path.join("untracked.txt"), "untracked\n")?;
    std::fs::write(handle.path.join("ignored.txt"), "ignored\n")?;
    let status = repo.manager.preview(&handle).await?;
    assert_eq!(
        status.changed_files.len(),
        2,
        "spawn-relevant changes include tracked and untracked content"
    );
    assert_eq!(
        status.ignored_files.len(),
        1,
        "ignored content remains visible independently"
    );
    assert!(
        repo.manager
            .cleanup(&handle, WorktreeCleanupPolicy::Safe)
            .await
            .is_err()
    );
    for file in ["file.txt", "untracked.txt", "ignored.txt"] {
        assert!(handle.path.join(file).exists());
    }
    git(&handle.path, &["restore", "--", "file.txt"])?;
    std::fs::remove_file(handle.path.join("untracked.txt"))?;
    let ignored_only = repo.manager.preview(&handle).await?;
    assert!(ignored_only.changed_files.is_empty());
    assert_eq!(ignored_only.ignored_files.len(), 1);
    assert!(
        repo.manager
            .cleanup(&handle, WorktreeCleanupPolicy::Safe)
            .await
            .is_err(),
        "Recovery Safe protects ignored content even with no ordinary changes"
    );
    git(
        &repo.path,
        &["worktree", "lock", handle.path.to_str().context("path")?],
    )?;
    assert!(matches!(
        repo.manager
            .cleanup(&handle, WorktreeCleanupPolicy::Discard)
            .await,
        Err(WorktreeError::GitExited { .. })
    ));
    assert!(
        handle.path.join("ignored.txt").exists(),
        "never bypass a Git lock with recursive deletion"
    );
    git(
        &repo.path,
        &["worktree", "unlock", handle.path.to_str().context("path")?],
    )?;
    repo.manager
        .cleanup(&handle, WorktreeCleanupPolicy::Discard)
        .await?;
    repo.manager
        .cleanup(&handle, WorktreeCleanupPolicy::Discard)
        .await?;
    assert!(!handle.path.exists());
    assert_eq!(
        git(&repo.path, &["branch", "--format=%(refname:short)"])?,
        "main"
    );
    Ok(())
}

#[tokio::test]
async fn missing_and_foreign_sites_keep_distinct_identity_and_retry_semantics() -> Result<()> {
    let repo = Repository::new()?;
    let first = repo.create("backlink-first").await?;
    let second = repo.create("backlink-second").await?;
    for relative_links in [false, true] {
        if relative_links {
            git(&repo.path, &["worktree", "repair", "--relative-paths"])?;
        }
        let first_gitfile = std::fs::read(first.path.join(".git"))?;
        std::fs::write(
            first.path.join(".git"),
            std::fs::read(second.path.join(".git"))?,
        )?;
        let redirected = repo.manager.verify(&first).await;
        std::fs::write(first.path.join(".git"), first_gitfile)?;
        assert!(
            matches!(redirected, Err(WorktreeError::IdentityMismatch(_))),
            "a same-repository sibling admin redirect must not pass identity: {redirected:?}"
        );
        repo.manager.verify(&first).await?;
        repo.manager.verify(&second).await?;
    }
    let handle = repo.create("missing").await?;
    assert!(
        repo.create("missing").await.is_err(),
        "Git adjudicates duplicate creation"
    );
    repo.manager.verify(&handle).await?;
    std::fs::remove_dir_all(&handle.path)?;
    assert!(matches!(
        repo.manager.verify(&handle).await,
        Err(WorktreeError::Missing)
    ));
    assert!(matches!(
        repo.manager
            .cleanup(&handle, WorktreeCleanupPolicy::Safe)
            .await,
        Err(WorktreeError::Missing)
    ));
    assert!(git(&repo.path, &["worktree", "list", "--porcelain"])?.contains("missing"));
    repo.manager
        .cleanup(&handle, WorktreeCleanupPolicy::Discard)
        .await?;
    assert!(!git(&repo.path, &["worktree", "list", "--porcelain"])?.contains("missing"));

    let foreign = repo.create("foreign").await?;
    std::fs::remove_dir_all(&foreign.path)?;
    std::fs::create_dir(&foreign.path)?;
    git(&foreign.path, &["init", "-b", "foreign-main"])?;
    std::fs::write(foreign.path.join("keep.txt"), "foreign\n")?;
    assert!(matches!(
        repo.manager.verify(&foreign).await,
        Err(WorktreeError::IdentityMismatch(_))
    ));
    assert!(
        repo.manager
            .cleanup(&foreign, WorktreeCleanupPolicy::Discard)
            .await
            .is_err()
    );
    assert_eq!(
        std::fs::read_to_string(foreign.path.join("keep.txt"))?,
        "foreign\n"
    );

    let unregistered = repo.create("unregistered").await?;
    git(
        &repo.path,
        &[
            "worktree",
            "remove",
            "--force",
            unregistered.path.to_str().context("path")?,
        ],
    )?;
    std::fs::create_dir(&unregistered.path)?;
    std::fs::write(unregistered.path.join("keep.txt"), "unregistered\n")?;
    assert!(matches!(
        repo.manager
            .cleanup(&unregistered, WorktreeCleanupPolicy::Discard)
            .await,
        Err(WorktreeError::IdentityMismatch(_))
    ));
    assert!(unregistered.path.join("keep.txt").exists());
    assert!(
        foreign.path.join("keep.txt").exists(),
        "no repository-wide prune or deletion"
    );
    Ok(())
}
