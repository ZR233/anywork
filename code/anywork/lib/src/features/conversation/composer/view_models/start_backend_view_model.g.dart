// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'start_backend_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(_startBackendAccountDemand)
final _startBackendAccountDemandProvider =
    _StartBackendAccountDemandProvider._();

final class _StartBackendAccountDemandProvider
    extends $FunctionalProvider<void, void, void>
    with $Provider<void> {
  _StartBackendAccountDemandProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'_startBackendAccountDemandProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$_startBackendAccountDemandHash();

  @$internal
  @override
  $ProviderElement<void> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  void create(Ref ref) {
    return _startBackendAccountDemand(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(void value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<void>(value),
    );
  }
}

String _$_startBackendAccountDemandHash() =>
    r'2c8179cf0a63bb011958db812e1a3e61d0ae0e50';

@ProviderFor(StartBackendViewModel)
final startBackendViewModelProvider = StartBackendViewModelFamily._();

final class StartBackendViewModelProvider
    extends $NotifierProvider<StartBackendViewModel, StartBackendViewState> {
  StartBackendViewModelProvider._({
    required StartBackendViewModelFamily super.from,
    required String? super.argument,
  }) : super(
         retry: null,
         name: r'startBackendViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$startBackendViewModelHash();

  @override
  String toString() {
    return r'startBackendViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  StartBackendViewModel create() => StartBackendViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(StartBackendViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<StartBackendViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is StartBackendViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$startBackendViewModelHash() =>
    r'6af8ba257f5c5d6be696b4ba6098ff0ab230c62d';

final class StartBackendViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          StartBackendViewModel,
          StartBackendViewState,
          StartBackendViewState,
          StartBackendViewState,
          String?
        > {
  StartBackendViewModelFamily._()
    : super(
        retry: null,
        name: r'startBackendViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  StartBackendViewModelProvider call(String? workspaceId) =>
      StartBackendViewModelProvider._(argument: workspaceId, from: this);

  @override
  String toString() => r'startBackendViewModelProvider';
}

abstract class _$StartBackendViewModel
    extends $Notifier<StartBackendViewState> {
  late final _$args = ref.$arg as String?;
  String? get workspaceId => _$args;

  StartBackendViewState build(String? workspaceId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref = this.ref as $Ref<StartBackendViewState, StartBackendViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<StartBackendViewState, StartBackendViewState>,
              StartBackendViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
