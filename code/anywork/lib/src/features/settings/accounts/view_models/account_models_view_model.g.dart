// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_models_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Model controls are narrow intents, never part of an account card save.

@ProviderFor(AccountModelsViewModel)
final accountModelsViewModelProvider = AccountModelsViewModelFamily._();

/// Model controls are narrow intents, never part of an account card save.
final class AccountModelsViewModelProvider
    extends
        $AsyncNotifierProvider<AccountModelsViewModel, AccountModelsViewState> {
  /// Model controls are narrow intents, never part of an account card save.
  AccountModelsViewModelProvider._({
    required AccountModelsViewModelFamily super.from,
    required AccountDisplayKey super.argument,
  }) : super(
         retry: null,
         name: r'accountModelsViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountModelsViewModelHash();

  @override
  String toString() {
    return r'accountModelsViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountModelsViewModel create() => AccountModelsViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountModelsViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountModelsViewModelHash() =>
    r'8a700f555166aa4b35bab576c9cf5e50cccbf7a3';

/// Model controls are narrow intents, never part of an account card save.

final class AccountModelsViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountModelsViewModel,
          AsyncValue<AccountModelsViewState>,
          AccountModelsViewState,
          FutureOr<AccountModelsViewState>,
          AccountDisplayKey
        > {
  AccountModelsViewModelFamily._()
    : super(
        retry: null,
        name: r'accountModelsViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Model controls are narrow intents, never part of an account card save.

  AccountModelsViewModelProvider call(AccountDisplayKey key) =>
      AccountModelsViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'accountModelsViewModelProvider';
}

/// Model controls are narrow intents, never part of an account card save.

abstract class _$AccountModelsViewModel
    extends $AsyncNotifier<AccountModelsViewState> {
  late final _$args = ref.$arg as AccountDisplayKey;
  AccountDisplayKey get key => _$args;

  FutureOr<AccountModelsViewState> build(AccountDisplayKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<AsyncValue<AccountModelsViewState>, AccountModelsViewState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountModelsViewState>,
                AccountModelsViewState
              >,
              AsyncValue<AccountModelsViewState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
