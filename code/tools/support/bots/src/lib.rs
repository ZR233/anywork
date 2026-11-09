//! Bot service facts. Credentials and project authorization remain in the service owner.
use serde::Serialize;
use std::{error::Error, future::Future};

#[derive(Debug)]
pub struct Bot<C> {
    pub id: String,
    pub name: String,
    pub connection: C,
    pub tools_enabled: bool,
}
#[derive(Debug)]
pub struct Page<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}
#[derive(Debug)]
pub struct ReadMessages {
    pub bot_id: String,
    pub chat_id: String,
    pub start_time: Option<i64>,
    pub end_time: Option<i64>,
    pub cursor: Option<String>,
    pub limit: Option<u32>,
}
#[derive(Debug)]
pub struct Sent<S, R> {
    pub status: SendStatus,
    pub segments: Vec<S>,
    pub receipt: R,
}
#[derive(Debug, Clone, Copy, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum SendStatus {
    Succeeded,
    Partial,
    Rejected,
    Unknown,
}

/// Only authorized bot queries and text sending; no tool output or configuration access.
pub trait BotSessionHost: Send + Sync + std::fmt::Debug + 'static {
    type Error: Error + Send + Sync + 'static;
    type Connection: Send + 'static;
    type Conversation: Send + 'static;
    type Message: Send + 'static;
    type Segment: Send + 'static;
    type Receipt: Send + 'static;
    fn list_bots(
        &self,
        scope: &str,
    ) -> impl Future<Output = Result<Vec<Bot<Self::Connection>>, Self::Error>> + Send;
    fn list_conversations(
        &self,
        scope: &str,
        bot_id: String,
        cursor: Option<String>,
        limit: Option<u32>,
    ) -> impl Future<Output = Result<Page<Self::Conversation>, Self::Error>> + Send;
    fn read_messages(
        &self,
        scope: &str,
        request: ReadMessages,
    ) -> impl Future<Output = Result<Page<Self::Message>, Self::Error>> + Send;
    fn send_message(
        &self,
        scope: &str,
        operation_id: String,
        bot_id: String,
        chat_id: String,
        text: String,
    ) -> impl Future<Output = Result<Sent<Self::Segment, Self::Receipt>, Self::Error>> + Send;
}
