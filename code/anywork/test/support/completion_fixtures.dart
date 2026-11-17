import 'dart:convert';

import 'package:anywork_client/models.dart';

import 'chat_fixtures.dart';

/// Explicit producer fixture. Callers choose the domain kind and immutable
/// block order; this helper does not classify atoms or combine rows.
FixtureCompletion completionEntry(
  String id,
  int seq, {
  bool isText = false,
  String databaseId = 'database',
  String? text,
}) => FixtureCompletion(
  recordId: id,
  completionSeq: seq,
  atom: ChatAtom(
    id: 'atom:$id',
    source: const ForegroundTurnChatSource(turnId: 'turn'),
    sourceOrder: null,
    kind: isText ? ChatAtomKind.text : ChatAtomKind.toolCall,
    delivery: ChatDeliveryKind.foreground,
    lifecycle: const TerminalChatAtom(
      started: null,
      ended: null,
      outcome: ChatTerminalOutcome.completed,
    ),
    textChannel: isText ? ThreadTextChannel.finalAnswer : null,
    contentPresent: true,
    contents: const [],
    payload: isText
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
