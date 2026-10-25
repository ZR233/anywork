// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'statistics_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Owns statistics filters and their immutable presentation projection.

@ProviderFor(StatisticsViewModel)
final statisticsViewModelProvider = StatisticsViewModelProvider._();

/// Owns statistics filters and their immutable presentation projection.
final class StatisticsViewModelProvider
    extends $NotifierProvider<StatisticsViewModel, StatisticsViewState> {
  /// Owns statistics filters and their immutable presentation projection.
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

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StatisticsViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StatisticsViewState>(value),
    );
  }
}

String _$statisticsViewModelHash() =>
    r'94d635a90ee6da8ce3ccc2f74b2ad0d44e6cef3b';

/// Owns statistics filters and their immutable presentation projection.

abstract class _$StatisticsViewModel extends $Notifier<StatisticsViewState> {
  StatisticsViewState build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StatisticsViewState, StatisticsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StatisticsViewState, StatisticsViewState>,
              StatisticsViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
