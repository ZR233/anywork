use super::*;
use json::{opt_meta, opt_protocol_meta};

pub(super) fn config(v: s::SessionConfigOption) -> R<BridgeAcpConfigOption> {
    Ok(BridgeAcpConfigOption {
        id: BridgeAcpConfigId {
            value: v.id.to_string(),
        },
        name: v.name,
        description: v.description,
        category: v
            .category
            .map(|v| {
                Ok(match v {
                    s::SessionConfigOptionCategory::Mode => BridgeAcpConfigCategory::Mode,
                    s::SessionConfigOptionCategory::Model => BridgeAcpConfigCategory::Model,
                    s::SessionConfigOptionCategory::ModelConfig => {
                        BridgeAcpConfigCategory::ModelConfig
                    }
                    s::SessionConfigOptionCategory::ThoughtLevel => {
                        BridgeAcpConfigCategory::ThoughtLevel
                    }
                    s::SessionConfigOptionCategory::Other(value) => {
                        BridgeAcpConfigCategory::Other { value }
                    }
                    _ => return Err(unsupported("SessionConfigOptionCategory")),
                })
            })
            .transpose()?,
        kind: match v.kind {
            s::SessionConfigKind::Select(v) => BridgeAcpConfigKind::Select {
                current_value: BridgeAcpConfigValueId {
                    value: v.current_value.to_string(),
                },
                options: match v.options {
                    s::SessionConfigSelectOptions::Ungrouped(v) => {
                        BridgeAcpSelectOptions::Ungrouped {
                            options: many(v, select_option)?,
                        }
                    }
                    s::SessionConfigSelectOptions::Grouped(v) => BridgeAcpSelectOptions::Grouped {
                        groups: many(v, |v| {
                            Ok(BridgeAcpSelectGroup {
                                group: v.group.to_string(),
                                name: v.name,
                                options: many(v.options, select_option)?,
                                meta: opt_meta(v.meta)?,
                            })
                        })?,
                    },
                    _ => return Err(unsupported("SessionConfigSelectOptions")),
                },
            },
            s::SessionConfigKind::Boolean(v) => BridgeAcpConfigKind::Boolean {
                current_value: v.current_value,
            },
            _ => return Err(unsupported("SessionConfigKind")),
        },
        meta: opt_meta(v.meta)?,
    })
}
fn select_option(v: s::SessionConfigSelectOption) -> R<BridgeAcpSelectOption> {
    Ok(BridgeAcpSelectOption {
        value: BridgeAcpConfigValueId {
            value: v.value.to_string(),
        },
        name: v.name,
        description: v.description,
        meta: opt_meta(v.meta)?,
    })
}
pub(crate) fn protocol_config_value(v: BridgeAcpConfigValue) -> s::SessionConfigOptionValue {
    match v {
        BridgeAcpConfigValue::Boolean { value } => s::SessionConfigOptionValue::Boolean { value },
        BridgeAcpConfigValue::ValueId { value } => {
            s::SessionConfigOptionValue::value_id(value.value)
        }
    }
}
pub(super) fn modes(v: s::SessionModeState) -> R<BridgeAcpModeState> {
    Ok(BridgeAcpModeState {
        current_mode_id: BridgeAcpModeId {
            value: v.current_mode_id.to_string(),
        },
        available_modes: many(v.available_modes, |v| {
            Ok(BridgeAcpMode {
                id: BridgeAcpModeId {
                    value: v.id.to_string(),
                },
                name: v.name,
                description: v.description,
                meta: opt_meta(v.meta)?,
            })
        })?,
        meta: opt_meta(v.meta)?,
    })
}
pub(crate) fn protocol_list(
    v: BridgeAcpListRequest,
) -> R<(p::AcpSessionTarget, s::ListSessionsRequest)> {
    let mut request = s::ListSessionsRequest::new();
    request.cwd = v.cwd.map(Into::into);
    request.cursor = v.cursor;
    request.meta = opt_protocol_meta(v.meta)?;
    Ok((v.target.into(), request))
}
