use std::collections::{BTreeMap, btree_map::Entry};

use reqwest::Url;
use serde_json::{Map, Value};

use super::input_schema::{CHILDREN, LISTS, TABLES};

pub const HOSTED_OUTPUT_SCHEMA_DIALECT: &str = "https://json-schema.org/draft/2020-12/schema";

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum HostedOutputSchemaError {
    #[error("hosted output schema requires JSON Schema 2020-12")]
    UnsupportedDialect,
    #[error(
        "hosted output schema $id must be fragment-free and resolve using the author-provided base URI"
    )]
    InvalidId,
    #[error("hosted output schema {0} needs a resolvable author-provided absolute base URI")]
    MissingReferenceBase(&'static str),
    #[error("conflicting output schema $id {0}")]
    ConflictingId(String),
}

/// Resource identities shared by the hosted output declarations in one request.
#[derive(Default)]
pub struct HostedOutputSchemaResources<'a> {
    by_id: BTreeMap<Url, &'a Map<String, Value>>,
}

impl<'a> HostedOutputSchemaResources<'a> {
    /// Embeds the author schema as its own resource without changing its assertions or references.
    /// An unspecified dialect defaults to 2020-12.
    pub fn embed(
        &mut self,
        tool_name: &str,
        schema: &'a Map<String, Value>,
    ) -> Result<Value, HostedOutputSchemaError> {
        self.visit(schema, None)?;
        let mut resource = schema.clone();
        resource
            .entry("$schema")
            .or_insert_with(|| HOSTED_OUTPUT_SCHEMA_DIALECT.into());
        // JSON Schema Core 2020-12 §§8.2.1 and 9.3: local fragments resolve within this
        // resource. An anonymous author's relative references cannot use the generated ID.
        if let serde_json::map::Entry::Vacant(entry) = resource.entry("$id") {
            let identity = serde_json::json!([tool_name, schema]).to_string();
            let digest = pl_core::context::content_hash(identity.as_bytes());
            let id = format!("https://anywork.invalid/responses/tool-output/{digest}");
            self.register(Url::parse(&id).expect("generated schema URI"), schema)?;
            entry.insert(id.into());
        }
        Ok(Value::Object(resource))
    }

    fn visit(
        &mut self,
        schema: &'a Map<String, Value>,
        author_base: Option<&Url>,
    ) -> Result<(), HostedOutputSchemaError> {
        if let Some(dialect) = schema.get("$schema")
            && dialect.as_str() != Some(HOSTED_OUTPUT_SCHEMA_DIALECT)
        {
            return Err(HostedOutputSchemaError::UnsupportedDialect);
        }
        let id = schema
            .get("$id")
            .map(|value| {
                value
                    .as_str()
                    .filter(|id| {
                        !id.is_empty()
                            && !id.contains('#')
                            && id.bytes().all(|byte| byte.is_ascii_graphic())
                    })
                    .and_then(|id| resolve_uri(id, author_base))
                    .ok_or(HostedOutputSchemaError::InvalidId)
            })
            .transpose()?;
        if let Some(id) = &id {
            self.register(id.clone(), schema)?;
        }
        let author_base = id.as_ref().or(author_base);
        for keyword in ["$ref", "$dynamicRef"] {
            if let Some(uri) = schema.get(keyword).and_then(Value::as_str)
                && !uri.is_empty()
                && !uri.starts_with('#')
                && resolve_uri(uri, author_base).is_none()
            {
                return Err(HostedOutputSchemaError::MissingReferenceBase(keyword));
            }
        }

        // Only schema-valued positions define resource scope. Data in const, enum and
        // examples may contain the same keys without expressing references or a dialect.
        let tables = TABLES
            .iter()
            .filter_map(|key| schema.get(*key)?.as_object())
            .flat_map(Map::values);
        let lists = LISTS
            .iter()
            .filter_map(|key| schema.get(*key)?.as_array())
            .flatten();
        let single = CHILDREN.iter().filter_map(|key| schema.get(*key));
        for child in tables
            .chain(lists)
            .chain(single)
            .filter_map(Value::as_object)
        {
            self.visit(child, author_base)?;
        }
        Ok(())
    }

    fn register(
        &mut self,
        id: Url,
        schema: &'a Map<String, Value>,
    ) -> Result<(), HostedOutputSchemaError> {
        match self.by_id.entry(id) {
            Entry::Vacant(entry) => {
                entry.insert(schema);
                Ok(())
            }
            Entry::Occupied(entry) if same_resource(entry.get(), schema) => Ok(()),
            Entry::Occupied(entry) => Err(HostedOutputSchemaError::ConflictingId(
                entry.key().to_string(),
            )),
        }
    }
}

fn resolve_uri(reference: &str, base: Option<&Url>) -> Option<Url> {
    Url::parse(reference)
        .ok()
        .or_else(|| base?.join(reference).ok())
}

fn same_resource(a: &Map<String, Value>, b: &Map<String, Value>) -> bool {
    // The registry key has already resolved the ID and every resource uses 2020-12.
    fn fields(schema: &Map<String, Value>) -> impl Iterator<Item = (&String, &Value)> {
        schema
            .iter()
            .filter(|(key, _)| !matches!(key.as_str(), "$id" | "$schema"))
    }
    fields(a).count() == fields(b).count()
        && fields(a).all(|(key, value)| b.get(key) == Some(value))
}
