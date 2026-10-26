//! ACP 的只读投影：官方模板目录与 Settings 中的接入视图。
//!
//! 这里**不创建、也不退役**接入记录：唯一的创建/退役路径是 Settings 提交观察者驱动的
//! [`super::registry::AcpAuthInner::observe_committed`]。Settings 投影必须与同一 Settings revision
//! 的已观察事实完全匹配；缺失、退役或身份不符一律是陈旧快照，返回类型化 `StaleRevision` 由调用
//! 方在 Settings command 边界内重读，而不是由投影补造或借用另一个身份的 revision。

use anyhow::Result;
use pl_protocol::studio::{
    AcpAccountCatalog, AcpAccountSettings, AcpAccountTemplate, AcpProvider as AcpProviderWire,
    StudioError, StudioErrorCode,
};

use super::admission::AcpAuthRuntime;
use super::registry::AcpAuthInner;
use super::registry::ConnectionIdentity;
use crate::config::{AcpProvider, StudioConfig};

/// 本阶段的接入模板；只读默认值，不启动程序。
///
/// `supported_version` 与内部启动资格消费同一份产品固定清单（当前 1.4.1），因此客户端不需要、
/// 也不允许硬编码第二份版本选择表；模板里既没有默认 argv，也没有本地程序路径。这里不做普通 CLI
/// 检测、不自动安装，也不提供平台或版本回退（design/28 §28.5）。
pub(crate) fn acp_account_catalog() -> AcpAccountCatalog {
    AcpAccountCatalog {
        templates: vec![AcpAccountTemplate {
            provider: AcpProviderWire::Antigravity,
            display_name: "Antigravity".to_string(),
            description: "通过官方 ACP server 连接 Antigravity，并使用其自身登录凭据。".to_string(),
            icon_key: "antigravity".to_string(),
            supported_version: super::super::acp_install::SERVER_VERSION.to_string(),
            install_url: "https://antigravity.google/docs/ide/extensions".to_string(),
            terms_url: "https://antigravity.google/terms".to_string(),
            automatic_install: super::super::acp_install::automatic_install_availability(),
        }],
    }
}

impl AcpAuthRuntime {
    /// canonical Settings 中的 ACP 接入投影。
    ///
    /// 只能在 [`crate::config::ConfigRuntime`] 的 Settings command 边界内调用：`settings_revision`
    /// 必须等于 owner 已观察的水位，且每条接入都有同身份、未退役的记录，否则返回类型化
    /// `StaleRevision`（调用方重读设置，而不是重试轮询或补造条目）。
    pub(crate) fn settings_view(
        &self,
        settings_revision: u64,
        config: &StudioConfig,
    ) -> Result<Vec<AcpAccountSettings>> {
        Ok(self.inner.settings_directory(settings_revision, config)?)
    }
}

impl AcpAuthInner {
    /// 与已提交 Settings revision 严格相符的不可变目录投影。
    ///
    /// Settings 提交观察边界专用：身份同步与目录捕获在同一 registry 锁序列内完成，因此返回
    /// 的行只描述该 revision 的连接代次；任何缺失、退役或身份不符都是陈旧快照，返回类型化
    /// `StaleRevision`，绝不由投影补造条目或借用其它 revision 的代次。
    pub(super) fn settings_directory(
        &self,
        settings_revision: u64,
        config: &StudioConfig,
    ) -> std::result::Result<Vec<AcpAccountSettings>, StudioError> {
        let registry = self.lock();
        if registry.settings_revision != settings_revision {
            return Err(stale_settings_studio_error());
        }
        let mut accounts = Vec::with_capacity(config.acp.accounts.len());
        for (account_id, account) in &config.acp.accounts {
            let Some(slot) = registry.slots.get(account_id) else {
                return Err(stale_settings_studio_error());
            };
            if slot.retired || slot.identity != ConnectionIdentity::of(account) {
                return Err(stale_settings_studio_error());
            }
            accounts.push(AcpAccountSettings {
                account_id: account_id.clone(),
                name: account.name.clone(),
                provider: provider_dto(account.provider),
                connection_revision: slot.revision,
            });
        }
        Ok(accounts)
    }
}

fn stale_settings_studio_error() -> StudioError {
    StudioError::new(
        StudioErrorCode::StaleRevision,
        "ACP 设置投影已过期，请重新读取设置",
        true,
    )
}

fn provider_dto(provider: AcpProvider) -> AcpProviderWire {
    match provider {
        AcpProvider::Antigravity => AcpProviderWire::Antigravity,
    }
}
