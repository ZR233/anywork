//! Profile-specific argument declarations; Studio owns catalog selection and generation.
use super::thread::{
    AgentSpawn, AgentSpawnProfile, AgentSpawnSchemaError, AgentWorkspaceMode, DelegationMode,
    NewThreadModelRoute, ToolDefinition,
};
use schemars::{JsonSchema, Schema, SchemaGenerator};
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet};

pub(super) fn declaration(
    profiles: &[AgentSpawnProfile],
    mode: DelegationMode,
) -> Result<Option<ToolDefinition>, AgentSpawnSchemaError> {
    if profiles.is_empty() {
        return Ok(None);
    }
    // Inline the typed request's definitions so each cloned branch remains self-contained.
    // Common fields keep exactly the parser's serde/schemars contract.
    let template = schemars::generate::SchemaSettings::default()
        .with(|settings| settings.inline_subschemas = true)
        .into_generator()
        .into_root_schema_for::<AgentSpawn>();
    let mut modes = BTreeMap::new();
    let mut branches = Vec::with_capacity(profiles.len());
    for profile in profiles {
        if modes
            .insert(&profile.profile_id, profile.workspace_mode.label())
            .is_some()
        {
            return Err(AgentSpawnSchemaError::DuplicateProfile(
                profile.profile_id.clone(),
            ));
        }
        branches.push(branch(&template, profile, mode)?);
    }
    let input_schema = top_level_schema(&template, branches)?;
    let routing = match mode {
        DelegationMode::Automatic => {
            "当前 Native 分发模式为 automatic（自动）。Profile 仅决定角色和工作区；modelSelection 必须指定当前具备派发资格的 Native 账号和模型，不能将 Profile 路由当作自动选模结果。"
        }
        DelegationMode::Profile => {
            "当前 Native 分发模式为 profile（固定）。使用 Profile 配置的路由，禁止传入 modelSelection。"
        }
    };
    let mut description = format!(
        "使用获授权的 Profile 创建具有独立上下文的子智能体。必填 taskSummary 为子会话列表显示的简短任务说明，折叠空白后须为 1–80 个 Unicode 字符；message 提供任务目标、关键约束，以及完整上下文或可访问交接文件的明确引用、用途与版本，二者共同构成完整指令，应用层不限制长度。顶层属性列出可用参数，请按 profileId 选择对应的 oneOf 分支。{routing} ACP 始终使用其配置的账号，禁止 modelSelection、writablePaths 和结构化审查。所选 Native 模型若声明 effort 候选，必须通过 modelSelection.effort 显式选择其中之一；只有模型不支持 effort 时才可省略或传 null。省略不会继承主代理或 Profile 的强度，也不会选择模型默认值。writablePaths 仅对 Native directory Profile 可选：省略表示整个工作区可写，[] 表示业务目录只读，但本 Thread 的 scratch/artifacts 仍可写。reviewTargetAgentId 仅对 Native review Profile 必填，必须为被审查的直接子智能体 agentId，宿主采用该成员的冻结工作区。宿主独立校验权限、当前可用性与限制。容量统计包含主代理以及树中所有未关闭和准备中的子智能体；因容量不足被拒绝时，先用 close_agent 关闭已完成成员，再创建新成员。Profile 工作区模式：{}。",
        serde_json::to_string(&modes)?
    );
    description.push_str(" ACP 可选传入有序 acpConfig 条目 {id,value}，使用服务声明的字符串值 ID 或布尔值，在首条消息前应用并确认。省略时使用新会话默认值，不继承父代理选择的模型。Native 不接受 ACP 配置。配置失败时，已创建的成员会保留且 messageAccepted=false；应检查或关闭该成员，不能假定没有创建子智能体。");
    Ok(Some(
        ToolDefinition::json("spawn_agent", description, input_schema)
            .expect("valid tool definition"),
    ))
}

