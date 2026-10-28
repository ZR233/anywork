// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(InteractionViewModel)
final interactionViewModelProvider = InteractionViewModelFamily._();

final class InteractionViewModelProvider
    extends $AsyncNotifierProvider<InteractionViewModel, InteractionViewState> {
  InteractionViewModelProvider._({
    required InteractionViewModelFamily super.from,
    required InteractionEditorKey super.argument,
  }) : super(
         retry: null,
         name: r'interactionViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$interactionViewModelHash();

  @override
  String toString() {
    return r'interactionViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  InteractionViewModel create() => InteractionViewModel();

  @override
  bool operator ==(Object other) {
    return other is InteractionViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$interactionViewModelHash() =>
    r'd80b8ec67197e293bc9610817d00f33c23c9f22a';

final class InteractionViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          InteractionViewModel,
          AsyncValue<InteractionViewState>,
          InteractionViewState,
          FutureOr<InteractionViewState>,
          InteractionEditorKey
        > {
  InteractionViewModelFamily._()
    : super(
        retry: null,
        name: r'interactionViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  InteractionViewModelProvider call(InteractionEditorKey key) =>
      InteractionViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'interactionViewModelProvider';
}

abstract class _$InteractionViewModel
    extends $AsyncNotifier<InteractionViewState> {
  late final _$args = ref.$arg as InteractionEditorKey;
  InteractionEditorKey get key => _$args;

  FutureOr<InteractionViewState> build(InteractionEditorKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<InteractionViewState>, InteractionViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<InteractionViewState>,
                InteractionViewState
              >,
              AsyncValue<InteractionViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
