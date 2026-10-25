// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_model_details_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(AccountModelDetailsViewModel)
final accountModelDetailsViewModelProvider =
    AccountModelDetailsViewModelFamily._();

final class AccountModelDetailsViewModelProvider
    extends
        $AsyncNotifierProvider<
          AccountModelDetailsViewModel,
          AccountModelDetailsViewState
        > {
  AccountModelDetailsViewModelProvider._({
    required AccountModelDetailsViewModelFamily super.from,
    required AccountModelDetailsEntry super.argument,
  }) : super(
         retry: null,
         name: r'accountModelDetailsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountModelDetailsViewModelHash();

  @override
  String toString() {
    return r'accountModelDetailsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountModelDetailsViewModel create() => AccountModelDetailsViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountModelDetailsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountModelDetailsViewModelHash() =>
    r'6f770c2ff037208ce062a542515a52ad5bb674fd';

final class AccountModelDetailsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountModelDetailsViewModel,
          AsyncValue<AccountModelDetailsViewState>,
          AccountModelDetailsViewState,
          FutureOr<AccountModelDetailsViewState>,
          AccountModelDetailsEntry
        > {
  AccountModelDetailsViewModelFamily._()
    : super(
        retry: null,
        name: r'accountModelDetailsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  AccountModelDetailsViewModelProvider call(AccountModelDetailsEntry entry) =>
      AccountModelDetailsViewModelProvider._(argument: entry, from: this);

  @override
  String toString() => r'accountModelDetailsViewModelProvider';
}

abstract class _$AccountModelDetailsViewModel
    extends $AsyncNotifier<AccountModelDetailsViewState> {
  late final _$args = ref.$arg as AccountModelDetailsEntry;
  AccountModelDetailsEntry get entry => _$args;

  FutureOr<AccountModelDetailsViewState> build(AccountModelDetailsEntry entry);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AccountModelDetailsViewState>,
              AccountModelDetailsViewState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountModelDetailsViewState>,
                AccountModelDetailsViewState
              >,
              AsyncValue<AccountModelDetailsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
