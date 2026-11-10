use super::*;
use json::{opt_meta, opt_protocol_meta};

pub(crate) fn content(value: s::ContentBlock) -> R<BridgeAcpContentBlock> {
    Ok(match value {
        s::ContentBlock::Text(v) => BridgeAcpContentBlock::Text {
            text: v.text,
            annotations: v.annotations.map(annotations).transpose()?,
            meta: opt_meta(v.meta)?,
        },
        s::ContentBlock::Image(v) => BridgeAcpContentBlock::Image {
            data: v.data,
            mime_type: v.mime_type,
            uri: v.uri,
            annotations: v.annotations.map(annotations).transpose()?,
            meta: opt_meta(v.meta)?,
        },
        s::ContentBlock::Audio(v) => BridgeAcpContentBlock::Audio {
            data: v.data,
            mime_type: v.mime_type,
            annotations: v.annotations.map(annotations).transpose()?,
            meta: opt_meta(v.meta)?,
        },
        s::ContentBlock::ResourceLink(v) => BridgeAcpContentBlock::ResourceLink {
            name: v.name,
            uri: v.uri,
            description: v.description,
            mime_type: v.mime_type,
            size: v.size,
            title: v.title,
            annotations: v.annotations.map(annotations).transpose()?,
            meta: opt_meta(v.meta)?,
        },
        s::ContentBlock::Resource(v) => BridgeAcpContentBlock::Resource {
            resource: match v.resource {
                s::EmbeddedResourceResource::TextResourceContents(v) => {
                    BridgeAcpEmbeddedResource::Text {
                        text: v.text,
                        uri: v.uri,
                        mime_type: v.mime_type,
                        meta: opt_meta(v.meta)?,
                    }
                }
                s::EmbeddedResourceResource::BlobResourceContents(v) => {
                    BridgeAcpEmbeddedResource::Blob {
                        blob: v.blob,
                        uri: v.uri,
                        mime_type: v.mime_type,
                        meta: opt_meta(v.meta)?,
                    }
                }
                _ => return Err(unsupported("EmbeddedResourceResource")),
            },
            annotations: v.annotations.map(annotations).transpose()?,
            meta: opt_meta(v.meta)?,
        },
        _ => return Err(unsupported("ContentBlock")),
    })
}
pub(crate) fn protocol_content(value: BridgeAcpContentBlock) -> R<s::ContentBlock> {
    Ok(match value {
        BridgeAcpContentBlock::Text {
            text,
            annotations,
            meta,
        } => {
            let mut v = s::TextContent::new(text);
            v.annotations = annotations.map(protocol_annotations).transpose()?;
            v.meta = opt_protocol_meta(meta)?;
            s::ContentBlock::Text(v)
        }
        BridgeAcpContentBlock::Image {
            data,
            mime_type,
            uri,
            annotations,
            meta,
        } => {
            let mut v = s::ImageContent::new(data, mime_type);
            v.uri = uri;
            v.annotations = annotations.map(protocol_annotations).transpose()?;
            v.meta = opt_protocol_meta(meta)?;
            s::ContentBlock::Image(v)
        }
        BridgeAcpContentBlock::Audio {
            data,
            mime_type,
            annotations,
            meta,
        } => {
            let mut v = s::AudioContent::new(data, mime_type);
            v.annotations = annotations.map(protocol_annotations).transpose()?;
            v.meta = opt_protocol_meta(meta)?;
            s::ContentBlock::Audio(v)
        }
        BridgeAcpContentBlock::ResourceLink {
            name,
            uri,
            description,
            mime_type,
            size,
            title,
            annotations,
            meta,
        } => {
            let mut v = s::ResourceLink::new(name, uri);
            v.description = description;
            v.mime_type = mime_type;
            v.size = size;
            v.title = title;
            v.annotations = annotations.map(protocol_annotations).transpose()?;
            v.meta = opt_protocol_meta(meta)?;
            s::ContentBlock::ResourceLink(v)
        }
        BridgeAcpContentBlock::Resource {
            resource,
            annotations,
            meta,
        } => {
            let resource = match resource {
                BridgeAcpEmbeddedResource::Text {
                    text,
                    uri,
                    mime_type,
                    meta,
                } => {
                    let mut v = s::TextResourceContents::new(text, uri);
                    v.mime_type = mime_type;
                    v.meta = opt_protocol_meta(meta)?;
                    s::EmbeddedResourceResource::TextResourceContents(v)
                }
                BridgeAcpEmbeddedResource::Blob {
                    blob,
                    uri,
                    mime_type,
                    meta,
                } => {
                    let mut v = s::BlobResourceContents::new(blob, uri);
                    v.mime_type = mime_type;
                    v.meta = opt_protocol_meta(meta)?;
                    s::EmbeddedResourceResource::BlobResourceContents(v)
                }
            };
            let mut v = s::EmbeddedResource::new(resource);
            v.annotations = annotations.map(protocol_annotations).transpose()?;
            v.meta = opt_protocol_meta(meta)?;
            s::ContentBlock::Resource(v)
        }
    })
}
fn annotations(v: s::Annotations) -> R<BridgeAcpAnnotations> {
    Ok(BridgeAcpAnnotations {
        audience: v
            .audience
            .map(|v| {
                many(v, |v| {
                    Ok(match v {
                        s::Role::User => BridgeAcpRole::User,
                        s::Role::Assistant => BridgeAcpRole::Assistant,
                        _ => return Err(unsupported("Role")),
                    })
                })
            })
            .transpose()?,
        last_modified: v.last_modified,
        priority: v.priority,
        meta: opt_meta(v.meta)?,
    })
}
fn protocol_annotations(v: BridgeAcpAnnotations) -> R<s::Annotations> {
    let mut result = s::Annotations::new();
    result.audience = v.audience.map(|roles| {
        roles
            .into_iter()
            .map(|r| match r {
                BridgeAcpRole::User => s::Role::User,
                BridgeAcpRole::Assistant => s::Role::Assistant,
            })
            .collect()
    });
    result.last_modified = v.last_modified;
    result.priority = v.priority;
    result.meta = opt_protocol_meta(v.meta)?;
    Ok(result)
}
