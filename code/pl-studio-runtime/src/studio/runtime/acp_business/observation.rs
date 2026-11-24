use crate::protocol::*;
use pl_acp::session::{Event, Observer};
use tokio::sync::watch;

use super::projection;

pub(super) type Publication = Option<Result<(), AcpBusinessFailure>>;

/// A repeatable borrow of the original preparation's product publication result.
/// This does not observe protocol open or consume any SDK updates.
#[derive(Clone)]
pub struct AcpSessionCompletion {
    pub(super) publication: watch::Receiver<Publication>,
}

impl AcpSessionCompletion {
    pub async fn wait(&self) -> Result<(), AcpBusinessFailure> {
        let mut publication = self.publication.clone();
        loop {
            if let Some(result) = publication.borrow_and_update().clone() {
                return result;
            }
            publication
                .changed()
                .await
                .map_err(|_| projection::preparation("ACP preparation stopped"))?;
        }
    }
}

/// Directly consumes the one SDK window, with no forwarding queue. Ready is
/// delivered only after the original Session preparation has published membership.
pub struct AcpSessionObservation {
    pub(super) observer: Observer,
    completion: AcpSessionCompletion,
    workflow_updates: Option<watch::Receiver<Option<AcpWorkflowStateSnapshot>>>,
    ended: bool,
}

impl AcpSessionObservation {
    pub(super) fn new(
        observer: Observer,
        completion: AcpSessionCompletion,
        mut workflow_updates: Option<watch::Receiver<Option<AcpWorkflowStateSnapshot>>>,
    ) -> Self {
        if let Some(rx) = workflow_updates.as_mut() {
            let _ = rx.borrow_and_update();
        }
        Self {
            observer,
            completion,
            workflow_updates,
            ended: false,
        }
    }

    pub async fn recv(&mut self) -> Option<AcpSessionEvent> {
        loop {
            if self.ended {
                return None;
            }
            let event = if let Some(workflow_rx) = self.workflow_updates.as_mut() {
                tokio::select! {
                    biased;
                    changed = workflow_rx.changed() => {
                        match changed {
                            Ok(()) => {
                                if let Some(state) = workflow_rx.borrow().clone() {
                                    return Some(AcpSessionEvent::WorkflowStateUpdated {
                                        state: Box::new(state),
                                    });
                                }
                                continue;
                            }
                            Err(_) => {
                                self.workflow_updates = None;
                                continue;
                            }
                        }
                    }
                    event = self.observer.recv() => event,
                }
            } else {
                self.observer.recv().await
            };
            return Some(match event {
                Some(Event::Initialized {
                    capabilities,
                    server_info,
                }) => AcpSessionEvent::Initialized {
                    capabilities,
                    server_info: server_info.map(projection::server_info),
                },
                Some(Event::Ready(response)) => match self.completion.wait().await {
                    Ok(()) => AcpSessionEvent::Ready { response },
                    Err(error) => {
                        self.ended = true;
                        AcpSessionEvent::Failed { error }
                    }
                },
                Some(Event::Failed(error)) => {
                    self.ended = true;
                    let error = self
                        .completion
                        .wait()
                        .await
                        .err()
                        .unwrap_or_else(|| projection::failure(error));
                    AcpSessionEvent::Failed { error }
                }
                Some(Event::Update(update, performance)) => AcpSessionEvent::Update {
                    update,
                    text_performance: performance.map(projection::text_performance),
                },
                Some(Event::Permission { id, request }) => AcpSessionEvent::Permission {
                    id: AcpPermissionId {
                        instance: id.instance,
                        sequence: id.sequence,
                    },
                    request,
                },
                Some(Event::Configured(response)) => AcpSessionEvent::Configured { response },
                Some(Event::ModeSet(mode_id)) => AcpSessionEvent::ModeSet { mode_id },
                Some(Event::Completed(value)) => AcpSessionEvent::Completed {
                    completed: projection::completed(value),
                },
                Some(Event::Gap(gap)) => {
                    self.ended = true;
                    AcpSessionEvent::Gap {
                        gap: projection::gap(gap),
                    }
                }
                None => {
                    self.ended = true;
                    match self.completion.wait().await {
                        Err(error) => AcpSessionEvent::Failed { error },
                        Ok(()) => return None,
                    }
                }
            });
        }
    }
}
