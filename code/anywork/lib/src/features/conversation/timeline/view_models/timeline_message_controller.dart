import 'dart:developer' as developer;

import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';
import '../state/completion_run_presentation.dart';
import '../state/timeline_display_unit.dart';

/// The only Main combination adapter. The public chat controller exclusively
/// owns loaded cards; Append reads only its tail, and never sorts or deduplicates.
final class TimelineMessageController implements ConversationBatchConsumer {
  TimelineMessageController(
    this.controller, {
    required this.generation,
    this.onUnitCreated,
    this.onUnitRetired,
  });

  final InMemoryChatController controller;
  final int generation;
  final void Function(TimelineDisplayUnit)? onUnitCreated;
  final void Function(TimelineDisplayUnit)? onUnitRetired;
  bool _disposed = false;
  bool _retired = false;
  int? _through;
  int get length => controller.messages.length;

  TimelineDisplayUnit _unitOf(Message message) =>
      message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;

  TimelineDisplayUnit _unit(
    CompletedEntry entry, {
    TimelineDisplayUnit? previous,
  }) {
    final run = switch (entry.mainPresentation) {
      MainPresentation.foregroundWork || MainPresentation.backgroundResults =>
        CompletionRunPresentation.fromEntry(entry),
      MainPresentation.single => null,
      MainPresentation.hidden => throw const ConversationContinuityError(
        'Main cannot contain Hidden records',
      ),
    };
    final unit = TimelineDisplayUnit(
      entry: entry,
      run: run,
      expansion: previous?.expansion,
    );
    unit.expansion.current = unit;
    if (previous == null) onUnitCreated?.call(unit);
    return unit;
  }

  Message _message(TimelineDisplayUnit unit) {
    final presentation = ChatItemPresentation.forUnit(unit);
    return Message.custom(
      id: unit.id,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {
        chatItemPresentationKey: presentation,
        timelineDisplayUnitKey: unit,
        completionRunPresentationKey: ?unit.run,
      },
    );
  }

  void _validateEntry(CompletedEntry entry) {
    final run = entry.run;
    if (entry.mainPresentation == MainPresentation.hidden ||
        run == null ||
        run.startSeq <= 0 ||
        run.startSeq > entry.completionSeq ||
        run.ordinal <= 0 ||
        run.ordinal > entry.completionSeq - run.startSeq + 1 ||
        entry.completionSeq <= 0 ||
        entry.recordId.isEmpty ||
        (entry.atom.completionItemId != null &&
            entry.atom.completionItemId != entry.recordId) ||
        (entry.atom.completionSeq != null &&
            entry.atom.completionSeq != entry.completionSeq) ||
        entry.atom.lifecycle is! TerminalChatAtom ||
        (entry.mainPresentation == MainPresentation.single &&
            (run.startSeq != entry.completionSeq || run.ordinal != 1))) {
      throw const ConversationContinuityError('Invalid Main completion');
    }
    if (entry.mainPresentation != MainPresentation.single) {
      CompletionRunPresentation.fromEntry(entry);
    }
  }

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    if (_disposed || _retired) {
      throw const StaleConversationScope();
    }
    if (batch.placement == ChatPlacement.append) {
      if (_through == null ||
          batch.fromSeq == null ||
          batch.fromSeq! < _through! ||
          batch.throughSeq <= _through! ||
          batch.before != null) {
        throw const ConversationContinuityError('Invalid Main completion cut');
      }
    } else if (batch.fromSeq != null ||
        (batch.placement == ChatPlacement.prepend && _through == null)) {
      throw const ConversationContinuityError('Invalid Main page cut');
    }
    if (batch.placement == ChatPlacement.append && batch.entries.isEmpty) {
      _through = batch.throughSeq;
      return;
    }
    // Validate all entries before mutating the public component. This visits
    // only the incoming batch and, for Append, the single existing tail card.
    int previousSeq = batch.fromSeq ?? 0;
    TimelineDisplayUnit? tail =
        batch.placement == ChatPlacement.append &&
            controller.messages.isNotEmpty
        ? _unitOf(controller.messages.last)
        : null;
    CompletedEntry? previous = tail?.entry;
    final recordIds = <String>{};
    for (final entry in batch.entries) {
      _validateEntry(entry);
      if (entry.completionSeq <= previousSeq ||
          entry.completionSeq > batch.throughSeq ||
          !recordIds.add(entry.recordId)) {
        throw const ConversationContinuityError('Unordered completion batch');
      }
      final prior = previous;
      if (batch.placement == ChatPlacement.append &&
          entry.run!.startSeq != prior?.run?.startSeq &&
          (entry.run!.startSeq != entry.completionSeq ||
              entry.run!.ordinal != 1)) {
        throw const ConversationContinuityError('Invalid new completion Run');
      }
      if (prior != null) {
        final start = entry.run!.startSeq;
        final priorStart = prior.run!.startSeq;
        if (start < priorStart ||
            entry.recordId == prior.recordId ||
            (start == priorStart &&
                (batch.placement != ChatPlacement.append ||
                    entry.mainPresentation == MainPresentation.single ||
                    entry.mainPresentation != prior.mainPresentation ||
                    entry.run!.ordinal != prior.run!.ordinal + 1))) {
          throw const ConversationContinuityError(
            'Non-contiguous completion Run',
          );
        }
        if (start == priorStart &&
            tail?.run != null &&
            CompletionRunPresentation.fromEntry(entry).reference.databaseId !=
                tail!.run!.reference.databaseId) {
          throw const ConversationContinuityError(
            'Completion database changed',
          );
        }
      }
      previousSeq = entry.completionSeq;
      previous = entry;
    }
    if (batch.placement == ChatPlacement.prepend &&
        batch.entries.isNotEmpty &&
        controller.messages.isNotEmpty &&
        batch.entries.last.completionSeq >=
            _unitOf(controller.messages.first).entry.run!.startSeq) {
      throw const ConversationContinuityError('Main pages overlap');
    }

