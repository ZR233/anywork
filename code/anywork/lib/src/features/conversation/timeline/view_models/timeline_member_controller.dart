import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';

/// Completed Run/Children records are immutable. No member update or activity
/// state machine, and no write back to the Main representative's ordinal.
final class TimelineMemberController implements ConversationBatchConsumer {
  TimelineMemberController(this.controller);
  final InMemoryChatController controller;
  bool _disposed = false;
  int? _through;

  Message _message(CompletedEntry entry) {
    final atom = entry.atom;
    final presentation = atom.payload == null
        ? ChatItemPresentation(
            id: entry.recordId,
            compatibility: ChatItemCompatibility.current,
            type: 'memberAtom',
            data: const {},
            bodies: const [],
            atom: atom,
          )
        : ChatItemPresentation.decode(
            atom,
            displayId: entry.recordId,
            record: DisplayRecord(
              atom: atom,
              contentSource: CompletedOriginal(completionId: entry.recordId),
            ),
          );
    return Message.custom(
      id: entry.recordId,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {chatItemPresentationKey: presentation},
    );
  }

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    if (_disposed) throw const StaleConversationScope();
    if (batch.placement == ChatPlacement.append &&
        (_through == null ||
            batch.fromSeq == null ||
            batch.fromSeq! < _through! ||
            batch.throughSeq <= _through!)) {
      throw const ConversationContinuityError('Invalid member completion cut');
    }
    var seq = batch.fromSeq ?? 0;
    final ids = <String>{};
    for (final entry in batch.entries) {
      if (entry.atom.lifecycle is! TerminalChatAtom ||
          entry.completionSeq <= seq ||
          entry.completionSeq > batch.throughSeq ||
          !ids.add(entry.recordId)) {
        throw const ConversationContinuityError('Invalid completed member');
      }
      seq = entry.completionSeq;
    }
    if (batch.placement != ChatPlacement.set && batch.entries.isNotEmpty) {
      final loaded = {for (final message in controller.messages) message.id};
      if (ids.any(loaded.contains)) {
        throw const ConversationContinuityError('Repeated completed member');
      }
    }
    final messages = [for (final entry in batch.entries) _message(entry)];
    switch (batch.placement) {
      case ChatPlacement.set:
        await controller.setMessages(messages, animated: false);
      case ChatPlacement.prepend:
      case ChatPlacement.append:
        if (messages.isNotEmpty) {
          await controller.insertAllMessages(
            messages,
            index: batch.placement == ChatPlacement.prepend
                ? 0
                : controller.messages.length,
            animated: false,
          );
        }
    }
    if (batch.placement != ChatPlacement.prepend) _through = batch.throughSeq;
  }

  void dispose() => _disposed = true;

  @override
  Future<void> applyActivity(ActivitySnapshot snapshot) async {
    if (_disposed) throw const StaleConversationScope();
    // Every scope receives Activity barriers. This completed-member renderer
    // accepts them without projecting live operations into its history.
  }
}
