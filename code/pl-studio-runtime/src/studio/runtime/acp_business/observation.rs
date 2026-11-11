use pl_acp::session::{Event, Observer};
use pl_protocol::studio::*;
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
    ended: bool,
}

impl AcpSessionObservation {
    pub(super) fn new(observer: Observer, completion: AcpSessionCompletion) -> Self {
        Self {
            observer,
            completion,
            ended: false,
        }
    }

    pub async fn recv(&mut self) -> Option<AcpSessionEvent> {
        if self.ended {
            return None;
        }
        let event = self.observer.recv().await;
        Some(match event {
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
            Some(Event::Update(update)) => AcpSessionEvent::Update { update },
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
        })
    }
}
