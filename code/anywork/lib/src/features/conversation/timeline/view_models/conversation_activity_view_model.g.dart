// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'conversation_activity_view_model.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// Observes only the activity component's current owner. Visibility and the
/// conversation reader remain owned by the committed page selection.

@ProviderFor(conversationActivityViewModel)
final conversationActivityViewModelProvider =
    ConversationActivityViewModelFamily._();

/// Observes only the activity component's current owner. Visibility and the
/// conversation reader remain owned by the committed page selection.

final class ConversationActivityViewModelProvider
    extends
        $FunctionalProvider<
          ConversationActivityState?,
          ConversationActivityState?,
          ConversationActivityState?
        >
    with $Provider<ConversationActivityState?> {
  /// Observes only the activity component's current owner. Visibility and the
  /// conversation reader remain owned by the committed page selection.
  ConversationActivityViewModelProvider._({
    required ConversationActivityViewModelFamily super.from,
    required String super.argument,
  }) : super(
         retry: null,
         name: r'conversationActivityViewModelProvider',
         isAutoDispose: true,
         dependencies: null,
         $allTransitiveDependencies: null,
       );

  @override
  String debugGetCreateSourceHash() => _$conversationActivityViewModelHash();

  @override
  String toString() {
    return r'conversationActivityViewModelProvider'
        ''
        '($argument)';
  }

  @$internal
  @override
  $ProviderElement<ConversationActivityState?> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  ConversationActivityState? create(Ref ref) {
    final argument = this.argument as String;
    return conversationActivityViewModel(ref, argument);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(ConversationActivityState? value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<ConversationActivityState?>(value),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ConversationActivityViewModelProvider &&
        other.argument == argument;
  }

  @override
  int get hashCode {
    return argument.hashCode;
  }
}

String _$conversationActivityViewModelHash() =>
    r'd4ca1ccf7e71703b708f67962495e40c5adb8a57';

/// Observes only the activity component's current owner. Visibility and the
/// conversation reader remain owned by the committed page selection.

final class ConversationActivityViewModelFamily extends $Family
    with $FunctionalFamilyOverride<ConversationActivityState?, String> {
  ConversationActivityViewModelFamily._()
    : super(
        retry: null,
        name: r'conversationActivityViewModelProvider',
        dependencies: null,
        $allTransitiveDependencies: null,
        isAutoDispose: true,
      );

  /// Observes only the activity component's current owner. Visibility and the
  /// conversation reader remain owned by the committed page selection.

  ConversationActivityViewModelProvider call(String threadId) =>
      ConversationActivityViewModelProvider._(argument: threadId, from: this);

  @override
  String toString() => r'conversationActivityViewModelProvider';
}
