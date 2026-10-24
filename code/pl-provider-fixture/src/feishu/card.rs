//! Official Feishu message-content and CardKit wire validation owned by this peer.
//!
//! These helpers only check the documented platform shape: a `post` message with
//! `md` nodes, a JSON 2.0 streaming card entity, an element-content update with a
//! cumulative body, and a settings update carrying `streaming_mode`. They never
//! decide product semantics such as which Turn text may be sent or how previews
//! are throttled; those remain runtime/owner decisions observed from outside.
//!
//! Wire references:
//! - <https://open.feishu.cn/document/server-docs/im-v1/message-content-description/create_json>
//! - <https://open.feishu.cn/document/cardkit-v1/streaming-updates-openapi-overview>
//! - <https://open.feishu.cn/document/cardkit-v1/card/create>
//! - <https://open.feishu.cn/document/cardkit-v1/card-element/content>
//! - <https://open.feishu.cn/document/cardkit-v1/card/settings>
//! - <https://open.feishu.cn/document/feishu-cards/card-json-v2-structure>

use anyhow::{Result, anyhow, bail, ensure};
use serde_json::Value;

/// Documented 30 KB limit for one IM message request and one card entity.
pub(crate) const MESSAGE_REQUEST_MAX_BYTES: usize = 30 * 1024;
/// Documented 100,000 character limit of one element content field.
pub(crate) const CARD_CONTENT_MAX_CHARS: usize = 100_000;
/// Documented positive int32 range of CardKit `sequence`.
pub(crate) const CARD_SEQUENCE_MAX: i64 = i32::MAX as i64;
/// Documented card id / uuid field lengths used by this peer's synthetic ids.
pub(crate) const CARD_ID_MAX_CHARS: usize = 20;
pub(crate) const CARD_UUID_MAX_CHARS: usize = 64;

/// Documented CardKit business codes this peer reproduces.
pub(crate) const CODE_NO_CARD: i32 = 200_740;
pub(crate) const CODE_CARD_EXPIRED: i32 = 200_750;
pub(crate) const CODE_UUID_CONFLICT: i32 = 200_770;
pub(crate) const CODE_CARD_TOO_LARGE: i32 = 200_860;
pub(crate) const CODE_STREAM_CLOSED: i32 = 300_309;
pub(crate) const CODE_ELEMENT_NOT_TEXT: i32 = 300_310;
pub(crate) const CODE_NO_PERMISSION: i32 = 300_311;
pub(crate) const CODE_SEQUENCE_NOT_INCREASING: i32 = 300_317;
/// A card entity may be sent as an IM message exactly once. The platform has no
/// separate documented code for the duplicate case; this peer answers a stable
/// synthetic business code instead of pretending success.
pub(crate) const CODE_CARD_ALREADY_SENT: i32 = 232_009;

/// The `md` text of one official `post` message.
pub(crate) struct PostContent {
    /// Concatenated `md` node text in row/node order.
    pub md_text: String,
}

/// Parse an official `post` content string.
///
/// Only the documented `zh_cn` locale body with row arrays of typed nodes is
/// accepted. Every node needs a string `tag`; `md` nodes need string `text`, and
/// at least one non-empty `md` node must exist. Other documented node tags are
/// tolerated without interpretation because this peer is not a renderer.
pub(crate) fn parse_post_content(content: &str) -> Result<PostContent> {
    let parsed: Value =
        serde_json::from_str(content).map_err(|error| anyhow!("post content json: {error}"))?;
    let object = parsed
        .as_object()
        .ok_or_else(|| anyhow!("post content must be a JSON object"))?;
    let locale = object
        .get("zh_cn")
        .ok_or_else(|| anyhow!("post content must carry zh_cn"))?;
    let body = locale
        .as_object()
        .ok_or_else(|| anyhow!("zh_cn must be a JSON object"))?;
    if let Some(title) = body.get("title") {
        ensure!(
            title.is_string(),
            "post zh_cn.title must be a string when present"
        );
    }
    let rows = body
        .get("content")
        .ok_or_else(|| anyhow!("post zh_cn.content is missing"))?
        .as_array()
        .ok_or_else(|| anyhow!("post zh_cn.content must be an array of rows"))?;
    ensure!(!rows.is_empty(), "post content must have at least one row");
    let mut md_text = String::new();
    let mut md_nodes = 0usize;
    for (row_index, row) in rows.iter().enumerate() {
        let nodes = row
            .as_array()
            .ok_or_else(|| anyhow!("post row {row_index} must be an array of nodes"))?;
        ensure!(
            !nodes.is_empty(),
            "post row {row_index} must have at least one node"
        );
        for (node_index, node) in nodes.iter().enumerate() {
            let node = node.as_object().ok_or_else(|| {
                anyhow!("post row {row_index} node {node_index} must be an object")
            })?;
            let tag = node.get("tag").and_then(Value::as_str).ok_or_else(|| {
                anyhow!("post row {row_index} node {node_index} needs a string tag")
            })?;
            match tag {
                "md" => {
                    let text = node.get("text").and_then(Value::as_str).ok_or_else(|| {
                        anyhow!("post md node at row {row_index} needs a string text")
                    })?;
                    ensure!(
                        !text.trim().is_empty(),
                        "post md node at row {row_index} must not be empty"
                    );
                    md_text.push_str(text);
                    md_nodes += 1;
                }
                "text" | "a" | "at" | "img" | "emotion" | "hr" | "code_block" | "media" => {}
                other => bail!("post node tag {other} is not part of the official content shape"),
            }
        }
    }
    ensure!(md_nodes > 0, "post content must carry at least one md node");
    Ok(PostContent { md_text })
}

