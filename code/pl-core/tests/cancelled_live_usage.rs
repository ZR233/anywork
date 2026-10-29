//! Public-API coverage of the live measurement a stopped attempt may publish.
//!
//! A cancelled or interrupted attempt produces no speed sample. These cases drive the real mailbox
//! cancellation entry points against a model that is parked mid-call, so the immediate snapshot and
//! the later in-flight watch updates are both observed while the attempt is still resident: the live
//! pair must already be unavailable while the partial body stays visible.

use std::sync::Arc;
use std::time::Duration;

use pl_core::context::ContextContent;
use pl_core::model::{
    DynModelSession, Model, ModelError, ModelFactory, ModelFailureKind, ModelRequest, ModelSession,
    ModelTextChannel, ModelUsage, ObservedItemKind, ObservedPart, ObservedPartIdentity,
    ObservedPartKind, PreparedModelCall, ProviderPartIdentity,
};
use pl_core::thread::{ModelStepLimit, ThreadError, ThreadHandle, ThreadSnapshot, TurnInput};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

fn turn(cancellation: CancellationToken) -> TurnInput {
    TurnInput {
        turn_id: "live-turn".into(),
        attempt_prefix: "live-attempt".into(),
        content: vec![ContextContent::Text {
            text: Arc::from("stop this live attempt"),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into().expect("one step is a valid limit")),
        cancellation,
    }
}

fn partial_part() -> ObservedPart {
    ObservedPart::new(ObservedPartIdentity::Provider(ProviderPartIdentity {
        item_id: Arc::from("message-1"),
        output_index: Some(0),
        item_kind: ObservedItemKind::Text(ModelTextChannel::Final),
        part: ObservedPartKind::OutputText,
        content_index: 0,
    }))
    .authorized("partial body")
}

/// Whether a snapshot presents a usable output/decode pair for this live channel.
fn has_live_pair(snapshot: &ThreadSnapshot) -> bool {
    snapshot
        .model_progress
        .as_ref()
        .and_then(|active| active.progress.usage_observation())
        .is_some_and(|usage| usage.completion_tokens.is_some() && usage.response_millis.is_some())
}

fn live_usage(snapshot: &ThreadSnapshot) -> Option<pl_core::model::ModelUsageObservation> {
    snapshot
        .model_progress
        .as_ref()
        .and_then(|active| active.progress.usage_observation())
        .cloned()
}

#[derive(Debug, Clone)]
enum Stop {
    CancelRunningTurn,
    InterruptTurn,
    /// 直接取消 Turn 输入自带的代次 token：不经过 mailbox，也不记录 interrupted Turn。
    TurnToken {
        cancellation: CancellationToken,
    },
    /// 直接取消 Thread 当前 active 代次：同样不经过 mailbox。
    ThreadInterrupt,
}

impl Stop {
    /// The token the Turn must be submitted with, so the stop can hit the real generation.
    fn cancellation(&self) -> CancellationToken {
        match self {
            Self::TurnToken { cancellation } => cancellation.clone(),
            Self::CancelRunningTurn | Self::InterruptTurn | Self::ThreadInterrupt => {
                CancellationToken::new()
            }
        }
    }

    async fn apply(&self, thread: &ThreadHandle) {
        match self {
            Self::CancelRunningTurn => {
                thread
                    .cancel_running_turn("live-turn".into())
                    .await
                    .expect("the running turn accepts cancellation");
            }
            Self::InterruptTurn => {
                thread
                    .interrupt_turn(None)
                    .await
                    .expect("the running turn accepts interruption");
            }
            Self::TurnToken { cancellation } => cancellation.cancel(),
            Self::ThreadInterrupt => {
                assert!(
                    thread.interrupt(),
                    "a resident generation is the target of a direct interrupt"
                );
            }
        }
    }

    fn label(&self) -> &'static str {
        match self {
            Self::CancelRunningTurn => "cancel",
            Self::InterruptTurn => "interrupt",
            Self::TurnToken { .. } => "turn token",
            Self::ThreadInterrupt => "thread interrupt",
        }
    }
}

/// Signals letting the test hold the model call open on both sides of the cancellation.
#[derive(Default)]
struct Barriers {
    seeded: Arc<Notify>,
    released: Arc<Notify>,
    republished: Arc<Notify>,
    finished: Arc<Notify>,
}

struct HangingLiveModel {
    barriers: Arc<Barriers>,
}

impl Model for HangingLiveModel {
    async fn open_session(&self) -> Result<DynModelSession, ModelError> {
        Ok(DynModelSession::new(HangingLiveSession {
            barriers: self.barriers.clone(),
        }))
    }
}

/// A session that publishes one live pair, parks, republishes after the test releases it, and only
/// then returns a cancelled failure. It never observes the cancellation token itself, so the test
/// owns the window in which snapshots are published.
struct HangingLiveSession {
    barriers: Arc<Barriers>,
}

