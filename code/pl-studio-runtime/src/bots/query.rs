use super::SendAuthority;
use super::config::BotConfigFile;
use super::owner::{BotRuntime, ManagedBot};
use super::protocol::error::{FeishuError, FeishuErrorKind};
use super::protocol::im::{FeishuIm, to_product_message};
use crate::protocol::*;

impl BotRuntime {
    pub async fn list_conversations(
        &self,
        bot_id: &str,
        cursor: Option<&str>,
        limit: Option<u32>,
    ) -> Result<BotConversationPage, FeishuError> {
        let managed = self.managed(bot_id).await?;
        let config = managed.config.lock().await.clone();
        let mut parsed = decode_cursor(cursor, bot_id)?;
        let page_size = limit.unwrap_or(20).clamp(1, 50);
        let directs = if parsed.kind == CursorKind::Directs {
            let rows = managed.store.list_observed_directs().await?;
            if rows.is_empty() {
                parsed = ParsedCursor {
                    kind: CursorKind::Groups,
                    token: None,
                };
            }
            rows
        } else {
            Vec::new()
        };
        let mut conversations = Vec::new();
        let next = match parsed.kind {
            CursorKind::Groups => {
                let token = self.token(&managed, &config).await?;
                let page = FeishuIm::new(self.inner.http.clone())
                    .list_chats(&token, parsed.token.as_deref(), page_size)
                    .await?;
                conversations.extend(page.chats.into_iter().map(|chat| BotConversation {
                    chat_id: chat.chat_id,
                    kind: chat.kind,
                    source: BotConversationSource::RemoteGroup,
                    name: chat.name,
                    last_observed_at: None,
                    thread_binding: None,
                }));
                if page.has_more {
                    Some(encode_cursor(
                        bot_id,
                        CursorKind::Groups,
                        page.page_token.as_deref(),
                    ))
                } else {
                    None
                }
            }
            CursorKind::Directs => {
                let start = parsed
                    .token
                    .as_deref()
                    .map(|token| {
                        token.parse::<usize>().map_err(|_| {
                            FeishuError::new(
                                FeishuErrorKind::Rejected,
                                "direct conversation cursor is not a valid page offset",
                                false,
                                None,
                            )
                        })
                    })
                    .transpose()?
                    .unwrap_or(0);
                let end = start.saturating_add(page_size as usize);
                let page = directs
                    .get(start..)
                    .unwrap_or(&[])
                    .iter()
                    .take(page_size as usize);
                let remaining = directs.len().saturating_sub(end);
                conversations.extend(page.cloned().map(|row| BotConversation {
                    chat_id: row.chat_id,
                    kind: BotConversationKind::Direct,
                    source: BotConversationSource::ObservedDirect,
                    name: row.name,
                    last_observed_at: Some(row.last_observed_at),
                    thread_binding: None,
                }));
                if remaining == 0 {
                    Some(encode_cursor(bot_id, CursorKind::Groups, None))
                } else {
                    Some(encode_cursor(
                        bot_id,
                        CursorKind::Directs,
                        Some(&end.to_string()),
                    ))
                }
            }
        };
        for conversation in &mut conversations {
            conversation.thread_binding = Some(
                self.conversation_binding(
                    &managed,
                    &config.id,
                    &config.workspace_id,
                    &conversation.chat_id,
                )
                .await?,
            );
        }
        Ok(BotConversationPage {
            bot_id: bot_id.to_string(),
            conversations,
            next_cursor: next,
        })
    }

    pub async fn read_messages(
        &self,
        bot_id: &str,
        chat_id: &str,
        start_time: Option<i64>,
        end_time: Option<i64>,
        cursor: Option<&str>,
        limit: Option<u32>,
    ) -> Result<BotMessagePage, FeishuError> {
        let managed = self.managed(bot_id).await?;
        let config = managed.config.lock().await.clone();
        let membership = self.prepare_chat_access(&managed, &config, chat_id).await?;
        self.authorize_chat(&config, SendAuthority::Owner, &membership)?;
        let token = self.token(&managed, &config).await?;
        let page_token = decode_history_cursor(cursor, bot_id, chat_id, start_time, end_time)?;
        let (messages, next) = FeishuIm::new(self.inner.http.clone())
            .list_messages(
                &token,
                chat_id,
                start_time,
                end_time,
                page_token.as_deref(),
                limit.unwrap_or(20),
            )
            .await?;
        Ok(BotMessagePage {
            bot_id: bot_id.to_string(),
            chat_id: chat_id.to_string(),
            messages: messages.iter().map(to_product_message).collect(),
            next_cursor: next
                .map(|token| encode_history_cursor(bot_id, chat_id, start_time, end_time, &token)),
        })
    }

    pub async fn authorized_bots(&self, workspace_id: &str) -> Vec<BotSnapshot> {
        let previous = self.snapshot().await;
        self.list_snapshots(&previous)
            .await
            .into_iter()
            .filter(|bot| bot.workspace_id == workspace_id && bot.tools_enabled)
            .collect()
    }

    pub(super) async fn prepare_auto_reply_token(
        &self,
        managed: &ManagedBot,
        chat_id: &str,
    ) -> Result<String, FeishuError> {
        let config = managed.config.lock().await.clone();
        let membership = self.prepare_chat_access(managed, &config, chat_id).await?;
        self.authorize_chat(&config, SendAuthority::AutoReply, &membership)?;
        self.token(managed, &config).await
    }

