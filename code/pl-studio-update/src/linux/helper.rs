use super::*;
use futures::StreamExt;
use std::os::unix::fs::{DirBuilderExt, MetadataExt};

/// Private executable entry; neither mode executes arbitrary commands or paths.
pub async fn run_helper() -> Result<(), StudioUpdateError> {
    let mut input = BufReader::new(tokio::io::stdin());
    let mut output = tokio::io::stdout();
    let result = match std::env::args().nth(1).as_deref() {
        Some("supervise") if !rustix::process::getuid().is_root() => {
            supervise(&mut input, &mut output).await
        }
        Some("install") if rustix::process::geteuid().is_root() => {
            install(&mut input, &mut output).await
        }
        _ => Err(launch_error("invalid update helper mode or identity")),
    };
    if let Err(error) = &result {
        let _ = send(
            &mut output,
            &Reply::Finished {
                error: Some(error.to_string()),
            },
        )
        .await;
    }
    result
}

async fn request(
    input: &mut (impl tokio::io::AsyncBufRead + Unpin),
) -> Result<Request, StudioUpdateError> {
    let request: Request =
        serde_json::from_str(&line(input).await?).map_err(|e| launch_error(e.to_string()))?;
    crate::manifest::validate_update(&request.update)?;
    if request.update.platform != crate::StudioUpdatePlatform::LinuxX86_64
        || request.signature.len() > 16 * 1024
        || semver::Version::parse(&request.update.version)
            .map_err(|e| launch_error(e.to_string()))?
            <= semver::Version::parse(crate::STUDIO_VERSION.trim())
                .map_err(|e| launch_error(e.to_string()))?
    {
        return Err(launch_error("the request is not a newer Linux release"));
    }
    Ok(request)
}

fn open_snapshot(request: &Request, uid: u32) -> Result<File, StudioUpdateError> {
    let parts: Vec<_> = request.source.split('/').collect();
    if parts.len() != 5
        || !parts[0].is_empty()
        || parts[1] != "proc"
        || parts[3] != "fd"
        || parts[2].parse::<u32>().is_err()
        || parts[4].parse::<u32>().is_err()
    {
        return Err(launch_error(
            "the installer source is not a process file descriptor",
        ));
    }
    let file = File::open(&request.source).map_err(io_error)?;
    let metadata = file.metadata().map_err(io_error)?;
    let required = rustix::fs::SealFlags::WRITE
        | rustix::fs::SealFlags::GROW
        | rustix::fs::SealFlags::SHRINK
        | rustix::fs::SealFlags::SEAL;
    if !metadata.is_file()
        || metadata.uid() != uid
        || metadata.len() != request.update.installer.size
        || !rustix::fs::fcntl_get_seals(&file)
            .map_err(|e| io_error(e.into()))?
            .contains(required)
    {
        return Err(launch_error(
            "the installer snapshot is not immutable or belongs to another user",
        ));
    }
    Ok(file)
}

async fn abort(child: &mut Child, input: ChildStdin) -> Result<(), StudioUpdateError> {
    drop(input); // A privileged helper exits without installing on channel EOF.
    // During authentication pkexec still has the caller's real uid. Once exec
    // has changed identity, EOF is the installer protocol's cancellation signal.
    let _ = child.start_kill();
    child.wait().await.map_err(io_error)?;
    Ok(())
}

async fn reap_committed_child(
    child: &mut Child,
    mut output: BufReader<tokio::process::ChildStdout>,
) -> Result<std::process::ExitStatus, StudioUpdateError> {
    // A failed reply/ACK delivery may leave the privileged helper writing its
    // terminal result. Drain it before waiting so pipe backpressure cannot
    // prevent exit. On read failure, closing the pipe still lets it settle.
    let drained = tokio::io::copy(&mut output, &mut tokio::io::sink()).await;
    drop(output);
    let result = child.wait().await.map_err(io_error);
    if let Err(error) = drained {
        tracing::warn!(%error, "failed to drain committed installer output");
    }
    result
}

