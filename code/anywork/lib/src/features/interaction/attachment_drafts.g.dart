// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment_drafts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 附件草稿的 admission / preview / removal。
///
/// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
/// 附件并写入 typed composer failure。不再使用 lifecycle token 或 barrier；同一目标
/// 的写入由 [CommandLane] 串行，提交前由调用方按 threadSessionStore 校验目标仍在。
/// 失败只记录诊断，不回滚 canonical。

@ProviderFor(AttachmentDrafts)
final attachmentDraftsProvider = AttachmentDraftsProvider._();

/// 附件草稿的 admission / preview / removal。
///
/// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
/// 附件并写入 typed composer failure。不再使用 lifecycle token 或 barrier；同一目标
/// 的写入由 [CommandLane] 串行，提交前由调用方按 threadSessionStore 校验目标仍在。
/// 失败只记录诊断，不回滚 canonical。
final class AttachmentDraftsProvider
    extends $NotifierProvider<AttachmentDrafts, AttachmentDraftBoard> {
  /// 附件草稿的 admission / preview / removal。
  ///
  /// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
  /// 附件并写入 typed composer failure。不再使用 lifecycle token 或 barrier；同一目标
  /// 的写入由 [CommandLane] 串行，提交前由调用方按 threadSessionStore 校验目标仍在。
  /// 失败只记录诊断，不回滚 canonical。
  AttachmentDraftsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'attachmentDraftsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$attachmentDraftsHash();

  @$internal
  @override
  AttachmentDrafts create() => AttachmentDrafts();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AttachmentDraftBoard value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AttachmentDraftBoard>(value),
    );
  }
}

String _$attachmentDraftsHash() => r'0819208ddbc0b4b009c5b97dfbf3b55be51d4eaf';

/// 附件草稿的 admission / preview / removal。
///
/// 两阶段：先发布稳定 metadata，再按 draft id 异步补 preview。预览失败保留已准入
/// 附件并写入 typed composer failure。不再使用 lifecycle token 或 barrier；同一目标
/// 的写入由 [CommandLane] 串行，提交前由调用方按 threadSessionStore 校验目标仍在。
/// 失败只记录诊断，不回滚 canonical。

abstract class _$AttachmentDrafts extends $Notifier<AttachmentDraftBoard> {
  AttachmentDraftBoard build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<AttachmentDraftBoard, AttachmentDraftBoard>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AttachmentDraftBoard, AttachmentDraftBoard>,
              AttachmentDraftBoard,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
