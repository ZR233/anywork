//! Bounded, single-consumer internal observation. Register before baseline capture; cancellation
//! never advances a delivery position and save acknowledgements never create another completion.

use crate::chat::*;
use std::{fmt, sync::Arc};
use tokio::sync::watch;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatTailBaseline {
    pub epoch: TimelineEpoch,
    pub items: Vec<ChatPageItem>,
    pub before: Option<ChatCursor>,
    /// Fixed captured H0, not the newest in-scope message.
    pub through_seq: u64,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChatCompletedBatch {
    pub from_seq: u64,
    /// Examined through this position; scope filtering may leave gaps or an empty internal batch.
    pub through_seq: u64,
    pub items: Vec<ChatPageItem>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ChatTailUpdate {
    Batch(ChatCompletedBatch),
    Closed,
}

pub struct ChatTail {
    subscription: Option<TailSubscription>,
    initial: Option<ChatTailBaseline>,
    delivered: u64,
    query: Option<ChatQuery>,
    demand: ReadDemand,
    budget: Arc<dyn ChatBudget>,
}
struct TailSubscription {
    session: Session,
    watch: watch::Receiver<u64>,
}
impl fmt::Debug for ChatTail {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("ChatTail")
            .field("delivered", &self.delivered)
            .finish_non_exhaustive()
    }
}

impl Session {
    pub async fn subscribe_tail(
        &self,
        query: ChatQuery,
        demand: ReadDemand,
        budget: Arc<dyn ChatBudget>,
    ) -> Result<ChatTail, ChatError> {
        let watch = self.0.changed.subscribe();
        let page = self
            .page(
                ChatPageRequest::latest(query.clone(), demand),
                budget.as_ref(),
            )
            .await?;
        let baseline = ChatTailBaseline {
            epoch: page.epoch,
            items: page.items,
            before: page.before,
            through_seq: page.ceiling,
        };
        Ok(ChatTail::new(
            self.clone(),
            watch,
            baseline,
            Some(query),
            demand,
            budget,
        ))
    }

    /// Resume an internal observation exactly at its delivered cut, never re-baseline at latest.
    pub async fn subscribe_after(
        &self,
        after: ChatCompletionCursor,
        query: Option<ChatQuery>,
        demand: ReadDemand,
        budget: Arc<dyn ChatBudget>,
    ) -> Result<ChatTail, ChatError> {
        self.validate_epoch(&after.epoch)?;
        super::read::reserve(demand, budget.as_ref())?;
        if let Some(query) = &query {
            query.validate()?;
        }
        let watch = self.0.changed.subscribe();
        self.ensure_initialized().await?;
        if after.append_seq > self.head_seq() {
            return Err(ChatError::InvalidArgument(
                "resume beyond published head".into(),
            ));
        }
        let baseline = ChatTailBaseline {
            epoch: self.epoch(),
            items: Vec::new(),
            before: None,
            through_seq: after.append_seq,
        };
        Ok(ChatTail::new(
            self.clone(),
            watch,
            baseline,
            query,
            demand,
            budget,
        ))
    }
}

impl ChatTail {
    fn new(
        session: Session,
        watch: watch::Receiver<u64>,
        baseline: ChatTailBaseline,
        query: Option<ChatQuery>,
        demand: ReadDemand,
        budget: Arc<dyn ChatBudget>,
    ) -> Self {
        Self {
            subscription: Some(TailSubscription { session, watch }),
            delivered: baseline.through_seq,
            initial: Some(baseline),
            query,
            demand,
            budget,
        }
    }

    pub fn initial(&mut self) -> Result<ChatTailBaseline, ChatError> {
        if self.subscription.is_none() {
            return Err(ChatError::Cancelled);
        }
        self.initial
            .take()
            .ok_or_else(|| ChatError::Conflict("baseline already taken".into()))
    }

    pub async fn next(&mut self) -> Result<ChatTailUpdate, ChatError> {
        if self.subscription.is_none() {
            return Err(ChatError::Cancelled);
        }
        if self.initial.is_some() {
            return Err(ChatError::Conflict("take initial baseline first".into()));
        }
        loop {
            let Some(subscription) = &self.subscription else {
                return Err(ChatError::Cancelled);
            };
            let mut waiter = subscription.watch.clone();
            while *waiter.borrow_and_update() <= self.delivered {
                if waiter.changed().await.is_err() {
                    return Ok(ChatTailUpdate::Closed);
                }
            }
            let session = subscription.session.clone();
            let batch = session
                .completed_after(
                    ChatCompletionCursor::new(session.epoch(), self.delivered),
                    self.query.clone(),
                    None,
                    self.demand,
                    self.budget.as_ref(),
                )
                .await?;
            self.delivered = batch.through_seq;
            if !batch.items.is_empty() {
                return Ok(ChatTailUpdate::Batch(batch));
            }
            // Out-of-scope completions advance the private cut, never create an empty product append.
        }
    }

    /// Drop/cancel a pending next future before closing. No spawned tasks or execution owner pins.
    pub fn close(&mut self) {
        self.subscription = None;
        self.initial = None;
    }
}
