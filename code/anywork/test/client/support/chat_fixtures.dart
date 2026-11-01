import 'dart:convert';

import 'package:anywork_client/studio_client.dart';

const chatDemand = ReadDemand(maxItems: 20, maxBytes: 65536);

ChatMessage chatMessage(String id, {String body = '中文 🐱'}) => ChatMessage(
  id: id,
  payload: InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': 'anywork.chat/1',
        'type': 'text',
        'turnId': 'turn',
        'data': {
          'channel': 'final',
          'attachments': <Object?>[],
          'outcome': {
            'kind': 'completed',
            'data': {'completedAt': 0},
          },
        },
        'bodies': [
          {
            'key': 'body',
            'byteLength': utf8.encode(body).length,
            'inline': utf8.encode(body),
          },
        ],
      }),
    ),
  ),
);

CurrentProjection chatCurrent({int sequence = 0}) => CurrentProjection(
  sourceEffectSeq: sequence,
  logicalStatus: ThreadStatusView.idle,
  executionPresent: false,
  previews: const [],
  collections: const [],
);

ChatMessage chatEnvelope(
  String id, {
  required String type,
  required Map<String, Object?> data,
  List<Map<String, Object?>> bodies = const [],
  int? sealedAt,
  String contract = 'anywork.chat/1',
}) => ChatMessage(
  id: id,
  payload: InlinePayload(
    bytes: utf8.encode(
      jsonEncode({
        'contract': contract,
        'type': type,
        'data': data,
        'bodies': bodies,
        'sealedAt': ?sealedAt,
      }),
    ),
  ),
);

Map<String, Object?> inlineBody(String key, String text) => {
  'key': key,
  'byteLength': utf8.encode(text).length,
  'inline': utf8.encode(text),
};

ChatBatch chatBatch(
  List<ChatMessage> messages, {
  ChatPlacement placement = ChatPlacement.set,
  String? before,
  CurrentProjection? current,
}) => ChatBatch(
  placement: placement,
  messages: messages,
  before: before,
  current: current,
);
