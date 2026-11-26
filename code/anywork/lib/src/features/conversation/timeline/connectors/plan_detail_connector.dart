import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../../../shared/studio_driver_keys.dart';
import '../../acp/view_models/acp_session_view_model.dart';
import '../view_models/plan_document_view_model.dart';
import '../views/plan_detail_view.dart';
export '../views/plan_detail_view.dart'
    show PlanDetailStatus, PlanDetailStatusBadge, planDetailStatusFromRuntime;
import '../widgets/timeline_markdown.dart';
import 'timeline_media_connector.dart';

class PlanDetailConnector extends ConsumerWidget {
  const PlanDetailConnector({
    super.key,
    required this.threadId,
    required this.identity,
  });

  final String threadId;
  final String identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = planDocumentProvider(threadId);
    final result = ref.watch(query);
    Widget loading() => LinearProgressIndicator(
      semanticsLabel: context.l10n.timelineItemBodyLoading,
    );
    return PlanDetailView(
      identity: identity,
      body: result.when<Widget?>(
        skipLoadingOnRefresh: false,
        loading: loading,
        error: (error, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(error is FormatException ? error.message : error.toString()),
            TextButton(
              key: const ValueKey('plan-document-retry'),
              onPressed: () => ref.invalidate(query),
              child: Text(context.l10n.runtimeFatalRetry),
            ),
          ],
        ),
        data: (readout) {
          if (readout == null || !readout.isCurrent()) return loading();
          final document = readout.plan?.document;
          if (document == null || document.markdown.isEmpty) return null;
          return TimelineMarkdown(
            key: StudioDriverKeys.planDetailsMarkdown,
            id: identity,
            text: document.markdown,
            isSafeLink: (url) => safeExternalWebUrl(url) != null,
            onLink: (raw) {
              final url = safeExternalWebUrl(raw);
              if (url == null || !context.mounted || !readout.isCurrent()) {
                return;
              }
              unawaited(
                ref.read(externalUrlLauncherProvider)(url).catchError((
                  Object error,
                ) {
                  if (context.mounted && readout.isCurrent()) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }
                }),
              );
            },
            imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
          );
        },
      ),
    );
  }
}

/// ACP Host MCP 实施计划展示连接器，与 Native 共用 [PlanDetailView] 与 Markdown 安全规则。
class AcpPlanDetailConnector extends ConsumerWidget {
  const AcpPlanDetailConnector({
    super.key,
    required this.threadId,
    required this.identity,
  });

  final String threadId;
  final String identity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(
      acpConversationStateProvider(threadId)
          .select((value) => value.value?.workflowState?.plan),
    );
    final markdown = plan?.document?.markdown;
    return PlanDetailView(
      identity: identity,
      body: markdown == null || markdown.isEmpty
          ? null
          : TimelineMarkdown(
              key: StudioDriverKeys.planDetailsMarkdown,
              id: identity,
              text: markdown,
              isSafeLink: (url) => safeExternalWebUrl(url) != null,
              onLink: (raw) {
                final url = safeExternalWebUrl(raw);
                if (url == null) return;
                unawaited(
                  ref.read(externalUrlLauncherProvider)(url).catchError((
                    Object error,
                  ) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(error.toString())));
                    }
                  }),
                );
              },
              imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
            ),
    );
  }
}
