use crate::cli::{BuildGuiOptions, LogLevel, RunGuiOptions};
use crate::release_bundle::{self, BundleKind};
use crate::remote_helper::{self, BUNDLE_DIR_ENV};
use crate::rust_bridge::{
    self, BRIDGE_DEBUG_SYMBOLS_ENV, BRIDGE_LIBRARY_ENV, BridgeConfiguration, RustBridgeArtifacts,
};
use crate::studio_version;
use anyhow::{Context, Result, bail, ensure};
use pl_dev_support::paths;
use pl_dev_support::process;
use std::ffi::OsString;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::Command;

mod codegen;
mod integration;
mod preview;
pub(crate) use integration::DesktopTestPreparation;
pub(crate) use preview::run as preview_gui;
#[cfg(target_os = "linux")]
mod linux;

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
enum DesktopTarget {
    Windows,
    Macos,
    Linux,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DemoMode {
    Native,
    Demo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum FlutterProcessMode {
    Batch,
    Resident,
}

#[derive(Debug, Clone, Copy)]
struct FlutterInvocation<'a> {
    demo_mode: DemoMode,
    process_mode: FlutterProcessMode,
    bridge_artifacts: Option<&'a RustBridgeArtifacts>,
    remote_helper_bundle_dir: Option<&'a Path>,
    log_level: Option<LogLevel>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum DistCleanMode {
    Clean,
    KeepExisting,
}

impl DesktopTarget {
    fn current() -> Result<Self> {
        if cfg!(target_os = "windows") {
            Ok(Self::Windows)
        } else if cfg!(target_os = "macos") {
            Ok(Self::Macos)
        } else if cfg!(target_os = "linux") {
            Ok(Self::Linux)
        } else {
            bail!("unsupported desktop OS for Flutter GUI build")
        }
    }

    fn flutter_name(self) -> &'static str {
        match self {
            Self::Windows => "windows",
            Self::Macos => "macos",
            Self::Linux => "linux",
        }
    }

    fn release_artifact_dir(self, app_dir: &Path) -> PathBuf {
        match self {
            Self::Windows => app_dir
                .join("build")
                .join("windows")
                .join("x64")
                .join("runner")
                .join("Release"),
            Self::Macos => app_dir
                .join("build")
                .join("macos")
                .join("Build")
                .join("Products")
                .join("Release"),
            Self::Linux => app_dir
                .join("build")
                .join("linux")
                .join("x64")
                .join("release")
                .join("bundle"),
        }
    }

    /// Directory of the `flutter build` bundle for a debug or profile mode.
    fn native_bundle_dir(self, app_dir: &Path, profile: bool) -> PathBuf {
        match self {
            Self::Windows => app_dir
                .join("build")
                .join("windows")
                .join("x64")
                .join("runner")
                .join(if profile { "Profile" } else { "Debug" }),
            Self::Macos => app_dir
                .join("build")
                .join("macos")
                .join("Build")
                .join("Products")
                .join(if profile { "Profile" } else { "Debug" }),
            Self::Linux => app_dir
                .join("build")
                .join("linux")
                .join("x64")
                .join(if profile { "profile" } else { "debug" })
                .join("bundle"),
        }
    }

    fn executable_name(self) -> &'static str {
        match self {
            Self::Windows => "anywork.exe",
            Self::Macos => "anywork.app/Contents/MacOS/anywork",
            Self::Linux => "anywork",
        }
    }
}

pub(crate) fn generate_gui() -> Result<()> {
    codegen::generate_gui()
}

pub(crate) fn check_gui_generated() -> Result<()> {
    codegen::check_gui_generated()
}

pub(crate) fn verify_gui() -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let app_dir = paths::studio_app_dir(&workspace_root);
    print_context(&workspace_root, &app_dir);
    codegen::check_gui_generated_sources(&workspace_root, &app_dir)?;
    run_tool(
        "flutter",
        &[
            "pub",
            "get",
            "--enforce-lockfile",
            "--directory",
            "../anywork_previews",
        ],
        &app_dir,
    )?;
    run_tool("cargo", &["fmt", "--all", "--check"], &workspace_root)?;
    run_tool(
        "dart",
        &[
            "format",
            "--output=none",
            "--set-exit-if-changed",
            "lib",
            "test",
            "tool",
            "integration_test",
            "../anywork_previews/lib",
        ],
        &app_dir,
    )?;
    run_flutter(
        &workspace_root,
        &app_dir,
        &["analyze", "--no-pub", ".", "../anywork_previews"],
        DemoMode::Native,
    )?;
    run_tool(
        "dart",
        &[
            "--packages=.dart_tool/package_config.json",
            "../../xtask/dart/client_boundary_check.dart",
            "--ui-closure",
            "../..",
        ],
        &app_dir,
    )?;
    Ok(())
}

