import 'package:flutter/material.dart';

import '../../../../shared/studio_driver_keys.dart';
import '../state/timeline_detail_state.dart';

class TimelineDetailView extends StatelessWidget {
  const TimelineDetailView({
    super.key,
    required this.title,
    required this.state,
    required this.onClose,
    required this.onRetry,
    required this.onCopy,
  });
  final String title;
  final TimelineDetailState state;
  final VoidCallback onClose;
  final VoidCallback onRetry;
  final VoidCallback onCopy;
  @override
  Widget build(BuildContext context) => Dialog(
    key: StudioDriverKeys.timelineDetailDialog,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 1000, maxHeight: 760),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text(title)),
                IconButton(
                  key: StudioDriverKeys.timelineDetailCopy,
                  onPressed:
                      state.complete && !state.terminal && state.error == null
                      ? onCopy
                      : null,
                  tooltip: '复制全文',
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  key: StudioDriverKeys.timelineDetailClose,
                  onPressed: onClose,
                  tooltip: '关闭',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            if (state.loading) const LinearProgressIndicator(minHeight: 1),
            if (state.terminal)
              const Text(
                '内容版本已变化或展示已关闭，请重新打开',
                key: StudioDriverKeys.timelineDetailTerminal,
              ),
            if (state.error != null)
              Row(
                children: [
                  Expanded(child: Text(state.error.toString())),
                  TextButton(
                    key: StudioDriverKeys.timelineDetailRetry,
                    onPressed: onRetry,
                    child: const Text('重试'),
                  ),
                ],
              ),
            Expanded(
              child: SingleChildScrollView(
                child: SelectableText(
                  state.text,
                  key: StudioDriverKeys.timelineDetailText,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
