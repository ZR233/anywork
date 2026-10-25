// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'thread_metrics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(ThreadMetricsViewModel)
final threadMetricsViewModelProvider = ThreadMetricsViewModelFamily._();

final class ThreadMetricsViewModelProvider
    extends
        $AsyncNotifierProvider<ThreadMetricsViewModel, ThreadMetricsViewState> {
  ThreadMetricsViewModelProvider._({
    required ThreadMetricsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'threadMetricsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$threadMetricsViewModelHash();

  @override
  String toString() {
    return r'threadMetricsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  ThreadMetricsViewModel create() => ThreadMetricsViewModel();

  @override
  bool operator ==(Object other) {
    return other is ThreadMetricsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$threadMetricsViewModelHash() =>
    r'ab551b07bb451baae23e9479a0fb874bcc9934a1';

final class ThreadMetricsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          ThreadMetricsViewModel,
          AsyncValue<ThreadMetricsViewState>,
          ThreadMetricsViewState,
          FutureOr<ThreadMetricsViewState>,
          String
        > {
  ThreadMetricsViewModelFamily._()
    : super(
        retry: null,
        name: r'threadMetricsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  ThreadMetricsViewModelProvider call(String threadId) =>
      ThreadMetricsViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'threadMetricsViewModelProvider';
}

abstract class _$ThreadMetricsViewModel
    extends $AsyncNotifier<ThreadMetricsViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  FutureOr<ThreadMetricsViewState> build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ThreadMetricsViewState>, ThreadMetricsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ThreadMetricsViewState>,
                ThreadMetricsViewState
              >,
              AsyncValue<ThreadMetricsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
