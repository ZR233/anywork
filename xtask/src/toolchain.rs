//! Warm-up for the repository's pinned Rust toolchain.
//!
//! `rustc --version` runs from the workspace root so rustup resolves
//! `rust-toolchain.toml` and links (or installs) the pinned toolchain before an
//! engineering command starts any Rust work. The warm-up deliberately owns no
//! version parsing, comparison, component installation or fallback: rustup
//! resolves the directory toolchain, and a failure keeps the original rustc or
//! rustup output and ends the command.

use std::process::Command;

use anyhow::Result;
use pl_dev_support::{paths, process};

use crate::cli::Command as XtaskCommand;

/// Returns whether `command` runs rustc directly or through cargo.
pub(crate) fn required_for(command: &XtaskCommand) -> bool {
    match command {
        XtaskCommand::GenerateGui
        | XtaskCommand::CheckGuiGenerated
        | XtaskCommand::VerifyGui
        | XtaskCommand::ManualGui(_)
        | XtaskCommand::RunGui(_)
        | XtaskCommand::BuildGui(_)
        | XtaskCommand::BuildRemoteHelper(_) => true,
        XtaskCommand::Flutter(_)
        | XtaskCommand::Dart(_)
        | XtaskCommand::VerifyClient
        | XtaskCommand::ReleaseGui { .. } => false,
    }
}

/// Resolves the workspace toolchain through rustup before Rust work starts.
///
/// # Errors
/// Returns an error when `rustc` cannot be started from `PATH` or exits
/// non-zero; the original rustc and rustup output stays above the summary.
pub(crate) fn sync() -> Result<()> {
    let workspace_root = paths::workspace_root()?;
    let mut command = Command::new("rustc");
    command.current_dir(workspace_root).arg("--version");
    process::run_checked(&mut command, "rustc --version")
}
