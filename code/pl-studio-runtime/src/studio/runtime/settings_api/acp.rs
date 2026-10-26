//! ACP 接入的 Settings 命令与认证命令入口。
//!
//! 保存/删除接入属于 Settings 写路径：沿用 ConfigRuntime 的 revision CAS 与原子提交，成功即
//! 返回 canonical 设置，绝不等待进程或登录。检查连接、登录与取消是独立的认证操作命令，返回
//! 受理身份后由 owner 在后台推进（见 design/20 §20.2、design/28 §28.2）。

use anyhow::Result;
use pl_protocol::studio::{
    AcpAccountCatalog, AcpAuthCommandReply, AcpAuthSnapshot, CancelAcpAuthRequest,
    CommandEffectPoint, RemoveAcpAccountRequest, SettingsCommandReply, StartAcpAuthRequest,
    UpdateAcpAccountRequest,
};

use crate::config::AcpProvider as ConfigAcpProvider;
use crate::config::acp::{
    AcpAccountConfig, normalize_acp_account, validate_acp_account_id, validate_acp_name,
};

use super::SettingsCommit;
use super::StudioRuntime;
use super::account_edit::invalid_settings_argument;
use super::commands::Followup;

impl StudioRuntime {
    /// 读取 ACP 接入模板目录；纯读取默认值，不启动程序、不检查凭据。
    pub fn load_acp_account_catalog(&self) -> AcpAccountCatalog {
        super::super::acp_auth::acp_account_catalog()
    }

    /// 保存（新增或更新）一条 ACP 接入。
    ///
    /// 只写这份接入资源；默认账号、模式/角色路由与 Native 账号都不被重放。这里既不验证也不等待
    /// 受管安装：保存成功不是安装就绪或认证通过的证明，检查时会在 `prepare` 阶段给出类型化失败。
    /// 接入不携带 program/argv，因此保存路径没有恢复自定义执行入口的可能。
    ///
    /// `commit_save_acp_account` 是同一次提交的原始证据出口：受管调用只保留本次捕获的配置读取
    /// 目标，不再返回整份 Settings。
    pub(in crate::studio::runtime) fn commit_save_acp_account(
        &self,
        request: UpdateAcpAccountRequest,
    ) -> Result<SettingsCommit> {
        Self::validate_operation_id(&request.operation_id)?;
        let (account_id, account) = validated_acp_account(&request.account)?;
        let mut changed = false;
        let state = self
            .config_runtime
            .update_evidence(request.expected_revision, |config| {
                let mut next = config.clone();
                changed = next.acp.accounts.get(&account_id) != Some(&account);
                next.acp
                    .accounts
                    .insert(account_id.clone(), account.clone());
                next.validate_declarations()?;
                Ok(next)
            })?;
        Ok(SettingsCommit {
            evidence: state,
            operation_id: request.operation_id,
            changed,
            effect: CommandEffectPoint::FutureSession,
            followup: Followup::None,
        })
    }

    pub fn save_acp_account(
        &self,
        request: UpdateAcpAccountRequest,
    ) -> Result<SettingsCommandReply> {
        let operation_id = request.operation_id.clone();
        let commit = self.commit_save_acp_account(request)?;
        // 连接身份若变化，旧代次在发布前被撤消；设置快照返回新的 connection revision。
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &commit.evidence.configuration,
            commit.changed,
            commit.effect,
        )
    }

    /// 删除一条 ACP 接入。
    ///
    /// 只移除本地接入并取消其所属操作；不注销官方账号、不删除官方凭据、不影响其它接入。
    pub(in crate::studio::runtime) fn commit_remove_acp_account(
        &self,
        request: RemoveAcpAccountRequest,
    ) -> Result<SettingsCommit> {
        Self::validate_operation_id(&request.operation_id)?;
        validate_acp_account_id(&request.account_id)
            .map_err(|_| invalid_settings_argument("ACP account id is invalid"))?;
        let mut changed = false;
        let state = self
            .config_runtime
            .update_evidence(request.expected_revision, |config| {
                let mut next = config.clone();
                changed = next.acp.accounts.remove(&request.account_id).is_some();
                Ok(next)
            })?;
        Ok(SettingsCommit {
            evidence: state,
            operation_id: request.operation_id,
            changed,
            effect: CommandEffectPoint::FutureSession,
            followup: Followup::None,
        })
    }

    pub fn remove_acp_account(
        &self,
        request: RemoveAcpAccountRequest,
    ) -> Result<SettingsCommandReply> {
        let operation_id = request.operation_id.clone();
        let commit = self.commit_remove_acp_account(request)?;
        self.publish_settings_state()?;
        self.settings_command_reply(
            operation_id,
            &commit.evidence.configuration,
            commit.changed,
            commit.effect,
        )
    }

    /// 当前 canonical ACP 认证快照；纯读取，不启动程序。
    pub fn read_acp_auth_state(&self) -> AcpAuthSnapshot {
        self.acp_auth.read_state()
    }

    /// 受理一次 ACP 认证操作（检查或登录）。
    ///
    /// 命令只校验配置连接身份与操作准入，随后立即返回受理回执；进展与终态经 `acpAuth` topic
    /// 发布，调用方不会因人工登录而挂起。
    pub fn start_acp_auth(&self, request: StartAcpAuthRequest) -> Result<AcpAuthCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_auth.start(request)?;
        Ok(AcpAuthCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-auth", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }

    /// 取消当前 ACP 认证操作；终态仍由 owner 在资源收尾后发布。
    pub fn cancel_acp_auth(&self, request: CancelAcpAuthRequest) -> Result<AcpAuthCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_auth.cancel(request)?;
        Ok(AcpAuthCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-auth", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }
}

/// 保存路径的严格校验与归一化；与既有请求字段一一对应，不复制第二套形状。
fn validated_acp_account(
    account: &pl_protocol::studio::AcpAccountUpdate,
) -> Result<(String, AcpAccountConfig)> {
    validate_acp_account_id(&account.account_id)
        .map_err(|_| invalid_settings_argument("ACP account id is invalid"))?;
    validate_acp_name(&account.name)
        .map_err(|_| invalid_settings_argument("ACP account name is invalid"))?;
    Ok((
        account.account_id.clone(),
        normalize_acp_account(AcpAccountConfig {
            name: account.name.clone(),
            provider: config_provider(account.provider),
        }),
    ))
}

/// wire 接入类型到配置类型的穷尽映射；两种表示刻意分离，避免协议类型进入配置文件。
fn config_provider(provider: pl_protocol::studio::AcpProvider) -> ConfigAcpProvider {
    match provider {
        pl_protocol::studio::AcpProvider::Antigravity => ConfigAcpProvider::Antigravity,
    }
}
