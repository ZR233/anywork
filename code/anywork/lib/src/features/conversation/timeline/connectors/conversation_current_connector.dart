import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart'
    show ConversationActivityView, ConversationActivityKind;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_activity_clock.dart';
import '../widgets/timeline_activity_section.dart';
import '../widgets/timeline_display_unit_view.dart';
import 'timeline_content_connector.dart';
import 'timeline_group_members_connector.dart';
import 'timeline_media_connector.dart';

/// Renders every admitted current item in producer order, including a later
/// response while an earlier group still has active members. No atomic reducer.
class ConversationCurrentConnector extends StatefulWidget {
  const ConversationCurrentConnector({
    required this.current,
    required this.content,
    required this.view,
    required this.units,
    required this.images,
    required this.readAttachment,
    required this.isDisplayActive,
    this.registerDisplay,
    this.onExpandedChanged,
    super.key,
  });
  final CurrentProjection current;
  final ConversationContent content;
  final ConversationActivityView? view;
  final ValueListenable<List<TimelineDisplayUnit>> units;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  final bool Function() isDisplayActive;
  final VoidCallback Function(TimelineCurrentDisplay)? registerDisplay;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<ConversationCurrentConnector> createState() => _CurrentState();
}

class _CurrentState extends State<ConversationCurrentConnector>
    implements TimelineCurrentDisplay {
  final Set<_CurrentItemState> _items = {};
  VoidCallback? _unregister;
  bool _disposed = false;
  @override
  bool get isCurrent => mounted && !_disposed && widget.isDisplayActive();
  @override
  String? get turnId => isCurrent ? widget.current.activeTurn?.id : null;
  @override
  String? get activityId => isCurrent ? widget.current.active?.id : null;
  @override
  bool get expanded =>
      isCurrent &&
      widget.units.value.any((unit) => unit.expansion.expanded ?? false);
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final item in _items) {
      if (!item.active) continue;
      yield* item.owner?.windows ?? const [];
      yield* item.ranges;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.units.addListener(_changed);
    _unregister = widget.registerDisplay?.call(this);
  }

  void _changed() {
    final ids = widget.units.value.map((unit) => unit.id).toSet();
    for (final item in List.of(_items)) {
      if (!ids.contains(item.widget.unit.id)) item.retire();
    }
    if (mounted && !_disposed) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.units, widget.units) ||
        !identical(oldWidget.content, widget.content)) {
      throw StateError('Current display cannot change its original lease');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.units.removeListener(_changed);
    for (final item in List.of(_items)) {
      item.retire();
    }
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final units = isCurrent
        ? widget.units.value
        : const <TimelineDisplayUnit>[];
    final view = widget.view;
    if (units.isEmpty && view == null) return const SizedBox.shrink();
    return ConversationActivityBar(
      children: [
        if (view != null &&
            (units.isEmpty ||
                view.kind == ConversationActivityKind.storageBlocked ||
                view.kind == ConversationActivityKind.stopping))
          ConversationActivityStatus(view: view),
        for (final unit in units)
          KeyedSubtree(
            key: ValueKey(unit.id),
            child: unit.item.kind == TimelineItemKind.workGroup
                ? TimelineDisplayUnitView(
                    key: ObjectKey(unit.expansion),
                    unit: unit,
                    executionPresent: widget.current.executionPresent,
                    onExpandedChanged: widget.onExpandedChanged,
                    childBuilder: (_) => TimelineGroupMembersConnector(
                      unit: unit,
                      threadId: widget.images.threadId,
                      readAttachment: widget.readAttachment,
                    ),
                  )
                : _CurrentItem(
                    key: ObjectKey(unit.expansion),
                    unit: unit,
                    content: widget.content,
                    executionPresent: widget.current.executionPresent,
                    isActive: widget.isDisplayActive,
                    images: widget.images,
                    readAttachment: widget.readAttachment,
                    mountedItems: _items,
                  ),
          ),
      ],
    );
  }
}

class _CurrentItem extends StatefulWidget {
  const _CurrentItem({
    super.key,
    required this.unit,
    required this.content,
    required this.executionPresent,
    required this.isActive,
    required this.images,
    required this.readAttachment,
    required this.mountedItems,
  });
  final TimelineDisplayUnit unit;
  final bool executionPresent;
  final ConversationContent content;
  final bool Function() isActive;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  final Set<_CurrentItemState> mountedItems;
  @override
  State<_CurrentItem> createState() => _CurrentItemState();
}

class _CurrentItemState extends State<_CurrentItem> {
  ConversationCurrentOwner? owner;
  ConversationQueryScope? _scope;
  late Object _bodyGeneration;
  final Set<TimelineCurrentWindowDisplay> ranges = {};
  bool _retired = false;
  bool get active =>
      mounted &&
      !_retired &&
      widget.isActive() &&
      !widget.unit.expansion.isRetired;
  @override
  void initState() {
    super.initState();
    widget.mountedItems.add(this);
    _bodyGeneration = widget.unit.expansion.bodyGeneration;
    widget.unit.expansion.addListener(_intentChanged);
    _observe();
  }

