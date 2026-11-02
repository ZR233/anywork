// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accounts_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Summary-only list and actions. Page location and finite editor resources
/// belong to the Router and editor session, never this owner.

@ProviderFor(AccountsViewModel)
final accountsViewModelProvider = AccountsViewModelProvider._();

/// Summary-only list and actions. Page location and finite editor resources
/// belong to the Router and editor session, never this owner.
final class AccountsViewModelProvider
    extends $AsyncNotifierProvider<AccountsViewModel, AccountsViewState> {
  /// Summary-only list and actions. Page location and finite editor resources
  /// belong to the Router and editor session, never this owner.
  AccountsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountsViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountsViewModelHash();

  @$internal
  @override
  AccountsViewModel create() => AccountsViewModel();
}

String _$accountsViewModelHash() => r'1d3e5f5f570762100eca003957033cbcae4da9db';

/// Summary-only list and actions. Page location and finite editor resources
/// belong to the Router and editor session, never this owner.

abstract class _$AccountsViewModel extends $AsyncNotifier<AccountsViewState> {
  FutureOr<AccountsViewState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<AccountsViewState>, AccountsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<AccountsViewState>, AccountsViewState>,
              AsyncValue<AccountsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