/// Runs one official desktop `integration_test` with the same bridge, helper,
/// and resident process ownership as a debug GUI run.
pub(crate) fn run_desktop_integration_test(
    preparation: &DesktopTestPreparation,
    test_path: &Path,
) -> Result<()> {
    preparation.validate()?;
    let workspace_root = preparation.workspace();
    let app_dir = paths::studio_app_dir(workspace_root);
    let target = DesktopTarget::current()?;
    let resolved = resolve_integration_test_path(&app_dir, test_path)?;
    let app_version = studio_version::read(&app_dir)?;
    let version_define = format!("--dart-define=ANYWORK_VERSION={app_version}");
    let app_root = app_dir
        .canonicalize()
        .context("resolve Flutter application directory")?;
    // Flutter interprets the CLI argument; keep canonical/device paths inside
    // the filesystem boundary and pass a verified app-relative test path.
    let test_arg = resolved
        .strip_prefix(&app_root)
        .context("desktop integration test is outside the Flutter application")?
        .to_string_lossy()
        .into_owned();
    print_context(workspace_root, &app_dir);
    let run_args = [
        "test",
        test_arg.as_str(),
        "-d",
        target.flutter_name(),
        "--no-pub",
        "--reporter=expanded",
        version_define.as_str(),
    ];
    run_flutter_with_process_mode(
        workspace_root,
        &app_dir,
        &run_args,
        FlutterInvocation {
            demo_mode: DemoMode::Native,
            process_mode: FlutterProcessMode::Resident,
            bridge_artifacts: Some(preparation.bridge()),
            remote_helper_bundle_dir: Some(preparation.helpers()),
            log_level: None,
        },
    )
}

fn resolve_integration_test_path(app_dir: &Path, test_path: &Path) -> Result<PathBuf> {
    let root = app_dir
        .join("integration_test")
        .canonicalize()
        .with_context(|| {
            format!(
                "integration_test directory is missing: {}",
                app_dir.join("integration_test").display()
            )
        })?;
    let candidate = if test_path.is_absolute() {
        test_path.to_path_buf()
    } else {
        app_dir.join(test_path)
    };
    let path = candidate.canonicalize().with_context(|| {
        format!(
            "desktop integration test does not exist: {}",
            candidate.display()
        )
    })?;
    ensure!(
        path.starts_with(&root),
        "desktop integration test must be inside {}: {}",
        root.display(),
        path.display()
    );
    ensure!(
        path.is_file(),
        "desktop integration test is not a file: {}",
        path.display()
    );
    Ok(path)
}

fn ensure_desktop_build_environment(target: DesktopTarget) -> Result<()> {
    match target {
        DesktopTarget::Linux => {
            #[cfg(target_os = "linux")]
            {
                linux::ensure_native_build_environment()
            }
            #[cfg(not(target_os = "linux"))]
            {
                Ok(())
            }
        }
        DesktopTarget::Windows | DesktopTarget::Macos => Ok(()),
    }
}

fn run_tool(program: &'static str, args: &[&str], cwd: &Path) -> Result<()> {
    let args = args.iter().map(OsString::from).collect::<Vec<_>>();
    run_os_tool(program, &args, cwd)
}

fn run_os_tool(program: &'static str, args: &[OsString], cwd: &Path) -> Result<()> {
    let display = process::display_command(program, args);
    let mut command = process::path_command(program, args);
    command.current_dir(cwd);
    process::run_checked(&mut command, &display)
}

