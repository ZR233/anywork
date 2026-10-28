import 'dart:async';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../platform/external_url_launcher.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../views/plan_detail_view.dart';
import '../widgets/timeline_markdown.dart';
import 'timeline_media_connector.dart';

class PlanDetailConnector extends ConsumerWidget {
  const PlanDetailConnector({
    super.key,
    required this.identity,
    required this.markdown,
    required this.awaitingConfirmation,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final String identity;
  final String markdown;
  final bool awaitingConfirmation;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;
  @override
  Widget build(BuildContext context, WidgetRef ref) => PlanDetailView(
    identity: identity,
    title: planDocumentTitle(markdown, fallback: '计划'),
    awaitingConfirmation: awaitingConfirmation,
    onClose: onClose,
    onToggleReadingMode: onToggleReadingMode,
    fullWidth: fullWidth,
    body: TimelineMarkdown(
      key: StudioDriverKeys.planDetailsMarkdown,
      id: identity,
      text: markdown,
      isSafeLink: (url) => safeExternalWebUrl(url) != null,
      onLink: (raw) {
        final url = safeExternalWebUrl(raw);
        if (url != null) {
          unawaited(
            ref.read(externalUrlLauncherProvider)(url).catchError((
              Object error,
            ) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(error.toString())));
              }
            }),
          );
        }
      },
      imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
    ),
  );
}
