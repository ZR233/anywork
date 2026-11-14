use sha2::{Digest, Sha256};
use std::{
    env, fs,
    path::{Path, PathBuf},
};

fn files(root: &Path, directory: &Path, out: &mut Vec<PathBuf>) {
    for entry in fs::read_dir(directory).expect("read bundled Skills") {
        let entry = entry.expect("read bundled Skill entry");
        if entry.file_type().expect("read Skill type").is_dir() {
            files(root, &entry.path(), out);
        } else {
            out.push(
                entry
                    .path()
                    .strip_prefix(root)
                    .expect("relative Skill path")
                    .into(),
            );
        }
    }
}
fn main() {
    let root = Path::new("assets/skills");
    println!("cargo:rerun-if-changed=assets/skills");
    let mut paths = Vec::new();
    files(root, root, &mut paths);
    paths.sort();
    let mut digest = Sha256::new();
    for path in paths {
        let name = path.to_str().expect("UTF-8 Skill path").replace('\\', "/");
        let contents = fs::read(root.join(path)).expect("read bundled Skill");
        digest.update((name.len() as u64).to_le_bytes());
        digest.update(name);
        digest.update((contents.len() as u64).to_le_bytes());
        digest.update(contents);
    }
    let output = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR"));
    fs::write(
        output.join("system_skills_fingerprint"),
        hex::encode(digest.finalize()),
    )
    .expect("write Skill fingerprint");
    if let Ok(target) = env::var("TARGET") {
        println!("cargo:rustc-env=PL_BUILD_TARGET={target}");
    }
    emit_git_commit_env();
}

fn emit_git_commit_env() {
    let manifest_dir =
        PathBuf::from(env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR"));
    if let Some(git_dir) = find_git_dir(&manifest_dir) {
        let head = git_dir.join("HEAD");
        if head.exists() {
            println!("cargo:rerun-if-changed={}", head.display());
            if let Ok(head_content) = fs::read_to_string(&head)
                && let Some(ref_path) = head_content.trim().strip_prefix("ref: ")
            {
                let target_ref = git_dir.join(ref_path.trim());
                if target_ref.exists() {
                    println!("cargo:rerun-if-changed={}", target_ref.display());
                }
            }
        }
    }
    let Ok(output) = std::process::Command::new("git")
        .arg("-C")
        .arg(&manifest_dir)
        .args(["rev-parse", "HEAD"])
        .output()
    else {
        return;
    };
    if !output.status.success() {
        return;
    }
    let commit = String::from_utf8_lossy(&output.stdout).trim().to_string();
    if !commit.is_empty() && commit.chars().all(|ch| ch.is_ascii_hexdigit()) {
        println!("cargo:rustc-env=PL_GIT_COMMIT={commit}");
    }
}

fn find_git_dir(start: &Path) -> Option<PathBuf> {
    for ancestor in start.ancestors() {
        let candidate = ancestor.join(".git");
        if candidate.is_dir() {
            return Some(candidate);
        }
        if candidate.is_file()
            && let Ok(text) = fs::read_to_string(&candidate)
            && let Some(rest) = text.trim().strip_prefix("gitdir: ")
        {
            let path = Path::new(rest.trim());
            return Some(if path.is_absolute() {
                path.to_path_buf()
            } else {
                ancestor.join(path)
            });
        }
    }
    None
}
