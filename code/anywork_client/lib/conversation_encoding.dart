import 'dart:convert';

import 'models.dart';

String _threadTextChannelToJson(ThreadTextChannel channel) =>
    channel == ThreadTextChannel.finalAnswer ? 'final' : channel.name;

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
  if (atom.wait case final wait?) 'wait': _threadWaitToJson(wait),
  'textChannel': atom.textChannel == null
      ? null
      : _threadTextChannelToJson(atom.textChannel!),
  if (atom.contentPresent != null) 'contentPresent': atom.contentPresent,
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

Map<String, Object?> _threadWaitToJson(ThreadWaitPresentationView wait) => {
  'intent': switch (wait.intent) {
    ThreadWaitEventsIntentView(:final targets, :final timeoutMs) => {
      'kind': 'events',
      'data': {
        'targets': [
          for (final target in targets)
            {
              'taskId': target.taskId,
              if (target.toolName != null) 'toolName': target.toolName,
              if (target.summary != null) 'summary': target.summary,
              if (target.summaryTruncated) 'summaryTruncated': true,
              if (target.status != null) 'status': target.status!.name,
            },
        ],
        'timeoutMs': timeoutMs,
      },
    },
    ThreadWaitTimerIntentView(:final durationMs) => {
      'kind': 'timer',
      'data': {'durationMs': durationMs},
    },
  },
  'state': wait.state.name,
  if (wait.messagesReady != null) 'messagesReady': wait.messagesReady,
};

Map<String, Object?> completedEntryToJson(CompletedEntry entry) => {
  'recordId': entry.recordId,
  'completionSeq': entry.completionSeq,
  'run': entry.run == null
      ? null
      : {'startSeq': entry.run!.startSeq, 'ordinal': entry.run!.ordinal},
  'mainPresentation': entry.mainPresentation.name,
  'atom': chatAtomToJson(entry.atom),
};

Map<String, Object?> completionRunRefToJson(CompletionRunRef reference) => {
  'databaseId': reference.databaseId,
  'indexVersion': reference.indexVersion,
  'startSeq': reference.startSeq,
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
      InboxMessageChatSource(:final sourceId, :final messageId) => {
        'kind': 'inboxMessage',
        'sourceId': sourceId,
        'messageId': messageId,
      },
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
