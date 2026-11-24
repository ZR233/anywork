use crate::plan::Plan;
use crate::types::{
    PLAN_CURRENT_TOOL, PLAN_HISTORY_TOOL, PLAN_NEXT_TOOL, PLAN_TRANSITION_TOOL, PlanActor,
    PlanEmptyArgs, PlanHistoryArgs, PlanHistoryResponse, PlanNextResponse, PlanSnapshot,
    PlanTransitionArgs, PlanTransitionCommand, PlanTransitionOutcome,
};
use pl_agent_tool::typed::TypedTool;
use std::future::Future;
use std::sync::{Arc, Mutex};
use std::time::{SystemTime, UNIX_EPOCH};
use thiserror::Error;

/// Narrow host capability consumed by the standalone Plan tool family.
///
/// Hosts (Native Thread, ACP session, or independent consumers) own storage and
/// confirmation UI delivery; `pl-tool-plan` stays strictly decoupled from them.
pub trait PlanHost: Send + Sync + 'static {
    type Context: Send + 'static;
    type Error: std::error::Error + Send + Sync + 'static;

    fn current(
        &self,
        context: Self::Context,
    ) -> impl Future<Output = Result<PlanSnapshot, Self::Error>> + Send;

    fn next(
        &self,
        context: Self::Context,
    ) -> impl Future<Output = Result<PlanNextResponse, Self::Error>> + Send;

    fn history(
        &self,
        args: PlanHistoryArgs,
        context: Self::Context,
    ) -> impl Future<Output = Result<PlanHistoryResponse, Self::Error>> + Send;

    fn transition(
        &self,
        args: PlanTransitionArgs,
        context: Self::Context,
    ) -> impl Future<Output = Result<PlanTransitionOutcome, Self::Error>> + Send;
}

/// Self-contained single-agent in-memory `PlanHost` for standalone / embedded consumers.
#[derive(Debug, Default)]
pub struct MemoryPlanHost {
    plan: Mutex<Plan>,
}

#[derive(Debug, Error)]
#[error("in-memory plan host lock poisoned")]
pub struct MemoryPlanHostError;

impl MemoryPlanHost {
    #[must_use]
    pub fn new(plan: Plan) -> Self {
        Self {
            plan: Mutex::new(plan),
        }
    }

    pub fn snapshot(&self) -> Result<PlanSnapshot, MemoryPlanHostError> {
        self.plan
            .lock()
            .map(|guard| guard.snapshot())
            .map_err(|_| MemoryPlanHostError)
    }
}

impl PlanHost for MemoryPlanHost {
    type Context = ();
    type Error = MemoryPlanHostError;

    async fn current(&self, _context: ()) -> Result<PlanSnapshot, Self::Error> {
        self.plan
            .lock()
            .map(|guard| guard.snapshot())
            .map_err(|_| MemoryPlanHostError)
    }

    async fn next(&self, _context: ()) -> Result<PlanNextResponse, Self::Error> {
        self.plan
            .lock()
            .map(|guard| guard.next())
            .map_err(|_| MemoryPlanHostError)
    }

    async fn history(
        &self,
        args: PlanHistoryArgs,
        _context: (),
    ) -> Result<PlanHistoryResponse, Self::Error> {
        self.plan
            .lock()
            .map(|guard| guard.history(args.limit))
            .map_err(|_| MemoryPlanHostError)
    }

    async fn transition(
        &self,
        args: PlanTransitionArgs,
        _context: (),
    ) -> Result<PlanTransitionOutcome, Self::Error> {
        let mut guard = self.plan.lock().map_err(|_| MemoryPlanHostError)?;
        let now_ms = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| i64::try_from(d.as_millis()).unwrap_or(i64::MAX))
            .unwrap_or(0);
        Ok(guard.transition(PlanTransitionCommand::from_args(
            args,
            PlanActor::Agent,
            now_ms,
        )))
    }
}

#[derive(Debug)]
pub struct PlanCurrentTool<H> {
    host: Arc<H>,
}

