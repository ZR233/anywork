use anyhow::Result;
use serde::{Deserialize, Serialize};
use version_migrate::{IntoDomain, MigratesTo, Migrator, Versioned};

use super::{ATTACHMENT_CATALOG_SCHEMA_VERSION, AttachmentCatalog};

const ENTITY: &str = "attachment-catalog";
const VERSION_KEY: &str = "schemaVersion";

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
enum AttachmentModalityV1 {
    Image,
    Video,
    File,
}

impl From<pl_protocol::studio::StudioAttachmentModality> for AttachmentModalityV1 {
    fn from(value: pl_protocol::studio::StudioAttachmentModality) -> Self {
        match value {
            pl_protocol::studio::StudioAttachmentModality::Image => Self::Image,
            pl_protocol::studio::StudioAttachmentModality::Video => Self::Video,
            pl_protocol::studio::StudioAttachmentModality::File => Self::File,
        }
    }
}

impl From<AttachmentModalityV1> for pl_protocol::studio::StudioAttachmentModality {
    fn from(value: AttachmentModalityV1) -> Self {
        match value {
            AttachmentModalityV1::Image => Self::Image,
            AttachmentModalityV1::Video => Self::Video,
            AttachmentModalityV1::File => Self::File,
        }
    }
}

#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AttachmentRecordV1 {
    id: String,
    thread_id: String,
    modality: AttachmentModalityV1,
    media_type: String,
    filename: Option<String>,
    #[serde(rename = "storagePath")]
    blob_relative_path: String,
    byte_size: u64,
    content_sha256: String,
    width: Option<u32>,
    height: Option<u32>,
    created_at: i64,
}

#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "1.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AttachmentCatalogV1 {
    thread_id: String,
    records: Vec<AttachmentRecordV1>,
}

impl IntoDomain<AttachmentRecordV1> for AttachmentRecordV1 {
    fn into_domain(self) -> AttachmentRecordV1 {
        self
    }
}

impl IntoDomain<AttachmentCatalogV1> for AttachmentCatalogV1 {
    fn into_domain(self) -> AttachmentCatalogV1 {
        self
    }
}

#[derive(Debug, Serialize, Deserialize, Versioned)]
#[versioned(version = "2.0.0")]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct AttachmentCatalogV2 {
    thread_id: String,
    records: Vec<AttachmentRecordV1>,
}
impl MigratesTo<AttachmentCatalogV2> for AttachmentCatalogV1 {
    fn migrate(self) -> AttachmentCatalogV2 {
        AttachmentCatalogV2 {
            thread_id: self.thread_id,
            records: self.records,
        }
    }
}
impl IntoDomain<AttachmentCatalogV2> for AttachmentCatalogV2 {
    fn into_domain(self) -> Self {
        self
    }
}
fn from_domain(document: &AttachmentCatalog) -> AttachmentCatalogV2 {
    AttachmentCatalogV2 {
        thread_id: document.thread_id.clone(),
        records: document
            .records
            .iter()
            .map(|record| AttachmentRecordV1 {
                id: record.id.clone(),
                thread_id: record.thread_id.clone(),
                modality: record.modality.into(),
                media_type: record.media_type.clone(),
                filename: record.filename.clone(),
                blob_relative_path: record.blob_relative_path.clone(),
                byte_size: record.byte_size,
                content_sha256: record.content_sha256.clone(),
                width: record.width,
                height: record.height,
                created_at: record.created_at,
            })
            .collect(),
    }
}

impl From<AttachmentCatalogV2> for AttachmentCatalog {
    fn from(document: AttachmentCatalogV2) -> Self {
        Self {
            schema_version: ATTACHMENT_CATALOG_SCHEMA_VERSION,
            thread_id: document.thread_id,
            records: document
                .records
                .into_iter()
                .map(|record| crate::studio::records::AttachmentRecord {
                    id: record.id,
                    thread_id: record.thread_id,
                    modality: record.modality.into(),
                    media_type: record.media_type,
                    filename: record.filename,
                    blob_relative_path: record.blob_relative_path,
                    byte_size: record.byte_size,
                    content_sha256: record.content_sha256,
                    width: record.width,
                    height: record.height,
                    created_at: record.created_at,
                })
                .collect(),
        }
    }
}

