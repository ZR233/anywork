// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_editor_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One form owns raw input, baseline, dirty and revision. No Widget controller
/// or canonical mirror is used to decide whether a save completed this draft.

@ProviderFor(AccountEditorViewModel)
final accountEditorViewModelProvider = AccountEditorViewModelFamily._();

/// One form owns raw input, baseline, dirty and revision. No Widget controller
/// or canonical mirror is used to decide whether a save completed this draft.
final class AccountEditorViewModelProvider
    extends
        $AsyncNotifierProvider<AccountEditorViewModel, AccountEditorViewState> {
  /// One form owns raw input, baseline, dirty and revision. No Widget controller
  /// or canonical mirror is used to decide whether a save completed this draft.
  AccountEditorViewModelProvider._({
    required AccountEditorViewModelFamily super.from,
    required AccountEditorKey super.argument,
  }) : super(
         retry: null,
         name: r'accountEditorViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountEditorViewModelHash();

  @override
  String toString() {
    return r'accountEditorViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountEditorViewModel create() => AccountEditorViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountEditorViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountEditorViewModelHash() =>
    r'5ea06907199530c96c3a3c00b0df6518bd017678';

/// One form owns raw input, baseline, dirty and revision. No Widget controller
/// or canonical mirror is used to decide whether a save completed this draft.

final class AccountEditorViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountEditorViewModel,
          AsyncValue<AccountEditorViewState>,
          AccountEditorViewState,
          FutureOr<AccountEditorViewState>,
          AccountEditorKey
        > {
  AccountEditorViewModelFamily._()
    : super(
        retry: null,
        name: r'accountEditorViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One form owns raw input, baseline, dirty and revision. No Widget controller
  /// or canonical mirror is used to decide whether a save completed this draft.

  AccountEditorViewModelProvider call(AccountEditorKey key) =>
      AccountEditorViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'accountEditorViewModelProvider';
}

/// One form owns raw input, baseline, dirty and revision. No Widget controller
/// or canonical mirror is used to decide whether a save completed this draft.

abstract class _$AccountEditorViewModel
    extends $AsyncNotifier<AccountEditorViewState> {
  late final _$args = ref.$arg as AccountEditorKey;
  AccountEditorKey get key => _$args;

  FutureOr<AccountEditorViewState> build(AccountEditorKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AccountEditorViewState>, AccountEditorViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountEditorViewState>,
                AccountEditorViewState
              >,
              AsyncValue<AccountEditorViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
