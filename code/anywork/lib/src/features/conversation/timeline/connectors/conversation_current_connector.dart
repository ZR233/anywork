import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart' show ConversationActivityView;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
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
  final ConversationActivityView view;
  final ValueListenable<List<TimelineDisplayUnit>> units;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  final bool Function() isDisplayActive;
  final VoidCallback Function(TimelineCurrentDisplay)? registerDisplay;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<ConversationCurrentConnector> createState() => _CurrentState();
}

class _CurrentState extends State<ConversationCurrentConnector> implements TimelineCurrentDisplay {
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
  bool get expanded => isCurrent && widget.units.value.any((unit) => unit.expansion.expanded ?? false);
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
    if (!identical(oldWidget.units, widget.units) || !identical(oldWidget.content, widget.content)) {
      throw StateError('Current display cannot change its original lease');
    }
  }
  @override
  void dispose() {
    _disposed = true;
    widget.units.removeListener(_changed);
    for (final item in List.of(_items)) { item.retire(); }
    _unregister?.call();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (!isCurrent || widget.units.value.isEmpty) {
      return ConversationActivityBar(view: widget.view, onExpandedChanged: widget.onExpandedChanged);
    }
    return LayoutBuilder(builder: (context, constraints) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: math.min(220, constraints.hasBoundedHeight ? constraints.maxHeight : MediaQuery.sizeOf(context).height * .45)),
      child: SingleChildScrollView(primary: false, child: SelectionArea(child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final unit in widget.units.value)
            if (unit.item.kind == TimelineItemKind.workGroup)
              TimelineDisplayUnitView(
                key: ValueKey(unit.id), unit: unit,
                onExpandedChanged: widget.onExpandedChanged,
                childBuilder: (_) => TimelineGroupMembersConnector(
                  unit: unit, threadId: widget.images.threadId,
                  readAttachment: widget.readAttachment,
                ),
              )
            else
              _CurrentItem(
                key: ValueKey(unit.id), unit: unit, content: widget.content,
                isActive: widget.isDisplayActive, images: widget.images,
                readAttachment: widget.readAttachment, mountedItems: _items,
              ),
        ]),
      ))),
    ));
  }
}

class _CurrentItem extends StatefulWidget {
  const _CurrentItem({super.key, required this.unit, required this.content,
    required this.isActive, required this.images, required this.readAttachment, required this.mountedItems});
  final TimelineDisplayUnit unit;
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
  final Set<TimelineCurrentWindowDisplay> ranges = {};
  bool _retired = false;
  bool get active => mounted && !_retired && widget.isActive() && !widget.unit.expansion.isRetired;
  @override
  void initState() {
    super.initState();
    widget.mountedItems.add(this);
    widget.unit.expansion.retirement.addListener(_intentRetired);
    _observe();
  }
  void _intentRetired() {
    if (widget.unit.expansion.retirement.value) retire();
  }
  void _observe() {
    if (!active || widget.unit.item.payload != null) return;
    owner ??= ConversationCurrentOwner(widget.content);
    owner!.synchronizeSources([
      for (final content in widget.unit.item.contents)
        CurrentWindowSource(id: widget.unit.id, reference: content.reference, text: ''),
    ]);
  }
  @override
  void didUpdateWidget(covariant _CurrentItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.unit.item.payload != null) { _closeBody(); } else { _observe(); }
  }
  void _closeBody() {
    final old = owner;
    owner = null;
    if (old != null) { unawaited(old.close()); old.dispose(); }
  }
  void retire() {
    if (_retired) return;
    _retired = true;
    _closeBody();
    _scope?.retire();
    if (_scope != null) unawaited(_scope!.close());
    _scope = null;
  }
  @override
  void dispose() {
    widget.mountedItems.remove(this);
    widget.unit.expansion.retirement.removeListener(_intentRetired);
    retire();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    if (widget.unit.item.payload != null) {
      return ChatItemView(
        item: ChatItemPresentation.forUnit(widget.unit), isDisplayActive: () => active,
        attachmentBuilder: (item) => TimelineAttachmentsConnector(item: item, resources: widget.images,
          readAttachment: widget.readAttachment, isActive: () => active),
        contentRangeBuilder: (id, key, label, reference, witness) => TimelineContentRangeConnector(
          key: ValueKey((id, key)), itemId: id, contentKey: key, label: label,
          reference: reference, witness: witness, isDisplayActive: () => active,
          registerDisplay: (display) { ranges.add(display); return () => ranges.remove(display); },
          readContent: (reference, range) {
            if (!active) return Future.error(const StaleConversationScope());
            return (_scope ??= widget.content.openScope(generation: 1)).readContent(reference: reference, range: range);
          },
        ),
      );
    }
    final body = owner;
    if (body == null || widget.unit.item.contents.isEmpty) return const Text('内容状态未知');
    return ListenableBuilder(listenable: body, builder: (_, _) => Column(
      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (body.cleanupError != null) Text(body.cleanupError.toString()),
        for (final window in body.windows)
          ConversationCurrentWindowView(
            id: window.id, text: window.window == null ? window.source.text : utf8.decode(window.window!.bytes, allowMalformed: true),
            error: window.error, offset: window.window?.offset,
            end: window.window == null ? null : window.window!.offset + window.window!.bytes.length,
            availableThrough: window.window?.availableThrough,
            onFirst: () => body.firstWindow(window), onNext: () => body.nextWindow(window),
          ),
      ],
    ));
  }
}
