//! Closed vendor protocol adaptations that compose one OpenAI base.
//!
//! Every vendor protocol is a sibling variant and keeps its own catalog interpretation,
//! request defaults and native capabilities. Request preparation, per-invocation decoder
//! creation and catalog decoding dispatch statically through [`ProtocolAdapter`]; the
//! asynchronous HTTP/WebSocket lifecycle, retries and cancellation stay owned by the single
//! invocation runner.
use enum_dispatch::enum_dispatch;
use pl_protocol::Result;

use super::ProtocolKind;
use super::discovery::{ModelCatalogQueryError, decode};
use crate::completion::stream::{CompletionEventStream, OpenAiRawEventStream};
use crate::completion::{CompletionRequest, CompletionTraceContext};
use crate::config::ModelCatalogDiscovery;
use crate::model::ModelInfo;
use crate::protocol::WireApi;
use crate::runtime::openai::{OpenAiBase, OpenAiRequestBody};

/// 厂商协议的同步窄能力；异步生命周期不在这里定义。
///
/// 请求准备与事件解码由全部厂商共享的 [`OpenAiBase`] 提供默认实现；每个适配只提供自己
/// 的目录解释。原生 HTTP/WS、重试和取消仍由唯一执行器拥有。
#[enum_dispatch]
pub(crate) trait ProtocolAdaptation {
    /// 组合复用的 OpenAI base。
    fn base(&self) -> OpenAiBase;

    /// 准备本次 wire 请求体（base body 与 parameter wire 由共享请求组装完成）。
    fn build_request(
        &self,
        api: WireApi,
        request: &CompletionRequest,
        model: &ModelInfo,
        prompt_cache_key: Option<&str>,
    ) -> Result<OpenAiRequestBody> {
        self.base()
            .build_request(api, request, model, prompt_cache_key)
    }

    /// 为一次调用创建独立解码器；解码状态不跨调用共享。
    fn decode_stream(
        &self,
        api: WireApi,
        stream: OpenAiRawEventStream,
        trace: Option<CompletionTraceContext>,
    ) -> CompletionEventStream {
        self.base().decode_stream(api, stream, trace)
    }

    /// 按本厂商 typed 声明解释 `/models` 响应。
    fn decode_catalog(
        &self,
        bytes: &[u8],
        discovery: &ModelCatalogDiscovery,
        previous: Option<&[ModelInfo]>,
        defaults: &[ModelInfo],
    ) -> std::result::Result<Vec<ModelInfo>, ModelCatalogQueryError>;
}

macro_rules! vendor_adapter {
    ($adapter:ident, $dialect:ident) => {
        #[derive(Debug, Clone, Copy, Default)]
        pub(crate) struct $adapter {
            base: OpenAiBase,
        }

        impl ProtocolAdaptation for $adapter {
            fn base(&self) -> OpenAiBase {
                self.base
            }

            fn decode_catalog(
                &self,
                bytes: &[u8],
                discovery: &ModelCatalogDiscovery,
                previous: Option<&[ModelInfo]>,
                defaults: &[ModelInfo],
            ) -> std::result::Result<Vec<ModelInfo>, ModelCatalogQueryError> {
                decode::models(
                    bytes,
                    discovery,
                    decode::DiscoveryDialect::$dialect,
                    previous,
                    defaults,
                )
            }
        }
    };
}

vendor_adapter!(OpenAiAdapter, OpenAi);
vendor_adapter!(DeepSeekAdapter, DeepSeek);
vendor_adapter!(ZhipuAdapter, Generic);
vendor_adapter!(XaiAdapter, Xai);
vendor_adapter!(MiMoAdapter, Generic);
vendor_adapter!(CompatibleAdapter, Generic);

/// 封闭的厂商协议选择；每个适配组合同一个 OpenAI base，但保留自己的解释边界。
#[derive(Debug, Clone, Copy)]
#[enum_dispatch(ProtocolAdaptation)]
pub(crate) enum ProtocolAdapter {
    OpenAi(OpenAiAdapter),
    DeepSeek(DeepSeekAdapter),
    Zhipu(ZhipuAdapter),
    Xai(XaiAdapter),
    MiMo(MiMoAdapter),
    Compatible(CompatibleAdapter),
}

impl ProtocolAdapter {
    pub(crate) fn of(kind: ProtocolKind) -> Self {
        match kind {
            ProtocolKind::OpenAi => Self::OpenAi(OpenAiAdapter::default()),
            ProtocolKind::DeepSeek => Self::DeepSeek(DeepSeekAdapter::default()),
            ProtocolKind::Zhipu => Self::Zhipu(ZhipuAdapter::default()),
            ProtocolKind::Xai => Self::Xai(XaiAdapter::default()),
            ProtocolKind::MiMo => Self::MiMo(MiMoAdapter::default()),
            ProtocolKind::OpenAiCompatible => Self::Compatible(CompatibleAdapter::default()),
        }
    }
}
