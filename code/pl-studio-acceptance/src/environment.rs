//! Shared isolated environment and report contract for Studio acceptance.
//!
//! Every run owns its data root, workspace, logs, and loopback ports. Fixture,
//! GUI, and helper processes are reclaimed on success, failure, and cancel.
//! Automatic and manual verdicts stay separate fields; a human pending value
//! never becomes an automatic pass.

use anyhow::Result;
use clap::Parser;

use crate::manual_gui;

/// How an acceptance preset is judged.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum PresetKind {
    /// Interactive operator flow. Human verdict stays pending until recorded.
    Manual,
    /// Official Flutter integration_test over the isolated real stack.
    Desktop,
    /// Out-of-process native exit, restart, and platform ownership.
    Native,
}

pub(crate) fn classify(preset: &str) -> PresetKind {
    match preset {
        "wait-events" | "conversation-read-work" => PresetKind::Desktop,
        "shutdown" | "single-instance" => PresetKind::Native,
        _ => PresetKind::Manual,
    }
}

pub(crate) fn run() -> Result<()> {
    let options = manual_gui::ManualGuiOptions::parse();
    let _kind = classify(&options.preset);
    manual_gui::run(options)
}
