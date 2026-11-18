use pl_protocol::FirstOutputSource;
use serde::{Deserialize, Serialize};

/// 一次成功 inference 的单调时钟耗时事实。
///
/// 三者以产生成功结果的 transport attempt 发送为起点；失败尝试、退避和工具执行不混入。
/// `response_millis` 到归一化终止事件到达为止，不包含其后的消费、展示与保存开销，也是输出
/// 吞吐的分母。`ttft_millis` 是首次非空内容观测；完整工具项也可提供边界，来源单独保留。
/// `decode_millis` 只是 `response - ttft` 的诊断值，不作为吞吐分母。
///
/// 旧口径的序列化只带 `totalMillis`；该字段不属于当前契约，解码后 `response_millis` 为 0，
/// 因此旧样本不会被当作可用速度重新读出。
#[derive(Debug, Clone, Copy, Default, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct InferenceTiming {
    pub first_output_source: FirstOutputSource,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ttft_millis: Option<u64>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub decode_millis: Option<u64>,
    #[serde(default)]
    pub response_millis: u64,
}

impl InferenceTiming {
    /// 已知总响应为正、可选首字边界一致时才可与输出词元组成吞吐样本。
    ///
    /// 首字未知不阻止输出吞吐：它只让首字延迟和首字后诊断耗时保持未知。
    pub fn has_throughput_sample(self) -> bool {
        self.response_millis > 0 && self.first_output_boundary_consistent()
    }

    /// 首字边界只能整组存在或整组未知，且存在时必须落在总响应之内。
    fn first_output_boundary_consistent(self) -> bool {
        match (self.ttft_millis, self.decode_millis) {
            (None, None) => true,
            (Some(ttft_millis), Some(decode_millis)) => {
                ttft_millis <= self.response_millis
                    && decode_millis == self.response_millis - ttft_millis
            }
            (Some(_), None) | (None, Some(_)) => false,
        }
    }
}
