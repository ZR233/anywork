//! Evidence only: use Git's existing blob implementation, never a second hasher
//! or a guessed target artifact. These Git commands do not write objects/index.

use super::*;

fn text(
    context: &ConversationReadWorkScenario<'_>,
    directory: &Path,
    label: &str,
    command: &mut Command,
) -> Result<String> {
    let evidence = run_tool(
        command,
        directory,
        label,
        context.interrupt,
        Duration::from_secs(120),
        None,
        None,
    );
    require_no_errors(&evidence.errors)?;
    fs::read_to_string(directory.join(format!("{label}.stdout.log")))
        .with_context(|| format!("read {label} command output"))
}

fn git(context: &ConversationReadWorkScenario<'_>) -> Command {
    let mut command = Command::new("git");
    command
        .current_dir(context.workspace)
        .env("GIT_OPTIONAL_LOCKS", "0");
    command
}

fn blob(
    context: &ConversationReadWorkScenario<'_>,
    directory: &Path,
    label: &str,
    path: &Path,
) -> Result<Value> {
    let path = fs::canonicalize(path)
        .with_context(|| format!("identify actual file {}", path.display()))?;
    let mut command = git(context);
    command
        .args(["hash-object", "--no-filters", "--"])
        .arg(&path);
    let object = text(context, directory, label, &mut command)?;
    let object = object.trim();
    ensure!(
        (object.len() == 40 || object.len() == 64)
            && object.bytes().all(|byte| byte.is_ascii_hexdigit()),
        "git hash-object returned an invalid identity: {object}"
    );
    Ok(json!({
        "gitBlob": object,
        "byteLength": fs::metadata(path)?.len(),
    }))
}

pub(super) fn source(context: &ConversationReadWorkScenario<'_>, phase: &str) -> Result<Value> {
    let directory = context.output.join(format!("profile-source-{phase}"));
    let mut head = git(context);
    head.args(["rev-parse", "HEAD"]);
    let head = text(context, &directory, "head", &mut head)?;
    let mut format = git(context);
    format.args(["rev-parse", "--show-object-format"]);
    let format = text(context, &directory, "object-format", &mut format)?;
    let mut status = git(context);
    status.args(["status", "--porcelain=v1", "--untracked-files=all"]);
    let status = text(context, &directory, "status", &mut status)?;
    let mut diff = git(context);
    diff.args([
        "diff",
        "--binary",
        "--no-ext-diff",
        "--no-textconv",
        "HEAD",
        "--",
    ]);
    text(context, &directory, "tracked-diff", &mut diff)?;
    let patch = blob(
        context,
        &directory,
        "tracked-diff-id",
        &directory.join("tracked-diff.stdout.log"),
    )?;
    let mut untracked = git(context);
    untracked.args(["ls-files", "--others", "--exclude-standard", "-z"]);
    let paths = text(context, &directory, "untracked", &mut untracked)?;
    let mut untracked_files = Vec::new();
    for (index, path) in paths
        .split('\0')
        .filter(|path| !path.is_empty())
        .enumerate()
    {
        untracked_files.push(json!({
            "path": path,
            "identity": blob(context, &directory, &format!("untracked-{index}"), &context.workspace.join(path))?,
        }));
    }
    Ok(json!({
        "head": head.trim(),
        "gitObjectFormat": format.trim(),
        "status": status,
        "trackedDiff": patch,
        "untrackedFiles": untracked_files,
    }))
}

pub(super) fn environment(context: &ConversationReadWorkScenario<'_>) -> Result<Value> {
    let directory = context.output.join("profile-environment");
    let mut flutter = Command::new("cargo");
    flutter
        .current_dir(context.workspace)
        .args(["flutter", "--version"]);
    let flutter = text(context, &directory, "flutter-version", &mut flutter)?;
    let mut rustc = Command::new("rustc");
    rustc
        .current_dir(context.workspace)
        .args(["--version", "--verbose"]);
    let rustc = text(context, &directory, "rustc-version", &mut rustc)?;
    let overrides: BTreeMap<_, _> = env::vars()
        .filter(|(name, _)| {
            name.starts_with("CARGO_PROFILE_RELEASE_")
                || matches!(
                    name.as_str(),
                    "RUSTFLAGS"
                        | "CARGO_ENCODED_RUSTFLAGS"
                        | "CARGO_BUILD_TARGET"
                        | "CARGO_TARGET_DIR"
                )
        })
        .collect();
    Ok(json!({
        "flutterVersionOutput": flutter,
        "rustcVersionOutput": rustc,
        "rustBuildOverrides": overrides,
        "rustBridge": {
            "configuration": "Profile",
            "cargoProfile": "release",
            "buildCommand": "cargo build --locked -p pl-studio-bridge --release",
            "configurationAuthority": blob(context, &directory, "bridge-build-source", &context.workspace.join("xtask/src/rust_bridge/mod.rs"))?,
            "workspaceManifest": blob(context, &directory, "workspace-manifest", &context.workspace.join("Cargo.toml"))?,
            "cargoLock": blob(context, &directory, "cargo-lock", &context.workspace.join("Cargo.lock"))?,
        },
        "appLock": blob(context, &directory, "app-lock", &context.workspace.join("code/anywork/pubspec.lock"))?,
        "probeSource": blob(context, &directory, "probe-source", &context.workspace.join("code/anywork/tool/profile_timeline_probe.dart"))?,
    }))
}

