// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_draft_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
///
/// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。

@ProviderFor(ComposerDraftController)
final composerDraftControllerProvider = ComposerDraftControllerFamily._();

/// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
///
/// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。
final class ComposerDraftControllerProvider
    extends $NotifierProvider<ComposerDraftController, ComposerThreadState> {
  /// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
  ///
  /// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。
  ComposerDraftControllerProvider._({
    required ComposerDraftControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'composerDraftControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerDraftControllerHash();

  @override
  String toString() {
    return r'composerDraftControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ComposerDraftController create() => ComposerDraftController();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ComposerThreadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ComposerThreadState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerDraftControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerDraftControllerHash() =>
    r'32b58a08042cc84196ce5f55ba47b6dbd25bfea2';

/// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
///
/// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。

final class ComposerDraftControllerFamily extends $Family
    with
        $ClassFamilyOverride<
          ComposerDraftController,
          ComposerThreadState,
          ComposerThreadState,
          ComposerThreadState,
          String
        > {
  ComposerDraftControllerFamily._()
    : super(
        retry: null,
        name: r'composerDraftControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
  ///
  /// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。

  ComposerDraftControllerProvider call(String threadId) =>
      ComposerDraftControllerProvider._(argument: threadId, from: this);

  @override
  String toString() => r'composerDraftControllerProvider';
}

/// 会话输入草稿。不进入全局 store；autoDispose，最后一个观察者离开即释放附件。
///
/// 正文、附件引用和编辑状态都在这里。附件 admission 由 [AttachmentDrafts] 执行。

abstract class _$ComposerDraftController
    extends $Notifier<ComposerThreadState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  ComposerThreadState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<ComposerThreadState, ComposerThreadState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<ComposerThreadState, ComposerThreadState>,
              ComposerThreadState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
