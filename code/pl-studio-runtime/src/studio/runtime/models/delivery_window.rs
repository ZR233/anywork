//! Models/Templates share one two-Data window, one pending slot and actual-send ACK prefix.
use std::collections::VecDeque;
use std::sync::Arc;

use pl_protocol::studio::{StudioError, StudioErrorCode};
use serde::Serialize;

use super::super::read_budget::require_budget;

pub(in crate::studio::runtime) struct DeliveryWindow<M> {
    pub(in crate::studio::runtime) closing: bool,
    pub(in crate::studio::runtime) pending: Option<Arc<M>>,
    claimed: bool,
    control_sent: bool,
    sent: u64,
    acked: u64,
    unacked: VecDeque<(u64, Arc<M>)>,
}

impl<M> DeliveryWindow<M> {
    pub(in crate::studio::runtime) fn new(material: Arc<M>) -> Self {
        Self {
            closing: false,
            pending: Some(material),
            claimed: false,
            control_sent: false,
            sent: 0,
            acked: 0,
            unacked: VecDeque::with_capacity(2),
        }
    }

    // The domain checks its original close fence under the same guard before these operations.
    pub(in crate::studio::runtime) fn claim(
        &mut self,
        domain: &'static str,
    ) -> Result<(), StudioError> {
        if self.claimed {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                format!("{domain} stream was already claimed"),
                false,
            ));
        }
        self.claimed = true;
        Ok(())
    }

    pub(in crate::studio::runtime) fn require_claimed(
        &self,
        domain: &'static str,
    ) -> Result<(), StudioError> {
        if !self.claimed {
            return Err(StudioError::new(
                StudioErrorCode::Conflict,
                format!("{domain} stream has not been claimed"),
                false,
            ));
        }
        Ok(())
    }

    pub(in crate::studio::runtime) fn has_credit(&self) -> bool {
        self.unacked.len() < 2
    }

    /// Caller holds the domain guard across the bounded, synchronous, non-reentrant send. A
    /// failed build/budget/send leaves both the exact pending pin and sent prefix unchanged.
    pub(in crate::studio::runtime) fn deliver<F: Serialize>(
        &mut self,
        domain: &'static str,
        build: impl FnOnce(u64, &M) -> Result<F, StudioError>,
        send: impl FnOnce(F) -> Result<(), StudioError>,
    ) -> Result<Option<Arc<M>>, StudioError> {
        self.require_claimed(domain)?;
        if !self.has_credit() {
            return Ok(None);
        }
        let Some(material) = self.pending.clone() else {
            return Ok(None);
        };
        let sequence = self.sent.checked_add(1).ok_or_else(|| {
            StudioError::new(
                StudioErrorCode::Overloaded,
                format!("{domain} delivery sequence is exhausted"),
                false,
            )
        })?;
        let frame = build(sequence, &material)?;
        require_budget(&frame)?;
        send(frame)?;
        self.pending.take();
        self.sent = sequence;
        self.unacked.push_back((sequence, material.clone()));
        Ok(Some(material))
    }

    pub(in crate::studio::runtime) fn ack_through(
        &mut self,
        delivery_sequence: u64,
        domain: &'static str,
    ) -> Result<(), StudioError> {
        if delivery_sequence == 0 || delivery_sequence <= self.acked {
            return Ok(());
        }
        if delivery_sequence > self.sent {
            return Err(StudioError::new(
                StudioErrorCode::Protocol,
                format!("{domain} ACK exceeds the sent prefix"),
                false,
            ));
        }
        self.acked = delivery_sequence;
        while self
            .unacked
            .front()
            .is_some_and(|(sequence, _)| *sequence <= delivery_sequence)
        {
            self.unacked.pop_front();
        }
        Ok(())
    }

    /// A single ordered control attempt uses no Data credit and does not release material pins.
    pub(in crate::studio::runtime) fn send_control(
        &mut self,
        send: impl FnOnce() -> Result<(), StudioError>,
    ) -> Result<(), StudioError> {
        if self.control_sent {
            return Ok(());
        }
        self.control_sent = true;
        send()
    }
}
