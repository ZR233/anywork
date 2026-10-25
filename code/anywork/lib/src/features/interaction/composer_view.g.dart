// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_view.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// 只读 Connector 投影；草稿、默认路由解析和 pending 展示规则由 Client 持有。

@ProviderFor(startPageComposerView)
final startPageComposerViewProvider = StartPageComposerViewProvider._();

/// 只读 Connector 投影；草稿、默认路由解析和 pending 展示规则由 Client 持有。

final class StartPageComposerViewProvider
    extends
        $FunctionalProvider<
          StartPageComposerProjection,
          StartPageComposerProjection,
          StartPageComposerProjection
        >
    with $Provider<StartPageComposerProjection> {
  /// 只读 Connector 投影；草稿、默认路由解析和 pending 展示规则由 Client 持有。
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
    r'579c2cc4deffe70ab69b4f4fde2fd24e316e1ed1';

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

String _$composerDockViewHash() => r'e5f666ffb9fffa3a52d06139daefb31ea6946901';

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
