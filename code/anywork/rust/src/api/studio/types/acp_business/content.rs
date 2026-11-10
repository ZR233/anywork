use super::BridgeAcpMeta;

#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpContentBlock {
    Text {
        text: String,
        annotations: Option<BridgeAcpAnnotations>,
        meta: Option<BridgeAcpMeta>,
    },
    Image {
        data: String,
        mime_type: String,
        uri: Option<String>,
        annotations: Option<BridgeAcpAnnotations>,
        meta: Option<BridgeAcpMeta>,
    },
    Audio {
        data: String,
        mime_type: String,
        annotations: Option<BridgeAcpAnnotations>,
        meta: Option<BridgeAcpMeta>,
    },
    ResourceLink {
        name: String,
        uri: String,
        description: Option<String>,
        mime_type: Option<String>,
        size: Option<i64>,
        title: Option<String>,
        annotations: Option<BridgeAcpAnnotations>,
        meta: Option<BridgeAcpMeta>,
    },
    Resource {
        resource: BridgeAcpEmbeddedResource,
        annotations: Option<BridgeAcpAnnotations>,
        meta: Option<BridgeAcpMeta>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub enum BridgeAcpEmbeddedResource {
    Text {
        text: String,
        uri: String,
        mime_type: Option<String>,
        meta: Option<BridgeAcpMeta>,
    },
    Blob {
        blob: String,
        uri: String,
        mime_type: Option<String>,
        meta: Option<BridgeAcpMeta>,
    },
}
#[derive(Debug, Clone, PartialEq)]
pub struct BridgeAcpAnnotations {
    pub audience: Option<Vec<BridgeAcpRole>>,
    pub last_modified: Option<String>,
    pub priority: Option<f64>,
    pub meta: Option<BridgeAcpMeta>,
}
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BridgeAcpRole {
    Assistant,
    User,
}