pub(crate) fn run_gui(options: RunGuiOptions) -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let app_dir = paths::studio_app_dir(&workspace_root);
    let target = DesktopTarget::current()?;
    if options.release {
        let dist_dir = paths::release_dist_dir(&workspace_root);
        let executable = dist_dir.join(target.executable_name());
        ensure!(
            executable.is_file(),
            "release executable is missing: {}; run cargo xtask build-gui first",
            executable.display()
        );
        let mut command = Command::new(&executable);
        command.current_dir(&dist_dir);
        configure_flutter_environment(
            &mut command,
            FlutterInvocation {
                demo_mode: DemoMode::Native,
                process_mode: FlutterProcessMode::Resident,
                bridge_artifacts: None,
                remote_helper_bundle_dir: None,
                log_level: options.log_level,
            },
        );
        return process::run_resident_checked(&mut command, "anywork release");
    }
    if options.native_launch {
        return run_gui_native_launch(&workspace_root, &app_dir, target, options);
    }
    let app_version = studio_version::read(&app_dir)?;
    let version_define = format!("--dart-define=ANYWORK_VERSION={app_version}");
    print_context(&workspace_root, &app_dir);
    let preflight_started = std::time::Instant::now();
    ensure_desktop_build_environment(target)?;
    ensure_flutter_dependencies(&workspace_root, &app_dir)?;
    println!(
        "startup_stage=development_preflight elapsed_ms={}",
        preflight_started.elapsed().as_millis()
    );
    let demo_mode = if options.demo {
        DemoMode::Demo
    } else {
        DemoMode::Native
    };
    let remote_helper_bundle_dir = prepare_remote_helpers(&workspace_root, demo_mode)?;
    let run_args = run_gui_args(target, &version_define, &options);
    let bridge_artifacts =
        prepare_bridge_artifacts(&workspace_root, demo_mode, BridgeConfiguration::Debug)?;
    run_flutter_with_process_mode(
        &workspace_root,
        &app_dir,
        &run_args,
        FlutterInvocation {
            demo_mode,
            process_mode: if options.inspect {
                FlutterProcessMode::Resident
            } else {
                FlutterProcessMode::Batch
            },
            bridge_artifacts: bridge_artifacts.as_ref(),
            remote_helper_bundle_dir: remote_helper_bundle_dir.as_deref(),
            log_level: options.log_level,
        },
    )
}

/// Builds the debug/profile bundle and launches the native artifact directly.
///
/// The platform launch tool reports exit code 0 for whatever the app does
/// (`resident_runner.dart` `appFinished`/`_serviceDisconnected` complete `0`),
/// so it cannot prove a native exit. Launching the built bundle here makes this
/// process the artifact's real parent: its `waitpid` status is authoritative,
/// and a SIGTERM-ignoring grandchild the product failed to supervise shows up as
/// a reclaimed descendant instead of being silently masked. The VM service is
/// re-enabled through the same engine switches the launch tool uses.
fn run_gui_native_launch(
    workspace_root: &Path,
    app_dir: &Path,
    target: DesktopTarget,
    options: RunGuiOptions,
) -> Result<()> {
    let app_version = studio_version::read(app_dir)?;
    let version_define = format!("--dart-define=ANYWORK_VERSION={app_version}");
    print_context(workspace_root, app_dir);
    ensure_desktop_build_environment(target)?;
    ensure_flutter_dependencies(workspace_root, app_dir)?;
    let spec = NativeLaunchSpec::from_options(app_dir, &options)?;
    let demo_mode = spec.demo_mode;
    let remote_helper_bundle_dir = prepare_remote_helpers(workspace_root, demo_mode)?;
    let build_args = run_native_launch_args(
        target,
        &version_define,
        spec.profile,
        &spec.entrypoint,
        spec.capture,
    );
    let bridge_artifacts = prepare_bridge_artifacts(
        workspace_root,
        demo_mode,
        if spec.profile {
            BridgeConfiguration::Profile
        } else {
            BridgeConfiguration::Debug
        },
    )?;
    run_flutter_with_process_mode(
        workspace_root,
        app_dir,
        &build_args,
        FlutterInvocation {
            demo_mode,
            process_mode: FlutterProcessMode::Batch,
            bridge_artifacts: bridge_artifacts.as_ref(),
            remote_helper_bundle_dir: remote_helper_bundle_dir.as_deref(),
            log_level: options.log_level,
        },
    )?;

    let bundle_dir = target.native_bundle_dir(app_dir, spec.profile);
    let executable = bundle_dir.join(target.executable_name());
    ensure!(
        executable.is_file(),
        "native-launch artifact is missing after build: {}",
        executable.display()
    );
    let mut command = Command::new(&executable);
    command.current_dir(&bundle_dir);
    configure_flutter_environment(
        &mut command,
        FlutterInvocation {
            demo_mode,
            process_mode: FlutterProcessMode::Resident,
            bridge_artifacts: bridge_artifacts.as_ref(),
            remote_helper_bundle_dir: remote_helper_bundle_dir.as_deref(),
            log_level: options.log_level,
        },
    );
    configure_native_engine_environment(&mut command);
    let program = executable.to_string_lossy().into_owned();
    let display = process::display_command(&program, &[]);
    publish_native_launch_boundary(&mut std::io::stdout().lock())?;
    let native_started = std::time::Instant::now();
    let exit = process::run_resident_reporting(&mut command, &display)?;
    let report = NativeExitReport::from_exit(&exit, native_started.elapsed());
    if let Some(path) = spec.report.as_deref() {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create {}", parent.display()))?;
        }
        fs::write(path, serde_json::to_vec_pretty(&report)?)
            .with_context(|| format!("failed to write native exit report {}", path.display()))?;
    }
    println!(
        "native_exit pid={} status={} reclaimed_descendants={}",
        report.pid,
        report.status,
        report.reclaimed_descendants.len()
    );
    Ok(())
}

