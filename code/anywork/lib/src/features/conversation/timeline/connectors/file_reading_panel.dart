import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../platform/external_url_launcher.dart';
import '../views/markdown_document_body.dart';
import '../widgets/timeline_markdown.dart';
import 'timeline_media_connector.dart';

/// A user-selected read, local to the shell. It never enters business state.
final class FileReadingRequest {
  const FileReadingRequest({
    required this.identity,
    required this.filename,
    required this.readBytes,
    required this.isActive,
  });
  final Object identity;
  final String filename;
  final Future<Uint8List> Function() readBytes;
  final bool Function() isActive;
}

class FileReadingScope extends InheritedWidget {
  const FileReadingScope({
    super.key,
    required this.onOpen,
    required super.child,
  });
  final ValueChanged<FileReadingRequest> onOpen;

  static FileReadingScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileReadingScope>();

  @override
  bool updateShouldNotify(FileReadingScope oldWidget) =>
      onOpen != oldWidget.onOpen;
}

class _FileReadingExpiredException implements Exception {
  const _FileReadingExpiredException();
}

class _FileReadingClosedException implements Exception {
  const _FileReadingClosedException();
}

class FileReadingPanel extends ConsumerStatefulWidget {
  const FileReadingPanel({super.key, required this.request});

  final FileReadingRequest request;

  @override
  ConsumerState<FileReadingPanel> createState() => _FileReadingPanelState();
}

class _FileReadingPanelState extends ConsumerState<FileReadingPanel> {
  late Future<String> _text;
  int _attempt = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(covariant FileReadingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.request.identity != oldWidget.request.identity) _start();
  }

  void _start() {
    final attempt = ++_attempt;
    final request = widget.request;
    _text = () async {
      if (!request.isActive()) throw const _FileReadingExpiredException();
      final bytes = await request.readBytes();
      if (!mounted || attempt != _attempt || !request.isActive()) {
        throw const _FileReadingClosedException();
      }
      return utf8.decode(bytes);
    }();
    _text.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }

  @override
  void dispose() {
    ++_attempt;
    super.dispose();
  }

  String _formatError(BuildContext context, Object error) {
    final l10n = context.l10n;
    if (error is _FileReadingExpiredException) return l10n.fileReadingExpired;
    if (error is _FileReadingClosedException) return l10n.fileReadingClosed;
    return l10n.fileReadingFailed('$error');
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    key: ValueKey(widget.request.identity),
    future: _text,
    builder: (context, snapshot) => FileDocumentView(
      identity: widget.request.identity,
      body: snapshot.connectionState != ConnectionState.done
          ? const Center(child: CircularProgressIndicator())
          : snapshot.hasError
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_formatError(context, snapshot.error!)),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: widget.request.isActive()
                      ? () => setState(_start)
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: Text(context.l10n.sidebarRetry),
                ),
              ],
            )
          : TimelineMarkdown(
              id: 'file:${widget.request.identity}',
              text: snapshot.requireData,
              isSafeLink: (url) => safeExternalWebUrl(url) != null,
              onLink: (raw) {
                final url = safeExternalWebUrl(raw);
                if (url == null || !widget.request.isActive()) return;
                unawaited(
                  ref.read(externalUrlLauncherProvider)(url).catchError((
                    Object error,
                  ) {
                    if (!mounted || !context.mounted) return;
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(error.toString())));
                  }),
                );
              },
              imageBuilder: (_, url) => TimelineRemoteImageConnector(url: url),
            ),
    ),
  );
}

/// Pure document reading surface shared across Plan and Markdown files.
class FileDocumentView extends StatefulWidget {
  const FileDocumentView({
    super.key,
    required this.identity,
    required this.body,
  });

  final Object identity;
  final Widget body;

  @override
  State<FileDocumentView> createState() => _FileDocumentViewState();
}

class _FileDocumentViewState extends State<FileDocumentView> {
  final _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant FileDocumentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.identity != oldWidget.identity && _scroll.hasClients) {
      _scroll.jumpTo(0);
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final body = MarkdownDocumentBody(child: widget.body);
    return Material(
      key: const ValueKey('file-reading-panel'),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SelectionArea(
        child: Scrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            key: const ValueKey('file-reading-scroll'),
            controller: _scroll,
            primary: false,
            child: body,
          ),
        ),
      ),
    );
  }
}
