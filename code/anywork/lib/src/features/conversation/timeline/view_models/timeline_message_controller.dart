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
  Future<void> _admission = Future.value();
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

  Future<void> applyBlocks(List<DisplayBlock> blocks, ChatPlacement placement) {
    if (_disposed || _retired) throw const StaleConversationScope();
    if (placement == ChatPlacement.append && blocks.isEmpty) {
      return Future.value();
    }
    return _serialize(() => _applyBlocks(blocks, placement));
  }

  Future<void> _applyBlocks(
    List<DisplayBlock> blocks,
    ChatPlacement placement,
  ) {
    if (_disposed || _retired) throw const StaleConversationScope();
    final messages = [for (final block in blocks) _message(block)];
    final previousUnits = placement == ChatPlacement.set
        ? [for (final message in controller.messages) _unitOf(message)]
        : const <TimelineDisplayUnit>[];
    final Future<void> applied;
    switch (placement) {
      case ChatPlacement.set:
        applied = controller.setMessages(messages, animated: false);
      case ChatPlacement.prepend:
      case ChatPlacement.append:
        if (messages.isNotEmpty) {
          applied = controller.insertAllMessages(
            messages,
            index: placement == ChatPlacement.prepend ? 0 : null,
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
      for (final message in messages) {
        final unit = _unitOf(message);
        unit.expansion.current = unit;
        onUnitCreated?.call(unit);
      }
      developer.Timeline.instantSync(
        'conversation.applied',
        arguments: {
          'generation': generation,
          'placement': placement.name,
          'acceptedBlocks': blocks.length,
          'controllerMessages': length,
        },
      );
    });
  }

  /// Replaces rows by stable row identity and appends genuinely new anchors.
  ///
  /// This is one controller admission and one serial Flyer mutation.
  Future<void> replaceBlocks(List<DisplayBlock> blocks) {
    if (_disposed || _retired) throw const StaleConversationScope();
    return _serialize(() => _replaceBlocks(blocks));
  }

  Future<void> _replaceBlocks(List<DisplayBlock> blocks) async {
    final existingById = {
      for (final message in controller.messages) message.id: message,
    };
    final appended = <Message>[];
    for (final block in blocks) {
      final next = _message(block);
      final old = existingById[block.id];
      if (old == null) {
        appended.add(next);
        continue;
      }
      final oldUnit = _unitOf(old);
      if (sameDisplayBlock(oldUnit.block, block)) continue;
      if (_isFrozenBoundary(oldUnit) && !_isFrozenBoundary(_unitOf(next))) {
        continue;
      }
      await controller.updateMessage(old, next);
      if (_disposed || _retired) return;
      _retire(oldUnit);
      final unit = _unitOf(next);
      unit.expansion.current = unit;
      onUnitCreated?.call(unit);
    }
    if (appended.isNotEmpty) {
      await _applyBlocks(
        blocks.where((block) => existingById[block.id] == null).toList(),
        ChatPlacement.append,
      );
    }
  }

  Future<void> trimNewest(int count) {
    if (count <= 0) return Future.value();
    return _serialize(() async {
      for (var index = 0; index < count; index++) {
        if (controller.messages.isEmpty) return;
        final message = controller.messages.last;
        await controller.removeMessage(message, animated: false);
        if (_disposed || _retired) return;
        _retire(_unitOf(message));
      }
    });
  }

  Future<void> _serialize(Future<void> Function() operation) {
    final work = _admission.then((_) => operation());
    _admission = work.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return work;
  }

  bool _isFrozenBoundary(TimelineDisplayUnit unit) {
    final body = unit.body;
    return body is SingleDisplayBlock &&
        body.record.contentSource is FrozenObservation;
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