/// The VM readiness budget starts here, after every build and artifact check.
/// Failure to publish the complete line must abort before any native spawn.
fn publish_native_launch_boundary(output: &mut impl Write) -> Result<()> {
    output
        .write_all(b"startup_stage=native_launch_ready\n")
        .context("failed to publish native launch boundary")?;
    output
        .flush()
        .context("failed to flush native launch boundary")
}

#[cfg(test)]
mod native_startup_stage_tests {
    use super::publish_native_launch_boundary;
    use std::io::{self, Write};

    #[derive(Default)]
    struct BoundaryOutput {
        bytes: Vec<u8>,
        flushed: bool,
        fail_write: bool,
        fail_flush: bool,
    }

    impl Write for BoundaryOutput {
        fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
            if self.fail_write {
                return Err(io::Error::other("stage write failed"));
            }
            self.bytes.extend_from_slice(bytes);
            Ok(bytes.len())
        }

        fn flush(&mut self) -> io::Result<()> {
            if self.fail_flush {
                return Err(io::Error::other("stage flush failed"));
            }
            self.flushed = true;
            Ok(())
        }
    }

    #[test]
    fn launch_boundary_is_a_complete_flushed_line() -> anyhow::Result<()> {
        let mut output = BoundaryOutput::default();
        publish_native_launch_boundary(&mut output)?;
        assert_eq!(output.bytes, b"startup_stage=native_launch_ready\n");
        assert!(output.flushed);
        Ok(())
    }

    #[test]
    fn publication_errors_are_preserved() {
        for mut output in [
            BoundaryOutput {
                fail_write: true,
                ..Default::default()
            },
            BoundaryOutput {
                fail_flush: true,
                ..Default::default()
            },
        ] {
            let error = publish_native_launch_boundary(&mut output).unwrap_err();
            let diagnostic = format!("{error:#}");
            assert!(
                diagnostic.contains(if output.fail_write {
                    "stage write failed"
                } else {
                    "stage flush failed"
                }),
                "{diagnostic}"
            );
        }
    }
}

/// Structured, machine-readable record of a native artifact's real exit.
#[derive(serde::Serialize)]
#[serde(rename_all = "camelCase")]
struct NativeExitReport {
    schema: &'static str,
    /// Distinguishes Linux descendant adoption from macOS process-group coverage.
    process_ownership: &'static str,
    pid: u32,
    exit_code: Option<i32>,
    signal: Option<i32>,
    status: String,
    /// Native launch and process-tree wait, excluding compilation and preflight.
    elapsed_millis: u128,
    /// Subtree present when the native host was reaped, before the natural
    /// reclamation window (the set the product's own supervisor must reclaim).
    descendants_at_root_exit: Vec<u32>,
    /// Subtree still alive after the natural window and force-killed by the
    /// harness. Empty means the product supervised its own subtree.
    reclaimed_descendants: Vec<u32>,
    cancelled: bool,
}

impl NativeExitReport {
    fn from_exit(exit: &process::ResidentExit, elapsed: std::time::Duration) -> Self {
        #[cfg(unix)]
        let signal = {
            use std::os::unix::process::ExitStatusExt;
            exit.status.signal()
        };
        #[cfg(not(unix))]
        let signal = None;
        Self {
            schema: "anywork-native-exit/1",
            process_ownership: if cfg!(target_os = "linux") {
                "adopted-descendants"
            } else if cfg!(target_os = "macos") {
                "process-group"
            } else {
                "windows-job"
            },
            pid: exit.pid,
            exit_code: exit.status.code(),
            signal,
            status: exit.status.to_string(),
            elapsed_millis: elapsed.as_millis(),
            descendants_at_root_exit: exit.descendants_at_root_exit.clone(),
            reclaimed_descendants: exit.reclaimed_descendants.clone(),
            cancelled: exit.cancelled,
        }
    }
}

