import 'dart:async';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/chat_item_presentation.dart';
import '../state/timeline_history_item_content.dart';
import '../state/timeline_display_unit.dart';
import '../view_models/timeline_view_model.dart';
import '../widgets/timeline_content_range_view.dart';

/// The original History read hands one prepared immutable row to its display.
class TimelineInitialHistoryContent extends InheritedWidget {
  const TimelineInitialHistoryContent({
    required this.content,
    required super.child,
    super.key,
  });
  final TimelinePreparedHistoryItem? content;

  static AsyncSnapshot<TimelineHistoryItemContent>? read(
    BuildContext context,
    ChatItemPresentation item,
  ) {
    final content = context
        .getInheritedWidgetOfExactType<TimelineInitialHistoryContent>()
        ?.content;
    return content?.identity == timelineHistoryItemIdentity(item)
        ? content?.result
        : null;
  }

  @override
  bool updateShouldNotify(TimelineInitialHistoryContent oldWidget) =>
      !identical(content, oldWidget.content);
}

/// Resolves the mounted completion's metadata and automatically disclosed text.
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
  Map<Object, AsyncSnapshot<ContentWindow>> _initialBodyReads = const {};
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

  Object get _identity => timelineHistoryItemIdentity(widget.item);

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
    if (timelineHistoryItemIdentity(oldWidget.item) != _identity ||
        oldWidget.threadId != widget.threadId) {
      _cancel();
      _resolved = null;
      _initialBodyReads = const {};
      _error = null;
    }
    if (!_active) _cancel();
    _schedule();
  }

  void _schedule() {
    if (_resolved == null && _error == null) {
      final prepared = TimelineInitialHistoryContent.read(context, widget.item);
      if (prepared != null) {
        if (prepared.data case final content?) {
          _resolved = widget.item.resolvePresentation(content.item);
          _initialBodyReads = content.bodyReads;
        } else if (prepared.error case final error?) {
          _error = timelineHistoryItemError(error);
        }
        return;
      }
    }
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
    scheduleMicrotask(() {
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
      final content = await readTimelineHistoryItem(history, widget.item);
      if (!eligible()) return;
      setState(() {
        _resolved = content.item;
        _initialBodyReads = content.bodyReads;
      });
    } catch (error) {
      if (eligible()) setState(() => _error = timelineHistoryItemError(error));
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
      if (_resolved case final item?) {
        return TimelineInitialBodyReads(
          results: _initialBodyReads,
          child: widget.render(item),
        );
      }
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
