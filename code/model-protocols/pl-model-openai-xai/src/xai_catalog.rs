//! xAI `/models`: `data`/`id`、`context_length`、官方 token 价格单位与
//! `capabilities.reasoning_effort` / `default_reasoning_effort`。
use pl_model_wire::discovery::reasoning::ReasoningDeclaration;
use pl_model_wire::discovery::{ModelCatalogQueryError, Record, nullable};
use pl_model_wire::generic_catalog::{standard_record, with_standard_records};
use pl_model_wire::model::*;
use serde::Deserialize;

#[derive(Deserialize)]
struct WireCapabilities {
    reasoning_effort: Option<Vec<String>>,
    #[serde(default, deserialize_with = "nullable")]
    default_reasoning_effort: Option<Option<String>>,
}

#[derive(Deserialize)]
struct WireRecord {
    context_length: Option<u64>,
    prompt_text_token_price: Option<f64>,
    completion_text_token_price: Option<f64>,
    cached_prompt_text_token_price: Option<f64>,
    prompt_text_token_price_long_context: Option<f64>,
    completion_text_token_price_long_context: Option<f64>,
    cached_prompt_text_token_price_long_context: Option<f64>,
    long_context_threshold: Option<u64>,
    capabilities: Option<WireCapabilities>,
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
        let pricing = match (
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
        };
        if let Some(value) = &pricing {
            value
                .validate()
                .map_err(|_| ModelCatalogQueryError::Protocol)?;
        }
        Ok(pricing)
    }

    fn supplement(self, record: &mut Record) -> Result<(), ModelCatalogQueryError> {
        if record.pricing.is_none() {
            record.pricing = self.online_pricing()?;
        }
        if record.context_window.is_none() {
            record.context_window = self.context_length.map(Some);
        }
        if !record.reasoning.declares_parameters()
            && let Some(capabilities) = self.capabilities
            && let Some(levels) = capabilities.reasoning_effort
        {
            record.reasoning = ReasoningDeclaration::from_effort(
                levels,
                capabilities.default_reasoning_effort.flatten(),
            );
        }
        Ok(())
    }
}

pub fn records(bytes: &[u8]) -> Result<Vec<Record>, ModelCatalogQueryError> {
    with_standard_records(bytes, |value| {
        let native: WireRecord =
            serde_json::from_value(value.clone()).map_err(|_| ModelCatalogQueryError::Protocol)?;
        let mut record = standard_record(value)?;
        native.supplement(&mut record)?;
        Ok(record)
    })
}

pub fn page(
    bytes: &[u8],
) -> Result<pl_model_wire::discovery::ParsedCatalogPage, ModelCatalogQueryError> {
    Ok(pl_model_wire::discovery::ParsedCatalogPage {
        records: records(bytes)?,
        next_page_token: None,
    })
}
