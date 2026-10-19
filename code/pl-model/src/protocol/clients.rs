//! Concrete clients retain native capabilities while sharing one invocation runner.
use super::{ProtocolEndpoint, ProtocolKind};
use crate::runtime::InvocationRunner;
use pl_protocol::Result;

/// Runtime route with statically named native clients. Matching exposes their concrete APIs.
#[derive(Debug, Clone)]
pub enum ProtocolClient<'a> {
    OpenAi(super::openai::OpenAiClient<'a>),
    DeepSeek(super::deepseek::DeepSeekClient<'a>),
    Zhipu(super::zhipu::ZhipuClient<'a>),
    MiMo(super::mimo::MiMoClient<'a>),
    Xai(super::xai::XaiClient<'a>),
    OpenAiCompatible(super::compatible::CompatibleClient<'a>),
}

impl<'a> ProtocolClient<'a> {
    pub(crate) fn new(endpoint: &ProtocolEndpoint, runner: &'a InvocationRunner) -> Self {
        let kind = endpoint.protocol;
        match kind {
            ProtocolKind::OpenAi => Self::OpenAi(super::openai::OpenAiClient { runner }),
            ProtocolKind::DeepSeek => Self::DeepSeek(super::deepseek::DeepSeekClient { runner }),
            ProtocolKind::Zhipu => Self::Zhipu(super::zhipu::ZhipuClient { runner }),
            ProtocolKind::MiMo => Self::MiMo(super::mimo::MiMoClient { runner }),
            ProtocolKind::Xai => Self::Xai(super::xai::XaiClient { runner }),
            ProtocolKind::OpenAiCompatible => {
                Self::OpenAiCompatible(super::compatible::CompatibleClient { runner })
            }
        }
    }
}

pub(super) fn native_body(
    options: impl serde::Serialize,
) -> Result<serde_json::Map<String, serde_json::Value>> {
    let value = serde_json::to_value(options)?;
    match value {
        serde_json::Value::Object(body) => Ok(body),
        _ => Err(pl_protocol::PureError::Protocol(
            "native request options must be an object".into(),
        )),
    }
}
