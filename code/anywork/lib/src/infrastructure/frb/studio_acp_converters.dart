part of 'studio_api.dart';

// ACP 桥接映射：只做 typed DTO ↔ 领域模型，不解析 raw ACP JSON、不读凭据、不猜测
// 未知协议或未知失败类别。生成模块由 `studio_bridge_api.dart` 统一导出，本文件只消费
// 当前生成的 canonical 声明。

AcpProviderView _acpProviderFromFrb(frb.BridgeAcpProvider value) =>
    switch (value) {
      frb.BridgeAcpProvider.antigravity => AcpProviderView.antigravity,
    };

frb.BridgeAcpProvider _acpProviderToFrb(AcpProviderView value) =>
    switch (value) {
      AcpProviderView.antigravity => frb.BridgeAcpProvider.antigravity,
    };

AcpAuthMethodKindView _acpMethodKindFromFrb(
  frb.BridgeAcpAuthMethodKind value,
) => switch (value) {
  frb.BridgeAcpAuthMethodKind.agent => AcpAuthMethodKindView.agent,
  frb.BridgeAcpAuthMethodKind.terminal => AcpAuthMethodKindView.terminal,
  frb.BridgeAcpAuthMethodKind.unsupported => AcpAuthMethodKindView.unsupported,
};

AcpAuthFailureCodeView _acpFailureCodeFromFrb(
  frb.BridgeAcpAuthFailureCode value,
) => switch (value) {
  frb.BridgeAcpAuthFailureCode.preparationRequired =>
    AcpAuthFailureCodeView.preparationRequired,
  frb.BridgeAcpAuthFailureCode.installationInvalid =>
    AcpAuthFailureCodeView.installationInvalid,
  frb.BridgeAcpAuthFailureCode.unsupportedPlatform =>
    AcpAuthFailureCodeView.unsupportedPlatform,
  frb.BridgeAcpAuthFailureCode.serverVersionMismatch =>
    AcpAuthFailureCodeView.serverVersionMismatch,
  frb.BridgeAcpAuthFailureCode.startup => AcpAuthFailureCodeView.startup,
  frb.BridgeAcpAuthFailureCode.missingExecutable =>
    AcpAuthFailureCodeView.missingExecutable,
  frb.BridgeAcpAuthFailureCode.io => AcpAuthFailureCodeView.io,
  frb.BridgeAcpAuthFailureCode.unsupportedVersion =>
    AcpAuthFailureCodeView.unsupportedVersion,
  frb.BridgeAcpAuthFailureCode.unsupportedMethod =>
    AcpAuthFailureCodeView.unsupportedMethod,
  frb.BridgeAcpAuthFailureCode.authentication =>
    AcpAuthFailureCodeView.authentication,
  frb.BridgeAcpAuthFailureCode.probe => AcpAuthFailureCodeView.probe,
  frb.BridgeAcpAuthFailureCode.protocol => AcpAuthFailureCodeView.protocol,
  frb.BridgeAcpAuthFailureCode.transport => AcpAuthFailureCodeView.transport,
  frb.BridgeAcpAuthFailureCode.timeout => AcpAuthFailureCodeView.timeout,
  frb.BridgeAcpAuthFailureCode.resourceLimit =>
    AcpAuthFailureCodeView.resourceLimit,
  frb.BridgeAcpAuthFailureCode.cancelled => AcpAuthFailureCodeView.cancelled,
  frb.BridgeAcpAuthFailureCode.cleanup => AcpAuthFailureCodeView.cleanup,
  frb.BridgeAcpAuthFailureCode.staleOperation =>
    AcpAuthFailureCodeView.staleOperation,
  frb.BridgeAcpAuthFailureCode.configChanged =>
    AcpAuthFailureCodeView.configChanged,
  frb.BridgeAcpAuthFailureCode.internal => AcpAuthFailureCodeView.internal,
};

AcpAuthStageView _acpStageFromFrb(frb.BridgeAcpAuthStage value) =>
    switch (value) {
      frb.BridgeAcpAuthStage.prepare => AcpAuthStageView.prepare,
      frb.BridgeAcpAuthStage.initialize => AcpAuthStageView.initialize,
      frb.BridgeAcpAuthStage.authenticate => AcpAuthStageView.authenticate,
      frb.BridgeAcpAuthStage.probe => AcpAuthStageView.probe,
      frb.BridgeAcpAuthStage.close => AcpAuthStageView.close,
      frb.BridgeAcpAuthStage.process => AcpAuthStageView.process,
      frb.BridgeAcpAuthStage.config => AcpAuthStageView.config,
      frb.BridgeAcpAuthStage.cleanup => AcpAuthStageView.cleanup,
    };

