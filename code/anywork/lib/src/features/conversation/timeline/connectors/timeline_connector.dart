import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/models.dart';
import 'package:anywork_client/conversation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../domain/models/timeline_commands.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../composer/composer.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../presentation/providers/client_provider.dart';
import '../../../../presentation/view_models/timeline_session_owner.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../view_models/timeline_view_model.dart';
import '../views/timeline_view.dart';
import '../widgets/timeline_markdown.dart';
import '../widgets/plan_summary_card.dart';
import 'timeline_media_connector.dart';
import 'timeline_read_demand_viewport.dart';
import 'completion_run_connector.dart';
import 'timeline_canonical_payload_connector.dart';

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
    final owner = ref.watch(timelineSessionOwnerProvider);
    return TimelineReadDemandViewport(
      ownerIdentity: owner,
      onDemand: owner.updateReadDemand,
      child: _TimelineConnectorBody(
        threadId: threadId,
        planConfirmation: planConfirmation,
        planExpanded: planExpanded,
        onPlanToggle: onPlanToggle,
      ),
    );
  }
}

class _TimelineConnectorBody extends ConsumerStatefulWidget {
  const _TimelineConnectorBody({
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
  ConsumerState<_TimelineConnectorBody> createState() =>
      _TimelineConnectorBodyState();
}

class _TimelineConnectorBodyState
    extends ConsumerState<_TimelineConnectorBody> {
  Observation? _submissionsObservation;
  List<ComposerSubmission> _submissions = const [];
  String? _observedThreadId;

  void _observeSubmissions(String threadId) {
    _submissionsObservation?.cancel();
    _observedThreadId = threadId;
    final composer = ref
        .read(anyworkClientProvider)
        .drafts
        .existingComposer(threadId);
    if (composer == null) {
      _submissions = const [];
      return;
    }
    final watch = composer.submissions.watchLatest((value) {
      if (!mounted || _observedThreadId != threadId) return;
      setState(() => _submissions = value);
    });
    _submissions = watch.value;
    _submissionsObservation = watch.observation;
  }

  @override
  void initState() {
    super.initState();
    _observeSubmissions(widget.threadId);
  }

  @override
  void didUpdateWidget(covariant _TimelineConnectorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.threadId != widget.threadId) {
      _observeSubmissions(widget.threadId);
    }
  }

  @override
  void dispose() {
    _submissionsObservation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final threadId = widget.threadId;
    final state = ref.watch(timelineViewModelProvider(threadId));
    final owner = ref.read(timelineSessionOwnerProvider);
    final observedView = state.asData?.value;
    final view = observedView?.threadId == threadId ? observedView : null;
    final lease = owner.lease(threadId);
    void link(String raw) {
      final url = safeExternalWebUrl(raw);
      if (url == null ||
          !mounted ||
          _observedThreadId != threadId ||
          (lease?.isRetired ?? false) ||
          !identical(owner.lease(threadId), lease)) {
        return;
      }
      unawaited(
        ref.read(externalUrlLauncherProvider)(url).catchError((Object error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text(error.toString())));
          }
        }),
      );
    }

    void retry() => ref.read(timelineSessionOwnerProvider).refresh(threadId);
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
              Flexible(
                child: SingleChildScrollView(
                  child: Text(
                    error?.toString() ?? context.l10n.workspaceLoading,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  child: ComposerSubmissionList(
                    submissions: _submissions,
                    submissionControlsBuilder: (submission) =>
                        ComposerSubmissionControls(
                          target: ComposerTarget.thread(
                            threadId: widget.threadId,
                          ),
                          submission: submission,
                        ),
                    bodyBuilder: (id, text) => TimelineMarkdown(
                      id: id,
                      text: text,
                      onLink: link,
                      isSafeLink: (raw) => safeExternalWebUrl(raw) != null,
                      imageBuilder: (_, url) =>
                          TimelineRemoteImageConnector(url: url),
                    ),
                  ),
                ),
              ),
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
                    ref.read(timelineSessionOwnerProvider).refresh(threadId);
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
    // The reader may outlive this row and its WidgetRef when the shell opens
    // a document. Authority belongs to the original display lease.
    final readAttachmentBytes = ref
        .read(anyworkClientProvider)
        .readAttachmentBytes;
    Future<Uint8List> readAttachment(String id) async {
      if (!active()) throw const StaleConversationScope();
      final bytes = await readAttachmentBytes(threadId, id);
      if (!active()) throw const StaleConversationScope();
      return bytes;
    }

    final plan = widget.planConfirmation;
    return TimelineView(
      key: lease.chatKey,
      threadId: threadId,
      view: view,
      submissions: _submissions,
      submissionControlsBuilder: (submission) => ComposerSubmissionControls(
        target: ComposerTarget.thread(threadId: widget.threadId),
        submission: submission,
      ),
      controls: lease,
      canonicalPresentationBuilder: (item, render) =>
          TimelineCanonicalPayloadConnector(
            key: ValueKey((lease.generation, item.id)),
            item: item,
            threadId: threadId,
            openHistory: () => lease.openHistoryScope(),
            retirement: lease.retirement,
            isActive: active,
            render: render,
          ),
      groupMembersBuilder: (unit) => CompletionRunConnector(
        unit: unit,
        threadId: threadId,
        content: lease,
        images: lease.imageResources,
        readAttachment: readAttachment,
        monotonicMicros: () => owner.monotonicMicros,
        onContentLayout: (itemId, micros) {
          if (active()) owner.recordContentLayout(lease, itemId, micros);
        },
        onCurrentContentLayout: (itemId, micros) {
          if (active()) {
            owner.recordCurrentContentLayout(lease, itemId, micros);
          }
        },
        onCurrentContentUnmounted: (itemId) {
          if (active()) {
            owner.recordCurrentContentUnmounted(lease, itemId);
          }
        },
      ),
      monotonicMicros: () => owner.monotonicMicros,
      isDisplayActive: active,
      onContentLayout: (itemId, completedMicros) {
        if (active()) owner.recordContentLayout(lease, itemId, completedMicros);
      },
      onCurrentContentLayout: (itemId, completedMicros) {
        if (active()) {
          owner.recordCurrentContentLayout(lease, itemId, completedMicros);
        }
      },
      onCurrentContentUnmounted: (itemId) {
        if (active()) owner.recordCurrentContentUnmounted(lease, itemId);
      },
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
          unawaited(
            owner
                .dispatch(threadId, const TimelineEnterHistory())
                .catchError((Object _, StackTrace _) {}),
          );
        }
      },
      onRetryConnection: () {
        if (active()) retry();
      },
      attachmentBuilder: (item) => TimelineAttachmentsConnector(
        key: ValueKey((lease.generation, item.id)),
        item: item,
        resources: lease.imageResources,
        readAttachment: readAttachment,
        isActive: active,
      ),
      onLink: link,
      isSafeLink: (url) => safeExternalWebUrl(url) != null,
      remoteImageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
      pendingPlanInteractionId: plan?.interactionId,
      planSummary: plan == null
          ? null
          : Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SelectionContainer.disabled(
                child: PlanSummaryCard(
                  key: StudioDriverKeys.planSummary,
                  title: plan.title,
                  expanded: widget.planExpanded,
                  onToggle: widget.onPlanToggle,
                ),
              ),
            ),
    );
  }
}
