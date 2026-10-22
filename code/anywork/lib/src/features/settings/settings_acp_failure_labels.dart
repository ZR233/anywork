import 'package:anywork_client/studio_client.dart';

import '../../l10n/app_localizations.dart';

/// typed 失败枚举 → 本地化产品文案的**唯一**映射。
///
/// 只做穷尽 switch：不按 enum 名字做 raw string map、不猜测未知值、不解析后端
/// message。机器 enum 值（`code.name`/`stage.name`）只保留给技术详情。
String acpAuthFailureCodeText(
  AppLocalizations l10n,
  AcpAuthFailureCodeView code,
) => switch (code) {
  AcpAuthFailureCodeView.startup => l10n.acpFailureCodeStartup,
  AcpAuthFailureCodeView.missingExecutable =>
    l10n.acpFailureCodeMissingExecutable,
  AcpAuthFailureCodeView.io => l10n.acpFailureCodeIo,
  AcpAuthFailureCodeView.unsupportedVersion =>
    l10n.acpFailureCodeUnsupportedVersion,
  AcpAuthFailureCodeView.unsupportedMethod =>
    l10n.acpFailureCodeUnsupportedMethod,
  AcpAuthFailureCodeView.authentication => l10n.acpFailureCodeAuthentication,
  AcpAuthFailureCodeView.probe => l10n.acpFailureCodeProbe,
  AcpAuthFailureCodeView.protocol => l10n.acpFailureCodeProtocol,
  AcpAuthFailureCodeView.transport => l10n.acpFailureCodeTransport,
  AcpAuthFailureCodeView.timeout => l10n.acpFailureCodeTimeout,
  AcpAuthFailureCodeView.resourceLimit => l10n.acpFailureCodeResourceLimit,
  AcpAuthFailureCodeView.cancelled => l10n.acpFailureCodeCancelled,
  AcpAuthFailureCodeView.staleOperation => l10n.acpFailureCodeStaleOperation,
  AcpAuthFailureCodeView.configChanged => l10n.acpFailureCodeConfigChanged,
  AcpAuthFailureCodeView.cleanup => l10n.acpFailureCodeCleanup,
  AcpAuthFailureCodeView.internal => l10n.acpFailureCodeInternal,
};

/// 认证阶段 → 本地化短语（用于拼进失败摘要）。
String acpAuthFailureStageText(AppLocalizations l10n, AcpAuthStageView stage) =>
    switch (stage) {
      AcpAuthStageView.process => l10n.acpFailureStageProcess,
      AcpAuthStageView.config => l10n.acpFailureStageConfig,
      AcpAuthStageView.initialize => l10n.acpFailureStageInitialize,
      AcpAuthStageView.authenticate => l10n.acpFailureStageAuthenticate,
      AcpAuthStageView.probe => l10n.acpFailureStageProbe,
      AcpAuthStageView.close => l10n.acpFailureStageClose,
      AcpAuthStageView.cleanup => l10n.acpFailureStageCleanup,
    };

/// 命令级 typed 失败 → 本地化短原因。
String studioFailureCodeText(
  AppLocalizations l10n,
  StudioFailureCode code,
) => switch (code) {
  StudioFailureCode.notInitialized => l10n.studioFailureCodeNotInitialized,
  StudioFailureCode.runtimeStopped => l10n.studioFailureCodeRuntimeStopped,
  StudioFailureCode.instanceBusy => l10n.studioFailureCodeInstanceBusy,
  StudioFailureCode.invalidArgument => l10n.studioFailureCodeInvalidArgument,
  StudioFailureCode.notFound => l10n.studioFailureCodeNotFound,
  StudioFailureCode.busy => l10n.studioFailureCodeBusy,
  StudioFailureCode.conflict => l10n.studioFailureCodeConflict,
  StudioFailureCode.staleRevision => l10n.studioFailureCodeStaleRevision,
  StudioFailureCode.permissionDenied => l10n.studioFailureCodePermissionDenied,
  StudioFailureCode.cancelled => l10n.studioFailureCodeCancelled,
  StudioFailureCode.cancellationTooLate =>
    l10n.studioFailureCodeCancellationTooLate,
  StudioFailureCode.overloaded => l10n.studioFailureCodeOverloaded,
  StudioFailureCode.unavailable => l10n.studioFailureCodeUnavailable,
  StudioFailureCode.protocol => l10n.studioFailureCodeProtocol,
  StudioFailureCode.storage => l10n.studioFailureCodeStorage,
  StudioFailureCode.update => l10n.studioFailureCodeUpdate,
  StudioFailureCode.internal => l10n.studioFailureCodeInternal,
};
