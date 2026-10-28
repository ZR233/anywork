// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'composer_draft_controller.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// This observer borrows the Client's logical draft across routes.

@ProviderFor(composerDraftController)
final composerDraftControllerProvider = ComposerDraftControllerFamily._();

/// This observer borrows the Client's logical draft across routes.

final class ComposerDraftControllerProvider
    extends
        $FunctionalProvider<
          ComposerThreadState,
          ComposerThreadState,
          ComposerThreadState
        >
    with $Provider<ComposerThreadState> {
  /// This observer borrows the Client's logical draft across routes.
  ComposerDraftControllerProvider._({
    required ComposerDraftControllerFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'composerDraftControllerProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$composerDraftControllerHash();

  @override
  String toString() {
    return r'composerDraftControllerProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ComposerThreadState> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ComposerThreadState create(Ref ref) {
    final argument = this.argument as String;
    return composerDraftController(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ComposerThreadState value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ComposerThreadState>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ComposerDraftControllerProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$composerDraftControllerHash() =>
    r'da63615e8f08463eb258ee5403260c748fe74aad';

/// This observer borrows the Client's logical draft across routes.

final class ComposerDraftControllerFamily extends $Family
    with $FunctionalFamilyOverride<ComposerThreadState, String> {
  ComposerDraftControllerFamily._()
    : super(
        retry: null,
        name: r'composerDraftControllerProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// This observer borrows the Client's logical draft across routes.

  ComposerDraftControllerProvider call(String threadId) =>
      ComposerDraftControllerProvider._(argument: threadId, from: this);

  @override
  String toString() => r'composerDraftControllerProvider';
}
