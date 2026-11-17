//! One Current metadata watch plus immutable History original coverage for one reply target.

use super::content::{
    FinalError, activity_preview, demand, history_turn_items, history_turn_terminal, read_failure,
};
use super::projection::{ReplyProjection, gap};
use crate::studio::CurrentReader;
use crate::studio::runtime::{CurrentWatch, StudioRuntime};
use anyhow::Context as _;
use pl_protocol::{CurrentFrame, CurrentView, TurnState};
use std::future::Future;
use tokio_util::sync::CancellationToken;

pub(super) struct ReplyWatch {
    current_reader: CurrentReader,
    history_reader: crate::history::HistoryReader,
    current_watch: CurrentWatch,
    view: CurrentView,
    input_id: Option<String>,
    turn_id: Option<String>,
    projection: Option<ReplyProjection>,
    observed_state: Option<TurnState>,
}

impl ReplyWatch {
    pub(super) async fn open(runtime: &StudioRuntime, thread_id: &str) -> Result<Self, FinalError> {
        let current_reader = runtime
            .open_current_reader(thread_id, pl_protocol::CURRENT_PROTOCOL_VERSION, demand())
            .await
            .map_err(|error| read_failure("bot current reader open failed", error))?;
        let history_reader = match runtime
            .open_history_reader(thread_id, crate::history::HISTORY_PROTOCOL_VERSION)
            .await
        {
            Ok(reader) => reader,
            Err(error) => {
                let error = match current_reader.close().await {
                    Ok(()) => error,
                    Err(close) => error.context(format!(
                        "closing current after history-open failure also failed: {close:#}"
                    )),
                };
                return Err(read_failure("bot history reader open failed", error));
            }
        };
        let mut current_watch = match current_reader.watch(None, demand()).await {
            Ok(watch) => watch,
            Err(error) => {
                let error = match current_reader.close().await {
                    Ok(()) => error,
                    Err(close) => error.context(format!(
                        "closing current after watch-open failure also failed: {close:#}"
                    )),
                };
                history_reader.close().await;
                return Err(read_failure("bot current watch open failed", error));
            }
        };
        let view = match current_watch
            .next()
            .await
            .map_err(|error| read_failure("bot current watch baseline failed", error))?
        {
            Some(CurrentFrame::Reset { view }) => *view,
            _ => {
                let _ = current_watch.close().await;
                current_reader.close().await.map_err(|error| {
                    read_failure("bot current reader close after bad baseline failed", error)
                })?;
                history_reader.close().await;
                return Err(gap("bot current watch did not start with Reset"));
            }
        };
        Ok(Self {
            current_reader,
            history_reader,
            current_watch,
            view,
            input_id: None,
            turn_id: None,
            projection: None,
            observed_state: None,
        })
    }

    pub(super) fn reader(&self) -> crate::history::HistoryReader {
        self.history_reader.clone()
    }

    pub(super) fn preview(&self) -> Option<String> {
        self.projection.as_ref().and_then(ReplyProjection::preview)
    }

    pub(super) fn projection(&self) -> Option<ReplyProjection> {
        self.projection.clone()
    }

    pub(super) fn terminal(&self, turn_id: &str) -> Option<TurnState> {
        if self.turn_id.as_deref() != Some(turn_id) {
            return None;
        }
        self.projection.as_ref()?.terminal()
    }

    pub(super) fn observed_state(&self, turn_id: &str) -> Option<TurnState> {
        if self.turn_id.as_deref() != Some(turn_id) {
            return None;
        }
        self.observed_state.clone()
    }

    pub(super) async fn select_target(
        &mut self,
        runtime: &StudioRuntime,
        input_id: &str,
        turn_id: Option<&str>,
    ) -> Result<(), FinalError> {
        if self.input_id.as_deref() == Some(input_id) && self.turn_id.as_deref() == turn_id {
            return Ok(());
        }
        self.input_id = Some(input_id.into());
        self.turn_id = turn_id.map(str::to_owned);
        self.projection = None;
        self.observed_state = None;
        self.reconnect(runtime).await
    }