/// Launch contract for a directly started debug/profile artifact.
///
/// Entrypoint, build mode, capture, and the native exit report are explicit.
/// Inspection uses the official Driver extension in a dedicated debug target;
/// VM service authentication remains enabled for inspection and capture.
struct NativeLaunchSpec {
    entrypoint: String,
    profile: bool,
    capture: bool,
    demo_mode: DemoMode,
    report: Option<PathBuf>,
}

impl NativeLaunchSpec {
    fn from_options(app_dir: &Path, options: &RunGuiOptions) -> Result<Self> {
        let entrypoint = match options.native_launch_target.as_deref() {
            Some(path) => {
                let path = if path.is_absolute() {
                    path.to_path_buf()
                } else {
                    app_dir.join(path)
                };
                ensure!(
                    path.is_file(),
                    "native-launch target does not exist: {}",
                    path.display()
                );
                path.to_string_lossy().into_owned()
            }
            None if options.inspect => "tool/inspect_main.dart".to_owned(),
            None => "lib/main.dart".to_owned(),
        };
        Ok(Self {
            entrypoint,
            profile: options.profile,
            capture: options.capture,
            demo_mode: if options.demo {
                DemoMode::Demo
            } else {
                DemoMode::Native
            },
            report: options.native_exit_report.clone(),
        })
    }
}

/// Enables the VM service for a directly launched debug/profile artifact.
///
/// The launch tool delivers these to the engine through `FLUTTER_ENGINE_SWITCH_*`
/// rather than command-line arguments (`desktop_device.dart`
/// `_computeEnvironment`). Auth codes stay enabled so capture uses the ordinary
/// authenticated VM service.
fn configure_native_engine_environment(command: &mut Command) {
    command.env("FLUTTER_ENGINE_SWITCHES", "2");
    command.env("FLUTTER_ENGINE_SWITCH_1", "enable-dart-profiling=true");
    command.env("FLUTTER_ENGINE_SWITCH_2", "enable-checked-mode=true");
}

fn run_native_launch_args<'a>(
    target: DesktopTarget,
    version_define: &'a str,
    profile: bool,
    launch_target: &'a str,
    capture: bool,
) -> Vec<&'a str> {
    let mut args = vec![
        "build",
        target.flutter_name(),
        if profile { "--profile" } else { "--debug" },
        version_define,
        "--no-pub",
        "-t",
        launch_target,
    ];
    if capture {
        args.push("--dart-define=ANYWORK_CAPTURE=true");
    }
    args
}

fn run_gui_args<'a>(
    target: DesktopTarget,
    version_define: &'a str,
    options: &RunGuiOptions,
) -> Vec<&'a str> {
    let mut args = vec![
        "run",
        "-d",
        target.flutter_name(),
        version_define,
        "--no-pub",
    ];
    if options.capture {
        args.push("--dart-define=ANYWORK_CAPTURE=true");
    }
    if options.inspect {
        args.extend(["-t", "tool/inspect_main.dart", "--print-dtd"]);
    }
    args
}

