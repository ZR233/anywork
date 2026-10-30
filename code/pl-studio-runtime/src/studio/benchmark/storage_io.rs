//! Linux storage-layer accounting, separate from Criterion's operation timer.
//! This measures the isolated benchmark process, not the whole block device.

use std::time::Duration;

use anyhow::{Context, Result, ensure};

#[derive(Debug, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StorageIo {
    pub read_bytes: u64,
    pub write_bytes: u64,
    pub cancelled_write_bytes: u64,
    pub elapsed_nanos: u64,
}

pub(super) struct IoSnapshot {
    read_bytes: u64,
    write_bytes: u64,
    cancelled_write_bytes: u64,
}

impl IoSnapshot {
    pub(super) fn read() -> Result<Option<Self>> {
        #[cfg(target_os = "linux")]
        {
            let text = std::fs::read_to_string("/proc/self/io")
                .context("read Linux benchmark storage I/O accounting")?;
            let field = |name: &str| -> Result<u64> {
                let value = text
                    .lines()
                    .filter_map(|line| line.split_once(':'))
                    .find_map(|(key, value)| (key == name).then_some(value.trim()))
                    .with_context(|| format!("missing Linux I/O counter {name}"))?;
                value
                    .parse()
                    .with_context(|| format!("parse Linux I/O counter {name}"))
            };
            Ok(Some(Self {
                read_bytes: field("read_bytes")?,
                write_bytes: field("write_bytes")?,
                cancelled_write_bytes: field("cancelled_write_bytes")?,
            }))
        }
        #[cfg(not(target_os = "linux"))]
        {
            Ok(None)
        }
    }
}

pub(super) fn measure(
    before: Option<IoSnapshot>,
    after: Option<IoSnapshot>,
    elapsed: Duration,
) -> Result<Option<StorageIo>> {
    let (Some(before), Some(after)) = (before, after) else {
        ensure!(!cfg!(target_os = "linux"), "Linux I/O observation missing");
        return Ok(None);
    };
    let delta = |after: u64, before: u64| {
        after
            .checked_sub(before)
            .context("Linux I/O counter moved backwards")
    };
    Ok(Some(StorageIo {
        read_bytes: delta(after.read_bytes, before.read_bytes)?,
        write_bytes: delta(after.write_bytes, before.write_bytes)?,
        cancelled_write_bytes: delta(after.cancelled_write_bytes, before.cancelled_write_bytes)?,
        elapsed_nanos: u64::try_from(elapsed.as_nanos())
            .context("benchmark I/O observation interval exceeds u64 nanoseconds")?,
    }))
}
