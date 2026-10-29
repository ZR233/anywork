//! Real Runtime queries parked after successful reads, before the native method returns.
//! The gate does not suspend SQLite I/O and never substitutes for a content reader.

use std::{
    future::Future,
    path::{Path, PathBuf},
    pin::Pin,
    process::Command,
};

use anyhow::{Context, Result, bail, ensure};
use pl_model::{
    config::{AccountConfig, AccountId, ModelRouteConfig},
    model::{ModelInfo, ModelTransportProfile},
    protocol::ProtocolEndpoint,
};
use pl_protocol::{
    ThreadContentField, ThreadNotification, ThreadSubscriptionRequest, ThreadSubscriptionUpdate,
    ThreadWorkspaceMode, TimelinePageQuery, TurnState,
    studio::{CreateThreadRequest, NewThreadModelRoute, StudioPromptInput},
};
use pl_provider_fixture::{FixtureServer, Protocol, Reply, Step};
use pl_studio_runtime::{
    StudioHostKind, StudioRuntime, StudioRuntimeOptions,
    config::{ConfigPaths, ConfigStore, StudioConfig},
};
use tokio::sync::oneshot;

use super::*;
use crate::api::studio::types::{BridgeContentField, BridgeErrorCode};

const MODEL: &str = "timeline-reader-fixture";
const ACCOUNT: &str = "timeline-reader-fixture";
const PROMPT: &str = "native reader lifecycle";
const INPUT: &str = "input-native-reader-lifecycle";
const BODY: &str = "A real completed answer for native page and Text detail.";

pub(super) struct QueryGate {
    entered: oneshot::Sender<()>,
    release: oneshot::Receiver<()>,
}

impl BridgeTimelineReader {
    // Take the single-use gate without retaining its mutex across the await.
    pub(super) async fn after_query(&self) {
        let gate = self
            .after_query
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .take();
        if let Some(gate) = gate {
            let _ = gate.entered.send(());
            let _ = gate.release.await;
        }
    }
}

fn arm(reader: &BridgeTimelineReader) -> (oneshot::Receiver<()>, oneshot::Sender<()>) {
    let (entered_tx, entered_rx) = oneshot::channel();
    let (release_tx, release_rx) = oneshot::channel();
    *reader.after_query.lock().expect("query gate mutex") = Some(QueryGate {
        entered: entered_tx,
        release: release_rx,
    });
    (entered_rx, release_tx)
}

struct Environment {
    _temp: tempfile::TempDir,
    repo: PathBuf,
    provider: FixtureServer,
    runtime: StudioRuntime,
}

fn git(repo: &Path, args: &[&str]) -> Result<()> {
    let output = Command::new("git")
        .arg("-C")
        .arg(repo)
        .args(args)
        .env("GIT_CONFIG_NOSYSTEM", "1")
        .env("GIT_CONFIG_GLOBAL", "/dev/null")
        .output()?;
    ensure!(
        output.status.success(),
        "fixture git {args:?}: {}",
        String::from_utf8_lossy(&output.stderr)
    );
    Ok(())
}

impl Environment {
    async fn new() -> Result<Self> {
        let temp = tempfile::tempdir()?;
        let home = temp.path().join("home");
        let repo = temp.path().join("repo");
        std::fs::create_dir(&repo)?;
        git(&repo, &["init", "-b", "main"])?;
        git(&repo, &["config", "user.name", "Timeline Reader Test"])?;
        git(&repo, &["config", "user.email", "reader@example.invalid"])?;
        std::fs::write(repo.join("tracked.txt"), "isolated native reader fixture\n")?;
        std::fs::write(repo.join(".gitignore"), ".anywork/\n")?;
        git(&repo, &["add", "."])?;
        git(&repo, &["commit", "-m", "initial"])?;

        let provider = FixtureServer::start(vec![Step::prompt(
            Protocol::ResponsesHttp,
            PROMPT,
            0,
            Reply::Sse(pl_provider_fixture::responses_text(
                BODY,
                "native-reader-answer",
                MODEL,
            )),
        )])
        .await?;
        // Once the listener exists, every fallible setup path explicitly joins it.
        let initialized: Result<StudioRuntime> = async {
            let mut config = StudioConfig::default_config()?;
            config.models.accounts.clear();
            let mut model = ModelInfo::compatible(MODEL);
            model
                .binding
                .set_transport(ModelTransportProfile::responses_http());
            model.capabilities.instruction_snapshot_overrides = true;
            model.base_instructions = "Follow the finite native reader fixture.".into();
            config.models.accounts.insert(
                AccountId::new(ACCOUNT)?,
                AccountConfig::from_explicit_models(
                    ProtocolEndpoint::compatible(ACCOUNT, provider.base_url()),
                    vec![model],
                ),
            );
            let route = ModelRouteConfig {
                account_id: AccountId::new(ACCOUNT)?,
                model_id: MODEL.into(),
                effort: None,
            };
            for selected in config
                .models
                .routes
                .values_mut()
                .chain(config.mode_model_routes.values_mut())
            {
                *selected = route.clone();
            }
            ConfigStore::new(ConfigPaths::from_config_dir(&home)).save(&config)?;
            Ok(Box::pin(StudioRuntime::initialize(StudioRuntimeOptions {
                studio_home: Some(home),
                host: StudioHostKind::Test,
                ..StudioRuntimeOptions::desktop()
            }))
            .await?)
        }
        .await;
        let runtime = match initialized {
            Ok(runtime) => runtime,
            Err(error) => {
                let cleanup = provider.finish().await;
                return Err(error.context(format!(
                    "fixture cleanup after initialization failure: {:?}",
                    cleanup.as_ref().map(|_| ())
                )));
            }
        };
        Ok(Self {
            _temp: temp,
            repo,
            provider,
            runtime,
        })
    }

