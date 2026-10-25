// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statistics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(StatisticsViewModel)
final statisticsViewModelProvider = StatisticsViewModelProvider._();

final class StatisticsViewModelProvider
    extends $AsyncNotifierProvider<StatisticsViewModel, StatisticsViewState> {
  StatisticsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'statisticsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$statisticsViewModelHash();

  @$internal
  @override
  StatisticsViewModel create() => StatisticsViewModel();
}

String _$statisticsViewModelHash() =>
    r'2a93f074087bb49e637b0c19b3e5633c92033740';

abstract class _$StatisticsViewModel
    extends $AsyncNotifier<StatisticsViewState> {
  FutureOr<StatisticsViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<StatisticsViewState>, StatisticsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<StatisticsViewState>, StatisticsViewState>,
              AsyncValue<StatisticsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