/// Parse an official `interactive` card message content string.
///
/// Shape: `{"type":"card","data":{"card_id":"..."}}`.
pub(crate) fn parse_interactive_content(content: &str) -> Result<String> {
    let parsed: Value = serde_json::from_str(content)
        .map_err(|error| anyhow!("interactive content json: {error}"))?;
    let object = parsed
        .as_object()
        .ok_or_else(|| anyhow!("interactive content must be a JSON object"))?;
    ensure!(
        object.get("type").and_then(Value::as_str) == Some("card"),
        "interactive content type must be card"
    );
    let card_id = object
        .get("data")
        .and_then(Value::as_object)
        .and_then(|data| data.get("card_id"))
        .and_then(Value::as_str)
        .ok_or_else(|| anyhow!("interactive content needs data.card_id"))?;
    ensure!(!card_id.is_empty(), "interactive card_id must not be empty");
    ensure!(
        card_id.chars().count() <= CARD_ID_MAX_CHARS,
        "interactive card_id must be at most {CARD_ID_MAX_CHARS} characters"
    );
    Ok(card_id.to_owned())
}

/// A parsed JSON 2.0 streaming card entity.
pub(crate) struct CardJson {
    /// Stable id of the first markdown element; this peer updates that element.
    pub element_id: String,
    /// Full initial markdown content of that element.
    pub content: String,
    /// Exact serialized size of the submitted JSON.
    pub entity_bytes: usize,
    /// Parsed entity, kept so later updates serialize the same document.
    pub data: Value,
}

/// Parse the official JSON 2.0 streaming card entity string.
///
/// Only documented structural properties are type-checked: `schema` is `"2.0"`,
/// `config.streaming_mode` and `config.update_multi` are `true`, and
/// `body.elements` carries at least one `markdown` element with a non-empty
/// unique `element_id` and string `content`. Other `config` properties are
/// allowed as long as they keep their documented JSON types.
pub(crate) fn parse_card_json(data: &str) -> Result<CardJson> {
    let parsed: Value =
        serde_json::from_str(data).map_err(|error| anyhow!("card data json: {error}"))?;
    let object = parsed
        .as_object()
        .ok_or_else(|| anyhow!("card data must be a JSON object"))?;
    ensure!(
        object.get("schema").and_then(Value::as_str) == Some("2.0"),
        "card data schema must be \"2.0\""
    );
    let config = object
        .get("config")
        .and_then(Value::as_object)
        .ok_or_else(|| anyhow!("card data needs a config object"))?;
    ensure!(
        config.get("streaming_mode").and_then(Value::as_bool) == Some(true),
        "card config.streaming_mode must be true"
    );
    ensure!(
        config.get("update_multi").and_then(Value::as_bool) == Some(true),
        "card config.update_multi must be true"
    );
    for key in ["wide_screen_mode", "enable_forward"] {
        if let Some(value) = config.get(key) {
            ensure!(
                value.is_boolean(),
                "card config.{key} must be a boolean when present"
            );
        }
    }
    let elements = object
        .get("body")
        .and_then(Value::as_object)
        .and_then(|body| body.get("elements"))
        .and_then(Value::as_array)
        .ok_or_else(|| anyhow!("card data needs body.elements"))?;
    ensure!(!elements.is_empty(), "card body.elements must not be empty");
    let mut markdown: Option<(String, String)> = None;
    let mut seen = std::collections::BTreeSet::new();
    for (index, element) in elements.iter().enumerate() {
        let element = element
            .as_object()
            .ok_or_else(|| anyhow!("card element {index} must be an object"))?;
        let tag = element
            .get("tag")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("card element {index} needs a string tag"))?;
        let element_id = element.get("element_id").and_then(Value::as_str);
        if let Some(element_id) = element_id {
            ensure!(
                !element_id.is_empty(),
                "card element {index} element_id must not be empty"
            );
            ensure!(
                seen.insert(element_id.to_owned()),
                "card element ids must be unique"
            );
        }
        if tag != "markdown" {
            continue;
        }
        let element_id = element_id
            .ok_or_else(|| anyhow!("card markdown element {index} needs an element_id"))?;
        let content = element
            .get("content")
            .and_then(Value::as_str)
            .ok_or_else(|| anyhow!("card markdown element {index} needs string content"))?;
        if markdown.is_none() {
            markdown = Some((element_id.to_owned(), content.to_owned()));
        }
    }
    let (element_id, content) =
        markdown.ok_or_else(|| anyhow!("card data needs at least one markdown element"))?;
    Ok(CardJson {
        element_id,
        content,
        entity_bytes: data.len(),
        data: parsed,
    })
}

