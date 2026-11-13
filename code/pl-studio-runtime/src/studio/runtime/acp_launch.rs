//! One preparation boundary for authentication and business ACP processes.
use std::collections::BTreeMap;
use std::ffi::{OsStr, OsString};
use std::path::{Path, PathBuf};

use tokio_util::sync::CancellationToken;

use crate::config::{AcpLaunch, AcpProvider, AcpServiceDefinition};
use crate::studio::StudioStore;

/// Memory-only frozen launch. Never serialize it into a product/session document.
pub(super) struct ResolvedAcpLaunch {
    pub program: PathBuf,
    pub args: Vec<String>,
    pub env: BTreeMap<OsString, OsString>,
    pub expected_server_version: Option<String>,
    pub template: Option<AcpProvider>,
}

pub(super) enum AcpLaunchError {
    Template(super::acp_install::PrepareFailure),
    InvalidWorkingDirectory,
    MissingExecutable,
    InvalidDefinition,
    Cancelled,
}

pub(super) async fn resolve_launch(
    store: &StudioStore,
    definition: &AcpServiceDefinition,
    cwd: &Path,
    cancellation: &CancellationToken,
) -> Result<ResolvedAcpLaunch, AcpLaunchError> {
    if cancellation.is_cancelled() {
        return Err(AcpLaunchError::Cancelled);
    }
    definition
        .validate()
        .map_err(|_| AcpLaunchError::InvalidDefinition)?;
    if !cwd.is_absolute() || !cwd.is_dir() {
        return Err(AcpLaunchError::InvalidWorkingDirectory);
    }
    let env = super::acp_worker::launch_environment(&definition.env);
    match &definition.launch {
        AcpLaunch::Command { command, args } => {
            // which 8 uses the supplied PATH and actual cwd for relative PATH entries.
            // No shell, additional search or package-manager-specific shim is involved.
            let path = env.iter().find_map(|(key, value)| {
                if key == OsStr::new("PATH") {
                    Some(value)
                } else {
                    #[cfg(windows)]
                    if key.to_string_lossy().eq_ignore_ascii_case("PATH") {
                        return Some(value);
                    }
                    None
                }
            });
            let program = which::which_in(command, path, cwd)
                .map_err(|_| AcpLaunchError::MissingExecutable)?;
            Ok(ResolvedAcpLaunch {
                program,
                args: args.clone(),
                env,
                expected_server_version: None,
                template: None,
            })
        }
        AcpLaunch::Template(template) => {
            let verified: super::acp_install::VerifiedInstall =
                super::acp_install::verified_install(store, *template, cancellation)
                    .await
                    .map_err(AcpLaunchError::Template)?;
            tracing::debug!(
                installation = %verified.installation_id,
                version = %verified.release.version,
                target = %verified.release.target,
                "ACP launch uses a verified managed installation"
            );
            Ok(ResolvedAcpLaunch {
                program: verified.program,
                args: verified.args,
                env,
                expected_server_version: Some(super::acp_install::SERVER_VERSION.into()),
                template: Some(*template),
            })
        }
    }
}

#[cfg(all(test, target_os = "linux"))]
mod tests {
    use super::*;
    use crate::studio::runtime::acp_worker::{AcpSpawnError, AcpSpawnRequest, AcpWorker, Reclaim};
    use pl_remote_helper::Executor;
    use std::os::unix::fs::PermissionsExt;
    use tokio::io::{AsyncBufReadExt, BufReader};

