//! xAI `/models`: `data`/`id`、`context_length`、官方 token 价格单位与
//! `capabilities.reasoning_effort` / `default_reasoning_effort`。
use super::reasoning::ReasoningDeclaration;
use super::{DiscoveryDialect, ModelCatalogQueryError, Record, nullable, required_id};
use crate::model::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct Envelope {
    data: Option<Vec<WireRecord>>,
    /// OpenAI/Codex 的富 envelope 名称；出现在本厂商响应中即歧义，不接受。
    models: Option<serde::de::IgnoredAny>,
    error: Option<serde::de::IgnoredAny>,
}

enum OnlinePricing {
    Tokens(ModelPricing),
    Other,
}

impl<'de> Deserialize<'de> for OnlinePricing {
    fn deserialize<D: serde::Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
        let value = serde_json::Value::deserialize(deserializer)?;
        if value
            .get("kind")
            .and_then(serde_json::Value::as_str)
            .is_some_and(|kind| matches!(kind, "rates" | "unknown"))
        {
            serde_json::from_value(value)
                .map(Self::Tokens)
                .map_err(|_| serde::de::Error::custom("invalid token pricing declaration"))
        } else {
            Ok(Self::Other)
        }
    }
}

#[derive(Deserialize)]
struct WireCapabilities {
    reasoning_effort: Option<Vec<String>>,
    #[serde(default, deserialize_with = "nullable")]
    default_reasoning_effort: Option<Option<String>>,
}

#[derive(Deserialize)]
struct WireRecord {
    id: Option<String>,
    name: Option<String>,
    display_name: Option<String>,
    context_length: Option<u64>,
    pricing: Option<OnlinePricing>,
    prompt_text_token_price: Option<f64>,
    completion_text_token_price: Option<f64>,
    cached_prompt_text_token_price: Option<f64>,
    prompt_text_token_price_long_context: Option<f64>,
    completion_text_token_price_long_context: Option<f64>,
    cached_prompt_text_token_price_long_context: Option<f64>,
    long_context_threshold: Option<u64>,
    capabilities: Option<WireCapabilities>,
    /// 传输 profile 仍由本账号观察声明；未声明的模态/窗口扩展字段按上游扩展忽略。
    binding: Option<ModelBinding>,
}

impl WireRecord {
    /// xAI 官方 token 价格单位为 USD cents / 100M tokens；其它计费单位不冒充 token 单价。
    fn online_pricing(&self) -> Result<Option<ModelPricing>, ModelCatalogQueryError> {
        if [
            self.prompt_text_token_price,
            self.completion_text_token_price,
            self.cached_prompt_text_token_price,
            self.prompt_text_token_price_long_context,
            self.completion_text_token_price_long_context,
            self.cached_prompt_text_token_price_long_context,
        ]
        .into_iter()
        .flatten()
        .any(|price| !price.is_finite() || price < 0.0)
        {
            return Err(ModelCatalogQueryError::Protocol);
        }
        let pricing = match &self.pricing {
            Some(OnlinePricing::Tokens(ModelPricing::Unknown)) => None,
            Some(OnlinePricing::Tokens(pricing)) => Some(pricing.clone()),
            _ => match (
                self.prompt_text_token_price,
                self.completion_text_token_price,
            ) {
                (Some(input), Some(output)) => {
                    let mut tiers = vec![TokenPriceTier::flat(
                        input / 10_000.0,
                        output / 10_000.0,
                        self.cached_prompt_text_token_price.map(|p| p / 10_000.0),
                        None,
                    )];
                    if let Some(threshold) = self.long_context_threshold.filter(|v| *v > 0) {
                        tiers[0].input_until = Some(threshold);
                        let mut long = TokenPriceTier::flat(
                            self.prompt_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .unwrap_or(input)
                                / 10_000.0,
                            self.completion_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .unwrap_or(output)
                                / 10_000.0,
                            self.cached_prompt_text_token_price_long_context
                                .filter(|v| *v != 0.0)
                                .or(self.cached_prompt_text_token_price)
                                .map(|v| v / 10_000.0),
                            None,
                        );
                        long.input_from = threshold;
                        tiers.push(long);
                    }
                    Some(ModelPricing::published_at(
                        "USD",
                        tiers,
                        "provider model catalog",
                        0,
                    ))
                }
                (None, None) => None,
                _ => return Err(ModelCatalogQueryError::Protocol),
            },
        };
        if let Some(value) = &pricing {
            value
                .validate()
                .map_err(|_| ModelCatalogQueryError::Protocol)?;
        }
        Ok(pricing)
    }

    fn into_record(self) -> Result<Record, ModelCatalogQueryError> {
        let pricing = self.online_pricing()?;
        let reasoning = self
            .capabilities
            .as_ref()
            .and_then(|capabilities| capabilities.reasoning_effort.clone())
            .map(|levels| {
                ReasoningDeclaration::from_effort(
                    levels,
                    self.capabilities
                        .as_ref()
                        .and_then(|capabilities| capabilities.default_reasoning_effort.clone())
                        .flatten(),
                )
            })
            .unwrap_or_default();
        let id = required_id(self.id)?;
        Ok(Record {
            id,
            display_name: self.display_name.or(self.name),
            context_window: self.context_length.map(Some),
            reasoning,
            binding: self.binding,
            pricing,
            unknown_default_input: None,
            ..Record::default()
        })
    }
}

pub(super) fn records(
    bytes: &[u8],
    _dialect: DiscoveryDialect,
) -> Result<Vec<Record>, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.models.is_some() {
        return Err(ModelCatalogQueryError::Protocol);
    }
    let records = envelope.data.ok_or(ModelCatalogQueryError::Protocol)?;
    records.into_iter().map(WireRecord::into_record).collect()
}
