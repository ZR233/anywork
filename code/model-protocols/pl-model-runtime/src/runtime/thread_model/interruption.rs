//! Reliable evidence that a model request was interrupted and will be retried.
use std::sync::Arc;

use pl_core::{
    context::OpaquePayload,
    model::{ModelCompletedMember, ModelError, ModelFailureKind, ModelParts},
};
use serde::{Deserialize, Serialize};

const FORMAT: &str = "pl.model.interruption";
const VERSION: u32 = 1;
pub(crate) const MEMBER_ID: &str = "interruption";

/// The first confirmed request interruption in one invocation, before its next generation.
///
/// This records a model request retry decision, without inferring physical network state.
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInterruptionReceipt {
    pub generation: u32,
    pub max_retries: u32,
    pub parts: ModelParts,
    pub message: Arc<str>,
}

impl ModelInterruptionReceipt {
    pub(crate) fn encode(&self) -> Result<OpaquePayload, serde_json::Error> {
        Ok(
            OpaquePayload::new(FORMAT, VERSION, serde_json::to_string(self)?)
                .expect("static interruption format"),
        )
    }
}

/// Decodes interruption evidence; ordinary completed members return `None`.
///
/// # Errors
/// Rejects unsupported versions, malformed contents and conflicting generation or member identity.
pub fn model_interruption_receipt(
    member: &ModelCompletedMember,
) -> Result<Option<ModelInterruptionReceipt>, ModelError> {
    if member.payload.format() != FORMAT {
        return Ok(None);
    }
    if member.payload.version() != VERSION {
        return Err(super::failure(
            ModelFailureKind::UnsupportedContent,
            std::io::Error::other("unsupported model interruption receipt version"),
        ));
    }
    let receipt: ModelInterruptionReceipt = serde_json::from_str(member.payload.content())
        .map_err(|source| super::failure(ModelFailureKind::InvalidResponse, source))?;
    if member.member_id != MEMBER_ID
        || member.generation != receipt.generation
        || receipt.max_retries == 0
        || receipt.max_retries > 32
        || receipt.generation >= receipt.max_retries
        || receipt.message.is_empty()
    {
        return Err(super::failure(
            ModelFailureKind::InvalidResponse,
            std::io::Error::other(
                "model interruption receipt differs from its admitted identity or retry policy",
            ),
        ));
    }
    Ok(Some(receipt))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_version_generation_and_identity_without_consuming_ordinary_members() {
        // Independent wire fixture: the decoder must retain the actual request failure message.
        let content =
            r#"{"generation":1,"maxRetries":5,"parts":[],"message":"request rejected with 503"}"#;
        let member = ModelCompletedMember {
            turn_id: "turn".into(),
            attempt_id: "attempt".into(),
            generation: 1,
            member_id: MEMBER_ID.into(),
            payload: OpaquePayload::new(FORMAT, 1, content).unwrap(),
        };
        let receipt = model_interruption_receipt(&member).unwrap().unwrap();
        assert_eq!(receipt.generation, 1);
        assert_eq!(receipt.max_retries, 5);
        assert_eq!(&*receipt.message, "request rejected with 503");
        assert!(receipt.parts.is_empty());
        for invalid in [
            ModelCompletedMember {
                generation: 0,
                ..member.clone()
            },
            ModelCompletedMember {
                member_id: "provider-item".into(),
                ..member.clone()
            },
            ModelCompletedMember {
                payload: OpaquePayload::new(FORMAT, 2, content).unwrap(),
                ..member.clone()
            },
            ModelCompletedMember {
                payload: OpaquePayload::new(FORMAT, 1, "{}").unwrap(),
                ..member.clone()
            },
            ModelCompletedMember {
                payload: OpaquePayload::new(
                    FORMAT,
                    1,
                    r#"{"generation":1,"maxRetries":1,"parts":[],"message":"exhausted"}"#,
                )
                .unwrap(),
                ..member.clone()
            },
        ] {
            assert!(
                model_interruption_receipt(&invalid).is_err(),
                "invalid envelope: {invalid:?}"
            );
        }
        let ordinary = ModelCompletedMember {
            payload: OpaquePayload::text("ordinary"),
            ..member
        };
        assert!(model_interruption_receipt(&ordinary).unwrap().is_none());
    }
}
