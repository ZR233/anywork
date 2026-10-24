//! ACP 官方 server 准备命令的 runtime 入口。
//!
//! 三个命令都是显式意图：读取是纯查询，准备与取消只做 owner 内准入并立即返回受理回执；长网络/
//! 文件 IO 由安装 owner 在后台推进，不持 Settings 提交锁，也不占用认证状态（见 design/28 §28.6）。

use anyhow::Result;
use pl_protocol::studio::{
    AcpInstallCommandReply, AcpInstallSnapshot, CancelAcpInstallRequest, CommandEffectPoint,
    StartAcpInstallRequest,
};

use super::StudioRuntime;

impl StudioRuntime {
    /// 当前 canonical 安装快照；纯读取，不联网、不扫描、不启动。
    pub fn read_acp_install_state(&self) -> AcpInstallSnapshot {
        self.acp_install.read_state()
    }

    /// 受理一次官方 server 准备；不保存账号、不启动认证。
    pub fn start_acp_install(
        &self,
        request: StartAcpInstallRequest,
    ) -> Result<AcpInstallCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_install.start(request)?;
        Ok(AcpInstallCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-install", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }

    /// 取消当前准备操作；终态仍由 owner 在资源收束后发布。
    pub fn cancel_acp_install(
        &self,
        request: CancelAcpInstallRequest,
    ) -> Result<AcpInstallCommandReply> {
        Self::validate_operation_id(&request.operation_id)?;
        let operation_id = request.operation_id.clone();
        let acceptance = self.acp_install.cancel(request)?;
        Ok(AcpInstallCommandReply {
            receipt: self.command_receipt(
                operation_id,
                acceptance.changed,
                vec![self.resource_stamp("acp-install", acceptance.snapshot.revision)],
                CommandEffectPoint::Immediate,
                false,
            ),
            snapshot: acceptance.snapshot,
        })
    }
}
