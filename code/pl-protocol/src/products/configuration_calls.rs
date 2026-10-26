//! Closed kind dispatch shared only by the original Configuration call owners. Public wire
//! endpoints keep their concrete request/result schemas, not this internal dispatch envelope.
use super::configuration_commands::{ConfigurationCommandOutcome, ConfigurationCommandRequest};
use super::profile_commands::{
    ConfigurationReloadOutcome, ConfigurationReloadRequest, ProfileCommandOutcome,
    ProfileCommandRequest,
};
use super::references::ConfigurationReadTarget;
use crate::studio::{StudioCommandReceipt, StudioError, UpdateAcpAccountRequest};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ConfigurationCallKind {
    Configuration,
    Profile,
    Reload,
    /// ACP 接入的保存/删除：复用配置领域的调用所有者与提交边界，但不是 HTTP 公开写请求。
    AcpAccount,
}
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigurationCallRequest {
    Configuration(ConfigurationCommandRequest),
    Profile(ProfileCommandRequest),
    Reload(ConfigurationReloadRequest),
    AcpAccount(AcpAccountCallRequest),
}
impl ConfigurationCallRequest {
    pub fn kind(&self) -> ConfigurationCallKind {
        match self {
            Self::Configuration(_) => ConfigurationCallKind::Configuration,
            Self::Profile(_) => ConfigurationCallKind::Profile,
            Self::Reload(_) => ConfigurationCallKind::Reload,
            Self::AcpAccount(_) => ConfigurationCallKind::AcpAccount,
        }
    }
    pub fn operation_id(&self) -> &str {
        match self {
            Self::Configuration(request) => request.operation_id(),
            Self::Profile(request) => request.operation_id(),
            Self::Reload(request) => &request.operation_id,
            Self::AcpAccount(request) => request.operation_id(),
        }
    }
    pub fn unknown(&self, error: StudioError) -> ConfigurationCallOutcome {
        let operation_id = self.operation_id().to_owned();
        match self {
            Self::Configuration(_) => {
                ConfigurationCallOutcome::Configuration(ConfigurationCommandOutcome::Unknown {
                    operation_id,
                    error,
                })
            }
            Self::Profile(_) => ConfigurationCallOutcome::Profile(ProfileCommandOutcome::Unknown {
                operation_id,
                error,
            }),
            Self::Reload(_) => {
                ConfigurationCallOutcome::Reload(ConfigurationReloadOutcome::Unknown {
                    operation_id,
                    error,
                })
            }
            Self::AcpAccount(_) => {
                ConfigurationCallOutcome::AcpAccount(AcpAccountCommandOutcome::Unknown {
                    operation_id,
                    error,
                })
            }
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub enum ConfigurationCallOutcome {
    Configuration(ConfigurationCommandOutcome),
    Profile(ProfileCommandOutcome),
    Reload(ConfigurationReloadOutcome),
    AcpAccount(AcpAccountCommandOutcome),
}

/// ACP 接入的两种提交意图；字段与严格校验沿用既有请求类型，不复制第二套形状。
#[derive(Debug, Clone, PartialEq)]
pub enum AcpAccountCallRequest {
    Save(UpdateAcpAccountRequest),
    Remove(crate::studio::RemoveAcpAccountRequest),
}
impl AcpAccountCallRequest {
    pub fn operation_id(&self) -> &str {
        match self {
            Self::Save(request) => &request.operation_id,
            Self::Remove(request) => &request.operation_id,
        }
    }
}

/// 提交成功只携带真实 Settings 回执与本次提交捕获的配置读取目标。
///
/// 不携带整份 ACP 目录、模型目录目标或模型资源回执：目录由原目标完整读取得到。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcpAccountCommandReply {
    pub receipt: StudioCommandReceipt,
    pub configuration: ConfigurationReadTarget,
}

/// ACP 接入提交的四个诚实阶段，与普通配置命令同形但更窄。
#[derive(Debug, Clone, PartialEq)]
pub enum AcpAccountCommandOutcome {
    Committed {
        reply: AcpAccountCommandReply,
    },
    CommittedButUnobserved {
        receipt: StudioCommandReceipt,
        error: StudioError,
    },
    Rejected {
        operation_id: String,
        error: StudioError,
    },
    Unknown {
        operation_id: String,
        error: StudioError,
    },
}
