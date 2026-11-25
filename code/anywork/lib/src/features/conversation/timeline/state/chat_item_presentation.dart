import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'chat_payload_reading.dart';
import 'timeline_display_unit.dart';
import '../tools/tool_item_registry.dart';

const chatItemPresentationKey = 'chatItemPresentation';

/// Frozen observation time ends at its captured cut, not a fabricated terminal.
extension DisplayRecordTime on DisplayRecord {
  int? get displayStartedAt => switch (contentSource) {
    FrozenObservation(capturedAt: null) => null,
    _ => atom.startedAt,
  };
  int? get displayObservedThrough => switch (contentSource) {
    FrozenObservation(:final capturedAt) =>
      capturedAt == null ? null : capturedAt ~/ Duration.millisecondsPerSecond,
    _ => atom.finishedAt,
  };
}

ChatItemPresentation? chatItemPresentationOf(Message message) =>
    message.metadata?[chatItemPresentationKey] as ChatItemPresentation?;

enum ChatItemCompatibility { current, unknown, malformed, deferred }

/// One item's presentation value, owned only by that Message.custom's metadata.
/// It is not a second message collection or a historical protocol decoder.
final class ChatItemPresentation {
  ChatItemPresentation({
    required this.id,
    required this.compatibility,
    required this.type,
    required this.data,
    required this.bodies,
    this.raw,
    this.byteLength,
    this.createdAt,
    this.authorId = 'unknown',
    this.presentationContract,
    this.diagnostic,
    this.displayUnit,
    this.atom,
    this.displayRecord,
  });

  final String id;
  final ChatItemCompatibility compatibility;
  final String type;
  final Map<String, Object?> data;
  final List<ChatBodyPresentation> bodies;
  final String? raw;
  final int? byteLength;
  final DateTime? createdAt;
  final String authorId;
  final String? presentationContract;
  final String? diagnostic;
  final TimelineDisplayUnit? displayUnit;
  final ChatAtom? atom;
  final DisplayRecord? displayRecord;
  String? get historyEventId => displayRecord?.historyEventId;
  String? get historyDetailEventId => displayRecord?.historyDetailEventId;
  List<CurrentAtomContent> get currentContents =>
      displayRecord?.currentContents ?? const [];
  bool get finalEmptyAfterContent => switch (displayUnit?.body) {
    SingleDisplayBlock(
      visibility: HistorySingleVisibility.finalEmptyAfterContent,
    ) =>
      true,
    _ => false,
  };
  bool get observationUnavailable =>
      displayRecord?.contentSource is FrozenObservation &&
      !(displayRecord!.contentSource as FrozenObservation).available;
  late final ToolCardReading toolCard = readToolCard(this);
  late final StudioModelRecoveryNotice? modelRecovery =
      atom?.modelRecovery ??
      (compatibility == ChatItemCompatibility.current && type == 'text'
          ? StudioModelRecoveryNotice.fromJson(data['modelRecovery'])
          : null);

  bool get showsTextCopy => switch (authorId) {
    'user' || 'parentAgent' => true,
    _ => switch (atom) {
      ChatAtom(
        kind: ChatAtomKind.text,
        textChannel: ThreadTextChannel.finalAnswer,
        lifecycle: TerminalChatAtom(outcome: ChatTerminalOutcome.completed),
        :final id,
      ) =>
        // The producer reserves this entity namespace for committed finish_turn
        // deliveries. Provider text can also be on the final-answer channel.
        displayRecord?.contentSource is CompletedOriginal &&
            id.startsWith('completion:'),
      _ => false,
    },
  };

  // The original producer's declaration, not envelope metadata, grants Body
  // intent. Keeping it on the original atom also keeps it stable after decode.
  late final List<int> publicInputBodyIndices = _publicInputBodyIndices();
  bool get hasPublicInputBody => publicInputBodyIndices.isNotEmpty;

  List<int> _publicInputBodyIndices() {
    final input = atom;
    if (input == null ||
        input.source is! InputChatSource ||
        input.kind != ChatAtomKind.input) {
      return const [];
    }
    return List.unmodifiable([
      for (var index = 0; index < currentContents.length; index++)
        if (currentContents[index].role == ChatContentRole.body &&
            currentContents[index].reference.contentKey == 'body')
          index,
    ]);
  }

  ChatItemPresentation resolvePayload(InlinePayload payload) =>
      resolvePresentation(decodePayload(id, payload));

