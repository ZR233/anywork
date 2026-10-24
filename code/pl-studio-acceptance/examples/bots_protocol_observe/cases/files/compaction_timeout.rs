//! Forces the real outer case deadline only after a public Studio compact is
//! held in the actual provider. The body is then dropped by the same runner as
//! ordinary cases; its Session-owned runtime/task must still close and join.

use super::super::Session;
use super::{input, requests, wait_idle};
use crate::env;
use anyhow::{Context, Result};
use pl_protocol::studio::{CreateThreadRequest, NewThreadModelRoute};
use pl_provider_fixture::bots_observe as model;
use tokio_util::sync::CancellationToken;

pub(super) async fn run(
    session: &mut Session,
    evidence: &mut Vec<String>,
    ready: &CancellationToken,
) -> Result<String> {
    let project = session
        .http()?
        .open_project(&session.project.to_string_lossy())
        .await?;
    let created = session
        .http()?
        .create_thread(
            &project.id,
            &CreateThreadRequest {
                title: Some("D2 outer timeout lifecycle probe".into()),
                input: input("compact-timeout-seed", model::COMPACT_TIMEOUT),
                mode: pl_protocol::ThreadModeId::SIMPLE.into(),
                route: NewThreadModelRoute {
                    account_id: env::model_account_id(&session.home)?,
                    model_id: "fixture-model".into(),
                    effort: None,
                },
                delegation_mode: None,
                delegation_preference: None,
                workspace_mode: Default::default(),
            },
        )
        .await?;
    let thread_id = created.thread.id;
    requests::wait_executions(session, 1).await?;
    wait_idle(session, &thread_id).await?;
    let mut server = session
        .server
        .take()
        .context("timeout probe server is not running")?;
    let pids = server.pids();
    server.stop()?;
    session.http = None;
    evidence.push(format!("timeout probe HTTP owner stopped/reaped: {pids:?}"));
    session.compaction_owner.initialize(&session.home).await?;
    session
        .compaction_owner
        .runtime()?
        .restore_thread(thread_id.clone())
        .await?;
    session.compaction_owner.spawn_compact(&thread_id)?;
    requests::wait_executions(session, 2).await?;
    evidence.push(format!("real public Studio compact held in provider for thread={thread_id}; outer deadline now armed, not a timing-based assumption"));
    ready.cancel();
    // The strict provider never completes this compact. The outer case
    // deadline drops this future; the only JoinHandle remains in Session.
    std::future::pending::<Result<String>>().await
}
