//! Shared media profiles and parameter wire assignments.

use serde_json::Value;

use crate::model::capabilities::ModelModality;
use crate::model::info::{
    MediaRepresentation, MediaWireFormat, ModelMediaInputProfile, ModelRequestProfile,
};
use crate::model::parameter::{ModelParameter, ParameterWire, WireAssignment};

impl ModelRequestProfile {
    /// 覆盖 profile 的图片媒体表示顺序。
    pub fn with_image_media(mut self, wire: MediaWireFormat, send_order: MediaSendOrder) -> Self {
        self.media = image_media_profiles(wire, send_order);
        self
    }
}

/// 图片首发与重放表示的顺序策略。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum MediaSendOrder {
    /// 优先使用供应商文件，其次远端 URL，最后回退 DataUrl。
    ProviderFileFirst,
    /// 优先发送远端 URL，失败或受限时回退 DataUrl。
    RemoteUrlFirst,
    /// 只发送 DataUrl（模型未声明远端来源时使用）。
    DataUrlOnly,
}

/// 构造图片模态的媒体表示 profile。
pub fn image_media_profiles(
    wire: MediaWireFormat,
    send_order: MediaSendOrder,
) -> Vec<ModelMediaInputProfile> {
    vec![media_profile(ModelModality::Image, wire, send_order)]
}

pub fn media_profile(
    modality: ModelModality,
    wire: MediaWireFormat,
    send_order: MediaSendOrder,
) -> ModelMediaInputProfile {
    let (first_send, replay) = match send_order {
        MediaSendOrder::ProviderFileFirst => (
            vec![
                MediaRepresentation::ProviderFile,
                MediaRepresentation::RemoteUrl,
                MediaRepresentation::DataUrl,
            ],
            vec![
                MediaRepresentation::ProviderFile,
                MediaRepresentation::DataUrl,
            ],
        ),
        MediaSendOrder::RemoteUrlFirst => (
            vec![MediaRepresentation::RemoteUrl, MediaRepresentation::DataUrl],
            vec![MediaRepresentation::DataUrl],
        ),
        MediaSendOrder::DataUrlOnly => (
            vec![MediaRepresentation::DataUrl],
            vec![MediaRepresentation::DataUrl],
        ),
    };
    ModelMediaInputProfile {
        modality,
        wire,
        first_send,
        replay,
    }
}

/// 构造「把单个字段设为字符串值」的 wire。
pub fn wire_set_one(path: &str, value: &str) -> ParameterWire {
    ParameterWire {
        set: vec![WireAssignment {
            path: path.to_string(),
            value: Value::String(value.to_string()),
        }],
        remove: Vec::new(),
    }
}

/// Declare effort values that the wire accepts without translation.
pub fn effort_parameter(path: &str, candidates: &[&str], default: Option<&str>) -> ModelParameter {
    ModelParameter {
        candidate_display_names: Default::default(),
        name: "effort".into(),
        label: None,
        default: default.map(str::to_owned),
        candidates: candidates.iter().map(|&effort| effort.to_owned()).collect(),
        wire: candidates
            .iter()
            .map(|&effort| (effort.into(), wire_set_one(path, effort)))
            .collect(),
    }
}
