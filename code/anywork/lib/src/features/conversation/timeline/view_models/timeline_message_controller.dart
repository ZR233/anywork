import 'dart:developer' as developer;

import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_image_resources.dart';

/// A stateless adapter to Flyer's sole loaded-message collection. The SDK
/// serializes admission; this adapter does not retain items or grouping indexes.
final class TimelineMessageController implements ConversationBatchConsumer {
  TimelineMessageController(
    this.controller, {
    required this.generation,
    required this.imageResources,
  });

  final InMemoryChatController controller;
  final int generation;
  final TimelineImageResources imageResources;
  bool _disposed = false;

  int get length => controller.messages.length;

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    if (_disposed) throw StateError('Timeline display is retired');
    final messages = batch.messages
        .map((item) {
          final value = ChatItemPresentation.decode(item);
          return Message.custom(
            id: item.id,
            authorId: value.authorId,
            createdAt: value.createdAt,
            metadata: {chatItemPresentationKey: value},
          );
        })
        .toList(growable: false);
    switch (batch.placement) {
      case ChatPlacement.set:
        await controller.setMessages(messages, animated: false);
      case ChatPlacement.prepend:
        if (messages.isNotEmpty) {
          await controller.insertAllMessages(
            messages,
            index: 0,
            animated: false,
          );
        }
      case ChatPlacement.append:
        if (messages.isNotEmpty) await controller.insertAllMessages(messages);
    }
    developer.Timeline.instantSync(
      'conversation.applied',
      arguments: {
        'generation': generation,
        'placement': batch.placement.name,
        'decodedItems': messages.length,
        'controllerMessages': controller.messages.length,
      },
    );
  }

  void dispose() => _disposed = true;
}
