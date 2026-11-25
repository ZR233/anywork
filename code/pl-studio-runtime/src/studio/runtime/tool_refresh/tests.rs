use super::*;
use crate::thread_assembler::ThreadAssemblyError;

#[test]
fn cancelled_or_superseded_catalog_refresh_does_not_settle_the_attempt() {
    let cases = [
        (
            "cancelled preparation",
            anyhow::Error::new(ThreadAssemblyError::from(ThreadError::Cancelled)),
            true,
        ),
        (
            "cancelled installation",
            anyhow::Error::new(std::sync::Arc::new(ThreadError::Cancelled)),
            true,
        ),
        (
            "superseded candidate",
            anyhow::Error::new(ThreadError::StaleRuntimeBundle),
            true,
        ),
        (
            "changed context",
            anyhow::Error::new(ThreadError::ContextConflict {
                expected: 1,
                actual: 2,
            }),
            true,
        ),
        (
            "invalidated workspace binding",
            anyhow::Error::new(ThreadAssemblyError::InvalidatedBinding(
                "project target disappeared".into(),
            )),
            false,
        ),
        (
            "untyped error with the same message",
            anyhow::anyhow!("request cancelled"),
            false,
        ),
    ];
    for (name, error, interrupted) in cases {
        assert_eq!(refresh_was_interrupted(&error), interrupted, "{name}");
    }
}
