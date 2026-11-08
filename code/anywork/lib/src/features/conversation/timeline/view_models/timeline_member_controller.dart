import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';

/// Member/real-Children adapter. Atom IDs update only this independently owned
/// window; they never enter the Main item mapper or rewrite a group summary.
final class TimelineMemberController implements ConversationBatchConsumer {
  TimelineMemberController(this.controller);
  final InMemoryChatController controller;
  bool _disposed = false;

  Message _message(ChatAtom atom) {
    final presentation = atom.payload == null
        ? ChatItemPresentation(
            id: atom.id,
            compatibility: ChatItemCompatibility.current,
            type: 'memberAtom',
            data: const {},
            bodies: const [],
            atom: atom,
          )
        : ChatItemPresentation.decode(atom);
    return Message.custom(
      id: atom.id,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {chatItemPresentationKey: presentation},
    );
  }

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    if (_disposed) throw const StaleConversationScope();
    if (batch.placement == ChatPlacement.update) {
      throw const ConversationContinuityError(
        'Header updates belong only to Main',
      );
    }
    if (batch.current != null) {
      throw const ConversationContinuityError(
        'Member windows cannot contain current projections',
      );
    }
    if (batch.entries.any((entry) => entry is ItemChatEntry)) {
      throw const ConversationContinuityError(
        'Member windows cannot contain Main items',
      );
    }
    final atoms = batch.atoms.toList();
    final messages = [for (final atom in atoms) _message(atom)];
    if (batch.placement == ChatPlacement.set) {
      await controller.setMessages(messages, animated: false);
    } else if (messages.isNotEmpty) {
      final inserted = <Message>[];
      final loadedById = <String, Message>{};
      for (final message in controller.messages) {
        loadedById[message.id] = message;
      }
      final pendingIndexById = <String, int>{};
      for (final message in messages) {
        final previous = loadedById[message.id];
        if (previous != null) {
          await controller.updateMessage(previous, message);
          loadedById[message.id] = message;
          continue;
        }
        final pendingIndex = pendingIndexById[message.id];
        if (pendingIndex != null) {
          inserted[pendingIndex] = message;
        } else {
          pendingIndexById[message.id] = inserted.length;
          inserted.add(message);
        }
      }
      if (inserted.isNotEmpty) {
        await controller.insertAllMessages(
          inserted,
          index: batch.placement == ChatPlacement.prepend
              ? 0
              : controller.messages.length,
          animated: false,
        );
      }
    }
  }

  void dispose() => _disposed = true;
}
