import 'dart:async';
import 'dart:typed_data';

import 'package:anywork_client/conversation.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_chat_core/flutter_chat_core.dart';

import '../state/timeline_display_diagnostics.dart';
import '../state/timeline_image_resources.dart';
import '../view_models/timeline_message_controller.dart';
import '../widgets/timeline_children_view.dart';
import 'timeline_content_connector.dart';
import 'timeline_media_connector.dart';

/// Expanded contents own a separate Children scope, never insert into Main.
class TimelineChildrenConnector extends StatefulWidget {
  const TimelineChildrenConnector({
    super.key,
    required this.repository,
    required this.threadId,
    required this.parentId,
    this.readAttachment,
    this.registerDisplay,
    this.isParentActive,
    this.parentRetirement,
  });
  final ConversationRepository repository;
  final String threadId;
  final String parentId;
  final Future<Uint8List> Function(String id)? readAttachment;
  final VoidCallback Function(TimelineChildrenDisplay display)? registerDisplay;
  final bool Function()? isParentActive;
  final ValueListenable<bool>? parentRetirement;

  @override
  State<TimelineChildrenConnector> createState() =>
      _TimelineChildrenConnectorState();
}

class _TimelineChildrenConnectorState extends State<TimelineChildrenConnector>
    implements ConversationBatchConsumer, TimelineChildrenDisplay {
  InMemoryChatController? _controller = InMemoryChatController();
  late final TimelineImageResources _images = TimelineImageResources(
    threadId: widget.threadId,
  );
  TimelineMessageController? _adapter;
  ConversationContent? _content;
  ConversationQueryScope? _queries;
  Observation? _consumer;
  Observation? _connection;
  String? _before;
  Object? _error;
  bool _ready = false;
  bool _retired = false;
  bool _opening = false;
  Future<void>? _older;
  late ReadDemand _demand;
  late final Future<void> _opened;
  final _openingDone = Completer<void>();
  int _mutations = 0;
  Object? _attempt;
  int _displayGeneration = 0;
  int _appliedSets = 0;
  int _appliedPrepends = 0;
  int _appliedAppends = 0;
  late final VoidCallback Function(TimelineChildrenDisplay)? _registerDisplay;
  late final bool Function()? _isParentActive;
  late final ValueListenable<bool>? _parentRetirement;
  late final String _originalThreadId;
  late final String _originalParentId;
  VoidCallback? _unregisterDisplay;

  bool get _parentActive =>
      widget.threadId == _originalThreadId &&
      widget.parentId == _originalParentId &&
      identical(widget.parentRetirement, _parentRetirement) &&
      !(_parentRetirement?.value ?? false) &&
      (_isParentActive?.call() ?? true);
  @override
  String get parentId => _originalParentId;
  @override
  int get generation => _displayGeneration;
  @override
  bool get isCurrent {
    final content = _content;
    final controller = _controller;
    return _ready &&
        content != null &&
        controller != null &&
        _eligibleDisplay(content, controller, _attempt, _displayGeneration);
  }

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
      isCurrent ? _controller!.messages : const [];
  @override
  int get appliedSets => _appliedSets;
  @override
  int get appliedPrepends => _appliedPrepends;
  @override
  int get appliedAppends => _appliedAppends;

  void _unregister() {
    final unregister = _unregisterDisplay;
    _unregisterDisplay = null;
    unregister?.call();
  }

  void _registerCurrent() {
    if (isCurrent && _unregisterDisplay == null) {
      _unregisterDisplay = _registerDisplay?.call(this);
    }
  }

  void _retireQueries() {
    _unregister();
    _appliedSets = _appliedPrepends = _appliedAppends = 0;
    _queries?.retire();
    _queries = null;
    _older = null;
    _displayGeneration++;
  }

  void _synchronizeAttempt(ConversationContent content) {
    final attempt = content.currentAttemptId;
    if (_attempt == attempt) return;
    _retireQueries();
    _attempt = attempt;
    _before = null;
    _ready = false;
  }

  bool _eligibleDisplay(
    ConversationContent content,
    InMemoryChatController controller,
    Object? attempt,
    int generation,
  ) =>
      !_retired &&
      mounted &&
      _parentActive &&
      identical(_content, content) &&
      identical(_controller, controller) &&
      _attempt == attempt &&
      content.currentAttemptId == attempt &&
      _displayGeneration == generation;

  @override
  void initState() {
    super.initState();
    _originalThreadId = widget.threadId;
    _originalParentId = widget.parentId;
    // Borrow only the original parent lease; widget rebuilds never transfer this
    // State or an old callback into a newly selected lease.
    _registerDisplay = widget.registerDisplay;
    _isParentActive = widget.isParentActive;
    _parentRetirement = widget.parentRetirement;
    if (_parentRetirement?.value ?? false) {
      _retired = true;
    } else {
      _parentRetirement?.addListener(_parentRetired);
    }
    _adapter = TimelineMessageController(
      _controller!,
      generation: 1,
      imageResources: _images,
    );
    _opened = _openingDone.future;
  }

  void _parentRetired() {
    if (!(_parentRetirement?.value ?? false) || _retired) return;
    _consumer?.cancel();
    _connection?.cancel();
    _retireQueries();
  }

  @override
  void didUpdateWidget(covariant TimelineChildrenConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_parentActive) {
      _unregister();
      _queries?.retire();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_opening) return;
    _opening = true;
    if (_retired || !_parentActive) {
      _openingDone.complete();
      return;
    }
    _demand = ReadDemand(
      maxItems: (MediaQuery.sizeOf(context).height / 72).ceil().clamp(1, 100),
      maxBytes: 256 * 1024,
    );
    _openingDone.complete(_open());
  }

  Future<void> _open() async {
    try {
      final content = await widget.repository.openChildren(
        threadId: _originalThreadId,
        parentId: _originalParentId,
        demand: _demand,
      );
      _content = content;
      if (_retired || !_parentActive) return;
      _connection = content.state.watch((state) {
        if (_retired ||
            !mounted ||
            !_parentActive ||
            !identical(_content, content)) {
          return;
        }
        setState(() {
          _synchronizeAttempt(content);
          if (state is ChatFailed<bool>) _error = state.error;
          if (state is ChatReady<bool>) {
            _registerCurrent();
          } else {
            _unregister();
          }
        });
      });
      _consumer = content.attachConsumer(this, demand: _demand);
    } catch (error) {
      if (!_retired && mounted && _parentActive) {
        setState(() => _error = error);
      }
    }
  }

  @override
  Future<void> applyBatch(ChatBatch batch) async {
    if (_retired || !_parentActive) return;
    final content = _content;
    final controller = _controller;
    final adapter = _adapter;
    if (content == null || controller == null || adapter == null) return;
    _synchronizeAttempt(content);
    if (batch.placement == ChatPlacement.set) {
      _retireQueries();
      _before = null;
      _ready = false;
    }
    final attempt = content.currentAttemptId;
    final generation = _displayGeneration;
    _mutations++;
    try {
      await adapter.applyBatch(batch);
      if (!_eligibleDisplay(content, controller, attempt, generation)) {
        return;
      }
      setState(() {
        if (batch.placement != ChatPlacement.append) _before = batch.before;
        _ready = true;
        if (batch.placement == ChatPlacement.set) _error = null;
        switch (batch.placement) {
          case ChatPlacement.set:
            _appliedSets++;
          case ChatPlacement.prepend:
            _appliedPrepends++;
          case ChatPlacement.append:
            _appliedAppends++;
        }
        _registerCurrent();
      });
    } finally {
      _mutations--;
      _releaseController();
    }
  }

  ConversationQueryScope _scope(
    ConversationContent content,
    InMemoryChatController controller,
    Object? attempt,
    int generation,
  ) {
    if (!_ready ||
        !_eligibleDisplay(content, controller, attempt, generation)) {
      throw const StaleConversationScope();
    }
    final scope = _queries;
    if (scope != null && scope.isActive) return scope;
    scope?.retire();
    return _queries = content.openScope(generation: generation);
  }

  Future<void> _loadOlder(
    ConversationContent content,
    InMemoryChatController controller,
    Object? attempt,
    int generation,
  ) {
    if (!_ready ||
        !_eligibleDisplay(content, controller, attempt, generation)) {
      return Future.value();
    }
    final existing = _older;
    if (existing != null) return existing;
    final before = _before;
    if (_retired || before == null || _error != null) return Future.value();
    final completion = Completer<void>();
    _older = completion.future;
    completion.complete(
      Future<void>.sync(() async {
        ConversationQueryScope? scope;
        try {
          scope = _scope(content, controller, attempt, generation);
          await scope.loadOlder(before: before, demand: _demand);
        } catch (error) {
          if (_eligibleDisplay(content, controller, attempt, generation) &&
              (scope == null ||
                  (scope.isActive && identical(scope, _queries)))) {
            setState(() => _error = error);
          }
        } finally {
          if (_eligibleDisplay(content, controller, attempt, generation) &&
              identical(_older, completion.future)) {
            _older = null;
          }
        }
      }),
    );
    return completion.future;
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final content = _content;
    final attempt = _attempt;
    final generation = _displayGeneration;
    if (_error != null) return Text(_error.toString());
    if (!_ready || controller == null || content == null) {
      return const SizedBox(
        height: 48,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    bool active() => _eligibleDisplay(content, controller, attempt, generation);
    return TimelineChildrenView(
      controller: controller,
      generation: generation,
      isDisplayActive: active,
      onLoadOlder: _before == null
          ? null
          : () => _loadOlder(content, controller, attempt, generation),
      contentRangeBuilder: (itemId, contentKey, label, reference, witness) =>
          TimelineContentRangeConnector(
            key: ValueKey((generation, itemId, contentKey)),
            itemId: itemId,
            contentKey: contentKey,
            label: label,
            reference: reference,
            witness: witness,
            isDisplayActive: active,
            readContent: (reference, range) => _scope(
              content,
              controller,
              attempt,
              generation,
            ).readContent(reference: reference, range: range),
          ),
      attachmentBuilder: (item) => TimelineAttachmentsConnector(
        item: item,
        resources: _images,
        readAttachment: widget.readAttachment,
        isActive: active,
      ),
    );
  }

  @override
  void dispose() {
    _parentRetirement?.removeListener(_parentRetired);
    _retired = true;
    _consumer?.cancel();
    _connection?.cancel();
    _retireQueries();
    _releaseController();
    unawaited(
      _close().catchError((Object error, StackTrace stack) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stack,
            context: ErrorDescription('closing expanded conversation contents'),
          ),
        );
      }),
    );
    super.dispose();
  }

  Future<void> _close() async {
    await _opened;
    final content = _content;
    await content?.close();
    _queries = null;
    _consumer = null;
    _connection = null;
    _content = null;
    _releaseController();
  }

  void _releaseController() {
    if (!_retired || _mutations != 0) return;
    // Native cleanup may fail independently. A detached component has no future
    // message admissions; its original in-flight mutation alone owns this join.
    // Release Message references as soon as that mutation settles, including on
    // failure, rather than retaining the disposed State behind a native retry.
    final controller = _controller;
    _controller = null;
    final adapter = _adapter;
    _adapter = null;
    adapter?.dispose();
    _images.release();
    controller?.dispose();
  }
}
