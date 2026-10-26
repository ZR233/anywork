// typed 失败枚举 → 本地化产品文案的**唯一**映射。
//
// 只做穷尽 switch：不按 enum 名字做 raw string map、不猜测未知值、不解析后端
// `message`。机器 enum 值（`code.name`/`stage.name`）只保留给技术详情。
import 'package:anywork_client/acp.dart';
import 'package:anywork_client/resources.dart';

import '../../../../l10n/app_localizations.dart';

/// 认证失败类别 → 本地化原因。
String acpAuthFailureCodeText(
  AppLocalizations l10n,
  AcpAuthFailureCode code,
) => switch (code) {
  AcpAuthFailureCode.preparationRequired =>
    l10n.acpFailureCodePreparationRequired,
  AcpAuthFailureCode.installationInvalid =>
    l10n.acpFailureCodeInstallationInvalid,
  AcpAuthFailureCode.unsupportedPlatform =>
    l10n.acpFailureCodeUnsupportedPlatform,
  AcpAuthFailureCode.serverVersionMismatch =>
    l10n.acpFailureCodeServerVersionMismatch,
  AcpAuthFailureCode.startup => l10n.acpFailureCodeStartup,
  AcpAuthFailureCode.missingExecutable => l10n.acpFailureCodeMissingExecutable,
  AcpAuthFailureCode.io => l10n.acpFailureCodeIo,
  AcpAuthFailureCode.unsupportedVersion =>
    l10n.acpFailureCodeUnsupportedVersion,
  AcpAuthFailureCode.unsupportedMethod => l10n.acpFailureCodeUnsupportedMethod,
  AcpAuthFailureCode.authentication => l10n.acpFailureCodeAuthentication,
  AcpAuthFailureCode.probe => l10n.acpFailureCodeProbe,
  AcpAuthFailureCode.protocol => l10n.acpFailureCodeProtocol,
  AcpAuthFailureCode.transport => l10n.acpFailureCodeTransport,
  AcpAuthFailureCode.timeout => l10n.acpFailureCodeTimeout,
  AcpAuthFailureCode.resourceLimit => l10n.acpFailureCodeResourceLimit,
  AcpAuthFailureCode.cancelled => l10n.acpFailureCodeCancelled,
  AcpAuthFailureCode.staleOperation => l10n.acpFailureCodeStaleOperation,
  AcpAuthFailureCode.configChanged => l10n.acpFailureCodeConfigChanged,
  AcpAuthFailureCode.cleanup => l10n.acpFailureCodeCleanup,
  AcpAuthFailureCode.internal => l10n.acpFailureCodeInternal,
};

/// 认证阶段 → 本地化短语（用于拼进失败摘要）。
String acpAuthFailureStageText(AppLocalizations l10n, AcpAuthStage stage) =>
    switch (stage) {
      AcpAuthStage.prepare => l10n.acpFailureStagePrepare,
      AcpAuthStage.process => l10n.acpFailureStageProcess,
      AcpAuthStage.config => l10n.acpFailureStageConfig,
      AcpAuthStage.initialize => l10n.acpFailureStageInitialize,
      AcpAuthStage.authenticate => l10n.acpFailureStageAuthenticate,
      AcpAuthStage.probe => l10n.acpFailureStageProbe,
      AcpAuthStage.close => l10n.acpFailureStageClose,
      AcpAuthStage.cleanup => l10n.acpFailureStageCleanup,
    };

/// 认证失败的就地摘要：原因 + 阶段。后端安全原文只进技术详情。
String acpAuthFailureSummary(AppLocalizations l10n, AcpAuthFailure failure) =>
    l10n.acpAuthFailureSummary(
      acpAuthFailureCodeText(l10n, failure.code),
      acpAuthFailureStageText(l10n, failure.stage),
    );

/// 准备阶段 → 本地化短语。下载 100% 仍然不是就绪，阶段名必须各自可读。
String acpInstallStageText(AppLocalizations l10n, AcpInstallStage stage) =>
    switch (stage) {
      AcpInstallStage.resolve => l10n.acpInstallStageResolve,
      AcpInstallStage.waitForLock => l10n.acpInstallStageWaitForLock,
      AcpInstallStage.download => l10n.acpInstallStageDownload,
      AcpInstallStage.verify => l10n.acpInstallStageVerify,
      AcpInstallStage.extract => l10n.acpInstallStageExtract,
      AcpInstallStage.publish => l10n.acpInstallStagePublish,
      AcpInstallStage.close => l10n.acpInstallStageClose,
    };

/// 准备失败类别 → 本地化原因；不展示原始库错误。
String acpInstallFailureCodeText(
  AppLocalizations l10n,
  AcpInstallFailureCode code,
) => switch (code) {
  AcpInstallFailureCode.unsupportedPlatform =>
    l10n.acpInstallFailureCodeUnsupportedPlatform,
  AcpInstallFailureCode.sourceRejected =>
    l10n.acpInstallFailureCodeSourceRejected,
  AcpInstallFailureCode.network => l10n.acpInstallFailureCodeNetwork,
  AcpInstallFailureCode.timeout => l10n.acpInstallFailureCodeTimeout,
  AcpInstallFailureCode.tooLarge => l10n.acpInstallFailureCodeTooLarge,
  AcpInstallFailureCode.checksumMismatch =>
    l10n.acpInstallFailureCodeChecksumMismatch,
  AcpInstallFailureCode.invalidArchive =>
    l10n.acpInstallFailureCodeInvalidArchive,
  AcpInstallFailureCode.missingExecutable =>
    l10n.acpInstallFailureCodeMissingExecutable,
  AcpInstallFailureCode.cacheCorrupt => l10n.acpInstallFailureCodeCacheCorrupt,
  AcpInstallFailureCode.io => l10n.acpInstallFailureCodeIo,
  AcpInstallFailureCode.busy => l10n.acpInstallFailureCodeBusy,
  AcpInstallFailureCode.staleOperation =>
    l10n.acpInstallFailureCodeStaleOperation,
  AcpInstallFailureCode.cancelled => l10n.acpInstallFailureCodeCancelled,
  AcpInstallFailureCode.resourceClose =>
    l10n.acpInstallFailureCodeResourceClose,
};

/// 准备失败的就地摘要：原因 + 阶段。
String acpInstallFailureSummary(
  AppLocalizations l10n,
  AcpInstallFailure failure,
) => l10n.acpInstallFailureSummary(
  acpInstallFailureCodeText(l10n, failure.code),
  acpInstallStageText(l10n, failure.stage),
);

/// 命令级 typed 失败 → 本地化短原因。
///
/// 命令回执的 `StudioFailure` 是产品可见原因；原始 `message` 只作次级技术详情，
/// 因此不把任意 `toString()` 放进摘要。
String acpStudioFailureCodeText(
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
  // `superseded` 表示命令目标已被更新状态取代；l10n 里唯一准确表达该语义的既有文案是
  // ACP 的“操作已被取代”，因此复用它，而不是新造一个同义键或退回原始 message。
  StudioFailureCode.superseded => l10n.acpFailureCodeStaleOperation,
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
