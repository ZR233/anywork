use std::path::{Path, PathBuf};
use std::sync::OnceLock;

/// Workspace `pl-remote-helper` binary for the current profile.
pub fn remote_helper_executable() -> &'static Path {
    static PATH: OnceLock<PathBuf> = OnceLock::new();
    PATH.get_or_init(locate).as_path()
}

fn locate() -> PathBuf {
    let name = format!("pl-remote-helper{}", std::env::consts::EXE_SUFFIX);
    let profile = if cfg!(debug_assertions) {
        "debug"
    } else {
        "release"
    };
    if let Some(path) = existing(&name, profile) {
        return path;
    }
    let status = std::process::Command::new(env!("CARGO"))
        .args(["build", "--locked", "-p", "pl-remote-helper"])
        .status()
        .expect("spawn cargo to build pl-remote-helper");
    assert!(
        status.success(),
        "cargo build -p pl-remote-helper failed with {status}"
    );
    existing(&name, profile).unwrap_or_else(|| {
        panic!("pl-remote-helper was built but not found under target/{profile}")
    })
}

fn existing(name: &str, profile: &str) -> Option<PathBuf> {
    candidates(name, profile)
        .into_iter()
        .find(|path| path.is_file())
}

fn candidates(name: &str, profile: &str) -> Vec<PathBuf> {
    let mut paths = Vec::new();
    if let Ok(dir) = std::env::var("CARGO_TARGET_DIR") {
        paths.push(PathBuf::from(dir).join(profile).join(name));
    }
    paths.push(
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(profile)
            .join(name),
    );
    paths
}
