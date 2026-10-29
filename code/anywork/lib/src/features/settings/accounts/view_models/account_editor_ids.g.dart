// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_editor_ids.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning

@ProviderFor(accountEditorIds)
final accountEditorIdsProvider = AccountEditorIdsProvider._();

final class AccountEditorIdsProvider
    extends
        $FunctionalProvider<
          AccountEditorIds,
          AccountEditorIds,
          AccountEditorIds
        >
    with $Provider<AccountEditorIds> {
  AccountEditorIdsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'accountEditorIdsProvider',
        isAutoDispose: false,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$accountEditorIdsHash();

  @$internal
  @override
  $ProviderElement<AccountEditorIds> $createElement($ProviderPointer pointer) =>
      $ProviderElement(pointer);

  @override
  AccountEditorIds create(Ref ref) {
    return accountEditorIds(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AccountEditorIds value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AccountEditorIds>(value),
    );
  }
}

String _$accountEditorIdsHash() => r'b6606eac9ff7cd996c936c1706f303725e02e0f4';