  /// Reuses parsed immutable content while keeping this row's display owner.
  ChatItemPresentation resolvePresentation(ChatItemPresentation value) =>
      ChatItemPresentation(
        id: id,
        compatibility: value.compatibility,
        type: value.type,
        data: value.data,
        bodies: value.bodies,
        raw: value.raw,
        createdAt: createdAt ?? value.createdAt,
        authorId: authorId == 'unknown' ? value.authorId : authorId,
        presentationContract: value.presentationContract,
        diagnostic: value.diagnostic,
        displayUnit: displayUnit,
        atom: atom,
        displayRecord: displayRecord,
      );

  bool get presentsFiles => timelineToolItemRegistry
      .resolveForChatItem(this)
      .presentsStandaloneMedia(this);

  /// Structural empty text still exists in owner metadata. Deferred/unknown
  /// content is never assumed empty.
  bool get isKnownEmptyText =>
      !finalEmptyAfterContent &&
      modelRecovery == null &&
      atom?.contentPresent == false &&
      type == 'text' &&
      compatibility == ChatItemCompatibility.current &&
      bodies.every((body) => body.byteLength == 0) &&
      attachments.isEmpty;

  bool get needsHistoryBodyLoad {
    if (historyEventId == null) return false;
    final predecoded = displayRecord?.predecodedPresentation;
    if (predecoded == null) return true;
    if (predecoded.compatibility != ChatItemCompatibility.current) {
      return false;
    }
    return (predecoded.type == 'text' || predecoded.type == 'input') &&
        predecoded.bodies.any(
          (body) =>
              body.key == 'body' &&
              body.historyReference != null &&
              !body.hasInline,
        );
  }

  ChatBodyPresentation? body(String key) =>
      bodies.where((body) => body.key == key).firstOrNull;
  String? inlineText(String key) => body(key)?.text;

  late final List<ThreadAttachmentView> attachments = chatAttachments(
    type == 'text'
        ? data['attachments']
        : type == 'tool' &&
              data['state'] is Map<String, Object?> &&
              (data['state'] as Map<String, Object?>)['output']
                  is Map<String, Object?>
        ? ((data['state'] as Map<String, Object?>)['output']
              as Map<String, Object?>)['attachments']
        : null,
  );

  static ChatItemPresentation decode(
    ChatAtom message, {
    DisplayRecord? record,
    String? displayId,
  }) {
    if (record?.contentSource case FrozenObservation(available: false)) {
      return _unavailableObservation(displayId ?? message.id, record!);
    }
    final payload = message.payload;
    if (payload == null) {
      throw const FormatException('Atom has no completion payload');
    }
    final value = decodePayload(displayId ?? message.id, payload);
    return ChatItemPresentation(
      id: value.id,
      compatibility: value.compatibility,
      type: value.type,
      data: value.data,
      bodies: value.bodies,
      raw: value.raw,
      byteLength: value.byteLength,
      createdAt: value.createdAt,
      authorId: _inboxAuthor(message) ?? value.authorId,
      presentationContract: value.presentationContract,
      diagnostic: value.diagnostic,
      atom: message,
      displayRecord: record,
    );
  }

