import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_display_unit.dart';
import '../view_models/timeline_view_model.dart';

/// Resolves only the mounted completion's metadata, never its body or siblings.
/// The original content owner tracks this scope through retirement/cleanup join.
class TimelineCanonicalPayloadConnector extends StatefulWidget {
  const TimelineCanonicalPayloadConnector({
    super.key,
    required this.item,
    required this.threadId,
    required this.isActive,
    required this.render,
    this.openHistory,
    this.retirement,
  });

  final ChatItemPresentation item;
  final String threadId;
  final HistoryReadScope Function()? openHistory;
  final bool Function() isActive;
  final ValueListenable<bool>? retirement;
  final Widget Function(ChatItemPresentation) render;

  @override
  State<TimelineCanonicalPayloadConnector> createState() =>
      _TimelineCanonicalPayloadConnectorState();
}

class _TimelineCanonicalPayloadConnectorState
    extends State<TimelineCanonicalPayloadConnector> {
  HistoryReadScope? _historyScope;
  ChatItemPresentation? _resolved;
  String? _error;
  int _request = 0;
  bool _scheduled = false;
  TimelineExpansionIntent? _group;
  Object? _groupGeneration;

  bool get _active =>
      mounted &&
      !(widget.retirement?.value ?? false) &&
      widget.isActive() &&
      (_group == null ||
          _group!.bodyActive &&
              identical(_groupGeneration, _group!.bodyGeneration));

  Object get _identity => _identityOf(widget);

  HistoryReadScope? _openHistory() {
    if (widget.openHistory != null) return widget.openHistory!();
    final lease = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(timelineSessionOwnerProvider).lease(widget.threadId);
    return lease?.openHistoryScope();
  }

  @override
  void initState() {
    super.initState();
    widget.retirement?.addListener(_qualificationChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = TimelineGroupBodyIntent.of(context);
    if (!identical(group, _group)) {
      _group?.removeListener(_qualificationChanged);
      _cancel();
      _group = group;
      _groupGeneration = group?.bodyGeneration;
      group?.addListener(_qualificationChanged);
    }
    _schedule();
  }

  void _qualificationChanged() {
    _cancel();
    // Reopening is a new capability. Never accept a prior in-flight result.
    _groupGeneration = _group?.bodyGeneration;
    _schedule();
  }

  void _cancel() {
    _request++;
    final history = _historyScope;
    _historyScope = null;
    history?.retire();
    if (history != null) unawaited(history.close());
  }

  @override
  void didUpdateWidget(covariant TimelineCanonicalPayloadConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.retirement != widget.retirement) {
      oldWidget.retirement?.removeListener(_qualificationChanged);
      widget.retirement?.addListener(_qualificationChanged);
      _cancel();
    }
    if (_identityOf(oldWidget) != _identity ||
        oldWidget.threadId != widget.threadId) {
      _cancel();
      _resolved = null;
      _error = null;
    }
    if (!_active) _cancel();
    _schedule();
  }

  Object _identityOf(TimelineCanonicalPayloadConnector value) => (
    value.item.id,
    value.item.atom?.id,
    value.item.atom?.source,
    value.item.historyEventId,
    value.item.historyDetailEventId,
    switch (value.item.displayRecord?.contentSource) {
      CurrentAtomSource() => (CurrentAtomSource,),
      FrozenObservation(:final capturedAt, :final available) => (
        FrozenObservation,
        capturedAt,
        available,
      ),
      CompletedOriginal(:final completionId) => (
        CompletedOriginal,
        completionId,
      ),
      null => null,
    },
  );

  void _schedule() {
    final needsOwnedBody = widget.item.historyEventId != null;
    if (widget.item.observationUnavailable ||
        !needsOwnedBody ||
        _scheduled ||
        _historyScope != null ||
        _resolved != null ||
        _error != null) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_active &&
          _historyScope == null &&
          _resolved == null &&
          _error == null) {
        unawaited(_load());
      }
    });
  }

  Future<void> _load() async {
    final item = widget.item;
    final atom = item.atom;
    final source = item.displayRecord?.contentSource;
    if (atom == null || source == null) {
      setState(() => _error = '完成内容身份不一致或缺失');
      return;
    }
    final request = ++_request;
    final identity = _identity;
    if (item.historyEventId != null) {
      await _loadHistoryPayload(request, identity);
      return;
    }
    setState(() => _error = '完成内容缺少 History canonical payload');
  }

  Future<void> _loadHistoryPayload(int request, Object identity) async {
    final history = _openHistory();
    if (history == null) {
      setState(() => _error = '历史读取作用域已失效');
      return;
    }
    _historyScope = history;
    bool eligible() => _active && request == _request && identity == _identity;
    try {
      final detailId =
          widget.item.historyDetailEventId ?? widget.item.historyEventId!;
      final event = await history.readEvent(
        eventId: detailId,
        demand: const HistoryDemand(maxRows: 1, maxBytes: 64 * 1024),
      );
      var reference = event.payloadRef;
      if (reference == null) {
        final bodyEventId = widget.item.historyEventId!;
        final bodyEvent = bodyEventId == detailId
            ? event
            : await history.readEvent(
                eventId: bodyEventId,
                demand: const HistoryDemand(maxRows: 1, maxBytes: 64 * 1024),
              );
        reference = bodyEvent.payloadRef;
      }
      if (reference == null) {
        final bodies = await history.listBodies(
          eventId: widget.item.historyEventId!,
          demand: const HistoryDemand(maxRows: 32, maxBytes: 64 * 1024),
        );
        reference = bodies.entries
            .where(
              (entry) =>
                  entry.role.kind == HistoryBodyRoleKind.canonicalPayload ||
                  entry.role.kind == HistoryBodyRoleKind.body,
            )
            .firstOrNull
            ?.reference;
      }
      if (!eligible()) return;
      if (reference == null || reference.byteLength > 64 * 1024) {
        setState(() => _error = '完成内容超出单次读取预算或缺失');
        return;
      }
      final window = await history.readBody(
        reference: reference,
        offset: 0,
        maxBytes: 64 * 1024,
      );
      if (!eligible()) return;
      if (window.offset != 0 ||
          window.totalLength != reference.byteLength ||
          window.bytes.length != window.totalLength) {
        setState(() => _error = '完成内容窗口不连续');
        return;
      }
      final resolved = widget.item.resolvePayload(
        InlinePayload(bytes: window.bytes),
      );
      if (!eligible()) return;
      if (resolved.compatibility != ChatItemCompatibility.current) {
        setState(() => _error = '完成内容格式无法解析');
        return;
      }
      setState(() => _resolved = resolved);
    } catch (_) {
      if (eligible()) setState(() => _error = '完成内容读取失败');
    } finally {
      if (identical(_historyScope, history)) _historyScope = null;
      history.retire();
      unawaited(history.close());
    }
  }

  @override
  void dispose() {
    widget.retirement?.removeListener(_qualificationChanged);
    _group?.removeListener(_qualificationChanged);
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.item.observationUnavailable) {
      return widget.render(widget.item);
    }
    if (widget.item.historyEventId != null) {
      if (_resolved case final item?) return widget.render(item);
      return Text(_error ?? '正在读取当前内容…');
    }
    if (widget.item.compatibility != ChatItemCompatibility.deferred) {
      return widget.render(widget.item);
    }
    if (widget.item.hasPublicInputBody) {
      // Keep the same outer layout and renderer slot across metadata delivery.
      // Only metadata/media changes; the public Body retains its original
      // item/reference/generation and bounded content-window owner.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.render(_resolved ?? widget.item),
          if (_error case final error?)
            Text(error)
          else if (_resolved == null)
            const Text('正在读取完成内容…'),
        ],
      );
    }
    if (_resolved case final item?) return widget.render(item);
    return Text(_error ?? '正在读取完成内容…');
  }
}
