//! DeepSeek adds its Chat thinking switch to standard model-list entries.
use pl_model_openai_wire::{
    discovery::{ModelCatalogQueryError, Record},
    generic_catalog::{standard_record, with_standard_records},
};

pub fn records(bytes: &[u8]) -> Result<Vec<Record>, ModelCatalogQueryError> {
    with_standard_records(bytes, |value| {
        let mut record = standard_record(value)?;
        record.thinking_base_body = true;
        Ok(record)
    })
}
