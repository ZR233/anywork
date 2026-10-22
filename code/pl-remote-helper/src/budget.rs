//! Shared, demand-driven ownership of resident transport bytes.
use pl_protocol::remote::RemoteAllocation;
use std::collections::VecDeque;
use std::io;
use std::sync::{Arc, Mutex};
use tokio::sync::Notify;
use tokio_util::sync::CancellationToken;

/// HTTP/2's minimum maximum-frame-size, used as the indivisible progress unit.
pub const FRAME_BYTES: usize = 16_384;
const HTTP_WINDOW_MAX: usize = (1 << 31) - 1;

/// Relative resource policy; no per-thread or per-command capacity is duplicated.
#[derive(Debug, Clone, Copy)]
pub struct ResourcePolicy {
    /// Fraction of currently available memory this runtime may borrow.
    pub available_memory_divisor: usize,
    /// Optional administrator-provided ceiling, in addition to OS constraints.
    pub resident_ceiling: Option<usize>,
}

impl Default for ResourcePolicy {
    fn default() -> Self {
        Self {
            available_memory_divisor: 16,
            resident_ceiling: None,
        }
    }
}

impl ResourcePolicy {
    /// Samples the OS, including the effective Linux cgroup memory limit.
    pub fn allocation(self) -> io::Result<RemoteAllocation> {
        if self.available_memory_divisor == 0 {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "memory share divisor must be positive",
            ));
        }
        let mut system = sysinfo::System::new();
        system.refresh_memory();
        let mut available = system.available_memory();
        if let Some(group) = system.cgroup_limits() {
            available = available.min(group.free_memory);
        }
        let available = usize::try_from(available).unwrap_or(usize::MAX);
        let resident_bytes = (available / self.available_memory_divisor)
            .min(self.resident_ceiling.unwrap_or(usize::MAX));
        allocation_for_resident(resident_bytes)
    }
}

/// Derives progress quanta and concurrency from a resident-memory grant.
pub fn allocation_for_resident(resident_bytes: usize) -> io::Result<RemoteAllocation> {
    if resident_bytes < FRAME_BYTES * 32 {
        return Err(io::Error::new(
            io::ErrorKind::OutOfMemory,
            "insufficient memory for HTTP/2 progress and cleanup",
        ));
    }
    let fragment_bytes = resident_bytes
        .isqrt()
        .next_power_of_two()
        .max(FRAME_BYTES)
        .min(resident_bytes / 32);
    let connection_window = (resident_bytes / 4).min(HTTP_WINDOW_MAX) as u32;
    let stream_window = fragment_bytes.min(connection_window as usize / 3) as u32;
    let ordinary_operations = (connection_window as usize / stream_window as usize)
        .saturating_sub(1)
        .saturating_div(2)
        .max(1);
    Ok(RemoteAllocation {
        resident_bytes,
        fragment_bytes,
        ordinary_operations,
        stream_window,
        connection_window,
    })
}

#[derive(Debug)]
struct State {
    allocation: RemoteAllocation,
    used: usize,
    peak: usize,
    next: u64,
    connections: usize,
    waiters: VecDeque<Waiting>,
}

#[derive(Debug)]
struct Waiting {
    id: u64,
    bytes: usize,
    bypassed_bytes: usize,
}

#[derive(Debug)]
struct Inner {
    state: Mutex<State>,
    changed: Notify,
}

#[derive(Debug, Clone)]
pub struct ResourceBudget(Arc<Inner>);

impl ResourceBudget {
    pub fn new(allocation: RemoteAllocation) -> io::Result<Self> {
        validate(allocation)?;
        Ok(Self(Arc::new(Inner {
            state: Mutex::new(State {
                allocation,
                used: 0,
                peak: 0,
                next: 0,
                connections: 0,
                waiters: VecDeque::new(),
            }),
            changed: Notify::new(),
        })))
    }

    pub fn allocation(&self) -> RemoteAllocation {
        self.0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .allocation
    }