  static ChatItemPresentation forUnit(TimelineDisplayUnit unit) {
    final item = unit.atom;
    if (item == null ||
        (unit.body is SingleDisplayBlock &&
            (unit.body as SingleDisplayBlock).visibility ==
                HistorySingleVisibility.finalEmptyAfterContent)) {
      return ChatItemPresentation(
        id: unit.id,
        compatibility: ChatItemCompatibility.current,
        type: 'displayUnit',
        data: const {},
        bodies: const [],
        displayUnit: unit,
        authorId: 'assistant',
      );
    }
    final record = (unit.body as SingleDisplayBlock).record;
    if (record.contentSource case FrozenObservation(available: false)) {
      if (record.predecodedPresentation?.compatibility !=
          ChatItemCompatibility.malformed) {
        return _unavailableObservation(unit.id, record);
      }
    }
    final author =
        _inboxAuthor(item) ??
        switch (item.textChannel) {
          ThreadTextChannel.user => 'user',
          ThreadTextChannel.parentAgent => 'parentAgent',
          ThreadTextChannel.commentary ||
          ThreadTextChannel.finalAnswer => 'assistant',
          null => null,
        };
    final finishedAt = item.finishedAt;
    final time =
        finishedAt != null &&
            finishedAt >= -8640000000000 &&
            finishedAt <= 8640000000000
        ? DateTime.fromMillisecondsSinceEpoch(finishedAt * 1000, isUtc: true)
        : null;
    if (item.payload == null) {
      if (record.contentSource is! CurrentAtomSource &&
          record.predecodedPresentation != null) {
        final pre = forRecord(record, id: unit.id);
        return ChatItemPresentation(
          id: unit.id,
          compatibility: pre.compatibility,
          type: pre.type,
          data: pre.data,
          bodies: pre.bodies,
          raw: pre.raw,
          byteLength: pre.byteLength,
          createdAt: pre.createdAt ?? time,
          authorId: author ?? pre.authorId,
          presentationContract: pre.presentationContract,
          diagnostic: pre.diagnostic,
          displayUnit: unit,
          atom: item,
          displayRecord: record,
        );
      }
      return ChatItemPresentation(
        id: unit.id,
        compatibility: ChatItemCompatibility.current,
        type: 'displayUnit',
        data: const {},
        bodies: const [],
        displayUnit: unit,
        displayRecord: record,
        atom: item,
        authorId: author ?? 'unknown',
        createdAt: time,
      );
    }
    final value = decodePayload(unit.id, item.payload!);
    return ChatItemPresentation(
      id: unit.id,
      compatibility: value.compatibility,
      type: value.type,
      data: value.data,
      bodies: value.bodies,
      raw: value.raw,
      byteLength: value.byteLength,
      createdAt: value.createdAt ?? time,
      authorId: author ?? value.authorId,
      presentationContract: value.presentationContract,
      diagnostic: value.diagnostic,
      displayUnit: unit,
      atom: item,
      displayRecord: (unit.body as SingleDisplayBlock).record,
    );
  }

  /// Wraps one stable History/Current display record without inventing a unit
  /// row. Canonical History body loading owns the actual event identity.
  static ChatItemPresentation forRecord(
    DisplayRecord record, {
    required String id,
  }) {
    final predecoded = record.contentSource is CurrentAtomSource
        ? null
        : record.predecodedPresentation;
    final fallbackAuthor =
        _inboxAuthor(record.atom) ??
        switch (record.atom.textChannel) {
          ThreadTextChannel.user => 'user',
          ThreadTextChannel.parentAgent => 'parentAgent',
          ThreadTextChannel.commentary ||
          ThreadTextChannel.finalAnswer => 'assistant',
          null => 'unknown',
        };
    if (predecoded != null) {
      return ChatItemPresentation(
        id: id,
        compatibility: predecoded.compatibility,
        type: predecoded.type,
        data: predecoded.data,
        bodies: predecoded.bodies,
        raw: predecoded.raw,
        byteLength: predecoded.byteLength,
        createdAt: predecoded.createdAt,
        authorId: predecoded.authorId == 'unknown'
            ? fallbackAuthor
            : predecoded.authorId,
        presentationContract: predecoded.presentationContract,
        diagnostic: predecoded.diagnostic,
        displayRecord: record,
        atom: record.atom,
      );
    }
    return ChatItemPresentation(
      id: id,
      compatibility: ChatItemCompatibility.current,
      type: 'displayRecord',
      data: const {},
      bodies: const [],
      displayRecord: record,
      atom: record.atom,
      authorId: fallbackAuthor,
    );
  }

  // Inbox payloads cannot grant parent identity. Only the runtime's typed
  // channel records admission from the direct parent; sourceId stays opaque.
  static String? _inboxAuthor(ChatAtom atom) => switch (atom.source) {
    InboxMessageChatSource(:final sourceId) =>
      atom.textChannel == ThreadTextChannel.parentAgent
          ? 'parentAgent'
          : 'inbox:$sourceId',
    _ => null,
  };

  static ChatItemPresentation _unavailableObservation(
    String id,
    DisplayRecord record,
  ) => ChatItemPresentation(
    id: id,
    compatibility: ChatItemCompatibility.current,
    type: 'observation',
    data: const {},
    bodies: const [],
    displayRecord: record,
  );

  static ChatItemPresentation decodePayload(String id, PayloadData payload) {
    if (payload is DeferredPayload) {
      return ChatItemPresentation(
        id: id,
        compatibility: ChatItemCompatibility.deferred,
        type: 'deferred',
        data: const {},
        bodies: const [],
        byteLength: payload.byteLength,
      );
    }
    try {
      final raw = utf8.decode((payload as InlinePayload).bytes);
      return decodePayloadJson(id, raw);
    } on FormatException catch (error) {
      return _malformed(id, null, error.message);
    }
  }

