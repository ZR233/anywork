// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StartPageComposerViewModel)
final startPageComposerViewModelProvider =
    StartPageComposerViewModelProvider._();

final class StartPageComposerViewModelProvider
    extends
        $AsyncNotifierProvider<
          StartPageComposerViewModel,
          StartPageComposerViewState
        > {
  StartPageComposerViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'startPageComposerViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$startPageComposerViewModelHash();

  @$internal
  @override
  StartPageComposerViewModel create() => StartPageComposerViewModel();
}

String _$startPageComposerViewModelHash() =>
    r'fdb13bdae60b686b0ea5525ba32881aeb84b6633';

abstract class _$StartPageComposerViewModel
    extends $AsyncNotifier<StartPageComposerViewState> {
  FutureOr<StartPageComposerViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<StartPageComposerViewState>,
              StartPageComposerViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<StartPageComposerViewState>,
                StartPageComposerViewState
              >,
              AsyncValue<StartPageComposerViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}

@ProviderFor(ComposerDockViewModel)
final composerDockViewModelProvider = ComposerDockViewModelFamily._();

final class ComposerDockViewModelProvider
    extends
        $AsyncNotifierProvider<ComposerDockViewModel, ComposerDockViewState> {
  ComposerDockViewModelProvider._({
    required ComposerDockViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'composerDockViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerDockViewModelHash();

  @override
  String toString() {
    return r'composerDockViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ComposerDockViewModel create() => ComposerDockViewModel();

  @override
  bool operator ==(Object other) {
    return other is ComposerDockViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerDockViewModelHash() =>
    r'4ea1923a3c83763e06bdc95b795ef86e86936551';

final class ComposerDockViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ComposerDockViewModel,
          AsyncValue<ComposerDockViewState>,
          ComposerDockViewState,
          FutureOr<ComposerDockViewState>,
          String
        > {
  ComposerDockViewModelFamily._()
    : super(
        retry: null,
        name: r'composerDockViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ComposerDockViewModelProvider call(String threadId) =>
      ComposerDockViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'composerDockViewModelProvider';
}

abstract class _$ComposerDockViewModel
    extends $AsyncNotifier<ComposerDockViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<ComposerDockViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ComposerDockViewState>, ComposerDockViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ComposerDockViewState>,
                ComposerDockViewState
              >,
              AsyncValue<ComposerDockViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
