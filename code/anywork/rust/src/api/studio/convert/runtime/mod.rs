//! Studio runtime 域模型到 FRB DTO 的桥接目录页。
//!
//! 按域拆分：`snapshot` 桥接关闭报告，`health` 桥接 MCP/LSP/agent 观测状态。

mod bots;
mod health;
mod observed;
mod persistence;
mod session_costs;
mod snapshot;
mod updater;

pub(crate) use bots::*;
pub(crate) use health::*;
pub(crate) use observed::*;
pub(crate) use persistence::*;
pub(crate) use session_costs::*;
pub(crate) use snapshot::*;
pub(crate) use updater::*;
