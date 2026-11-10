import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'chat_payload_reading.dart';
import 'timeline_display_unit.dart';

const chatItemPresentationKey = 'chatItemPresentation';

/// Frozen observation time ends at its captured cut, not a fabricated terminal.
extension DisplayRecordTime on DisplayRecord {
  int? get displayStartedAt => switch (contentSource) {
    FrozenObservation(capturedAt: null) => null,
    _ => atom.startedAt,
  };
  int? get displayObservedThrough => switch (contentSource) {
    FrozenObservation(:final capturedAt) => capturedAt,
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
    this.reference,
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
  final ContentRef? reference;
  final int? byteLength;
  final DateTime? createdAt;
  final String authorId;
  final String? presentationContract;
  final String? diagnostic;
  final TimelineDisplayUnit? displayUnit;
  final ChatAtom? atom;
  final DisplayRecord? displayRecord;
  bool get observationUnavailable =>
      displayRecord?.contentSource is FrozenObservation &&
      !(displayRecord!.contentSource as FrozenObservation).available;
  late final ToolCardReading toolCard = readToolCard(this);

  // The original producer's declaration, not envelope metadata, grants Body
  // intent. Keeping it on the original atom also keeps it stable after decode.
  late final List<int> publicInputBodyIndices = _publicInputBodyIndices();
  bool get hasPublicInputBody => publicInputBodyIndices.isNotEmpty;

  List<int> _publicInputBodyIndices() {
    final input = atom;
    if (input == null ||
        input.source is! InputChatSource ||
        input.kind != ChatAtomKind.input ||
        input.payload is! DeferredPayload) {
      return const [];
    }
    return List.unmodifiable([
      for (var index = 0; index < input.contents.length; index++)
        if (input.contents[index].role == ChatContentRole.body)
          if (input.contents[index].reference.target case BodyContentTarget(
            key: 'body',
            owner: ItemContentOwner(itemId: final ownerItemId),
          ))
            if (ownerItemId == (input.completionItemId ?? input.id)) index,
    ]);
  }

  ChatItemPresentation resolvePayload(InlinePayload payload) {
    final value = decodePayload(id, payload);
    return ChatItemPresentation(
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
  }

  bool get presentsFiles {
    if (type != 'tool' || presentationContract != 'builtin.show_files@1') {
      return false;
    }
    final state = chatObject(data['state'], 'state');
    return state['kind'] == 'succeeded' ||
        (state['kind'] == 'failed' && body('tool.output-artifacts') != null);
  }

  /// Structural empty text still exists in owner metadata. Deferred/unknown
  /// content is never assumed empty.
  bool get isKnownEmptyText =>
      atom?.contentPresent == false &&
      type == 'text' &&
      compatibility == ChatItemCompatibility.current &&
      bodies.every((body) => body.byteLength == 0) &&
      attachments.isEmpty;

  ChatBodyPresentation? body(String key) =>
      bodies.where((body) => body.key == key).firstOrNull;
  String? inlineText(String key) {
    final bytes = body(key)?.inline;
    return bytes == null ? null : utf8.decode(bytes);
  }

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
      reference: value.reference,
      byteLength: value.byteLength,
      createdAt: value.createdAt,
      authorId: message.source is InboxMessageChatSource
          ? 'inbox:${(message.source as InboxMessageChatSource).sourceId}'
          : value.authorId,
      presentationContract: value.presentationContract,
      diagnostic: value.diagnostic,
      atom: message,
      displayRecord: record,
    );
  }