    pub(super) fn authorize_chat(
        &self,
        config: &BotConfigFile,
        authority: SendAuthority,
        membership: &ChatAuthorizer,
    ) -> Result<(), FeishuError> {
        if matches!(authority, SendAuthority::Tool { .. }) && !config.tools_enabled {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "project tools are not enabled for this bot",
                false,
                None,
            ));
        }
        if let SendAuthority::Tool { workspace_id } = &authority
            && config.workspace_id != *workspace_id
        {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "bot is not authorized for this project",
                false,
                None,
            ));
        }
        if membership.covers() {
            Ok(())
        } else {
            Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "chat is not an authorized group or observed direct conversation",
                false,
                None,
            ))
        }
    }

    /// 回读既有结果的本地来源授权：只读当前机器人的工具授权标量，不联网、不读 keyring。
    /// Tool 来源不得因重放绕过撤销的项目工具授权；Owner 与已受理入站回复维持其原来源语义。
    pub(super) async fn authorize_replay_source(
        &self,
        managed: &ManagedBot,
        authority: &SendAuthority,
    ) -> Result<(), FeishuError> {
        let SendAuthority::Tool { workspace_id } = authority else {
            return Ok(());
        };
        let current = managed.config.lock().await;
        if !current.tools_enabled {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "project tools are not enabled for this bot",
                false,
                None,
            ));
        }
        if current.workspace_id != *workspace_id {
            return Err(FeishuError::new(
                FeishuErrorKind::Permission,
                "bot is not authorized for this project",
                false,
                None,
            ));
        }
        Ok(())
    }

    pub(super) async fn prepare_chat_access(
        &self,
        managed: &ManagedBot,
        config: &BotConfigFile,
        chat_id: &str,
    ) -> Result<ChatAuthorizer, FeishuError> {
        let directs = managed.store.list_observed_directs().await?;
        if directs.iter().any(|row| row.chat_id == chat_id) {
            return Ok(ChatAuthorizer {
                observed_direct: true,
                remote_group: false,
            });
        }
        let token = self.token(managed, config).await?;
        let im = FeishuIm::new(self.inner.http.clone());
        let mut page_token = None;
        loop {
            let page = im.list_chats(&token, page_token.as_deref(), 50).await?;
            if page.chats.iter().any(|chat| chat.chat_id == chat_id) {
                return Ok(ChatAuthorizer {
                    observed_direct: false,
                    remote_group: true,
                });
            }
            if !page.has_more {
                break;
            }
            page_token = page.page_token;
            if page_token.is_none() {
                break;
            }
        }
        Ok(ChatAuthorizer {
            observed_direct: false,
            remote_group: false,
        })
    }
}
#[derive(Clone, Copy, PartialEq, Eq)]
pub(super) struct ChatAuthorizer {
    observed_direct: bool,
    remote_group: bool,
}

impl ChatAuthorizer {
    fn covers(self) -> bool {
        self.observed_direct || self.remote_group
    }
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum CursorKind {
    Groups,
    Directs,
}

struct ParsedCursor {
    kind: CursorKind,
    token: Option<String>,
}

fn decode_cursor(cursor: Option<&str>, bot_id: &str) -> Result<ParsedCursor, FeishuError> {
    let Some(cursor) = cursor.filter(|value| !value.is_empty()) else {
        return Ok(ParsedCursor {
            kind: CursorKind::Directs,
            token: None,
        });
    };
    let mut parts = cursor.splitn(3, ':');
    let cursor_bot = parts.next().unwrap_or_default();
    let kind = parts.next().unwrap_or_default();
    let token = parts
        .next()
        .filter(|value| !value.is_empty())
        .map(str::to_string);
    if cursor_bot != bot_id {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "conversation cursor does not match bot",
            false,
            None,
        ));
    }
    Ok(ParsedCursor {
        kind: match kind {
            "directs" => CursorKind::Directs,
            _ => CursorKind::Groups,
        },
        token,
    })
}

fn encode_cursor(bot_id: &str, kind: CursorKind, token: Option<&str>) -> String {
    let label = match kind {
        CursorKind::Groups => "groups",
        CursorKind::Directs => "directs",
    };
    match token {
        Some(token) => format!("{bot_id}:{label}:{token}"),
        None => format!("{bot_id}:{label}:"),
    }
}

fn decode_history_cursor(
    cursor: Option<&str>,
    bot_id: &str,
    chat_id: &str,
    start_time: Option<i64>,
    end_time: Option<i64>,
) -> Result<Option<String>, FeishuError> {
    let Some(cursor) = cursor.filter(|value| !value.is_empty()) else {
        return Ok(None);
    };
    let mut parts = cursor.splitn(6, ':');
    let cursor_bot = parts.next().unwrap_or_default();
    let kind = parts.next().unwrap_or_default();
    let cursor_chat = parts.next().unwrap_or_default();
    let cursor_start = parts.next().unwrap_or_default();
    let cursor_end = parts.next().unwrap_or_default();
    let token = parts.next().filter(|value| !value.is_empty());
    let expected_start = start_time
        .map(|value| value.to_string())
        .unwrap_or_default();
    let expected_end = end_time.map(|value| value.to_string()).unwrap_or_default();
    if cursor_bot != bot_id
        || kind != "history"
        || cursor_chat != chat_id
        || cursor_start != expected_start
        || cursor_end != expected_end
    {
        return Err(FeishuError::new(
            FeishuErrorKind::Rejected,
            "history cursor does not match bot, chat and time range",
            false,
            None,
        ));
    }
    Ok(token.map(str::to_string))
}

fn encode_history_cursor(
    bot_id: &str,
    chat_id: &str,
    start_time: Option<i64>,
    end_time: Option<i64>,
    token: &str,
) -> String {
    format!(
        "{bot_id}:history:{chat_id}:{}:{}:{token}",
        start_time
            .map(|value| value.to_string())
            .unwrap_or_default(),
        end_time.map(|value| value.to_string()).unwrap_or_default()
    )
}
