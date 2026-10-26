import 'package:anywork_client/acp.dart';

import '../../../../rust/api/studio/types/acp.dart' as native;
import '../../../../rust/api/studio/types/acp_install.dart' as native_install;
import '../../shared/exact_numbers.dart';
import '../../shared/read_converters.dart';

/// ACP 的 FRB typed DTO ↔ 领域值映射。
///
/// 只做逐字段转换：不解析文本、不读取凭据、不把 `acpAuth` 与 `acpInstall` 合并成
/// 一个版本域，也不从本地布尔值或进度推断“已登录”“已就绪”。所有枚举分支都显式
/// 穷举，生成端新增值时本文件编译失败，而不是静默落到默认类别。
///
/// `null` 与空字符串在这里保持生成端的真实事实：[AcpServerInfo.title]、
/// [AcpAuthMethod.description] 与 [AcpInstallRelease.sha256] 的缺失不被本地文案
/// 或账号名称补造。

AcpProvider acpProviderFromBridge(native.BridgeAcpProvider value) =>
    switch (value) {
      native.BridgeAcpProvider.antigravity => AcpProvider.antigravity,
    };

native.BridgeAcpProvider acpProviderToBridge(AcpProvider value) =>
    switch (value) {
      AcpProvider.antigravity => native.BridgeAcpProvider.antigravity,
    };

AcpAuthMethodKind acpAuthMethodKindFromBridge(
  native.BridgeAcpAuthMethodKind value,
) => switch (value) {
  native.BridgeAcpAuthMethodKind.agent => AcpAuthMethodKind.agent,
  native.BridgeAcpAuthMethodKind.terminal => AcpAuthMethodKind.terminal,
  native.BridgeAcpAuthMethodKind.unsupported => AcpAuthMethodKind.unsupported,
};

AcpAuthMethod acpAuthMethodFromBridge(native.BridgeAcpAuthMethod value) =>
    AcpAuthMethod(
      id: value.id,
      name: value.name,
      description: value.description,
      kind: acpAuthMethodKindFromBridge(value.kind),
    );

AcpServerInfo acpServerInfoFromBridge(native.BridgeAcpServerInfo value) =>
    AcpServerInfo(name: value.name, title: value.title, version: value.version);

AcpAuthFailureCode acpAuthFailureCodeFromBridge(
  native.BridgeAcpAuthFailureCode value,
) => switch (value) {
  native.BridgeAcpAuthFailureCode.preparationRequired =>
    AcpAuthFailureCode.preparationRequired,
  native.BridgeAcpAuthFailureCode.installationInvalid =>
    AcpAuthFailureCode.installationInvalid,
  native.BridgeAcpAuthFailureCode.unsupportedPlatform =>
    AcpAuthFailureCode.unsupportedPlatform,
  native.BridgeAcpAuthFailureCode.serverVersionMismatch =>
    AcpAuthFailureCode.serverVersionMismatch,
  native.BridgeAcpAuthFailureCode.startup => AcpAuthFailureCode.startup,
  native.BridgeAcpAuthFailureCode.missingExecutable =>
    AcpAuthFailureCode.missingExecutable,
  native.BridgeAcpAuthFailureCode.io => AcpAuthFailureCode.io,
  native.BridgeAcpAuthFailureCode.unsupportedVersion =>
    AcpAuthFailureCode.unsupportedVersion,
  native.BridgeAcpAuthFailureCode.unsupportedMethod =>
    AcpAuthFailureCode.unsupportedMethod,
  native.BridgeAcpAuthFailureCode.authentication =>
    AcpAuthFailureCode.authentication,
  native.BridgeAcpAuthFailureCode.probe => AcpAuthFailureCode.probe,
  native.BridgeAcpAuthFailureCode.protocol => AcpAuthFailureCode.protocol,
  native.BridgeAcpAuthFailureCode.transport => AcpAuthFailureCode.transport,
  native.BridgeAcpAuthFailureCode.timeout => AcpAuthFailureCode.timeout,
  native.BridgeAcpAuthFailureCode.resourceLimit =>
    AcpAuthFailureCode.resourceLimit,
  native.BridgeAcpAuthFailureCode.cancelled => AcpAuthFailureCode.cancelled,
  native.BridgeAcpAuthFailureCode.staleOperation =>
    AcpAuthFailureCode.staleOperation,
  native.BridgeAcpAuthFailureCode.configChanged =>
    AcpAuthFailureCode.configChanged,
  native.BridgeAcpAuthFailureCode.cleanup => AcpAuthFailureCode.cleanup,
  native.BridgeAcpAuthFailureCode.internal => AcpAuthFailureCode.internal,
};