async fn supervise(
    input: &mut (impl tokio::io::AsyncBufRead + Unpin),
    output: &mut (impl tokio::io::AsyncWrite + Unpin),
) -> Result<(), StudioUpdateError> {
    let mut request = request(input).await?;
    if rustix::process::getppid().map(|p| p.as_raw_pid() as u32) != Some(request.app_pid) {
        return Err(launch_error("the application parent identity changed"));
    }
    let snapshot = open_snapshot(&request, rustix::process::getuid().as_raw())?;
    request.source = format!("/proc/{}/fd/{}", std::process::id(), snapshot.as_raw_fd());
    let mut child = Command::new("/usr/bin/pkexec")
        .args(["--disable-internal-agent", HELPER, "install"])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .map_err(io_error)?;
    let mut privileged_input = child
        .stdin
        .take()
        .ok_or_else(|| launch_error("missing privileged input"))?;
    let mut privileged_output = BufReader::new(
        child
            .stdout
            .take()
            .ok_or_else(|| launch_error("missing privileged output"))?,
    );
    let mut committed = false;
    let outcome: Result<Option<String>, StudioUpdateError> = async {
        send(&mut privileged_input, &request).await?;
        let ready = tokio::select! {
            _ = line(input) => Err(launch_error("installation cancelled before authorization")),
            result = read_reply(&mut privileged_output) => result,
        }?;
        match ready {
            Reply::Ready => {}
            Reply::Finished { error: Some(error) } => return Err(launch_error(error)),
            _ => return Err(launch_error("system authorization was cancelled or failed")),
        }
        send(output, &Reply::Ready).await?;
        if line(input).await?.trim() != "commit" {
            return Err(launch_error("installation cancelled before clean shutdown"));
        }
        privileged_input
            .write_all(b"commit\n")
            .await
            .map_err(io_error)?;
        privileged_input.flush().await.map_err(io_error)?;
        if !matches!(read_reply(&mut privileged_output).await?, Reply::Committed) {
            return Err(launch_error(
                "privileged installer did not accept the handoff",
            ));
        }
        committed = true;
        send(output, &Reply::Committed).await?;
        match read_reply(&mut privileged_output).await? {
            Reply::Finished { error } => Ok(error),
            _ => Err(launch_error("installer ended without a transaction result")),
        }
    }
    .await;
    // All paths, including channel/serialization errors, close and reap the
    // privileged child. EOF is an abort before commit, never an install intent.
    let status = if committed {
        drop(privileged_input);
        reap_committed_child(&mut child, privileged_output).await?
    } else {
        abort(&mut child, privileged_input).await?;
        if child
            .try_wait()
            .map_err(io_error)?
            .and_then(|status| status.code())
            == Some(126)
        {
            send(output, &Reply::Cancelled).await?;
            return Ok(());
        }
        return Err(outcome
            .err()
            .unwrap_or_else(|| launch_error("installation was not committed")));
    };
    let error = match outcome {
        Ok(error) if status.success() => error,
        Ok(Some(error)) => Some(error),
        Err(error) => Some(error.to_string()),
        _ => Some(format!(
            "installer ended without a confirmed transaction result: {status}"
        )),
    };
    let receipt = write_receipt(&Receipt {
        update: request.update,
        error,
    });
    // The original user, with the original desktop environment, starts the app.
    // The privileged helper never launches a GUI or receives its environment.
    Command::new(APP)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .spawn()
        .map_err(io_error)?;
    receipt?;
    Ok(())
}

fn write_receipt(receipt: &Receipt) -> Result<(), StudioUpdateError> {
    let directory = dirs::state_dir()
        .ok_or_else(|| launch_error("user state directory unavailable"))?
        .join("anywork");
    std::fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&directory)
        .map_err(io_error)?;
    let mut file = tempfile::NamedTempFile::new_in(&directory).map_err(io_error)?;
    serde_json::to_writer(file.as_file_mut(), receipt).map_err(|e| launch_error(e.to_string()))?;
    file.as_file().sync_all().map_err(io_error)?;
    file.persist(directory.join("update-result.json"))
        .map_err(|e| io_error(e.error))?;
    Ok(())
}