impl ModelSession for HangingLiveSession {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let progress = request
            .progress
            .clone()
            .expect("core attaches a live observation channel");
        let seeded = self.barriers.seeded.clone();
        let released = self.barriers.released.clone();
        let republished = self.barriers.republished.clone();
        let finished = self.barriers.finished.clone();
        let call = PreparedModelCall::new(async move {
            progress.edit_parts(|parts| parts.push(partial_part()));
            progress.observe_usage(Some(8), Some(120));
            progress.observe_response_millis(1_500);
            seeded.notify_one();
            released.notified().await;
            // 取消之后仍然到达的在途观察：它们不得把已停止代次的 pair 复活。
            progress.observe_usage(Some(9), Some(140));
            progress.observe_response_millis(1_800);
            republished.notify_one();
            finished.notified().await;
            Err(ModelError {
                details: None,
                kind: ModelFailureKind::Cancelled,
                usage: Box::new(ModelUsage {
                    output_tokens: Some(9),
                    ..Default::default()
                }),
                source: None,
            })
        });
        Ok(call)
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

/// Reads the snapshot the Thread would hand a new subscriber right now.
async fn current_snapshot(thread: &ThreadHandle) -> ThreadSnapshot {
    let mut subscription = thread.subscribe();
    tokio::time::timeout(Duration::from_secs(10), subscription.next())
        .await
        .expect("the Thread publishes a snapshot")
        .expect("the Thread stays open")
}

async fn stopped_attempt_never_publishes_a_live_pair(stop: Stop) {
    let barriers = Arc::new(Barriers::default());
    let model = HangingLiveModel {
        barriers: barriers.clone(),
    };
    let session = ModelFactory::new(model)
        .open_session()
        .await
        .expect("model session opens");
    let thread = ThreadHandle::start("live-thread".into(), session).expect("thread starts");
    let mut subscription = thread.subscribe();
    let running = thread.run_turn(turn(stop.cancellation()));
    tokio::pin!(running);

    // 先确认成对样本真的出现过：取消前的 live 预览必须可用。
    let observed_pair = tokio::time::timeout(Duration::from_secs(10), async {
        loop {
            let snapshot = tokio::select! {
                result = &mut running => panic!("the turn ended before the live pair arrived: {result:?}"),
                snapshot = subscription.next() => snapshot.expect("thread stays open"),
            };
            if has_live_pair(&snapshot) {
                break snapshot;
            }
        }
    })
    .await
    .expect("the live pair is observable before the stop");
    assert_eq!(
        live_usage(&observed_pair)
            .expect("the live identity is published")
            .completion_tokens,
        Some(8)
    );

    stop.apply(&thread).await;
    // 无论停止来自 mailbox 还是直接取消 token，都必须有一份**新的**撤销快照：生产者此刻
    // 没有任何新观察，model 调用仍被暂停，所以 attempt 仍是 Running。
    let immediate = tokio::time::timeout(Duration::from_secs(10), subscription.next())
        .await
        .unwrap_or_else(|_| {
            panic!(
                "{} must publish a withdrawal snapshot without a new observation",
                stop.label()
            )
        })
        .expect("the Thread stays open");
    assert!(immediate.observation_revision > observed_pair.observation_revision);
    assert!(
        immediate.model_progress.is_some(),
        "the stopped attempt keeps its observation identity and partial content"
    );
    assert!(
        !has_live_pair(&immediate),
        "{} must withdraw the live pair in its immediate snapshot",
        stop.label()
    );
    let usage = live_usage(&immediate).expect("the live identity survives the withdrawal");
    assert_eq!(usage.completion_tokens, None, "{} numerator", stop.label());
    assert_eq!(usage.response_millis, None, "{} denominator", stop.label());
    assert!(
        immediate
            .model_progress
            .as_ref()
            .is_some_and(|active| active
                .progress
                .parts()
                .iter()
                .any(|part| part.text() == "partial body")),
        "{} must keep the partial body",
        stop.label()
    );

    // 在途观察继续到达：生产者重新发布一组完整 pair，但已停止的代次不得复活它。
    barriers.released.notify_one();
    barriers.republished.notified().await;
    let after_republish = tokio::time::timeout(Duration::from_secs(10), subscription.next())
        .await
        .expect("the republished observation is published")
        .expect("the Thread stays open");
    assert!(
        !has_live_pair(&after_republish),
        "{} let an in-flight observation resurrect the stopped attempt's live pair",
        stop.label()
    );

    barriers.finished.notify_one();
    let completion = tokio::time::timeout(Duration::from_secs(30), running)
        .await
        .expect("the cancelled call returns");
    match completion {
        Ok(_) | Err(ThreadError::Cancelled) => {}
        // 直接取消 active token 时输入代次本身没有被标记取消，core 按既有策略把这个失败
        // 归类为模型失败；本用例只保证不发布速度样本。
        Err(ThreadError::Model(error)) if error.kind == ModelFailureKind::Cancelled => {}
        Err(other) => panic!("unexpected stopped-turn result: {other:?}"),
    }
    let final_snapshot = current_snapshot(&thread).await;
    assert!(
        final_snapshot.model_progress.is_none(),
        "the settled attempt publishes no live observation"
    );
    assert!(
        after_republish.model_progress.is_some(),
        "the observed frame still belonged to the resident attempt"
    );
}

#[tokio::test]
async fn cancelling_a_running_turn_withdraws_the_live_pair_immediately() {
    stopped_attempt_never_publishes_a_live_pair(Stop::CancelRunningTurn).await;
}

#[tokio::test]
async fn interrupting_the_running_turn_withdraws_the_live_pair_immediately() {
    stopped_attempt_never_publishes_a_live_pair(Stop::InterruptTurn).await;
}

#[tokio::test]
async fn cancelling_the_turn_token_withdraws_the_live_pair_immediately() {
    stopped_attempt_never_publishes_a_live_pair(Stop::TurnToken {
        cancellation: CancellationToken::new(),
    })
    .await;
}

#[tokio::test]
async fn interrupting_the_thread_withdraws_the_live_pair_immediately() {
    stopped_attempt_never_publishes_a_live_pair(Stop::ThreadInterrupt).await;
}
