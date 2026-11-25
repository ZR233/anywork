use super::error::{FeishuError, FeishuErrorKind};
use serde::Deserialize;
use serde::de::DeserializeOwned;

pub(super) fn classify_oauth(code: i64, status: reqwest::StatusCode) -> FeishuError {
    let (kind, retryable, message) = match code {
        20002 | 20048 | 20130 | 20140 => (
            FeishuErrorKind::Auth,
            false,
            "Feishu application authentication was rejected",
        ),
        20009 | 20069 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu application is not installed or enabled",
        ),
        20068 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu application scopes were denied",
        ),
        20001 | 20036 | 20063 | 20067 | 20070 => (
            FeishuErrorKind::Rejected,
            false,
            "Feishu OAuth request parameters were rejected",
        ),
        20050 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu OAuth service is unavailable",
        ),
        21001 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu OAuth access control policy denied the token request",
        ),
        _ if status.is_server_error() || status == reqwest::StatusCode::TOO_MANY_REQUESTS => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu OAuth service is unavailable",
        ),
        _ => return classify_open_api(code, None),
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}

pub(super) fn transport(error: reqwest::Error) -> FeishuError {
    let kind = if error.is_timeout() {
        FeishuErrorKind::Timeout
    } else {
        FeishuErrorKind::Transport
    };
    FeishuError::new(kind, "Feishu HTTP request failed", true, None)
}

fn classify_open_api(code: i64, msg: Option<&str>) -> FeishuError {
    let _ = msg;
    let (kind, retryable) = match code {
        99991663 | 99991664 | 1000040343 => (FeishuErrorKind::Auth, false),
        21001 | 99991672 | 230002 | 230006 | 230013 | 230018 | 230027 | 230035 | 230038
        | 230053 | 230073 => (FeishuErrorKind::Permission, false),
        99991400 | 230001 => (FeishuErrorKind::Rejected, false),
        99991404 | 230019 | 230110 | 232009 => (FeishuErrorKind::NotFound, false),
        200740 | 200750 => (FeishuErrorKind::NotFound, false),
        200770 | 300317 => (FeishuErrorKind::Conflict, false),
        200810 | 200850 | 200860 | 300302 | 300309 | 300310 => (FeishuErrorKind::Rejected, false),
        300311 => (FeishuErrorKind::Permission, false),
        1 | 99991429 | 230020 => (FeishuErrorKind::Unavailable, true),
        _ => (FeishuErrorKind::Unavailable, code > 0 && code < 100),
    };
    let message = match (code, kind) {
        (21001, _) => "Feishu access control policy denied the request",
        (230002, _) => "Feishu bot is not a member of this chat",
        (230006, _) => "Feishu application bot capability is not enabled",
        (230013, _) => "Feishu bot is not available to this user",
        (230053, _) => "Feishu user has stopped receiving bot messages",
        (200740, _) => "CardKit card does not exist",
        (200750, _) => "CardKit card has expired; replacement is not automatic",
        (200770, _) => "CardKit operation UUID conflicts with an earlier operation",
        (200810, _) => "CardKit rejected the card interaction configuration",
        (200850, _) => "CardKit streaming timed out (200850)",
        (200860, _) => "CardKit card exceeds the platform size bound",
        (300302, _) => "CardKit card requires update_multi=true",
        (300309, _) => "CardKit streaming is closed (300309)",
        (300310, _) => "CardKit target element is not a Markdown text element",
        (300311, _) => "CardKit permission denied; administrator must grant cardkit:card:write",
        (300317, _) => "CardKit sequence was rejected",
        (_, FeishuErrorKind::Auth) => "Feishu authentication was rejected",
        (_, FeishuErrorKind::Permission) => "Feishu permission was denied",
        (_, FeishuErrorKind::Rejected) => "Feishu rejected the request",
        (_, FeishuErrorKind::NotFound) => "Feishu resource was not found",
        _ => "Feishu API rejected the request",
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}

pub(super) fn require_open_success(code: i64, message: Option<&str>) -> Result<(), FeishuError> {
    if code == 0 {
        Ok(())
    } else {
        Err(classify_open_api(code, message))
    }
}

pub(super) fn require_open_http_success(
    status: reqwest::StatusCode,
    bytes: &[u8],
) -> Result<(), FeishuError> {
    if status.is_success() {
        return Ok(());
    }
    #[derive(Deserialize)]
    struct Failure {
        code: i64,
    }
    if let Ok(failure) = serde_json::from_slice::<Failure>(bytes)
        && failure.code != 0
    {
        return Err(classify_open_api(failure.code, None));
    }
    Err(classify_http_status(status))
}

pub(super) fn parse_json<T: DeserializeOwned>(
    bytes: &[u8],
    status: reqwest::StatusCode,
) -> Result<T, FeishuError> {
    serde_json::from_slice(bytes).map_err(|error| json_protocol_error(status, error))
}

pub(super) fn json_protocol_error(
    status: reqwest::StatusCode,
    error: serde_json::Error,
) -> FeishuError {
    let line = error.line();
    let column = error.column();
    let category = match error.classify() {
        serde_json::error::Category::Io => "io",
        serde_json::error::Category::Syntax => "syntax",
        serde_json::error::Category::Data => "data",
        serde_json::error::Category::Eof => "eof",
    };
    FeishuError::new(
        FeishuErrorKind::Protocol,
        format!("invalid Feishu JSON ({category} at {line}:{column})"),
        status.is_server_error(),
        None,
    )
}

pub(super) fn classify_http_status(status: reqwest::StatusCode) -> FeishuError {
    let code = status.as_u16();
    let (kind, retryable, message) = match code {
        401 => (
            FeishuErrorKind::Auth,
            false,
            "Feishu HTTP authentication was rejected",
        ),
        403 => (
            FeishuErrorKind::Permission,
            false,
            "Feishu HTTP permission was denied",
        ),
        404 => (
            FeishuErrorKind::NotFound,
            false,
            "Feishu HTTP resource was not found",
        ),
        429 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu HTTP rate limit was reached",
        ),
        400..=499 => (
            FeishuErrorKind::Rejected,
            false,
            "Feishu HTTP request was rejected",
        ),
        500..=599 => (
            FeishuErrorKind::Unavailable,
            true,
            "Feishu HTTP service is unavailable",
        ),
        _ => (
            FeishuErrorKind::Unavailable,
            false,
            "Feishu HTTP request failed",
        ),
    };
    FeishuError::new(kind, message, retryable, Some(code.to_string()))
}