    pub fn resize(&self, allocation: RemoteAllocation) -> io::Result<()> {
        validate(allocation)?;
        self.0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .allocation = allocation;
        self.0.changed.notify_waiters();
        Ok(())
    }

    /// A helper connection borrows from the same host budget as all other connections.
    pub fn register_connection(&self) -> ConnectionRegistration {
        self.0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .connections += 1;
        self.0.changed.notify_waiters();
        ConnectionRegistration(self.clone())
    }
    pub fn connection_allocation(&self) -> io::Result<RemoteAllocation> {
        let state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        allocation_for_resident(state.allocation.resident_bytes / state.connections.max(1))
    }
    pub fn changed(&self) -> tokio::sync::futures::Notified<'_> {
        self.0.changed.notified()
    }

    /// Charged ownership and promised credit, with its high-water mark (not physical RSS).
    pub fn usage(&self) -> (usize, usize) {
        let state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        (state.used, state.peak)
    }

    pub fn fragment_bytes(&self) -> usize {
        let state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let demand = state.waiters.len().saturating_add(1);
        (state.allocation.resident_bytes.saturating_sub(state.used) / demand)
            .min(state.allocation.fragment_bytes)
            .max(1)
    }

    /// Immediate reservation for an already-admitted operation. Failure is local to that operation.
    pub fn try_reserve(&self, bytes: usize) -> Option<ByteLease> {
        let mut state = self
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if bytes > state.allocation.resident_bytes.saturating_sub(state.used)
            || state
                .waiters
                .front()
                .is_some_and(|waiter| waiter.bypassed_bytes >= waiter.bytes)
        {
            return None;
        }
        state.used += bytes;
        state.peak = state.peak.max(state.used);
        Some(ByteLease {
            budget: self.clone(),
            bytes,
        })
    }

    /// Event-driven admission. An oversized waiter never blocks a smaller runnable operation.
    /// Requests may reserve only a bounded progress quantum; whole files never enter this queue.
    pub async fn reserve(&self, bytes: usize, stop: &CancellationToken) -> io::Result<ByteLease> {
        self.reserve_with_intent(bytes, stop, self).await
    }

    /// Charge waiting metadata to its runtime owner. A restricted control/data sub-pool must
    /// not reject waiters just because its active exchanges currently use all of its credit.
    /// The parent still bounds the number of admitted lightweight intents, before side effects.
    pub async fn reserve_with_intent(
        &self,
        bytes: usize,
        stop: &CancellationToken,
        intents: &ResourceBudget,
    ) -> io::Result<ByteLease> {
        let intent = {
            let mut state = intents
                .0
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let cost = std::mem::size_of::<Waiting>();
            if cost > state.allocation.resident_bytes.saturating_sub(state.used) {
                return Err(io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "resource intent admission exhausted",
                ));
            }
            state.used += cost;
            state.peak = state.peak.max(state.used);
            ByteLease {
                budget: intents.clone(),
                bytes: cost,
            }
        };
        let ticket = {
            let mut state = self
                .0
                .state
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            if bytes.saturating_add(std::mem::size_of::<Waiting>())
                > state.allocation.resident_bytes
            {
                return Err(io::Error::new(
                    io::ErrorKind::OutOfMemory,
                    "operation exceeds current resource grant",
                ));
            }
            state.next = state
                .next
                .checked_add(1)
                .ok_or_else(|| io::Error::other("budget ticket exhausted"))?;
            let id = state.next;
            state.waiters.push_back(Waiting {
                id,
                bytes,
                bypassed_bytes: 0,
            });
            Waiter {
                budget: self.clone(),
                id,
                _intent: intent,
            }
        };
        loop {
            let changed = self.0.changed.notified();
            tokio::pin!(changed);
            changed.as_mut().enable();
            if stop.is_cancelled() {
                return Err(io::Error::new(
                    io::ErrorKind::Interrupted,
                    "resource admission cancelled",
                ));
            }
            {
                let mut state = self
                    .0
                    .state
                    .lock()
                    .unwrap_or_else(std::sync::PoisonError::into_inner);
                let available = state.allocation.resident_bytes.saturating_sub(state.used);
                if bytes.saturating_add(std::mem::size_of::<Waiting>())
                    > state.allocation.resident_bytes
                {
                    return Err(io::Error::new(
                        io::ErrorKind::OutOfMemory,
                        "resource grant shrank below the pending quantum",
                    ));
                }
                // Permit bounded bypass while the oldest quantum cannot run. Once younger work
                // has consumed one equivalent quantum, released credit accumulates for the oldest.
                let candidate = match state.waiters.front() {
                    Some(head) if head.bypassed_bytes >= head.bytes => {
                        (head.bytes <= available).then_some(head.id)
                    }
                    _ => state
                        .waiters
                        .iter()
                        .find(|waiter| waiter.bytes <= available)
                        .map(|waiter| waiter.id),
                };
                if candidate == Some(ticket.id) {
                    for waiter in state
                        .waiters
                        .iter_mut()
                        .take_while(|waiter| waiter.id != ticket.id)
                    {
                        waiter.bypassed_bytes = waiter.bypassed_bytes.saturating_add(bytes);
                    }
                    state.waiters.retain(|waiter| waiter.id != ticket.id);
                    state.used += bytes;
                    state.peak = state.peak.max(state.used);
                    drop(state);
                    self.0.changed.notify_waiters();
                    return Ok(ByteLease {
                        budget: self.clone(),
                        bytes,
                    });
                }
            }
            tokio::select! {
                _ = changed => {},
                _ = stop.cancelled() => return Err(io::Error::new(io::ErrorKind::Interrupted, "resource admission cancelled")),
            }
        }
    }
}

