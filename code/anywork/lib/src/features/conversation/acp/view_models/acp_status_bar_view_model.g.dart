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
    r'08f5459ac73dc90f69fdfd8c10e048db08e1bd18';

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

@ProviderFor(acpContextUsageViewModel)
final acpContextUsageViewModelProvider = AcpContextUsageViewModelFamily._();

final class AcpContextUsageViewModelProvider
    extends
        $FunctionalProvider<
          AcpContextUsageViewState?,
          AcpContextUsageViewState?,
          AcpContextUsageViewState?
        >
    with $Provider<AcpContextUsageViewState?> {
  AcpContextUsageViewModelProvider._({
    required AcpContextUsageViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpContextUsageViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpContextUsageViewModelHash();

  @override
  String toString() {
    return r'acpContextUsageViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpContextUsageViewState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpContextUsageViewState? create(Ref ref) {
    final argument = this.argument as String;
    return acpContextUsageViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpContextUsageViewState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpContextUsageViewState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpContextUsageViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpContextUsageViewModelHash() =>
    r'b31bad67a23fc443fbcc104b7092d4fd230f1b98';

final class AcpContextUsageViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpContextUsageViewState?, String> {
  AcpContextUsageViewModelFamily._()
    : super(
        retry: null,
        name: r'acpContextUsageViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpContextUsageViewModelProvider call(String threadId) =>
      AcpContextUsageViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpContextUsageViewModelProvider';
}

@ProviderFor(acpCostViewModel)
final acpCostViewModelProvider = AcpCostViewModelFamily._();

final class AcpCostViewModelProvider
    extends
        $FunctionalProvider<
          AcpCostViewState?,
          AcpCostViewState?,
          AcpCostViewState?
        >
    with $Provider<AcpCostViewState?> {
  AcpCostViewModelProvider._({
    required AcpCostViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpCostViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpCostViewModelHash();

  @override
  String toString() {
    return r'acpCostViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpCostViewState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpCostViewState? create(Ref ref) {
    final argument = this.argument as String;
    return acpCostViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpCostViewState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpCostViewState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpCostViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpCostViewModelHash() => r'd0991d3493afb8df43e4e49c5c53705901e8edb7';

final class AcpCostViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpCostViewState?, String> {
  AcpCostViewModelFamily._()
    : super(
        retry: null,
        name: r'acpCostViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpCostViewModelProvider call(String threadId) =>
      AcpCostViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpCostViewModelProvider';
}