impl<H> PlanCurrentTool<H> {
    #[must_use]
    pub fn new(host: Arc<H>) -> Self {
        Self { host }
    }
}

impl<H: PlanHost> TypedTool for PlanCurrentTool<H> {
    const NAME: &'static str = PLAN_CURRENT_TOOL;
    const DESCRIPTION: &'static str = "Read the current Plan state, document, revision, allowed transitions, and all valid Plan states.";
    type Args = PlanEmptyArgs;
    type Context = H::Context;
    type Output = PlanSnapshot;
    type Error = H::Error;

    fn execute(
        &self,
        _args: Self::Args,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send {
        self.host.current(context)
    }
}

#[derive(Debug)]
pub struct PlanNextTool<H> {
    host: Arc<H>,
}

impl<H> PlanNextTool<H> {
    #[must_use]
    pub fn new(host: Arc<H>) -> Self {
        Self { host }
    }
}

impl<H: PlanHost> TypedTool for PlanNextTool<H> {
    const NAME: &'static str = PLAN_NEXT_TOOL;
    const DESCRIPTION: &'static str =
        "List allowed outgoing Plan state transitions and conditions from the current state.";
    type Args = PlanEmptyArgs;
    type Context = H::Context;
    type Output = PlanNextResponse;
    type Error = H::Error;

    fn execute(
        &self,
        _args: Self::Args,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send {
        self.host.next(context)
    }
}

#[derive(Debug)]
pub struct PlanHistoryTool<H> {
    host: Arc<H>,
}

impl<H> PlanHistoryTool<H> {
    #[must_use]
    pub fn new(host: Arc<H>) -> Self {
        Self { host }
    }
}

impl<H: PlanHost> TypedTool for PlanHistoryTool<H> {
    const NAME: &'static str = PLAN_HISTORY_TOOL;
    const DESCRIPTION: &'static str = "Read committed Plan state transitions and archive digest.";
    type Args = PlanHistoryArgs;
    type Context = H::Context;
    type Output = PlanHistoryResponse;
    type Error = H::Error;

    fn execute(
        &self,
        args: Self::Args,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send {
        self.host.history(args, context)
    }
}

#[derive(Debug)]
pub struct PlanTransitionTool<H> {
    host: Arc<H>,
}

impl<H> PlanTransitionTool<H> {
    #[must_use]
    pub fn new(host: Arc<H>) -> Self {
        Self { host }
    }
}

impl<H: PlanHost> TypedTool for PlanTransitionTool<H> {
    const NAME: &'static str = PLAN_TRANSITION_TOOL;
    const DESCRIPTION: &'static str = "Transition the agent's independent Plan state machine (`drafting`, `awaitingConfirmation`, `revisionRequested`, `approved`). When `force` is false (default), only valid outgoing transitions are permitted and invalid targets return detailed hints listing allowed targets and valid states; set `force=true` only when intentionally overriding state rules. Provide complete Markdown in `content` when entering `awaitingConfirmation`.";
    type Args = PlanTransitionArgs;
    type Context = H::Context;
    type Output = PlanTransitionOutcome;
    type Error = H::Error;

    fn execute(
        &self,
        args: Self::Args,
        context: Self::Context,
    ) -> impl Future<Output = Result<Self::Output, Self::Error>> + Send {
        self.host.transition(args, context)
    }
}

/// Complete independent Plan tool set bound to one host adapter.
pub struct PlanToolFamily<H> {
    pub current: PlanCurrentTool<H>,
    pub next: PlanNextTool<H>,
    pub history: PlanHistoryTool<H>,
    pub transition: PlanTransitionTool<H>,
}

#[must_use]
pub fn plan_tool_family<H>(host: Arc<H>) -> PlanToolFamily<H> {
    PlanToolFamily {
        current: PlanCurrentTool::new(Arc::clone(&host)),
        next: PlanNextTool::new(Arc::clone(&host)),
        history: PlanHistoryTool::new(Arc::clone(&host)),
        transition: PlanTransitionTool::new(host),
    }
}
