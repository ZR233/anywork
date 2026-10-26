// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'accounts_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AccountsViewModel)
final accountsViewModelProvider = AccountsViewModelProvider._();

final class AccountsViewModelProvider
    extends $AsyncNotifierProvider<AccountsViewModel, AccountsViewState> {
  AccountsViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountsViewModelProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountsViewModelHash();

  @$internal
  @override
  AccountsViewModel create() => AccountsViewModel();
}

String _$accountsViewModelHash() => r'f312d3b1d9e89942252a3e22efa3c5f26e063aa3';

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
