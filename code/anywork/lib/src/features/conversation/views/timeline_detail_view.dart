import 'package:flutter/material.dart';

import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../state/timeline_detail_state.dart';

class TimelineDetailView extends StatelessWidget {
  const TimelineDetailView({
    required this.state,
    required this.onRetry,
    required this.onCopy,
    required this.onClose,
    this.artifactLinks = const [],
    this.artifactDecodeFailed = false,
    super.key,
  });
  final TimelineDetailViewState state;
  final VoidCallback onRetry;
  final VoidCallback onCopy;
  final VoidCallback onClose;
  final List<String> artifactLinks;
  final bool artifactDecodeFailed;
  @override
  Widget build(BuildContext context) => AlertDialog(
    key: StudioDriverKeys.timelineDetailDialog,
    title: Text(context.l10n.timelineItemBodyLoad),
    content: SizedBox(
      width: 800,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (state.loading) const LinearProgressIndicator(),
          Text('${state.loadedBytes}/${state.totalBytes ?? '—'} B'),
          if (state.error != null) Text(state.error!.message),
          if (artifactDecodeFailed)
            const Text('Artifact links could not be decoded'),
          for (final link in artifactLinks) SelectableText(link),
          Flexible(
            child: SingleChildScrollView(
              child: SelectableText(
                state.text,
                key: StudioDriverKeys.timelineDetailText,
              ),
            ),
          ),
          if (state.complete)
            const SizedBox(key: StudioDriverKeys.timelineDetailTerminal),
        ],
      ),
    ),
    actions: [
      if (state.error != null)
        TextButton(
          key: StudioDriverKeys.timelineDetailRetry,
          onPressed: state.loading || state.closing ? null : onRetry,
          child: Text(context.l10n.sidebarRetry),
        ),
      TextButton(
        key: StudioDriverKeys.timelineDetailCopy,
        onPressed: state.complete && !state.closing ? onCopy : null,
        child: const Icon(Icons.copy),
      ),
      TextButton(
        key: StudioDriverKeys.timelineDetailClose,
        onPressed: state.closing ? null : onClose,
        child: const Icon(Icons.close),
      ),
    ],
  );
}