/// Close the object once, at the envelope. Each branch still rejects every known
/// field it does not own, without rejecting fields a client adds to its envelope.
/// The unmodified declaration admits exactly the original closed branches.
fn top_level_schema(
    template: &Schema,
    mut branches: Vec<Schema>,
) -> Result<Value, AgentSpawnSchemaError> {
    let profile_template = template
        .as_object()
        .and_then(|object| object.get("properties"))
        .and_then(Value::as_object)
        .and_then(|properties| properties.get("profileId"))
        .and_then(Value::as_object)
        .ok_or(AgentSpawnSchemaError::Shape(
            "profileId template must be a string schema",
        ))?;
    if profile_template.get("type").and_then(Value::as_str) != Some("string")
        || profile_template.contains_key("const")
        || profile_template.contains_key("enum")
    {
        return Err(AgentSpawnSchemaError::Shape(
            "profileId template must be an unrestricted typed string schema",
        ));
    }
    let mut properties = BTreeMap::<String, Value>::new();
    let mut profile_ids = BTreeSet::new();
    let mut common_required: Option<BTreeSet<String>> = None;
    for branch in &branches {
        let object = branch.as_object().ok_or(AgentSpawnSchemaError::Shape(
            "spawn branch must be an object schema",
        ))?;
        if object.get("type").and_then(Value::as_str) != Some("object")
            || object.get("additionalProperties").and_then(Value::as_bool) != Some(false)
            || object.contains_key("patternProperties")
        {
            return Err(AgentSpawnSchemaError::Shape(
                "spawn branch must close explicitly named properties",
            ));
        }
        let fields = object.get("properties").and_then(Value::as_object).ok_or(
            AgentSpawnSchemaError::Shape("spawn branch properties are missing"),
        )?;
        for (name, field) in fields {
            if name == "profileId" {
                let mut identity =
                    field
                        .as_object()
                        .cloned()
                        .ok_or(AgentSpawnSchemaError::Shape(
                            "branch profileId must be a string schema",
                        ))?;
                let Some(Value::String(id)) = identity.remove("const") else {
                    return Err(AgentSpawnSchemaError::Shape(
                        "branch profileId constant is missing",
                    ));
                };
                if identity != *profile_template || !profile_ids.insert(id) {
                    return Err(AgentSpawnSchemaError::Shape(
                        "branch profileId constants must be distinct and share the typed schema",
                    ));
                }
            } else {
                if !field.is_object() && !field.is_boolean() {
                    return Err(AgentSpawnSchemaError::Shape(
                        "branch properties must contain schemas",
                    ));
                }
                match properties.get(name) {
                    Some(existing) if existing != field => {
                        return Err(AgentSpawnSchemaError::Shape(
                            "same-named branch fields must have identical schemas",
                        ));
                    }
                    Some(_) => {}
                    None => {
                        properties.insert(name.clone(), field.clone());
                    }
                }
            }
        }
        let mut required = BTreeSet::new();
        for field in
            object
                .get("required")
                .and_then(Value::as_array)
                .ok_or(AgentSpawnSchemaError::Shape(
                    "branch required fields are missing",
                ))?
        {
            let name = field.as_str().ok_or(AgentSpawnSchemaError::Shape(
                "branch required fields must be strings",
            ))?;
            if !fields.contains_key(name) || !required.insert(name.to_owned()) {
                return Err(AgentSpawnSchemaError::Shape(
                    "branch required fields must name distinct properties",
                ));
            }
        }
        if !required.contains("profileId") {
            return Err(AgentSpawnSchemaError::Shape(
                "branch profileId must be required",
            ));
        }
        match common_required.as_mut() {
            Some(common) => common.retain(|name| required.contains(name)),
            None => common_required = Some(required),
        }
    }
    let required = common_required.ok_or(AgentSpawnSchemaError::Shape(
        "spawn declaration must contain branches",
    ))?;
    let mut identity = profile_template.clone();
    identity.insert(
        "enum".into(),
        Value::Array(profile_ids.into_iter().map(Value::String).collect()),
    );
    properties.insert("profileId".into(), Value::Object(identity));
    for branch in &mut branches {
        let object = branch.as_object_mut().ok_or(AgentSpawnSchemaError::Shape(
            "spawn branch must be an object schema",
        ))?;
        object.remove("additionalProperties");
        let fields = object
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .ok_or(AgentSpawnSchemaError::Shape(
                "spawn branch properties are missing",
            ))?;
        // The envelope already rejects names outside this union. A false property
        // schema rejects the remaining names excluded by the original branch,
        // including explicit nulls. Do not alter any nested object closure.
        for name in properties.keys() {
            fields.entry(name.clone()).or_insert(Value::Bool(false));
        }
    }
    Ok(schemars::json_schema!({
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": false,
        "oneOf": branches,
    })
    .to_value())
}