    #[tokio::test]
    async fn real_child_uses_frozen_path_env_argv_cwd_and_confirms_root_exit() {
        let temp = tempfile::tempdir().unwrap();
        let store = StudioStore::open(temp.path().join("home/data/studio.sqlite"))
            .await
            .unwrap();
        let cwd = temp.path().join("actual workspace");
        let bin = cwd.join("relative-bin");
        std::fs::create_dir_all(&bin).unwrap();
        let program = bin.join("synthetic-agent");
        std::fs::write(
            &program,
            r#"#!/bin/sh
/bin/sleep 60 &
child=$!
printf '%s\n' "$PWD" "$ACP_FIXTURE_VALUE" "$1" "$PATH" "$HOME" "$$" "$child"
i=0
while [ "$i" -lt 2048 ]; do
  printf '%s' 'stderr-token-not-for-publication' >&2
  i=$((i+1))
done
wait
"#,
        )
        .unwrap();
        std::fs::set_permissions(&program, std::fs::Permissions::from_mode(0o700)).unwrap();
        let mut definition = AcpServiceDefinition {
            id: "fixture".into(),
            display_name: "Fixture".into(),
            enabled: true,
            launch: AcpLaunch::Command {
                command: "synthetic-agent".into(),
                args: vec!["literal $HOME ; with spaces".into()],
            },
            env: BTreeMap::from([
                ("PATH".into(), "relative-bin".into()),
                (
                    "HOME".into(),
                    temp.path()
                        .join("isolated-home")
                        .to_string_lossy()
                        .into_owned(),
                ),
                ("ACP_FIXTURE_VALUE".into(), "literal $VALUE".into()),
            ]),
        };
        let cancel = CancellationToken::new();
        let resolved = resolve_launch(&store, &definition, &cwd, &cancel)
            .await
            .ok()
            .expect("resolve generic command");
        assert_eq!(resolved.program, program);
        assert_eq!(resolved.expected_server_version, None);
        assert_eq!(resolved.template, None);
        // Later desired edits cannot alter this prepared launch or trigger another search.
        definition.launch = AcpLaunch::Command {
            command: "nonexistent-after-freeze".into(),
            args: Vec::new(),
        };
        definition
            .env
            .insert("PATH".into(), "/nonexistent-after-freeze".into());
        let source = Executor::local().expect("local executor");
        let mut worker = AcpWorker::spawn(
            AcpSpawnRequest {
                program: resolved.program,
                args: resolved.args,
                env: resolved.env,
                cwd: cwd.clone(),
            },
            &source,
            &cancel,
        )
        .await
        .expect("spawn supervised fixture");
        let (writer, reader) = worker.take_streams().expect("stdio");
        drop(writer);
        let mut lines = BufReader::new(reader).lines();
        let observed = tokio::time::timeout(std::time::Duration::from_secs(10), async {
            let mut observed = Vec::new();
            for _ in 0..7 {
                observed.push(lines.next_line().await.unwrap().expect("fixture line"));
            }
            observed
        })
        .await;
        // Always join the actual process owner before asserting fixture output.
        let reclaimed =
            tokio::time::timeout(std::time::Duration::from_secs(10), worker.reclaim()).await;
        assert!(
            matches!(reclaimed, Ok(Reclaim::Stopped)),
            "worker must report real process and stderr reclamation"
        );
        let observed = observed.expect("fixture output arrived");
        assert_eq!(observed[0], cwd.to_string_lossy());
        assert_eq!(observed[1], "literal $VALUE");
        assert_eq!(observed[2], "literal $HOME ; with spaces");
        assert_eq!(observed[3], "relative-bin");
        assert_eq!(
            observed[4],
            temp.path().join("isolated-home").to_string_lossy()
        );
        assert!(
            !std::path::Path::new("/proc").join(&observed[5]).exists(),
            "the direct child was reaped"
        );
        // Root exit does not synchronize with the descendant's exit. Wait for its actual
        // terminal state; an orphaned zombie may still await reaping by the system parent.
        let descendant = std::path::Path::new("/proc")
            .join(&observed[6])
            .join("stat");
        let deadline = tokio::time::Instant::now() + std::time::Duration::from_secs(10);
        loop {
            let stat = match std::fs::read_to_string(&descendant) {
                Ok(stat) => stat,
                Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
                Err(error) => panic!("read descendant state: {error}"),
            };
            if stat
                .rsplit_once(") ")
                .is_some_and(|(_, tail)| tail.starts_with('Z'))
            {
                break;
            }
            assert!(
                tokio::time::Instant::now() < deadline,
                "the descendant is still running: {stat}"
            );
            tokio::time::sleep(std::time::Duration::from_millis(10)).await;
        }

        let absent = temp.path().join("never-created");
        let cancellation = CancellationToken::new();
        cancellation.cancel();
        let result = AcpWorker::spawn(
            AcpSpawnRequest {
                program: program.clone(),
                args: Vec::new(),
                cwd: absent.clone(),
                env: BTreeMap::new(),
            },
            &source,
            &cancellation,
        )
        .await;
        assert!(matches!(result, Err(AcpSpawnError::Cancelled)));
        assert!(!absent.exists());
        // Even an uncancelled worker cannot create a business directory.
        if let Ok(mut worker) = AcpWorker::spawn(
            AcpSpawnRequest {
                program,
                args: Vec::new(),
                cwd: absent.clone(),
                env: BTreeMap::new(),
            },
            &source,
            &CancellationToken::new(),
        )
        .await
        {
            assert!(matches!(
                tokio::time::timeout(std::time::Duration::from_secs(10), worker.reclaim()).await,
                Ok(Reclaim::Stopped | Reclaim::Settled(_))
            ));
        }
        assert!(!absent.exists());
    }

    #[tokio::test]
    async fn missing_template_is_explicit_and_generic_requires_no_managed_installation() {
        let temp = tempfile::tempdir().unwrap();
        let store = StudioStore::open(temp.path().join("home/data/studio.sqlite"))
            .await
            .unwrap();
        let template = AcpServiceDefinition::template(
            "template".into(),
            "Template".into(),
            AcpProvider::Antigravity,
        );
        let result =
            resolve_launch(&store, &template, temp.path(), &CancellationToken::new()).await;
        assert!(matches!(
            result,
            Err(AcpLaunchError::Template(
                super::super::acp_install::PrepareFailure::PreparationRequired
            ))
        ));
        let generic = AcpServiceDefinition {
            id: "generic".into(),
            display_name: "Generic".into(),
            enabled: true,
            launch: AcpLaunch::Command {
                command: "/bin/cat".into(),
                args: Vec::new(),
            },
            env: BTreeMap::new(),
        };
        let launch = resolve_launch(&store, &generic, temp.path(), &CancellationToken::new())
            .await
            .ok()
            .expect("generic launch independent of installation");
        assert!(launch.expected_server_version.is_none());
        assert!(launch.template.is_none());
    }
}