AcpAuthStage acpAuthStageFromBridge(native.BridgeAcpAuthStage value) =>
    switch (value) {
      native.BridgeAcpAuthStage.prepare => AcpAuthStage.prepare,
      native.BridgeAcpAuthStage.process => AcpAuthStage.process,
      native.BridgeAcpAuthStage.config => AcpAuthStage.config,
      native.BridgeAcpAuthStage.initialize => AcpAuthStage.initialize,
      native.BridgeAcpAuthStage.authenticate => AcpAuthStage.authenticate,
      native.BridgeAcpAuthStage.probe => AcpAuthStage.probe,
      native.BridgeAcpAuthStage.close => AcpAuthStage.close,
      native.BridgeAcpAuthStage.cleanup => AcpAuthStage.cleanup,
    };

AcpAuthFailure acpAuthFailureFromBridge(native.BridgeAcpAuthFailure value) =>
    AcpAuthFailure(
      code: acpAuthFailureCodeFromBridge(value.code),
      stage: acpAuthStageFromBridge(value.stage),
      message: value.message,
      retryable: value.retryable,
    );

/// 单个接入的认证状态；`closing`／`cancelling` 等非终态原样保留。
///
/// `unchecked` 不等于失败，`verified` 只表示当时观察，二者都不在这里被压缩或补造。
AcpAuthState acpAuthStateFromBridge(native.BridgeAcpAuthState value) =>
    switch (value) {
      native.BridgeAcpAuthState_Unchecked() => const AcpAuthUnchecked(),
      native.BridgeAcpAuthState_Checking(:final operationId) => AcpAuthChecking(
        operationId: operationId,
      ),
      native.BridgeAcpAuthState_Required(:final methods, :final server) =>
        AcpAuthRequired(
          // 对端未提供 `agentInfo` 时保持 null：不拿账号名冒充服务端身份。
          server: server == null ? null : acpServerInfoFromBridge(server),
          methods: [
            for (final method in methods) acpAuthMethodFromBridge(method),
          ],
        ),
      native.BridgeAcpAuthState_Authenticating(
        :final operationId,
        :final methodId,
      ) =>
        AcpAuthAuthenticating(operationId: operationId, methodId: methodId),
      native.BridgeAcpAuthState_Verifying(:final operationId) =>
        AcpAuthVerifying(operationId: operationId),
      native.BridgeAcpAuthState_Closing(:final operationId, :final failure) =>
        AcpAuthClosing(
          operationId: operationId,
          // 收束失败只是资源问题，不是认证结果。
          failure: failure == null ? null : acpAuthFailureFromBridge(failure),
        ),
      native.BridgeAcpAuthState_Verified(:final checkedAt, :final server) =>
        AcpAuthVerified(
          checkedAt: exactI64(BigInt.from(checkedAt), 'ACP auth checked time'),
          server: server == null ? null : acpServerInfoFromBridge(server),
        ),
      native.BridgeAcpAuthState_Cancelling(:final operationId) =>
        AcpAuthCancelling(operationId: operationId),
      native.BridgeAcpAuthState_Cancelled() => const AcpAuthCancelled(),
      native.BridgeAcpAuthState_Failed(:final failure) => AcpAuthFailed(
        failure: acpAuthFailureFromBridge(failure),
      ),
    };

AcpAuthAccount acpAuthAccountFromBridge(native.BridgeAcpAuthAccount value) =>
    AcpAuthAccount(
      accountId: value.accountId,
      connectionRevision: exactU64(
        value.connectionRevision,
        'ACP connection revision',
      ),
      state: acpAuthStateFromBridge(value.state),
    );

AcpAuthSnapshot acpAuthSnapshotFromBridge(native.BridgeAcpAuthSnapshot value) =>
    AcpAuthSnapshot(
      revision: exactU64(value.revision, 'ACP auth revision'),
      updatedAt: exactI64(
        BigInt.from(value.updatedAt),
        'ACP auth updated time',
      ),
      accounts: [
        for (final account in value.accounts) acpAuthAccountFromBridge(account),
      ],
    );

/// 显式认证意图；`check` 与 `authenticate` 是两个不同命令，不互相回退。
native.BridgeAcpAuthAction acpAuthActionToBridge(AcpAuthAction value) =>
    switch (value) {
      AcpAuthCheck() => const native.BridgeAcpAuthAction.check(),
      AcpAuthAuthenticate(:final methodId) =>
        native.BridgeAcpAuthAction.authenticate(methodId: methodId),
    };

