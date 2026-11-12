//! Reliable member facts on the original call's owner and cold-admission path.
use std::collections::BTreeMap;
use std::sync::{
    Arc, Mutex,
    atomic::{AtomicBool, Ordering},
};
use std::time::Duration;

use pl_core::{
    context::{ContextContent, ContextSource, OpaquePayload},
    model::{
        AggregateChannel, DynModelSession, ModelError, ModelFailureKind, ModelMemberError,
        ModelMemberSender, ModelRequest, ModelSession, ModelStepOutput, ObservedItemKind,
        ObservedPartIdentity, ObservedPartKind, PreparedModelCall, ProviderPartIdentity,
    },
    thread::{
        AttemptOutcome, AttemptStatus, ModelStepLimit, ThreadHandle, TurnInput,
        cold::{ColdStore, ColdStoreError, ColdStoreHandle, StoragePressure, ThreadWrite},
    },
};
use tokio::sync::Notify;

#[derive(Debug, Default)]
struct Store {
    writes: Mutex<Vec<ThreadWrite>>,
    charges: Mutex<Vec<u64>>,
    released: AtomicBool,
    flushed: AtomicBool,
    reject_member: AtomicBool,
    reject_next_charge: AtomicBool,
    limit: Option<u64>,
    accounting: Mutex<Accounting>,
    durable_on_admit: bool,
    reject_first_running: bool,
}

#[derive(Debug)]
struct OperationAccount {
    limit: u64,
    accepted: u64,
    transferred: u64,
}

impl OperationAccount {
    fn retained(&self) -> u64 {
        self.accepted - self.transferred
    }
}

#[derive(Debug, Default)]
struct Accounting {
    operations: BTreeMap<String, OperationAccount>,
    effects: BTreeMap<u64, u64>,
    durable: u64,
    releases: usize,
    member_sequence: Option<u64>,
    terminal_member_retained: Option<u64>,
    running_effect_bytes: Option<u64>,
    running_refusals: usize,
    transfers: Vec<ClaimTransfer>,
}

#[derive(Debug)]
struct ClaimTransfer {
    sequence: u64,
    bytes: u64,
    taken: u64,
    retained: u64,
}

impl Accounting {
    fn output_retained(&self) -> u64 {
        self.operations
            .values()
            .map(OperationAccount::retained)
            .sum()
    }

    fn effect_bytes(&self) -> u64 {
        self.effects.values().sum()
    }
}

#[derive(Debug)]
struct Storage(Arc<Store>);

impl std::ops::Deref for Storage {
    type Target = Store;
    fn deref(&self) -> &Store {
        &self.0
    }
}

impl ColdStore for Storage {
    fn admit(&self, _: &str, write: ThreadWrite) -> Result<(), ColdStoreError> {
        let bytes = write.effect.encode().unwrap().content().len() as u64;
        if write
            .effect
            .attempt
            .as_ref()
            .is_some_and(|a| matches!(a.outcome, AttemptOutcome::Running))
        {
            let mut account = self.accounting.lock().unwrap();
            account.running_effect_bytes = Some(bytes);
            if self.reject_first_running && account.running_refusals == 0 {
                account.running_refusals += 1;
                return Err(ColdStoreError {
                    source: Box::new(std::io::Error::other("controlled first Running refusal")),
                });
            }
        }
        if !write.effect.model_members.is_empty()
            || !write.effect.model_member_starts.is_empty()
            || !write.effect.model_member_content_available.is_empty()
        {
            assert!(
                !self.released.load(Ordering::SeqCst),
                "member precedes budget release"
            );
            assert_eq!(write.output_claim.as_deref(), Some("member-attempt:0"));
            if self.reject_member.load(Ordering::SeqCst) {
                return Err(ColdStoreError {
                    source: Box::new(std::io::Error::other("controlled admission refusal")),
                });
            }
        }
        let sequence = write.effect.sequence;
        let mut account = self.accounting.lock().unwrap();
        if sequence <= account.durable || account.effects.contains_key(&sequence) {
            return Ok(());
        }
        // The production writer draws only accepted-but-not-transferred output, then charges the
        // admitted effect as its own retained bytes. Durability frees that effect, not the call.
        if let Some(operation) = write
            .output_claim
            .as_ref()
            .and_then(|id| account.operations.get_mut(id))
        {
            let taken = operation.retained().min(bytes);
            operation.transferred += taken;
            let retained = operation.retained();
            account.transfers.push(ClaimTransfer {
                sequence,
                bytes,
                taken,
                retained,
            });
        }
        if !write.effect.model_members.is_empty()
            || !write.effect.model_member_starts.is_empty()
            || !write.effect.model_member_content_available.is_empty()
        {
            account.member_sequence = Some(sequence);
        }
        if account.member_sequence.is_some()
            && write
                .effect
                .attempt
                .as_ref()
                .is_some_and(|a| !matches!(a.outcome, AttemptOutcome::Running))
        {
            account.terminal_member_retained = Some(account.output_retained());
        }
        account.effects.insert(sequence, bytes);
        let mut writes = self.writes.lock().unwrap();
        writes.push(write);
        if self.durable_on_admit {
            // A controlled writer may finish before the owner next samples pressure. Drop every
            // durable ThreadWrite (including its opaque allocation), then publish the real receipt.
            account.durable = sequence;
            account.effects.retain(|seq, _| *seq > sequence);
            writes.retain(|w| w.effect.sequence > sequence);
        }
        Ok(())
    }

