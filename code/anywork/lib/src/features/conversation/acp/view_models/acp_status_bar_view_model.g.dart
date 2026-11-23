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
    r'efe528d3ee4f302931ad1fed357e66f8d3b3ed4c';

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

String _$acpCostViewModelHash() => r'c95c3d5dab3d1275db017e09e044e761ba3d389a';

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

@ProviderFor(acpContextDetailViewModel)
final acpContextDetailViewModelProvider = AcpContextDetailViewModelFamily._();

final class AcpContextDetailViewModelProvider
    extends
        $FunctionalProvider<
          AcpContextDetailViewState,
          AcpContextDetailViewState,
          AcpContextDetailViewState
        >
    with $Provider<AcpContextDetailViewState> {
  AcpContextDetailViewModelProvider._({
    required AcpContextDetailViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpContextDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpContextDetailViewModelHash();

  @override
  String toString() {
    return r'acpContextDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpContextDetailViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpContextDetailViewState create(Ref ref) {
    final argument = this.argument as String;
    return acpContextDetailViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpContextDetailViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpContextDetailViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpContextDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpContextDetailViewModelHash() =>
    r'dd31a7fab423c2ff9bb001861dd5ce8c5a4b109a';

final class AcpContextDetailViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpContextDetailViewState, String> {
  AcpContextDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'acpContextDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpContextDetailViewModelProvider call(String threadId) =>
      AcpContextDetailViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpContextDetailViewModelProvider';
}

@ProviderFor(acpThroughputDetailViewModel)
final acpThroughputDetailViewModelProvider =
    AcpThroughputDetailViewModelFamily._();

final class AcpThroughputDetailViewModelProvider
    extends
        $FunctionalProvider<
          AcpThroughputDetailViewState,
          AcpThroughputDetailViewState,
          AcpThroughputDetailViewState
        >
    with $Provider<AcpThroughputDetailViewState> {
  AcpThroughputDetailViewModelProvider._({
    required AcpThroughputDetailViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpThroughputDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpThroughputDetailViewModelHash();

  @override
  String toString() {
    return r'acpThroughputDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpThroughputDetailViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpThroughputDetailViewState create(Ref ref) {
    final argument = this.argument as String;
    return acpThroughputDetailViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpThroughputDetailViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpThroughputDetailViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpThroughputDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpThroughputDetailViewModelHash() =>
    r'bca64c7dcf7ba1a4a2d02bfdfb7edc0f1c834415';

final class AcpThroughputDetailViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpThroughputDetailViewState, String> {
  AcpThroughputDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'acpThroughputDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpThroughputDetailViewModelProvider call(String threadId) =>
      AcpThroughputDetailViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpThroughputDetailViewModelProvider';
}

@ProviderFor(acpCostDetailViewModel)
final acpCostDetailViewModelProvider = AcpCostDetailViewModelFamily._();

final class AcpCostDetailViewModelProvider
    extends
        $FunctionalProvider<
          AcpCostDetailViewState?,
          AcpCostDetailViewState?,
          AcpCostDetailViewState?
        >
    with $Provider<AcpCostDetailViewState?> {
  AcpCostDetailViewModelProvider._({
    required AcpCostDetailViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpCostDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpCostDetailViewModelHash();

  @override
  String toString() {
    return r'acpCostDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpCostDetailViewState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpCostDetailViewState? create(Ref ref) {
    final argument = this.argument as String;
    return acpCostDetailViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpCostDetailViewState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpCostDetailViewState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpCostDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpCostDetailViewModelHash() =>
    r'c9d74eca73cae6975dac2ff5927c9d43042ea9be';

final class AcpCostDetailViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpCostDetailViewState?, String> {
  AcpCostDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'acpCostDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpCostDetailViewModelProvider call(String threadId) =>
      AcpCostDetailViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpCostDetailViewModelProvider';
}

@ProviderFor(acpSessionDetailViewModel)
final acpSessionDetailViewModelProvider = AcpSessionDetailViewModelFamily._();

final class AcpSessionDetailViewModelProvider
    extends
        $FunctionalProvider<
          AcpSessionDetailViewState,
          AcpSessionDetailViewState,
          AcpSessionDetailViewState
        >
    with $Provider<AcpSessionDetailViewState> {
  AcpSessionDetailViewModelProvider._({
    required AcpSessionDetailViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'acpSessionDetailViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpSessionDetailViewModelHash();

  @override
  String toString() {
    return r'acpSessionDetailViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<AcpSessionDetailViewState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AcpSessionDetailViewState create(Ref ref) {
    final argument = this.argument as String;
    return acpSessionDetailViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AcpSessionDetailViewState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AcpSessionDetailViewState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is AcpSessionDetailViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpSessionDetailViewModelHash() =>
    r'34523e0ddf345e3d63339ed10f82fadb024a2242';

final class AcpSessionDetailViewModelFamily extends $Family
    with $FunctionalFamilyOverride<AcpSessionDetailViewState, String> {
  AcpSessionDetailViewModelFamily._()
    : super(
        retry: null,
        name: r'acpSessionDetailViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AcpSessionDetailViewModelProvider call(String threadId) =>
      AcpSessionDetailViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'acpSessionDetailViewModelProvider';
}
