import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import 'chat_payload_reading.dart';
import 'timeline_display_unit.dart';
import '../tools/tool_item_registry.dart';

const chatItemPresentationKey = 'chatItemPresentation';

ChatItemPresentation? chatItemPresentationOf(Message message) =>
    message.metadata?[chatItemPresentationKey] as ChatItemPresentation?;

enum ChatItemCompatibility { current, unknown, malformed, deferred }

/// The immutable render value carried by one Flyer message.
final class ChatItemPresentation {
  ChatItemPresentation({
    required this.id,
    required this.compatibility,
    required this.type,
    required this.data,
    required this.bodies,
    this.raw,
    this.createdAt,
    this.authorId = 'unknown',
    this.presentationContract,
    this.diagnostic,
    this.displayUnit,
    this.finalTurnDelivery = false,
    this.recoveryNotice,
    this.toolCallId,
    this.turnId,
  });

  final String id;
  final ChatItemCompatibility compatibility;
  final String type;
  final Map<String, Object?> data;
  final List<ChatBodyPresentation> bodies;
  final String? raw;
  final DateTime? createdAt;
  final String authorId;
  final String? presentationContract;
  final String? diagnostic;
  final TimelineDisplayUnit? displayUnit;
  final bool finalTurnDelivery;
  final StudioModelRecoveryNotice? recoveryNotice;
  final String? toolCallId;
  final String? turnId;

  bool get showsTextCopy =>
      authorId == 'user' || authorId == 'parentAgent' || finalTurnDelivery;

  bool get isKnownEmptyText =>
      !finalTurnDelivery &&
      type == 'text' &&
      compatibility == ChatItemCompatibility.current &&
      modelRecovery == null &&
      bodies.every((body) => body.byteLength == 0) &&
      switch (data['attachments']) {
        null || [] => true,
        _ => false,
      };
  late final ToolCardReading toolCard = readToolCard(this);
  late final StudioModelRecoveryNotice? modelRecovery =
      recoveryNotice ??
      (compatibility == ChatItemCompatibility.current && type == 'text'
          ? StudioModelRecoveryNotice.fromJson(data['modelRecovery'])
          : null);

  bool get presentsFiles => timelineToolItemRegistry
      .resolveForChatItem(this)
      .presentsStandaloneMedia(this);
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
        bodies.add(
          ChatBodyPresentation(
            key: body['key'] as String,
            byteLength: body['byteLength'] as int,
            mediaType: rawMediaType as String?,
            inline: inlineBytes,
            inlineText: inlineText as String?,
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
    this.feedReference,
  });
  final String key;
  final int byteLength;
  final String? mediaType;
  final Uint8List? inline;
  final String? inlineText;
  final BodyRef? feedReference;
  bool get hasInline => inlineText != null || inline != null;
  String? get text =>
      inlineText ?? (inline == null ? null : utf8.decode(inline!));
  bool get hasReference => feedReference != null;
}