AcpServerInfoView _acpServerFromFrb(frb.BridgeAcpServerInfo value) =>
    AcpServerInfoView(
      name: value.name,
      title: value.title ?? '',
      version: value.version,
    );

AcpAuthMethodView _acpMethodFromFrb(frb.BridgeAcpAuthMethod value) =>
    AcpAuthMethodView(
      id: value.id,
      name: value.name,
      description: value.description ?? '',
      kind: _acpMethodKindFromFrb(value.kind),
    );

AcpAuthFailureView _acpFailureFromFrb(frb.BridgeAcpAuthFailure value) =>
    AcpAuthFailureView(
      code: _acpFailureCodeFromFrb(value.code),
      stage: _acpStageFromFrb(value.stage),
      message: value.message,
      retryable: value.retryable,
    );

AcpAuthStateView _acpAuthStateFromFrb(frb.BridgeAcpAuthState value) =>
    switch (value) {
      frb.BridgeAcpAuthState_Unchecked() => const AcpUncheckedState(),
      frb.BridgeAcpAuthState_Checking(operationId: final operationId) =>
        AcpCheckingState(operationId: operationId),
      frb.BridgeAcpAuthState_Required(
        server: final server,
        methods: final methods,
      ) =>
        AcpRequiredState(
          // 缺少 agentInfo 时保持 null：不伪造服务端身份。
          server: server == null ? null : _acpServerFromFrb(server),
          methods: [for (final method in methods) _acpMethodFromFrb(method)],
        ),
      frb.BridgeAcpAuthState_Authenticating(
        operationId: final operationId,
        methodId: final methodId,
      ) =>
        AcpAuthenticatingState(operationId: operationId, methodId: methodId),
      frb.BridgeAcpAuthState_Verifying(operationId: final operationId) =>
        AcpVerifyingState(operationId: operationId),
      frb.BridgeAcpAuthState_Verified(
        checkedAt: final checkedAt,
        server: final server,
      ) =>
        AcpVerifiedState(
          checkedAt: _frbInt(checkedAt),
          server: server == null ? null : _acpServerFromFrb(server),
        ),
      frb.BridgeAcpAuthState_Closing(
        operationId: final operationId,
        failure: final failure,
      ) =>
        AcpClosingState(
          operationId: operationId,
          failure: failure == null ? null : _acpFailureFromFrb(failure),
        ),
      frb.BridgeAcpAuthState_Cancelling(operationId: final operationId) =>
        AcpCancellingState(operationId: operationId),
      frb.BridgeAcpAuthState_Cancelled() => const AcpCancelledState(),
      frb.BridgeAcpAuthState_Failed(failure: final failure) => AcpFailedState(
        failure: _acpFailureFromFrb(failure),
      ),
    };

AcpAccountTemplateView _acpTemplateFromFrb(
  frb.BridgeAcpAccountTemplate value,
) => AcpAccountTemplateView(
  provider: _acpProviderFromFrb(value.provider),
  displayName: value.displayName,
  description: value.description,
  iconKey: value.iconKey,
  supportedVersion: value.supportedVersion,
  installUrl: value.installUrl,
  termsUrl: value.termsUrl,
  automaticInstall: _acpInstallAvailabilityFromFrb(value.automaticInstall),
);

AcpAccountCatalogView _acpCatalogFromFrb(frb.BridgeAcpAccountCatalog value) =>
    AcpAccountCatalogView(
      templates: [
        for (final template in value.templates) _acpTemplateFromFrb(template),
      ],
    );

AcpAccountSettingsView _acpAccountFromFrb(frb.BridgeAcpAccountSettings value) =>
    AcpAccountSettingsView(
      accountId: value.accountId,
      name: value.name,
      provider: _acpProviderFromFrb(value.provider),
      connectionRevision: _frbInt(value.connectionRevision),
    );

frb.BridgeAcpAccountUpdate _acpAccountUpdateToFrb(AcpAccountUpdateView value) =>
    frb.BridgeAcpAccountUpdate(
      accountId: value.accountId,
      name: value.name,
      provider: _acpProviderToFrb(value.provider),
    );

AcpAuthAccountView _acpAuthAccountFromFrb(frb.BridgeAcpAuthAccount value) =>
    AcpAuthAccountView(
      accountId: value.accountId,
      connectionRevision: _frbInt(value.connectionRevision),
      state: _acpAuthStateFromFrb(value.state),
    );