    async fn content(&self) -> Result<Content> {
        let project = self.runtime.open_project(&self.repo).await?;
        let started = Box::pin(self.runtime.create_thread_command(
            project.id,
            CreateThreadRequest {
                title: Some("Native timeline reader lifecycle".into()),
                input: StudioPromptInput {
                    input_id: INPUT.into(),
                    text: PROMPT.into(),
                    attachment_draft_ids: Vec::new(),
                },
                mode: pl_protocol::ThreadModeId::simple().to_string(),
                route: NewThreadModelRoute {
                    account_id: ACCOUNT.into(),
                    model_id: MODEL.into(),
                    effort: None,
                },
                delegation_mode: Some(pl_protocol::DelegationMode::Profile),
                delegation_preference: None,
                workspace_mode: ThreadWorkspaceMode::Worktree,
            },
            None,
        ))
        .await?;
        let thread_id = started.thread.id;
        let mut subscription = self
            .runtime
            .subscribe_thread(ThreadSubscriptionRequest {
                thread_id: thread_id.clone(),
            })
            .await?;
        loop {
            let update = subscription
                .recv()
                .await?
                .context("fixture stream ended before its completed Turn")?;
            if let ThreadSubscriptionUpdate::Notification { notification } = update
                && let ThreadNotification::TurnCompleted { turn } = notification.notification
                && turn.input_id.as_deref() == Some(INPUT)
            {
                ensure!(
                    matches!(turn.state, TurnState::Completed(_)),
                    "fixture Turn failed instead of completing: {:?}",
                    turn.state
                );
                break;
            }
        }
        drop(subscription);
        // This is the formal projection + durable writer barrier, not a sleep or
        // a terminal-notification assumption about when history becomes saved.
        self.runtime
            .synchronize_thread_observation(&thread_id)
            .await?;
        let reader = self.runtime.timeline_reader(&thread_id).await?;
        let page = reader
            .page(&TimelinePageQuery {
                before: None,
                limit: Some(100),
            })
            .await?;
        ensure!(!page.items.is_empty(), "fixture must have completed atoms");
        ensure!(page.timeline_epoch == reader.epoch());
        ensure!(
            page.items
                .iter()
                .all(|item| item.header.thread_id == thread_id && item.header.append_seq > 0)
        );
        let item_id = page
            .items
            .iter()
            .find(|item| {
                item.fields
                    .iter()
                    .any(|field| field.field == ThreadContentField::Text && field.text == BODY)
            })
            .context("saved history lacks the real fixture answer's Text atom")?
            .header
            .id
            .clone();
        ensure!(
            reader.durable_seq() >= reader.head_seq() && reader.head_seq() > 0,
            "fixture content was not durably saved"
        );
        Ok(Content {
            reader,
            page: timeline_content::page(page),
            item_id,
        })
    }

    async fn finish(self, result: Result<()>) -> Result<()> {
        let shutdown = self.runtime.shutdown_runtime().await;
        let provider = self.provider.finish().await;
        if let Err(error) = result {
            return Err(error.context(format!(
                "cleanup results: runtime={:?}; provider={:?}",
                shutdown.as_ref().map(|_| ()),
                provider.as_ref().map(|_| ())
            )));
        }
        shutdown.context("native reader Runtime shutdown failed")?;
        provider.context("native reader provider script failed")?;
        Ok(())
    }
}

struct Content {
    reader: TimelineContentReader,
    page: BridgeTimelinePage,
    item_id: String,
}

impl Content {
    fn bridge(&self) -> BridgeTimelineReader {
        BridgeTimelineReader {
            thread_id: self.reader.thread_id().into(),
            timeline_epoch: self.reader.epoch(),
            reader: Mutex::new(Some(self.reader.clone())),
            queries: TaskTracker::new(),
            after_query: Mutex::new(None),
        }
    }

