import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart'
    show ConversationActivityView, ConversationActivityKind;
import 'package:flutter/material.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_image_resources.dart';
import '../widgets/conversation_activity_bar.dart';
import 'timeline_member_atom.dart';

/// The bounded Activity snapshot is the only source of visible operations.
/// Completed records retire typed identities in the SDK before its next frame;
/// this view revokes their body/media eligibility synchronously on publication.
class ConversationCurrentConnector extends StatefulWidget {
  const ConversationCurrentConnector({
    required this.session,
    required this.content,
    required this.view,
    required this.images,
    required this.readAttachment,
    required this.isDisplayActive,
    this.registerDisplay,
    this.onExpandedChanged,
    super.key,
  });
  final ThreadSessionState session;
  final ConversationContent content;
  final ConversationActivityView? view;
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
  final Map<ActivityIdentity, ValueNotifier<bool>> _retirements = {};
  final Set<TimelineMemberDisplay> _members = {};
  Observation? _observation;
  VoidCallback? _unregister;
  bool _disposed = false;
  ActivitySnapshot? get _snapshot => widget.content.activity.value;
  @override
  bool get isCurrent => mounted && !_disposed && widget.isDisplayActive();
  @override
  String? get turnId => isCurrent ? widget.session.activeTurn?.turnId : null;
  @override
  String? get activityId =>
      isCurrent ? widget.session.activity?.identity : null;
  @override
  bool get expanded => isCurrent && _members.isNotEmpty;
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections => const [];
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final member in _members) {
      yield* member.windows;
    }
  }

  @override
  void initState() {
    super.initState();
    _unregister = widget.registerDisplay?.call(this);
    _observation = widget.content.activity.watch((_) => _changed());
    _synchronize();
  }

  void _synchronize() {
    final wanted = {
      for (final entry in _snapshot?.entries ?? const <ActivityEntry>[])
        entry.identity,
    };
    for (final identity in _retirements.keys.toList()) {
      if (wanted.contains(identity)) continue;
      final retired = _retirements.remove(identity)!;
      retired.value = true;
      // Descendants detach after this frame; they still borrow the notifier.
      WidgetsBinding.instance.addPostFrameCallback((_) => retired.dispose());
    }
    for (final identity in wanted) {
      _retirements.putIfAbsent(identity, () => ValueNotifier(false));
    }
  }

  void _changed() {
    if (!mounted || _disposed) return;
    _synchronize();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content)) {
      throw StateError('Activity cannot change its original content lease');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _observation?.cancel();
    for (final retirement in _retirements.values) {
      retirement.value = true;
      retirement.dispose();
    }
    _retirements.clear();
    _members.clear();
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = isCurrent ? _snapshot : null;
    final entries = snapshot?.entries ?? const <ActivityEntry>[];
    final view = widget.view;
    if (entries.isEmpty && view == null) return const SizedBox.shrink();
    return ConversationActivityBar(
      children: [
        if (view != null &&
            (entries.isEmpty ||
                view.kind == ConversationActivityKind.storageBlocked ||
                view.kind == ConversationActivityKind.stopping ||
                view.kind == ConversationActivityKind.awaitingApproval))
          ConversationActivityStatus(view: view),
        for (final entry in entries)
          TimelineMemberAtom(
            key: ValueKey((entry.identity, _retirements[entry.identity])),
            atom: entry.atom,
            content: widget.content,
            retirement: _retirements[entry.identity],
            isActive: () =>
                isCurrent && _retirements[entry.identity]?.value == false,
            images: widget.images,
            readAttachment: widget.readAttachment,
            registerDisplay: (display) {
              _members.add(display);
              return () => _members.remove(display);
            },
          ),
      ],
    );
  }
}
