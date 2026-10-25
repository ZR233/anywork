// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_model_limits_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AccountModelLimitsViewModel)
final accountModelLimitsViewModelProvider =
    AccountModelLimitsViewModelFamily._();

final class AccountModelLimitsViewModelProvider
    extends
        $AsyncNotifierProvider<
          AccountModelLimitsViewModel,
          AccountModelLimitsViewState
        > {
  AccountModelLimitsViewModelProvider._({
    required AccountModelLimitsViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'accountModelLimitsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountModelLimitsViewModelHash();

  @override
  String toString() {
    return r'accountModelLimitsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountModelLimitsViewModel create() => AccountModelLimitsViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountModelLimitsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountModelLimitsViewModelHash() =>
    r'67beaeb50760f49b4de3fcd37c42074648062eab';

final class AccountModelLimitsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountModelLimitsViewModel,
          AsyncValue<AccountModelLimitsViewState>,
          AccountModelLimitsViewState,
          FutureOr<AccountModelLimitsViewState>,
          String
        > {
  AccountModelLimitsViewModelFamily._()
    : super(
        retry: null,
        name: r'accountModelLimitsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AccountModelLimitsViewModelProvider call(String accountId) =>
      AccountModelLimitsViewModelProvider._(argument: accountId, from: this);

  @override
  String toString() => r'accountModelLimitsViewModelProvider';
}

abstract class _$AccountModelLimitsViewModel
    extends $AsyncNotifier<AccountModelLimitsViewState> {
  late final _$args = ref.$arg as String;
  String get accountId => _$args;

  FutureOr<AccountModelLimitsViewState> build(String accountId);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AccountModelLimitsViewState>,
              AccountModelLimitsViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountModelLimitsViewState>,
                AccountModelLimitsViewState
              >,
              AsyncValue<AccountModelLimitsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
