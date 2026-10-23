import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../platform/external_url_launcher.dart';
import '../widgets/conversation_markdown.dart';

/// Platform UI adaptation only. No Repository, body query or native capability
/// is given to the Markdown widget.
class MarkdownConnector extends ConsumerWidget {
  const MarkdownConnector({required this.id, required this.text,
    this.surface = MarkdownSurface.assistant, super.key});
  final String id;
  final String text;
  final MarkdownSurface surface;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ConversationMarkdown(
    id: id, text: text, surface: surface,
    linkAllowed: (url) => safeExternalWebUrl(url) != null,
    onLink: (url) async {
      final safe = safeExternalWebUrl(url);
      if (safe == null) return;
      try { await ref.read(externalUrlLauncherProvider)(safe); } catch (_) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.timelineExternalLinkOpenFailed)));
      }
    },
    imageBuilder: (context, url, alt) => RemoteMarkdownImageConnector(
      key: ValueKey((id, url)), url: url, alt: alt,
      enabled: surface == MarkdownSurface.assistant || surface == MarkdownSurface.panel),
  );
}

class RemoteMarkdownImageConnector extends StatefulWidget {
  const RemoteMarkdownImageConnector({required this.url, required this.alt,
    required this.enabled, super.key});
  final String url;
  final String alt;
  final bool enabled;
  @override
  State<RemoteMarkdownImageConnector> createState() => _RemoteMarkdownImageState();
}

class _RemoteMarkdownImageState extends State<RemoteMarkdownImageConnector> {
  ImageProvider? _image;

  @override
  void didUpdateWidget(covariant RemoteMarkdownImageConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) _image = null;
  }

  @override
  Widget build(BuildContext context) {
    final url = _safeImageUrl(widget.url);
    final image = _image;
    if (!widget.enabled || url == null) return Text(widget.alt.isEmpty ? widget.url : widget.alt);
    if (image == null) return TextButton.icon(
      onPressed: () => setState(() { _image = NetworkImage(url); }),
      icon: const Icon(Icons.image_outlined), label: Text(widget.alt.isEmpty ? url : widget.alt));
    return ConstrainedBox(constraints: const BoxConstraints(maxWidth: 360, maxHeight: 360),
      child: Image(image: image, fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => TextButton.icon(
          onPressed: () => setState(() { _image = null; }),
          icon: const Icon(Icons.broken_image_outlined), label: Text(context.l10n.sidebarRetry))));
  }
}

String? _safeImageUrl(String raw) {
  if (raw.isEmpty || raw.length > 8192 || raw.codeUnits.any((unit) => unit < 32 || unit == 127)) return null;
  final uri = Uri.tryParse(raw);
  return uri != null && uri.scheme.toLowerCase() == 'https' && uri.host.isNotEmpty ? uri.toString() : null;
}
