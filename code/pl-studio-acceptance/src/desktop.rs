//! Automatic desktop runner.
//!
//! Desktop presets prepare the shared isolated environment, then invoke the
//! official Flutter integration_test runner. Assertions and discovery belong
//! to Flutter. The current automatic desktop presets are `wait-events` and
//! `conversation-read-work`.

#![allow(dead_code)]
