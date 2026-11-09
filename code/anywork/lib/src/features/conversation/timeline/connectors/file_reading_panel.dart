import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class FileReadingPanel extends ConsumerStatefulWidget {
  const FileReadingPanel({
    super.key,
    required this.request,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final FileReadingRequest request;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;

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
      if (!request.isActive()) throw StateError('文件读取资格已失效');
      final bytes = await request.readBytes();
      if (!mounted || attempt != _attempt || !request.isActive()) {
        throw StateError('文件阅读已关闭或切换');
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

  @override
  Widget build(BuildContext context) => FutureBuilder<String>(
    key: ValueKey(widget.request.identity),
    future: _text,
    builder: (context, snapshot) => FileDocumentView(
      identity: widget.request.identity,
      filename: widget.request.filename,
      onClose: widget.onClose,
      onToggleReadingMode: widget.onToggleReadingMode,
      fullWidth: widget.fullWidth,
      body: snapshot.connectionState != ConnectionState.done
          ? const Center(child: CircularProgressIndicator())
          : snapshot.hasError
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('文件读取失败：${snapshot.error}'),
                TextButton.icon(
                  onPressed: widget.request.isActive()
                      ? () => setState(_start)
                      : null,
                  icon: const Icon(Icons.refresh),
                  label: const Text('重试'),
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

/// The same quiet document surface as Plan, without Plan status or decisions.
class FileDocumentView extends StatefulWidget {
  const FileDocumentView({
    super.key,
    required this.identity,
    required this.filename,
    required this.body,
    required this.onClose,
    this.onToggleReadingMode,
    this.fullWidth = false,
  });
  final Object identity;
  final String filename;
  final Widget body;
  final VoidCallback onClose;
  final VoidCallback? onToggleReadingMode;
  final bool fullWidth;

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
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final header = Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
        child: Row(
          children: [
            const Icon(Icons.article_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Tooltip(
                message: widget.filename,
                child: Text(
                  widget.filename,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            if (widget.onToggleReadingMode != null)
              IconButton(
                tooltip: widget.fullWidth ? '恢复分栏' : '展开阅读',
                onPressed: widget.onToggleReadingMode,
                icon: Icon(
                  widget.fullWidth
                      ? Icons.vertical_split_outlined
                      : Icons.open_in_full,
                ),
              ),
            IconButton(
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: widget.onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
      final body = MarkdownDocumentBody(child: widget.body);
      Widget scroll(Widget child) => Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: const ValueKey('file-reading-scroll'),
          controller: _scroll,
          primary: false,
          child: child,
        ),
      );
      return Material(
        key: const ValueKey('file-reading-panel'),
        color: Theme.of(context).colorScheme.surfaceContainerLowest,
        child: SelectionArea(
          child: constraints.maxHeight < 260
              ? scroll(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SelectionContainer.disabled(child: header),
                      const Divider(height: 1),
                      body,
                    ],
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SelectionContainer.disabled(child: header),
                    const Divider(height: 1),
                    Expanded(child: scroll(body)),
                  ],
                ),
        ),
      );
    },
  );
}