fn observe_process(
    pid: u32,
) -> Result<tokio::io::unix::AsyncFd<rustix::fd::OwnedFd>, StudioUpdateError> {
    let pid = rustix::process::Pid::from_raw(pid as i32)
        .ok_or_else(|| launch_error("invalid application process"))?;
    let pidfd = rustix::process::pidfd_open(pid, rustix::process::PidfdFlags::empty())
        .map_err(|e| io_error(e.into()))?;
    // SAFETY: pidfd is exclusively owned and stays alive inside AsyncFd. We
    // only await readiness; it is never read, written, duplicated or replaced.
    let process = unsafe { tokio::io::unix::AsyncFd::register(pidfd) }
        .map_err(|e| launch_error(e.to_string()))?;
    Ok(process)
}

async fn install(
    input: &mut (impl tokio::io::AsyncBufRead + Unpin),
    output: &mut (impl tokio::io::AsyncWrite + Unpin),
) -> Result<(), StudioUpdateError> {
    let request = request(input).await?;
    let uid = std::env::var("PKEXEC_UID")
        .map_err(|_| launch_error("pkexec identity is missing"))?
        .parse::<u32>()
        .map_err(|e| launch_error(e.to_string()))?;
    if uid == 0
        || std::fs::metadata(format!("/proc/{}", request.app_pid))
            .map_err(io_error)?
            .uid()
            != uid
    {
        return Err(launch_error(
            "the target application belongs to another user",
        ));
    }
    let process = observe_process(request.app_pid)?;
    let mut snapshot = open_snapshot(&request, uid)?;
    // PackageKit/APT's path API needs a .deb filename. Only the privileged owner
    // creates this directory, so user cache replacement cannot change the bytes.
    let staging = tempfile::Builder::new()
        .prefix("anywork-update-")
        .tempdir_in("/var/tmp")
        .map_err(io_error)?;
    let package = staging
        .path()
        .join(request.update.platform.asset_name(&request.update.version));
    let mut destination = File::create(&package).map_err(io_error)?;
    std::io::copy(&mut snapshot, &mut destination).map_err(io_error)?;
    destination.sync_all().map_err(io_error)?;
    crate::verification::verify(
        File::open(&package).map_err(io_error)?,
        &request.update.installer,
        include_str!("../anywork.pub"),
        &request.signature,
    )?;
    let metadata = Command::new("/usr/bin/dpkg-deb")
        .args(["--field"])
        .arg(&package)
        .args(["Package", "Version", "Architecture"])
        .output()
        .await
        .map_err(io_error)?;
    let expected = format!(
        "Package: anywork\nVersion: {}\nArchitecture: amd64\n",
        request.update.version
    );
    if !metadata.status.success() || metadata.stdout != expected.as_bytes() {
        return Err(launch_error(
            "the signed .deb package identity does not match the update",
        ));
    }
    let connection = zbus::Connection::system().await.map_err(bus_error)?;
    let control = zbus::Proxy::new(
        &connection,
        "org.freedesktop.PackageKit",
        "/org/freedesktop/PackageKit",
        "org.freedesktop.PackageKit",
    )
    .await
    .map_err(bus_error)?;
    let backend: String = control
        .get_property("BackendName")
        .await
        .map_err(bus_error)?;
    if backend != "aptcc" && backend != "apt" {
        return Err(launch_error(format!(
            "unsupported PackageKit backend: {backend}"
        )));
    }
    send(output, &Reply::Ready).await?;
    if line(input).await?.trim() != "commit" {
        return Err(launch_error("installation was not committed"));
    }
    send(output, &Reply::Committed).await?;
    // A clean report authorizes installation, but does not prove process exit.
    // Never replace files while the original process still runs.
    let _exit = tokio::time::timeout(Duration::from_secs(40), process.readable())
        .await
        .map_err(|_| launch_error("the original application did not exit"))?
        .map_err(io_error)?;
    if let Err(error) = install_package(&connection, &control, &package).await {
        if error.code() == StudioUpdateErrorCode::InstallerOutcomeUnknown {
            // A lost daemon does not prove that its package-manager child has
            // stopped reading. Retain these bytes for recovery, never unlink
            // an installation input whose completion is still unknown.
            let retained = staging.keep();
            eprintln!(
                "installation outcome unknown; retained {}",
                retained.display()
            );
        }
        return Err(error);
    }
    send(output, &Reply::Finished { error: None }).await
}

