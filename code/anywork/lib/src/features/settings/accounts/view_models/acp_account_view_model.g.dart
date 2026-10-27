// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acp_account_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// ACP display/intent ownership. It does not own configuration or synthesize
/// authentication/install success. Start and cancel have independent lanes.

@ProviderFor(AcpAccountViewModel)
final acpAccountViewModelProvider = AcpAccountViewModelFamily._();

/// ACP display/intent ownership. It does not own configuration or synthesize
/// authentication/install success. Start and cancel have independent lanes.
final class AcpAccountViewModelProvider
    extends $AsyncNotifierProvider<AcpAccountViewModel, AccountAcpViewState> {
  /// ACP display/intent ownership. It does not own configuration or synthesize
  /// authentication/install success. Start and cancel have independent lanes.
  AcpAccountViewModelProvider._({
    required AcpAccountViewModelFamily super.from,
    required AccountAcpKey super.argument,
  }) : super(
         retry: null,
         name: r'acpAccountViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$acpAccountViewModelHash();

  @override
  String toString() {
    return r'acpAccountViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AcpAccountViewModel create() => AcpAccountViewModel();

  @override
  bool operator ==(Object other) {
    return other is AcpAccountViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$acpAccountViewModelHash() =>
    r'6ab58b9abfd9d428fdd806de8c4ca779cfc082ad';

/// ACP display/intent ownership. It does not own configuration or synthesize
/// authentication/install success. Start and cancel have independent lanes.

final class AcpAccountViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AcpAccountViewModel,
          AsyncValue<AccountAcpViewState>,
          AccountAcpViewState,
          FutureOr<AccountAcpViewState>,
          AccountAcpKey
        > {
  AcpAccountViewModelFamily._()
    : super(
        retry: null,
        name: r'acpAccountViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// ACP display/intent ownership. It does not own configuration or synthesize
  /// authentication/install success. Start and cancel have independent lanes.

  AcpAccountViewModelProvider call(AccountAcpKey key) =>
      AcpAccountViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'acpAccountViewModelProvider';
}

/// ACP display/intent ownership. It does not own configuration or synthesize
/// authentication/install success. Start and cancel have independent lanes.

abstract class _$AcpAccountViewModel
    extends $AsyncNotifier<AccountAcpViewState> {
  late final _$args = ref.$arg as AccountAcpKey;
  AccountAcpKey get key => _$args;

  FutureOr<AccountAcpViewState> build(AccountAcpKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AccountAcpViewState>, AccountAcpViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AccountAcpViewState>, AccountAcpViewState>,
              AsyncValue<AccountAcpViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
