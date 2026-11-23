//! 受管 Antigravity 大版本 `1` 注册表解析、升级、离线择优与后台版本检查单元测试。

use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use anyhow::Result;
use axum::Router;
use axum::extract::{Path as AxumPath, State};
use axum::http::StatusCode;
use axum::response::IntoResponse;
use axum::routing::get;
use serde_json::json;
use sha2::Digest;
use tokio::net::TcpListener;
use tokio_util::sync::CancellationToken;

use super::prepare::{self, PrepareFailure};
#[cfg(target_os = "linux")]
use super::seed_synthetic_install_version;
use super::source::{self, RegistryLookup, SourcePolicy, TestSourceOverride};
use crate::config::{ConfigPaths, ConfigStore, StudioConfig};
use crate::{
    AcpInstallFailureCode, AcpInstallSnapshot, AcpInstallState, AcpInstallUpdateState, AcpProvider,
    CheckAcpInstallUpdateRequest, StartAcpInstallRequest, StudioHostKind,
    StudioProductBaselineState, StudioProductEventKind, StudioProductFrame, StudioProductTopic,
    StudioRuntime, StudioRuntimeOptions,
};

#[derive(Clone, Default)]
struct MockServerState {
    registry_body: Arc<Mutex<Vec<u8>>>,
    archives: Arc<Mutex<HashMap<String, Vec<u8>>>>,
    registry_delay: Arc<Mutex<Option<Duration>>>,
}

async fn serve_registry(State(state): State<MockServerState>) -> impl IntoResponse {
    let delay = *state.registry_delay.lock().unwrap();
    if let Some(delay) = delay {
        tokio::time::sleep(delay).await;
    }
    let body = state.registry_body.lock().unwrap().clone();
    (StatusCode::OK, body)
}

