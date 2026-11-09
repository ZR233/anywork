import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ValueListenable;

import '../state/conversation_realtime_presentation.dart';
import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_display_unit.dart';
import '../state/timeline_image_resources.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/timeline_display_unit_view.dart';
import 'completion_run_connector.dart';
import 'timeline_member_atom.dart';

/// Reads only the display lease's accepted cut, never SDK live independently.
class ConversationCurrentConnector extends StatefulWidget {
  const ConversationCurrentConnector({
    required this.session,
    required this.content,
    required this.region,
    required this.live,
    required this.liveUnit,
    required this.images,
    required this.readAttachment,
    required this.isDisplayActive,
    this.loadLiveOlder,
    this.registerDisplay,
    this.onExpandedChanged,
    super.key,
  });
  final ThreadSessionState session;
  final ConversationContent content;
  final ContentRealtimeRegion region;
  final ValueListenable<LiveDisplayWindow?> live;
  final TimelineDisplayUnit Function(LiveDisplayBlock, bool) liveUnit;
  final TimelineImageResources images;
  final Future<Uint8List> Function(String) readAttachment;
  final bool Function() isDisplayActive;
  final Future<LiveDisplayWindow> Function(String)? loadLiveOlder;
  final VoidCallback Function(TimelineCurrentDisplay)? registerDisplay;
  final ValueChanged<bool>? onExpandedChanged;
  @override
  State<ConversationCurrentConnector> createState() => _CurrentState();
}

class _CurrentState extends State<ConversationCurrentConnector>
    implements TimelineCurrentDisplay {
  final Set<TimelineMemberDisplay> _members = {};
  final Map<String, ValueNotifier<bool>> _retirements = {};
  VoidCallback? _unregister;
  bool _disposed = false;
  LiveDisplayWindow? _older;
  bool _loadingOlder = false;
  Object? _olderError;
  LiveDisplayWindow? _acceptedCut;
  Object? _attempt;
  bool _wasCurrent = false;
  Object _windowQualification = Object();
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
    widget.live.addListener(_changed);
    _acceptedCut = widget.live.value;
    _attempt = widget.content.currentAttemptId;
    _wasCurrent = isCurrent;
    _synchronize();
  }

  bool _sameCut(LiveDisplayWindow? a, LiveDisplayWindow? b) =>
      a?.revision == b?.revision &&
      a?.historyThrough == b?.historyThrough &&
      a?.executionPresent == b?.executionPresent;

  void _reconcileCut() {
    final next = widget.live.value;
    final attempt = widget.content.currentAttemptId;
    final current = isCurrent;
    if (!_sameCut(_acceptedCut, next) ||
        _attempt != attempt ||
        _wasCurrent != current) {
      _windowQualification = Object();
      _older = null;
      _olderError = null;
      _loadingOlder = false;
    }
    _acceptedCut = next;
    _attempt = attempt;
    _wasCurrent = current;
    _synchronize();
  }

  void _synchronize() {
    final wanted = {
      if (isCurrent)
        for (final block
            in (_older ?? widget.live.value)?.blocks ??
                const <LiveDisplayBlock>[])
          if (block.body is SingleDisplayBlock) block.id,
    };
    for (final id in _retirements.keys.toList()) {
      if (wanted.contains(id)) continue;
      final notifier = _retirements.remove(id)!;
      notifier.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => notifier.dispose());
    }
    for (final id in wanted) {
      _retirements.putIfAbsent(id, () => ValueNotifier(false));
    }
  }

  void _changed() {
    if (!mounted || _disposed) return;
    _reconcileCut();
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content)) {
      throw StateError('Live content cannot change its original lease');
    }
    if (!identical(oldWidget.live, widget.live)) {
      throw StateError('Live display cannot replace its admission notifier');
    }
    _reconcileCut();
  }

  Future<void> _loadOlder(String before) async {
    final read = widget.loadLiveOlder;
    final original = widget.live.value;
    if (!isCurrent || _loadingOlder || read == null || original == null) return;
    final qualification = _windowQualification;
    setState(() {
      _loadingOlder = true;
      _olderError = null;
    });
    try {
      final value = await read(before);
      if (!isCurrent ||
          !identical(qualification, _windowQualification) ||
          !_sameCut(widget.live.value, original) ||
          !_sameCut(value, original)) {
        return;
      }
      setState(() {
        _older = value;
        _synchronize();
      });
    } catch (error) {
      if (isCurrent && identical(qualification, _windowQualification)) {
        setState(() => _olderError = error);
      }
    } finally {
      if (isCurrent && identical(qualification, _windowQualification)) {
        setState(() => _loadingOlder = false);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    widget.live.removeListener(_changed);
    for (final notifier in _retirements.values) {
      notifier.value = true;
      notifier.dispose();
    }
    _retirements.clear();
    _members.clear();
    _unregister?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final live = isCurrent ? _older ?? widget.live.value : null;
    return ConversationActivityBar(
      children: [
        ConversationRealtimeNotices(notices: widget.region.notices),
        if (_olderError case final error?) Text(error.toString()),
        if (_loadingOlder) const LinearProgressIndicator(),
        if (live?.older case final before?)
          TextButton(
            onPressed: () => _loadOlder(before),
            child: const Text('更早实时片段'),
          ),
        if (_older != null)
          TextButton(
            onPressed: () => setState(() {
              _older = null;
              _synchronize();
            }),
            child: const Text('最新实时片段'),
          ),
        for (final block in live?.blocks ?? const <LiveDisplayBlock>[])
          switch (block.body) {
            WorkDisplayBlock() => _work(block, live!.executionPresent),
            SingleDisplayBlock(:final atom) => TimelineMemberAtom(
              key: ValueKey((block.id, _retirements[block.id])),
              atom: atom,
              executionPresent: live!.executionPresent,
              retirement: _retirements[block.id],
              content: widget.content,
              isActive: () =>
                  isCurrent && _retirements[block.id]?.value == false,
              images: widget.images,
              readAttachment: widget.readAttachment,
              registerDisplay: (member) {
                _members.add(member);
                return () => _members.remove(member);
              },
            ),
          },
      ],
    );
  }

  Widget _work(LiveDisplayBlock block, bool executionPresent) {
    final unit = widget.liveUnit(block, executionPresent);
    return TimelineDisplayUnitView(
      key: ValueKey(block.id),
      unit: unit,
      onExpandedChanged: widget.onExpandedChanged,
      childBuilder: (_) => CompletionRunConnector(
        unit: unit,
        threadId: widget.session.threadId,
        content: widget.content,
        images: widget.images,
        readAttachment: widget.readAttachment,
        registerMemberDisplay: (member) {
          _members.add(member);
          return () => _members.remove(member);
        },
      ),
    );
  }
}
