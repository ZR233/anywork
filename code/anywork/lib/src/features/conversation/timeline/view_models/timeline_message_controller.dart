import 'dart:developer' as developer;

import 'package:anywork_client/conversation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_display_unit.dart';

/// The component controller alone owns loaded immutable blocks. No tail folding.
final class TimelineMessageController {
  TimelineMessageController(
    this.controller, {
    required this.generation,
    this.onUnitCreated,
    this.onUnitRetired,
    this.expansionForBlock,
  });

  final InMemoryChatController controller;
  final int generation;
  final void Function(TimelineDisplayUnit)? onUnitCreated;
  final void Function(TimelineDisplayUnit)? onUnitRetired;
  final TimelineExpansionIntent Function(String)? expansionForBlock;
  bool _disposed = false;
  bool _retired = false;
  int? _through;
  int? _firstPosition;
  final Set<String> _loadedIds = {};
  int get length => controller.messages.length;

  TimelineDisplayUnit _unitOf(Message message) =>
      message.metadata![timelineDisplayUnitKey] as TimelineDisplayUnit;

  Message _message(DisplayBlock block) {
    final unit = TimelineDisplayUnit(
      block: block,
      expansion: expansionForBlock?.call(block.id),
    );
    final presentation = ChatItemPresentation.forUnit(unit);
    return Message.custom(
      id: block.id,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {
        chatItemPresentationKey: presentation,
        timelineDisplayUnitKey: unit,
      },
    );
  }

  Future<void> applyTimeline(TimelineBatch batch) {
    if (_disposed || _retired) throw const StaleConversationScope();
    if (batch.presentationVersion != presentationVersion) {
      throw const ConversationContinuityError(
        'Unsupported presentation version',
      );
    }
    final validCut = switch (batch.placement) {
      ChatPlacement.set => batch.fromPos == null,
      ChatPlacement.prepend =>
        _through != null &&
            batch.fromPos == null &&
            batch.live == null &&
            batch.throughPos <= _through!,
      ChatPlacement.append =>
        _through != null &&
            batch.fromPos == _through &&
            batch.throughPos >= _through! &&
            batch.before == null,
    };
    var previous = batch.fromPos ?? 0;
    final ids = <String>{};
    var valid = validCut && batch.throughPos >= 0;
    for (final block in batch.blocks) {
      valid =
          valid &&
          block.id.isNotEmpty &&
          ids.add(block.id) &&
          (batch.placement == ChatPlacement.set ||
              !_loadedIds.contains(block.id)) &&
          block.historyPos > previous &&
          block.historyPos <= batch.throughPos;
      previous = block.historyPos;
    }
    if (!valid) {
      throw const ConversationContinuityError('Invalid display block page');
    }
    // Pure live frames do not even inspect the existing Main collection.
    if (batch.placement == ChatPlacement.append && batch.blocks.isEmpty) {
      if (batch.throughPos != _through) {
        throw const ConversationContinuityError(
          'Pure live frame advanced history',
        );
      }
      return Future.value();
    }
    if (batch.placement == ChatPlacement.prepend &&
        batch.blocks.isNotEmpty &&
        _firstPosition != null &&
        batch.blocks.last.historyPos >= _firstPosition!) {
      throw const ConversationContinuityError('Display pages overlap');
    }
    final messages = [for (final block in batch.blocks) _message(block)];
    final previousUnits = batch.placement == ChatPlacement.set
        ? [for (final message in controller.messages) _unitOf(message)]
        : const <TimelineDisplayUnit>[];
    final Future<void> applied;
    switch (batch.placement) {
      case ChatPlacement.set:
        applied = controller.setMessages(messages, animated: false);
      case ChatPlacement.prepend:
      case ChatPlacement.append:
        if (messages.isNotEmpty) {
          applied = controller.insertAllMessages(
            messages,
            index: batch.placement == ChatPlacement.prepend ? 0 : null,
            animated: false,
          );
        } else {
          applied = Future.value();
        }
    }
    // The component's async methods may return a failed Future even when their
    // validation runs before the call returns. Do not commit shared intentions,
    // position or callbacks until that original Future succeeds.
    return applied.then((_) {
      // A successful component operation may re-enter selection through its
      // operation stream. Its retired owner must not publish the late success;
      // the original failed Future still propagates without this success path.
      if (_disposed || _retired) return;
      for (final unit in previousUnits) {
        _retire(unit);
      }
      if (batch.placement == ChatPlacement.set) {
        _loadedIds.clear();
        _firstPosition = batch.blocks.firstOrNull?.historyPos;
      } else if (batch.blocks.isNotEmpty) {
        _firstPosition = batch.placement == ChatPlacement.prepend
            ? batch.blocks.first.historyPos
            : _firstPosition ?? batch.blocks.first.historyPos;
      }
      _loadedIds.addAll(ids);
      if (batch.placement != ChatPlacement.prepend) _through = batch.throughPos;
      for (final message in messages) {
        final unit = _unitOf(message);
        unit.expansion.current = unit;
        onUnitCreated?.call(unit);
      }
      developer.Timeline.instantSync(
        'conversation.applied',
        arguments: {
          'generation': generation,
          'placement': batch.placement.name,
          'acceptedBlocks': batch.blocks.length,
          'controllerMessages': length,
        },
      );
    });
  }

  void _retire(TimelineDisplayUnit unit) {
    unit.expansion.retire();
    onUnitRetired?.call(unit);
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
