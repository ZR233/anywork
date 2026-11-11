// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_permission_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AcpPermissionViewModel)
final acpPermissionViewModelProvider = AcpPermissionViewModelFamily._();

final class AcpPermissionViewModelProvider
    extends
        $NotifierProvider<AcpPermissionViewModel, AcpPermissionDockViewState> {
  AcpPermissionViewModelProvider._({
    required AcpPermissionViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpPermissionViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpPermissionViewModelHash();

  @override
  String toString() {
    return r'acpPermissionViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpPermissionViewModel create() => AcpPermissionViewModel();

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpPermissionDockViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpPermissionDockViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpPermissionViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpPermissionViewModelHash() =>
    r'9a1bea77c79eec1b50f332e892bb55079a88da87';

final class AcpPermissionViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpPermissionViewModel,
          AcpPermissionDockViewState,
          AcpPermissionDockViewState,
          AcpPermissionDockViewState,
          String
        > {
  AcpPermissionViewModelFamily._()
    : super(
        retry: null,
        name: r'acpPermissionViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpPermissionViewModelProvider call(String threadId) =>
      AcpPermissionViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpPermissionViewModelProvider';
}

abstract class _$AcpPermissionViewModel
    extends $Notifier<AcpPermissionDockViewState> {
  late final _$args = ref.$arg as String;
  String get threadId => _$args;

  AcpPermissionDockViewState build(String threadId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AcpPermissionDockViewState, AcpPermissionDockViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AcpPermissionDockViewState,
                AcpPermissionDockViewState
              >,
              AcpPermissionDockViewState,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
