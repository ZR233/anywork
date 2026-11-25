//! 统一关机阶段编排与退出期限。
//!
//! 严格关闭（进程内 server）与应用退出共用同一套阶段编排，只按
//! `ShutdownBudget` 与调用契约区分：严格路径要求真实 `Clean`，退出路径接受 `Degraded`
//! 并按剩余期限终止。任何阶段失败都不阻断其余彼此独立的安全清理。
//!
//! 本次退出只在首个调用者处固定一个绝对期限；退出编排运行在真正 owned 的 spawned task 上，
//! 即使等待方超时或全部离开也会被运行时继续 poll 到结束。每个阶段先广播取消（或 abort），
//! 再做有界 join；等待超时只放弃等待，从不 drop 在途的存储 / writer / JoinHandle。

mod diagnostics;
mod orchestrator;
mod run;
mod stages;

pub(super) use diagnostics::redacted_chain;
pub(crate) use run::{ShutdownLatch, ShutdownRun};
pub(crate) use stages::ServiceStopSlots;

#[cfg(test)]
mod member_mcp_tests;
#[cfg(test)]
mod observer_tests;