async fn install_package(
    connection: &zbus::Connection,
    control: &zbus::Proxy<'_>,
    path: &std::path::Path,
) -> Result<(), StudioUpdateError> {
    let transaction_path: zbus::zvariant::OwnedObjectPath = control
        .call("CreateTransaction", &())
        .await
        .map_err(bus_error)?;
    let transaction = zbus::Proxy::new(
        connection,
        "org.freedesktop.PackageKit",
        transaction_path,
        "org.freedesktop.PackageKit.Transaction",
    )
    .await
    .map_err(bus_error)?;
    // Subscribe before invoking InstallFiles: fast errors/Finished must not race
    // observer registration. One ordered stream carries every transaction signal.
    let mut signals = transaction.receive_all_signals().await.map_err(bus_error)?;
    let mut owners = transaction
        .receive_owner_changed()
        .await
        .map_err(bus_error)?;
    let _: () = transaction
        .call("SetHints", &(vec!["interactive=false"],))
        .await
        .map_err(bus_error)?;
    // Application Minisign verification is independent of repository GPG trust.
    // This locally signed .deb is authorized by pkexec, never marked GPG-trusted.
    let _: () = transaction
        .call(
            "InstallFiles",
            &(0_u64, vec![path.to_string_lossy().as_ref()]),
        )
        .await
        .map_err(bus_error)?;
    let mut error = None;
    loop {
        let signal = tokio::select! {
            biased;
            signal = signals.next() => match signal { Some(signal) => signal, None => break },
            _ = owners.next() => return Err(unknown_outcome("PackageKit changed owner before confirming the transaction outcome")),
        };
        match signal.header().member().map(|m| m.as_str()) {
            Some("ErrorCode") => {
                let (code, details): (u32, String) =
                    signal.body().deserialize().map_err(bus_error)?;
                error = Some(format!("PackageKit error {code}: {details}"));
            }
            Some("Finished") => {
                let (exit, _runtime): (u32, u32) =
                    signal.body().deserialize().map_err(bus_error)?;
                return if exit == 1 && error.is_none() {
                    Ok(())
                } else {
                    Err(launch_error(error.unwrap_or_else(|| {
                        format!("PackageKit transaction exited with {exit}")
                    })))
                };
            }
            _ => {}
        }
    }
    Err(unknown_outcome(
        "PackageKit disconnected before confirming the transaction outcome",
    ))
}

fn bus_error(error: impl std::fmt::Display) -> StudioUpdateError {
    unknown_outcome(format!("PackageKit communication failed: {error}"))
}