AcpInstallAvailability acpInstallAvailabilityFromBridge(
  native_install.BridgeAcpInstallAvailability value,
) => switch (value) {
  native_install.BridgeAcpInstallAvailability_Available(:final target) =>
    AcpInstallAvailable(target: target),
  native_install.BridgeAcpInstallAvailability_UnsupportedPlatform() =>
    const AcpInstallUnsupportedPlatform(),
};

AcpAccountTemplate acpAccountTemplateFromBridge(
  native.BridgeAcpAccountTemplate value,
) => AcpAccountTemplate(
  provider: acpProviderFromBridge(value.provider),
  displayName: value.displayName,
  description: value.description,
  iconKey: value.iconKey,
  supportedVersion: value.supportedVersion,
  installUrl: value.installUrl,
  termsUrl: value.termsUrl,
  automaticInstall: acpInstallAvailabilityFromBridge(value.automaticInstall),
);

/// 只读模板目录；空目录是后端事实，不是“尚未加载”的替代值。
AcpAccountCatalog acpAccountCatalogFromBridge(
  native.BridgeAcpAccountCatalog value,
) => AcpAccountCatalog(
  templates: [
    for (final template in value.templates)
      acpAccountTemplateFromBridge(template),
  ],
);

AcpInstallStage acpInstallStageFromBridge(
  native_install.BridgeAcpInstallStage value,
) => switch (value) {
  native_install.BridgeAcpInstallStage.resolve => AcpInstallStage.resolve,
  native_install.BridgeAcpInstallStage.waitForLock =>
    AcpInstallStage.waitForLock,
  native_install.BridgeAcpInstallStage.download => AcpInstallStage.download,
  native_install.BridgeAcpInstallStage.verify => AcpInstallStage.verify,
  native_install.BridgeAcpInstallStage.extract => AcpInstallStage.extract,
  native_install.BridgeAcpInstallStage.publish => AcpInstallStage.publish,
  native_install.BridgeAcpInstallStage.close => AcpInstallStage.close,
};

AcpInstallFailureCode acpInstallFailureCodeFromBridge(
  native_install.BridgeAcpInstallFailureCode value,
) => switch (value) {
  native_install.BridgeAcpInstallFailureCode.unsupportedPlatform =>
    AcpInstallFailureCode.unsupportedPlatform,
  native_install.BridgeAcpInstallFailureCode.sourceRejected =>
    AcpInstallFailureCode.sourceRejected,
  native_install.BridgeAcpInstallFailureCode.network =>
    AcpInstallFailureCode.network,
  native_install.BridgeAcpInstallFailureCode.timeout =>
    AcpInstallFailureCode.timeout,
  native_install.BridgeAcpInstallFailureCode.tooLarge =>
    AcpInstallFailureCode.tooLarge,
  native_install.BridgeAcpInstallFailureCode.checksumMismatch =>
    AcpInstallFailureCode.checksumMismatch,
  native_install.BridgeAcpInstallFailureCode.invalidArchive =>
    AcpInstallFailureCode.invalidArchive,
  native_install.BridgeAcpInstallFailureCode.missingExecutable =>
    AcpInstallFailureCode.missingExecutable,
  native_install.BridgeAcpInstallFailureCode.cacheCorrupt =>
    AcpInstallFailureCode.cacheCorrupt,
  native_install.BridgeAcpInstallFailureCode.io => AcpInstallFailureCode.io,
  native_install.BridgeAcpInstallFailureCode.busy => AcpInstallFailureCode.busy,
  native_install.BridgeAcpInstallFailureCode.staleOperation =>
    AcpInstallFailureCode.staleOperation,
  native_install.BridgeAcpInstallFailureCode.cancelled =>
    AcpInstallFailureCode.cancelled,
  native_install.BridgeAcpInstallFailureCode.resourceClose =>
    AcpInstallFailureCode.resourceClose,
};

AcpInstallFailure acpInstallFailureFromBridge(
  native_install.BridgeAcpInstallFailure value,
) => AcpInstallFailure(
  code: acpInstallFailureCodeFromBridge(value.code),
  stage: acpInstallStageFromBridge(value.stage),
  message: value.message,
  retryable: value.retryable,
);

/// 一次显式保存意图；连接身份不在这里提交，由配置领域按回执解析。
native.BridgeAcpAccountUpdate acpAccountUpdateToBridge(
  AcpAccountUpdate value,
) => native.BridgeAcpAccountUpdate(
  accountId: value.accountId,
  name: value.name,
  provider: acpProviderToBridge(value.provider),
);

AcpInstallRelease acpInstallReleaseFromBridge(
  native_install.BridgeAcpInstallRelease value,
) => AcpInstallRelease(
  version: value.version,
  target: value.target,
  archiveUrl: value.archiveUrl,
  sha256: value.sha256,
);

