//! Thin typed adapter for the official CardKit JSON 2.0 entity API.

use super::error::{FeishuError, FeishuErrorKind};
use super::http::{FeishuHttp, classify_open_api};
use reqwest::Method;
use serde::{Deserialize, Serialize};

pub const ELEMENT_ID: &str = "answer";
pub const CARD_LIMIT_BYTES: usize = 30_000;

pub struct FeishuCardKit {
    http: FeishuHttp,
}

#[derive(Serialize)]
struct Card<'a> {
    schema: &'static str,
    config: Config<'a>,
    body: CardBody<'a>,
}

#[derive(Serialize)]
struct Config<'a> {
    streaming_mode: bool,
    update_multi: bool,
    summary: Summary<'a>,
}

#[derive(Serialize)]
struct Summary<'a> {
    content: &'a str,
}

#[derive(Serialize)]
struct CardBody<'a> {
    elements: [Markdown<'a>; 1],
}

#[derive(Serialize)]
struct Markdown<'a> {
    tag: &'static str,
    element_id: &'static str,
    content: &'a str,
}

#[derive(Serialize)]
struct CreateBody {
    r#type: &'static str,
    data: String,
}

#[derive(Deserialize)]
struct Response<T> {
    code: i64,
    data: Option<T>,
}

#[derive(Deserialize)]
struct Created {
    card_id: String,
}

#[derive(Serialize)]
struct ContentBody<'a> {
    content: &'a str,
    sequence: i32,
    uuid: &'a str,
}

#[derive(Serialize)]
struct SettingsBody<'a> {
    settings: String,
    sequence: i32,
    uuid: &'a str,
}

#[derive(Serialize)]
struct Settings<'a> {
    config: SettingsConfig<'a>,
}

#[derive(Serialize)]
struct SettingsConfig<'a> {
    streaming_mode: bool,
    summary: Summary<'a>,
}

/// Validate the whole serialized card, not the content endpoint's larger field limit.
pub fn validate_card(text: &str, streaming: bool, summary: &str) -> Result<(), FeishuError> {
    card_json(text, streaming, summary).map(|_| ())
}

fn card_json(text: &str, streaming: bool, summary: &str) -> Result<String, FeishuError> {
    if text.trim().is_empty() || text.chars().count() > 100_000 {
        return Err(size_error(
            "card Markdown must contain 1..100000 characters",
        ));
    }
    let json = serde_json::to_string(&Card {
        schema: "2.0",
        config: Config {
            streaming_mode: streaming,
            update_multi: true,
            summary: Summary { content: summary },
        },
        body: CardBody {
            elements: [Markdown {
                tag: "markdown",
                element_id: ELEMENT_ID,
                content: text,
            }],
        },
    })
    .expect("card strings serialize");
    if json.len() > CARD_LIMIT_BYTES {
        return Err(size_error(
            "serialized CardKit card exceeds 30000 UTF-8 bytes; full answer retained locally",
        ));
    }
    Ok(json)
}

impl FeishuCardKit {
    pub fn new(http: FeishuHttp) -> Self {
        Self { http }
    }

    pub async fn create(&self, token: &str, text: &str) -> Result<String, FeishuError> {
        let body = CreateBody {
            r#type: "card_json",
            data: card_json(text, true, "Generating")?,
        };
        let response: Response<Created> = self
            .http
            .open_typed(
                Method::POST,
                "/open-apis/cardkit/v1/cards",
                Some(token),
                &[],
                Some(&body),
            )
            .await
            .map_err(card_error)?;
        if response.code != 0 {
            return Err(card_error(classify_open_api(response.code, None)));
        }
        response
            .data
            .map(|data| data.card_id)
            .filter(|id| !id.trim().is_empty() && id.len() <= 256)
            .ok_or_else(|| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "CardKit create response missing a valid card_id; acceptance is unknown",
                    false,
                    None,
                )
            })
    }

    pub async fn content(
        &self,
        token: &str,
        card_id: &str,
        text: &str,
        sequence: i32,
        uuid: &str,
    ) -> Result<(), FeishuError> {
        self.operation(
            Method::PUT,
            &self.path(card_id, &["elements", ELEMENT_ID, "content"]),
            token,
            &ContentBody {
                content: text,
                sequence,
                uuid,
            },
        )
        .await
    }

    pub async fn settings(
        &self,
        token: &str,
        card_id: &str,
        settings: CardSettings<'_>,
    ) -> Result<(), FeishuError> {
        let settings_json = serde_json::to_string(&Settings {
            config: SettingsConfig {
                streaming_mode: settings.streaming,
                summary: Summary {
                    content: settings.summary,
                },
            },
        })
        .expect("settings strings serialize");
        self.operation(
            Method::PATCH,
            &self.path(card_id, &["settings"]),
            token,
            &SettingsBody {
                settings: settings_json,
                sequence: settings.sequence,
                uuid: settings.uuid,
            },
        )
        .await
    }

    async fn operation<B: Serialize>(
        &self,
        method: Method,
        path: &str,
        token: &str,
        body: &B,
    ) -> Result<(), FeishuError> {
        let response: Response<serde::de::IgnoredAny> = self
            .http
            .open_typed(method, path, Some(token), &[], Some(body))
            .await
            .map_err(card_error)?;
        if response.code != 0 {
            return Err(card_error(classify_open_api(response.code, None)));
        }
        Ok(())
    }

    fn path(&self, card_id: &str, suffix: &[&str]) -> String {
        let mut url = self.http.open_api().clone();
        url.path_segments_mut()
            .expect("validated hierarchical HTTP origin")
            .clear()
            .extend(["open-apis", "cardkit", "v1", "cards", card_id])
            .extend(suffix.iter().copied());
        url.path().to_string()
    }
}

pub struct CardSettings<'a> {
    pub streaming: bool,
    pub summary: &'a str,
    pub sequence: i32,
    pub uuid: &'a str,
}

fn size_error(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}

fn card_error(error: FeishuError) -> FeishuError {
    if error.kind() == FeishuErrorKind::Permission {
        return FeishuError::new(
            FeishuErrorKind::Permission,
            "CardKit permission denied; administrator must grant cardkit:card:write",
            false,
            error.platform_code().map(str::to_string),
        );
    }
    error
}