async fn serve_archive(
    State(state): State<MockServerState>,
    AxumPath(name): AxumPath<String>,
) -> impl IntoResponse {
    let found = state.archives.lock().unwrap().get(&name).cloned();
    match found {
        Some(bytes) => (StatusCode::OK, bytes).into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

async fn start_mock_server(
    state: MockServerState,
) -> Result<(String, String, tokio::task::JoinHandle<()>)> {
    let listener = TcpListener::bind("127.0.0.1:0").await?;
    let address = listener.local_addr()?;
    let app = Router::new()
        .route("/registry.json", get(serve_registry))
        .route("/archives/{name}", get(serve_archive))
        .with_state(state);
    let handle = tokio::spawn(async move {
        let _ = axum::serve(listener, app).await;
    });
    let base = format!("http://{address}");
    Ok((
        format!("{base}/registry.json"),
        format!("{base}/archives/"),
        handle,
    ))
}

fn crc32_ieee(bytes: &[u8]) -> u32 {
    let mut crc = 0xFFFF_FFFFu32;
    for &byte in bytes {
        crc ^= u32::from(byte);
        for _ in 0..8 {
            let mask = (crc & 1).wrapping_neg();
            crc = (crc >> 1) ^ (0xEDB8_8320 & mask);
        }
    }
    !crc
}

/// 构造满足 `archive::extract` 全部安全性校验的 STORED ZIP 并返回 `(bytes, sha256_hex)`。
fn build_stored_zip(entries: &[(&str, &[u8], u32)]) -> (Vec<u8>, String) {
    let mut out = Vec::new();
    let mut central = Vec::new();
    for &(name, data, mode) in entries {
        let local_offset = u32::try_from(out.len()).unwrap();
        let name_bytes = name.as_bytes();
        let crc = crc32_ieee(data);
        let size = u32::try_from(data.len()).unwrap();
        let name_len = u16::try_from(name_bytes.len()).unwrap();

        // Local file header (30 bytes + name)
        out.extend_from_slice(b"PK\x03\x04");
        out.extend_from_slice(&20u16.to_le_bytes()); // version needed
        out.extend_from_slice(&0x0800u16.to_le_bytes()); // UTF-8 flag
        out.extend_from_slice(&0u16.to_le_bytes()); // STORE
        out.extend_from_slice(&0u16.to_le_bytes()); // mod time
        out.extend_from_slice(&0u16.to_le_bytes()); // mod date
        out.extend_from_slice(&crc.to_le_bytes());
        out.extend_from_slice(&size.to_le_bytes());
        out.extend_from_slice(&size.to_le_bytes());
        out.extend_from_slice(&name_len.to_le_bytes());
        out.extend_from_slice(&0u16.to_le_bytes()); // extra len
        out.extend_from_slice(name_bytes);
        out.extend_from_slice(data);

        // Central directory header (46 bytes + name)
        central.extend_from_slice(b"PK\x01\x02");
        central.extend_from_slice(&0x0314u16.to_le_bytes()); // UNIX + version 2.0
        central.extend_from_slice(&20u16.to_le_bytes()); // version needed
        central.extend_from_slice(&0x0800u16.to_le_bytes()); // UTF-8 flag
        central.extend_from_slice(&0u16.to_le_bytes()); // STORE
        central.extend_from_slice(&0u16.to_le_bytes()); // mod time
        central.extend_from_slice(&0u16.to_le_bytes()); // mod date
        central.extend_from_slice(&crc.to_le_bytes());
        central.extend_from_slice(&size.to_le_bytes());
        central.extend_from_slice(&size.to_le_bytes());
        central.extend_from_slice(&name_len.to_le_bytes());
        central.extend_from_slice(&0u16.to_le_bytes()); // extra len
        central.extend_from_slice(&0u16.to_le_bytes()); // comment len
        central.extend_from_slice(&0u16.to_le_bytes()); // disk number
        central.extend_from_slice(&0u16.to_le_bytes()); // internal attrs
        central.extend_from_slice(&(mode << 16).to_le_bytes()); // external attrs (Unix mode)
        central.extend_from_slice(&local_offset.to_le_bytes());
        central.extend_from_slice(name_bytes);
    }
    let cd_offset = u32::try_from(out.len()).unwrap();
    let cd_size = u32::try_from(central.len()).unwrap();
    let count = u16::try_from(entries.len()).unwrap();
    out.extend_from_slice(&central);

    // End of central directory (22 bytes)
    out.extend_from_slice(b"PK\x05\x06");
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());
    out.extend_from_slice(&count.to_le_bytes());
    out.extend_from_slice(&count.to_le_bytes());
    out.extend_from_slice(&cd_size.to_le_bytes());
    out.extend_from_slice(&cd_offset.to_le_bytes());
    out.extend_from_slice(&0u16.to_le_bytes());

    let sha256 = hex::encode(sha2::Sha256::digest(&out));
    (out, sha256)
}

fn target_command_and_args(target: &str) -> (&'static str, Vec<&'static str>) {
    if target.starts_with("linux-") {
        ("agy_acp_server.par", vec!["--uid="])
    } else if target.starts_with("windows-") {
        ("agy_acp_server.exe", Vec::new())
    } else {
        ("agy_acp_server.par", Vec::new())
    }
}

fn registry_json(
    version: &str,
    target: &str,
    archive_url: &str,
    cmd: &str,
    args: &[&str],
    sha256: &str,
) -> Vec<u8> {
    serde_json::to_vec(&json!({
        "agents": [{
            "id": "antigravity-acp",
            "version": version,
            "distribution": {
                "binary": {
                    target: {
                        "archive": archive_url,
                        "cmd": format!("./{cmd}"),
                        "args": args,
                        "sha256": sha256,
                    }
                }
            }
        }]
    }))
    .unwrap()
}

async fn test_runtime() -> Result<(tempfile::TempDir, StudioRuntime)> {
    let home = tempfile::tempdir()?;
    let config = StudioConfig::default_config()?;
    let paths = ConfigPaths::from_config_dir(home.path());
    ConfigStore::new(paths).save(&config)?;
    let runtime = StudioRuntime::initialize(StudioRuntimeOptions {
        studio_home: Some(home.path().to_owned()),
        host: StudioHostKind::Test,
        ..StudioRuntimeOptions::desktop()
    })
    .await?;
    Ok((home, runtime))
}

async fn wait_install_snapshot(
    runtime: &StudioRuntime,
    predicate: impl Fn(&AcpInstallSnapshot) -> bool,
) -> Result<AcpInstallSnapshot> {
    tokio::time::timeout(Duration::from_secs(15), async {
        let mut updates = runtime
            .subscribe_product_topic(StudioProductTopic::AcpInstall)
            .await?;
        loop {
            let snapshot = match updates
                .recv()
                .await
                .expect("install topic emits frames")
                .expect("install topic stays open")
            {
                StudioProductFrame::Baseline(baseline) => match baseline.state {
                    StudioProductBaselineState::AcpInstall(snapshot) => *snapshot,
                    other => anyhow::bail!("unexpected install baseline: {other:?}"),
                },
                StudioProductFrame::Event(event) => match event.kind {
                    StudioProductEventKind::AcpInstallStateChanged(snapshot) => *snapshot,
                    other => anyhow::bail!("unexpected install event: {other:?}"),
                },
                StudioProductFrame::Lagged { dropped, .. } => {
                    anyhow::bail!("lagged {dropped} install updates");
                }
            };
            if predicate(&snapshot) {
                return Ok(snapshot);
            }
        }
    })
    .await?
}

#[tokio::test]
async fn registry_parsing_enforces_major_version_and_security_boundaries() -> Result<()> {
    let policy = SourcePolicy::official();
    let target = "linux-x86_64";
    let sha = "0".repeat(64);
    let official_url = "https://dl.google.com/agy-extensions/releases/antigravity-acp/1.5.2/agy-acp-server-1.5.2-linux-x86_64.zip";

    // Valid 1.5.2 release
    let valid = registry_json(
        "1.5.2",
        target,
        official_url,
        "agy_acp_server.par",
        &["--uid="],
        &sha,
    );
    match source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &valid)
        .expect("1.5.2 registry parses")
    {
        RegistryLookup::Release(resolved) => {
            assert_eq!(resolved.release.version, "1.5.2");
            assert_eq!(resolved.command, "agy_acp_server.par");
            assert_eq!(resolved.args, vec!["--uid="]);
        }
        other => panic!("expected release, got {other:?}"),
    }

    // Below minimum 1.4.5 -> SourceRejected
    let too_old = registry_json(
        "1.4.4",
        target,
        official_url,
        "agy_acp_server.par",
        &["--uid="],
        &sha,
    );
    assert_eq!(
        source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &too_old)
            .unwrap_err()
            .code,
        AcpInstallFailureCode::SourceRejected
    );

    // Major 2.0.0 -> IncompatibleMajor
    let major_two = registry_json(
        "2.0.0",
        target,
        official_url,
        "agy_acp_server.par",
        &["--uid="],
        &sha,
    );
    assert_eq!(
        source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &major_two)
            .expect("2.0.0 registry classifies as IncompatibleMajor"),
        RegistryLookup::IncompatibleMajor {
            version: "2.0.0".to_string()
        }
    );

    // Untrusted archive URL -> SourceRejected
    let untrusted = registry_json(
        "1.5.2",
        target,
        "https://evil.example.com/agy-acp-server-1.5.2-linux-x86_64.zip",
        "agy_acp_server.par",
        &["--uid="],
        &sha,
    );
    assert_eq!(
        source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &untrusted)
            .unwrap_err()
            .code,
        AcpInstallFailureCode::SourceRejected
    );

    // Malformed SHA-256 -> SourceRejected
    let bad_sha = registry_json(
        "1.5.2",
        target,
        official_url,
        "agy_acp_server.par",
        &["--uid="],
        "BAD",
    );
    assert_eq!(
        source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &bad_sha)
            .unwrap_err()
            .code,
        AcpInstallFailureCode::SourceRejected
    );

    // Disallowed command / args -> SourceRejected
    let bad_cmd = registry_json("1.5.2", target, official_url, "evil.sh", &["--uid="], &sha);
    assert_eq!(
        source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &bad_cmd)
            .unwrap_err()
            .code,
        AcpInstallFailureCode::SourceRejected
    );
    for bad_args in [&["positional"][..], &["--uid=;sh"][..]] {
        let bad_arg = registry_json(
            "1.5.2",
            target,
            official_url,
            "agy_acp_server.par",
            bad_args,
            &sha,
        );
        assert_eq!(
            source::parse_registry_payload(&policy, AcpProvider::Antigravity, target, &bad_arg)
                .unwrap_err()
                .code,
            AcpInstallFailureCode::SourceRejected
        );
    }

    // Oversized registry payload (> 2 MiB) -> TooLarge
    let state = MockServerState {
        registry_body: Arc::new(Mutex::new(vec![b' '; 2 * 1024 * 1024 + 1024])),
        ..Default::default()
    };
    let (registry_url, archive_base_url, handle) = start_mock_server(state).await?;
    let test_policy = SourcePolicy::for_test(TestSourceOverride {
        registry_url,
        archive_base_url,
    });
    let cancel = CancellationToken::new();
    let error = source::fetch_latest_from_registry(&test_policy, AcpProvider::Antigravity, &cancel)
        .await
        .unwrap_err();
    handle.abort();
    assert_eq!(error.code, AcpInstallFailureCode::TooLarge);
    Ok(())
}

