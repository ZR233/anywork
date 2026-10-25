// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ComposerViewModel)
final composerViewModelProvider = ComposerViewModelFamily._();

final class ComposerViewModelProvider
    extends $AsyncNotifierProvider<ComposerViewModel, ComposerViewState> {
  ComposerViewModelProvider._({
    required ComposerViewModelFamily super.from,
    required ComposerKey super.argument,
  }) : super(
         retry: null,
         name: r'composerViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerViewModelHash();

  @override
  String toString() {
    return r'composerViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ComposerViewModel create() => ComposerViewModel();

  @override
  bool operator ==(Object other) {
    return other is ComposerViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerViewModelHash() => r'a7aa2028d11ed3120483a5f11898f0f8ec418878';

final class ComposerViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ComposerViewModel,
          AsyncValue<ComposerViewState>,
          ComposerViewState,
          FutureOr<ComposerViewState>,
          ComposerKey
        > {
  ComposerViewModelFamily._()
    : super(
        retry: null,
        name: r'composerViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ComposerViewModelProvider call(ComposerKey target) =>
      ComposerViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'composerViewModelProvider';
}

abstract class _$ComposerViewModel extends $AsyncNotifier<ComposerViewState> {
  late final _$args = ref.$arg as ComposerKey;
  ComposerKey get target => _$args;

  FutureOr<ComposerViewState> build(ComposerKey target);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ComposerViewState>, ComposerViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ComposerViewState>, ComposerViewState>,
              AsyncValue<ComposerViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
