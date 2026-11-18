use pl_model_openai_wire::protocol::*;

pub const ID: ProtocolId = ProtocolId::from_static("zhipu");

pub const CODING_PLAN_BASE_URL: &str = "https://open.bigmodel.cn/api/v1";
pub fn endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    ProtocolEndpoint::new(
        ID,
        "Zhipu",
        base_url.unwrap_or_else(|| "https://open.bigmodel.cn/api/paas/v4".into()),
    )
}
pub fn coding_plan_endpoint(base_url: Option<String>) -> ProtocolEndpoint {
    ProtocolEndpoint::new(
        ID,
        "Zhipu Coding Plan",
        base_url.unwrap_or_else(|| CODING_PLAN_BASE_URL.into()),
    )
}
