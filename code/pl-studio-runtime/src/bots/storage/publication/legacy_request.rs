//! 仅九到十边界：按原 CardKit/IM typed 请求形状冻结原参数，不作为当前网络 serializer。

use super::*;

#[derive(Serialize)]
struct Summary<'a> {
    content: &'a str,
}
#[derive(Serialize)]
struct Card<'a> {
    schema: &'a str,
    config: Config<'a>,
    body: Body<'a>,
}
#[derive(Serialize)]
struct Config<'a> {
    streaming_mode: bool,
    update_multi: bool,
    summary: Summary<'a>,
}
#[derive(Serialize)]
struct Body<'a> {
    elements: [Markdown<'a>; 1],
}
#[derive(Serialize)]
struct Markdown<'a> {
    tag: &'a str,
    element_id: &'a str,
    content: &'a str,
}
#[derive(Serialize)]
struct Create {
    r#type: &'static str,
    data: String,
}
#[derive(Serialize)]
struct Content<'a> {
    content: &'a str,
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
#[derive(Serialize)]
struct UpdateSettings<'a> {
    settings: String,
    sequence: i32,
    uuid: &'a str,
}
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

fn encode(value: &impl Serialize) -> Result<String, FeishuError> {
    serde_json::to_string(value).map_err(|_| unreadable())
}

pub(super) fn freeze_legacy_request(
    chat_id: &str,
    action: &DeliveryAction,
    sequence: i32,
    uuid: &str,
) -> Result<FrozenDeliveryRequest, FeishuError> {
    let body = match action {
        DeliveryAction::CreateCard { text } => encode(&Create {
            r#type: "card_json",
            data: encode(&Card {
                schema: "2.0",
                config: Config {
                    streaming_mode: true,
                    update_multi: true,
                    summary: Summary {
                        content: "Generating",
                    },
                },
                body: Body {
                    elements: [Markdown {
                        tag: "markdown",
                        element_id: crate::bots::protocol::cardkit::ELEMENT_ID,
                        content: text,
                    }],
                },
            })?,
        })?,
        DeliveryAction::SendCard { card_id } => encode(&Send {
            receive_id: chat_id,
            msg_type: "interactive",
            content: encode(&CardReference {
                r#type: "card",
                data: CardId { card_id },
            })?,
            uuid,
        })?,
        DeliveryAction::UpdateContent { text, .. } => encode(&Content {
            content: text,
            sequence,
            uuid,
        })?,
        DeliveryAction::UpdateSettings {
            streaming,
            lifecycle,
            ..
        } => encode(&UpdateSettings {
            settings: encode(&Settings {
                config: SettingsConfig {
                    streaming_mode: *streaming,
                    summary: Summary {
                        content: lifecycle.summary(),
                    },
                },
            })?,
            sequence,
            uuid,
        })?,
    };
    let target = match action {
        DeliveryAction::CreateCard { .. } => DeliveryRequestTarget::CreateCard,
        DeliveryAction::SendCard { .. } => DeliveryRequestTarget::SendCard,
        DeliveryAction::UpdateContent { .. } => DeliveryRequestTarget::ElementContent,
        DeliveryAction::UpdateSettings { .. } => DeliveryRequestTarget::Settings,
    };
    FrozenDeliveryRequest::legacy(target, body)
}
