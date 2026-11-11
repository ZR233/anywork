import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../../timeline/widgets/timeline_image_view.dart';
import '../state/acp_view_state.dart';
import '../view_models/acp_content_view_model.dart';
import '../view_models/acp_timeline_view_model.dart';
import '../views/acp_conversation_content_view.dart';
import 'acp_plan_card_connector.dart';

/// Thin Riverpod connector binding [acpTimelineHeaderViewModelProvider] and
/// per-index [acpTimelineItemViewModelProvider] to [AcpConversationContentView].
class AcpTimelineConnector extends ConsumerWidget {
  const AcpTimelineConnector({super.key, required this.threadId});

  final String threadId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final header = ref.watch(acpTimelineHeaderViewModelProvider(threadId));
    return AcpConversationContentView(
      threadId: threadId,
      header: header,
      planCard: header.hasPlan
          ? AcpPlanCardConnector(threadId: threadId)
          : null,
      itemBuilder: (context, index) =>
          _AcpTimelineItemConnector(threadId: threadId, index: index),
    );
  }
}

class _AcpTimelineItemConnector extends ConsumerWidget {
  const _AcpTimelineItemConnector({
    required this.threadId,
    required this.index,
  });

  final String threadId;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(acpTimelineItemViewModelProvider(threadId, index));
    if (item == null) return const SizedBox.shrink();
    return AcpTimelineEntryView(
      item: item,
      isSafeLink: (url) => safeExternalWebUrl(url) != null,
      onOpenLink: (url) => _openSafeExternalLink(context, ref, url),
      imageBuilder: (itemId, image) =>
          _AcpDecodedImageConnector(itemId: itemId, image: image),
    );
  }

  void _openSafeExternalLink(
    BuildContext context,
    WidgetRef ref,
    String rawUrl,
  ) {
    final safe = safeExternalWebUrl(rawUrl);
    if (safe == null) return;
    final launcher = ref.read(externalUrlLauncherProvider);
    unawaited(
      launcher(safe).catchError((Object error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.acpMediaOpenLinkFailed('$error')),
          ),
        );
      }),
    );
  }
}

class _AcpDecodedImageConnector extends ConsumerWidget {
  const _AcpDecodedImageConnector({required this.itemId, required this.image});

  final String itemId;
  final AcpImageBlockPresentation image;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payload = AcpImagePayload(
      cacheKey: image.cacheKey,
      dataBase64: image.dataBase64,
      mimeType: image.mimeType,
      uri: image.uri,
    );
    final decoded = ref.watch(acpDecodedImageProvider(payload));
    return decoded.when(
      data: (data) => TimelineImageView(
        itemId: itemId,
        attachment: data.attachment,
        isTool: false,
        active: true,
        imageIdentity: payload,
        bytes: data.bytes,
        width: data.attachment.width,
        height: data.attachment.height,
      ),
      loading: () => const SizedBox.square(
        dimension: 32,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      error: (error, _) => Text(
        context.l10n.acpMediaImageLoadFailed('$error'),
        style: Theme.of(context).textTheme.bodySmall
            ?.copyWith(color: Theme.of(context).colorScheme.error),
      ),
    );
  }
}
