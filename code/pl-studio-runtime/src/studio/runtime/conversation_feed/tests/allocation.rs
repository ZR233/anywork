//! Test-only allocation requests made while polling the real feed receive future.
//!
//! This is gross requested volume (including successful realloc's new size),
//! not resident memory, physical IO, or an exact serialization count. Other
//! tasks polled later, or work dispatched to another thread, are outside a poll.
use std::{
    alloc::{GlobalAlloc, Layout, System},
    cell::Cell,
    future::{Future, poll_fn},
};

#[derive(Clone, Copy, Debug, Default)]
pub(super) struct Sample {
    pub bytes: usize,
    overflow: bool,
    unavailable: bool,
}

impl Sample {
    fn record(&mut self, bytes: usize) {
        match self.bytes.checked_add(bytes) {
            Some(total) => self.bytes = total,
            None => {
                self.bytes = usize::MAX;
                self.overflow = true;
            }
        }
    }

    pub(super) fn add(&mut self, sample: Self) {
        self.record(sample.bytes);
        self.overflow |= sample.overflow;
        self.unavailable |= sample.unavailable;
    }

    pub(super) fn validate(self) -> anyhow::Result<Self> {
        // Run only after leaving the observer, never inside an allocator method.
        anyhow::ensure!(!self.overflow, "allocation request byte counter overflowed");
        anyhow::ensure!(!self.unavailable, "allocation observer TLS is unavailable");
        Ok(self)
    }
}

#[derive(Clone, Copy, Default)]
struct Observer {
    enabled: bool,
    sample: Sample,
}

std::thread_local! {
    // Const initialization and scalar Cell operations require no allocator.
    // try_with also permits ordinary allocations during thread-local teardown.
    static OBSERVER: Cell<Observer> = const {
        Cell::new(Observer {
            enabled: false,
            sample: Sample { bytes: 0, overflow: false, unavailable: false },
        })
    };
}

fn record(bytes: usize) {
    let _ = OBSERVER.try_with(|slot| {
        let mut observer = slot.get();
        if observer.enabled {
            observer.sample.record(bytes);
            slot.set(observer);
        }
    });
}

struct ObservedSystem;

#[global_allocator]
static ALLOCATOR: ObservedSystem = ObservedSystem;

// SAFETY: All four operations delegate to System with the caller's unchanged
// pointer, Layout and new size; returned pointers/nulls are returned unchanged.
// Every allocation handled here therefore has the same System provenance on
// deallocation/reallocation. The observer never accesses allocated memory,
// changes allocation failures, or frees anything. Its only operations are
// try_with, scalar Cell reads/writes and checked integer arithmetic: no locks,
// formatting, allocation, assertions, or unwinding inside allocator callbacks.
unsafe impl GlobalAlloc for ObservedSystem {
    unsafe fn alloc(&self, layout: Layout) -> *mut u8 {
        // SAFETY: GlobalAlloc's caller supplies the valid nonzero Layout.
        let pointer = unsafe { System.alloc(layout) };
        if !pointer.is_null() {
            record(layout.size());
        }
        pointer
    }

    unsafe fn alloc_zeroed(&self, layout: Layout) -> *mut u8 {
        // SAFETY: Preserve the caller's Layout and System's zeroing contract.
        let pointer = unsafe { System.alloc_zeroed(layout) };
        if !pointer.is_null() {
            record(layout.size());
        }
        pointer
    }

    unsafe fn dealloc(&self, pointer: *mut u8, layout: Layout) {
        // SAFETY: The caller supplies a live allocation and its original Layout.
        // All allocations above came from System, including outside a sample.
        unsafe { System.dealloc(pointer, layout) };
    }

    unsafe fn realloc(&self, pointer: *mut u8, layout: Layout, new_size: usize) -> *mut u8 {
        // SAFETY: Preserve the live System allocation, old Layout and valid new
        // size. System alone moves/releases it; null leaves the old block live.
        let next = unsafe { System.realloc(pointer, layout, new_size) };
        if !next.is_null() {
            record(new_size);
        }
        next
    }
}

struct PollScope {
    previous: Observer,
    active: bool,
}

impl PollScope {
    fn enter() -> anyhow::Result<Self> {
        let previous = OBSERVER
            .try_with(|slot| {
                slot.replace(Observer {
                    enabled: true,
                    sample: Sample::default(),
                })
            })
            .map_err(|_| anyhow::anyhow!("allocation observer TLS is unavailable"))?;
        Ok(Self {
            previous,
            active: true,
        })
    }

    fn restore(&mut self) -> Option<Sample> {
        if !self.active {
            return None;
        }
        self.active = false;
        OBSERVER
            .try_with(|slot| {
                let sample = slot.get().sample;
                let mut previous = self.previous;
                if previous.enabled {
                    previous.sample.add(sample);
                }
                slot.set(previous);
                sample
            })
            .ok()
    }

    fn finish(mut self) -> Sample {
        self.restore().unwrap_or(Sample {
            unavailable: true,
            ..Sample::default()
        })
    }
}

impl Drop for PollScope {
    fn drop(&mut self) {
        // Also restores a previously enabled outer scope if the future panics.
        // No fallible reporting or unwinding is allowed in this cleanup.
        let _ = self.restore();
    }
}

pub(super) async fn measure<F: Future>(future: F) -> anyhow::Result<(F::Output, Sample)> {
    // Pinning/setup and all assertion/serialization work stay outside the scope.
    let mut future = Box::pin(future);
    let mut total = Sample::default();
    let output = poll_fn(|context| {
        let scope = match PollScope::enter() {
            Ok(scope) => scope,
            Err(error) => return std::task::Poll::Ready(Err(error)),
        };
        let result = future.as_mut().poll(context);
        total.add(scope.finish());
        result.map(Ok)
    })
    .await?;
    Ok((output, total.validate()?))
}

#[test]
fn observation_scope_restores_after_pending_unwind_and_nested_poll() {
    use std::{panic::AssertUnwindSafe, task::Context};
    let waker = futures::task::noop_waker();
    let mut context = Context::from_waker(&waker);
    let enabled = || OBSERVER.with(|slot| slot.get().enabled);

    let mut pending = Box::pin(measure(std::future::pending::<()>()));
    assert!(pending.as_mut().poll(&mut context).is_pending());
    assert!(!enabled());

    let outer = PollScope::enter().unwrap();
    assert!(pending.as_mut().poll(&mut context).is_pending());
    assert!(enabled(), "nested poll lost its outer observation scope");
    drop(outer);
    assert!(!enabled());

    let mut panicking = Box::pin(measure(async { panic!("poll unwind fixture") }));
    let result =
        std::panic::catch_unwind(AssertUnwindSafe(|| panicking.as_mut().poll(&mut context)));
    assert!(result.is_err());
    assert!(!enabled(), "unwinding left allocation observation enabled");
}

#[test]
fn another_test_thread_does_not_inherit_the_observation_scope() {
    let outer = PollScope::enter().unwrap();
    std::thread::spawn(|| {
        assert!(!OBSERVER.with(|slot| slot.get().enabled));
        let own = PollScope::enter().unwrap();
        assert!(OBSERVER.with(|slot| slot.get().enabled));
        drop(own);
        assert!(!OBSERVER.with(|slot| slot.get().enabled));
    })
    .join()
    .unwrap();
    assert!(OBSERVER.with(|slot| slot.get().enabled));
    drop(outer);
    assert!(!OBSERVER.with(|slot| slot.get().enabled));
}
