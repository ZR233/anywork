import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_history_projection.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/timeline_message_controller.dart';
import 'timeline_member_atom.dart';
import '../widgets/timeline_children_view.dart';
import 'timeline_content_connector.dart';
import 'timeline_media_connector.dart';

/// Expanded originals own an independent History reader, never a second Main.
class TimelineChildrenConnector extends StatefulWidget {
  const TimelineChildrenConnector({
    super.key,
    required this.repository,
    required this.threadId,
    required this.parentId,
    this.monotonicMicros,
    this.onContentLayout,
    this.readAttachment,
    this.registerDisplay,
    this.isParentActive,
    this.parentRetirement,
  });
  final ConversationRepository repository;
  final String threadId;
  final String parentId;
  final int Function()? monotonicMicros;
  final void Function(String, int)? onContentLayout;
  final Future<Uint8List> Function(String id)? readAttachment;
  final VoidCallback Function(TimelineChildrenDisplay display)? registerDisplay;
  final bool Function()? isParentActive;
  final ValueListenable<bool>? parentRetirement;

  @override
  State<TimelineChildrenConnector> createState() =>
      _TimelineChildrenConnectorState();
}

class _TimelineChildrenConnectorState extends State<TimelineChildrenConnector>
    implements TimelineChildrenDisplay {
  InMemoryChatController? _controller = InMemoryChatController();
  late final TimelineImageResources _images = TimelineImageResources(
    threadId: widget.threadId,
  );
  TimelineMessageController? _adapter;
  HistoryReader? _reader;
  HistoryCut? _cut;
  String? _before;
  Object? _error;
  bool _ready = false;
  bool _retired = false;
  bool _opening = false;
  Future<void>? _older;
  Future<void>? _closing;
  Future<void>? _retrying;
  late final Future<void> _opened;
  final _openingDone = Completer<void>();
  int _mutations = 0;
  int _displayGeneration = 0;
  int _appliedSets = 0;
  int _appliedPrepends = 0;
  int _appliedAppends = 0;
  VoidCallback? _unregisterDisplay;
  final Set<TimelineMemberDisplay> _members = {};

  bool get _parentActive =>
      !(_parentRetirement?.value ?? false) &&
      (widget.isParentActive?.call() ?? true) &&
      !_retired &&
      mounted;

  @override
  String get parentId => widget.parentId;
  @override
  int get generation => _displayGeneration;
  @override
  bool get isCurrent => _ready && _parentActive && _reader != null;
  @override
  bool get ready => _ready;
  @override
  String? get olderCursor => _before;
  @override
  bool get loadingOlder => _older != null;
  @override
  Object? get error => _error;
  @override
  Iterable<Message> get messages =>
      isCurrent ? _controller?.messages ?? const [] : const [];
  @override
  int get appliedSets => _appliedSets;
  @override
  int get appliedPrepends => _appliedPrepends;
  @override
  int get appliedAppends => _appliedAppends;
  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    for (final member in _members) {
      yield* member.windows;
    }
  }

  @override
  void initState() {
    super.initState();
    _adapter = TimelineMessageController(_controller!, generation: 0);
    _opened = _openingDone.future;
    widget.parentRetirement?.addListener(_parentRetired);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opening) return;
    _opening = true;
    _openingDone.complete(_open());
  }

  @override
  void didUpdateWidget(covariant TimelineChildrenConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.parentRetirement != widget.parentRetirement) {
      oldWidget.parentRetirement?.removeListener(_parentRetired);
      widget.parentRetirement?.addListener(_parentRetired);
    }
    if (oldWidget.threadId != widget.threadId ||
        oldWidget.parentId != widget.parentId ||
        !_parentActive) {
      _retireOwner();
    }
  }

  void _parentRetired() {
    if (_parentRetirement?.value ?? false) _retireOwner();
  }

  Future<void> _open() async {
    try {
      final reader = await widget.repository.openHistoryReader(widget.threadId);
      if (!_parentActive) {
        reader.requestClose();
        await reader.close();
        return;
      }
      _reader = reader;
      _cut = await reader.capture();
      await _load(reset: true);
      if (!_parentActive) return;
      setState(() {
        _ready = true;
        _error = null;
      });
      _registerCurrent();
    } catch (error) {
      if (mounted && _parentActive) setState(() => _error = error);
    }
  }

  Future<void> _load({required bool reset}) async {
    final reader = _reader;
    final cut = _cut;
    if (reader == null || cut == null) return;
    final page = await reader.eventsPage(
      query: OriginalsHistoryEvents(
        queryClass: 'conversation',
        parentId: widget.parentId,
      ),
      cut: cut,
      cursor: reset ? null : _before,
      demand: HistoryDemand(maxRows: 50, maxBytes: 256 * 1024),
    );
    if (!_parentActive || !identical(_reader, reader)) {
      throw const StaleConversationScope();
    }
    final blocks = [
      for (final detail in page.entries)
        if (TimelineHistoryProjection.eventDetail(detail) case final block?)
          block,
    ];
    final adapter = _adapter;
    if (adapter == null) throw const StaleConversationScope();
    _mutations++;
    try {
      await adapter.applyBlocks(
        blocks,
        reset ? TimelineApplyPlacement.set : TimelineApplyPlacement.prepend,
      );
      if (reset) {
        _appliedSets++;
      } else {
        _appliedPrepends++;
      }
      _before = page.next;
    } finally {
      _mutations--;
      _releaseController();
    }
  }

  Future<void> _loadOlder(HistoryReader reader, int generation) {
    if (!_ready || _before == null || _error != null) return Future.value();
    final existing = _older;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _older = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        try {
          await _load(reset: false);
          if (!isCurrent || generation != _displayGeneration) {
            throw const StaleConversationScope();
          }
        } catch (error) {
          if (isCurrent && generation == _displayGeneration) {
            setState(() => _error = error);
          }
        } finally {
          if (identical(_older, completion.future)) _older = null;
        }
      }),
    );
    return completion.future;
  }

  void _registerCurrent() {
    if (isCurrent && _unregisterDisplay == null) {
      _unregisterDisplay = widget.registerDisplay?.call(this);
    }
  }

  void _unregister() {
    final unregister = _unregisterDisplay;
    _unregisterDisplay = null;
    unregister?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_retired) return const SizedBox.shrink();
    final controller = _controller;
    final reader = _reader;
    final generation = _displayGeneration;
    if (!_ready || controller == null || reader == null) {
      if (_error != null) return _failure();
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    bool active() => isCurrent && generation == _displayGeneration;
    final members = TimelineChildrenView(
      controller: controller,
      generation: generation,
      isDisplayActive: active,
      atomBuilder: (item) => TimelineMemberAtom(
        key: ValueKey((generation, item.id)),
        displayId: item.id,
        record: item.displayRecord!,
        threadId: widget.threadId,
        retirement: widget.parentRetirement,
        isActive: active,
        images: _images,
        readAttachment: widget.readAttachment,
        monotonicMicros: widget.monotonicMicros,
        onContentLayout: widget.onContentLayout,
        registerDisplay: (display) {
          _members.add(display);
          return () => _members.remove(display);
        },
      ),
      onLoadOlder: _before == null
          ? null
          : () => _loadOlder(reader, generation),
      attachmentBuilder: (item) => TimelineAttachmentsConnector(
        item: item,
        resources: _images,
        readAttachment: widget.readAttachment,
        isActive: active,
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [if (_error != null) _failure(), members],
    );
  }

  Widget _failure() => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(_error.toString()),
      TextButton(
        key: const ValueKey('timeline-members-retry'),
        onPressed: _retired || !_parentActive || _retrying != null
            ? null
            : _retry,
        child: const Text('重试读取'),
      ),
    ],
  );

  void _retry() {
    if (_retired || !_parentActive || _retrying != null) return;
    setState(() => _error = null);
    final request = _ready ? _load(reset: false) : _open();
    _retrying = request;
    unawaited(
      request.whenComplete(() {
        if (identical(_retrying, request)) _retrying = null;
        if (mounted && !_retired) setState(() {});
      }),
    );
  }

  @override
  void dispose() {
    widget.parentRetirement?.removeListener(_parentRetired);
    _retireOwner();
    super.dispose();
  }

  void _retireOwner() {
    if (_retired) return;
    _retired = true;
    _unregister();
    _images.retire();
    _displayGeneration++;
    _adapter?.retireDisplays();
    _reader?.requestClose();
    _releaseController();
    unawaited(_closeOwned());
  }

  Future<void> _closeOwned() =>
      _closing ??= _close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            context: ErrorDescription('closing expanded History reader'),
          ),
        );
      });

  Future<void> _close() async {
    await _opened;
    await _retrying;
    final reader = _reader;
    _reader = null;
    await reader?.close();
    _releaseController();
  }

  void _releaseController() {
    if (!_retired || _mutations != 0) return;
    final controller = _controller;
    _controller = null;
    final adapter = _adapter;
    _adapter = null;
    adapter?.dispose();
    _images.release();
    controller?.dispose();
  }
}
