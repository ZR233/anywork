//! Dynamic spawn declaration and execution share the frozen root dispatch mode.
use super::{StudioThreadAssembler, ThreadAssemblyError};

impl StudioThreadAssembler {
    pub(super) fn spawn_declaration(
        &self,
        selection: pl_protocol::DelegationSettings,
    ) -> Result<pl_protocol::ToolSpec, ThreadAssemblyError> {
        let schema = schemars::schema_for!(pl_tool::collaboration::thread::AgentSpawn).to_value();
        let services = self.0.state().agent_services.clone();
        let mut branches = Vec::new();
        if let Some(services) = services {
            let snapshot = services.config.read()?;
            let catalog = services.config.agent_profiles()?;
            for profile in catalog.profiles {
                if selection.mode == pl_protocol::DelegationMode::Profile
                    && crate::studio::delegation::resolve_child_route(&snapshot.config, &profile)
                        .is_err()
                {
                    continue;
                }
                let mut branch = schema.clone();
                branch
                    .as_object_mut()
                    .expect("JsonSchema object")
                    .remove("$defs");
                let properties = branch["properties"]
                    .as_object_mut()
                    .expect("AgentSpawn has properties");
                properties.insert(
                    "profileId".into(),
                    serde_json::json!({"type":"string","const":profile.profile_id}),
                );
                if profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Directory {
                    properties.remove("writablePaths");
                }
                if profile.workspace_mode != pl_protocol::AgentWorkspaceMode::Review {
                    properties.remove("reviewTargetAgentId");
                }
                if selection.mode == pl_protocol::DelegationMode::Profile {
                    properties.remove("modelSelection");
                }
                let required = branch["required"]
                    .as_array_mut()
                    .expect("AgentSpawn has required fields");
                if selection.mode == pl_protocol::DelegationMode::Automatic {
                    required.push("modelSelection".into());
                    // A present null is not an automatic model selection.
                    branch["properties"]["modelSelection"] =
                        serde_json::json!({"$ref":"#/$defs/NewThreadModelRoute"});
                }
                if profile.workspace_mode == pl_protocol::AgentWorkspaceMode::Review {
                    branch["required"]
                        .as_array_mut()
                        .expect("required fields")
                        .push("reviewTargetAgentId".into());
                    branch["properties"]["reviewTargetAgentId"] =
                        serde_json::json!({"type":"string","minLength":1});
                }
                branches.push(branch);
            }
        }
        let dynamic = if branches.is_empty() {
            serde_json::json!({"type":"object","not":{}})
        } else {
            serde_json::json!({"type":"object","oneOf":branches,"$defs":schema.get("$defs").cloned().unwrap_or_else(|| serde_json::json!({}))})
        };
        Ok(pl_protocol::ToolSpec::function(
            "spawn_agent",
            "Create a direct child using an enabled role Profile. taskSummary is 1–80 Unicode characters; message contains complete self-contained instructions. Automatic mode requires modelSelection from a current model query; fixed Profile mode forbids overrides. Workspace parameters follow the selected role; metadata grants no routing or permissions.",
            dynamic,
        ))
    }
}