pub(crate) fn build_gui(options: BuildGuiOptions) -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let app_dir = paths::studio_app_dir(&workspace_root);
    let target = DesktopTarget::current()?;
    let app_version = studio_version::read(&app_dir)?;
    print_context(&workspace_root, &app_dir);
    ensure_desktop_build_environment(target)?;
    ensure_flutter_dependencies_for_build(&workspace_root, &app_dir)?;
    if options.check_generated {
        codegen::check_gui_generated_sources_for_build(&workspace_root, &app_dir)?;
    }
    let version_define = format!("--dart-define=ANYWORK_VERSION={app_version}");
    let demo_mode = if options.demo {
        DemoMode::Demo
    } else {
        DemoMode::Native
    };
    let remote_helper_bundle_dir = prepare_remote_helpers(&workspace_root, demo_mode)?;
    let configuration = if options.debug {
        BridgeConfiguration::Debug
    } else {
        BridgeConfiguration::Release
    };
    let args = build_gui_args(target, &version_define, configuration);
    let bridge_artifacts = prepare_bridge_artifacts(&workspace_root, demo_mode, configuration)?;
    run_flutter_with_process_mode(
        &workspace_root,
        &app_dir,
        &args,
        FlutterInvocation {
            demo_mode,
            process_mode: FlutterProcessMode::Batch,
            bridge_artifacts: bridge_artifacts.as_ref(),
            remote_helper_bundle_dir: remote_helper_bundle_dir.as_deref(),
            log_level: None,
        },
    )?;

    if options.debug {
        println!(
            "Debug build complete. Output: {}",
            target.native_bundle_dir(&app_dir, false).display()
        );
        return Ok(());
    }

    let artifact_dir = target.release_artifact_dir(&app_dir);
    let dist_dir = paths::release_dist_dir(&workspace_root);

    let clean_mode = if options.no_clean {
        DistCleanMode::KeepExisting
    } else {
        DistCleanMode::Clean
    };
    copy_release_artifacts(&artifact_dir, &dist_dir, clean_mode, target)
}

fn build_gui_args(
    target: DesktopTarget,
    version_define: &str,
    configuration: BridgeConfiguration,
) -> Vec<&str> {
    vec![
        "build",
        target.flutter_name(),
        match configuration {
            BridgeConfiguration::Debug => "--debug",
            BridgeConfiguration::Profile => "--profile",
            BridgeConfiguration::Release => "--release",
        },
        version_define,
        "--no-pub",
    ]
}

fn ensure_flutter_dependencies_for_build(workspace_root: &Path, app_dir: &Path) -> Result<()> {
    run_flutter(
        workspace_root,
        app_dir,
        &["pub", "get", "--enforce-lockfile"],
        DemoMode::Native,
    )
}

pub(super) fn ensure_flutter_dependencies(workspace_root: &Path, app_dir: &Path) -> Result<()> {
    run_flutter(workspace_root, app_dir, &["pub", "get"], DemoMode::Native)
}

fn print_context(workspace_root: &Path, app_dir: &Path) {
    println!("Workspace root: {}", workspace_root.display());
    println!("Studio app dir: {}", app_dir.display());
}

fn prepare_remote_helpers(workspace_root: &Path, demo_mode: DemoMode) -> Result<Option<PathBuf>> {
    if matches!(demo_mode, DemoMode::Native) {
        let started = std::time::Instant::now();
        let bundle_dir = remote_helper::prepare_bundle_resources(workspace_root)?;
        println!(
            "startup_stage=build_remote_helpers elapsed_ms={}",
            started.elapsed().as_millis()
        );
        return Ok(Some(bundle_dir));
    }
    Ok(None)
}

fn prepare_bridge_artifacts(
    workspace_root: &Path,
    demo_mode: DemoMode,
    configuration: BridgeConfiguration,
) -> Result<Option<RustBridgeArtifacts>> {
    if matches!(demo_mode, DemoMode::Native) {
        let started = std::time::Instant::now();
        let result =
            rust_bridge::build_workspace_artifacts(workspace_root, configuration).map(Some);
        println!(
            "startup_stage=build_bridge elapsed_ms={}",
            started.elapsed().as_millis()
        );
        return result;
    }
    Ok(None)
}

fn run_flutter(
    workspace_root: &Path,
    app_dir: &Path,
    args: &[&str],
    demo_mode: DemoMode,
) -> Result<()> {
    run_flutter_with_process_mode(
        workspace_root,
        app_dir,
        args,
        FlutterInvocation {
            demo_mode,
            process_mode: FlutterProcessMode::Batch,
            bridge_artifacts: None,
            remote_helper_bundle_dir: None,
            log_level: None,
        },
    )
}

fn run_flutter_with_process_mode(
    _workspace_root: &Path,
    app_dir: &Path,
    args: &[&str],
    invocation: FlutterInvocation<'_>,
) -> Result<()> {
    let args = flutter_args(args, invocation.demo_mode);
    let display = process::display_command("flutter", &args);
    let mut command = process::path_command("flutter", &args);
    command.current_dir(app_dir);
    configure_flutter_environment(&mut command, invocation);
    match invocation.process_mode {
        FlutterProcessMode::Batch => process::run_checked(&mut command, &display),
        FlutterProcessMode::Resident => process::run_resident_checked(&mut command, &display),
    }
}

