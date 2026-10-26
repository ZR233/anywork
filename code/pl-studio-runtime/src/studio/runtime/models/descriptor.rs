use pl_protocol::products::read::models::*;
use pl_protocol::studio::StudioError;

use super::fields::{DescriptorText, ListField, ModelPath, StringList, TextField};
use super::material::{ModelReadMaterial, wrong_field};

impl ModelReadMaterial {
    pub(super) fn model_read(
        &self,
        path: ModelPath,
        inline: usize,
    ) -> Result<ModelDescriptorRead, StudioError> {
        let model = self.model(path)?;
        let text = |field| self.read(TextField::Model(path, field), inline);
        let context = &model.context;
        let capabilities = &model.capabilities;
        let reasoning = model
            .reasoning
            .as_ref()
            .map(|value| -> Result<_, StudioError> {
                Ok(ModelReasoningDescriptorRead {
                    parameter: text(DescriptorText::ReasoningParameter)?,
                    label: text(DescriptorText::ReasoningLabel)?,
                    default: value
                        .default
                        .as_ref()
                        .map(|_| text(DescriptorText::ReasoningDefault))
                        .transpose()?,
                    candidates: self.list(
                        ListField::Strings(StringList::Candidates(path)),
                        value.candidates.len(),
                    )?,
                })
            })
            .transpose()?;
        let pricing = model
            .pricing
            .as_ref()
            .map(|value| -> Result<_, StudioError> {
                Ok(ModelPricingRead {
                    currency: text(DescriptorText::PricingCurrency)?,
                    tiers: self.list(ListField::Tiers(path), value.tiers.len())?,
                    source: text(DescriptorText::PricingSource)?,
                    verified_at: value.verified_at,
                })
            })
            .transpose()?;
        Ok(ModelDescriptorRead {
            model_id: text(DescriptorText::Id)?,
            type_support: self.list(ListField::TypeSupport(path), model.type_support.len())?,
            origin: model.origin,
            enabled: model.enabled,
            display_name: text(DescriptorText::DisplayName)?,
            description: model
                .description
                .as_ref()
                .map(|_| text(DescriptorText::Description))
                .transpose()?,
            context_window: model.context_window,
            max_context_window: model.max_context_window,
            context: ModelContextResolutionRead {
                unavailable: context.unavailable,
                context_window: context.context_window,
                input_token_limit: context.input_token_limit,
                auto_compact_limit: context.auto_compact_limit,
                adjustment: context.adjustment,
            },
            max_output_tokens: model.max_output_tokens,
            transport: ModelTransportDescriptorRead {
                protocol: text(DescriptorText::Protocol)?,
                connection_modes: self.list(
                    ListField::ConnectionModes(path),
                    model.transport.connection_modes.len(),
                )?,
                default_connection_mode: text(DescriptorText::DefaultConnection)?,
            },
            capabilities: ModelCapabilitiesRead {
                input: self.list(ListField::Inputs(path), capabilities.input.len())?,
                output: self.list(ListField::Modalities(path), capabilities.output.len())?,
                streaming: capabilities.streaming,
                temperature: capabilities.temperature,
                reasoning: capabilities.reasoning,
                web_search: capabilities.web_search,
                function_calling: capabilities.function_calling,
                parallel_tool_calls: capabilities.parallel_tool_calls,
                custom_tools: capabilities.custom_tools,
                freeform_tools: capabilities.freeform_tools,
                instruction_snapshot_overrides: capabilities.instruction_snapshot_overrides,
                native_context_family: capabilities
                    .native_context_family
                    .as_ref()
                    .map(|_| text(DescriptorText::NativeContext))
                    .transpose()?,
            },
            reasoning,
            pricing,
        })
    }

    pub(super) fn type_support_read(
        &self,
        path: ModelPath,
        index: usize,
    ) -> Result<ModelTypeSupportRead, StudioError> {
        let value = self
            .model(path)?
            .type_support
            .get(index)
            .ok_or_else(wrong_field)?;
        Ok(ModelTypeSupportRead {
            model_type: value.model_type,
            exclusions: self.list(ListField::Exclusions(path, index), value.exclusions.len())?,
        })
    }

    pub(super) fn connection_read(
        &self,
        path: ModelPath,
        index: usize,
        inline: usize,
    ) -> Result<ConnectionModeRead, StudioError> {
        self.model(path)?
            .transport
            .connection_modes
            .get(index)
            .ok_or_else(wrong_field)?;
        Ok(ConnectionModeRead {
            id: self.read(TextField::ConnectionId(path, index), inline)?,
            display_name: self.read(TextField::ConnectionName(path, index), inline)?,
        })
    }

    pub(super) fn input_read(
        &self,
        path: ModelPath,
        index: usize,
    ) -> Result<ModelInputCapabilityRead, StudioError> {
        let value = self
            .model(path)?
            .capabilities
            .input
            .get(index)
            .ok_or_else(wrong_field)?;
        Ok(ModelInputCapabilityRead {
            modality: value.modality,
            sources: self.list(ListField::InputSources(path, index), value.sources.len())?,
            max_count: value.max_count,
            max_bytes: value.max_bytes,
            max_total_bytes: value.max_total_bytes,
            max_width: value.max_width,
            max_height: value.max_height,
            media_types: self.list(
                ListField::Strings(StringList::MediaTypes(path, index)),
                value.media_types.len(),
            )?,
        })
    }

    pub(super) fn tier_read(
        &self,
        path: ModelPath,
        index: usize,
        inline: usize,
    ) -> Result<ModelPriceTierRead, StudioError> {
        let value = self
            .model(path)?
            .pricing
            .as_ref()
            .and_then(|pricing| pricing.tiers.get(index))
            .ok_or_else(wrong_field)?;
        Ok(ModelPriceTierRead {
            label: self.read(TextField::TierLabel(path, index), inline)?,
            input_per_mtok: value.input_per_mtok,
            output_per_mtok: value.output_per_mtok,
            cache_read_per_mtok: value.cache_read_per_mtok,
            cache_write_per_mtok: value.cache_write_per_mtok,
        })
    }
}
