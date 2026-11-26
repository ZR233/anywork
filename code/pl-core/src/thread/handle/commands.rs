//! Priority-split owner commands: Tier 1 user controls vs Tier 2 internal runtime events.
use super::*;

/// Tier 1 (priority) commands initiated directly by user/host control actions.
#[derive(Debug)]
pub(in crate::thread) enum UserCommand {
    Mailbox(mailbox::MailboxCommand),
    CurrentResume {
        epoch: current::RuntimeEpoch,
        expected_stop_generation: u64,
        input: TurnInput,
        reply: oneshot::Sender<Result<TurnCompletion, current::CurrentError>>,
    },
    QueuedTurn(
        input::QueuedTurn,
        oneshot::Sender<Result<Option<TurnCompletion>, ThreadError>>,
    ),
    ResolveInteraction(
        interactions::InteractionResolution,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    CancelInteraction(
        interactions::InteractionCancellation,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    Turn(
        TurnInput,
        oneshot::Sender<Result<TurnCompletion, ThreadError>>,
    ),
    Close(
        crate::thread::owner::ClosePurpose,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
}

impl UserCommand {
    pub(in crate::thread) fn reject(self) {
        fn closed<T>(reply: oneshot::Sender<Result<T, ThreadError>>) {
            let _ = reply.send(Err(ThreadError::Closed));
        }
        match self {
            Self::Mailbox(command) => drop(command),
            Self::CurrentResume { reply, .. } => {
                let _ = reply.send(Err(current::CurrentError::Closed));
            }
            Self::ResolveInteraction(_, reply) | Self::CancelInteraction(_, reply) => closed(reply),
            Self::Turn(_, reply) => closed(reply),
            Self::QueuedTurn(_, reply) => closed(reply),
            Self::Close(_, reply) => closed(reply),
        }
    }
}

/// Tier 2 general runtime/tool/context events processed after ready Tier 1 user commands.
#[derive(Debug)]
pub(in crate::thread) enum LoopEvent {
    Mailbox(mailbox::MailboxCommand),
    ContextPreparation(
        Option<context_preparation::ContextPreparer>,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Reveal(Vec<String>, oneshot::Sender<Result<(), ThreadError>>),
    RequestInteraction(
        interactions::InteractionRequest,
        oneshot::Sender<Result<interactions::InteractionRecord, ThreadError>>,
    ),
    Application(
        extensions::ApplicationUpdate,
        oneshot::Sender<Result<ThreadSnapshot, ThreadError>>,
    ),
    Resources(
        crate::context::ResourceAccess,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Retry {
        source: String,
        attempt: String,
        cancellation: CancellationToken,
        reply: oneshot::Sender<Result<ModelStepOutput, ThreadError>>,
    },
    AttachHistory(
        super::super::history_sink::HistorySinkHandle,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    AttachEventSink(
        Arc<dyn super::super::events::CoreEventSink>,
        oneshot::Sender<Result<(), ThreadError>>,
    ),
    Capacity(ContextCapacity, oneshot::Sender<Result<(), ThreadError>>),
    PatchRuntimeFacts(
        Vec<RuntimeFact>,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    UpdateFacts(
        Vec<RuntimeFact>,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    CompactContext(
        u64,
        CancellationToken,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    ReplaceContext(
        ReplaceContext,
        oneshot::Sender<Result<ContextSnapshot, ThreadError>>,
    ),
    Execute(
        String,
        CancellationToken,
        oneshot::Sender<Result<ToolDispatch, ThreadError>>,
    ),
    Step(
        StepInput,
        oneshot::Sender<Result<ModelStepOutput, ThreadError>>,
    ),
}

impl LoopEvent {
    pub(in crate::thread) fn reject(self) {
        fn closed<T>(reply: oneshot::Sender<Result<T, ThreadError>>) {
            let _ = reply.send(Err(ThreadError::Closed));
        }
        match self {
            Self::Mailbox(command) => drop(command),
            Self::ContextPreparation(_, reply)
            | Self::Reveal(_, reply)
            | Self::Resources(_, reply)
            | Self::AttachHistory(_, reply)
            | Self::AttachEventSink(_, reply)
            | Self::Capacity(_, reply) => closed(reply),
            Self::RequestInteraction(_, reply) => closed(reply),
            Self::Application(_, reply) => closed(reply),
            Self::Retry { reply, .. } | Self::Step(_, reply) => closed(reply),
            Self::PatchRuntimeFacts(_, reply)
            | Self::UpdateFacts(_, reply)
            | Self::CompactContext(_, _, reply)
            | Self::ReplaceContext(_, reply) => closed(reply),
            Self::Execute(_, _, reply) => closed(reply),
        }
    }
}
