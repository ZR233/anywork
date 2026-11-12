// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One target-bound presentation owner, not a second draft or submission owner.

@ProviderFor(ComposerViewModel)
final composerViewModelProvider = ComposerViewModelFamily._();

/// One target-bound presentation owner, not a second draft or submission owner.
final class ComposerViewModelProvider
    extends $AsyncNotifierProvider<ComposerViewModel, ComposerViewState> {
  /// One target-bound presentation owner, not a second draft or submission owner.
  ComposerViewModelProvider._({
    required ComposerViewModelFamily super.from,
    required ComposerTarget super.argument,
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

String _$composerViewModelHash() => r'5ac635b73b2a0f77a93d90d00f37b49b45746b62';

/// One target-bound presentation owner, not a second draft or submission owner.

final class ComposerViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ComposerViewModel,
          AsyncValue<ComposerViewState>,
          ComposerViewState,
          FutureOr<ComposerViewState>,
          ComposerTarget
        > {
  ComposerViewModelFamily._()
    : super(
        retry: null,
        name: r'composerViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One target-bound presentation owner, not a second draft or submission owner.

  ComposerViewModelProvider call(ComposerTarget target) =>
      ComposerViewModelProvider._(argument: target, from: this);

  @override
  String toString() => r'composerViewModelProvider';
}

/// One target-bound presentation owner, not a second draft or submission owner.

abstract class _$ComposerViewModel extends $AsyncNotifier<ComposerViewState> {
  late final _$args = ref.$arg as ComposerTarget;
  ComposerTarget get target => _$args;

  FutureOr<ComposerViewState> build(ComposerTarget target);
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