/// Replaces the markdown element content in the stored entity and returns the
/// exact serialized size the platform would hold.
pub(crate) fn replace_element_content(
    data: &mut Value,
    element_id: &str,
    content: &str,
) -> Result<usize> {
    let elements = data
        .get_mut("body")
        .and_then(Value::as_object_mut)
        .and_then(|body| body.get_mut("elements"))
        .and_then(Value::as_array_mut)
        .ok_or_else(|| anyhow!("stored card lost body.elements"))?;
    let mut found = false;
    for element in elements.iter_mut() {
        let Some(element) = element.as_object_mut() else {
            continue;
        };
        if element.get("element_id").and_then(Value::as_str) != Some(element_id) {
            continue;
        }
        element.insert("content".to_owned(), Value::String(content.to_owned()));
        found = true;
        break;
    }
    ensure!(found, "element {element_id} is not part of this card");
    Ok(serde_json::to_vec(data)
        .map_err(|error| anyhow!("stored card serialize: {error}"))?
        .len())
}

/// Parsed official CardKit settings update.
pub(crate) struct CardSettings {
    /// `config.streaming_mode` when present.
    pub streaming_mode: Option<bool>,
    /// `config.summary.content` when present.
    pub summary: Option<String>,
}

/// Parses the official `settings` string of a card settings update.
///
/// Only documented properties are type-checked; unknown sibling properties are
/// preserved by the platform and therefore not interpreted here.
pub(crate) fn parse_card_settings(settings: &str) -> Result<CardSettings> {
    let parsed: Value =
        serde_json::from_str(settings).map_err(|error| anyhow!("settings json: {error}"))?;
    let object = parsed
        .as_object()
        .ok_or_else(|| anyhow!("settings must be a JSON object"))?;
    let mut streaming_mode = None;
    let mut summary = None;
    if let Some(config) = object.get("config") {
        let config = config
            .as_object()
            .ok_or_else(|| anyhow!("settings.config must be an object"))?;
        if let Some(value) = config.get("streaming_mode") {
            streaming_mode = Some(
                value
                    .as_bool()
                    .ok_or_else(|| anyhow!("settings.config.streaming_mode must be a boolean"))?,
            );
        }
        if let Some(value) = config.get("summary") {
            let summary_object = value
                .as_object()
                .ok_or_else(|| anyhow!("settings.config.summary must be an object"))?;
            if let Some(content) = summary_object.get("content") {
                summary = Some(
                    content
                        .as_str()
                        .ok_or_else(|| anyhow!("settings.config.summary.content must be a string"))?
                        .to_owned(),
                );
            }
        }
    }
    ensure!(
        streaming_mode.is_some() || summary.is_some(),
        "settings must carry config.streaming_mode or config.summary.content"
    );
    Ok(CardSettings {
        streaming_mode,
        summary,
    })
}
