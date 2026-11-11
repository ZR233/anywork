import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import '../state/chat_item_presentation.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_unit.dart';

/// Resolves only the mounted completion's metadata, never its body or siblings.
/// The original content owner tracks this scope through retirement/cleanup join.
class TimelineCanonicalPayloadConnector extends StatefulWidget {
  const TimelineCanonicalPayloadConnector({
    super.key,
    required this.item,
    required this.content,
    required this.isActive,
    required this.render,
    this.retirement,
  });

  final ChatItemPresentation item;
  final ConversationContent content;
  final bool Function() isActive;
  final ValueListenable<bool>? retirement;
  final Widget Function(ChatItemPresentation) render;

  @override
  State<TimelineCanonicalPayloadConnector> createState() =>
      _TimelineCanonicalPayloadConnectorState();
}

class _TimelineCanonicalPayloadConnectorState
    extends State<TimelineCanonicalPayloadConnector> {
  ConversationQueryScope? _scope;
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
    final scope = _scope;
    _scope = null;
    scope?.retire();
    if (scope != null) unawaited(scope.close());
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
        !identical(oldWidget.content, widget.content)) {
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
    value.item.atom?.completionItemId,
    value.item.atom?.completionSeq,
    switch (value.item.displayRecord?.contentSource) {
      CurrentAtom() => (CurrentAtom,),
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
    value.item.reference == null
        ? null
        : contentReferenceIdentity(value.item.reference!),
  );

  void _schedule() {
    if (widget.item.compatibility != ChatItemCompatibility.deferred ||
        widget.item.observationUnavailable ||
        widget.item.displayRecord?.contentSource is CurrentAtom ||
        _scheduled ||
        _scope != null ||
        _resolved != null ||
        _error != null) {
      return;
    }
    _scheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (_active && _scope == null && _resolved == null && _error == null) {
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
    ConversationQueryScope? scope;
    bool eligible() => _active && request == _request && identity == _identity;
    try {
      scope = widget.content.openScope(generation: request);
      _scope = scope;
      if (source is! CompletedOriginal) {
        final reference = item.reference;
        if (source is FrozenObservation &&
            (!source.available ||
                reference == null ||
                !isDisplayObservationReference(reference))) {
          if (eligible()) setState(() => _error = '旧边界观察不可用');
          return;
        }
        if (reference == null) {
          if (eligible()) setState(() => _error = '显示内容引用缺失');
          return;
        }
        final window = await scope.readContent(
          reference: reference,
          range: const ContentRange(offset: 0, maxBytes: 64 * 1024),
        );
        if (!eligible()) return;
        if (!window.sealed ||
            window.offset != 0 ||
            window.bytes.length != window.availableThrough ||
            window.bytes.length > 64 * 1024) {
          setState(() => _error = '显示内容超出单次读取预算或尚未封存（64 KiB）');
          return;
        }
        final resolved = item.resolvePayload(
          InlinePayload(bytes: window.bytes),
        );
        if (resolved.compatibility != ChatItemCompatibility.current) {
          setState(() => _error = '显示内容格式无法解析');
          return;
        }
        setState(() => _resolved = resolved);
        return;
      }
      final recordId = source.completionId;
      final payloadMismatch = switch (item.reference?.target) {
        ItemPayloadTarget(:final itemId) => itemId != recordId,
        _ => false,
      };
      if ((atom.completionItemId != null &&
              atom.completionItemId != recordId) ||
          payloadMismatch) {
        if (eligible()) setState(() => _error = '完成内容身份不一致');
        return;
      }
      final entry = await scope.readCompleted(
        recordId: recordId,
        demand: const ReadDemand(maxItems: 1, maxBytes: 64 * 1024),
      );
      if (!eligible()) return;
      final original = entry.atom;
      if (entry.recordId != recordId ||
          original.id != atom.id ||
          original.source != atom.source ||
          original.kind != atom.kind ||
          original.lifecycle is! TerminalChatAtom ||
          (original.completionItemId != null &&
              original.completionItemId != recordId) ||
          (atom.completionSeq != null &&
              entry.completionSeq != atom.completionSeq) ||
          (original.completionSeq != null &&
              original.completionSeq != entry.completionSeq)) {
        setState(() => _error = '完成内容身份不一致');
        return;
      }
      final payload = original.payload;
      if (payload is! InlinePayload || payload.bytes.length > 64 * 1024) {
        setState(() => _error = '完成内容超出单次读取预算（64 KiB）');
        return;
      }
      final resolved = item.resolvePayload(payload);
      if (resolved.compatibility != ChatItemCompatibility.current) {
        setState(() => _error = '完成内容格式无法解析');
        return;
      }
      setState(() => _resolved = resolved);
    } catch (_) {
      if (eligible()) setState(() => _error = '完成内容读取失败');
    } finally {
      if (identical(_scope, scope)) _scope = null;
      scope?.retire();
      if (scope != null) unawaited(scope.close());
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
    if (widget.item.displayRecord?.contentSource is CurrentAtom) {
      return widget.render(widget.item);
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
