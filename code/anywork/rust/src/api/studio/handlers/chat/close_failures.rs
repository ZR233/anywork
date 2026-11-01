//! Preserve each original cleanup diagnostic, including simultaneous independent failures.
use std::collections::BTreeMap;

use crate::api::studio::types::BridgeError;

#[flutter_rust_bridge::frb(ignore)]
#[derive(Default)]
pub(super) struct CloseFailures {
    first: Option<BridgeError>,
    resources: BTreeMap<String, BridgeError>,
}

impl CloseFailures {
    pub(super) fn record(&mut self, resource: &str, error: BridgeError) {
        // A sealed facade has at most 32 watch owners plus its fixed feed/read/task responsibilities.
        // Repeated retries of a resource keep its first error instead of growing an error log.
        self.first.get_or_insert_with(|| error.clone());
        self.resources.entry(resource.to_owned()).or_insert(error);
    }

    pub(super) fn outcome(&self) -> Option<BridgeError> {
        let mut first = self.first.clone()?;
        if self.resources.len() > 1 {
            first.details_json = Some(
                serde_json::json!({
                    "closeFailures": self.resources.iter().map(|(resource, error)| {
                        serde_json::json!({"resource": resource, "error": error})
                    }).collect::<Vec<_>>(),
                })
                .to_string(),
            );
        }
        Some(first)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::api::studio::handlers::chat::owner::error;
    use pl_protocol::studio::StudioErrorCode;

    #[test]
    fn independent_failures_keep_both_original_correlations_and_details_across_retries() {
        let mut failures = CloseFailures::default();
        let mut feed = error(StudioErrorCode::Storage, "native feed failure");
        feed.details_json = Some(r#"{"native":"feed"}"#.into());
        let mut read = error(StudioErrorCode::Unavailable, "native read failure");
        read.details_json = Some(r#"{"native":"read"}"#.into());
        failures.record("feed", feed.clone());
        failures.record("read", read.clone());
        failures.record(
            "feed",
            error(StudioErrorCode::Internal, "later retry failure"),
        );
        let combined = failures.outcome().unwrap();
        assert_eq!(combined.correlation_id, feed.correlation_id);
        assert_eq!(combined.code, feed.code);
        let details: serde_json::Value =
            serde_json::from_str(combined.details_json.as_ref().unwrap()).unwrap();
        let causes = details["closeFailures"].as_array().unwrap();
        assert_eq!(causes.len(), 2);
        assert_eq!(causes[0]["error"], serde_json::to_value(feed).unwrap());
        assert_eq!(causes[1]["error"], serde_json::to_value(read).unwrap());
        assert_eq!(failures.outcome().unwrap(), combined);
    }
}