    switch (batch.placement) {
      case ChatPlacement.set:
        for (final message in controller.messages) {
          _retire(_unitOf(message));
        }
        await controller.setMessages([
          for (final entry in batch.entries) _message(_unit(entry)),
        ], animated: false);
      case ChatPlacement.prepend:
        if (batch.entries.isNotEmpty) {
          await controller.insertAllMessages(
            [for (final entry in batch.entries) _message(_unit(entry))],
            index: 0,
            animated: false,
          );
        }
      case ChatPlacement.append:
        for (final entry in batch.entries) {
          if (_retired) return;
          if (tail != null && entry.run!.startSeq == tail.entry.run!.startSeq) {
            final old = controller.messages.last;
            final next = _unit(entry, previous: tail);
            await controller.updateMessage(old, _message(next));
            tail = next;
          } else {
            final next = _unit(entry);
            await controller.insertMessage(_message(next));
            tail = next;
          }
        }
    }
    if (_retired) return;
    if (batch.placement != ChatPlacement.prepend) _through = batch.throughSeq;
    developer.Timeline.instantSync(
      'conversation.applied',
      arguments: {
        'generation': generation,
        'placement': batch.placement.name,
        'acceptedEntries': batch.entries.length,
        'controllerMessages': length,
      },
    );
  }

  void _retire(TimelineDisplayUnit unit) {
    unit.expansion.retire();
    onUnitRetired?.call(unit);
  }

  @override
  Future<void> applyActivity(ActivitySnapshot snapshot) async {
    if (_disposed || _retired) throw const StaleConversationScope();
    final identities = <ActivityIdentity>{};
    for (final entry in snapshot.entries) {
      if (entry.atom.lifecycle is! ActiveChatAtom ||
          !identities.add(entry.identity)) {
        throw const ConversationContinuityError('Invalid unfinished activity');
      }
    }
    // Activity belongs to ConversationContent.activity. In particular this
    // operation must never inspect the completed message collection.
  }

  void retireDisplays() {
    if (_retired) return;
    _retired = true;
    for (final message in controller.messages) {
      _retire(_unitOf(message));
    }
  }

  void dispose() {
    if (_disposed) return;
    retireDisplays();
    _disposed = true;
  }
}