fn unknown_outcome(error: impl Into<String>) -> StudioUpdateError {
    StudioUpdateError::new(StudioUpdateErrorCode::InstallerOutcomeUnknown, error)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Write;

    #[tokio::test]
    async fn committed_child_is_reaped_even_when_its_reply_reader_failed() {
        let mut child = Command::new("head")
            .args(["-c", "131072", "/dev/zero"])
            .stdout(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let output = BufReader::new(child.stdout.take().unwrap());
        let result = tokio::time::timeout(
            Duration::from_secs(2),
            reap_committed_child(&mut child, output),
        )
        .await;
        if result.is_err() {
            let _ = child.kill().await;
            child.wait().await.unwrap();
        }
        assert!(
            result
                .expect("committed installer blocked on its unread output")
                .unwrap()
                .success()
        );
        assert!(child.try_wait().unwrap().is_some());
    }

    #[test]
    fn handoff_rejects_mutable_or_foreign_descriptors_and_seals_prevent_replacement() {
        let fd = rustix::fs::memfd_create("updater-test", rustix::fs::MemfdFlags::ALLOW_SEALING)
            .unwrap();
        let mut file = File::from(fd);
        file.write_all(b"test").unwrap();
        let request = Request {
            update: crate::test_support::update(b"test"),
            signature: String::new(),
            source: format!("/proc/{}/fd/{}", std::process::id(), file.as_raw_fd()),
            app_pid: std::process::id(),
        };
        let uid = rustix::process::getuid().as_raw();
        assert!(open_snapshot(&request, uid).is_err());
        rustix::fs::fcntl_add_seals(
            &file,
            rustix::fs::SealFlags::WRITE
                | rustix::fs::SealFlags::GROW
                | rustix::fs::SealFlags::SHRINK
                | rustix::fs::SealFlags::SEAL,
        )
        .unwrap();
        assert!(file.write_all(b"evil").is_err());
        assert!(file.set_len(0).is_err());
        assert!(open_snapshot(&request, uid.wrapping_add(1)).is_err());
        let mut lease = open_snapshot(&request, uid).unwrap();
        let mut bytes = String::new();
        lease.read_to_string(&mut bytes).unwrap();
        assert_eq!(bytes, "test");
    }

    #[tokio::test]
    #[ignore = "requires a disposable root container with the real PackageKit system service"]
    async fn real_packagekit_upgrades_and_preserves_installed_version_on_failure() {
        assert!(rustix::process::geteuid().is_root());
        assert!(
            std::path::Path::new("/run/anywork-updater-test").is_dir(),
            "never execute package mutations outside the dedicated disposable image"
        );
        let fixture = tempfile::tempdir().unwrap();
        let connection = zbus::Connection::system().await.unwrap();
        let control = zbus::Proxy::new(
            &connection,
            "org.freedesktop.PackageKit",
            "/org/freedesktop/PackageKit",
            "org.freedesktop.PackageKit",
        )
        .await
        .unwrap();
        for (version, dependency, success) in [
            ("1.0.0", "libc6", true),
            ("2.0.0", "libc6", true),
            ("3.0.0", "anywork-updater-missing-dependency", false),
        ] {
            let directory = fixture.path().join(version);
            std::fs::create_dir_all(directory.join("DEBIAN")).unwrap();
            std::fs::create_dir_all(directory.join("usr/share/anywork-updater-fixture")).unwrap();
            std::fs::write(directory.join("DEBIAN/control"), format!(
                "Package: anywork-updater-fixture\nVersion: {version}\nArchitecture: amd64\nMaintainer: Test <test@example.invalid>\nDepends: {dependency}\nDescription: isolated update transaction fixture\n")).unwrap();
            std::fs::write(
                directory.join("usr/share/anywork-updater-fixture/version"),
                version,
            )
            .unwrap();
            let package = fixture
                .path()
                .join(format!("anywork-updater-fixture-{version}.deb"));
            assert!(
                Command::new("dpkg-deb")
                    .args(["--build", "--root-owner-group"])
                    .arg(&directory)
                    .arg(&package)
                    .status()
                    .await
                    .unwrap()
                    .success()
            );
            let outcome = tokio::time::timeout(
                Duration::from_secs(90),
                install_package(&connection, &control, &package),
            )
            .await
            .unwrap();
            assert_eq!(outcome.is_ok(), success, "{version}: {outcome:?}");
            let installed = Command::new("dpkg-query")
                .args(["-W", "-f=${Version}", "anywork-updater-fixture"])
                .output()
                .await
                .unwrap();
            assert!(installed.status.success());
            let expected = if success { version } else { "2.0.0" };
            assert_eq!(String::from_utf8(installed.stdout).unwrap(), expected);
            assert_eq!(
                std::fs::read_to_string("/usr/share/anywork-updater-fixture/version").unwrap(),
                expected
            );
        }
        assert!(
            Command::new("dpkg")
                .args(["--remove", "anywork-updater-fixture"])
                .status()
                .await
                .unwrap()
                .success()
        );
    }

    #[tokio::test]
    async fn a_clean_handoff_still_waits_for_the_actual_process_exit() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "read command"])
            .stdin(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let process = observe_process(child.id().unwrap()).unwrap();
        assert!(
            tokio::time::timeout(Duration::from_millis(20), process.readable())
                .await
                .is_err()
        );
        assert!(child.try_wait().unwrap().is_none());
        child.kill().await.unwrap();
        child.wait().await.unwrap();
        let _ready = tokio::time::timeout(Duration::from_secs(2), process.readable())
            .await
            .unwrap()
            .unwrap();
    }

    #[tokio::test]
    async fn a_lost_commit_ack_is_never_reported_as_success_by_a_retry() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "read command; exit 0"])
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let mut handoff = LinuxHandoff {
            input: child.stdin.take(),
            output: BufReader::new(child.stdout.take().unwrap()),
            child,
            commit_state: CommitState::Pending,
            _sealed: tempfile::tempfile().unwrap(),
        };
        assert!(handoff.commit().await.is_err());
        assert_eq!(
            handoff.commit().await.unwrap_err().code(),
            StudioUpdateErrorCode::InstallerOutcomeUnknown
        );
        assert_eq!(
            handoff.abort().await.unwrap_err().code(),
            StudioUpdateErrorCode::CancellationTooLate
        );
        handoff.child.wait().await.unwrap();
    }

    struct Control;
    #[zbus::interface(name = "org.freedesktop.PackageKit")]
    impl Control {
        fn create_transaction(&self) -> zbus::zvariant::OwnedObjectPath {
            zbus::zvariant::OwnedObjectPath::try_from(
                "/org/freedesktop/PackageKit/transactions/test",
            )
            .unwrap()
        }
    }
    struct Transaction {
        exit: u32,
    }
    #[zbus::interface(name = "org.freedesktop.PackageKit.Transaction")]
    impl Transaction {
        fn set_hints(&self, hints: Vec<String>) {
            assert_eq!(hints, ["interactive=false"]);
        }
        async fn install_files(
            &self,
            flags: u64,
            files: Vec<String>,
            #[zbus(signal_emitter)] emitter: zbus::object_server::SignalEmitter<'_>,
        ) -> zbus::fdo::Result<()> {
            assert_eq!(flags, 0);
            assert_eq!(files, ["/fixture/anywork.deb"]);
            if self.exit != 1 {
                Self::error_code(&emitter, 5, "fixture install failure").await?;
            }
            // Deliberately finish before the method reply: subscribing afterwards loses this signal.
            Self::finished(&emitter, self.exit, 0).await?;
            Ok(())
        }
        #[zbus(signal)]
        async fn error_code(
            emitter: &zbus::object_server::SignalEmitter<'_>,
            code: u32,
            details: &str,
        ) -> zbus::Result<()>;
        #[zbus(signal)]
        async fn finished(
            emitter: &zbus::object_server::SignalEmitter<'_>,
            exit: u32,
            runtime: u32,
        ) -> zbus::Result<()>;
    }

    #[tokio::test]
    async fn packagekit_requires_a_real_finished_signal_and_preserves_transaction_errors() {
        for exit in [1, 2] {
            let mut bus = Command::new("dbus-daemon")
                .args(["--session", "--nofork", "--print-address=1"])
                .stdout(Stdio::piped())
                .kill_on_drop(true)
                .spawn()
                .unwrap();
            let mut address = String::new();
            BufReader::new(bus.stdout.take().unwrap())
                .read_line(&mut address)
                .await
                .unwrap();
            let server = zbus::connection::Builder::address(address.trim())
                .unwrap()
                .name("org.freedesktop.PackageKit")
                .unwrap()
                .serve_at("/org/freedesktop/PackageKit", Control)
                .unwrap()
                .serve_at(
                    "/org/freedesktop/PackageKit/transactions/test",
                    Transaction { exit },
                )
                .unwrap()
                .build()
                .await
                .unwrap();
            let client = zbus::connection::Builder::address(address.trim())
                .unwrap()
                .build()
                .await
                .unwrap();
            let control = zbus::Proxy::new(
                &client,
                "org.freedesktop.PackageKit",
                "/org/freedesktop/PackageKit",
                "org.freedesktop.PackageKit",
            )
            .await
            .unwrap();
            let outcome = tokio::time::timeout(
                Duration::from_secs(5),
                install_package(
                    &client,
                    &control,
                    std::path::Path::new("/fixture/anywork.deb"),
                ),
            )
            .await
            .unwrap();
            if exit == 1 {
                outcome.unwrap();
            } else {
                assert!(
                    outcome
                        .unwrap_err()
                        .to_string()
                        .contains("fixture install failure")
                );
            }
            drop(control);
            drop(client);
            drop(server);
            bus.kill().await.unwrap();
            bus.wait().await.unwrap();
        }
    }

    #[tokio::test]
    async fn abort_closes_the_control_channel_and_reaps_the_child() {
        let mut child = Command::new("/bin/sh")
            .args(["-c", "read command; exit 0"])
            .stdin(Stdio::piped())
            .kill_on_drop(true)
            .spawn()
            .unwrap();
        let input = child.stdin.take().unwrap();
        abort(&mut child, input).await.unwrap();
        assert!(child.try_wait().unwrap().is_some());
    }
}
