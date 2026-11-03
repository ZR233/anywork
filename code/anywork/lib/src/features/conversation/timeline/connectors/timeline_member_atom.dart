import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../state/chat_item_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_image_resources.dart';
import '../state/tool_presentation.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/content_layout_witness.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_tool_blocks.dart';
import '../widgets/timeline_wait_blocks.dart';
import 'timeline_content_connector.dart';
import 'timeline_media_connector.dart';

class TimelineMemberAtom extends StatefulWidget {
  const TimelineMemberAtom({
    super.key,
    required this.atom,
    required this.content,
    this.retirement,
    required this.isActive,
    required this.images,
    required this.readAttachment,
    this.monotonicMicros,
    this.onContentLayout,
    this.registerDisplay,
  });
  final ChatAtom atom;
  final ConversationContent content;
  final ValueListenable<bool>? retirement;
  final bool Function() isActive;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String)? readAttachment;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final VoidCallback Function(TimelineMemberDisplay)? registerDisplay;
  @override
  State<TimelineMemberAtom> createState() => _TimelineMemberAtomState();
}

class _TimelineMemberAtomState extends State<TimelineMemberAtom> implements TimelineMemberDisplay {
  ConversationCurrentOwner? _owner;
  ConversationQueryScope? _scope;
  Object _rangeQualification = Object();
  final Set<TimelineCurrentWindowDisplay> _rangeDisplays = {};
  VoidCallback? _unregister;
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!_bodyActive) return;
    yield* _owner?.windows ?? const [];
    yield* _rangeDisplays;
  }
  VoidCallback _registerRange(TimelineCurrentWindowDisplay display) {
    _rangeDisplays.add(display);
    return () => _rangeDisplays.remove(display);
  }

  bool _retired = false;
  bool _toolExpanded = false;
  bool get _active =>
      mounted && !_retired && !(widget.retirement?.value ?? false) && widget.isActive();
  bool get _bodyActive => _active &&
      (widget.atom.kind != ChatAtomKind.toolCall || _toolExpanded);
  @override
  void initState() {
    super.initState();
    _unregister = widget.registerDisplay?.call(this);
    widget.retirement?.addListener(_retiredParent);
    if (widget.atom.kind != ChatAtomKind.toolCall &&
        widget.atom.payload == null) {
      _observe();
    }
  }

  void _retiredParent() {
    if (_retired) return;
    // A disclosure can reopen before ExpansionTile unmounts its children.
    // Folding revokes reads immediately, but is not permanent member retirement.
    if ((widget.retirement?.value ?? false)) {
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
      _toolExpanded = expanded;
      if (expanded) {
        if (widget.atom.payload == null) _observe();
      } else {
        _rangeQualification = Object();
        _closeBodies();
        _scope?.retire();
        if (_scope != null) unawaited(_scope!.close());
        _scope = null;
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
  void didUpdateWidget(covariant TimelineMemberAtom oldWidget) {
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
    widget.retirement?.removeListener(_retiredParent);
    _unregister?.call();
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
                _witness(observation, ConversationCurrentWindowView(
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
                )),
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
      final qualification = _rangeQualification;
      bool qualified() => _bodyActive && identical(qualification, _rangeQualification);
      return ChatItemView(
        item: ChatItemPresentation.decode(atom),
        monotonicMicros: widget.monotonicMicros,
        onContentLayout: widget.onContentLayout,
        onToolExpansionChanged: _expandTool,
        isDisplayActive: () => _active,
        attachmentBuilder: (item) => TimelineAttachmentsConnector(
          item: item,
          resources: widget.images,
          readAttachment: widget.readAttachment,
          isActive: qualified,
        ),
        contentRangeBuilder: (id, key, label, reference, witness) {
          final qualification = _rangeQualification;
          bool active() =>
              _bodyActive && identical(qualification, _rangeQualification);
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
        inline: atom.wait != null,
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

  Widget _witness(TimelineCurrentWindowDisplay observation, Widget child) {
    final clock = widget.monotonicMicros;
    final onLayout = widget.onContentLayout;
    if (clock == null || onLayout == null || observation.window?.bytes.isEmpty != false) return child;
    return ContentLayoutWitness(
      itemId: widget.atom.id,
      monotonicMicros: clock,
      onContentLayout: onLayout,
      isDisplayActive: () => _active,
      child: child,
    );
  }
}
