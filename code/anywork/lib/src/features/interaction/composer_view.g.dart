// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 起始页投影。Mode、工作区、正文与模型意图来自 route 作用域草稿；
/// 未显式选择时跟随 settingsStore canonical，并用命令 lane 的 pending 目标覆盖。

@ProviderFor(startPageComposerView)
final startPageComposerViewProvider = StartPageComposerViewProvider._();

/// 起始页投影。Mode、工作区、正文与模型意图来自 route 作用域草稿；
/// 未显式选择时跟随 settingsStore canonical，并用命令 lane 的 pending 目标覆盖。

final class StartPageComposerViewProvider
    extends
        $FunctionalProvider<
          StartPageComposerProjection,
          StartPageComposerProjection,
          StartPageComposerProjection
        >
    with $Provider<StartPageComposerProjection> {
  /// 起始页投影。Mode、工作区、正文与模型意图来自 route 作用域草稿；
  /// 未显式选择时跟随 settingsStore canonical，并用命令 lane 的 pending 目标覆盖。
  StartPageComposerViewProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startPageComposerViewProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startPageComposerViewHash();

  @$internal
  @override
  $ProviderElement<StartPageComposerProjection> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  StartPageComposerProjection create(Ref ref) {
    return startPageComposerView(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartPageComposerProjection value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartPageComposerProjection>(value),
    );
  }
}

String _$startPageComposerViewHash() =>
    r'a1f0b7d75c03bddeebfb361429f1fc1a7796db50';

@ProviderFor(composerDockView)
final composerDockViewProvider = ComposerDockViewFamily._();

final class ComposerDockViewProvider
    extends
        $FunctionalProvider<
          ComposerDockView,
          ComposerDockView,
          ComposerDockView
        >
    with $Provider<ComposerDockView> {
  ComposerDockViewProvider._({
    required ComposerDockViewFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'composerDockViewProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerDockViewHash();

  @override
  String toString() {
    return r'composerDockViewProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ComposerDockView> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  ComposerDockView create(Ref ref) {
    final argument = this.argument as String;
    return composerDockView(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ComposerDockView value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ComposerDockView>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerDockViewProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerDockViewHash() => r'a0f2b7f468ab5bfc6b2f86f8ae81b8e3d7027eb1';

final class ComposerDockViewFamily extends $Family
    with $FunctionalFamilyOverride<ComposerDockView, String> {
  ComposerDockViewFamily._()
    : super(
        retry: null,
        name: r'composerDockViewProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ComposerDockViewProvider call(String threadId) =>
      ComposerDockViewProvider._(argument: threadId, from: this);

  @override
  String toString() => r'composerDockViewProvider';
}