  void _intentChanged() {
    final intent = widget.unit.expansion;
    if (intent.isRetired) {
      retire();
      return;
    }
    if (!identical(_bodyGeneration, intent.bodyGeneration)) {
      _bodyGeneration = intent.bodyGeneration;
      _closeRanges();
    }
    _observe();
  }

  void _observe() {
    if (!active) return;
    // Admission updates the intent before notifying, while widget.unit still
    // belongs to the previous layout. Revoke old sources in that same call.
    final unit = widget.unit.expansion.current ?? widget.unit;
    if (unit.item.payload != null) {
      _closeBody();
      return;
    }
    owner ??= ConversationCurrentOwner(widget.content);
    owner!.synchronizeSources([
      for (final content in unit.item.contents)
        CurrentWindowSource(
          id: unit.id,
          reference: content.reference,
          text: '',
        ),
    ]);
  }

  @override
  void didUpdateWidget(covariant _CurrentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.unit.expansion, widget.unit.expansion)) {
      throw StateError('A mounted current item cannot change its intent');
    }
    _observe();
  }

  void _closeBody() {
    final old = owner;
    owner = null;
    if (old != null) {
      unawaited(old.close());
      old.dispose();
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _closeBody();
    _bodyGeneration = Object();
    _closeRanges();
  }

  void _closeRanges() {
    _scope?.retire();
    if (_scope != null) unawaited(_scope!.close());
    _scope = null;
    ranges.clear();
  }

  @override
  void dispose() {
    widget.mountedItems.remove(this);
    widget.unit.expansion.removeListener(_intentChanged);
    retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.unit.item;
    if (item.kind == TimelineItemKind.text) {
      return ConversationResponseView(
        startedAt: item.startedAt,
        finishedAt: item.finishedAt,
        active: widget.executionPresent && item.outcome == null,
        child: _buildContent(context),
      );
    }
    return _buildContent(context);
  }

  Widget _buildContent(BuildContext context) {
    final generation = _bodyGeneration;
    bool bodyActive() => active && identical(generation, _bodyGeneration);
    if (widget.unit.item.payload != null) {
      return ChatItemView(
        item: ChatItemPresentation.forUnit(widget.unit),
        isDisplayActive: bodyActive,
        attachmentBuilder: (item) => TimelineAttachmentsConnector(
          item: item,
          resources: widget.images,
          readAttachment: widget.readAttachment,
          isActive: bodyActive,
        ),
        contentRangeBuilder: (id, key, label, reference, witness) =>
            TimelineContentRangeConnector(
              key: ValueKey((id, key, generation)),
              itemId: id,
              contentKey: key,
              label: label,
              reference: reference,
              witness: witness,
              isDisplayActive: bodyActive,
              registerDisplay: (display) {
                if (!bodyActive()) return () {};
                ranges.add(display);
                return () => ranges.remove(display);
              },
              readContent: (reference, range) {
                if (!bodyActive()) {
                  return Future.error(const StaleConversationScope());
                }
                return (_scope ??= widget.content.openScope(
                  generation: 1,
                )).readContent(reference: reference, range: range);
              },
            ),
      );
    }
    final item = widget.unit.item;
    if (widget.unit.live &&
        widget.executionPresent &&
        item.kind == TimelineItemKind.status &&
        item.atomKind == ChatAtomKind.compaction &&
        item.outcome == null) {
      return TimelineActivitySection(
        header: TimelineActivityClock(
          startedAt: item.startedAt,
          running: true,
          builder: (context, seconds) => TimelineActivityRow(
            label: context.l10n.conversationActivityCompacting,
            icon: Icons.compress_outlined,
            active: true,
            expandable: false,
            header: true,
            meta: seconds == null
                ? null
                : activityDurationLabel(context, seconds),
          ),
        ),
      );
    }
    final body = owner;
    if (body == null || widget.unit.item.contents.isEmpty) {
      return const Text('内容状态未知');
    }
    return ListenableBuilder(
      listenable: body,
      builder: (_, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (body.cleanupError != null) Text(body.cleanupError.toString()),
          for (final window in body.windows)
            ConversationCurrentWindowView(
              id: window.id,
              text: window.window == null
                  ? window.source.text
                  : utf8.decode(window.window!.bytes, allowMalformed: true),
              error: window.error,
              offset: window.window?.offset,
              end: window.window == null
                  ? null
                  : window.window!.offset + window.window!.bytes.length,
              availableThrough: window.window?.availableThrough,
              onFirst: () => body.firstWindow(window),
              onNext: () => body.nextWindow(window),
            ),
        ],
      ),
    );
  }
}
