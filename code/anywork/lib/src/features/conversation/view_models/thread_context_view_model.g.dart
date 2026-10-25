// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_context_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ThreadContextViewModel)
final threadContextViewModelProvider = ThreadContextViewModelFamily._();

final class ThreadContextViewModelProvider
    extends
        $AsyncNotifierProvider<ThreadContextViewModel, ThreadContextViewState> {
  ThreadContextViewModelProvider._({
    required ThreadContextViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadContextViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadContextViewModelHash();

  @override
  String toString() {
    return r'threadContextViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ThreadContextViewModel create() => ThreadContextViewModel();

  @override
  bool operator ==(Object other) {
    return other is ThreadContextViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadContextViewModelHash() =>
    r'da487962982a47cec070678fac882b05c3c7082e';

final class ThreadContextViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ThreadContextViewModel,
          AsyncValue<ThreadContextViewState>,
          ThreadContextViewState,
          FutureOr<ThreadContextViewState>,
          String
        > {
  ThreadContextViewModelFamily._()
    : super(
        retry: null,
        name: r'threadContextViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThreadContextViewModelProvider call(String threadId) =>
      ThreadContextViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadContextViewModelProvider';
}

abstract class _$ThreadContextViewModel
    extends $AsyncNotifier<ThreadContextViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<ThreadContextViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ThreadContextViewState>, ThreadContextViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ThreadContextViewState>,
                ThreadContextViewState
              >,
              AsyncValue<ThreadContextViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
