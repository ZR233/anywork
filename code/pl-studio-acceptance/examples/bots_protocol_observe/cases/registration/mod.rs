//! Optional registration observe cases. Selected alone so each success path
//! owns a private home and peer. Product verdicts stay on public HTTP/SSE.

mod lifecycle;
mod no_user;
mod observe;

use super::Session;
use crate::report::{self, CaseResult};

pub(super) const CASE_LIFECYCLE: &str = "registration-lifecycle";
pub(super) const CASE_NO_USER: &str = "registration-no-user";

pub(super) fn is_exclusive(name: &str) -> bool {
    name == CASE_LIFECYCLE || name == CASE_NO_USER
}

pub(super) async fn run(session: &mut Session, name: &'static str) -> anyhow::Result<CaseResult> {
    match name {
        CASE_LIFECYCLE => lifecycle::run(session).await,
        CASE_NO_USER => no_user::run(session).await,
        other => Ok(report::failed(other, "unknown registration case")),
    }
}

impl Session {
    pub(super) fn remember_marker(&mut self, marker: &str) {
        if !marker.is_empty() && !self.sensitive_markers.iter().any(|item| item == marker) {
            self.sensitive_markers.push(marker.to_owned());
        }
    }
}
