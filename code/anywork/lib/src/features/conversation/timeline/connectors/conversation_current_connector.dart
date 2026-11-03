import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../state/tool_presentation.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/timeline_display_unit_view.dart';
import '../widgets/timeline_tool_blocks.dart';
import '../widgets/timeline_wait_blocks.dart';
import '../widgets/timeline_activity_row.dart';
import 'timeline_content_connector.dart';
import 'timeline_media_connector.dart';

/// Binds only the sole reducer's live units. No independent atom/group cache,
/// Responding heuristic, completed-tail collection or Turn Children route.
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
    this.activity,
    this.loadActivity,
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
  final ValueListenable<({bool hasMore, bool loading, Object? error})>?
  activity;
  final Future<void> Function()? loadActivity;
  @override
  State<ConversationCurrentConnector> createState() => _CurrentState();
}

class _CurrentState extends State<ConversationCurrentConnector>
    implements TimelineCurrentDisplay {
  final Map<String, ValueNotifier<bool>> _retirements = {};
  final Set<_LiveAtomState> _members = {};
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
      widget.units.value.any((unit) => unit.expansion.expanded ?? unit.live);
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final member in _members) {
      if (!member._active) continue;
      yield* member._owner?.windows ?? const [];
      yield* member._rangeDisplays;
    }
  }

  @override
  void initState() {
    super.initState();
    widget.units.addListener(_changed);
    widget.activity?.addListener(_changed);
    _synchronize();
    _unregister = widget.registerDisplay?.call(this);
  }

  void _synchronize() {
    final wanted = isCurrent
        ? widget.units.value.map((unit) => unit.id).toSet()
        : <String>{};
    for (final id in _retirements.keys.toList()) {
      if (wanted.contains(id)) continue;
      final retirement = _retirements.remove(id)!;
      retirement.value = true;
      retirement.dispose();
    }
    for (final id in wanted) {
      _retirements.putIfAbsent(id, () => ValueNotifier(false));
    }
    final members = widget.units.value
        .expand((unit) => unit.members)
        .map((atom) => atom.id)
        .toSet();
    for (final member in List.of(_members)) {
      if (!members.contains(member.widget.atom.id)) member.retire();
    }
  }

  void _changed() {
    _synchronize();
    if (mounted && !_disposed) setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.units, widget.units) ||
        !identical(oldWidget.content, widget.content)) {
      throw StateError('Current display cannot change its original lease');
    }
    _synchronize();
  }

  @override
  void dispose() {
    _disposed = true;
    widget.units.removeListener(_changed);
    widget.activity?.removeListener(_changed);
    _synchronize();
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isCurrent ||
        widget.units.value.isEmpty && widget.activity?.value.hasMore != true) {
      return ConversationActivityBar(
        view: widget.view,
        onExpandedChanged: widget.onExpandedChanged,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.min(
            220,
            constraints.hasBoundedHeight
                ? constraints.maxHeight
                : MediaQuery.sizeOf(context).height * .45,
          ),
        ),
        child: SingleChildScrollView(
          primary: false,
          child: SelectionArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.activity?.value.hasMore == true)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.timelineActivityNotLoaded,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        if (widget.activity!.value.loading)
                          const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          TextButton(
                            onPressed: () async {
                              try {
                                await widget.loadActivity?.call();
                              } catch (_) {
                                /* The original lease retains the retry error. */
                              }
                            },
                            child: Text(
                              widget.activity!.value.error == null
                                  ? context.l10n.timelineLoadEarlier
                                  : context.l10n.timelineItemBodyRetry,
                            ),
                          ),
                      ],
                    ),
                  if (widget.activity?.value.error case final error?)
                    Text(
                      error.toString(),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  for (final unit in widget.units.value)
                    TimelineDisplayUnitView(
                      key: ValueKey(unit.id),
                      unit: unit,
                      onExpandedChanged: (expanded) {
                        _retirements[unit.id]!.value = !expanded;
                        widget.onExpandedChanged?.call(expanded);
                      },
                      memberBuilder: (atom) => _LiveAtom(
                        key: ValueKey((atom.id, _retirements[unit.id])),
                        atom: atom,
                        content: widget.content,
                        retirement: _retirements[unit.id]!,
                        isActive: widget.isDisplayActive,
                        members: _members,
                        images: widget.images,
                        readAttachment: widget.readAttachment,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveAtom extends StatefulWidget {
  const _LiveAtom({
    super.key,
    required this.atom,
    required this.content,
    required this.retirement,
    required this.isActive,
    required this.members,
    required this.images,
    required this.readAttachment,
  });
  final ChatAtom atom;
  final ConversationContent content;
  final ValueListenable<bool> retirement;
  final bool Function() isActive;
  final Set<_LiveAtomState> members;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  @override
  State<_LiveAtom> createState() => _LiveAtomState();
}

class _LiveAtomState extends State<_LiveAtom> {
  ConversationCurrentOwner? _owner;
  ConversationQueryScope? _scope;
  Object _rangeQualification = Object();
  final Set<TimelineCurrentWindowDisplay> _rangeDisplays = {};
  VoidCallback _registerRange(TimelineCurrentWindowDisplay display) {
    _rangeDisplays.add(display);
    return () => _rangeDisplays.remove(display);
  }

  bool _retired = false;
  bool get _active =>
      mounted && !_retired && !widget.retirement.value && widget.isActive();
  @override
  void initState() {
    super.initState();
    widget.members.add(this);
    widget.retirement.addListener(_retiredParent);
    if (widget.atom.kind != ChatAtomKind.toolCall &&
        widget.atom.payload == null) {
      _observe();
    }
  }

  void _retiredParent() {
    if (_retired) return;
    // A disclosure can reopen before ExpansionTile unmounts its children.
    // Folding revokes reads immediately, but is not permanent member retirement.
    if (widget.retirement.value) {
      _rangeQualification = Object();
      _closeBodies();
      _scope?.retire();
      if (_scope != null) unawaited(_scope!.close());
      _scope = null;
    } else if (widget.atom.kind != ChatAtomKind.toolCall &&
        widget.atom.payload == null) {
      _observe();
    }
    if (mounted) setState(() {});
  }

  void _observe() {
    if (!_active) return;
    _owner ??= ConversationCurrentOwner(widget.content);
    _owner!.synchronizeSources([
      for (final content in widget.atom.contents)
        CurrentWindowSource(
          id: widget.atom.id,
          reference: content.reference,
          text: '',
        ),
    ]);
  }

  void _expandTool(bool expanded) {
    if (!_active) return;
    setState(() {
      if (expanded) {
        _observe();
      } else {
        _closeBodies();
      }
    });
  }

  void _closeBodies() {
    final owner = _owner;
    _owner = null;
    if (owner != null) {
      unawaited(owner.close());
      owner.dispose();
    }
  }

  void retire() {
    if (_retired) return;
    _retired = true;
    _closeBodies();
    _scope?.retire();
    if (_scope != null) unawaited(_scope!.close());
    _scope = null;
  }

  @override
  void didUpdateWidget(covariant _LiveAtom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.atom.payload != null &&
        widget.atom.kind != ChatAtomKind.toolCall) {
      _closeBodies();
    } else if (_owner != null) {
      _observe();
    }
  }

  @override
  void dispose() {
    widget.members.remove(this);
    widget.retirement.removeListener(_retiredParent);
    retire();
    super.dispose();
  }

  Widget _windows() => _owner == null
      ? const SizedBox.shrink()
      : ListenableBuilder(
          listenable: _owner!,
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_owner!.cleanupError != null)
                Text(_owner!.cleanupError.toString()),
              for (final observation in _owner!.windows)
                ConversationCurrentWindowView(
                  id: observation.id,
                  text: observation.window == null
                      ? observation.source.text
                      : utf8.decode(
                          observation.window!.bytes,
                          allowMalformed: true,
                        ),
                  error: observation.error,
                  offset: observation.window?.offset,
                  end: observation.window == null
                      ? null
                      : observation.window!.offset +
                            observation.window!.bytes.length,
                  availableThrough: observation.window?.availableThrough,
                  onFirst: () => _owner!.firstWindow(observation),
                  onNext: () => _owner!.nextWindow(observation),
                ),
            ],
          ),
        );
  @override
  Widget build(BuildContext context) {
    final atom = widget.atom;
    if (atom.kind == ChatAtomKind.compaction &&
        atom.lifecycle is ActiveChatAtom) {
      return TimelineActivityRow(
        icon: Icons.compress_outlined,
        label: context.l10n.conversationActivityCompacting,
        active: true,
        expandable: false,
      );
    }
    if (atom.payload != null) {
      return ChatItemView(
        item: ChatItemPresentation.decode(atom),
        isDisplayActive: () => _active,
        attachmentBuilder: (item) => TimelineAttachmentsConnector(
          item: item,
          resources: widget.images,
          readAttachment: widget.readAttachment,
          isActive: () => _active,
        ),
        contentRangeBuilder: (id, key, label, reference, witness) {
          final qualification = _rangeQualification;
          bool active() =>
              _active && identical(qualification, _rangeQualification);
          return TimelineContentRangeConnector(
            key: ValueKey((id, key, qualification)),
            itemId: id,
            contentKey: key,
            label: label,
            reference: reference,
            witness: witness,
            isDisplayActive: active,
            registerDisplay: _registerRange,
            readContent: (reference, range) {
              if (!active()) {
                return Future.error(const StaleConversationScope());
              }
              return (_scope ??= widget.content.openScope(
                generation: 1,
              )).readContent(reference: reference, range: range);
            },
          );
        },
      );
    }
    if (atom.tool case final tool?) {
      final details = TimelineToolDetails(
        item: TimelineToolPresentation(
          id: atom.id,
          toolCallId: tool.callId,
          name: tool.name,
          presentationContract: '',
          statusString: switch (atom.lifecycle) {
            ActiveChatAtom(:final status) => status.name,
            TerminalChatAtom(:final outcome) => switch (outcome) {
              ChatTerminalOutcome.completed => 'succeeded',
              ChatTerminalOutcome.failed => 'failed',
              ChatTerminalOutcome.cancelled => 'cancelled',
              ChatTerminalOutcome.transferred => 'transferred',
            },
          },
          arguments: '',
          output: '',
        ),
        onExpansionChanged: _expandTool,
        declaredContents: [_windows()],
      );
      return atom.wait == null
          ? details
          : TimelineWaitPanel(
              identity: atom.id,
              presentation: atom.wait!,
              diagnostics: details,
              onExpansionChanged: _expandTool,
            );
    }
    if (atom.kind == ChatAtomKind.toolCall) {
      return TimelineActivityDisclosure(
        onExpansionChanged: _expandTool,
        titleBuilder: (_, expanded) => TimelineActivityRow(
          label: '工具调用',
          icon: Icons.build_outlined,
          expanded: expanded,
        ),
        children: [_windows()],
      );
    }
    return _windows();
  }
}
