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
    elements: Vec<Markdown<'a>>,
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

impl FeishuCardKit {
    pub fn new(http: FeishuHttp) -> Self {
        Self { http }
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

/// The host region is a separate Markdown element: it must never become part of an
/// unclosed model code fence. This serializer is also used by the pre-intent budget check.
pub(in crate::bots) fn publication_card_json(
    text: &str,
    host: &str,
    streaming: bool,
    summary: &str,
) -> Result<String, FeishuError> {
    if text.chars().count() > 100_000 || text.trim().is_empty() && host.trim().is_empty() {
        return Err(size_error(
            "CardKit requires bounded public text or a real independent host status",
        ));
    }
    let mut elements = vec![Markdown {
        tag: "markdown",
        element_id: ELEMENT_ID,
        content: text,
    }];
    if !host.is_empty() {
        elements.push(Markdown {
            tag: "markdown",
            element_id: "publication_status",
            content: host,
        });
    }
    let json = serialize(&Card {
        schema: "2.0",
        config: Config {
            streaming_mode: streaming,
            update_multi: true,
            summary: Summary { content: summary },
        },
        body: CardBody { elements },
    })?;
    bounded(json)
}

pub(in crate::bots) fn publication_create(card: String) -> Result<String, FeishuError> {
    bounded(serialize(&CreateBody {
        r#type: "card_json",
        data: card,
    })?)
}

pub(in crate::bots) fn publication_content(
    text: &str,
    sequence: i32,
    uuid: &str,
) -> Result<String, FeishuError> {
    bounded(serialize(&ContentBody {
        content: text,
        sequence,
        uuid,
    })?)
}

pub(in crate::bots) fn publication_whole(
    card: String,
    sequence: i32,
    uuid: &str,
) -> Result<String, FeishuError> {
    #[derive(Serialize)]
    struct Whole {
        card: CreateBody,
        sequence: i32,
        uuid: String,
    }
    bounded(serialize(&Whole {
        card: CreateBody {
            r#type: "card_json",
            data: card,
        },
        sequence,
        uuid: uuid.to_owned(),
    })?)
}

pub(in crate::bots) fn publication_settings(
    streaming: bool,
    summary: &str,
    sequence: i32,
    uuid: &str,
) -> Result<String, FeishuError> {
    bounded(serialize(&SettingsBody {
        settings: serialize(&Settings {
            config: SettingsConfig {
                streaming_mode: streaming,
                summary: Summary { content: summary },
            },
        })?,
        sequence,
        uuid,
    })?)
}

pub(in crate::bots) fn publication_send(
    chat_id: &str,
    card_id: &str,
    uuid: &str,
) -> Result<String, FeishuError> {
    #[derive(Serialize)]
    struct CardReference<'a> {
        r#type: &'static str,
        data: CardId<'a>,
    }
    #[derive(Serialize)]
    struct CardId<'a> {
        card_id: &'a str,
    }
    #[derive(Serialize)]
    struct Send<'a> {
        receive_id: &'a str,
        msg_type: &'static str,
        content: String,
        uuid: &'a str,
    }
    bounded(serialize(&Send {
        receive_id: chat_id,
        msg_type: "interactive",
        uuid,
        content: serialize(&CardReference {
            r#type: "card",
            data: CardId { card_id },
        })?,
    })?)
}

fn serialize(value: &impl Serialize) -> Result<String, FeishuError> {
    serde_json::to_string(value).map_err(|_| {
        FeishuError::new(
            FeishuErrorKind::Protocol,
            "CardKit request serialization failed",
            false,
            None,
        )
    })
}

fn bounded(body: String) -> Result<String, FeishuError> {
    if body.len() > CARD_LIMIT_BYTES {
        return Err(size_error(
            "serialized CardKit card/request exceeds 30000 UTF-8 bytes",
        ));
    }
    Ok(body)
}

/// A fully prepared request owns exactly the frozen bytes. Preparing performs no HTTP.
pub(in crate::bots) struct PreparedPublication {
    request: reqwest::Request,
    target: crate::bots::storage::publication::DeliveryRequestTarget,
}

impl PreparedPublication {
    /// Bind the transaction's exact bytes without changing the already prepared endpoint/method.
    pub(in crate::bots) fn bind_frozen(
        &mut self,
        frozen: &crate::bots::storage::publication::FrozenDeliveryRequest,
    ) -> Result<(), FeishuError> {
        frozen.validate()?;
        if self.target != frozen.target() {
            return Err(size_error(
                "frozen CardKit target changed after preparation",
            ));
        }
        *self.request.body_mut() = Some(frozen.body().to_owned().into());
        Ok(())
    }
}

pub(in crate::bots) enum PublicationResponse {
    Created(String),
    Sent(String),
    Updated,
}

