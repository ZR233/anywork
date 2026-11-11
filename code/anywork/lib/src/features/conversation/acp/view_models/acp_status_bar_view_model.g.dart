// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_status_bar_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(acpStatusBarViewModel)
final acpStatusBarViewModelProvider = AcpStatusBarViewModelFamily._();

final class AcpStatusBarViewModelProvider
    extends
        $FunctionalProvider<
          AcpStatusBarViewState,
          AcpStatusBarViewState,
          AcpStatusBarViewState
        >
    with $Provider<AcpStatusBarViewState> {
  AcpStatusBarViewModelProvider._({
    required AcpStatusBarViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpStatusBarViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpStatusBarViewModelHash();

  @override
  String toString() {
    return r'acpStatusBarViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpStatusBarViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpStatusBarViewState create(Ref ref) {
    final argument = this.argument as String;
    return acpStatusBarViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpStatusBarViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpStatusBarViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpStatusBarViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpStatusBarViewModelHash() =>
    r'42590cf237f5e29f0ed421381c25c8ad10b086ee';

final class AcpStatusBarViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpStatusBarViewState, String> {
  AcpStatusBarViewModelFamily._()
    : super(
        retry: null,
        name: r'acpStatusBarViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpStatusBarViewModelProvider call(String threadId) =>
      AcpStatusBarViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpStatusBarViewModelProvider';
}
