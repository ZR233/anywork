use std::{
    path::{Path, PathBuf},
    process::Command,
};

pub struct Repository {
    _directory: tempfile::TempDir,
    pub worktree: PathBuf,
    pub remote: PathBuf,
}

impl Repository {
    pub fn new() -> Self {
        let directory = tempfile::tempdir().unwrap();
        let worktree = directory.path().join("worktree");
        let remote = directory.path().join("origin.git");
        std::fs::create_dir(&worktree).unwrap();
        std::fs::create_dir(&remote).unwrap();
        git(&remote, &["init", "--bare", "--initial-branch=main"]);
        git(&worktree, &["init", "--initial-branch=main"]);
        git(&worktree, &["config", "user.name", "Git Tool Fixture"]);
        git(
            &worktree,
            &["config", "user.email", "git-tool@example.invalid"],
        );
        git(&worktree, &["config", "commit.gpgsign", "false"]);
        git(
            &worktree,
            &["remote", "add", "origin", remote.to_str().unwrap()],
        );
        std::fs::write(worktree.join("tracked.txt"), "initial\n").unwrap();
        git(&worktree, &["add", "tracked.txt"]);
        Self {
            _directory: directory,
            worktree,
            remote,
        }
    }
}

pub fn git(cwd: &Path, args: &[&str]) -> String {
    let output = Command::new("git")
        .args(args)
        .current_dir(cwd)
        .env("GIT_TERMINAL_PROMPT", "0")
        .output()
        .unwrap();
    assert!(
        output.status.success(),
        "git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    String::from_utf8(output.stdout).unwrap()
}
