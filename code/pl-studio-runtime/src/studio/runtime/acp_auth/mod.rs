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
//! - `connection`：账户级连接代次、共享准备、SDK 与进程监督、物理回收。
//!
//! 只读查询和订阅不启动程序。启动/配置提交后台检查已安装模板，普通 command 按需准备；
//! 操作结束只关闭自身探测会话，账户撤代/退出才回收进程。迟到结果、已退役接入与旧代次结果丢弃
//! （见 design/28 §28.2–28.4、design/18 §18.2）。

mod admission;
mod connection;
mod continuation;
mod mapping;
mod operation;
mod projection;
mod registry;
mod usage;

pub(crate) use admission::AcpAuthRuntime;
pub(crate) use connection::AccountConnection;
pub(crate) use projection::acp_account_catalog;
