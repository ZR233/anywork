import 'dart:convert';

import 'models.dart';

/// Mechanical canonical conversation JSON. No presentation grouping or state.
Map<String, Object?> chatAtomToJson(ChatAtom atom) => {
  'id': atom.id,
  'completionItemId': atom.completionItemId,
  'completionSeq': atom.completionSeq,
  'source': chatSourceIdToJson(atom.source),
  if (atom.sourceState case final state?)
    'sourceState': chatSourceStateToJson(state),
  'sourceOrder': atom.sourceOrder,
  'kind': atom.kind.name,
  'delivery': atom.delivery.name,
  'lifecycle': switch (atom.lifecycle) {
    ActiveChatAtom(:final started, :final status) => {
      'kind': 'active',
      'started': chatFactPositionToJson(started),
      'status': status.name,
    },
    TerminalChatAtom(:final started, :final ended, :final outcome) => {
      'kind': 'terminal',
      'started': chatFactPositionToJson(started),
      'ended': chatFactPositionToJson(ended),
      'outcome': outcome.name,
    },
  },
  'turnId': atom.turnId,
  'attemptId': atom.attemptId,
  'tool': atom.tool == null
      ? null
      : {'callId': atom.tool!.callId, 'name': atom.tool!.name},
  'textChannel': atom.textChannel?.name,
  'startedAt': atom.startedAt,
  'finishedAt': atom.finishedAt,
  'contents': [
    for (final content in atom.contents)
      {
        'role': content.role.name,
        'reference': contentRefToJson(content.reference),
      },
  ],
  'payload': atom.payload == null ? null : chatPayloadToJson(atom.payload!),
};

Map<String, Object?> chatEntryToJson(ChatEntry entry) => switch (entry) {
  ChatAtomEntry(:final atom) => {'kind': 'atom', 'value': chatAtomToJson(atom)},
  ChatSourceEntry(:final state) => {
    'kind': 'source',
    'value': chatSourceStateToJson(state),
  },
};

/// Counts the canonical UTF-8 entry, including the discriminant and envelope.
/// The caller owns the workset; this function retains no atom or encoded bytes.
int chatAtomEntryEncodedLength(ChatAtom atom) => utf8
    .encode(jsonEncode({'kind': 'atom', 'value': chatAtomToJson(atom)}))
    .length;

Map<String, Object?> chatSourceIdToJson(ChatSourceId source) =>
    switch (source) {
      ForegroundTurnChatSource(:final turnId) => {
        'kind': 'foregroundTurn',
        'turnId': turnId,
      },
      InputChatSource(:final inputId) => {'kind': 'input', 'inputId': inputId},
      BackgroundResultChatSource(:final messageId) => {
        'kind': 'backgroundResult',
        'messageId': messageId,
      },
      OperationChatSource(:final operationId) => {
        'kind': 'operation',
        'operationId': operationId,
      },
      ReceiptChatSource(:final receiptId) => {
        'kind': 'receipt',
        'receiptId': receiptId,
      },
    };

Map<String, Object?>? chatFactPositionToJson(ChatFactPosition? position) =>
    position == null
    ? null
    : {'effectSeq': position.effectSeq, 'suborder': position.suborder};

Map<String, Object?> chatSourceStateToJson(ChatSourceState state) => {
  'source': chatSourceIdToJson(state.source),
  'lifecycle': switch (state.lifecycle) {
    UnknownChatSource() => {'kind': 'unknown'},
    ActiveChatSource() => {'kind': 'active'},
    EndedChatSource(:final outcome) => {
      'kind': 'ended',
      'outcome': outcome.name,
    },
  },
  'started': chatFactPositionToJson(state.started),
  'ended': chatFactPositionToJson(state.ended),
};

Map<String, Object?> chatPayloadToJson(PayloadData payload) =>
    switch (payload) {
      InlinePayload(:final bytes) => {'kind': 'inline', 'bytes': bytes},
      DeferredPayload(:final reference, :final byteLength) => {
        'kind': 'deferred',
        'reference': contentRefToJson(reference),
        'byteLength': byteLength,
      },
    };

Map<String, Object?> contentRefToJson(ContentRef reference) => {
  'databaseId': reference.databaseId,
  'target': switch (reference.target) {
    ItemPayloadTarget(:final itemId) => {
      'kind': 'itemPayload',
      'itemId': itemId,
    },
    BodyContentTarget(:final owner, :final key) => {
      'kind': 'body',
      'owner': switch (owner) {
        ItemContentOwner(:final itemId) => {'kind': 'item', 'itemId': itemId},
        CurrentContentOwner(:final domain, :final id, :final revision) => {
          'kind': 'current',
          'domain': domain,
          'id': id,
          'revision': revision,
        },
      },
      'key': key,
    },
  },
};
