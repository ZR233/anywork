//! 平台入站到同一 Studio Thread 的可靠输入交接。
//!
//! 这里只拥有绑定接续、当前平台准入、附件准备与稳定输入受理；持久输入已可证后立即
//! 交还入站工作，不观察模型、交互、卡片或普通公开投递。工作终态仍由 commands 落盘。

mod admission;
mod binding;
mod error;
mod owner;
mod unsupported;
mod watch;