pub(super) fn artifacts(
    context: &ConversationReadWorkScenario<'_>,
    directory: &Path,
) -> Result<Value> {
    // Mirror only the documented native-launch paths, then require real files.
    // The packaged bridge is the one explicitly opened by StudioApi, not a
    // development target found by FRB's default search.
    let app = context.workspace.join("code/anywork");
    // Flutter's Profile AOT bundle targets install the Dart executable separately
    // from the native runner: LinuxAotBundle -> lib/libapp.so, WindowsAotBundle
    // -> data/app.so, and macOS embed -> App.framework/App (a versioned symlink).
    let (bundle, executable, bridge, dart_code) = match env::consts::OS {
        "linux" => (
            app.join("build/linux/x64/profile/bundle"),
            "anywork",
            "lib/libpl_studio_bridge.so",
            "lib/libapp.so",
        ),
        "windows" => (
            app.join("build/windows/x64/runner/Profile"),
            "anywork.exe",
            "pl_studio_bridge.dll",
            "data/app.so",
        ),
        "macos" => (
            app.join("build/macos/Build/Products/Profile/anywork.app/Contents"),
            "MacOS/anywork",
            "Frameworks/libpl_studio_bridge.dylib",
            "Frameworks/App.framework/App",
        ),
        os => bail!("unsupported native Profile artifact platform {os}"),
    };
    let native = bundle.join(executable);
    let bridge = bundle.join(bridge);
    let dart_code = bundle.join(dart_code);
    let identity_directory = directory.join("identity");
    Ok(json!({
        "flutterBuildMode": "profile",
        "rustBridgeConfiguration": "Profile",
        "rustBridgeCargoProfile": "release",
        "nativePath": fs::canonicalize(&native)?,
        "nativeIdentity": blob(context, &identity_directory, "native", &native)?,
        "packagedBridgePath": fs::canonicalize(&bridge)?,
        "packagedBridgeIdentity": blob(context, &identity_directory, "bridge", &bridge)?,
        "dartCodePath": fs::canonicalize(&dart_code)?,
        "dartCodeIdentity": blob(context, &identity_directory, "dart-code", &dart_code)?,
    }))
}

pub(super) fn require_same_artifacts(expected: &Value, actual: &Value) -> Result<()> {
    let ids = |value: &Value| -> Result<(String, String, String)> {
        let get = |field: &str| -> Result<String> {
            let id = value[field]["gitBlob"]
                .as_str()
                .context("missing artifact Git blob identity")?;
            ensure!(
                (id.len() == 40 || id.len() == 64)
                    && id.bytes().all(|byte| byte.is_ascii_hexdigit()),
                "invalid artifact Git blob identity"
            );
            Ok(id.to_owned())
        };
        Ok((
            get("nativeIdentity")?,
            get("packagedBridgeIdentity")?,
            get("dartCodeIdentity")?,
        ))
    };
    ensure!(
        ids(expected)? == ids(actual)?,
        "actual native, packaged bridge or Dart code artifact changed"
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fixed_artifacts_compare_real_blobs_not_paths_or_profile_labels() {
        let original = json!({
            "nativeIdentity": {"gitBlob": "a".repeat(40)},
            "packagedBridgeIdentity": {"gitBlob": "b".repeat(40)},
            "dartCodeIdentity": {"gitBlob": "d".repeat(40)},
            "nativePath": "/first/native", "rustBridgeCargoProfile": "release"
        });
        let mut same = original.clone();
        same["nativePath"] = json!("/other/native");
        assert!(require_same_artifacts(&original, &same).is_ok());
        same["packagedBridgeIdentity"]["gitBlob"] = json!("c".repeat(40));
        assert!(require_same_artifacts(&original, &same).is_err());
        let mut dart_changed = original.clone();
        dart_changed["dartCodeIdentity"]["gitBlob"] = json!("e".repeat(40));
        assert!(require_same_artifacts(&original, &dart_changed).is_err());
        let mut dart_missing = original.clone();
        assert!(
            dart_missing
                .as_object_mut()
                .unwrap()
                .remove("dartCodeIdentity")
                .is_some()
        );
        assert!(require_same_artifacts(&original, &dart_missing).is_err());
        assert!(require_same_artifacts(&original, &Value::Null).is_err());
    }
}
