//! 额度 session 的报告和回合预算；共享连接不按累计历史字节计费。
use std::time::Duration;

pub(super) const USAGE_QUERY_BUDGET: Duration = Duration::from_secs(60);
pub(super) const USAGE_REPORT_BYTE_BUDGET: usize = 256 * 1024;
