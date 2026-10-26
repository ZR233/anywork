// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statistics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns the statistics page's visibility demand, its observation and its
/// filters. Every collection, page and read identity stays inside the
/// Repository; this ViewModel never pages, merges or fabricates a snapshot.

@ProviderFor(StatisticsViewModel)
final statisticsViewModelProvider = StatisticsViewModelProvider._();

/// Owns the statistics page's visibility demand, its observation and its
/// filters. Every collection, page and read identity stays inside the
/// Repository; this ViewModel never pages, merges or fabricates a snapshot.
final class StatisticsViewModelProvider
    extends $AsyncNotifierProvider<StatisticsViewModel, StatisticsViewState> {
  /// Owns the statistics page's visibility demand, its observation and its
  /// filters. Every collection, page and read identity stays inside the
  /// Repository; this ViewModel never pages, merges or fabricates a snapshot.
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
    r'f2ffc031106ec6e44c365e33864c2f0395747162';

/// Owns the statistics page's visibility demand, its observation and its
/// filters. Every collection, page and read identity stays inside the
/// Repository; this ViewModel never pages, merges or fabricates a snapshot.

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