#[tokio::test]
async fn mock_http_install_and_upgrade_from_1_4_5_to_1_5_2() -> Result<()> {
    let target = source::current_target().expect("supported test target");
    let (cmd, args) = target_command_and_args(target);
    let (zip_145, sha_145) = build_stored_zip(&[(cmd, b"#!/bin/sh\necho 1.4.5\n", 0o100755)]);
    let (zip_152, sha_152) = build_stored_zip(&[(cmd, b"#!/bin/sh\necho 1.5.2\n", 0o100755)]);

    let state = MockServerState::default();
    {
        let mut archives = state.archives.lock().unwrap();
        archives.insert("agy-1.4.5.zip".into(), zip_145);
        archives.insert("agy-1.5.2.zip".into(), zip_152);
    }
    let (registry_url, archive_base_url, server_handle) = start_mock_server(state.clone()).await?;
    *state.registry_body.lock().unwrap() = registry_json(
        "1.4.5",
        target,
        &format!("{archive_base_url}agy-1.4.5.zip"),
        cmd,
        &args,
        &sha_145,
    );

    let (_home, runtime) = test_runtime().await?;
    runtime
        .acp_install
        .set_test_source_override(TestSourceOverride {
            registry_url,
            archive_base_url: archive_base_url.clone(),
        });

    // Step 1: initial install 1.4.5
    runtime.start_acp_install(StartAcpInstallRequest {
        operation_id: "install-145".into(),
        provider: AcpProvider::Antigravity,
    })?;
    let after_install = wait_install_snapshot(&runtime, |snapshot| {
        matches!(
            &snapshot.state_of(AcpProvider::Antigravity),
            AcpInstallState::Ready { server, .. } if server.release.version == "1.4.5"
        )
    })
    .await?;
    assert_eq!(
        after_install
            .installed_of(AcpProvider::Antigravity)
            .map(|server| server.release.version.as_str()),
        Some("1.4.5")
    );
    assert!(matches!(
        after_install.update_of(AcpProvider::Antigravity),
        AcpInstallUpdateState::UpToDate { latest_version, .. } if latest_version == "1.4.5"
    ));

    // Step 2: upstream publishes 1.5.2; check_acp_install_update discovers it
    *state.registry_body.lock().unwrap() = registry_json(
        "1.5.2",
        target,
        &format!("{archive_base_url}agy-1.5.2.zip"),
        cmd,
        &args,
        &sha_152,
    );
    runtime.check_acp_install_update(CheckAcpInstallUpdateRequest {
        operation_id: "check-152".into(),
        provider: AcpProvider::Antigravity,
    })?;
    let after_check = wait_install_snapshot(&runtime, |snapshot| {
        matches!(
            snapshot.update_of(AcpProvider::Antigravity),
            AcpInstallUpdateState::UpdateAvailable { latest, .. } if latest.version == "1.5.2"
        )
    })
    .await?;
    assert_eq!(
        after_check
            .installed_of(AcpProvider::Antigravity)
            .map(|server| server.release.version.as_str()),
        Some("1.4.5")
    );

    // Step 3: one-click upgrade installs 1.5.2 & updates installed/update facts
    runtime.start_acp_install(StartAcpInstallRequest {
        operation_id: "upgrade-152".into(),
        provider: AcpProvider::Antigravity,
    })?;
    let after_upgrade = wait_install_snapshot(&runtime, |snapshot| {
        matches!(
            snapshot.state_of(AcpProvider::Antigravity),
            AcpInstallState::Ready { server, .. } if server.release.version == "1.5.2"
        ) && matches!(
            snapshot.update_of(AcpProvider::Antigravity),
            AcpInstallUpdateState::UpToDate { latest_version, .. } if latest_version == "1.5.2"
        )
    })
    .await?;
    assert_eq!(
        after_upgrade
            .installed_of(AcpProvider::Antigravity)
            .map(|server| server.release.version.as_str()),
        Some("1.5.2")
    );

    // Step 4: background check seeing 2.0.0 surfaces IncompatibleMajor without changing installed 1.5.2
    *state.registry_body.lock().unwrap() = registry_json(
        "2.0.0",
        target,
        &format!("{archive_base_url}agy-1.5.2.zip"),
        cmd,
        &args,
        &sha_152,
    );
    runtime.acp_install.start_background_check(true);
    let after_major = wait_install_snapshot(&runtime, |snapshot| {
        matches!(
            snapshot.update_of(AcpProvider::Antigravity),
            AcpInstallUpdateState::IncompatibleMajor { latest_version, .. } if latest_version == "2.0.0"
        )
    })
    .await?;
    assert_eq!(
        after_major
            .installed_of(AcpProvider::Antigravity)
            .map(|server| server.release.version.as_str()),
        Some("1.5.2")
    );

    runtime.shutdown_runtime().await?;
    server_handle.abort();
    Ok(())
}

