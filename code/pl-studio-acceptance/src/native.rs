//! Native lifecycle runner.
//!
//! Native presets judge real OS exit, restart, second instance, and process
//! tree ownership out of process. Faults use the thin native-test assembly,
//! not capture or release. The current native presets are `shutdown` and
//! `single-instance`.

#![allow(dead_code)]