  static ChatItemPresentation forUnit(TimelineDisplayUnit unit) {
    final item = unit.atom;
    if (item == null) {
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
      return _unavailableObservation(unit.id, record);
    }
    final author = item.source is InboxMessageChatSource
        ? 'inbox:${(item.source as InboxMessageChatSource).sourceId}'
        : switch (item.textChannel) {
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
      return ChatItemPresentation(
        id: unit.id,
        compatibility: ChatItemCompatibility.current,
        type: 'displayUnit',
        data: const {},
        bodies: const [],
        displayUnit: unit,
        displayRecord: record,
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
      reference: value.reference,
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
        reference: payload.reference,
        byteLength: payload.byteLength,
      );
    }
    String? raw;
    try {
      raw = utf8.decode((payload as InlinePayload).bytes);
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) {
        throw const FormatException('Payload envelope must be an object');
      }
      final type = json['type'];
      final data = json['data'];
      if (json['contract'] != 'anywork.chat/1') {
        return ChatItemPresentation(
          id: id,
          compatibility: ChatItemCompatibility.unknown,
          type: type is String ? type : 'unknown',
          data: const {},
          bodies: const [],
          raw: raw,
        );
      }
      if (type is! String || data is! Map<String, dynamic>) {
        throw const FormatException('Payload type/data is invalid');
      }
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
        final inline = body['inline'];
        if (inline != null &&
            (inline is! List<dynamic> ||
                inline.any((byte) => byte is! int || byte < 0 || byte > 255))) {
          throw const FormatException('Invalid inline body bytes');
        }
        bodies.add(
          ChatBodyPresentation(
            key: body['key'] as String,
            byteLength: body['byteLength'] as int,
            inline: inline == null
                ? null
                : Uint8List.fromList((inline as List<dynamic>).cast<int>())
                      .asUnmodifiableView(),
            reference: body['reference'] == null
                ? null
                : contentReference(body['reference']),
          ),
        );
      }
      final invocation = data['invocation'];
      final marker = invocation is Map<String, dynamic>
          ? invocation['presentationContract']
          : null;
      if (marker != null && marker is! String) {
        throw const FormatException('Invalid presentation contract');
      }
      final sealedAt = json['sealedAt'];
      DateTime? createdAt;
      if (sealedAt is int &&
          sealedAt >= -8640000000000 &&
          sealedAt <= 8640000000000) {
        createdAt = DateTime.fromMillisecondsSinceEpoch(
          sealedAt * 1000,
          isUtc: true,
        );
      }
      // Author comes only from explicit producer facts, never a fallback to
      // assistant, tool name, item id, or this machine's clock.
      final channel = data['channel'];
      final author = type == 'text'
          ? switch (channel) {
              'user' => 'user',
              'parentAgent' => 'parentAgent',
              'commentary' || 'final' => 'assistant',
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

  static ContentRef contentReference(Object? value) {
    if (value is! Map<String, dynamic> ||
        value['databaseId'] is! String ||
        value['target'] is! Map<String, dynamic>) {
      throw const FormatException('Invalid content reference');
    }
    final target = value['target'] as Map<String, dynamic>;
    final ContentTarget decoded;
    switch (target['kind']) {
      case 'itemPayload':
        decoded = ItemPayloadTarget(itemId: target['itemId'] as String);
      case 'body':
        final owner = target['owner'] as Map<String, dynamic>;
        decoded = BodyContentTarget(
          owner: switch (owner['kind']) {
            'item' => ItemContentOwner(itemId: owner['itemId'] as String),
            'displayObservation' => DisplayObservationContentOwner(
              blockId: owner['blockId'] as String,
              memberKey: owner['memberKey'] as String,
            ),
            'current' => CurrentContentOwner(
              domain: owner['domain'] as String,
              id: owner['id'] as String,
              revision: owner['revision'] as int,
            ),
            _ => throw const FormatException('Unknown content owner'),
          },
          key: target['key'] as String,
        );
      default:
        throw const FormatException('Unknown content target');
    }
    return ContentRef(
      databaseId: value['databaseId'] as String,
      target: decoded,
    );
  }
}

final class ChatBodyPresentation {
  const ChatBodyPresentation({
    required this.key,
    required this.byteLength,
    this.inline,
    this.reference,
  });
  final String key;
  final int byteLength;
  final Uint8List? inline;
  final ContentRef? reference;
}
