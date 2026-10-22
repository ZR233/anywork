use super::error::{FeishuError, FeishuErrorKind};
use super::http::FeishuHttp;
use crate::studio::unix_seconds;
use tokio::sync::{Mutex, OnceCell};

#[derive(Clone)]
pub struct TenantAccessToken {
    pub token: String,
    pub expires_in: i64,
}

/// 每机器人一份共享租户 token：按服务端 expires_in 缓存，并发刷新合并。
///
/// 身份、当前缓存与在途刷新登记共用同一个裁决边界（`state`）。该边界内只做
/// 内存读写：HTTP 刷新在锁外完成，完成后回到同一临界区一次性完成身份核验、
/// 缓存发布与原 cell 释放，避免“清槽未发布”的半提交或旧身份登记到新代。
pub struct TokenLease {
    http: FeishuHttp,
    state: Mutex<TokenState>,
}

struct TokenState {
    app_id: String,
    secret: String,
    generation: u64,
    current: Option<CachedToken>,
    refresh: Option<RefreshCell>,
}

#[derive(Clone)]
struct TokenIdentity {
    app_id: String,
    secret: String,
    generation: u64,
}

#[derive(Clone)]
struct CachedToken {
    token: String,
    expires_at: i64,
    generation: u64,
}

/// 保存本次刷新原 typed 结果：并发 waiter 共享同一错误类别与平台码，
/// 不用字符串重造错误。
type RefreshCell = std::sync::Arc<OnceCell<Result<CachedToken, FeishuError>>>;

impl TokenLease {
    pub fn new(http: FeishuHttp, app_id: String, secret: String) -> Self {
        Self {
            http,
            state: Mutex::new(TokenState {
                app_id,
                secret,
                generation: 1,
                current: None,
                refresh: None,
            }),
        }
    }

    /// 身份、当前缓存与在途刷新登记在同一临界区整体推进：旧代晚到的成功或失败
    /// 结果都不会写入、清理或恢复新代状态。
    pub async fn replace(&self, app_id: String, secret: String) {
        let mut state = self.state.lock().await;
        state.app_id = app_id;
        state.secret = secret;
        state.generation = state.generation.saturating_add(1);
        state.current = None;
        state.refresh = None;
    }

    pub async fn identity_matches(&self, app_id: &str) -> bool {
        let state = self.state.lock().await;
        state.app_id == app_id && !state.secret.is_empty() && state.generation != 0
    }

    pub async fn access_token(&self) -> Result<String, FeishuError> {
        let now = unix_seconds();
        // 身份快照、缓存查看与在途 cell 登记共享同一临界区：replace 不会插在
        // 中间让旧身份登记到新槽，也不会出现“缓存空 + cell 空”的可见窗口。
        let (identity, cell) = {
            let mut state = self.state.lock().await;
            if state.secret.is_empty() || state.app_id.is_empty() {
                return Err(missing_secret_error());
            }
            if let Some(cached) = state.current.as_ref()
                && cached.generation == state.generation
                && cached.expires_at > now + 60
            {
                return Ok(cached.token.clone());
            }
            let identity = TokenIdentity {
                app_id: state.app_id.clone(),
                secret: state.secret.clone(),
                generation: state.generation,
            };
            let cell = match state.refresh.as_ref() {
                Some(existing) => existing.clone(),
                None => {
                    let created = std::sync::Arc::new(OnceCell::new());
                    state.refresh = Some(created.clone());
                    created
                }
            };
            (identity, cell)
        };
        // HTTP 刷新在锁外：同一在途刷新由同一 OnceCell 合并，waiter 共享原结果。
        let outcome = cell
            .get_or_init(|| async { self.refresh_now(&identity).await })
            .await
            .clone();
        // 完成核验、当前缓存发布与原 cell 释放在同一裁决内一次完成：
        // replace 的整组重置与这里线性化，后继不会看到半提交状态。
        let mut state = self.state.lock().await;
        let identity_matches = state.app_id == identity.app_id
            && state.secret == identity.secret
            && state.generation == identity.generation
            && !state.secret.is_empty();
        if !identity_matches {
            // 旧代结果（成功或失败）都不得恢复或改写新认证，也不清理新代 cell。
            return Err(token_superseded_error());
        }
        // 只有仍登记着本 cell 的那个完成者发布缓存并释放它：后继 cell 的登记与
        // 发布受同一锁保护，旧 cell 的慢等待者既不能覆盖也不能清掉后继缓存。
        let owns_cell = state
            .refresh
            .as_ref()
            .is_some_and(|current| std::sync::Arc::ptr_eq(current, &cell));
        match outcome {
            Ok(cached) => {
                if owns_cell {
                    // 同代刷新成功即发布：cache 的新鲜度只由服务端 expires_in 决定，
                    // 不由代次或时间戳大小推断 token 新旧。
                    state.current = Some(cached.clone());
                    state.refresh = None;
                }
                Ok(cached.token)
            }
            Err(error) => {
                if owns_cell {
                    state.refresh = None;
                }
                Err(error)
            }
        }
    }

    async fn refresh_now(&self, identity: &TokenIdentity) -> Result<CachedToken, FeishuError> {
        let refreshed = self
            .http
            .tenant_access_token(&identity.app_id, &identity.secret)
            .await?;
        Ok(CachedToken {
            token: refreshed.token,
            expires_at: unix_seconds().saturating_add(refreshed.expires_in),
            generation: identity.generation,
        })
    }
}

fn missing_secret_error() -> FeishuError {
    FeishuError::new(FeishuErrorKind::Auth, "bot secret is missing", false, None)
}

fn token_superseded_error() -> FeishuError {
    FeishuError::new(
        FeishuErrorKind::Conflict,
        "bot token refresh was superseded",
        true,
        None,
    )
}