impl FeishuCardKit {
    pub(in crate::bots) fn prepare_publication(
        &self,
        token: &str,
        chat_id: &str,
        card_id: Option<&str>,
        frozen: &crate::bots::storage::publication::FrozenDeliveryRequest,
    ) -> Result<PreparedPublication, FeishuError> {
        use crate::bots::storage::publication::DeliveryRequestTarget as Target;
        frozen.validate()?;
        let (method, path) = match frozen.target() {
            Target::CreateCard => (Method::POST, "/open-apis/cardkit/v1/cards".to_owned()),
            Target::SendCard => (Method::POST, "/open-apis/im/v1/messages".to_owned()),
            target => {
                let id = card_id
                    .filter(|id| !id.is_empty() && id.len() <= 256)
                    .ok_or_else(|| {
                        size_error("CardKit mutation lacks its original card identity")
                    })?;
                match target {
                    Target::ElementContent => (
                        Method::PUT,
                        self.path(id, &["elements", ELEMENT_ID, "content"]),
                    ),
                    Target::WholeCard => (Method::PUT, self.path(id, &[])),
                    Target::Settings => (Method::PATCH, self.path(id, &["settings"])),
                    Target::CreateCard | Target::SendCard => unreachable!(),
                }
            }
        };
        let mut url = self
            .http
            .open_api()
            .join(path.trim_start_matches('/'))
            .map_err(|_| size_error("invalid CardKit API path"))?;
        if frozen.target() == Target::SendCard {
            // chat identity is already frozen in the body; never replace it here.
            if chat_id.is_empty() {
                return Err(size_error("empty original publication chat"));
            }
            url.query_pairs_mut()
                .append_pair("receive_id_type", "chat_id");
        }
        self.http
            .client()
            .request(method, url)
            .bearer_auth(token)
            .header(reqwest::header::CONTENT_TYPE, "application/json")
            .body(frozen.body().to_owned())
            .build()
            .map(|request| PreparedPublication {
                request,
                target: frozen.target(),
            })
            .map_err(|_| {
                FeishuError::new(
                    FeishuErrorKind::Protocol,
                    "cannot prepare frozen CardKit request",
                    false,
                    None,
                )
            })
    }

    /// This future is first polled under publication admission, then drained by the same owner.
    /// Only a typed business rejection or explicit HTTP 4xx proves rejection; malformed replies,
    /// disconnects and 5xx without a business rejection remain Unknown.
    pub(in crate::bots) async fn execute_publication(
        &self,
        prepared: PreparedPublication,
        target: crate::bots::storage::publication::DeliveryRequestTarget,
    ) -> Result<PublicationResponse, super::http::PostFailure> {
        use super::http::PostFailure;
        use crate::bots::storage::publication::DeliveryRequestTarget as Target;
        let unknown = || {
            FeishuError::new(
                FeishuErrorKind::Protocol,
                "started CardKit request has no valid bounded response; acceptance is unknown",
                false,
                None,
            )
        };
        let mut response = self
            .http
            .client()
            .execute(prepared.request)
            .await
            .map_err(|_| PostFailure::Unknown(unknown()))?;
        let status = response.status();
        let mut bytes = Vec::new();
        while let Some(chunk) = response
            .chunk()
            .await
            .map_err(|_| PostFailure::Unknown(unknown()))?
        {
            if bytes.len().saturating_add(chunk.len()) > 64 * 1024 {
                return Err(PostFailure::Unknown(unknown()));
            }
            bytes.extend_from_slice(&chunk);
        }
        #[derive(Deserialize)]
        struct Envelope {
            code: i64,
        }
        let envelope = serde_json::from_slice::<Envelope>(&bytes);
        if let Ok(envelope) = &envelope
            && envelope.code != 0
        {
            return Err(PostFailure::Rejected(card_error(classify_open_api(
                envelope.code,
                None,
            ))));
        }
        if !status.is_success() {
            let error = FeishuError::new(
                if status.is_client_error() {
                    FeishuErrorKind::Rejected
                } else {
                    FeishuErrorKind::Unavailable
                },
                "CardKit HTTP request failed",
                false,
                Some(status.as_u16().to_string()),
            );
            return Err(if status.is_client_error() {
                PostFailure::Rejected(error)
            } else {
                PostFailure::Unknown(error)
            });
        }
        envelope.map_err(|_| PostFailure::Unknown(unknown()))?;
        match target {
            Target::CreateCard => {
                let created = serde_json::from_slice::<Response<Created>>(&bytes)
                    .map_err(|_| PostFailure::Unknown(unknown()))?
                    .data
                    .ok_or_else(|| PostFailure::Unknown(unknown()))?;
                if created.card_id.trim().is_empty() || created.card_id.len() > 256 {
                    return Err(PostFailure::Unknown(unknown()));
                }
                Ok(PublicationResponse::Created(created.card_id))
            }
            Target::SendCard => {
                #[derive(Deserialize)]
                struct Sent {
                    message_id: String,
                }
                let sent = serde_json::from_slice::<Response<Sent>>(&bytes)
                    .map_err(|_| PostFailure::Unknown(unknown()))?
                    .data
                    .ok_or_else(|| PostFailure::Unknown(unknown()))?;
                if sent.message_id.trim().is_empty() || sent.message_id.len() > 256 {
                    return Err(PostFailure::Unknown(unknown()));
                }
                Ok(PublicationResponse::Sent(sent.message_id))
            }
            Target::ElementContent | Target::WholeCard | Target::Settings => {
                Ok(PublicationResponse::Updated)
            }
        }
    }
}
