//! Evidence files written by the ACP install fixture peer.
//!
//! The acceptance harness watches `ready.json` to learn the proxy address and CA
//! path, streams `requests.jsonl` while the lifecycle runs, and reviews
//! `report.json` after a clean stop. Files hold fixture facts only; the harness
//! redacts isolated paths before copying them into its evidence directory.

use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::Path;
use std::sync::Mutex;

use anyhow::{Context, Result};
use serde_json::Value;

/// Written once the peer is listening and the package is ready to serve.
pub const READY_FILE: &str = "ready.json";

/// Append-only request log, one JSON object per line.
pub const REQUESTS_FILE: &str = "requests.jsonl";

/// Written when the peer stops.
pub const REPORT_FILE: &str = "report.json";

pub fn open_requests(state_dir: &Path) -> Result<File> {
    let path = state_dir.join(REQUESTS_FILE);
    OpenOptions::new()
        .create(true)
        .write(true)
        .truncate(true)
        .open(&path)
        .with_context(|| {
            format!(
                "failed to create the fixture request log: {}",
                path.display()
            )
        })
}

/// Appends one request record and reports every failure.
///
/// 记录是验收证据的一部分：锁中毒、序列化失败、写失败、flush 失败都必须让调用方
/// 知道，不能静默丢行——否则“没有旧 registry 请求”这类结论会被丢失的记录假绿。
pub fn append_request(log: &Mutex<File>, value: &Value) -> Result<()> {
    let mut file = log
        .lock()
        .map_err(|_| anyhow::anyhow!("the fixture request log lock is poisoned"))?;
    let mut line =
        serde_json::to_vec(value).context("failed to encode one fixture request record")?;
    line.push(b'\n');
    file.write_all(&line)
        .context("failed to append one fixture request record")?;
    file.flush()
        .context("failed to flush the fixture request log")?;
    Ok(())
}

pub fn write_ready(state_dir: &Path, value: &Value) -> Result<()> {
    write_json(&state_dir.join(READY_FILE), value)
}

pub fn write_report(state_dir: &Path, value: &Value) -> Result<()> {
    write_json(&state_dir.join(REPORT_FILE), value)
}

fn write_json(path: &Path, value: &Value) -> Result<()> {
    let bytes = serde_json::to_vec_pretty(value)?;
    let temporary = path.with_extension("json.tmp");
    fs::write(&temporary, &bytes)
        .with_context(|| format!("failed to write the fixture evidence: {}", path.display()))?;
    fs::rename(&temporary, path)
        .with_context(|| format!("failed to publish the fixture evidence: {}", path.display()))
}