#[cfg(target_os = "linux")]
#[tokio::test]
async fn offline_scan_prefers_highest_supported_and_fails_closed_on_corrupt_latest() -> Result<()> {
    let (_home, runtime) = test_runtime().await?;
    seed_synthetic_install_version(&runtime.store, "1.4.5", b"#!/bin/sh\necho 1.4.5\n");
    seed_synthetic_install_version(&runtime.store, "1.5.2", b"#!/bin/sh\necho 1.5.2\n");

    let cancel = CancellationToken::new();
    let verified = prepare::verified_install(
        &runtime.store,
        crate::config::AcpProvider::Antigravity,
        &cancel,
    )
    .await
    .expect("selects highest installed 1.x version");
    assert_eq!(verified.release.version, "1.5.2");

    // Corrupt highest version: must fail closed rather than silently falling back to 1.4.5
    std::fs::write(&verified.program, b"#!/bin/sh\necho tampered\n")?;
    let error = prepare::verified_install(
        &runtime.store,
        crate::config::AcpProvider::Antigravity,
        &cancel,
    )
    .await
    .expect_err("corrupt highest install must fail closed");
    assert_eq!(error, PrepareFailure::InstallationInvalid);

    runtime.shutdown_runtime().await?;
    Ok(())
}

#[tokio::test]
async fn background_check_cancels_and_joins_cleanly_on_shutdown() -> Result<()> {
    let state = MockServerState {
        registry_delay: Arc::new(Mutex::new(Some(Duration::from_secs(30)))),
        ..Default::default()
    };
    let (registry_url, archive_base_url, server_handle) = start_mock_server(state).await?;
    let (_home, runtime) = test_runtime().await?;
    runtime
        .acp_install
        .set_test_source_override(TestSourceOverride {
            registry_url,
            archive_base_url,
        });

    runtime.acp_install.start_background_check(true);
    let _ = wait_install_snapshot(&runtime, |snapshot| {
        matches!(
            snapshot.update_of(AcpProvider::Antigravity),
            AcpInstallUpdateState::Checking { .. }
        )
    })
    .await?;

    tokio::time::timeout(Duration::from_secs(5), runtime.shutdown_runtime())
        .await
        .expect("shutdown cancels in-flight update check promptly")?;
    server_handle.abort();
    Ok(())
}
