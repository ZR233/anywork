// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_session_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 起始页 route 作用域草稿。不进入全局 store；autoDispose，最后一个观察者离开即销毁。
///
/// 正文、Mode 与工作区按项目隔离，未写过的项目使用默认值（`mode.simple` / `local`）。
/// 模型与思考强度意图按 Mode 持有，不属于项目草稿：canonical 永不覆盖它们。
/// 附件引用仍在 [AttachmentDrafts]，按 projectId 组织。

@ProviderFor(StartSessionController)
final startSessionControllerProvider = StartSessionControllerProvider._();

/// 起始页 route 作用域草稿。不进入全局 store；autoDispose，最后一个观察者离开即销毁。
///
/// 正文、Mode 与工作区按项目隔离，未写过的项目使用默认值（`mode.simple` / `local`）。
/// 模型与思考强度意图按 Mode 持有，不属于项目草稿：canonical 永不覆盖它们。
/// 附件引用仍在 [AttachmentDrafts]，按 projectId 组织。
final class StartSessionControllerProvider
    extends $NotifierProvider<StartSessionController, StartSessionDraft> {
  /// 起始页 route 作用域草稿。不进入全局 store；autoDispose，最后一个观察者离开即销毁。
  ///
  /// 正文、Mode 与工作区按项目隔离，未写过的项目使用默认值（`mode.simple` / `local`）。
  /// 模型与思考强度意图按 Mode 持有，不属于项目草稿：canonical 永不覆盖它们。
  /// 附件引用仍在 [AttachmentDrafts]，按 projectId 组织。
  StartSessionControllerProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startSessionControllerProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startSessionControllerHash();

  @$internal
  @override
  StartSessionController create() => StartSessionController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartSessionDraft value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartSessionDraft>(value),
    );
  }
}

String _$startSessionControllerHash() =>
    r'37601da77c86deedfc5adb92206afb62abecdd74';

/// 起始页 route 作用域草稿。不进入全局 store；autoDispose，最后一个观察者离开即销毁。
///
/// 正文、Mode 与工作区按项目隔离，未写过的项目使用默认值（`mode.simple` / `local`）。
/// 模型与思考强度意图按 Mode 持有，不属于项目草稿：canonical 永不覆盖它们。
/// 附件引用仍在 [AttachmentDrafts]，按 projectId 组织。

abstract class _$StartSessionController extends $Notifier<StartSessionDraft> {
  StartSessionDraft build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StartSessionDraft, StartSessionDraft>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StartSessionDraft, StartSessionDraft>,
              StartSessionDraft,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
