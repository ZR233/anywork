// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shutdown_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Presentation only; the coordinator owns all deadlines, futures and cleanup.

@ProviderFor(ShutdownViewModel)
final shutdownViewModelProvider = ShutdownViewModelProvider._();

/// Presentation only; the coordinator owns all deadlines, futures and cleanup.
final class ShutdownViewModelProvider
    extends $AsyncNotifierProvider<ShutdownViewModel, ApplicationExitState> {
  /// Presentation only; the coordinator owns all deadlines, futures and cleanup.
  ShutdownViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shutdownViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shutdownViewModelHash();

  @$internal
  @override
  ShutdownViewModel create() => ShutdownViewModel();
}

String _$shutdownViewModelHash() => r'0e25c14926799c255943155f5c23202758dcf62a';

/// Presentation only; the coordinator owns all deadlines, futures and cleanup.

abstract class _$ShutdownViewModel
    extends $AsyncNotifier<ApplicationExitState> {
  FutureOr<ApplicationExitState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<ApplicationExitState>, ApplicationExitState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<ApplicationExitState>,
                ApplicationExitState
              >,
              AsyncValue<ApplicationExitState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
