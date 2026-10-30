// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_details_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AccountDetailsViewModel)
final accountDetailsViewModelProvider = AccountDetailsViewModelFamily._();

final class AccountDetailsViewModelProvider
    extends
        $AsyncNotifierProvider<
          AccountDetailsViewModel,
          AccountDetailsViewState
        > {
  AccountDetailsViewModelProvider._({
    required AccountDetailsViewModelFamily super.from,
    required AccountDisplayKey super.argument,
  }) : super(
         retry: null,
         name: r'accountDetailsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountDetailsViewModelHash();

  @override
  String toString() {
    return r'accountDetailsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountDetailsViewModel create() => AccountDetailsViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountDetailsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountDetailsViewModelHash() =>
    r'6db26aa97403c5753631d8e2f511f49905cdd224';

final class AccountDetailsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountDetailsViewModel,
          AsyncValue<AccountDetailsViewState>,
          AccountDetailsViewState,
          FutureOr<AccountDetailsViewState>,
          AccountDisplayKey
        > {
  AccountDetailsViewModelFamily._()
    : super(
        retry: null,
        name: r'accountDetailsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AccountDetailsViewModelProvider call(AccountDisplayKey key) =>
      AccountDetailsViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'accountDetailsViewModelProvider';
}

abstract class _$AccountDetailsViewModel
    extends $AsyncNotifier<AccountDetailsViewState> {
  late final _$args = ref.$arg as AccountDisplayKey;
  AccountDisplayKey get key => _$args;

  FutureOr<AccountDetailsViewState> build(AccountDisplayKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AccountDetailsViewState>,
              AccountDetailsViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountDetailsViewState>,
                AccountDetailsViewState
              >,
              AsyncValue<AccountDetailsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