fn branch(
    template: &Schema,
    profile: &AgentSpawnProfile,
    mode: DelegationMode,
) -> Result<Schema, AgentSpawnSchemaError> {
    let mut schema = template.clone();
    let object = schema
        .as_object_mut()
        .ok_or(AgentSpawnSchemaError::Shape("request must be an object"))?;
    object.remove("$schema");
    object.remove("title");
    let properties = object
        .get_mut("properties")
        .and_then(Value::as_object_mut)
        .ok_or(AgentSpawnSchemaError::Shape(
            "request properties are missing",
        ))?;
    let identity = properties
        .get_mut("profileId")
        .and_then(Value::as_object_mut)
        .ok_or(AgentSpawnSchemaError::Shape(
            "profileId must be a string schema",
        ))?;
    identity.insert("const".into(), Value::String(profile.profile_id.clone()));
    let native = profile.backend == pl_protocol::AgentBackendKind::Native;
    if native {
        properties.remove("acpConfig");
    }
    if !native || profile.workspace_mode != AgentWorkspaceMode::Directory {
        properties.remove("writablePaths");
    }
    if native && profile.workspace_mode == AgentWorkspaceMode::Review {
        properties.insert(
            "reviewFeedback".into(),
            super::thread::ReviewFeedback::json_schema(&mut SchemaGenerator::default()).to_value(),
        );
        // Option<String> is appropriate for parsing all modes, but a review branch requires a
        // non-null target. The host still checks that the target is an authorized direct child.
        properties.insert(
            "reviewTargetAgentId".into(),
            String::json_schema(&mut SchemaGenerator::default()).to_value(),
        );
        object
            .get_mut("required")
            .and_then(Value::as_array_mut)
            .ok_or(AgentSpawnSchemaError::Shape("required fields are missing"))?
            .push(Value::String("reviewTargetAgentId".into()));
    } else {
        properties.remove("reviewTargetAgentId");
        properties.remove("reviewFeedback");
    }
    if native && mode == DelegationMode::Automatic {
        let mut generator = schemars::generate::SchemaSettings::default()
            .with(|settings| settings.inline_subschemas = true)
            .into_generator();
        object
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .ok_or(AgentSpawnSchemaError::Shape(
                "request properties are missing",
            ))?
            .insert(
                "modelSelection".into(),
                NewThreadModelRoute::json_schema(&mut generator).to_value(),
            );
        object
            .get_mut("required")
            .and_then(Value::as_array_mut)
            .ok_or(AgentSpawnSchemaError::Shape("required fields are missing"))?
            .push(Value::String("modelSelection".into()));
    } else {
        object
            .get_mut("properties")
            .and_then(Value::as_object_mut)
            .ok_or(AgentSpawnSchemaError::Shape(
                "request properties are missing",
            ))?
            .remove("modelSelection");
    }
    object.insert("additionalProperties".into(), Value::Bool(false));
    Ok(schema)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mixed_spawn_branches_share_one_closed_envelope_without_relaxing_fields() {
        for mode in [DelegationMode::Automatic, DelegationMode::Profile] {
            let definition = declaration(
                &[
                    AgentSpawnProfile {
                        profile_id: "native".into(),
                        backend: pl_protocol::AgentBackendKind::Native,
                        workspace_mode: AgentWorkspaceMode::Directory,
                    },
                    AgentSpawnProfile {
                        profile_id: "acp".into(),
                        backend: pl_protocol::AgentBackendKind::Acp,
                        workspace_mode: AgentWorkspaceMode::Directory,
                    },
                    AgentSpawnProfile {
                        profile_id: "review".into(),
                        backend: pl_protocol::AgentBackendKind::Native,
                        workspace_mode: AgentWorkspaceMode::Review,
                    },
                    AgentSpawnProfile {
                        profile_id: "worktree".into(),
                        backend: pl_protocol::AgentBackendKind::Native,
                        workspace_mode: AgentWorkspaceMode::Worktree,
                    },
                    AgentSpawnProfile {
                        profile_id: "unrestricted".into(),
                        backend: pl_protocol::AgentBackendKind::Native,
                        workspace_mode: AgentWorkspaceMode::Unrestricted,
                    },
                ],
                mode,
            )
            .unwrap()
            .unwrap();
            let pl_agent_tool::InputFormat::JsonSchema(schema) = definition.input() else {
                panic!("spawn must declare JSON input");
            };
            let branches = schema["oneOf"].as_array().unwrap();
            let envelope = schema["properties"].as_object().unwrap();
            assert_eq!(schema["additionalProperties"], false);
            assert!(!envelope.contains_key("toolSummary"));
            assert!(!envelope.contains_key("metadata"));
            for branch in branches {
                assert!(branch.get("additionalProperties").is_none());
                let fields = branch["properties"].as_object().unwrap();
                assert_eq!(
                    fields.keys().collect::<BTreeSet<_>>(),
                    envelope.keys().collect::<BTreeSet<_>>()
                );
                let id = fields["profileId"]["const"].as_str().unwrap();
                for field in ["reviewTargetAgentId", "reviewFeedback"] {
                    assert_eq!(fields[field] == false, id != "review");
                }
                assert_eq!(fields["writablePaths"] == false, id != "native");
            }
            let native = branches
                .iter()
                .find(|branch| branch["properties"]["profileId"]["const"] == "native")
                .unwrap();
            let acp = branches
                .iter()
                .find(|branch| branch["properties"]["profileId"]["const"] == "acp")
                .unwrap();
            for field in [
                "modelSelection",
                "writablePaths",
                "reviewTargetAgentId",
                "reviewFeedback",
            ] {
                if envelope.contains_key(field) {
                    assert_eq!(acp["properties"][field], false, "{field} must be rejected");
                } else {
                    assert!(acp["properties"].get(field).is_none());
                }
            }
            assert!(native["properties"].get("writablePaths").is_some());
            assert_eq!(
                native["properties"].get("modelSelection").is_some(),
                mode == DelegationMode::Automatic
            );
            let required = native["required"].as_array().unwrap();
            assert_eq!(
                required.iter().any(|field| field == "modelSelection"),
                mode == DelegationMode::Automatic
            );
        }
    }
}