AcpAuthSnapshotView _acpAuthSnapshotFromFrb(frb.BridgeAcpAuthSnapshot value) =>
    AcpAuthSnapshotView(
      revision: _frbInt(value.revision),
      updatedAt: _frbInt(value.updatedAt),
      accounts: [
        for (final account in value.accounts) _acpAuthAccountFromFrb(account),
      ],
    );

AcpAuthCommandReply _acpAuthReplyFromFrb(frb.BridgeAcpAuthCommandReply value) =>
    AcpAuthCommandReply(
      snapshot: _acpAuthSnapshotFromFrb(value.snapshot),
      receipt: _commandReceiptFromFrb(value.receipt),
    );

frb.BridgeAcpAuthAction _acpAuthActionToFrb(AcpAuthActionView action) =>
    switch (action) {
      AcpCheckActionView() => const frb.BridgeAcpAuthAction.check(),
      AcpAuthenticateActionView(:final methodId) =>
        frb.BridgeAcpAuthAction.authenticate(methodId: methodId),
    };

// ---------------------------------------------------------------------------
// `acpInstall`：官方 server 准备的 typed 映射。
//
// 只做 DTO ↔ 领域模型；不解析 registry JSON、不拼装下载地址、不从字符串推断
// 阶段或失败类别。生成端把阶段、目标平台与进度都表达为 typed 值。
// ---------------------------------------------------------------------------

AcpInstallAvailabilityView _acpInstallAvailabilityFromFrb(
  frb.BridgeAcpInstallAvailability value,
) => switch (value) {
  frb.BridgeAcpInstallAvailability_Available(:final target) =>
    AcpInstallAvailableView(target: target),
  frb.BridgeAcpInstallAvailability_UnsupportedPlatform() =>
    const AcpInstallUnsupportedPlatformView(),
};

AcpInstallStageView _acpInstallStageFromFrb(frb.BridgeAcpInstallStage value) =>
    switch (value) {
      frb.BridgeAcpInstallStage.resolve => AcpInstallStageView.resolve,
      frb.BridgeAcpInstallStage.waitForLock => AcpInstallStageView.waitForLock,
      frb.BridgeAcpInstallStage.download => AcpInstallStageView.download,
      frb.BridgeAcpInstallStage.verify => AcpInstallStageView.verify,
      frb.BridgeAcpInstallStage.extract => AcpInstallStageView.extract,
      frb.BridgeAcpInstallStage.publish => AcpInstallStageView.publish,
      frb.BridgeAcpInstallStage.close => AcpInstallStageView.close,
    };

AcpInstallFailureCodeView _acpInstallFailureCodeFromFrb(
  frb.BridgeAcpInstallFailureCode value,
) => switch (value) {
  frb.BridgeAcpInstallFailureCode.unsupportedPlatform =>
    AcpInstallFailureCodeView.unsupportedPlatform,
  frb.BridgeAcpInstallFailureCode.sourceRejected =>
    AcpInstallFailureCodeView.sourceRejected,
  frb.BridgeAcpInstallFailureCode.network => AcpInstallFailureCodeView.network,
  frb.BridgeAcpInstallFailureCode.timeout => AcpInstallFailureCodeView.timeout,
  frb.BridgeAcpInstallFailureCode.tooLarge =>
    AcpInstallFailureCodeView.tooLarge,
  frb.BridgeAcpInstallFailureCode.checksumMismatch =>
    AcpInstallFailureCodeView.checksumMismatch,
  frb.BridgeAcpInstallFailureCode.invalidArchive =>
    AcpInstallFailureCodeView.invalidArchive,
  frb.BridgeAcpInstallFailureCode.missingExecutable =>
    AcpInstallFailureCodeView.missingExecutable,
  frb.BridgeAcpInstallFailureCode.cacheCorrupt =>
    AcpInstallFailureCodeView.cacheCorrupt,
  frb.BridgeAcpInstallFailureCode.io => AcpInstallFailureCodeView.io,
  frb.BridgeAcpInstallFailureCode.busy => AcpInstallFailureCodeView.busy,
  frb.BridgeAcpInstallFailureCode.staleOperation =>
    AcpInstallFailureCodeView.staleOperation,
  frb.BridgeAcpInstallFailureCode.cancelled =>
    AcpInstallFailureCodeView.cancelled,
  frb.BridgeAcpInstallFailureCode.resourceClose =>
    AcpInstallFailureCodeView.resourceClose,
};

AcpInstallReleaseView _acpInstallReleaseFromFrb(
  frb.BridgeAcpInstallRelease value,
) => AcpInstallReleaseView(
  version: value.version,
  target: value.target,
  archiveUrl: value.archiveUrl,
  sha256: value.sha256,
);