    fn detail_query(&self) -> BridgeTimelineDetailQuery {
        BridgeTimelineDetailQuery {
            timeline_epoch: self.page.timeline_epoch.clone(),
            field: BridgeContentField::Text,
            continuation: None,
            max_bytes: Some(4096),
        }
    }

    async fn rejects_queries(&self, bridge: &BridgeTimelineReader) -> Result<()> {
        let page = bridge.page(None, Some(100)).await;
        ensure!(
            matches!(page, Err(ref error) if error.code == BridgeErrorCode::Cancelled),
            "closed page must return typed Cancelled, got {page:?}"
        );
        let detail = bridge
            .read_detail(self.item_id.clone(), self.detail_query())
            .await;
        ensure!(
            matches!(detail, Err(ref error) if error.code == BridgeErrorCode::Cancelled),
            "closed detail must return typed Cancelled, got {detail:?}"
        );
        Ok(())
    }
}

#[derive(Debug, Clone, Copy)]
enum QueryPath {
    Page,
    TextDetail,
}

impl QueryPath {
    async fn run(self, bridge: &BridgeTimelineReader, content: &Content) -> Result<()> {
        match self {
            Self::Page => {
                let page = bridge.page(None, Some(100)).await?;
                ensure!(page == content.page, "native page DTO changed after close");
            }
            Self::TextDetail => {
                let chunk = bridge
                    .read_detail(content.item_id.clone(), content.detail_query())
                    .await?;
                ensure!(chunk.timeline_epoch == content.page.timeline_epoch);
                ensure!(chunk.item_id == content.item_id);
                ensure!(chunk.field == BridgeContentField::Text);
                ensure!(chunk.text == BODY);
                ensure!(chunk.total_bytes == BODY.len() as u64);
                ensure!(chunk.continuation.is_none());
            }
        }
        Ok(())
    }
}

async fn reached(
    query: &mut Pin<Box<impl Future<Output = Result<()>>>>,
    entered: oneshot::Receiver<()>,
) -> Result<()> {
    tokio::select! {
        result = query.as_mut() => {
            result.context("real native query failed before the post-query gate")?;
            bail!("native query returned without waiting at the post-query gate");
        }
        entered = entered => entered.context("native query dropped its entered barrier")?,
    }
    ensure!(
        futures::poll!(query.as_mut()).is_pending(),
        "native method must still be in flight after the real query succeeded"
    );
    Ok(())
}

#[tokio::test]
async fn close_waits_for_real_page_and_text_detail_methods_and_can_be_retried() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let content = env.content().await?;
        for path in [QueryPath::Page, QueryPath::TextDetail] {
            let bridge = content.bridge();
            let (entered, release) = arm(&bridge);
            let mut query = Box::pin(path.run(&bridge, &content));
            reached(&mut query, entered).await?;

            bridge.request_close();
            content.rejects_queries(&bridge).await?;
            let mut first_close = Box::pin(bridge.close());
            ensure!(
                futures::poll!(first_close.as_mut()).is_pending(),
                "{path:?}: close completed before the native method returned"
            );
            drop(first_close);
            let mut retry = Box::pin(bridge.close());
            ensure!(
                futures::poll!(retry.as_mut()).is_pending(),
                "{path:?}: cancelling a close waiter lost its admitted query"
            );
            release
                .send(())
                .map_err(|_| anyhow::anyhow!("{path:?}: admitted method dropped its gate"))?;
            query.await?;
            retry.await;
            bridge.close().await;
            content.rejects_queries(&bridge).await?;
        }
        Ok(())
    }
    .await;
    env.finish(result).await
}

#[tokio::test]
async fn cancelling_real_page_and_text_detail_futures_releases_close() -> Result<()> {
    let env = Environment::new().await?;
    let result = async {
        let content = env.content().await?;
        for path in [QueryPath::Page, QueryPath::TextDetail] {
            let bridge = content.bridge();
            let (entered, release) = arm(&bridge);
            let mut query = Box::pin(path.run(&bridge, &content));
            reached(&mut query, entered).await?;

            bridge.request_close();
            content.rejects_queries(&bridge).await?;
            let mut close = Box::pin(bridge.close());
            ensure!(
                futures::poll!(close.as_mut()).is_pending(),
                "{path:?}: close did not retain the accepted native method"
            );
            // Drop the actual method Future, not a detached task or a hand-held
            // tracker token. Its reader clone and token unwind together.
            drop(query);
            ensure!(
                release.is_closed(),
                "{path:?}: cancelled method retained its post-query receiver"
            );
            ensure!(
                futures::poll!(close.as_mut()).is_ready(),
                "{path:?}: cancelled native method leaked a query into close"
            );
            bridge.close().await;
            content.rejects_queries(&bridge).await?;
        }
        Ok(())
    }
    .await;
    env.finish(result).await
}