    pub(super) async fn ensure_coverage(&mut self) -> Result<(), FinalError> {
        let Some(turn_id) = self.turn_id.clone() else {
            return Ok(());
        };
        if self.projection.as_ref().is_some_and(|projection| {
            projection.completed().is_ok() && projection.terminal().is_some()
        }) {
            self.refresh_current()?;
            return Ok(());
        }
        let items = history_turn_items(&self.history_reader, &turn_id).await?;
        let terminal = history_turn_terminal(&self.history_reader, &turn_id).await?;
        let mut projection = ReplyProjection::new();
        projection.replace(items)?;
        projection.mark_covered();
        if terminal {
            projection.mark_history_terminal();
        }
        self.observed_state = projection.terminal();
        self.projection = Some(projection);
        self.refresh_current()?;
        Ok(())
    }

    pub(super) async fn reconnect(&mut self, runtime: &StudioRuntime) -> Result<(), FinalError> {
        self.current_watch
            .close()
            .await
            .map_err(|error| read_failure("bot current watch close failed", error))?;
        self.current_reader
            .close()
            .await
            .map_err(|error| read_failure("bot current reader close on reconnect failed", error))?;
        self.history_reader.close().await;
        let thread_id = self.view.state.thread.id.clone();
        let reopened = Self::open(runtime, &thread_id).await?;
        let input_id = self.input_id.clone();
        let turn_id = self.turn_id.clone();
        *self = reopened;
        self.input_id = input_id;
        self.turn_id = turn_id;
        self.ensure_coverage().await
    }

    pub(super) async fn during<T>(
        &mut self,
        future: impl Future<Output = T>,
        action_cancel: Option<&CancellationToken>,
    ) -> (T, Option<FinalError>) {
        tokio::pin!(future);
        let mut failure = None;
        loop {
            let event = tokio::select! {
                result = &mut future => return (result, failure),
                event = self.receive(), if failure.is_none() => event,
            };
            if let Err(error) = event {
                self.current_watch.request_close();
                if let Some(cancel) = action_cancel {
                    cancel.cancel();
                }
                failure = Some(error);
            }
        }
    }

    pub(super) async fn receive(&mut self) -> Result<(), FinalError> {
        let frame = self
            .current_watch
            .next()
            .await
            .map_err(|error| read_failure("bot current watch failed", error))?
            .ok_or_else(|| gap("bot current watch ended before reply completed"))?;
        match frame {
            CurrentFrame::Reset { view } => self.view = *view,
            CurrentFrame::Projection {
                revision,
                projection,
            } if revision.owner_id == self.view.revision.owner_id => {
                self.view.projection = *projection;
            }
            CurrentFrame::Notification { revision, .. }
                if revision.owner_id == self.view.revision.owner_id =>
            {
                self.view = self
                    .current_reader
                    .snapshot(demand())
                    .await
                    .map_err(|error| read_failure("bot current snapshot failed", error))?;
            }
            _ => {
                self.view = self
                    .current_reader
                    .snapshot(demand())
                    .await
                    .map_err(|error| read_failure("bot current snapshot reset failed", error))?;
            }
        }
        self.refresh_current()?;
        if self.turn_id.is_some() {
            self.ensure_coverage().await?;
        }
        Ok(())
    }

    fn refresh_current(&mut self) -> Result<(), FinalError> {
        let Some(turn_id) = self.turn_id.as_deref() else {
            return Ok(());
        };
        let Some(projection) = &mut self.projection else {
            return Ok(());
        };
        let active = self
            .view
            .projection
            .active_turn
            .as_ref()
            .is_some_and(|turn| turn.id == turn_id);
        let previews = self
            .view
            .projection
            .atoms
            .iter()
            .flat_map(|atom| {
                self.view
                    .projection
                    .previews
                    .iter()
                    .filter_map(move |body| activity_preview(atom, body, turn_id))
                    .map(move |text| (atom.id.clone(), text))
            })
            .collect::<Vec<_>>();
        projection.set_activity(active, previews)?;
        projection.validate_budget()?;
        Ok(())
    }

    pub(super) async fn close(&mut self) -> Result<(), FinalError> {
        self.current_watch.request_close();
        let mut errors = Vec::new();
        if let Err(error) = self.current_watch.close().await {
            errors.push(read_failure("bot current watch close failed", error));
        }
        if let Err(error) = self.current_reader.close().await {
            errors.push(read_failure("bot current reader close failed", error));
        }
        self.history_reader.close().await;
        match errors.len() {
            0 => Ok(()),
            1 => Err(errors.into_iter().next().expect("one close error")),
            _ => Err(FinalError::Attention(format!(
                "reply close failed on multiple current owners: {errors:?}"
            ))),
        }
    }
}