    async fn flush(&self, _: &str, _: u64) -> Result<(), ColdStoreError> {
        self.flushed.store(true, Ordering::SeqCst);
        Ok(())
    }

    fn reserve_operation_output(
        &self,
        _: &str,
        operation_id: &str,
        requested: u64,
    ) -> Result<u64, ColdStoreError> {
        let limit = self.limit.unwrap_or(requested).min(requested);
        assert!(
            self.accounting
                .lock()
                .unwrap()
                .operations
                .insert(
                    operation_id.into(),
                    OperationAccount {
                        limit,
                        accepted: 0,
                        transferred: 0
                    },
                )
                .is_none()
        );
        Ok(limit)
    }

    fn charge_operation_output(
        &self,
        _: &str,
        operation_id: &str,
        bytes: u64,
    ) -> Result<(), ColdStoreError> {
        if self.reject_next_charge.swap(false, Ordering::SeqCst) {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("controlled output budget refusal")),
            });
        }
        let mut account = self.accounting.lock().unwrap();
        let operation = account
            .operations
            .get_mut(operation_id)
            .expect("registered operation");
        if bytes > operation.limit {
            return Err(ColdStoreError {
                source: Box::new(std::io::Error::other("operation limit")),
            });
        }
        operation.accepted = operation.accepted.max(bytes);
        self.charges.lock().unwrap().push(bytes);
        Ok(())
    }

    fn release_operation_output(&self, _: &str, operation_id: &str) {
        let mut account = self.accounting.lock().unwrap();
        assert!(
            account.operations.remove(operation_id).is_some(),
            "release exactly once"
        );
        account.releases += 1;
        self.released.store(true, Ordering::SeqCst);
    }

    fn pressure(&self, _: &str) -> StoragePressure {
        let account = self.accounting.lock().unwrap();
        let bytes = account.output_retained() + account.effect_bytes();
        StoragePressure {
            thread_bytes: bytes,
            store_bytes: bytes,
            durable_sequence: account.durable,
            ..Default::default()
        }
    }
}

#[derive(Clone, Copy)]
enum Ending {
    Complete,
    DuplicateAllocation,
    Cancel,
    Closing,
    Conflict,
    Fail,
    Queued,
    InvalidGeneration,
}

struct MemberModel {
    admitted: Arc<Notify>,
    release: Arc<Notify>,
    held_sender: Arc<Mutex<Option<ModelMemberSender>>>,
    ending: Ending,
    body: String,
}

