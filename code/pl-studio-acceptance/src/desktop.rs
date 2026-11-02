//! Automatic desktop runner.
//!
//! Desktop presets prepare the shared isolated environment, then invoke the
//! official Flutter integration_test runner. Assertions and discovery belong
//! to Flutter. The current automatic desktop preset is `wait-events`.

#![allow(dead_code)]
