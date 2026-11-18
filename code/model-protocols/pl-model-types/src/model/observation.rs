//! Explicit online fields and their durable acquisition order. Inherited defaults are not observations.
use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum ModelMetadataField {
    DisplayName,
    Description,
    ContextWindow,
    MaxContextWindow,
    AutoCompactTokenLimit,
    MaxOutputTokens,
    DefaultTemperature,
    Input,
    Output,
    Streaming,
    Temperature,
    Reasoning,
    WebSearch,
    FunctionCalling,
    ParallelToolCalls,
    CustomTools,
    FreeformTools,
    ProgrammaticToolCalling,
    Parameters,
    Interleaved,
    PromptCache,
    InstructionSnapshotOverrides,
    NativeContextFamily,
    TruncationPolicy,
    BaseInstructions,
}

/// Zero is an uncommitted response field; the host stamps it when accepting the response.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelObservation {
    pub fields: BTreeMap<ModelMetadataField, u64>,
    /// Original budget declarations, before paired budget normalization. A later
    /// field must never promote an inherited/derived companion to an online fact.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub budgets: BTreeMap<ModelMetadataField, Option<u64>>,
    /// Defaults have their own clock: a candidate-only update cannot promote an inherited default.
    #[serde(default, skip_serializing_if = "BTreeMap::is_empty")]
    pub parameter_defaults: BTreeMap<String, ModelParameterDefaultObservation>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub price_order: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct ModelParameterDefaultObservation {
    pub value: Option<String>,
    pub order: u64,
}

impl ModelObservation {
    pub fn declare(&mut self, field: ModelMetadataField) {
        self.fields.insert(field, 0);
    }

    pub fn commit(&mut self, order: u64) {
        if self.price_order == Some(0) {
            self.price_order = Some(order);
        }
        for value in self.fields.values_mut() {
            if *value == 0 {
                *value = order;
            }
        }
        for default in self.parameter_defaults.values_mut() {
            if default.order == 0 {
                default.order = order;
            }
        }
    }

    pub fn latest_order(&self) -> u64 {
        self.fields
            .values()
            .copied()
            .chain(self.price_order)
            .chain(
                self.parameter_defaults
                    .values()
                    .map(|default| default.order),
            )
            .max()
            .unwrap_or(0)
    }
}
