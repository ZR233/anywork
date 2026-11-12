//! Product task transitions over independent root and capture completions.
use super::{CommandProcessState, HeadTailBuffer, INTERNAL_BUFFER_BYTES, StreamKind};
pub use pl_tool_command::process::state::*;

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) enum CommandProcessTransition {
    TimeOut,
    Cancel,
    /// The durable output capture could not continue; terminate the operation but keep its bytes.
    OutputFailed {
        failure: CommandCaptureFailure,
    },
    ProcessExited {
        exit_code: Option<i32>,
    },
    ProcessWaitFailed {
        error: String,
    },
    StreamClosed(StreamKind),
}

impl CommandProcessState {
    /// Freeze output budgets; target capture is not known before its completion.
    pub(super) fn new(
        stdout_open: bool,
        stderr_open: bool,
        capture_limit_bytes: u64,
        model_output_bytes_cap: Option<u64>,
    ) -> Self {
        Self {
            lifecycle: CommandProcessLifecycle::Running(RunningCommandProcess::healthy()),
            stdout_open,
            stderr_open,
            stdout: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            stderr: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            pending_stdout: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            pending_stderr: HeadTailBuffer::new(INTERNAL_BUFFER_BYTES),
            output_revision: 0,
            exit: None,
            capture_limit_bytes,
            capture_result: None,
            capture_completion_observed: false,
            model_output_bytes_cap,
            output_failure: None,
        }
    }

    pub(super) fn can_accept_input(&self) -> bool {
        self.lifecycle.can_accept_input()
    }

    pub(super) fn record_output(&mut self, stream: StreamKind, chunk: &[u8]) -> u64 {
        self.output_revision = self.output_revision.saturating_add(1);
        match stream {
            StreamKind::Stdout => {
                self.stdout.push_chunk(chunk);
                self.pending_stdout.push_chunk(chunk);
            }
            StreamKind::Stderr => {
                self.stderr.push_chunk(chunk);
                self.pending_stderr.push_chunk(chunk);
            }
        }
        self.output_revision
    }

    pub(super) fn observe_capture(&mut self, capture: pl_remote_helper::CaptureResult) {
        use crate::command::{
            CommandCaptureIoError, CommandCaptureResult, CommandCaptureState, CommandCapturedStream,
        };
        let convert = |stream: pl_remote_helper::CapturedStream| CommandCapturedStream {
            state: match stream.state {
                pl_remote_helper::CaptureState::Complete => CommandCaptureState::Complete,
                pl_remote_helper::CaptureState::LimitExceeded => CommandCaptureState::LimitExceeded,
                pl_remote_helper::CaptureState::IoFailed => CommandCaptureState::IoFailed,
                pl_remote_helper::CaptureState::Incomplete => CommandCaptureState::Incomplete,
            },
            confirmed_bytes: stream.confirmed_bytes,
            error: stream.error.map(|error| CommandCaptureIoError {
                kind: error.kind(),
                raw_os_error: error.raw_os_error(),
            }),
        };
        let capture = CommandCaptureResult {
            stdout: convert(capture.stdout),
            stderr: convert(capture.stderr),
        };
        if capture.stdout.state == CommandCaptureState::LimitExceeded
            || capture.stderr.state == CommandCaptureState::LimitExceeded
        {
            self.record_capture_failure(CommandCaptureFailure::OutputLimitExceeded {
                limit_bytes: self.capture_limit_bytes,
                charged_bytes: capture.confirmed_total(),
                refused_bytes: None,
            });
        } else if !capture.complete() {
            self.record_capture_failure(CommandCaptureFailure::Read {
                message: format!(
                    "capture incomplete: {:?}/{:?}",
                    capture.stdout.state, capture.stderr.state
                ),
            });
        }
        self.capture_result = Some(capture);
        self.capture_completion_observed = true;
        self.promote_drained_final();
    }
    pub(super) fn model_output_bytes_cap(&self) -> Option<u64> {
        self.model_output_bytes_cap
    }

    /// Records the reason the durable capture could not continue, before the process is terminated.
    ///
    /// It sets the health so a process that exits on its own still reports the typed output failure,
    /// and it keeps the *first* category/reason: a second reader that reaches the boundary after the
    /// first failure only terminates the same way and must not overwrite what ended the operation. The
    /// accepted chunks neither reader stored stay accumulated in the one capture plan instead of
    /// replacing one another.
    pub(super) fn record_capture_failure(&mut self, failure: CommandCaptureFailure) {
        if self.output_failure.is_none() {
            self.output_failure = Some(failure);
        }
        if let Some(first) = &self.output_failure {
            let message = first.message();
            if let CommandProcessLifecycle::Draining(state) = &self.lifecycle
                && matches!(
                    state.result(),
                    CommandProcessFinalResult::Succeeded { .. }
                        | CommandProcessFinalResult::Failed {
                            failure: CommandProcessFailure::Exited { .. }
                        }
                )
            {
                self.lifecycle = CommandProcessLifecycle::Draining(DrainingCommandProcess::new(
                    CommandProcessFinalResult::Failed {
                        failure: CommandProcessFailure::Output {
                            message: message.clone(),
                            exit_code: self.exit.as_ref().and_then(|exit| exit.exit_code),
                        },
                    },
                ));
            }
            self.record_output_error(message);
        }
    }

    pub(super) fn record_output_error(&mut self, error: String) {
        match &mut self.lifecycle {
            CommandProcessLifecycle::Running(state) => state.record_output_error(error),
            CommandProcessLifecycle::Draining(state) => state.record_output_error(error),
            CommandProcessLifecycle::Final(state) => state.record_output_error(error),
            CommandProcessLifecycle::Terminating(_) => {}
        }
    }

