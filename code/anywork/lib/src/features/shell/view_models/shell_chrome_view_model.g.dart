// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'shell_chrome_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Chrome owns only read demands. It cannot select/open a Thread, stop a Turn,
/// submit a draft, save preferences, or close an application-owned Session.

@ProviderFor(ShellChromeViewModel)
final shellChromeViewModelProvider = ShellChromeViewModelProvider._();

/// Chrome owns only read demands. It cannot select/open a Thread, stop a Turn,
/// submit a draft, save preferences, or close an application-owned Session.
final class ShellChromeViewModelProvider
    extends $AsyncNotifierProvider<ShellChromeViewModel, ShellChromeState> {
  /// Chrome owns only read demands. It cannot select/open a Thread, stop a Turn,
  /// submit a draft, save preferences, or close an application-owned Session.
  ShellChromeViewModelProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'shellChromeViewModelProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$shellChromeViewModelHash();

  @$internal
  @override
  ShellChromeViewModel create() => ShellChromeViewModel();
}

String _$shellChromeViewModelHash() =>
    r'7d808d825ed70b19cce5b3616f7e3eba0191a52d';

/// Chrome owns only read demands. It cannot select/open a Thread, stop a Turn,
/// submit a draft, save preferences, or close an application-owned Session.

abstract class _$ShellChromeViewModel extends $AsyncNotifier<ShellChromeState> {
  FutureOr<ShellChromeState> build();
  @$mustCallSuper
  @override
  WhenComplete runBuild() {
    final ref =
        this.ref as $Ref<AsyncValue<ShellChromeState>, ShellChromeState>;
    final element =
        ref.element
            as $ClassProviderElement<
              AnyNotifier<AsyncValue<ShellChromeState>, ShellChromeState>,
              AsyncValue<ShellChromeState>,
              Object?,
              Object?
            >;
    return element.handleCreate(ref, build);
  }
}
