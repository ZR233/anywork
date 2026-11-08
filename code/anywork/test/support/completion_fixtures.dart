import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ThreadTextChannel;

/// Explicit producer fixtures. This helper does not classify atoms or combine
/// records; every caller chooses its class, start and ordinal.
CompletedEntry completionEntry(
  String id,
  int seq, {
  int? start,
  int ordinal = 1,
  MainPresentation presentation = MainPresentation.foregroundWork,
  String databaseId = 'database',
  String? text,
}) => CompletedEntry(
  recordId: id,
  completionSeq: seq,
  run: CompletionRunPosition(startSeq: start ?? seq, ordinal: ordinal),
  mainPresentation: presentation,
  atom: ChatAtom(
    id: 'atom:$id',
    completionItemId: id,
    completionSeq: seq,
    source: const ForegroundTurnChatSource(turnId: 'turn'),
    sourceOrder: null,
    kind: presentation == MainPresentation.single
        ? ChatAtomKind.text
        : ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: null,
      outcome: ChatTerminalOutcome.completed,
    ),
    textChannel: presentation == MainPresentation.single
        ? ThreadTextChannel.finalAnswer
        : null,
    contentPresent: true,
    contents: const [],
    payload: presentation == MainPresentation.single
        ? InlinePayload(
            bytes: utf8.encode(
              jsonEncode({
                'contract': 'anywork.chat/1',
                'type': 'text',
                'data': {'channel': 'final', 'attachments': []},
                'bodies': [
                  {
                    'key': 'body',
                    'byteLength': utf8.encode(text ?? id).length,
                    'inline': utf8.encode(text ?? id),
                  },
                ],
              }),
            ),
          )
        : DeferredPayload(
            reference: ContentRef(
              databaseId: databaseId,
              target: ItemPayloadTarget(itemId: id),
            ),
            byteLength: 100,
          ),
  ),
);

ChatBatch completedBatch(
  List<CompletedEntry> entries, {
  ChatPlacement placement = ChatPlacement.set,
  int? from,
  int? through,
  String? before,
}) => ChatBatch(
  placement: placement,
  entries: entries,
  fromSeq: from,
  throughSeq: through ?? entries.lastOrNull?.completionSeq ?? 0,
  before: before,
);
