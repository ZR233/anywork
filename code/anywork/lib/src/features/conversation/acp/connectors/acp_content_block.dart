import 'dart:async';

import 'package:anywork_client/acp_sessions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../../platform/external_url_launcher.dart';
import '../../timeline/widgets/timeline_image_view.dart';
import '../../timeline/widgets/timeline_markdown.dart';
import '../view_models/acp_content_view_model.dart';

class AcpContentBlock extends ConsumerWidget {
  const AcpContentBlock({super.key, required this.id, required this.content});

  final String id;
  final AcpContentBlockView content;

  @override
  Widget build(BuildContext context, WidgetRef ref) => switch (content) {
    AcpTextContentView(:final text) => TimelineMarkdown(
      id: id,
      text: text,
      isSafeLink: (url) => safeExternalWebUrl(url) != null,
      onLink: (url) => _open(context, ref, url),
      // Markdown URLs do not grant local file access or implicit network reads.
      imageBuilder: (_, url) => _ResourceLink(
        label: url,
        uri: url,
        onOpen: safeExternalWebUrl(url) == null
            ? null
            : () => _open(context, ref, url),
      ),
    ),
    final AcpImageContentView image =>
      ref
          .watch(acpImageViewModelProvider(image))
          .when(
            data: (data) => TimelineImageView(
              itemId: id,
              attachment: data.attachment,
              isTool: false,
              active: true,
              imageIdentity: image,
              bytes: data.bytes,
              width: data.attachment.width,
              height: data.attachment.height,
            ),
            loading: () => const SizedBox.square(
              dimension: 32,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            error: (error, _) => Text('图片读取失败：$error'),
          ),
    AcpAudioContentView(:final mimeType) => ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.audio_file_outlined),
      title: Text('音频 · $mimeType'),
      subtitle: const Text('当前阅读器不支持音频播放'),
    ),
    AcpResourceLinkView(:final title, :final name, :final uri) => _ResourceLink(
      label: title ?? name,
      uri: uri,
      onOpen: safeExternalWebUrl(uri) == null
          ? null
          : () => _open(context, ref, uri),
    ),
    AcpEmbeddedResourceView(
      resource: AcpTextResourceContentsView(:final uri, :final text),
    ) =>
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(uri),
        children: [
          Align(alignment: Alignment.centerLeft, child: SelectableText(text)),
        ],
      ),
    AcpEmbeddedResourceView(
      resource: AcpBlobResourceContentsView(:final uri, :final mimeType),
    ) =>
      _ResourceLink(label: mimeType ?? '二进制资源', uri: uri),
  };

  void _open(BuildContext context, WidgetRef ref, String url) {
    final safe = safeExternalWebUrl(url);
    if (safe == null) return;
    final launcher = ref.read(externalUrlLauncherProvider);
    unawaited(
      launcher(safe).catchError((Object error) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开链接：$error')));
      }),
    );
  }
}

class _ResourceLink extends StatelessWidget {
  const _ResourceLink({required this.label, required this.uri, this.onOpen});

  final String label;
  final String uri;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.insert_drive_file_outlined),
    title: Text(label),
    subtitle: SelectableText(uri),
    onTap: onOpen,
  );
}
