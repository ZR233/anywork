//! Timeline 历史与实时正文统一由权威 ChatView 窗口交付（`handlers/chat.rs`）；FRB 不再
//! 暴露 SQL 分页/按 identity 读条目的旁路入口。HTTP 的 `/timeline` 只读分页仍由
//! `pl-studio-server` 独立提供，不经过这条 GUI 契约。