  static ChatItemPresentation decodeEventRecord(
    HistoryEventRecord record, {
    String? id,
  }) {
    final displayId = id ?? record.entityId ?? record.eventId;
    final decoded = decodePayloadJson(
      displayId,
      record.payloadJson,
      payloadSchema: record.payloadSchema,
    );
    final timestamp = record.occurredAt ?? record.recordedAt;
    final fallbackTime =
        timestamp >= -8640000000000000 && timestamp <= 8640000000000000
        ? DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
        : null;
    final author = switch (record.source) {
      InboxMessageChatSource(:final sourceId) =>
        decoded.authorId == 'parentAgent' ? 'parentAgent' : 'inbox:$sourceId',
      _ => null,
    };
    return ChatItemPresentation(
      id: decoded.id,
      compatibility: decoded.compatibility,
      type: decoded.type,
      data: decoded.data,
      bodies: decoded.bodies,
      raw: decoded.raw,
      byteLength: decoded.byteLength,
      createdAt: decoded.createdAt ?? fallbackTime,
      authorId: author ?? decoded.authorId,
      presentationContract: decoded.presentationContract,
      diagnostic: decoded.diagnostic,
    );
  }

  static ChatItemPresentation decodePayloadJson(
    String id,
    String raw, {
    String? payloadSchema,
  }) {
    if (payloadSchema != null &&
        payloadSchema != 'anywork.event/1' &&
        payloadSchema != 'anywork.chat/1') {
      return ChatItemPresentation(
        id: id,
        compatibility: ChatItemCompatibility.unknown,
        type: 'unknown',
        data: const {},
        bodies: const [],
        raw: raw,
        diagnostic: '不支持的载荷协议: $payloadSchema',
      );
    }
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Payload envelope must be an object');
      }
      final contract = json['contract'];
      final type = json['type'];
      final data = json['data'];
      if (contract != 'anywork.chat/1' && contract != 'anywork.event/1') {
        return ChatItemPresentation(
          id: id,
          compatibility: ChatItemCompatibility.unknown,
          type: type is String ? type : 'unknown',
          data: const {},
          bodies: const [],
          raw: raw,
          diagnostic: contract is String ? '不支持的载荷契约: $contract' : null,
        );
      }
      if (type is! String || data is! Map<String, dynamic>) {
        throw const FormatException('Payload type/data is invalid');
      }
      final rawMeta = json['meta'];
      if (contract == 'anywork.event/1' &&
          rawMeta != null &&
          rawMeta is! Map<String, dynamic>) {
        throw const FormatException('Payload meta must be an object');
      }
      final meta = rawMeta is Map<String, dynamic> ? rawMeta : null;
      final encodedBodies = json['bodies'];
      if (encodedBodies != null && encodedBodies is! List<dynamic>) {
        throw const FormatException('Payload bodies must be an ordered list');
      }
      final bodies = <ChatBodyPresentation>[];
      for (final body in encodedBodies as List<dynamic>? ?? const []) {
        if (body is! Map<String, dynamic> ||
            body['key'] is! String ||
            body['byteLength'] is! int) {
          throw const FormatException('Invalid body manifest entry');
        }
        final rawMediaType = body['mediaType'];
        if (rawMediaType != null && rawMediaType is! String) {
          throw const FormatException('Invalid body mediaType');
        }
        final inlineText = body['inlineText'];
        if (inlineText != null && inlineText is! String) {
          throw const FormatException('Invalid inlineText body');
        }
        final inline = body['inline'];
        if (inline != null &&
            (inline is! List<dynamic> ||
                inline.any((byte) => byte is! int || byte < 0 || byte > 255))) {
          throw const FormatException('Invalid inline body bytes');
        }
        final Uint8List? inlineBytes;
        if (inline != null) {
          inlineBytes = Uint8List.fromList(
            (inline as List<dynamic>).cast<int>(),
          ).asUnmodifiableView();
        } else if (inlineText is String) {
          inlineBytes = Uint8List.fromList(utf8.encode(inlineText))
              .asUnmodifiableView();
        } else {
          inlineBytes = null;
        }
        final rawReference = body['reference'];
        HistoryEventBodyRef? historyReference;
        CurrentContentRef? currentReference;
        if (rawReference != null) {
          if (rawReference is! Map<String, dynamic>) {
            throw const FormatException('Invalid body reference');
          }
          if (rawReference['ownerEventId'] != null) {
            historyReference = _historyBodyReference(rawReference);
          } else if (rawReference['ownerId'] != null) {
            currentReference = _currentBodyReference(rawReference);
          } else {
            throw const FormatException('Unknown body reference kind');
          }
        }
        bodies.add(
          ChatBodyPresentation(
            key: body['key'] as String,
            byteLength: body['byteLength'] as int,
            mediaType: rawMediaType as String?,
            inline: inlineBytes,
            inlineText: inlineText as String?,
            historyReference: historyReference,
            currentReference: currentReference,
          ),
        );
      }
      final invocation = data['invocation'];
      final marker =
          (invocation is Map<String, dynamic>
              ? invocation['presentationContract']
              : null) ??
          meta?['presentationContract'];
      if (marker != null && marker is! String) {
        throw const FormatException('Invalid presentation contract');
      }
      final metaMillis =
          meta?['finishedAt'] ?? meta?['startedAt'] ?? json['capturedAt'];
      final sealedAt = json['sealedAt'];
      DateTime? createdAt;
      if (metaMillis is int &&
          metaMillis >= -8640000000000000 &&
          metaMillis <= 8640000000000000) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(
          metaMillis,
          isUtc: true,
        );
      } else if (sealedAt is int &&
          sealedAt >= -8640000000000 &&
          sealedAt <= 8640000000000) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(
          sealedAt * 1000,
          isUtc: true,
        );
      }
      // Author comes only from explicit producer facts, never a fallback to
      // assistant, tool name, item id, or this machine's clock.
      final channel = data['channel'] ?? meta?['textChannel'];
      final author = type == 'text'
          ? switch (channel) {
              'user' => 'user',
              'parentAgent' => 'parentAgent',
              'commentary' || 'final' || 'finalAnswer' => 'assistant',
              _ => 'unknown',
            }
          : 'unknown';
      return ChatItemPresentation(
        id: id,
        compatibility: ChatItemCompatibility.current,
        type: type,
        data: Map.unmodifiable(data),
        bodies: List.unmodifiable(bodies),
        raw: raw,
        createdAt: createdAt,
        authorId: author,
        presentationContract: marker as String?,
      );
    } on FormatException catch (error) {
      return _malformed(id, raw, error.message);
    } on TypeError catch (error) {
      return _malformed(id, raw, error.toString());
    }
  }

  static ChatItemPresentation _malformed(
    String id,
    String? raw,
    String diagnostic,
  ) => ChatItemPresentation(
    id: id,
    compatibility: ChatItemCompatibility.malformed,
    type: 'malformed',
    data: const {},
    bodies: const [],
    raw: raw,
    diagnostic: diagnostic,
  );
}

