import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../state/chat_item_presentation.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_image_resources.dart';
import '../state/tool_presentation.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/conversation_current_views.dart';
import '../widgets/content_layout_witness.dart';
import '../widgets/timeline_activity_row.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_reasoning_view.dart';
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

class _TimelineMemberAtomState extends State<TimelineMemberAtom>
    implements TimelineMemberDisplay {
  ConversationCurrentOwner? _owner;
  ConversationQueryScope? _scope;
  Object _rangeQualification = Object();
  final Set<TimelineCurrentWindowDisplay> _rangeDisplays = {};
  VoidCallback? _unregister;
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!_active) return;
    yield* _owner?.windows ?? const [];
    yield* _rangeDisplays;
  }

  VoidCallback _registerRange(TimelineCurrentWindowDisplay display) {
    _rangeDisplays.add(display);
    return () => _rangeDisplays.remove(display);
  }

  bool _retired = false;
  bool _expanded = false;
  bool get _active =>
      mounted &&
      !_retired &&
      !(widget.retirement?.value ?? false) &&
      widget.isActive();
  bool _readActive(String key) =>
      _active &&
      (key == 'payload' ||
          key.startsWith('part.summaryText.') ||
          (widget.atom.kind != ChatAtomKind.toolCall &&
              widget.atom.kind != ChatAtomKind.reasoning) ||
          _expanded);
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
      _retireRanges();
      _closeBodies();
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
        if (widget.atom.kind != ChatAtomKind.reasoning ||
            content.role == ChatContentRole.reasoningSummary ||
            _expanded)
          CurrentWindowSource(
            id: widget.atom.id,
            reference: content.reference,
            text: '',
          ),
    ]);
  }

  void _expand(bool expanded) {
    if (!_active) return;
    setState(() {
      _expanded = expanded;
      if (expanded) {
        if (widget.atom.payload == null) _observe();
      } else {
        _retireRanges();
        if (widget.atom.kind == ChatAtomKind.reasoning &&
            widget.atom.payload == null) {
          _observe();
        } else {
          _closeBodies();
        }
      }
    });
  }

  void _retireRanges() {
    _rangeQualification = Object();
    _rangeDisplays.clear();
    final scope = _scope;
    _scope = null;
    scope?.retire();
    if (scope != null) unawaited(scope.close());
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
    _retireRanges();
    _closeBodies();
  }

  @override
  void didUpdateWidget(covariant TimelineMemberAtom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.atom.payload != null) {
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

  bool _hasRole(CurrentWindowObservation observation, ChatContentRole role) =>
      widget.atom.contents.any(
        (content) =>
            content.role == role &&
            contentReferenceIdentity(content.reference) ==
                contentReferenceIdentity(observation.reference),
      );

  Widget _body(String id, String text) => TimelineMarkdown(
    id: id,
    text: text,
    isSafeLink: (url) => safeExternalWebUrl(url) != null,
    onLink: (raw) {
      final url = safeExternalWebUrl(raw);
      if (url == null || !_active) return;
      unawaited(
        ProviderScope.containerOf(
          context,
          listen: false,
        ).read(externalUrlLauncherProvider)(url).catchError((Object error) {
          if (mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }),
      );
    },
    imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
  );

  Widget _windows({ChatContentRole? role}) => _owner == null
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
                if (role == null || _hasRole(observation, role))
                  _witness(
                    observation,
                    ConversationCurrentWindowView(
                      id: observation.id,
                      bodyBuilder:
                          (widget.atom.kind == ChatAtomKind.text ||
                                  widget.atom.kind == ChatAtomKind.input) &&
                              _hasRole(observation, ChatContentRole.body)
                          ? (text) => _body(observation.id, text)
                          : null,
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
                  ),
            ],
          ),
        );

  Widget _reasoning() {
    Widget view() {
      final summaries =
          _owner?.windows.where(
            (window) => _hasRole(window, ChatContentRole.reasoningSummary),
          ) ??
          const <CurrentWindowObservation>[];
      final summary = summaries
          .map(
            (window) => window.window == null
                ? window.source.text
                : utf8.decode(window.window!.bytes, allowMalformed: true),
          )
          .join(' ');
      final atom = widget.atom;
      final row = TimelineReasoningView(
        summary: summary,
        startedAt: atom.startedAt,
        finishedAt: atom.finishedAt,
        running: atom.lifecycle is ActiveChatAtom,
        outcome: switch (atom.lifecycle) {
          TerminalChatAtom(:final outcome) => outcome.name,
          _ => null,
        },
        diagnostic:
            _owner?.cleanupError?.toString() ??
            summaries
                .map((window) => window.error)
                .whereType<Object>()
                .firstOrNull
                ?.toString(),
        initiallyExpanded: _expanded,
        onExpansionChanged: _expand,
        body:
            atom.contents.any((content) => content.role == ChatContentRole.body)
            ? _windows(role: ChatContentRole.body)
            : null,
      );
      return summaries.isEmpty ? row : _witness(summaries.first, row);
    }

    final owner = _owner;
    return owner == null
        ? view()
        : ListenableBuilder(listenable: owner, builder: (_, _) => view());
  }

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
      final presentation = ChatItemPresentation.decode(atom);
      bool qualified() =>
          (presentation.presentationContract == 'builtin.show_files@1'
              ? _active
              : _readActive('attachments')) &&
          identical(qualification, _rangeQualification);
      final view = ChatItemView(
        item: presentation,
        bodyBuilder: _body,
        initiallyExpanded: _expanded,
        monotonicMicros: widget.monotonicMicros,
        onContentLayout: widget.onContentLayout,
        onExpansionChanged: _expand,
        isDisplayActive: () => _active,
        attachmentBuilder: (item) => TimelineAttachmentsConnector(
          item: item,
          resources: widget.images,
          readAttachment: widget.readAttachment,
          isActive: qualified,
          readContent: (reference, range) {
            if (!qualified()) {
              return Future.error(const StaleConversationScope());
            }
            return (_scope ??= widget.content.openScope(
              generation: 1,
            )).readContent(reference: reference, range: range);
          },
        ),
        contentRangeBuilder: (id, key, label, reference, witness) {
          final qualification = _rangeQualification;
          bool active() =>
              _readActive(key) && identical(qualification, _rangeQualification);
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
      return _response(view);
    }
    if (atom.kind == ChatAtomKind.reasoning) return _reasoning();
    if (atom.tool case final tool?) {
      final details = TimelineToolDetails(
        inline: atom.wait != null,
        initiallyExpanded: _expanded,
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
        onExpansionChanged: _expand,
        declaredContents: [_windows()],
      );
      return atom.wait == null
          ? details
          : TimelineWaitPanel(
              identity: atom.id,
              presentation: atom.wait!,
              initiallyExpanded: _expanded,
              diagnostics: details,
              onExpansionChanged: _expand,
            );
    }
    if (atom.kind == ChatAtomKind.toolCall) {
      return TimelineActivityDisclosure(
        initiallyExpanded: _expanded,
        onExpansionChanged: _expand,
        titleBuilder: (_, expanded) => TimelineActivityRow(
          label: '工具调用',
          icon: Icons.build_outlined,
          expanded: expanded,
        ),
        children: [_windows()],
      );
    }
    return _response(_windows());
  }

  Widget _response(Widget body) {
    final atom = widget.atom;
    if (atom.kind == ChatAtomKind.text && atom.lifecycle is ActiveChatAtom) {
      return ConversationResponseView(startedAt: atom.startedAt, child: body);
    }
    if ((atom.kind == ChatAtomKind.text || atom.kind == ChatAtomKind.input) &&
        SelectionContainer.maybeOf(context) == null) {
      body = SelectionArea(child: body);
    }
    return body;
  }

  Widget _witness(TimelineCurrentWindowDisplay observation, Widget child) {
    final clock = widget.monotonicMicros;
    final onLayout = widget.onContentLayout;
    if (clock == null ||
        onLayout == null ||
        observation.window?.bytes.isEmpty != false) {
      return child;
    }
    return ContentLayoutWitness(
      itemId: widget.atom.id,
      monotonicMicros: clock,
      onContentLayout: onLayout,
      isDisplayActive: () => _active,
      child: child,
    );
  }
}
