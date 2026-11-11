import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../../../shared/studio_chrome.dart';
import '../../timeline/widgets/timeline_activity_row.dart';
import '../../timeline/widgets/timeline_markdown.dart';
import '../state/acp_view_state.dart';

typedef AcpImageWidgetBuilder = Widget Function(
  String itemId,
  AcpImageBlockPresentation image,
);

bool _defaultIsSafeLink(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || uri.host.isEmpty) return false;
  final scheme = uri.scheme.toLowerCase();
  return scheme == 'http' || scheme == 'https';
}

/// Pure presentation widget for a single ACP content block.
///
/// Consumes only immutable [AcpContentBlockPresentation] values and callbacks;
/// never imports Riverpod, platform launchers, or live ACP session owners.
class AcpContentBlockView extends StatelessWidget {
  const AcpContentBlockView({
    super.key,
    required this.id,
    required this.block,
    this.isSafeLink = _defaultIsSafeLink,
    this.onOpenLink,
    this.imageBuilder,
    this.textStyle,
  });

  final String id;
  final AcpContentBlockPresentation block;
  final bool Function(String url) isSafeLink;
  final ValueChanged<String>? onOpenLink;
  final AcpImageWidgetBuilder? imageBuilder;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) => switch (block) {
    AcpTextBlockPresentation(:final text) => TimelineMarkdown(
      id: id,
      text: text,
      style: textStyle,
      isSafeLink: isSafeLink,
      onLink: (url) {
        if (isSafeLink(url)) {
          onOpenLink?.call(url);
        }
      },
      // Markdown image links do not trigger implicit network/file reads; render
      // a safe clickable/copyable reference card instead.
      imageBuilder: (_, url) => _AcpResourceCard(
        icon: Icons.image_outlined,
        label: url,
        uri: url,
        canOpen: isSafeLink(url) && onOpenLink != null,
        onOpen: () => onOpenLink?.call(url),
      ),
    ),
    final AcpImageBlockPresentation image =>
      imageBuilder != null
          ? imageBuilder!(id, image)
          : _FallbackImageFrame(image: image),
    AcpAudioBlockPresentation(:final mimeType) => _AcpAudioCard(
      mimeType: mimeType,
    ),
    AcpResourceLinkBlockPresentation(
      :final label,
      :final uri,
      :final description,
      :final mimeType,
      :final canOpenExternal,
    ) =>
      _AcpResourceCard(
        icon: canOpenExternal
            ? Icons.open_in_new_rounded
            : Icons.insert_drive_file_outlined,
        label: label,
        uri: uri,
        description: description,
        badgeText: mimeType,
        canOpen: canOpenExternal && onOpenLink != null,
        onOpen: () => onOpenLink?.call(uri),
      ),
    AcpTextResourceBlockPresentation(
      :final uri,
      :final text,
      :final mimeType,
    ) =>
      _AcpEmbeddedTextResource(uri: uri, text: text, mimeType: mimeType),
    AcpBlobResourceBlockPresentation(
      :final uri,
      :final mimeType,
      :final byteCount,
    ) =>
      _AcpResourceCard(
        icon: Icons.inventory_2_outlined,
        label: context.l10n.acpContentResourceLabel,
        uri: uri,
        description: context.l10n.acpContentBinarySummary(
          mimeType ?? 'application/octet-stream',
          byteCount,
        ),
        canOpen: false,
      ),
  };
}

class _FallbackImageFrame extends StatelessWidget {
  const _FallbackImageFrame({required this.image});

  final AcpImageBlockPresentation image;

  @override
  Widget build(BuildContext context) {
    try {
      final bytes = base64Decode(image.dataBase64);
      return ClipRRect(
        borderRadius: BorderRadius.circular(StudioRadii.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: context.colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(StudioRadii.md),
            border: Border.all(color: context.colors.outlineVariant),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 300),
            child: Image.memory(bytes, fit: BoxFit.contain),
          ),
        ),
      );
    } on FormatException {
      return StudioInlineMessage(
        icon: Icons.broken_image_outlined,
        message: context.l10n.timelineImageLoadFailed,
        color: context.colors.error,
      );
    }
  }
}

class _AcpAudioCard extends StatelessWidget {
  const _AcpAudioCard({required this.mimeType});

  final String mimeType;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLow,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StudioIconBadge(icon: Icons.graphic_eq_rounded, size: 32),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.l10n.acpContentAudioLabel,
                  style: context.text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  mimeType,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontFamily: studioCodeFontFamily,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AcpResourceCard extends StatelessWidget {
  const _AcpResourceCard({
    required this.icon,
    required this.label,
    required this.uri,
    this.description,
    this.badgeText,
    this.canOpen = false,
    this.onOpen,
  });

  final IconData icon;
  final String label;
  final String uri;
  final String? description;
  final String? badgeText;
  final bool canOpen;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    return StudioPanel(
      backgroundColor: context.colors.surfaceContainerLow,
      borderColor: context.colors.outlineVariant,
      radius: StudioRadii.md,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 18, color: context.colors.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (badgeText case final mime? when mime.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      StudioPill(label: mime),
                    ],
                  ],
                ),
                if (description case final desc?
                    when desc.trim().isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    desc,
                    style: context.text.bodySmall?.copyWith(
                      color: context.colors.onSurfaceVariant,
                    ),
                  ),
                ],
                const SizedBox(height: 3),
                SelectableText(
                  uri,
                  maxLines: 1,
                  style: context.text.labelSmall?.copyWith(
                    color: context.colors.onSurfaceVariant,
                    fontFamily: studioCodeFontFamily,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: context.l10n.acpContentCopyUri,
            visualDensity: VisualDensity.compact,
            onPressed: () => Clipboard.setData(ClipboardData(text: uri)),
            icon: const Icon(Icons.copy_rounded, size: 15),
          ),
          if (canOpen && onOpen != null)
            TextButton.icon(
              onPressed: onOpen,
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: Text(context.l10n.acpContentOpenLink),
            ),
        ],
      ),
    );
  }
}

class _AcpEmbeddedTextResource extends StatefulWidget {
  const _AcpEmbeddedTextResource({
    required this.uri,
    required this.text,
    this.mimeType,
  });

  final String uri;
  final String text;
  final String? mimeType;

  @override
  State<_AcpEmbeddedTextResource> createState() =>
      _AcpEmbeddedTextResourceState();
}

class _AcpEmbeddedTextResourceState extends State<_AcpEmbeddedTextResource> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(StudioRadii.xs),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: TimelineActivityRow(
              icon: Icons.description_outlined,
              label: widget.uri,
              meta: widget.mimeType,
              expanded: _expanded,
              expandable: true,
              tooltip: widget.uri,
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(
              left: TimelineActivityRow.contentIndent,
              top: 4,
              bottom: 4,
            ),
            child: StudioCodeBlock(
              text: widget.text,
              language: widget.mimeType ?? widget.uri,
              maxHeight: 260,
            ),
          ),
      ],
    );
  }
}
