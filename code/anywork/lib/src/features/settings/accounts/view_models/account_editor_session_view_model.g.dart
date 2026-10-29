// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_editor_session_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// A finite locator for the current mounted entry's business resources.
/// Provider retention does not identify a mount or authorize an earlier owner.

@ProviderFor(AccountEditorSessionViewModel)
final accountEditorSessionViewModelProvider =
    AccountEditorSessionViewModelFamily._();

/// A finite locator for the current mounted entry's business resources.
/// Provider retention does not identify a mount or authorize an earlier owner.
final class AccountEditorSessionViewModelProvider
    extends
        $AsyncNotifierProvider<
          AccountEditorSessionViewModel,
          AccountEditorSessionState
        > {
  /// A finite locator for the current mounted entry's business resources.
  /// Provider retention does not identify a mount or authorize an earlier owner.
  AccountEditorSessionViewModelProvider._({
    required AccountEditorSessionViewModelFamily super.from,
    required AccountEditorEntryKey super.argument,
  }) : super(
         retry: null,
         name: r'accountEditorSessionViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountEditorSessionViewModelHash();

  @override
  String toString() {
    return r'accountEditorSessionViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountEditorSessionViewModel create() => AccountEditorSessionViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountEditorSessionViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountEditorSessionViewModelHash() =>
    r'd71a891f01f0559e679a49ca4f6571a571d4db9b';

/// A finite locator for the current mounted entry's business resources.
/// Provider retention does not identify a mount or authorize an earlier owner.

final class AccountEditorSessionViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountEditorSessionViewModel,
          AsyncValue<AccountEditorSessionState>,
          AccountEditorSessionState,
          FutureOr<AccountEditorSessionState>,
          AccountEditorEntryKey
        > {
  AccountEditorSessionViewModelFamily._()
    : super(
        retry: null,
        name: r'accountEditorSessionViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// A finite locator for the current mounted entry's business resources.
  /// Provider retention does not identify a mount or authorize an earlier owner.

  AccountEditorSessionViewModelProvider call(AccountEditorEntryKey entry) =>
      AccountEditorSessionViewModelProvider._(argument: entry, from: this);

  @override
  String toString() => r'accountEditorSessionViewModelProvider';
}

/// A finite locator for the current mounted entry's business resources.
/// Provider retention does not identify a mount or authorize an earlier owner.

abstract class _$AccountEditorSessionViewModel
    extends $AsyncNotifier<AccountEditorSessionState> {
  late final _$args = ref.$arg as AccountEditorEntryKey;
  AccountEditorEntryKey get entry => _$args;

  FutureOr<AccountEditorSessionState> build(AccountEditorEntryKey entry);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AccountEditorSessionState>,
              AccountEditorSessionState
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountEditorSessionState>,
                AccountEditorSessionState
              >,
              AsyncValue<AccountEditorSessionState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
