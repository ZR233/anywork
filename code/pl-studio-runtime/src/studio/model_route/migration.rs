//! Historical account identity encodings. Ordinary route/Profile reads accept only version 2.
use super::*;

pub(crate) fn upgrade(state: &mut ThreadSnapshot) -> Result<()> {
    if let Some(record) = state.extensions.get_mut(MODEL_ROUTE_EXTENSION) {
        record.payload = upgrade_route(&record.payload)?;
    }
    if let Some(record) = state.extensions.get_mut(AGENT_PROFILE_EXTENSION) {
        record.payload = upgrade_profile(&record.payload)?;
    }
    Ok(())
}
fn upgrade_route(payload: &OpaquePayload) -> Result<OpaquePayload> {
    let converted = if payload.format() == MODEL_ROUTE_FORMAT && payload.version() == 1 {
        let mut value: serde_json::Value = serde_json::from_str(payload.content())?;
        let object = value
            .as_object_mut()
            .context("saved model route is not an object")?;
        crate::studio::payload_alias::rename_key(object, "provider", "account_id")?;
        crate::studio::payload_alias::rename_key(object, "model", "model_id")?;
        OpaquePayload::new(MODEL_ROUTE_FORMAT, 2, serde_json::to_string(&value)?)?
    } else {
        payload.clone()
    };
    decode(&converted)?;
    Ok(converted)
}
fn upgrade_profile(payload: &OpaquePayload) -> Result<OpaquePayload> {
    let converted = if payload.format() == AGENT_PROFILE_FORMAT && payload.version() == 1 {
        let mut value: serde_json::Value = serde_json::from_str(payload.content())?;
        let object = value
            .as_object_mut()
            .context("saved Agent Profile is not an object")?;
        crate::studio::payload_alias::rename_key(object, "providerId", "accountId")?;
        crate::studio::payload_alias::rename_key(object, "model", "modelId")?;
        OpaquePayload::new(AGENT_PROFILE_FORMAT, 2, serde_json::to_string(&value)?)?
    } else {
        payload.clone()
    };
    decode_profile_payload(&converted, AGENT_PROFILE_FORMAT, "Agent Profile")?;
    Ok(converted)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn payload(version: u32, body: serde_json::Value) -> OpaquePayload {
        OpaquePayload::new(MODEL_ROUTE_FORMAT, version, body.to_string()).unwrap()
    }

    #[test]
    fn v1_model_route_payload_converts_identity_without_touching_v2() {
        let legacy = payload(
            1,
            serde_json::json!({ "provider": "deepseek", "model": "deepseek-flash", "effort": "high" }),
        );
        assert!(
            decode(&legacy).is_err(),
            "ordinary reads reject legacy encodings"
        );
        let route =
            decode(&upgrade_route(&legacy).expect("v1 route converts")).expect("current route");
        assert_eq!(route.account_id.as_str(), "deepseek");
        assert_eq!(route.model_id, "deepseek-flash");
        assert_eq!(
            route.effort.as_ref().map(|value| value.as_str()),
            Some("high")
        );

        let current = payload(
            2,
            serde_json::json!({ "account_id": "second", "model_id": "m", "effort": null }),
        );
        let route = decode(&current).expect("v2 route decodes");
        assert_eq!(route.account_id.as_str(), "second");
        assert_eq!(route.model_id, "m");
    }

    #[test]
    fn conflicting_v1_and_v2_identity_keys_fail_without_guessing() {
        let conflicting = payload(
            1,
            serde_json::json!({ "provider": "a", "account_id": "b", "model": "m" }),
        );
        assert!(upgrade_route(&conflicting).is_err());
    }

    #[test]
    fn v1_frozen_profile_payload_converts_identity() {
        let legacy = OpaquePayload::new(
            AGENT_PROFILE_FORMAT,
            1,
            serde_json::json!({
                "profileId": "reviewer",
                "displayName": "Reviewer",
                "description": "",
                "whenToUse": "",
                "systemInstructions": "",
                "providerId": "deepseek",
                "model": "deepseek-flash",
                "effort": "high",
                "source": "config",
                "revision": "1",
                "contentHash": "",
                "system": true,
                "enabled": true,
                "workspaceMode": "unrestricted"
            })
            .to_string(),
        )
        .unwrap();
        let profile = decode_profile_payload(
            &upgrade_profile(&legacy).expect("v1 profile converts"),
            AGENT_PROFILE_FORMAT,
            "Agent Profile",
        )
        .expect("v1 profile decodes");
        assert_eq!(profile.account_id, "deepseek");
        assert_eq!(profile.model_id, "deepseek-flash");
        assert_eq!(profile.effort.as_deref(), Some("high"));
    }
}
