use pl_model_wire::discovery::{
    ModelCatalogQueryError, ParsedCatalogPage, Record, presentation_name,
};
use pl_model_wire::model::ModelModality;
use serde::Deserialize;

fn required_id(raw: Option<String>) -> Result<String, ModelCatalogQueryError> {
    raw.map(|value| value.trim().to_owned())
        .filter(|value| !value.is_empty())
        .ok_or(ModelCatalogQueryError::Protocol)
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Envelope {
    models: Option<Vec<GeminiApiModel>>,
    publisher_models: Option<Vec<VertexPublisherModel>>,
    next_page_token: Option<String>,
    error: Option<serde::de::IgnoredAny>,
    data: Option<serde::de::IgnoredAny>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct GeminiApiModel {
    name: Option<String>,
    display_name: Option<String>,
    description: Option<String>,
    input_token_limit: Option<u64>,
    output_token_limit: Option<u64>,
    supported_generation_methods: Option<Vec<String>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct VertexPublisherModel {
    name: Option<String>,
    version_id: Option<String>,
    display_name: Option<String>,
    description: Option<String>,
    input_token_limit: Option<u64>,
    output_token_limit: Option<u64>,
    supported_generation_methods: Option<Vec<String>>,
}

fn normalize_model_id(raw: &str) -> String {
    let trimmed = raw.trim();
    if let Some(rest) = trimmed.strip_prefix("publishers/google/models/") {
        return rest.to_owned();
    }
    if let Some(rest) = trimmed.strip_prefix("models/") {
        return rest.to_owned();
    }
    trimmed.to_owned()
}

fn build_record(
    raw_id: Option<String>,
    display_name: Option<String>,
    description: Option<String>,
    input_token_limit: Option<u64>,
    output_token_limit: Option<u64>,
    supported_generation_methods: Option<Vec<String>>,
) -> Result<Record, ModelCatalogQueryError> {
    let id = required_id(raw_id.map(|s| normalize_model_id(&s)))?;
    let (input_modalities, output_modalities) = match supported_generation_methods {
        Some(methods) => {
            if methods
                .iter()
                .any(|m| matches!(m.as_str(), "generateContent" | "streamGenerateContent"))
            {
                (
                    Some(vec![
                        ModelModality::Text,
                        ModelModality::Image,
                        ModelModality::File,
                    ]),
                    Some(vec![ModelModality::Text]),
                )
            } else {
                (Some(Vec::new()), Some(Vec::new()))
            }
        }
        None => (None, None),
    };
    Ok(Record {
        id,
        display_name: presentation_name(display_name, None),
        description: description.map(Some),
        context_window: input_token_limit.map(Some),
        max_context_window: input_token_limit.map(Some),
        max_output_tokens: output_token_limit.map(Some),
        input_modalities,
        output_modalities,
        ..Record::default()
    })
}

pub fn parse_page(bytes: &[u8]) -> Result<ParsedCatalogPage, ModelCatalogQueryError> {
    let envelope: Envelope =
        serde_json::from_slice(bytes).map_err(|_| ModelCatalogQueryError::Protocol)?;
    if envelope.error.is_some() || envelope.data.is_some() {
        return Err(ModelCatalogQueryError::Protocol);
    }
    let records = match (envelope.models, envelope.publisher_models) {
        (Some(models), None) => models
            .into_iter()
            .map(|m| {
                build_record(
                    m.name,
                    m.display_name,
                    m.description,
                    m.input_token_limit,
                    m.output_token_limit,
                    m.supported_generation_methods,
                )
            })
            .collect::<Result<Vec<_>, _>>()?,
        (None, Some(models)) => models
            .into_iter()
            .map(|m| {
                let raw_id = m.version_id.filter(|v| !v.trim().is_empty()).or(m.name);
                build_record(
                    raw_id,
                    m.display_name,
                    m.description,
                    m.input_token_limit,
                    m.output_token_limit,
                    m.supported_generation_methods,
                )
            })
            .collect::<Result<Vec<_>, _>>()?,
        _ => return Err(ModelCatalogQueryError::Protocol),
    };
    Ok(ParsedCatalogPage {
        records,
        next_page_token: envelope
            .next_page_token
            .filter(|token| !token.trim().is_empty()),
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_gemini_api_models_page_and_non_generative_entries() {
        let json = br#"{
            "models": [
                {
                    "name": "models/gemini-2.5-flash",
                    "displayName": "Gemini 2.5 Flash",
                    "description": "Fast reasoning model",
                    "inputTokenLimit": 1048576,
                    "outputTokenLimit": 65536,
                    "supportedGenerationMethods": ["generateContent", "countTokens"]
                },
                {
                    "name": "models/text-embedding-004",
                    "displayName": "Text Embedding 004",
                    "inputTokenLimit": 2048,
                    "outputTokenLimit": 1,
                    "supportedGenerationMethods": ["embedContent"]
                }
            ],
            "nextPageToken": "page-2"
        }"#;
        let page = parse_page(json).unwrap();
        assert_eq!(page.next_page_token.as_deref(), Some("page-2"));
        assert_eq!(page.records.len(), 2);
        assert_eq!(page.records[0].id, "gemini-2.5-flash");
        assert_eq!(
            page.records[0].display_name.as_deref(),
            Some("Gemini 2.5 Flash")
        );
        assert_eq!(page.records[0].context_window, Some(Some(1_048_576)));
        assert_eq!(page.records[0].max_output_tokens, Some(Some(65_536)));
        assert_eq!(
            page.records[0].output_modalities,
            Some(vec![ModelModality::Text])
        );
        assert_eq!(page.records[1].id, "text-embedding-004");
        assert_eq!(page.records[1].output_modalities, Some(Vec::new()));
    }

    #[test]
    fn parses_vertex_publisher_models_page() {
        let json = br#"{
            "publisherModels": [
                {
                    "name": "publishers/google/models/gemma3",
                    "versionId": "gemma-3-1b-it"
                }
            ]
        }"#;
        let page = parse_page(json).unwrap();
        assert!(page.next_page_token.is_none());
        assert_eq!(page.records.len(), 1);
        assert_eq!(page.records[0].id, "gemma-3-1b-it");
    }
}
