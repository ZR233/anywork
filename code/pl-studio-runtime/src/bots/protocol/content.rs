//! Official IM content shapes. Markdown is passed through, never parsed or rewritten.
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

use super::error::{FeishuError, FeishuErrorKind};
use crate::bots::inbound::InboundAttachment;

#[derive(Serialize)]
struct MarkdownPost<'a> {
    zh_cn: MarkdownBody<'a>,
}

#[derive(Serialize)]
struct MarkdownBody<'a> {
    title: &'a str,
    content: [[MarkdownNode<'a>; 1]; 1],
}

#[derive(Serialize)]
struct MarkdownNode<'a> {
    tag: &'static str,
    text: &'a str,
}

pub fn markdown_content(text: &str) -> Result<String, FeishuError> {
    serde_json::to_string(&MarkdownPost {
        zh_cn: MarkdownBody {
            title: "",
            content: [[MarkdownNode { tag: "md", text }]],
        },
    })
    .map_err(|_| content_error("could not encode Markdown post"))
}

#[derive(Deserialize)]
pub struct TextContent {
    pub text: String,
}

#[derive(Deserialize)]
struct ImageContent {
    image_key: String,
}

#[derive(Deserialize)]
struct FileContent {
    file_key: String,
    #[serde(default)]
    file_name: Option<String>,
}

#[derive(Deserialize)]
struct WirePost {
    #[serde(default)]
    title: String,
    #[serde(default)]
    content: Present<Box<serde_json::value::RawValue>>,
    #[serde(default)]
    content_v2: Present<Box<serde_json::value::RawValue>>,
}

struct PostBody {
    title: String,
    content: Vec<Vec<PostNode>>,
}

impl WirePost {
    fn resolve(self) -> Result<PostBody, FeishuError> {
        // Defer only the two alternative fields, then immediately decode the selected official
        // schema. A downgraded legacy field cannot override or invalidate an authoritative v2.
        let selected = match self.content_v2 {
            Present::Value(content) => content,
            Present::Absent => match self.content {
                Present::Value(content) => content,
                Present::Absent => return Err(content_error("post has no content field")),
            },
        };
        let content = decode(selected.get())?;
        Ok(PostBody {
            title: self.title,
            content,
        })
    }
}

fn decode_post(content: &str) -> Result<PostBody, FeishuError> {
    let post: WirePost = decode(content)?;
    if !matches!(post.content_v2, Present::Absent) || !matches!(post.content, Present::Absent) {
        return post.resolve();
    }
    let mut languages: BTreeMap<String, WirePost> = decode(content)?;
    languages
        .remove("zh_cn")
        .or_else(|| languages.into_values().next())
        .ok_or_else(|| content_error("post has no language body"))?
        .resolve()
}

// Option would collapse explicit null into absence and incorrectly fall back to legacy content.
// A present empty array is authoritative; a malformed/null present field is a schema error.
#[derive(Default)]
enum Present<T> {
    #[default]
    Absent,
    Value(T),
}

impl<'de, T: Deserialize<'de>> Deserialize<'de> for Present<T> {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        T::deserialize(deserializer).map(Self::Value)
    }
}

#[derive(Deserialize)]
#[serde(tag = "tag")]
enum PostNode {
    #[serde(rename = "text", alias = "md", alias = "code_block")]
    Text { text: String },
    #[serde(rename = "a")]
    Link { text: String, href: String },
    #[serde(rename = "at")]
    Mention {
        user_id: String,
        #[serde(default)]
        user_name: Option<String>,
    },
    #[serde(rename = "img")]
    Image { image_key: String },
    #[serde(rename = "media")]
    Media { file_key: String },
    #[serde(rename = "emotion")]
    Emotion { emoji_type: String },
    #[serde(rename = "hr")]
    Rule,
    #[serde(other)]
    Unsupported,
}

#[derive(Default)]
pub struct ReceivedContent {
    pub text: String,
    pub attachments: Vec<InboundAttachment>,
}

impl ReceivedContent {
    fn resource(&mut self, attachment: InboundAttachment) {
        let index = self
            .attachments
            .iter()
            .filter(|item| item.key().is_some())
            .count()
            + 1;
        // Markers preserve the original relative position; bytes remain real attachments in
        // the same ordered batch, not invented text standing in for an unsupported resource.
        self.text.push_str(&format!("[附件 {index}]"));
        self.attachments.push(attachment);
    }
}

pub fn receive_content(kind: &str, content: &str) -> Result<ReceivedContent, FeishuError> {
    let mut result = ReceivedContent::default();
    match kind {
        "text" => result.text = decode::<TextContent>(content)?.text,
        "post" => {
            let post = decode_post(content)?;
            if !post.title.is_empty() {
                result.text.push_str(&post.title);
                result.text.push('\n');
            }
            for (index, paragraph) in post.content.into_iter().enumerate() {
                if index > 0 {
                    result.text.push('\n');
                }
                for node in paragraph {
                    match node {
                        PostNode::Text { text } => result.text.push_str(&text),
                        PostNode::Link { text, href } => {
                            result.text.push_str(&format!("[{text}]({href})"));
                        }
                        PostNode::Mention { user_id, user_name } => {
                            result.text.push('@');
                            result
                                .text
                                .push_str(user_name.as_deref().unwrap_or(&user_id));
                        }
                        PostNode::Image { image_key } => {
                            result.resource(InboundAttachment::Image { key: image_key });
                        }
                        PostNode::Media { file_key } => {
                            result.resource(InboundAttachment::File {
                                key: file_key,
                                filename: "video".into(),
                            });
                        }
                        PostNode::Emotion { emoji_type } => {
                            result.text.push_str(&format!("[{emoji_type}]"));
                        }
                        PostNode::Rule => result.text.push_str("\n---\n"),
                        PostNode::Unsupported => {
                            result
                                .text
                                .push_str("[不支持的飞书富文本元素，未作为附件接收]");
                            result.attachments.push(InboundAttachment::Unsupported {
                                message_type: "postElement".into(),
                            });
                        }
                    }
                }
            }
        }
        "image" => result.resource(InboundAttachment::Image {
            key: decode::<ImageContent>(content)?.image_key,
        }),
        "file" | "audio" | "media" => {
            let file = decode::<FileContent>(content)?;
            result.resource(InboundAttachment::File {
                key: file.file_key,
                filename: file
                    .file_name
                    .filter(|name| !name.is_empty())
                    .unwrap_or_else(|| {
                        match kind {
                            "audio" => "audio",
                            "media" => "video",
                            _ => "file",
                        }
                        .into()
                    }),
            });
        }
        _ => {
            return Err(content_error(
                "message type has no supported original resource API",
            ));
        }
    }
    if result.attachments.iter().any(|attachment| {
        attachment.key().is_some_and(str::is_empty) || attachment.frozen_bytes() > 4096
    }) {
        return Err(content_error("message resource identity is invalid"));
    }
    Ok(result)
}

fn decode<T: serde::de::DeserializeOwned>(content: &str) -> Result<T, FeishuError> {
    serde_json::from_str(content)
        .map_err(|_| content_error("message content has an invalid schema"))
}

fn content_error(message: &str) -> FeishuError {
    FeishuError::new(FeishuErrorKind::Rejected, message, false, None)
}
