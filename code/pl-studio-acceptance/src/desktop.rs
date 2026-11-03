//! Automatic desktop runner.
//!
//! Desktop presets prepare the shared isolated environment, then invoke the
//! official Flutter integration_test runner. Assertions and discovery belong
//! to Flutter. The current automatic desktop presets are `wait-events`,
//! `conversation-read-work`, `question-history`, `realtime-presentation` and
//! `sidebar-query`.

#![allow(dead_code)]