/// 阶段进度：未知总量与无效速度样本保持 null，不合成百分比。
AcpInstallProgress acpInstallProgressFromBridge(
  native_install.BridgeAcpInstallProgress value,
) => AcpInstallProgress(
  completedBytes: exactU64(value.completedBytes, 'ACP install completed bytes'),
  totalBytes: nullableU64(value.totalBytes, 'ACP install total bytes'),
  bytesPerSecond: nullableU64(
    value.bytesPerSecond,
    'ACP install bytes per second',
  ),
);

AcpInstalledServer acpInstalledServerFromBridge(
  native_install.BridgeAcpInstalledServer value,
) => AcpInstalledServer(
  installationId: value.installationId,
  release: acpInstallReleaseFromBridge(value.release),
  program: value.program,
  readyAt: exactI64(BigInt.from(value.readyAt), 'ACP install ready time'),
  reused: value.reused,
);

/// 单个 provider 的安装状态；终态同样保留 operation 身份。
///
/// 下载进度是后端已处理字节，本层不推算剩余时间、不自造 100%，也不把
/// `ready` 之外的任何状态解释为可用 server。
AcpInstallState acpInstallStateFromBridge(
  native_install.BridgeAcpInstallState value,
) => switch (value) {
  native_install.BridgeAcpInstallState_Idle() => const AcpInstallIdleState(),
  native_install.BridgeAcpInstallState_Resolving(:final operationId) =>
    AcpInstallResolving(operationId: operationId),
  native_install.BridgeAcpInstallState_Waiting(
    :final operationId,
    :final release,
  ) =>
    AcpInstallWaiting(
      operationId: operationId,
      release: acpInstallReleaseFromBridge(release),
    ),
  native_install.BridgeAcpInstallState_Downloading(
    :final operationId,
    :final release,
    :final progress,
    :final retryCount,
  ) =>
    AcpInstallDownloading(
      operationId: operationId,
      release: acpInstallReleaseFromBridge(release),
      progress: acpInstallProgressFromBridge(progress),
      retryCount: retryCount,
    ),
  native_install.BridgeAcpInstallState_Verifying(
    :final operationId,
    :final release,
    :final progress,
  ) =>
    AcpInstallVerifying(
      operationId: operationId,
      release: acpInstallReleaseFromBridge(release),
      progress: acpInstallProgressFromBridge(progress),
    ),
  native_install.BridgeAcpInstallState_Extracting(
    :final operationId,
    :final release,
    :final progress,
  ) =>
    AcpInstallExtracting(
      operationId: operationId,
      release: acpInstallReleaseFromBridge(release),
      progress: acpInstallProgressFromBridge(progress),
    ),
  native_install.BridgeAcpInstallState_Publishing(
    :final operationId,
    :final release,
  ) =>
    AcpInstallPublishing(
      operationId: operationId,
      release: acpInstallReleaseFromBridge(release),
    ),
  native_install.BridgeAcpInstallState_Closing(
    :final operationId,
    :final failure,
  ) =>
    AcpInstallClosing(
      operationId: operationId,
      failure: failure == null ? null : acpInstallFailureFromBridge(failure),
    ),
  native_install.BridgeAcpInstallState_Ready(
    :final operationId,
    :final server,
  ) =>
    AcpInstallReady(
      operationId: operationId,
      server: acpInstalledServerFromBridge(server),
    ),
  native_install.BridgeAcpInstallState_Cancelling(:final operationId) =>
    AcpInstallCancelling(operationId: operationId),
  native_install.BridgeAcpInstallState_Cancelled(:final operationId) =>
    AcpInstallCancelled(operationId: operationId),
  native_install.BridgeAcpInstallState_Failed(
    :final operationId,
    :final failure,
  ) =>
    AcpInstallFailed(
      operationId: operationId,
      failure: acpInstallFailureFromBridge(failure),
    ),
};

AcpInstallEntry acpInstallEntryFromBridge(
  native_install.BridgeAcpInstallEntry value,
) => AcpInstallEntry(
  provider: acpProviderFromBridge(value.provider),
  state: acpInstallStateFromBridge(value.state),
);

AcpInstallSnapshot acpInstallSnapshotFromBridge(
  native_install.BridgeAcpInstallSnapshot value,
) => AcpInstallSnapshot(
  revision: exactU64(value.revision, 'ACP install revision'),
  updatedAt: exactI64(BigInt.from(value.updatedAt), 'ACP install updated time'),
  installations: [
    for (final entry in value.installations) acpInstallEntryFromBridge(entry),
  ],
);
