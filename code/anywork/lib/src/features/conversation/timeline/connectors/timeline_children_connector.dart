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
import 'timeline_media_connector.dart';

const _maxChildrenWindowDescriptors = 16;

enum _ChildrenPageDirection { older, newer }

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
  String? _pageCursor;
  String? _before;
  final List<({String? cursor, String? next})> _newer = [];
  ({_ChildrenPageDirection direction, String? cursor, int generation})?
  _failedPage;
  Object? _error;
  bool _ready = false;
  bool _retired = false;
  bool _opening = false;
  Future<void>? _pageLoading;
  Future<void>? _closing;
  Future<void>? _retrying;
  late final Future<void> _opened;
  final _openingDone = Completer<void>();
  int _mutations = 0;
  int _displayGeneration = 0;
  int _appliedSets = 0;
  final int _appliedPrepends = 0;
  final int _appliedAppends = 0;
  VoidCallback? _unregisterDisplay;
  final Set<TimelineMemberDisplay> _members = {};

  bool get _parentActive =>
      !(widget.parentRetirement?.value ?? false) &&
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
  bool get loadingOlder => _pageLoading != null;
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
    if (widget.parentRetirement?.value ?? false) _retireOwner();
  }

  Future<void> _open() async {
    HistoryReader? openingReader;
    try {
      final reader = openingReader = await widget.repository.openHistoryReader(
        widget.threadId,
      );
      if (!_parentActive) {
        reader.requestClose();
        await reader.close();
        return;
      }
      _reader = reader;
      _cut = await reader.capture();
      await _loadPage(cursor: null);
      if (!_parentActive) return;
      setState(() {
        _ready = true;
        _error = null;
      });
      _registerCurrent();
    } catch (error) {
      if (identical(_reader, openingReader)) {
        _reader = null;
        _cut = null;
      }
      if (openingReader != null) {
        openingReader.requestClose();
        await openingReader.close();
      }
      if (mounted && _parentActive) setState(() => _error = error);
    }
  }

  Future<void> _loadPage({required String? cursor}) async {
    final reader = _reader;
    final cut = _cut;
    if (reader == null || cut == null) return;
    final generation = _displayGeneration;
    final page = await reader.eventsPage(
      query: OriginalsHistoryEvents(
        queryClass: 'conversation',
        parentId: widget.parentId,
      ),
      cut: cut,
      cursor: cursor,
      demand: HistoryDemand(maxRows: 50, maxBytes: 256 * 1024),
    );
    if (!_parentActive ||
        !identical(_reader, reader) ||
        generation != _displayGeneration) {
      throw const StaleConversationScope();
    }
    if (page.cut != cut) {
      throw const ConversationContinuityError(
        'Children page changed its fixed History cut',
      );
    }
    final next = page.next;
    if (next != null && next.isEmpty) {
      throw const ConversationContinuityError(
        'Children page returned an empty History cursor',
      );
    }
    if (cursor != null &&
        (page.next == cursor || (page.entries.isEmpty && page.next != null))) {
      throw const ConversationContinuityError(
        'Children page made no bounded cursor progress',
      );
    }
    final blocks = [
      for (final detail in page.entries)
        ?TimelineHistoryProjection.eventDetail(detail, cut: cut),
    ];
    final ids = <String>{};
    if (blocks.any((block) => block.id.isEmpty || !ids.add(block.id))) {
      throw const ConversationContinuityError(
        'Children page returned duplicate or empty row identities',
      );
    }
    final adapter = _adapter;
    if (adapter == null) throw const StaleConversationScope();
    _mutations++;
    try {
      if (!_ready) {
        await adapter.applyBlocks(blocks, TimelineApplyPlacement.set);
        _appliedSets++;
      } else {
        await adapter.reconcileBlocks(blocks);
      }
      if (!_parentActive ||
          !identical(_reader, reader) ||
          generation != _displayGeneration) {
        throw const StaleConversationScope();
      }
      _pageCursor = cursor;
      _before = next;
    } finally {
      _mutations--;
      _releaseController();
    }
  }

  Future<void> _loadOlder(HistoryReader reader, int generation) {
    final cursor = _before;
    if (!_ready ||
        cursor == null ||
        _error != null ||
        !identical(_reader, reader) ||
        generation != _displayGeneration) {
      return Future.value();
    }
    return _loadWindow(
      direction: _ChildrenPageDirection.older,
      cursor: cursor,
      generation: generation,
    );
  }

  Future<void> _loadNewer(int generation) {
    if (!_ready ||
        _newer.isEmpty ||
        _error != null ||
        generation != _displayGeneration) {
      return Future.value();
    }
    return _loadWindow(
      direction: _ChildrenPageDirection.newer,
      cursor: _newer.last.cursor,
      generation: generation,
    );
  }

  Future<void> _loadWindow({
    required _ChildrenPageDirection direction,
    required String? cursor,
    required int generation,
  }) {
    final existing = _pageLoading;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _pageLoading = completion.future;
    _failedPage = null;
    final previous = (cursor: _pageCursor, next: _before);
    completion.complete(
      Future<void>.sync(() async {
        try {
          if (direction == _ChildrenPageDirection.newer &&
              (_newer.isEmpty || _newer.last.cursor != cursor)) {
            throw const ConversationContinuityError(
              'Children newer window qualification changed',
            );
          }
          await _loadPage(cursor: cursor);
          if (!isCurrent || generation != _displayGeneration) {
            throw const StaleConversationScope();
          }
          switch (direction) {
            case _ChildrenPageDirection.older:
              _newer.add(previous);
              if (_newer.length > _maxChildrenWindowDescriptors) {
                _newer.removeAt(0);
              }
            case _ChildrenPageDirection.newer:
              _newer.removeLast();
          }
          _error = null;
        } catch (error) {
          if (isCurrent && generation == _displayGeneration) {
            _failedPage = (
              direction: direction,
              cursor: cursor,
              generation: generation,
            );
            setState(() => _error = error);
          }
        } finally {
          if (identical(_pageLoading, completion.future)) _pageLoading = null;
          if (mounted && !_retired) setState(() {});
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
      onLoadNewer: _newer.isEmpty ? null : () => _loadNewer(generation),
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
    final failed = _failedPage;
    final request = !_ready
        ? _open()
        : failed != null && failed.generation == _displayGeneration
        ? _loadWindow(
            direction: failed.direction,
            cursor: failed.cursor,
            generation: failed.generation,
          )
        : Future<void>.value();
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
    await _pageLoading;
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
