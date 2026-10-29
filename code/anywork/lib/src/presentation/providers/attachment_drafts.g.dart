// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'attachment_drafts.dart';

// **************************************************************************
// RiverpodGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint, type=warning
/// This observer borrows the Client's logical draft across routes.

@ProviderFor(attachmentDrafts)
final attachmentDraftsProvider = AttachmentDraftsProvider._();

/// This observer borrows the Client's logical draft across routes.

final class AttachmentDraftsProvider
    extends
        $FunctionalProvider<
          AttachmentDraftBoard,
          AttachmentDraftBoard,
          AttachmentDraftBoard
        >
    with $Provider<AttachmentDraftBoard> {
  /// This observer borrows the Client's logical draft across routes.
  AttachmentDraftsProvider._()
    : super(
        from: null,
        argument: null,
        retry: null,
        name: r'attachmentDraftsProvider',
        isAutoDispose: true,
        dependencies: null,
        $allTransitiveDependencies: null,
      );

  @override
  String debugGetCreateSourceHash() => _$attachmentDraftsHash();

  @$internal
  @override
  $ProviderElement<AttachmentDraftBoard> $createElement(
    $ProviderPointer pointer,
  ) => $ProviderElement(pointer);

  @override
  AttachmentDraftBoard create(Ref ref) {
    return attachmentDrafts(ref);
  }

  /// {@macro riverpod.override_with_value}
  Override overrideWithValue(AttachmentDraftBoard value) {
    return $ProviderOverride(
      origin: this,
      providerOverride: $SyncValueProvider<AttachmentDraftBoard>(value),
    );
  }
}

String _$attachmentDraftsHash() => r'5ff43a6d134b7adffc576c30d4fe8cde0a236f8e';
