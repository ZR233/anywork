import 'package:anywork_client/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/timeline_detail_state.dart';
import '../presentation/artifact_links.dart';
import '../timeline/display_binding.dart';
import '../view_models/timeline_detail_view_model.dart';
import '../views/timeline_detail_view.dart';

Future<void> openTimelineDetail(BuildContext context, {
  required TimelineDisplayBinding display, required String itemId,
  required StudioTimelineDetailRef reference,
}) => showDialog<void>(context: context, barrierDismissible: false,
  builder: (_) => TimelineDetailConnector(display: display, target: TimelineDetailKey(
    threadId: display.threadId, displayGeneration: display.generation,
    itemId: itemId, field: reference.field, revision: reference.revision)));

class TimelineDetailConnector extends ConsumerStatefulWidget {
  const TimelineDetailConnector({required this.display, required this.target, super.key});
  final TimelineDisplayBinding display;
  final TimelineDetailKey target;
  @override
  ConsumerState<TimelineDetailConnector> createState() => _TimelineDetailConnectorState();
}

class _TimelineDetailConnectorState extends ConsumerState<TimelineDetailConnector> {
  bool _canPop = false;
  @override
  void initState() {
    super.initState();
    widget.display.addRetireListener(_retired);
    _read();
  }

  void _retired() {
    if (mounted) ref.read(timelineDetailViewModelProvider(widget.target).notifier).closeReader().ignore();
  }

  @override
  void dispose() {
    widget.display.removeRetireListener(_retired);
    super.dispose();
  }

  void _read() {
    if (widget.display.retired) return;
    final display = widget.display;
    final target = widget.target;
    final reference = display.detailFor(target.itemId, target.field);
    if (reference?.revision != target.revision) return;
    ref.read(timelineDetailViewModelProvider(target).notifier).readFrom(
      read: (query) => display.readDetail(itemId: target.itemId, query: query),
      current: () => !display.retired && display.generation == target.displayGeneration &&
        display.threadId == target.threadId).ignore();
  }

  Future<void> _close() async {
    if (_canPop) return;
    await ref.read(timelineDetailViewModelProvider(widget.target).notifier).closeReader();
    if (!mounted) return;
    setState(() { _canPop = true; });
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final value = ref.watch(timelineDetailViewModelProvider(widget.target));
    return PopScope(canPop: _canPop,
      onPopInvokedWithResult: (didPop, result) { if (!didPop) _close().ignore(); },
      child: value.when(loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => const Icon(Icons.error_outline),
        data: (state) {
          var links = const <String>[];
          var decodeFailed = false;
          if (state.complete && state.key.field is ThreadToolOutputArtifactsFieldView) {
            try { links = extractArtifactLinks([OpaqueArtifactJson(json: state.text)]); }
            on ArtifactLinksDecodeFailure { decodeFailed = true; }
          }
          return TimelineDetailView(state: state, onRetry: _read,
            artifactLinks: links, artifactDecodeFailed: decodeFailed,
            onCopy: () => Clipboard.setData(ClipboardData(text: state.text)),
            onClose: () => _close().ignore());
        })));
  }
}
