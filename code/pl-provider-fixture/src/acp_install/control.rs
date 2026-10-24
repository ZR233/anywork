//! Control surface for the ACP install fixture peer.
//!
//! The acceptance harness writes one `control.json` per lifecycle into the fixture
//! state directory. Nothing here is read by production code: the peer only decides
//! which *external* response (TLS boundary, redirect, archive body shape) an
//! official HTTPS request receives, and which synthetic control the packaged
//! fixture agent finds inside its own package.
//!
//! 产品只认一条固定的 1.4.1 发行：这里没有版本、摘要、URL、argv 之类的可选项，
//! 因为那些事实属于产品代码，测试没有权限改写它们。

use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

/// Control document name inside the fixture state directory.
pub const CONTROL_FILE: &str = "control.json";

/// One acceptance lifecycle's external environment.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct AcpInstallControl {
    pub archive: ArchiveControl,
    /// When this file appears the peer stops serving and writes its report.
    #[serde(default)]
    pub stop_file: Option<PathBuf>,
}

impl AcpInstallControl {
    pub fn load(path: &Path) -> Result<Self> {
        let bytes = fs::read(path)
            .with_context(|| format!("failed to read ACP install control: {}", path.display()))?;
        serde_json::from_slice(&bytes)
            .with_context(|| format!("invalid ACP install control: {}", path.display()))
    }
}

/// Where a redirect from the fixed archive URL points.
///
/// The product validates every hop against the fixed official source policy, so
/// these samples prove the rejection still happens after the registry document
/// disappeared.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum RedirectTarget {
    /// Another path on the same official distribution host and prefix.
    AllowedPath,
    /// A different host, which the source policy must reject.
    ForeignHost,
    /// Plain HTTP on the official host, which the source policy must reject.
    PlainHttp,
    /// A redirect back to the same URL, which must stop at the hop budget.
    Loop,
}

/// Package shape served for the archive request.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ArchiveVariant {
    /// Real program plus a real auxiliary member and the synthetic agent control.
    Normal,
    Traversal,
    AbsolutePath,
    Backslash,
    /// NTFS alternate data stream spelling.
    Ads,
    Symlink,
    Duplicate,
    CaseCollision,
    /// The fixed entry names a member the package does not contain.
    MissingExecutable,
    /// The program member exists but carries no executable bit.
    ProgramNotExecutable,
    /// Bytes cut inside the archive.
    Truncated,
    /// Program payload corrupted after CRC computation.
    CorruptCrc,
    /// Central directory declares an expanded member above the per-file budget.
    TooLargeDeclared,
    /// More members than the package budget allows.
    TooManyMembers,
    /// Valid ZIP64 extra fields (the per-file switch forces zip64 metadata).
    Zip64,
    /// Valid ZIP64 entries written with data descriptors (sizes after the data).
    Zip64DataDescriptor,
    /// STORED member whose trailing data descriptor carries zero CRC/sizes while
    /// the central directory and the payload stay intact: an accepted sample for
    /// the policy where only the duplicated descriptor fields are not re-compared.
    DataDescriptorZero,
    /// STORED member whose bit-3 local header carries non-zero, wrong sizes while
    /// the trailing data descriptor matches the central directory.
    DataDescriptorLocalNonZero,
    /// STORED member whose general-purpose flags carry a bit outside the supported
    /// allowlist (patched-data, bit 5).
    UnknownFlags,
    /// Many implicit parent directories with few members: the directory budget
    /// must reject it before anything is published.
    ImplicitDirectories,
    /// Valid package that also ships a genuinely empty member (local header,
    /// descriptor and central directory all carry real zeros).
    EmptyMember,
    /// Central directory declares a different expanded size than the data.
    SizeMismatch,
    /// ZipCrypto-encrypted member produced by the standard `zip` tool.
    Encrypted,
}

/// Archive endpoint behaviour for one lifecycle.
#[derive(Debug, Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArchiveControl {
    pub variant: ArchiveVariant,
    /// Absolute path of a real executable packaged as the official server.
    pub program: PathBuf,
    /// Absolute path of a real auxiliary file kept in the package.
    pub auxiliary: PathBuf,
    /// Absolute synthetic state directory the packaged fixture agent is told to
    /// use through its in-package `agent-control.json` member.
    ///
    /// It must live outside the installed tree: the agent writes its own
    /// behaviour, markers and evidence there, and the product verifies the
    /// installed tree against its receipt.
    pub agent_state_dir: PathBuf,
    /// Body chunk size; `None` sends the whole body at once.
    #[serde(default)]
    pub chunk_bytes: Option<usize>,
    /// Delay between body chunks.
    #[serde(default)]
    pub chunk_delay_ms: u64,
    /// Answer without `Content-Length` (chunked transfer).
    #[serde(default)]
    pub unknown_length: bool,
    /// Abort the body after this many bytes on affected requests.
    #[serde(default)]
    pub drop_after_bytes: Option<u64>,
    /// How many archive requests abort their body.
    #[serde(default)]
    pub drop_requests: u32,
    /// How many archive requests fail with HTTP 503 before bytes are served.
    #[serde(default)]
    pub fail_requests: u32,
    /// Redirects issued before the archive body is served.
    #[serde(default)]
    pub redirects: u32,
    /// Where those redirects point; `None` keeps the same-host allowed path.
    #[serde(default)]
    pub redirect_target: Option<RedirectTarget>,
    /// Validator every archive response carries unless a script step overrides it.
    #[serde(default)]
    pub etag: Option<String>,
    /// Scripted responses consumed in request order; afterwards the default
    /// behaviour applies. Empty keeps the historical single-validator behaviour.
    #[serde(default)]
    pub script: Vec<ArchiveStep>,
}

/// One scripted archive response.
///
/// The peer may deliberately change the validator between requests — a real hazard
/// a resumable downloader must survive — and abort the body after a fixed number of
/// bytes. Status codes are still derived from the real request (Range/If-Range).
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ArchiveStep {
    /// Validator this response carries instead of the run validator.
    #[serde(default)]
    pub etag: Option<String>,
    /// Abort this response's body after this many bytes.
    #[serde(default)]
    pub drop_after_bytes: Option<u64>,
}
