//! Controlled external environment for the ACP install acceptance.
//!
//! The peer imitates only what lies outside the product: the fixed Google
//! distribution endpoint (1.4.1, no publisher digest), the TLS/trust boundary and
//! the redirect/rejection surface, reached through the ordinary `HTTPS_PROXY` +
//! isolated `SSL_CERT_FILE` mechanism. It never implements product install logic,
//! never forwards to the real network, and never offers a "skip verification"
//! switch.
//!
//! 生产只按固定清单离线解析，所以这里也不再提供 registry 文档或任何版本、摘要、
//! URL、argv 选择项：peer 只会对“那一份固定发行”给出可控的外部响应。

use std::path::PathBuf;

use anyhow::{Context, Result, ensure};
use sha2::{Digest, Sha256};

mod archive;
mod certs;
mod control;
pub mod fixed;
mod proxy;
mod state;

pub use control::{
    AcpInstallControl, ArchiveControl, ArchiveStep, ArchiveVariant, CONTROL_FILE, RedirectTarget,
};
pub use fixed::{
    AGENT_CONTROL_MEMBER, ARCHIVE_BASE_URL, SERVER_VERSION, archive_url, program_member,
};
pub use proxy::ARCHIVE_PREFIX;
pub use state::{READY_FILE, REPORT_FILE, REQUESTS_FILE};

/// Options for one fixture peer lifecycle.
#[derive(Debug, Clone)]
pub struct AcpInstallFixtureOptions {
    /// Absolute directory holding `control.json` and every evidence file.
    pub state_dir: PathBuf,
}

/// Serves the controlled fixed distribution environment until the harness stops the
/// process or writes the control stop file.
pub async fn run_acp_install_fixture(options: AcpInstallFixtureOptions) -> Result<()> {
    ensure!(
        options.state_dir.is_absolute(),
        "the ACP install fixture state directory must be absolute: {}",
        options.state_dir.display()
    );
    let state_dir = options.state_dir.canonicalize().with_context(|| {
        format!(
            "the ACP install fixture state directory is missing: {}",
            options.state_dir.display()
        )
    })?;
    let control = AcpInstallControl::load(&state_dir.join(CONTROL_FILE))?;
    let target = host_target()?;
    let package = archive::build(&control, &target)?;
    let certificates = certs::generate(&state_dir.join("tls"))?;
    proxy::serve(state_dir, control, target, package, certificates).await
}

/// The host target string the fixed release table uses for this build.
pub fn host_target() -> Result<String> {
    let os = match std::env::consts::OS {
        "linux" => "linux",
        "windows" => "windows",
        other => anyhow::bail!("unsupported fixture platform: {other}"),
    };
    let arch = match std::env::consts::ARCH {
        "x86_64" => "x86_64",
        "aarch64" => "aarch64",
        other => anyhow::bail!("unsupported fixture architecture: {other}"),
    };
    Ok(format!("{os}-{arch}"))
}

/// Lowercase SHA-256 of `bytes`, used by one-shot acceptance evidence.
pub fn sha256_hex(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

/// Lowercase SHA-256 of one file.
pub fn file_sha256(path: &std::path::Path) -> Result<String> {
    let bytes = std::fs::read(path)
        .with_context(|| format!("failed to read a package member: {}", path.display()))?;
    Ok(sha256_hex(&bytes))
}
