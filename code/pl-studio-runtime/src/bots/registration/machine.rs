//! Pure registration state. The worker supplies time, IDs and protocol outcomes.
use crate::{BotRegistrationAttempt, BotRegistrationStatus};
use std::time::Instant;

pub(super) struct RegistrationStateMachine {
    pub(super) attempt_id: String,
    pub(super) operation_id: String,
    pub(super) name: String,
    pub(super) workspace_id: String,
    device_code: String,
    verification_url: String,
    expires_at: i64,
    pub(super) deadline: Instant,
    pub(super) interval_seconds: u32,
    pub(super) status: BotRegistrationStatus,
    completed_bot_id: Option<String>,
    pub(super) commit_claimed: bool,
}

pub(super) enum RegistrationFinish {
    Denied {
        message: String,
    },
    Expired,
    Failed {
        code: String,
        message: String,
        retryable: bool,
    },
}

impl RegistrationStateMachine {
    pub(super) fn snapshot(&self) -> BotRegistrationAttempt {
        BotRegistrationAttempt {
            attempt_id: self.attempt_id.clone(),
            name: self.name.clone(),
            workspace_id: self.workspace_id.clone(),
            status: self.status.clone(),
            completed_bot_id: self.completed_bot_id.clone(),
        }
    }

    fn clear_authorization_material(&mut self) {
        self.device_code.clear();
        self.verification_url.clear();
        if let BotRegistrationStatus::Waiting {
            verification_url, ..
        }
        | BotRegistrationStatus::SlowDown {
            verification_url, ..
        } = &mut self.status
        {
            verification_url.clear();
        }
    }

    pub(super) fn matches_request(
        &self,
        operation_id: &str,
        name: &str,
        workspace_id: &str,
    ) -> bool {
        self.operation_id == operation_id && self.name == name && self.workspace_id == workspace_id
    }

    pub(super) fn is_terminal(&self) -> bool {
        matches!(
            self.status,
            BotRegistrationStatus::Completed { .. }
                | BotRegistrationStatus::Denied { .. }
                | BotRegistrationStatus::Expired { .. }
                | BotRegistrationStatus::Cancelled { .. }
                | BotRegistrationStatus::Failed { .. }
        )
    }

    pub(super) fn is_committing(&self) -> bool {
        self.commit_claimed && matches!(self.status, BotRegistrationStatus::Committing { .. })
    }
    pub(super) fn new(
        attempt_id: String,
        operation_id: String,
        name: String,
        workspace_id: String,
        now: Instant,
    ) -> Self {
        Self {
            status: BotRegistrationStatus::Preparing {
                attempt_id: attempt_id.clone(),
            },
            attempt_id,
            operation_id,
            name,
            workspace_id,
            device_code: String::new(),
            verification_url: String::new(),
            expires_at: 0,
            deadline: now,
            interval_seconds: 5,
            completed_bot_id: None,
            commit_claimed: false,
        }
    }

    pub(super) fn cancel(&mut self) {
        self.clear_authorization_material();
        self.status = BotRegistrationStatus::Cancelled {
            attempt_id: self.attempt_id.clone(),
        };
    }

    pub(super) fn wait_for_scan(
        &mut self,
        device_code: String,
        verification_url: String,
        deadline: Instant,
        expires_at: i64,
        interval_seconds: u32,
    ) {
        self.device_code = device_code;
        self.verification_url = verification_url;
        self.deadline = deadline;
        self.expires_at = expires_at;
        self.interval_seconds = interval_seconds.max(1);
        self.refresh_waiting(false, None);
    }

    /// Return whether polling may continue after applying the platform input.
    pub(super) fn refresh_waiting(&mut self, slow_down: bool, now: Option<(Instant, i64)>) -> bool {
        if now.is_some_and(|(clock, unix)| self.expired(clock, unix)) {
            self.expire();
            return false;
        }
        if slow_down {
            self.interval_seconds = self.interval_seconds.saturating_add(5).max(1);
            self.status = BotRegistrationStatus::SlowDown {
                attempt_id: self.attempt_id.clone(),
                verification_url: self.verification_url.clone(),
                expires_at: self.expires_at,
                interval_seconds: self.interval_seconds,
            };
        } else {
            self.status = BotRegistrationStatus::Waiting {
                attempt_id: self.attempt_id.clone(),
                verification_url: self.verification_url.clone(),
                expires_at: self.expires_at,
                interval_seconds: self.interval_seconds,
            };
        }
        true
    }

    pub(super) fn expired(&self, now: Instant, unix: i64) -> bool {
        now >= self.deadline || unix >= self.expires_at
    }

    pub(super) fn expire(&mut self) {
        self.clear_authorization_material();
        self.status = BotRegistrationStatus::Expired {
            attempt_id: self.attempt_id.clone(),
        };
    }

    pub(super) fn claim_commit(&mut self, bot_id: String) {
        self.commit_claimed = true;
        self.clear_authorization_material();
        self.completed_bot_id = None;
        self.status = BotRegistrationStatus::Committing {
            attempt_id: self.attempt_id.clone(),
            bot_id,
        };
    }

    pub(super) fn complete(&mut self, bot_id: String) {
        self.clear_authorization_material();
        self.completed_bot_id = Some(bot_id);
        self.status = BotRegistrationStatus::Completed {
            attempt_id: self.attempt_id.clone(),
        };
    }

    pub(super) fn finish(&mut self, finish: RegistrationFinish) {
        self.clear_authorization_material();
        let attempt_id = self.attempt_id.clone();
        self.status = match finish {
            RegistrationFinish::Denied { message } => BotRegistrationStatus::Denied {
                attempt_id,
                message,
            },
            RegistrationFinish::Expired => BotRegistrationStatus::Expired { attempt_id },
            RegistrationFinish::Failed {
                code,
                message,
                retryable,
            } => BotRegistrationStatus::Failed {
                attempt_id,
                code,
                message,
                retryable,
            },
        };
    }
}