fn validate(value: RemoteAllocation) -> io::Result<()> {
    if value.fragment_bytes == 0
        || value.ordinary_operations == 0
        || value.fragment_bytes > value.resident_bytes / 2
        || value.stream_window == 0
        || value.stream_window > value.connection_window / 2
        || value.connection_window as usize > HTTP_WINDOW_MAX
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            "invalid resource allocation",
        ));
    }
    Ok(())
}

#[derive(Debug)]
pub struct ByteLease {
    budget: ResourceBudget,
    bytes: usize,
}
impl ByteLease {
    pub fn bytes(&self) -> usize {
        self.bytes
    }
    /// Adjust an existing promise without revoking bytes still owned by its consumer.
    pub fn resize(&mut self, bytes: usize) -> bool {
        let mut state = self
            .budget
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        if bytes > self.bytes
            && bytes - self.bytes > state.allocation.resident_bytes.saturating_sub(state.used)
        {
            return false;
        }
        state.used = state.used - self.bytes + bytes;
        state.peak = state.peak.max(state.used);
        self.bytes = bytes;
        drop(state);
        self.budget.0.changed.notify_waiters();
        true
    }
}
impl Drop for ByteLease {
    fn drop(&mut self) {
        let mut state = self
            .budget
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.used -= self.bytes;
        drop(state);
        self.budget.0.changed.notify_waiters();
    }
}
struct Waiter {
    budget: ResourceBudget,
    id: u64,
    _intent: ByteLease,
}
impl Drop for Waiter {
    fn drop(&mut self) {
        let mut state = self
            .budget
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        state.waiters.retain(|waiter| waiter.id != self.id);
        if state.waiters.is_empty() {
            state.waiters.shrink_to_fit();
        }
        drop(state);
        self.budget.0.changed.notify_waiters();
    }
}

#[derive(Debug)]
pub struct ConnectionRegistration(ResourceBudget);
impl Drop for ConnectionRegistration {
    fn drop(&mut self) {
        self.0
            .0
            .state
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .connections -= 1;
        self.0.0.changed.notify_waiters();
    }
}