    pub(super) fn is_final(&self) -> bool {
        self.lifecycle.is_final()
    }

    pub(super) fn apply_transition(&mut self, transition: CommandProcessTransition) {
        match transition {
            CommandProcessTransition::TimeOut
                if matches!(self.lifecycle, CommandProcessLifecycle::Draining(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Draining(DrainingCommandProcess::new(
                    CommandProcessFinalResult::TimedOut,
                ));
            }
            CommandProcessTransition::Cancel
                if matches!(self.lifecycle, CommandProcessLifecycle::Draining(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Draining(DrainingCommandProcess::new(
                    CommandProcessFinalResult::Cancelled,
                ));
            }
            CommandProcessTransition::TimeOut
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::TimedOut),
                );
            }
            CommandProcessTransition::Cancel
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::Cancelled),
                );
            }
            CommandProcessTransition::OutputFailed { failure }
                if matches!(self.lifecycle, CommandProcessLifecycle::Running(_)) =>
            {
                // The first failure already named the reason; a later one only terminates the same
                // way. Keep it so the reported category and reason never regress.
                if self.output_failure.is_none() {
                    self.output_failure = Some(failure);
                }
                self.lifecycle = CommandProcessLifecycle::Terminating(
                    TerminatingCommandProcess::new(CommandTerminationReason::OutputFailed),
                );
            }
            CommandProcessTransition::ProcessExited { exit_code } => {
                let result = match &self.lifecycle {
                    CommandProcessLifecycle::Terminating(state) => match state.reason() {
                        CommandTerminationReason::TimedOut => CommandProcessFinalResult::TimedOut,
                        CommandTerminationReason::Cancelled => CommandProcessFinalResult::Cancelled,
                        CommandTerminationReason::OutputFailed => {
                            CommandProcessFinalResult::Failed {
                                failure: CommandProcessFailure::Output {
                                    message: self.output_failure.as_ref().map_or_else(
                                        || "command output could not be captured".to_string(),
                                        CommandCaptureFailure::message,
                                    ),
                                    exit_code,
                                },
                            }
                        }
                    },
                    CommandProcessLifecycle::Running(state) => match state.health() {
                        CommandProcessHealth::Healthy if exit_code == Some(0) => {
                            CommandProcessFinalResult::Succeeded { exit_code: 0 }
                        }
                        CommandProcessHealth::Healthy => CommandProcessFinalResult::Failed {
                            failure: CommandProcessFailure::Exited { exit_code },
                        },
                        CommandProcessHealth::OutputFailed { message } => {
                            CommandProcessFinalResult::Failed {
                                failure: CommandProcessFailure::Output {
                                    message: message.clone(),
                                    exit_code,
                                },
                            }
                        }
                    },
                    CommandProcessLifecycle::Draining(_) | CommandProcessLifecycle::Final(_) => {
                        return;
                    }
                };
                self.finish_or_drain(result);
            }
            CommandProcessTransition::ProcessWaitFailed { error } => {
                let result = match &self.lifecycle {
                    CommandProcessLifecycle::Terminating(_)
                    | CommandProcessLifecycle::Running(_) => CommandProcessFinalResult::Failed {
                        failure: CommandProcessFailure::Wait { message: error },
                    },
                    CommandProcessLifecycle::Draining(_) | CommandProcessLifecycle::Final(_) => {
                        return;
                    }
                };
                self.finish_or_drain(result);
            }
            CommandProcessTransition::StreamClosed(stream) => {
                match stream {
                    StreamKind::Stdout => {
                        self.stdout_open = false;
                        self.stdout.finish_text();
                    }
                    StreamKind::Stderr => {
                        self.stderr_open = false;
                        self.stderr.finish_text();
                    }
                }
                // Root exit, preview EOF and capture completion must all have been observed.
                if self.capture_completion_observed
                    && self.output_streams_closed()
                    && let CommandProcessLifecycle::Draining(state) = &self.lifecycle
                {
                    self.lifecycle = CommandProcessLifecycle::Final(FinalCommandProcess::new(
                        state.result().clone(),
                    ));
                }
            }
            CommandProcessTransition::TimeOut
            | CommandProcessTransition::Cancel
            | CommandProcessTransition::OutputFailed { .. } => {}
        }
    }

    fn finish_or_drain(&mut self, result: CommandProcessFinalResult) {
        // Root exit remains visible while the target capture and preview streams settle.
        self.lifecycle = if self.capture_completion_observed && self.output_streams_closed() {
            CommandProcessLifecycle::Final(FinalCommandProcess::new(result))
        } else {
            CommandProcessLifecycle::Draining(DrainingCommandProcess::new(result))
        };
    }

    /// Publish a final product task only after both output observations settle.
    pub(super) fn promote_drained_final(&mut self) {
        if !(self.capture_completion_observed && self.output_streams_closed()) {
            return;
        }
        let result = match &self.lifecycle {
            CommandProcessLifecycle::Draining(state) => state.result().clone(),
            CommandProcessLifecycle::Running(_)
            | CommandProcessLifecycle::Terminating(_)
            | CommandProcessLifecycle::Final(_) => return,
        };
        self.lifecycle = CommandProcessLifecycle::Final(FinalCommandProcess::new(result));
    }

    pub(super) fn output_streams_closed(&self) -> bool {
        !self.stdout_open && !self.stderr_open
    }
}
