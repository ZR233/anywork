import 'dart:convert';

import 'package:anywork_client/conversation.dart';

/// A Main card's complete immutable value. Members belong to an independent
/// Run reader, never to this value or a second collection of history.
final class CompletionRunPresentation {
  const CompletionRunPresentation({
    required this.messageId,
    required this.representative,
    required this.reference,
  });

  final String messageId;
  final CompletedEntry representative;
  final CompletionRunRef reference;

  static CompletionRunPresentation fromEntry(CompletedEntry entry) {
    final run = entry.run;
    final payload = entry.atom.payload;
    if (run == null || payload is! DeferredPayload) {
      throw const ConversationContinuityError(
        'A folded work representative requires a Run and deferred payload',
      );
    }
    final databaseId = payload.reference.databaseId;
    if (databaseId.isEmpty) {
      throw const ConversationContinuityError('Missing completion database');
    }
    return CompletionRunPresentation(
      messageId: jsonEncode(['completion-run', databaseId, run.startSeq]),
      representative: entry,
      reference: CompletionRunRef(
        databaseId: databaseId,
        indexVersion: completedReadIndexVersion,
        startSeq: run.startSeq,
      ),
    );
  }
}

const completionRunPresentationKey = 'completionRunPresentation';
