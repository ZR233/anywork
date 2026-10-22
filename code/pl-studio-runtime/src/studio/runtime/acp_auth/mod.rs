//! ACP 认证 owner 的目录页。
//!
//! 子模块职责（唯一 canonical 路径，不复制第二套事实）：
//! - `registry`：owner 内唯一可变事实——独立 revision、已观察的 Settings 水位、关闭闸门、
//!   连接身份、操作槽位与已受理身份，以及全部状态转换。接入记录的创建/退役只发生在 Settings
//!   提交观察里。
//! - `admission`：认证命令入口（受理/取消/关闭回收）与 Settings 提交观察者接线；受理复用
//!   `ConfigRuntime` 的 Settings command 序列化边界。
//! - `projection`：官方模板与 Settings 接入视图的只读投影；陈旧快照返回类型化错误，不补造。
//! - `mapping`：`pl-acp` 结果到产品 wire 的穷尽映射、安全失败文案与探测目录准备。
//! - `operation`：单次操作的 supervisor（IO 装配、进展、取消、收尾、终态）。
//! - `worker`：官方进程 owner（受监督启动、管道、有界 stderr、收尾三态）。
//!
//! 只读查询、订阅与 Settings 页面出现都不会启动外部程序：只有显式 start 命令才装配 IO 并派生
//! 进程。终态只在协议结束且物理资源确认退出后发布；迟到结果、已退役接入与旧代次结果一律丢弃
//! （见 design/27 §27.2–27.4、design/18 §18.2）。

mod admission;
mod mapping;
mod operation;
mod projection;
mod registry;
mod worker;

pub(crate) use admission::AcpAuthRuntime;
pub(crate) use projection::acp_account_catalog;
