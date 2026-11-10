import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../platform/external_url_launcher.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/content_reference_identity.dart';
import '../view_models/timeline_view_model.dart';
import '../views/plan_detail_view.dart';
export '../views/plan_detail_view.dart'
    show PlanDetailStatus, planDetailStatusFromRuntime;
import '../widgets/timeline_markdown.dart';
import 'plan_document_connector.dart';
import 'timeline_media_connector.dart';

class PlanDetailConnector extends ConsumerWidget {
  const PlanDetailConnector({
    super.key,
    required this.threadId,
    required this.identity,
    required this.status,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final String threadId;
  final String identity;
  final PlanDetailStatus status;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(threadSessionStoreProvider(threadId));
    final conversations = ref.read(anyworkClientProvider).conversations;
    final session = conversations.existingSession(threadId);
    final content = session?.content;
    ref.watch(timelineViewModelProvider(threadId));
    final plan = state.businessRefs?.plan;
    final document = plan?.document;
    bool current() =>
        content != null &&
        session != null &&
        identical(conversations.existingSession(threadId), session) &&
        conversations.visibleThreadId.value == threadId &&
        session.state.businessRefs?.plan?.document == document;
    return PlanDetailView(
      identity: identity,
      title: context.l10n.interactionPlanDetailsTitle,
      status: plan == null ? status : planDetailStatusFromRuntime(plan.phase),
      onClose: onClose,
      onToggleReadingMode: onToggleReadingMode,
      fullWidth: fullWidth,
      body: document == null
          ? null
          : content == null
          ? Text(context.l10n.planDocumentNotReady)
          : PlanDocumentConnector(
              key: ValueKey((
                content,
                content.currentAttemptId,
                contentReferenceIdentity(document),
              )),
              content: content,
              reference: document,
              isCurrent: current,
              documentBuilder: (text) => TimelineMarkdown(
                key: StudioDriverKeys.planDetailsMarkdown,
                id: identity,
                text: text,
                isSafeLink: (url) => safeExternalWebUrl(url) != null,
                onLink: (raw) {
                  final url = safeExternalWebUrl(raw);
                  if (url == null || !current()) return;
                  unawaited(
                    ref.read(externalUrlLauncherProvider)(url).catchError((
                      Object error,
                    ) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(error.toString())),
                        );
                      }
                    }),
                  );
                },
                imageBuilder: (_, url) =>
                    TimelineRemoteImageConnector(url: url),
              ),
            ),
    );
  }
}
