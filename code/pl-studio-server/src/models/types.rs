use pl_protocol::products::{
    identity::{
        ProductEntityRef, ProductReadOrigin, ProductReadScopeIdentity, ProductSourceStatusRef,
    },
    read::delegation_models::DelegationModelReadTarget,
    references::ModelCatalogReadRef,
};

#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EmptyRequest {}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct AckRequest {
    pub delivery_sequence: u64,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenCatalogRequest {
    pub reference: ModelCatalogReadRef,
    pub origin: ProductReadOrigin,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenStatusRequest {
    pub reference: ProductSourceStatusRef,
    pub origin: ProductReadOrigin,
}
#[derive(serde::Serialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct OpenReadReply {
    pub scope_id: String,
    pub identity: ProductReadScopeIdentity,
    pub target: Option<DelegationModelReadTarget>,
}
impl OpenReadReply {
    /// Native queries budget their own DTOs. This HTTP-only opening envelope also carries the
    /// original target, whose ID text must not be truncated or silently exceed the same limit.
    pub(super) fn ensure_budget(&self) -> Result<(), pl_protocol::studio::StudioError> {
        use pl_protocol::studio::{StudioError, StudioErrorCode};
        let mut counter = OpenReplyBytes {
            bytes: 0,
            exhausted: false,
        };
        serde_json::to_writer(&mut counter, self).map_err(|_| {
            if counter.exhausted {
                StudioError::new(
                    StudioErrorCode::Overloaded,
                    "Models HTTP open reply exceeds its final JSON byte budget",
                    false,
                )
            } else {
                StudioError::new(
                    StudioErrorCode::Protocol,
                    "Models HTTP open reply cannot be serialized",
                    false,
                )
            }
        })
    }
}
struct OpenReplyBytes {
    bytes: usize,
    exhausted: bool,
}
impl std::io::Write for OpenReplyBytes {
    fn write(&mut self, bytes: &[u8]) -> std::io::Result<usize> {
        match self
            .bytes
            .checked_add(bytes.len())
            .filter(|value| *value <= 256 * 1024)
        {
            Some(total) => {
                self.bytes = total;
                Ok(bytes.len())
            }
            None => {
                self.exhausted = true;
                Err(std::io::Error::other("Models open JSON budget exceeded"))
            }
        }
    }
    fn flush(&mut self) -> std::io::Result<()> {
        Ok(())
    }
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct TextRequest {
    pub field_id: u64,
    pub offset: u64,
    pub max_bytes: Option<u32>,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ListRequest {
    pub list_id: u64,
    pub offset: u64,
    pub limit: Option<u32>,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntriesRequest {
    pub offset: u64,
    pub limit: Option<u32>,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EntityRequest {
    pub reference: ProductEntityRef,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct LookupRequest {
    pub account_id: String,
}
#[derive(serde::Deserialize, utoipa::ToSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct EffortRequest {
    pub account_id: String,
    pub model_id: String,
    pub candidate: Option<String>,
}
