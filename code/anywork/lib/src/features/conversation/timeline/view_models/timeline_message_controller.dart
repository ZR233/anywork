import 'dart:developer' as developer;

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/chat_item_presentation.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_unit.dart';

/// Main's mechanical admission adapter. Loaded history belongs exclusively to
/// InMemoryChatController; only the bounded current item fragment lives here.
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
  final ValueNotifier<List<TimelineDisplayUnit>> live = ValueNotifier(const []);
  bool _disposed = false;
  bool _retired = false;
  int get length => controller.messages.length;

  Iterable<TimelineDisplayUnit> get _history sync* {
    for (final message in controller.messages) {
      final unit = message.metadata?[timelineDisplayUnitKey];
      if (unit is TimelineDisplayUnit) yield unit;
    }
  }

  TimelineDisplayUnit _unit(
    TimelineItem item, {
    required bool current,
    bool borrowCurrentIntent = true,
    TimelineDisplayUnit? previousUnit,
  }) {
    // Borrow intent only from the bounded current fragment at handoff. There
    // is deliberately no permanent history-ID or member-ID map.
    final previous =
        previousUnit ??
        (borrowCurrentIntent
            ? live.value
                  .where(
                    (unit) => unit.id == item.id && !unit.expansion.isRetired,
                  )
                  .firstOrNull
            : null);
    final unit = TimelineDisplayUnit(
      item: item,
      live: current,
      expansion: previous?.expansion,
    );
    unit.expansion.current = unit;
    if (previous != null &&
        (previous.item.members != item.members ||
            !listEquals(
              _bodyCapabilities(previous.item),
              _bodyCapabilities(item),
            ))) {
      unit.expansion.replaceBody();
    }
    if (previous == null) onUnitCreated?.call(unit);
    return unit;
  }

  List<Object> _bodyCapabilities(TimelineItem item) => [
    item.payload != null,
    for (final content in item.contents)
      (content.role, contentReferenceIdentity(content.reference)),
    if (item.payload case DeferredPayload(:final reference))
      contentReferenceIdentity(reference),
  ];

  Message _message(TimelineDisplayUnit unit) {
    final presentation = ChatItemPresentation.forUnit(unit);
    return Message.custom(
      id: unit.id,
      authorId: presentation.authorId,
      createdAt: presentation.createdAt,
      metadata: {
        chatItemPresentationKey: presentation,
        timelineDisplayUnitKey: unit,
      },
    );
  }

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    _checkActive();
    if (batch.entries.any((entry) => entry is! ItemChatEntry)) {
      throw const ConversationContinuityError(
        'Main accepts only TimelineItem entries',
      );
    }
    final items = batch.items.toList();
    final ids = items.map((item) => item.id).toSet();
    if (ids.length != items.length) {
      throw const ConversationContinuityError('Duplicate Main item identity');
    }
    if (batch.placement == ChatPlacement.update) {
      if (batch.before != null || batch.current != null || items.isEmpty) {
        throw const ConversationContinuityError('Invalid Main header update');
      }
      final replacements = <(Message, TimelineDisplayUnit, TimelineItem)>[];
      for (final item in items) {
        final message = controller.messages
            .where((message) => message.id == item.id)
            .firstOrNull;
        final previous = message?.metadata?[timelineDisplayUnitKey];
        if (message == null ||
            previous is! TimelineDisplayUnit ||
            previous.item.kind != TimelineItemKind.workGroup ||
            previous.item.delivery != ChatDeliveryKind.independent ||
            previous.item.source is! BackgroundResultChatSource ||
            item.kind != previous.item.kind ||
            item.delivery != previous.item.delivery ||
            item.source != previous.item.source ||
            item.position != previous.item.position ||
            item.members != previous.item.members ||
            item.turnId != previous.item.turnId) {
          throw const ConversationContinuityError(
            'Main header update changed or lost its group identity',
          );
        }
        replacements.add((message, previous, item));
      }
      for (final (message, previous, item) in replacements) {
        if (_retired) return;
        await controller.updateMessage(
          message,
          _message(
            _unit(
              item,
              current: false,
              borrowCurrentIntent: false,
              previousUnit: previous,
            ),
          ),
        );
      }
      return;
    }
    if (batch.placement == ChatPlacement.set) {
      for (final unit in [
        ..._history,
        if (batch.current != null) ...live.value,
      ]) {
        _retire(unit);
      }
    }
    if (batch.placement != ChatPlacement.set && items.isNotEmpty) {
      final loadedIds = <String>{
        for (final message in controller.messages) message.id,
      };
      if (items.any((item) => loadedIds.contains(item.id))) {
        throw const ConversationContinuityError(
          'Main item was already committed',
        );
      }
    }
    final messages = [
      for (final item in items)
        _message(
          _unit(
            item,
            current: false,
            borrowCurrentIntent: batch.current != null,
          ),
        ),
    ];
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
        if (messages.isNotEmpty) {
          await controller.insertAllMessages(
            messages,
            index: controller.messages.length,
          );
        }
      case ChatPlacement.update:
        throw StateError('Header updates are applied before insertion');
    }
    // The public component operation may synchronously trigger selection
    // retirement. Its successful completion must join the old admission, not
    // reactivate that display or publish current after losing qualification.
    if (_retired) return;
    if (batch.current case final current?) {
      final next = [
        for (final item in current.items) _unit(item, current: true),
      ];
      final retained = {...ids, ...next.map((unit) => unit.id)};
      for (final unit in live.value) {
        if (!retained.contains(unit.id)) _retire(unit);
      }
      live.value = List.unmodifiable(next);
    }
    developer.Timeline.instantSync(
      'conversation.applied',
      arguments: {
        'generation': generation,
        'placement': batch.placement.name,
        'acceptedEntries': items.length,
        'controllerMessages': length,
        'liveUnits': live.value.length,
      },
    );
  }

  void _retire(TimelineDisplayUnit unit) {
    unit.expansion.retire();
    onUnitRetired?.call(unit);
  }

  void _checkActive() {
    if (_disposed || _retired) {
      throw StateError('Timeline message controller is retired');
    }
  }

  /// Revoke group/body/media qualification before the old widget tree detaches.
  /// Controller disposal still waits for the owner's in-flight mutations.
  void retireDisplays() {
    if (_retired) return;
    _retired = true;
    for (final unit in [..._history, ...live.value]) {
      _retire(unit);
    }
  }

  void dispose() {
    if (_disposed) return;
    retireDisplays();
    _disposed = true;
    live.dispose();
  }
}
