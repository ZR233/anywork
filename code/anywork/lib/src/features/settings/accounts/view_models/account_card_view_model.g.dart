// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_card_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// One list member's read-only projection and refresh intent. Search never owns
/// this resource; the visible list retains it independently of row widgets.

@ProviderFor(AccountCardViewModel)
final accountCardViewModelProvider = AccountCardViewModelFamily._();

/// One list member's read-only projection and refresh intent. Search never owns
/// this resource; the visible list retains it independently of row widgets.
final class AccountCardViewModelProvider
    extends
        $AsyncNotifierProvider<AccountCardViewModel, AccountRowPresentation?> {
  /// One list member's read-only projection and refresh intent. Search never owns
  /// this resource; the visible list retains it independently of row widgets.
  AccountCardViewModelProvider._({
    required AccountCardViewModelFamily super.from,
    required AccountDisplayKey super.argument,
  }) : super(
         retry: null,
         name: r'accountCardViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$accountCardViewModelHash();

  @override
  String toString() {
    return r'accountCardViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  AccountCardViewModel create() => AccountCardViewModel();

  @override
  bool operator ==(Object other) {
    return other is AccountCardViewModelProvider && other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$accountCardViewModelHash() =>
    r'3f825e9feb3897daf89c671dcef7f123ecc9c01c';

/// One list member's read-only projection and refresh intent. Search never owns
/// this resource; the visible list retains it independently of row widgets.

final class AccountCardViewModelFamily extends $Family
    with
        $ClassFamilyOverride<
          AccountCardViewModel,
          AsyncValue<AccountRowPresentation?>,
          AccountRowPresentation?,
          FutureOr<AccountRowPresentation?>,
          AccountDisplayKey
        > {
  AccountCardViewModelFamily._()
    : super(
        retry: null,
        name: r'accountCardViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// One list member's read-only projection and refresh intent. Search never owns
  /// this resource; the visible list retains it independently of row widgets.

  AccountCardViewModelProvider call(AccountDisplayKey key) =>
      AccountCardViewModelProvider._(argument: key, from: this);

  @override
  String toString() => r'accountCardViewModelProvider';
}

/// One list member's read-only projection and refresh intent. Search never owns
/// this resource; the visible list retains it independently of row widgets.

abstract class _$AccountCardViewModel
    extends $AsyncNotifier<AccountRowPresentation?> {
  late final _$args = ref.$arg as AccountDisplayKey;
  AccountDisplayKey get key => _$args;

  FutureOr<AccountRowPresentation?> build(AccountDisplayKey key);
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref
            as $Ref<
              AsyncValue<AccountRowPresentation?>,
              AccountRowPresentation?
            >;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<
                AsyncValue<AccountRowPresentation?>,
                AccountRowPresentation?
              >,
              AsyncValue<AccountRowPresentation?>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, () => build(_$args));
  }
}
