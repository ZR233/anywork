//! Scenario-owned background command peer for one normal native shutdown.
//! Records its real process identity; descendant cleanup is judged by the native launcher.

use anyhow::{Context, Result};
use serde_json::json;
use std::fs;
use std::path::{Path, PathBuf};

use crate::stdio_peer::proc_start_ticks;

/// Options for [`run_tool_peer`].
pub struct ToolPeerOptions {
    /// File receiving the peer process identity.
    pub coord_file: PathBuf,
}

/// Runs the scenario-owned background tool until the product kills the subtree.
pub fn run_tool_peer(options: ToolPeerOptions) -> Result<()> {
    let tool_pid = std::process::id();
    write_coord_record(&options.coord_file, tool_pid)?;
    // Keep a real background command alive until coordinated shutdown.
    println!("shutdown tool peer running (pid {tool_pid})");
    loop {
        std::thread::sleep(std::time::Duration::from_secs(3600));
    }
}

/// Records the peer identity with a pid-reuse guard.
fn write_coord_record(coord_file: &Path, tool_pid: u32) -> Result<()> {
    let record = json!({
        "schema": "anywork-tool-peer/1",
        "toolPid": tool_pid,
        "toolStartTicks": proc_start_ticks(tool_pid),
    });
    if let Some(parent) = coord_file.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    let mut temporary = tempfile::NamedTempFile::new_in(
        coord_file
            .parent()
            .filter(|parent| !parent.as_os_str().is_empty())
            .unwrap_or_else(|| Path::new(".")),
    )?;
    serde_json::to_writer_pretty(&mut temporary, &record)?;
    temporary.persist(coord_file).map_err(|error| error.error)?;
    Ok(())
}
