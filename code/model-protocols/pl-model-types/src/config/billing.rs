use serde::{Deserialize, Serialize};
/// 账号计费意图的唯一事实源；请求由此冻结 [`crate::model::PricingMode`]。
///
/// `subscription` 只表示账号走订阅计量，不证明订阅有效、额度充足或实际零费用；
/// 未知价格也不能被解释为免费。
#[derive(
    Debug,
    Clone,
    Copy,
    Default,
    Serialize,
    Deserialize,
    PartialEq,
    Eq,
    schemars::JsonSchema,
    utoipa::ToSchema,
)]
#[serde(rename_all = "camelCase")]
pub enum BillingKind {
    Metered,
    Subscription,
    /// 用户声明后续调用不计费；不抹去模型目录参考价格。
    NoCharge,
    #[default]
    Unknown,
}

pl_protocol::impl_labeled_enum!(
    BillingKind,
    "BillingKind",
    [
        BillingKind::Metered => "metered",
        BillingKind::Subscription => "subscription",
        BillingKind::NoCharge => "noCharge",
        BillingKind::Unknown => "unknown",
    ]
);