impl ModelSession for MemberModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let admitted = self.admitted.clone();
        let release = self.release.clone();
        let held_sender = self.held_sender.clone();
        let ending = self.ending;
        let payload = OpaquePayload::text(self.body.clone());
        let duplicate = matches!(ending, Ending::DuplicateAllocation)
            .then(|| OpaquePayload::text(self.body.clone()));
        Ok(PreparedModelCall::new(async move {
            let sender = request.members.as_ref().unwrap();
            *held_sender.lock().unwrap() = Some(sender.clone());
            if matches!(ending, Ending::Queued) {
                // Exercise owner draining even if execute becomes ready in the same poll as send.
                use futures::FutureExt;
                assert!(
                    sender
                        .submit(0, "item".into(), payload)
                        .now_or_never()
                        .is_none()
                );
            } else {
                sender
                    .submit(
                        u32::from(matches!(ending, Ending::InvalidGeneration)),
                        "item".into(),
                        payload.clone(),
                    )
                    .await
                    .map_err(model_error)?;
                sender
                    .submit(0, "item".into(), payload)
                    .await
                    .map_err(model_error)?;
                if let Some(duplicate) = duplicate {
                    sender
                        .submit(0, "item".into(), duplicate)
                        .await
                        .map_err(model_error)?;
                }
            }
            admitted.notify_one();
            if matches!(ending, Ending::Cancel | Ending::Closing) {
                request.cancellation.cancelled().await;
            } else if !matches!(ending, Ending::Queued) {
                release.notified().await;
            }
            if matches!(ending, Ending::Conflict) {
                assert!(matches!(
                    sender
                        .submit(0, "item".into(), OpaquePayload::text("changed"))
                        .await,
                    Err(ModelMemberError::Rejected(_))
                ));
            }
            if matches!(ending, Ending::Fail) {
                return Err(model_error(std::io::Error::other(
                    "provider failed after member",
                )));
            }
            Ok(ModelStepOutput {
                turn_action: Default::default(),
                attempt_id: request.attempt_id,
                base_context_revision: request.context.revision,
                content: vec![ContextContent::Text {
                    text: Arc::from("final answer"),
                }],
                tool_calls: vec![],
                private_context: None,
                usage: Default::default(),
            })
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn model_error(source: impl std::error::Error + Send + Sync + 'static) -> ModelError {
    ModelError {
        kind: ModelFailureKind::InvalidResponse,
        source: Some(Box::new(source)),
        details: None,
        usage: Box::default(),
    }
}

struct StartingModel {
    admitted: Arc<Notify>,
    complete: bool,
    queued: bool,
    conflict: bool,
    content: bool,
    identity: ObservedPartIdentity,
}

impl ModelSession for StartingModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let admitted = self.admitted.clone();
        let complete = self.complete;
        let queued = self.queued;
        let conflict = self.conflict;
        let content = self.content;
        let identity = self.identity.clone();
        Ok(PreparedModelCall::new(async move {
            let sender = request.members.as_ref().unwrap();
            if queued {
                use futures::FutureExt;
                assert!(sender.start(0, identity).now_or_never().is_none());
                return Err(model_error(std::io::Error::other(
                    "return with occupied slot",
                )));
            }
            sender
                .start(0, identity.clone())
                .await
                .map_err(model_error)?;
            let mut enriched = identity;
            if let ObservedPartIdentity::Provider(part) = &mut enriched {
                part.output_index = Some(7);
            }
            sender
                .start(0, enriched.clone())
                .await
                .map_err(model_error)?;
            if conflict {
                if let ObservedPartIdentity::Provider(part) = &mut enriched {
                    part.output_index = Some(8);
                }
                return sender
                    .start(0, enriched)
                    .await
                    .map(|()| unreachable!("conflicting start cannot be admitted"))
                    .map_err(model_error);
            }
            if content {
                sender
                    .content_available(0, enriched.clone())
                    .await
                    .map_err(model_error)?;
                sender
                    .content_available(0, enriched)
                    .await
                    .map_err(model_error)?;
            }
            if complete {
                sender
                    .submit(0, "starting-item".into(), OpaquePayload::text("ended"))
                    .await
                    .map_err(model_error)?;
            }
            admitted.notify_one();
            request.cancellation.cancelled().await;
            Err(model_error(std::io::Error::other("cancelled after start")))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

fn starting_identity() -> ObservedPartIdentity {
    ObservedPartIdentity::Provider(ProviderPartIdentity {
        item_id: Arc::from("starting-item"),
        output_index: None,
        item_kind: ObservedItemKind::Reasoning,
        part: ObservedPartKind::ReasoningText,
        content_index: 0,
    })
}

async fn exercise_start(complete: bool, reject_storage: bool, content: bool) {
    let admitted = Arc::new(Notify::new());
    let store = Arc::new(Store::default());
    store.reject_member.store(reject_storage, Ordering::SeqCst);
    let thread = ThreadHandle::start(
        "starts".into(),
        DynModelSession::new(StartingModel {
            admitted: admitted.clone(),
            complete,
            queued: false,
            conflict: false,
            content,
            identity: starting_identity(),
        }),
    )
    .unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let cancellation = tokio_util::sync::CancellationToken::new();
    let task = {
        let thread = thread.clone();
        let cancellation = cancellation.clone();
        tokio::spawn(async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "member-turn".into(),
                    attempt_prefix: "member-attempt".into(),
                    content: vec![],
                    max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                    cancellation,
                })
                .await
        })
    };
    tokio::time::timeout(Duration::from_secs(5), admitted.notified())
        .await
        .unwrap();
    let effects = thread.effects().await.unwrap();
    let starts: Vec<_> = effects
        .iter()
        .filter(|e| !e.model_member_starts.is_empty())
        .collect();
    assert_eq!(
        starts.len(),
        1,
        "late output index is not a second identity"
    );
    assert_eq!(
        starts[0].model_member_starts[0].identity,
        starting_identity()
    );
    assert!(starts[0].context.is_none());
    assert!(starts[0].attempt.is_none());
    assert!(starts[0].turn.is_none());
    let snapshot = thread.snapshot();
    assert_eq!(
        snapshot.attempts.last().unwrap().status,
        AttemptStatus::Running
    );
    assert!(snapshot.attempts.last().unwrap().usage.is_none());
    assert!(
        !snapshot
            .context
            .records
            .iter()
            .any(|r| r.source == ContextSource::Assistant)
    );
    let completed: Vec<_> = effects
        .iter()
        .filter(|e| !e.model_members.is_empty())
        .collect();
    assert_eq!(completed.len(), usize::from(complete));
    let available: Vec<_> = effects
        .iter()
        .filter(|effect| !effect.model_member_content_available.is_empty())
        .collect();
    assert_eq!(available.len(), usize::from(content));
    if content {
        let effect = available[0];
        assert_eq!(effect.model_member_content_available.len(), 1);
        let member = &effect.model_member_content_available[0];
        assert_eq!(member.turn_id, "member-turn");
        assert_eq!(member.attempt_id, "member-attempt:0");
        assert_eq!(member.generation, 0);
        assert!(starts[0].sequence < effect.sequence);
        assert!(effect.context.is_none() && effect.attempt.is_none() && effect.turn.is_none());
        assert!(effect.model_members.is_empty());
        let restored =
            pl_core::thread::ThreadEffectBatch::decode(&effect.encode().unwrap()).unwrap();
        assert_eq!(
            restored.model_member_content_available,
            effect.model_member_content_available
        );
        if complete {
            assert!(effect.sequence < completed[0].sequence);
        }
    }
    if complete {
        assert!(starts[0].sequence < completed[0].sequence);
    }
    if reject_storage {
        assert!(
            store
                .writes
                .lock()
                .unwrap()
                .iter()
                .all(|w| w.effect.model_member_starts.is_empty())
        );
        store.reject_member.store(false, Ordering::SeqCst);
    }
    assert!(!store.released.load(Ordering::SeqCst));
    cancellation.cancel();
    assert!(
        tokio::time::timeout(Duration::from_secs(5), task)
            .await
            .unwrap()
            .unwrap()
            .is_err()
    );
    {
        let writes = store.writes.lock().unwrap();
        assert_eq!(
            writes
                .iter()
                .map(|w| w.effect.model_member_starts.len())
                .sum::<usize>(),
            1
        );
        assert_eq!(
            writes
                .iter()
                .map(|w| w.effect.model_members.len())
                .sum::<usize>(),
            usize::from(complete)
        );
        assert_eq!(
            writes
                .iter()
                .map(|write| write.effect.model_member_content_available.len())
                .sum::<usize>(),
            usize::from(content),
            "storage retry reuses the original content evidence"
        );
        if content {
            let persisted = writes
                .iter()
                .find(|write| !write.effect.model_member_content_available.is_empty())
                .unwrap();
            assert_eq!(persisted.effect.sequence, available[0].sequence);
            assert_eq!(
                persisted.effect.encode().unwrap(),
                available[0].encode().unwrap(),
                "pending replay preserves the exact frozen effect"
            );
        }
    }
    assert!(store.released.load(Ordering::SeqCst));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn beginning_only_is_reliable_without_context_and_cancellation_drains_started_and_completed()
{
    exercise_start(false, false, false).await;
    exercise_start(true, false, false).await;
    exercise_start(false, true, false).await;
}

#[tokio::test]
async fn content_available_is_once_reliable_ordered_and_replayed_through_cancellation() {
    exercise_start(false, false, true).await;
    exercise_start(true, false, true).await;
    exercise_start(false, true, true).await;
}

#[derive(Clone, Copy, Debug)]
enum ContentEnding {
    Queued,
    MissingStart,
    WrongGeneration,
    Conflict,
    Budget,
    Failure,
}

struct ContentModel {
    ending: ContentEnding,
    store: Arc<Store>,
}

impl ModelSession for ContentModel {
    async fn prepare(&mut self, request: ModelRequest) -> Result<PreparedModelCall, ModelError> {
        let ending = self.ending;
        let store = self.store.clone();
        Ok(PreparedModelCall::new(async move {
            let sender = request.members.as_ref().unwrap();
            let mut identity = starting_identity();
            if !matches!(ending, ContentEnding::MissingStart) {
                sender
                    .start(0, identity.clone())
                    .await
                    .map_err(model_error)?;
            }
            if matches!(ending, ContentEnding::Budget) {
                store.reject_next_charge.store(true, Ordering::SeqCst);
            }
            if matches!(ending, ContentEnding::Queued) {
                use futures::FutureExt;
                assert!(
                    sender
                        .content_available(0, identity)
                        .now_or_never()
                        .is_none()
                );
            } else {
                let generation = u32::from(matches!(ending, ContentEnding::WrongGeneration));
                sender
                    .content_available(generation, identity.clone())
                    .await
                    .map_err(model_error)?;
                if matches!(ending, ContentEnding::Conflict) {
                    if let ObservedPartIdentity::Provider(part) = &mut identity {
                        part.output_index = Some(4);
                    }
                    sender
                        .content_available(0, identity.clone())
                        .await
                        .map_err(model_error)?;
                    if let ObservedPartIdentity::Provider(part) = &mut identity {
                        part.output_index = Some(5);
                    }
                    sender
                        .content_available(0, identity)
                        .await
                        .map_err(model_error)?;
                    panic!("contradictory content identity must be rejected");
                }
            }
            Err(model_error(std::io::Error::other(
                "controlled model failure",
            )))
        }))
    }

    async fn close(&mut self) -> Result<(), ModelError> {
        Ok(())
    }
}

#[tokio::test]
async fn content_available_checks_start_identity_generation_and_budget_and_drains_queued_fact() {
    for ending in [
        ContentEnding::Queued,
        ContentEnding::MissingStart,
        ContentEnding::WrongGeneration,
        ContentEnding::Conflict,
        ContentEnding::Budget,
        ContentEnding::Failure,
    ] {
        let store = Arc::new(Store::default());
        let thread = ThreadHandle::start(
            "content-evidence".into(),
            DynModelSession::new(ContentModel {
                ending,
                store: store.clone(),
            }),
        )
        .unwrap();
        thread
            .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
            .await
            .unwrap();
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            thread.run_turn(TurnInput {
                turn_id: "member-turn".into(),
                attempt_prefix: "member-attempt".into(),
                content: vec![],
                max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                cancellation: Default::default(),
            }),
        )
        .await
        .unwrap();
        assert!(result.is_err(), "{ending:?}: {result:?}");
        let effects = thread.effects().await.unwrap();
        assert_eq!(
            effects
                .iter()
                .map(|e| e.model_member_starts.len())
                .sum::<usize>(),
            usize::from(!matches!(ending, ContentEnding::MissingStart)),
            "{ending:?}",
        );
        assert_eq!(
            effects
                .iter()
                .map(|e| e.model_member_content_available.len())
                .sum::<usize>(),
            usize::from(matches!(
                ending,
                ContentEnding::Queued | ContentEnding::Conflict | ContentEnding::Failure
            )),
            "{ending:?}",
        );
        assert!(effects.iter().all(|e| e.model_members.is_empty()));
        assert!(store.released.load(Ordering::SeqCst));
        assert_eq!(store.accounting.lock().unwrap().releases, 1);
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn queued_start_drains_and_conflicts_or_budget_refusals_do_not_publish_new_starts() {
    for (queued, conflict, limit) in [
        (true, false, None),
        (false, true, None),
        (false, false, Some(512)),
    ] {
        let store = Arc::new(Store {
            limit,
            ..Default::default()
        });
        let thread = ThreadHandle::start(
            "starts".into(),
            DynModelSession::new(StartingModel {
                admitted: Arc::new(Notify::new()),
                complete: false,
                queued,
                conflict,
                content: false,
                identity: starting_identity(),
            }),
        )
        .unwrap();
        thread
            .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
            .await
            .unwrap();
        let result = tokio::time::timeout(
            Duration::from_secs(5),
            thread.run_turn(TurnInput {
                turn_id: "member-turn".into(),
                attempt_prefix: "member-attempt".into(),
                content: vec![],
                max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                cancellation: Default::default(),
            }),
        )
        .await
        .unwrap();
        assert!(result.is_err());
        let effects = thread.effects().await.unwrap();
        assert_eq!(
            effects
                .iter()
                .map(|e| e.model_member_starts.len())
                .sum::<usize>(),
            usize::from(limit.is_none())
        );
        assert!(effects.iter().all(|e| e.model_members.is_empty()));
        assert!(store.released.load(Ordering::SeqCst));
        thread.close().await.unwrap();
    }
}

#[test]
fn older_effect_does_not_infer_starts_from_completed_members() {
    let mut effect = serde_json::to_value(pl_core::thread::ThreadEffectBatch {
        model_members: vec![pl_core::model::ModelCompletedMember {
            turn_id: "turn".into(),
            attempt_id: "attempt".into(),
            generation: 0,
            member_id: "completed".into(),
            payload: OpaquePayload::text("already ended"),
        }]
        .into(),
        ..Default::default()
    })
    .unwrap();
    effect.as_object_mut().unwrap().remove("modelMemberStarts");
    effect
        .as_object_mut()
        .unwrap()
        .remove("modelMemberContentAvailable");
    let decoded: pl_core::thread::ThreadEffectBatch = serde_json::from_value(effect).unwrap();
    assert!(decoded.model_member_starts.is_empty());
    assert!(decoded.model_member_content_available.is_empty());
    assert_eq!(decoded.model_members.len(), 1);
    let aggregate = ObservedPartIdentity::Aggregate {
        channel: AggregateChannel::Text,
    };
    let started = pl_core::model::ModelStartedMember {
        turn_id: "turn".into(),
        attempt_id: "attempt".into(),
        generation: 0,
        identity: aggregate,
    };
    assert_eq!(
        serde_json::to_value(&started).unwrap()["attemptId"],
        "attempt"
    );
    let mut legacy = serde_json::to_value(pl_core::thread::ThreadEffectBatch {
        model_member_starts: vec![started].into(),
        ..Default::default()
    })
    .unwrap();
    legacy
        .as_object_mut()
        .unwrap()
        .remove("modelMemberContentAvailable");
    let decoded: pl_core::thread::ThreadEffectBatch = serde_json::from_value(legacy).unwrap();
    assert_eq!(decoded.model_member_starts.len(), 1);
    assert!(decoded.model_member_content_available.is_empty());
}

async fn exercise(ending: Ending) {
    let admitted = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let held_sender = Arc::new(Mutex::new(None));
    let store = Arc::new(Store::default());
    let model = MemberModel {
        admitted: admitted.clone(),
        release: release.clone(),
        held_sender: held_sender.clone(),
        ending,
        body: "authoritative member".into(),
    };
    let thread = ThreadHandle::start("members".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let input = TurnInput {
        turn_id: "member-turn".into(),
        attempt_prefix: "member-attempt".into(),
        content: vec![ContextContent::Text {
            text: Arc::from("question"),
        }],
        max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
        cancellation: Default::default(),
    };
    let cancellation = input.cancellation.clone();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move { thread.run_turn(input).await })
    };
    tokio::time::timeout(Duration::from_secs(5), admitted.notified())
        .await
        .unwrap();
    if !matches!(ending, Ending::Queued) {
        let writes = store.writes.lock().unwrap();
        let members: Vec<_> = writes
            .iter()
            .filter(|write| !write.effect.model_members.is_empty())
            .collect();
        assert_eq!(members.len(), 1, "duplicate is idempotent");
        let fact = members[0];
        assert!(fact.effect.context.is_none());
        assert!(fact.effect.attempt.is_none());
        assert!(fact.effect.turn.is_none());
        assert_eq!(
            fact.effect.model_members[0].payload.content(),
            "authoritative member"
        );
        assert_eq!(fact.effect.model_members[0].turn_id, "member-turn");
        let snapshot = thread.snapshot();
        assert_eq!(
            snapshot.attempts.last().unwrap().status,
            AttemptStatus::Running
        );
        assert!(snapshot.attempts.last().unwrap().usage.is_none());
        assert!(
            !snapshot
                .context
                .records
                .iter()
                .any(|r| r.source == ContextSource::Assistant)
        );
        assert!(!store.released.load(Ordering::SeqCst));
        assert_eq!(
            store.charges.lock().unwrap().len(),
            if matches!(ending, Ending::DuplicateAllocation) {
                4
            } else {
                3
            },
            "the preceding claim, resident envelope and member effect are charged; only a real duplicate allocation adds another charge"
        );
    }
    let closing = if matches!(ending, Ending::Closing) {
        let thread = thread.clone();
        Some(tokio::spawn(async move { thread.close().await }))
    } else {
        if matches!(ending, Ending::Cancel) {
            cancellation.cancel();
        } else {
            release.notify_one();
        }
        None
    };
    let result = tokio::time::timeout(Duration::from_secs(5), task)
        .await
        .unwrap()
        .unwrap();
    if matches!(
        ending,
        Ending::Complete | Ending::DuplicateAllocation | Ending::Queued
    ) {
        assert!(result.is_ok(), "{result:?}");
    }
    {
        let writes = store.writes.lock().unwrap();
        let member = writes
            .iter()
            .find(|write| !write.effect.model_members.is_empty())
            .unwrap();
        assert_eq!(
            writes
                .iter()
                .map(|w| w.effect.model_members.len())
                .sum::<usize>(),
            1
        );
        let terminal = writes
            .iter()
            .find(|w| {
                w.effect
                    .attempt
                    .as_ref()
                    .is_some_and(|a| !matches!(a.outcome, AttemptOutcome::Running))
            })
            .unwrap();
        assert!(member.effect.sequence < terminal.effect.sequence);
    }
    let sender = held_sender.lock().unwrap().take().unwrap();
    assert!(
        matches!(
            sender
                .submit(0, "late".into(), OpaquePayload::text("late"))
                .await,
            Err(ModelMemberError::Closed)
        ),
        "unused clone cannot keep ingress alive"
    );
    assert!(store.released.load(Ordering::SeqCst));
    if let Some(closing) = closing {
        tokio::time::timeout(Duration::from_secs(5), closing)
            .await
            .unwrap()
            .unwrap()
            .unwrap();
    } else {
        assert!(
            !store.flushed.load(Ordering::SeqCst),
            "member delivery does not flush"
        );
        thread.close().await.unwrap();
    }
}

#[tokio::test]
async fn member_effect_precedes_execute_barrier_and_terminal_without_flushing() {
    exercise(Ending::Complete).await;
}

#[tokio::test]
async fn identical_member_from_a_distinct_allocation_is_charged_without_republication() {
    exercise(Ending::DuplicateAllocation).await;
}

#[tokio::test]
async fn cancel_failure_and_conflict_preserve_previously_admitted_member() {
    for ending in [
        Ending::Cancel,
        Ending::Closing,
        Ending::Fail,
        Ending::Conflict,
    ] {
        exercise(ending).await;
    }
}

#[tokio::test]
async fn ready_execute_drains_the_slot_without_waiting_for_sender_eof() {
    exercise(Ending::Queued).await;
}

#[tokio::test]
async fn durable_member_effect_keeps_exact_dedup_body_funded_until_call_release() {
    durable_member_funding(false, vec![]).await;
}

#[tokio::test]
async fn delayed_running_claim_cannot_spend_the_exact_registry_resident_charge() {
    durable_member_funding(true, vec![]).await;
    durable_member_funding(
        true,
        vec![ContextContent::Text {
            text: Arc::from("vary the actual preceding effect envelope".repeat(7)),
        }],
    )
    .await;
}

async fn durable_member_funding(reject_first_running: bool, content: Vec<ContextContent>) {
    let admitted = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let body = "opaque allocation without progress".repeat(512);
    let body_bytes = body.len() as u64;
    let store = Arc::new(Store {
        durable_on_admit: true,
        reject_first_running,
        ..Default::default()
    });
    let model = MemberModel {
        admitted: admitted.clone(),
        release: release.clone(),
        held_sender: Default::default(),
        ending: Ending::Complete,
        body,
    };
    let thread = ThreadHandle::start("members".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "member-turn".into(),
                    attempt_prefix: "member-attempt".into(),
                    content,
                    max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                    cancellation: Default::default(),
                })
                .await
        })
    };
    tokio::time::timeout(Duration::from_secs(5), admitted.notified())
        .await
        .unwrap();
    assert_eq!(
        thread.snapshot().attempts.last().unwrap().status,
        AttemptStatus::Running
    );
    assert!(
        thread
            .snapshot()
            .model_progress
            .as_ref()
            .is_none_or(|p| p.progress.parts().is_empty())
    );
    assert!(
        store.writes.lock().unwrap().is_empty(),
        "writer no longer owns opaque bytes"
    );
    assert!(
        thread.effects().await.unwrap().is_empty(),
        "owner released the durable effect window"
    );
    {
        let account = store.accounting.lock().unwrap();
        let member_sequence = account.member_sequence.expect("member actually admitted");
        assert!(account.durable >= member_sequence);
        assert_eq!(account.effect_bytes(), 0);
        let operation = account.operations.get("member-attempt:0").unwrap();
        assert!(
            operation.transferred > body_bytes,
            "the claim actually transferred effect funding"
        );
        assert!(
            operation.retained() >= body_bytes,
            "strong call-local opaque body needs resident funds after effect durability: {} < {body_bytes}",
            operation.retained()
        );
        // With no progress, the backend first funds the complete preceding claim E, then receives
        // the full opaque+registry resident R as a distinct increment. Measure R from that grant,
        // not a guessed struct size or a lower bound on its body.
        let charges = store.charges.lock().unwrap();
        let preceding = account.running_effect_bytes.unwrap();
        assert_eq!(
            charges[0], preceding,
            "the complete preceding claim is funded first"
        );
        let resident = charges[1] - charges[0];
        assert!(
            resident > body_bytes,
            "R includes the registry metadata obligation"
        );
        assert!(
            operation.retained() >= resident,
            "the full resident charge must survive durability"
        );
        assert_eq!(account.running_refusals, usize::from(reject_first_running));
        for transfer in &account.transfers {
            if transfer.taken > 0 {
                assert!(
                    transfer.retained >= resident,
                    "claim seq={} bytes={} take={} left {} below resident R={resident}",
                    transfer.sequence,
                    transfer.bytes,
                    transfer.taken,
                    transfer.retained
                );
            }
        }
        if reject_first_running {
            assert_eq!(
                account.transfers.len(),
                2,
                "Running precedes the member in the same pending queue"
            );
            assert!(account.transfers[0].sequence < account.transfers[1].sequence);
            assert_eq!(account.transfers[0].taken, preceding);
            assert_eq!(account.transfers[1].taken, account.transfers[1].bytes);
        }
        assert_eq!(account.releases, 0);
    }
    assert!(!store.flushed.load(Ordering::SeqCst));
    release.notify_one();
    tokio::time::timeout(Duration::from_secs(5), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    {
        let account = store.accounting.lock().unwrap();
        let charges = store.charges.lock().unwrap();
        let resident = charges[1] - charges[0];
        assert!(
            account.terminal_member_retained.unwrap() >= resident,
            "terminal claim must not consume the live dedup body's resident funding"
        );
        assert_eq!(account.releases, 1);
        assert!(account.operations.is_empty());
        assert_eq!(account.effect_bytes(), 0);
    }
    thread.close().await.unwrap();
    assert_eq!(store.accounting.lock().unwrap().releases, 1);
}

#[tokio::test]
async fn synchronous_cold_refusal_keeps_member_in_the_original_pending_obligation() {
    let admitted = Arc::new(Notify::new());
    let release = Arc::new(Notify::new());
    let store = Arc::new(Store::default());
    store.reject_member.store(true, Ordering::SeqCst);
    let model = MemberModel {
        admitted: admitted.clone(),
        release: release.clone(),
        held_sender: Default::default(),
        ending: Ending::Complete,
        body: "pending member".into(),
    };
    let thread = ThreadHandle::start("members".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let task = {
        let thread = thread.clone();
        tokio::spawn(async move {
            thread
                .run_turn(TurnInput {
                    turn_id: "member-turn".into(),
                    attempt_prefix: "member-attempt".into(),
                    content: vec![],
                    max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
                    cancellation: Default::default(),
                })
                .await
        })
    };
    tokio::time::timeout(Duration::from_secs(5), admitted.notified())
        .await
        .unwrap();
    assert_eq!(
        thread
            .effects()
            .await
            .unwrap()
            .iter()
            .map(|e| e.model_members.len())
            .sum::<usize>(),
        1
    );
    assert!(
        store
            .writes
            .lock()
            .unwrap()
            .iter()
            .all(|w| w.effect.model_members.is_empty())
    );
    assert!(!store.released.load(Ordering::SeqCst));
    assert!(!store.flushed.load(Ordering::SeqCst));
    store.reject_member.store(false, Ordering::SeqCst);
    release.notify_one();
    tokio::time::timeout(Duration::from_secs(5), task)
        .await
        .unwrap()
        .unwrap()
        .unwrap();
    assert_eq!(
        store
            .writes
            .lock()
            .unwrap()
            .iter()
            .map(|w| w.effect.model_members.len())
            .sum::<usize>(),
        1
    );
    assert!(store.released.load(Ordering::SeqCst));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn member_envelope_budget_refuses_before_effect_publication() {
    let store = Arc::new(Store {
        limit: Some(512),
        ..Default::default()
    });
    let model = MemberModel {
        admitted: Arc::new(Notify::new()),
        release: Arc::new(Notify::new()),
        held_sender: Default::default(),
        ending: Ending::Complete,
        body: "\"".repeat(1024),
    };
    let thread = ThreadHandle::start("members".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let result = thread
        .run_turn(TurnInput {
            turn_id: "member-turn".into(),
            attempt_prefix: "member-attempt".into(),
            content: vec![],
            max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
            cancellation: Default::default(),
        })
        .await;
    assert!(result.is_err());
    assert!(
        store
            .writes
            .lock()
            .unwrap()
            .iter()
            .all(|w| w.effect.model_members.is_empty())
    );
    assert!(store.released.load(Ordering::SeqCst));
    thread.close().await.unwrap();
}

#[tokio::test]
async fn wrong_generation_is_rejected_before_effect_publication() {
    let store = Arc::new(Store::default());
    let model = MemberModel {
        admitted: Arc::new(Notify::new()),
        release: Arc::new(Notify::new()),
        held_sender: Default::default(),
        ending: Ending::InvalidGeneration,
        body: "invalid generation".into(),
    };
    let thread = ThreadHandle::start("members".into(), DynModelSession::new(model)).unwrap();
    thread
        .attach_storage(ColdStoreHandle::new(Storage(store.clone())))
        .await
        .unwrap();
    let result = thread
        .run_turn(TurnInput {
            turn_id: "member-turn".into(),
            attempt_prefix: "member-attempt".into(),
            content: vec![],
            max_model_steps: ModelStepLimit::Limited(1.try_into().unwrap()),
            cancellation: Default::default(),
        })
        .await;
    assert!(result.is_err());
    assert!(
        store
            .writes
            .lock()
            .unwrap()
            .iter()
            .all(|w| w.effect.model_members.is_empty())
    );
    assert!(store.released.load(Ordering::SeqCst));
    thread.close().await.unwrap();
}