AcpInstallProgressView _acpInstallProgressFromFrb(
  frb.BridgeAcpInstallProgress value,
) => AcpInstallProgressView(
  completedBytes: _frbInt(value.completedBytes),
  totalBytes: _frbNullableInt(value.totalBytes),
  bytesPerSecond: _frbNullableInt(value.bytesPerSecond),
);

AcpInstallFailureView _acpInstallFailureFromFrb(
  frb.BridgeAcpInstallFailure value,
) => AcpInstallFailureView(
  code: _acpInstallFailureCodeFromFrb(value.code),
  stage: _acpInstallStageFromFrb(value.stage),
  message: value.message,
  retryable: value.retryable,
);

AcpInstalledServerView _acpInstalledServerFromFrb(
  frb.BridgeAcpInstalledServer value,
) => AcpInstalledServerView(
  installationId: value.installationId,
  release: _acpInstallReleaseFromFrb(value.release),
  program: value.program,
  readyAt: _frbInt(value.readyAt),
  reused: value.reused,
);

AcpInstallStateView _acpInstallStateFromFrb(frb.BridgeAcpInstallState value) =>
    switch (value) {
      frb.BridgeAcpInstallState_Idle() => const AcpInstallIdleState(),
      frb.BridgeAcpInstallState_Resolving(:final operationId) =>
        AcpResolvingState(operationId: operationId),
      frb.BridgeAcpInstallState_Waiting(:final operationId, :final release) =>
        AcpWaitingForAssetState(
          operationId: operationId,
          release: _acpInstallReleaseFromFrb(release),
        ),
      frb.BridgeAcpInstallState_Downloading(
        :final operationId,
        :final release,
        :final progress,
        :final retryCount,
      ) =>
        AcpDownloadingState(
          operationId: operationId,
          release: _acpInstallReleaseFromFrb(release),
          progress: _acpInstallProgressFromFrb(progress),
          retryCount: _frbInt(retryCount),
        ),
      frb.BridgeAcpInstallState_Verifying(
        :final operationId,
        :final release,
        :final progress,
      ) =>
        AcpInstallVerifyingState(
          operationId: operationId,
          release: _acpInstallReleaseFromFrb(release),
          progress: _acpInstallProgressFromFrb(progress),
        ),
      frb.BridgeAcpInstallState_Extracting(
        :final operationId,
        :final release,
        :final progress,
      ) =>
        AcpExtractingState(
          operationId: operationId,
          release: _acpInstallReleaseFromFrb(release),
          progress: _acpInstallProgressFromFrb(progress),
        ),
      frb.BridgeAcpInstallState_Publishing(
        :final operationId,
        :final release,
      ) =>
        AcpPublishingState(
          operationId: operationId,
          release: _acpInstallReleaseFromFrb(release),
        ),
      frb.BridgeAcpInstallState_Closing(:final operationId, :final failure) =>
        AcpInstallClosingState(
          operationId: operationId,
          failure: failure == null ? null : _acpInstallFailureFromFrb(failure),
        ),
      frb.BridgeAcpInstallState_Ready(:final operationId, :final server) =>
        AcpInstallReadyState(
          operationId: operationId,
          server: _acpInstalledServerFromFrb(server),
        ),
      frb.BridgeAcpInstallState_Cancelling(:final operationId) =>
        AcpInstallCancellingState(operationId: operationId),
      frb.BridgeAcpInstallState_Cancelled(:final operationId) =>
        AcpInstallCancelledState(operationId: operationId),
      frb.BridgeAcpInstallState_Failed(:final operationId, :final failure) =>
        AcpInstallFailedState(
          operationId: operationId,
          failure: _acpInstallFailureFromFrb(failure),
        ),
    };

AcpInstallEntryView _acpInstallEntryFromFrb(frb.BridgeAcpInstallEntry value) =>
    AcpInstallEntryView(
      provider: _acpProviderFromFrb(value.provider),
      state: _acpInstallStateFromFrb(value.state),
    );

AcpInstallSnapshotView _acpInstallSnapshotFromFrb(
  frb.BridgeAcpInstallSnapshot value,
) => AcpInstallSnapshotView(
  revision: _frbInt(value.revision),
  updatedAt: _frbInt(value.updatedAt),
  installations: [
    for (final entry in value.installations) _acpInstallEntryFromFrb(entry),
  ],
);

AcpInstallCommandReply _acpInstallReplyFromFrb(
  frb.BridgeAcpInstallCommandReply value,
) => AcpInstallCommandReply(
  snapshot: _acpInstallSnapshotFromFrb(value.snapshot),
  receipt: _commandReceiptFromFrb(value.receipt),
);
