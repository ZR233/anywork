// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_status_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ThreadStatusViewModel)
final threadStatusViewModelProvider = ThreadStatusViewModelFamily._();

final class ThreadStatusViewModelProvider
    extends
        $AsyncNotifierProvider<ThreadStatusViewModel, ThreadStatusViewState> {
  ThreadStatusViewModelProvider._({
    required ThreadStatusViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadStatusViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadStatusViewModelHash();

  @override
  String toString() {
    return r'threadStatusViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ThreadStatusViewModel create() => ThreadStatusViewModel();

  @override
  bool operator ==(Object other) {
    return other is ThreadStatusViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadStatusViewModelHash() =>
    r'3bdac486f09b3765c15b981373afa279afdadd2d';

final class ThreadStatusViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ThreadStatusViewModel,
          AsyncValue<ThreadStatusViewState>,
          ThreadStatusViewState,
          FutureOr<ThreadStatusViewState>,
          String
        > {
  ThreadStatusViewModelFamily._()
    : super(
        retry: null,
        name: r'threadStatusViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThreadStatusViewModelProvider call(String threadId) =>
      ThreadStatusViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadStatusViewModelProvider';
}

abstract class _$ThreadStatusViewModel
    extends $AsyncNotifier<ThreadStatusViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<ThreadStatusViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ThreadStatusViewState>, ThreadStatusViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ThreadStatusViewState>,
                ThreadStatusViewState
              >,
              AsyncValue<ThreadStatusViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
