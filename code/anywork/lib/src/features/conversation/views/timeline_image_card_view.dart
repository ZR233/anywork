import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app/theme/studio_tokens.dart';
import '../../../diagnostics/studio_driver_keys.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../ui/attachments/attachment_preview.dart';
import '../../../ui/badges/studio_badges.dart';

/// Only UI props cross this boundary. Caption awaits its native typed source.
class TimelineImageCardView extends StatelessWidget {
  const TimelineImageCardView({
    required this.statusLabel,
    required this.isIssue,
    required this.diagnostics,
    this.media,
    super.key,
  });

  final String statusLabel;
  final bool isIssue;
  final Widget diagnostics;
  final Widget? media;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 700),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.colors.surfaceContainer,
          border: Border.all(color: context.colors.outlineVariant),
          borderRadius: BorderRadius.circular(StudioRadii.lg),
          boxShadow: StudioShadows.soft(context.colors.shadow),
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.image_outlined,
                    size: 16,
                    color: context.colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      context.l10n.timelineImageCardTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.titleSmall?.copyWith(
                        color: context.colors.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: StudioPill(
                      label: statusLabel,
                      tone: isIssue ? StudioTone.error : StudioTone.neutral,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              media ??
                  Container(
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: context.colors.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(StudioRadii.sm),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      context.l10n.timelineImageCardEmpty,
                      textAlign: TextAlign.center,
                      style: context.text.bodySmall?.copyWith(
                        color: context.colors.error,
                      ),
                    ),
                  ),
              diagnostics,
            ],
          ),
        ),
      ),
    ),
  );
}

class TimelineImageCardMediaView extends StatelessWidget {
  const TimelineImageCardMediaView({
    required this.entryId,
    required this.preview,
    this.width,
    this.height,
    this.onOpen,
    this.onRetry,
    super.key,
  });

  final String entryId;
  final AttachmentPreview preview;
  final int? width;
  final int? height;
  final VoidCallback? onOpen;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final imageWidth = width;
    final imageHeight = height;
    final aspect =
        imageWidth != null &&
            imageWidth > 0 &&
            imageHeight != null &&
            imageHeight > 0
        ? imageWidth / imageHeight
        : 16 / 9;
    return LayoutBuilder(
      builder: (context, constraints) => ClipRRect(
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: SizedBox(
          width: constraints.maxWidth,
          height: math.min(360.0, constraints.maxWidth / aspect),
          child: ColoredBox(
            color: context.colors.surfaceContainerHigh,
            child: switch (preview) {
              NoAttachmentPreview() || LoadingAttachmentPreview() => _loading(),
              FailedAttachmentPreview() => _failure(context),
              ReadyAttachmentPreview(:final image) => Image(
                image: image,
                fit: BoxFit.cover,
                frameBuilder: (context, child, frame, synchronous) =>
                    frame == null && !synchronous
                    ? _loading()
                    : Material(
                        color: Colors.transparent,
                        child: InkWell(
                          key: StudioDriverKeys.imageCardImage(entryId),
                          onTap: onOpen,
                          child: child,
                        ),
                      ),
                errorBuilder: (context, error, stack) => _failure(context),
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _loading() => const Center(
    child: SizedBox.square(
      dimension: 24,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
  );

  Widget _failure(BuildContext context) => Center(
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, color: context.colors.error),
            const SizedBox(height: 8),
            Text(
              context.l10n.timelineImageLoadFailed,
              textAlign: TextAlign.center,
              style: context.text.bodySmall?.copyWith(
                color: context.colors.error,
              ),
            ),
            TextButton.icon(
              key: StudioDriverKeys.imageCardRetry(entryId),
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: Text(context.l10n.timelineImageRetry),
            ),
          ],
        ),
      ),
    ),
  );
}

class TimelineImageCardDialog extends StatelessWidget {
  const TimelineImageCardDialog({
    required this.image,
    required this.onClose,
    this.filename,
    super.key,
  });

  final ImageProvider image;
  final String? filename;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Dialog(
    clipBehavior: Clip.antiAlias,
    child: SizedBox(
      width: math.min(
        1000.0,
        math.max(240.0, MediaQuery.sizeOf(context).width - 80),
      ),
      height: math.min(
        760.0,
        math.max(200.0, MediaQuery.sizeOf(context).height - 80),
      ),
      child: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    minScale: .5,
                    maxScale: 5,
                    child: Center(
                      child: Image(
                        image: image,
                        errorBuilder: (context, error, stack) => Center(
                          child: Text(context.l10n.timelineImageLoadFailed),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton.filledTonal(
                    key: StudioDriverKeys.timelineImageClose,
                    tooltip: context.l10n.timelineImageClose,
                    onPressed: onClose,
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          ),
          if (filename?.isNotEmpty == true)
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: context.colors.outlineVariant),
                ),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 96),
                child: SingleChildScrollView(
                  child: SelectionArea(
                    child: Text(filename!, style: context.text.titleSmall),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