final class ChatBodyPresentation {
  const ChatBodyPresentation({
    required this.key,
    required this.byteLength,
    this.mediaType,
    this.inline,
    this.inlineText,
    this.historyReference,
    this.currentReference,
  });
  final String key;
  final int byteLength;
  final String? mediaType;
  final Uint8List? inline;
  final String? inlineText;
  final HistoryEventBodyRef? historyReference;
  final CurrentContentRef? currentReference;
  bool get hasInline => inlineText != null || inline != null;
  String? get text =>
      inlineText ?? (inline == null ? null : utf8.decode(inline!));
  bool get hasReference => historyReference != null || currentReference != null;
}

HistoryEventBodyRef _historyBodyReference(Map<String, dynamic> value) =>
    HistoryEventBodyRef(
      databaseId: chatString(value['databaseId'], 'body.databaseId'),
      ownerEventId: chatString(value['ownerEventId'], 'body.ownerEventId'),
      bodyKey: chatString(value['bodyKey'], 'body.bodyKey'),
      bodyId: chatString(value['bodyId'], 'body.bodyId'),
      byteStart: chatInteger(value['byteStart'], 'body.byteStart'),
      byteLength: chatInteger(value['byteLength'], 'body.byteLength'),
    );

CurrentContentRef _currentBodyReference(Map<String, dynamic> value) =>
    CurrentContentRef(
      ownerId: chatString(value['ownerId'], 'body.ownerId'),
      domain: chatString(value['domain'], 'body.domain'),
      entityId: chatString(value['entityId'], 'body.entityId'),
      contentKey: chatString(value['contentKey'], 'body.contentKey'),
      generation: chatString(value['generation'], 'body.generation'),
    );