fn configure_flutter_environment(command: &mut Command, invocation: FlutterInvocation<'_>) {
    // Xcode can report arm64e as NATIVE_ARCH_ACTUAL on Apple Silicon; the Rust
    // target and Flutter engine both use arm64. Keep every native input aligned.
    #[cfg(target_os = "macos")]
    command.env(
        "ANYWORK_MACOS_ARCH",
        if cfg!(target_arch = "aarch64") {
            "arm64"
        } else {
            "x86_64"
        },
    );
    command.env_remove(BRIDGE_LIBRARY_ENV);
    command.env_remove(BRIDGE_DEBUG_SYMBOLS_ENV);
    command.env_remove(BUNDLE_DIR_ENV);
    match invocation.demo_mode {
        DemoMode::Native => {
            command.env_remove("ANYWORK_DEMO");
        }
        DemoMode::Demo => {
            command.env("ANYWORK_DEMO", "true");
        }
    }
    match invocation.log_level {
        Some(log_level) => {
            command.env("ANYWORK_LOG_LEVEL", log_level.as_str());
        }
        None => {
            command.env_remove("ANYWORK_LOG_LEVEL");
        }
    }
    if let Some(artifacts) = invocation.bridge_artifacts {
        command.env(BRIDGE_LIBRARY_ENV, artifacts.dynamic_library());
        if let Some(debug_symbols) = artifacts.debug_symbols() {
            command.env(BRIDGE_DEBUG_SYMBOLS_ENV, debug_symbols);
        }
    }
    if let Some(bundle_dir) = invocation.remote_helper_bundle_dir {
        command.env(BUNDLE_DIR_ENV, bundle_dir);
    }
}

fn flutter_args(args: &[&str], demo_mode: DemoMode) -> Vec<OsString> {
    let mut result = args.iter().map(OsString::from).collect::<Vec<_>>();
    if matches!(demo_mode, DemoMode::Demo) && !args.contains(&"--dart-define=ANYWORK_DEMO=true") {
        result.push(OsString::from("--dart-define=ANYWORK_DEMO=true"));
    }
    result
}

fn copy_release_artifacts(
    artifact_dir: &Path,
    dist_dir: &Path,
    clean_mode: DistCleanMode,
    target: DesktopTarget,
) -> Result<()> {
    if !artifact_dir.is_dir() {
        bail!(
            "build artifact directory not found: {}",
            artifact_dir.display()
        );
    }
    if matches!(clean_mode, DistCleanMode::Clean) && dist_dir.exists() {
        clean_directory_contents(dist_dir)?;
    }
    fs::create_dir_all(dist_dir)
        .with_context(|| format!("failed to create {}", dist_dir.display()))?;
    let bundle_kind = if target == DesktopTarget::Windows {
        BundleKind::Windows
    } else {
        BundleKind::PreserveAll
    };
    if target == DesktopTarget::Macos {
        release_bundle::copy(
            &artifact_dir.join("anywork.app"),
            &dist_dir.join("anywork.app"),
            bundle_kind,
        )?;
    } else {
        release_bundle::copy(artifact_dir, dist_dir, bundle_kind)?;
    }

    println!();
    println!("Release build complete.");
    println!("Output: {}", dist_dir.display());
    let mut files = fs::read_dir(dist_dir)
        .with_context(|| format!("failed to read {}", dist_dir.display()))?
        .filter_map(Result::ok)
        .filter(|entry| entry.file_type().is_ok_and(|kind| kind.is_file()))
        .map(|entry| entry.file_name())
        .collect::<Vec<_>>();
    files.sort();
    if !files.is_empty() {
        println!("Files:");
        for file in files {
            println!("  {}", file.to_string_lossy());
        }
    }
    Ok(())
}

fn clean_directory_contents(directory: &Path) -> Result<()> {
    for entry in fs::read_dir(directory)
        .with_context(|| format!("failed to read {} for cleanup", directory.display()))?
    {
        let entry =
            entry.with_context(|| format!("failed to read entry in {}", directory.display()))?;
        let path = entry.path();
        let file_type = entry
            .file_type()
            .with_context(|| format!("failed to inspect {}", path.display()))?;
        let result = if file_type.is_dir() {
            fs::remove_dir_all(&path)
        } else {
            fs::remove_file(&path)
        };
        result.with_context(|| format!("failed to remove stale artifact {}", path.display()))?;
    }
    Ok(())
}
