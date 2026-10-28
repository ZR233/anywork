import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/timeline_commands.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../state/timeline_entry.dart';
import '../view_models/timeline_view_model.dart';
import '../views/timeline_view.dart';
import 'timeline_detail_connector.dart';
import 'timeline_media_connector.dart';

/// The canonical feature entry. It only borrows the selected display: navigation
/// owns visible demand; providers and widget disposal do not close sessions.
class TimelineConnector extends ConsumerWidget {
  const TimelineConnector({
    super.key,
    required this.threadId,
    this.planConfirmation,
    this.planExpanded = true,
    this.onPlanToggle,
  });
  final String threadId;
  final PlanConfirmationView? planConfirmation;
  final bool planExpanded;
  final VoidCallback? onPlanToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(timelineViewModelProvider(threadId));
    final owner = ref.read(timelineSessionOwnerProvider);
    final observedView = state.asData?.value;
    final view = observedView?.threadId == threadId ? observedView : null;
    final lease = owner.lease(threadId);
    void retry() => ref
        .read(anyworkClientProvider)
        .conversations
        .session(threadId)
        .content
        .refresh();
    if (view == null || lease == null) {
      final failedView =
          lease == null &&
              view?.connection == TimelineConnectionPhase.failed &&
              identical(owner.source.value, view)
          ? view
          : null;
      final failedSession = failedView == null
          ? null
          : ref
                .read(anyworkClientProvider)
                .conversations
                .existingSession(threadId);
      // Provider assembly errors are not content failures. Display them without
      // turning content.refresh into a provider reconstruction action.
      final providerError = view == null ? state.asError?.error : null;
      final error = providerError ?? view?.connectionError;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (providerError == null &&
                  view?.connection != TimelineConnectionPhase.failed)
                const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              Text(error?.toString() ?? context.l10n.workspaceLoading),
              if (failedView != null && failedSession != null)
                TextButton(
                  key: StudioDriverKeys.timelineRetryConnection,
                  onPressed: () {
                    if (!context.mounted ||
                        !identical(owner.source.value, failedView) ||
                        failedView.threadId != threadId ||
                        owner.lease(threadId) != null ||
                        failedView.connection !=
                            TimelineConnectionPhase.failed) {
                      return;
                    }
                    failedSession.content.refresh();
                  },
                  child: Text(context.l10n.sidebarRetry),
                ),
            ],
          ),
        ),
      );
    }
    bool active() =>
        identical(owner.lease(threadId), lease) && !lease.isRetired;
    void link(String raw) {
      final url = safeExternalWebUrl(raw);
      if (url == null || !active()) return;
      unawaited(
        ref.read(externalUrlLauncherProvider)(url).catchError((Object error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }),
      );
    }

    Future<Uint8List> readAttachment(String attachmentId) => ref
        .read(anyworkClientProvider)
        .readAttachmentBytes(threadId, attachmentId);
    void detail(String itemId, ThreadContentFieldView field) {
      if (!active()) return;
      unawaited(
        openTimelineDetail(
          context,
          lease: lease,
          itemId: itemId,
          field: field,
        ).catchError((Object error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }),
      );
    }

    final plan = planConfirmation;
    return TimelineView(
      key: lease.chatKey,
      threadId: threadId,
      view: view,
      controls: lease,
      onLoadOlder: () => active()
          ? owner.loadOlder(threadId, generation: lease.generation)
          : Future.value(),
      onRetryOlder: () => active()
          ? owner.retryOlder(threadId, generation: lease.generation)
          : Future.value(),
      onReturnLive: () =>
          active() ? owner.returnToLive(threadId) : Future.value(),
      onEnterHistory: () {
        if (active()) {
          unawaited(owner.dispatch(threadId, const TimelineEnterHistory()));
        }
      },
      onRetryConnection: () {
        if (active()) retry();
      },
      onDetail: detail,
      onLink: link,
      isSafeLink: (url) => safeExternalWebUrl(url) != null,
      imageBuilder: (_, message, index) => TimelineImageConnector(
        key: ValueKey((lease.generation, message.id)),
        message: message,
        index: index,
        item: timelineEntryOf(message)!.first,
        resources: lease.imageResources,
        readBytes: () => readAttachment(
          (message.metadata!['attachment'] as ThreadAttachmentView).id,
        ),
        isActive: active,
        onDetail: detail,
      ),
      remoteImageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
      groupMediaBuilder: (item) => TimelineGroupMediaConnector(
        key: ValueKey(item.id),
        item: item,
        resources: lease.imageResources,
        readAttachment: readAttachment,
        isActive: active,
        onDetail: detail,
      ),
      pendingPlanInteractionId: plan?.interactionId,
      planSummary: plan == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SelectionContainer.disabled(
                child: TextButton.icon(
                  key: StudioDriverKeys.planSummary,
                  onPressed: onPlanToggle,
                  icon: Icon(
                    planExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                  label: Text(plan.title),
                ),
              ),
            ),
    );
  }
}
