import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../platform/external_url_launcher.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/providers/thread_session_store.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../view_models/plan_document_view_model.dart';
import '../view_models/timeline_view_model.dart';
import '../views/plan_detail_view.dart';
export '../views/plan_detail_view.dart'
    show PlanDetailStatus, planDetailStatusFromRuntime;
import '../widgets/timeline_markdown.dart';
import '../widgets/timeline_content_range_view.dart';
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
    final timeline = ref.read(timelineSessionOwnerProvider);
    final content = timeline.lease(threadId);
    final documentState = ref.watch(planDocumentViewModelProvider(threadId));
    final documentModel = ref.read(
      planDocumentViewModelProvider(threadId).notifier,
    );
    final plan = state.businessRefs?.plan;
    final document = plan?.document;
    bool current() =>
        content != null &&
        !content.isRetired &&
        identical(timeline.lease(threadId), content) &&
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
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!documentState.canRead && documentState.error == null)
                  Text(context.l10n.planDocumentNotReady),
                if (documentState.error != null)
                  TextButton(
                    key: const ValueKey('plan-document-retry'),
                    onPressed: documentState.loading
                        ? null
                        : documentModel.retry,
                    child: Text(context.l10n.runtimeFatalRetry),
                  ),
                TimelineContentRangeView(
                  itemId: 'plan-document',
                  contentKey: 'plan.document',
                  label: context.l10n.interactionPlanDetailsTitle,
                  disclosed: true,
                  loading: documentState.loading,
                  active: documentState.canRead,
                  canRead: true,
                  window: documentState.window,
                  error: documentState.error,
                  onExpansionChanged: (_) {},
                  onNext: documentModel.next,
                  onCopy: documentModel.copy,
                  witness: (text, child) => text.isEmpty
                      ? child
                      : TimelineMarkdown(
                          key: StudioDriverKeys.planDetailsMarkdown,
                          id: identity,
                          text: text,
                          isSafeLink: (url) => safeExternalWebUrl(url) != null,
                          onLink: (raw) {
                            final url = safeExternalWebUrl(raw);
                            if (url == null || !current()) return;
                            unawaited(
                              ref
                                  .read(externalUrlLauncherProvider)(url)
                                  .catchError((Object error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(
                                              content: Text(error.toString()),
                                            ),
                                          );
                                    }
                                  }),
                            );
                          },
                          imageBuilder: (_, url) =>
                              TimelineRemoteImageConnector(url: url),
                        ),
                ),
              ],
            ),
    );
  }
}