fn migrator() -> Result<Migrator> {
    let mut migrator = Migrator::new();
    migrator
        .register(
            Migrator::define(ENTITY)
                .with_keys(VERSION_KEY, "data")
                .from::<AttachmentCatalogV1>()
                .step::<AttachmentCatalogV2>()
                .into::<AttachmentCatalogV2>(),
        )
        .map_err(|error| crate::toml_schema::chain_error(ENTITY, error))?;
    Ok(migrator)
}

pub(super) fn decode_v2(path: &std::path::Path, content: &str) -> Result<AttachmentCatalog> {
    let loaded = crate::toml_schema::load::<AttachmentCatalogV1, AttachmentCatalogV2>(
        path,
        content,
        &migrator()?,
        ENTITY,
        VERSION_KEY,
    )?;
    Ok(loaded.document.into())
}

pub(super) fn decode(path: &std::path::Path, content: &str) -> Result<AttachmentCatalog> {
    let document = decode_v2(path, content)?;
    let version: toml::Table = toml::from_str(content)?;
    if version.get(VERSION_KEY).and_then(toml::Value::as_integer) != Some(2) {
        return Err(crate::toml_schema::migration_error(
            path,
            ENTITY,
            Some(1),
            2,
            "preflight",
            anyhow::anyhow!("legacy attachment catalog requires explicit layout migration"),
        ));
    }
    Ok(document)
}
pub(super) fn encode(document: &AttachmentCatalog) -> Result<String> {
    crate::toml_schema::encode(&from_domain(document), VERSION_KEY)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn catalog() -> AttachmentCatalog {
        AttachmentCatalog {
            schema_version: 1,
            thread_id: "thread-a".into(),
            records: vec![crate::studio::records::AttachmentRecord {
                id: "attachment-a".into(),
                thread_id: "thread-a".into(),
                modality: pl_protocol::studio::StudioAttachmentModality::Image,
                media_type: "image/png".into(),
                filename: Some("image.png".into()),
                blob_relative_path: "blobs/aa/blob".into(),
                byte_size: 4,
                content_sha256: "abcd".into(),
                width: Some(2),
                height: Some(2),
                created_at: 7,
            }],
        }
    }

    #[test]
    fn v1_catalog_round_trips_without_changing_the_integer_wire_header() -> Result<()> {
        let expected = catalog();
        let encoded = encode(&expected)?;
        let table: toml::Table = toml::from_str(&encoded)?;
        assert_eq!(table[VERSION_KEY].as_integer(), Some(2));
        let wire_record = table["records"]
            .as_array()
            .and_then(|records| records.first())
            .and_then(toml::Value::as_table)
            .expect("one encoded record");
        assert!(wire_record.contains_key("storagePath"));
        assert!(!wire_record.contains_key("blobRelativePath"));
        let loaded = decode(std::path::Path::new("attachments.toml"), &encoded)?;
        assert_eq!(loaded.thread_id, expected.thread_id);
        assert_eq!(loaded.records, expected.records);
        Ok(())
    }

    #[test]
    fn future_and_missing_catalog_versions_are_typed_document_failures() {
        for input in [
            "schemaVersion = 99\nthreadId = 'thread-a'\nrecords = []\n",
            "threadId = 'thread-a'\nrecords = []\n",
        ] {
            let error =
                decode(std::path::Path::new("attachments.toml"), input).expect_err("must reject");
            assert!(error.chain().any(|cause| {
                cause
                    .downcast_ref::<crate::toml_schema::DocumentMigrationFailed>()
                    .is_some()
            }));
        }
    }
}
