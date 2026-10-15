import 'package:anywork_client/studio_client.dart' show AttachmentDraftBoard;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'client_provider.dart';
import 'observe_client.dart';

export 'package:anywork_client/models.dart' show AttachmentDraftBoard;

part 'attachment_drafts.g.dart';

/// This observer borrows the Client's logical draft across routes.
@riverpod
AttachmentDraftBoard attachmentDrafts(Ref ref) {
  final source = ref.read(anyworkClientProvider).attachments.source;
  return observeClient(ref, source, (_) => ref.invalidateSelf());
}
