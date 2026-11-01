import 'dart:async';
import 'dart:convert';

import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../../../shared/studio_driver_keys.dart';
import '../state/chat_item_presentation.dart';
import '../state/content_reference_identity.dart';
import '../state/timeline_display_diagnostics.dart';
import '../view_models/conversation_current_owner.dart';
import '../widgets/chat_item_view.dart';
import '../widgets/conversation_activity_bar.dart';
import '../widgets/timeline_markdown.dart';

/// The current display borrows the same content owner's read qualification.
/// Its expanded windows never become messages in the history controller.
class ConversationCurrentConnector extends StatefulWidget {
  const ConversationCurrentConnector({
    super.key,
    required this.current,
    required this.content,
    required this.view,
    this.onExpandedChanged,
    this.registerDisplay,
    this.isDisplayActive,
    this.completedItemsBuilder,
  });
  final CurrentProjection current;
  final ConversationContent content;
  final ConversationActivityView view;
  final ValueChanged<bool>? onExpandedChanged;

  /// Borrows existing resources for diagnostics; never creates read demand.
  final VoidCallback Function(TimelineCurrentDisplay display)? registerDisplay;
  final bool Function()? isDisplayActive;
  final Widget Function(String parentId, ValueListenable<bool> retirement)?
  completedItemsBuilder;

  @override
  State<ConversationCurrentConnector> createState() =>
      _ConversationCurrentConnectorState();
}

class _ConversationCurrentConnectorState
    extends State<ConversationCurrentConnector>
    implements TimelineCurrentDisplay {
  late ConversationCurrentOwner _owner;
  final Set<_CurrentCollectionState> _collections = {};
  late VoidCallback Function(TimelineCurrentDisplay)? _registerDisplay;
  late bool Function()? _isDisplayActive;
  Object? _attempt;
  late int _queryGeneration;
  VoidCallback? _unregisterDisplay;
  bool _expanded = false;
  bool _disposed = false;
  ValueNotifier<bool>? _completedRetirement;

  void _retireCompletedItems() {
    final retirement = _completedRetirement;
    _completedRetirement = null;
    if (retirement == null) return;
    retirement.value = true;
    retirement.dispose();
  }

  bool get _parentActive =>
      (_isDisplayActive?.call() ?? true) &&
      (widget.isDisplayActive?.call() ?? true);
  @override
  bool get isCurrent =>
      mounted &&
      !_disposed &&
      _parentActive &&
      _attempt == widget.content.currentAttemptId &&
      identical(_owner.content, widget.content) &&
      _owner.isCurrent;
  @override
  String? get turnId => isCurrent ? widget.current.activeTurn?.id : null;
  @override
  String? get childrenParentId =>
      isCurrent ? widget.current.activeTurn?.childrenParentId : null;
  @override
  String? get activityId => isCurrent ? widget.current.active?.id : null;
  @override
  bool get expanded => isCurrent && _expanded;
  @override
  Iterable<TimelineCurrentCollectionDisplay> get collections sync* {
    if (!expanded) return;
    for (final collection in _collections) {
      if (collection.isCurrent) yield collection;
    }
  }

  @override
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent) return;
    yield* _owner.windows;
    if (!expanded) return;
    for (final collection in _collections) {
      if (collection.isCurrent) yield* collection.windows;
    }
  }

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

  void _bind() {
    _registerDisplay = widget.registerDisplay;
    _isDisplayActive = widget.isDisplayActive;
    _attempt = widget.content.currentAttemptId;
    _owner = ConversationCurrentOwner(widget.content)
      ..addListener(_ownerChanged);
    _queryGeneration = _owner.queryGeneration;
    _synchronize();
    _registerCurrent();
  }

  void _ownerChanged() {
    final queryChanged = _queryGeneration != _owner.queryGeneration;
    _queryGeneration = _owner.queryGeneration;
    if (!isCurrent || (queryChanged && _expanded)) {
      _retireCollections(stale: true);
    }
    if (!isCurrent) {
      _retireCompletedItems();
      _unregister();
    } else {
      _registerCurrent();
    }
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(covariant ConversationCurrentConnector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.content, widget.content) ||
        oldWidget.registerDisplay != widget.registerDisplay) {
      _unregister();
      _release(_owner);
      _expanded = false;
      _bind();
    }
    if (_attempt != widget.content.currentAttemptId) {
      _retireCompletedItems();
      _unregister();
      _retireCollections(stale: true);
      _attempt = widget.content.currentAttemptId;
    }
    if (oldWidget.current.activeTurn?.id != widget.current.activeTurn?.id ||
        oldWidget.current.activeTurn?.childrenParentId !=
            widget.current.activeTurn?.childrenParentId ||
        oldWidget.current.active?.id != widget.current.active?.id) {
      _retireCompletedItems();
      _retireCollections();
      _expanded = false;
    }
    if (!_parentActive) {
      _retireCompletedItems();
      _unregister();
      _retireCollections();
      _expanded = false;
    }
    _synchronize();
    _registerCurrent();
  }

  void _synchronize() => _owner.synchronize(
    widget.current,
    responding:
        _parentActive &&
        widget.view.kind == ConversationActivityKind.responding,
    expanded: _parentActive && _expanded,
  );
  void _expandedChanged(bool expanded) {
    if (_disposed || (expanded && !isCurrent)) return;
    _expanded = expanded;
    if (!expanded) {
      _retireCompletedItems();
      _retireCollections();
    }
    _synchronize(); // Cancellation seals old scope synchronously, before joins.
    widget.onExpandedChanged?.call(expanded);
  }

  @override
  void dispose() {
    _disposed = true;
    _unregister();
    _release(_owner);
    super.dispose();
  }

  void _release(ConversationCurrentOwner owner) {
    _retireCompletedItems();
    _retireCollections();
    owner.removeListener(_ownerChanged);
    unawaited(owner.close());
    owner.dispose();
  }

  void _retireCollections({bool stale = false}) {
    for (final collection in List.of(_collections)) {
      collection.retire(stale: stale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final owner = _owner;
    return ListenableBuilder(
      listenable: owner,
      builder: (context, _) => ConversationActivityBar(
        key: ValueKey((
          owner,
          widget.current.activeTurn?.id,
          widget.current.active?.id,
        )),
        view: widget.view,
        onExpandedChanged: (expanded) {
          if (identical(_owner, owner)) _expandedChanged(expanded);
        },
        responseContentBuilder: (_) => _windows(),
        expandedContentBuilder: (_) => Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _windows(),
              if (widget.current.activeTurn?.childrenParentId
                  case final parentId?)
                if (widget.completedItemsBuilder case final builder?)
                  ExpansionTile(
                    key: StudioDriverKeys.currentCompletedItems(parentId),
                    title: const Text('已完成成员'),
                    onExpansionChanged: (expanded) {
                      if (!isCurrent) return;
                      setState(() {
                        _retireCompletedItems();
                        if (expanded) {
                          _completedRetirement = ValueNotifier(false);
                        }
                      });
                    },
                    children: [
                      if (_completedRetirement case final retirement?)
                        builder(parentId, retirement),
                    ],
                  ),
              for (final collection in widget.current.collections)
                _CurrentCollection(
                  key: ValueKey((collection.databaseId, collection.collection)),
                  reference: collection,
                  owner: _owner,
                  displays: _collections,
                  isDisplayActive: () =>
                      identical(_owner, owner) &&
                      expanded &&
                      widget.current.collections.any(
                        (current) =>
                            currentCollectionIdentity(current) ==
                            currentCollectionIdentity(collection),
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _windows() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [
      if (_owner.invalidationNotice case final notice?) Text(notice),
      if (_owner.cleanupError case final error?) ...[
        Text(error.toString(), key: const ValueKey('current-cleanup-error')),
        TextButton(
          onPressed: () => unawaited(_owner.retryCleanup()),
          child: const Text('重试释放内容观察'),
        ),
      ],
      for (final observation in _owner.windows)
        _CurrentWindow(
          key: ValueKey(contentReferenceIdentity(observation.source.reference)),
          observation: observation,
          onNext: () => _owner.nextWindow(observation),
          onFirst: () => _owner.firstWindow(observation),
        ),
    ],
  );
}

class _CurrentWindow extends StatelessWidget {
  const _CurrentWindow({
    super.key,
    required this.observation,
    required this.onNext,
    required this.onFirst,
  });
  final CurrentWindowObservation observation;
  final VoidCallback onNext;
  final VoidCallback onFirst;
  @override
  Widget build(BuildContext context) {
    final window = observation.window;
    final text = window == null
        ? observation.source.text
        : utf8.decode(window.bytes, allowMalformed: true);
    final end = window == null ? 0 : window.offset + window.bytes.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (observation.source.id.startsWith('plan:')) const Text('当前计划文档'),
        if (observation.error case final error?)
          Text(
            error.toString(),
            key: ValueKey('current-window-error:${observation.source.id}'),
          ),
        TimelineMarkdown(
          id: 'current:${observation.source.id}',
          text: text,
          onLink: (_) {},
          isSafeLink: (_) => false,
          imageBuilder: (_, url) => Text(url),
        ),
        if (window != null &&
            (window.offset > 0 || end < window.availableThrough))
          Row(
            children: [
              Text('字节 ${window.offset}–$end / ${window.availableThrough}'),
              if (window.offset > 0)
                TextButton(onPressed: onFirst, child: const Text('第一段')),
              if (window.bytes.isNotEmpty && end < window.availableThrough)
                TextButton(onPressed: onNext, child: const Text('下一段')),
            ],
          ),
      ],
    );
  }
}

/// One revision-bound collection page, fetched only on explicit expansion/page
/// selection. Revisions never concatenate and pages never become chat messages.
class _CurrentCollection extends StatefulWidget {
  const _CurrentCollection({
    super.key,
    required this.reference,
    required this.owner,
    required this.displays,
    required this.isDisplayActive,
  });
  final CurrentCollectionRef reference;
  final ConversationCurrentOwner owner;
  final Set<_CurrentCollectionState> displays;
  final bool Function() isDisplayActive;
  @override
  State<_CurrentCollection> createState() => _CurrentCollectionState();
}

class _CurrentCollectionState extends State<_CurrentCollection>
    implements TimelineCurrentCollectionDisplay {
  CurrentCollectionPage? _page;
  ConversationQueryScope? _pageScope;
  Object? _error;
  bool _loading = false;
  bool _expanded = false;
  bool _stale = false;
  int _generation = 0;
  final Set<VoidCallback> _memberRetirements = {};
  final Set<ConversationCurrentOwner> _memberOwners = {};
  final Set<TimelineCurrentWindowDisplay> _payloadWindows = {};

  @override
  bool get isCurrent =>
      mounted &&
      _expanded &&
      widget.isDisplayActive() &&
      widget.owner.isCurrent;
  @override
  CurrentCollectionRef get reference => widget.reference;
  @override
  int get generation => _generation;
  @override
  bool get expanded => isCurrent;
  @override
  bool get loading => isCurrent && _loading;
  @override
  Object? get error => isCurrent ? _error : null;
  @override
  CurrentCollectionPage? get page =>
      isCurrent && (_pageScope?.isActive ?? false) ? _page : null;
  Iterable<TimelineCurrentWindowDisplay> get windows sync* {
    if (!isCurrent || page == null) return;
    for (final owner in _memberOwners) {
      yield* owner.windows;
    }
    yield* _payloadWindows;
  }

  void retire({bool stale = false}) {
    _generation++;
    _retireMembers();
    _page = null;
    _pageScope = null;
    _loading = false;
    _error = null;
    _stale = stale;
    if (!stale) _expanded = false;
  }

  @override
  void initState() {
    super.initState();
    widget.displays.add(this);
  }

  void _retireMembers() {
    _payloadWindows.clear();
    for (final retire in List.of(_memberRetirements)) {
      retire();
    }
  }

  @override
  void didUpdateWidget(covariant _CurrentCollection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.displays, widget.displays)) {
      oldWidget.displays.remove(this);
      widget.displays.add(this);
    }
    if (currentCollectionIdentity(oldWidget.reference) !=
            currentCollectionIdentity(widget.reference) ||
        !identical(oldWidget.owner, widget.owner)) {
      retire(stale: true);
    }
  }

  Future<void> _load({String? continuation}) async {
    if (_loading || !isCurrent) return;
    final generation = ++_generation;
    final owner = widget.owner;
    final reference = widget.reference;
    ConversationQueryScope? scope;
    bool eligible() =>
        mounted &&
        generation == _generation &&
        identical(owner, widget.owner) &&
        currentCollectionIdentity(reference) ==
            currentCollectionIdentity(widget.reference) &&
        isCurrent &&
        (scope?.isActive ?? true);
    setState(() {
      _payloadWindows.clear();
      _loading = true;
      _error = null;
      _stale = false;
    });
    try {
      scope = owner.queryScope;
      final page = await scope.pageCurrent(
        reference: reference,
        continuation: continuation,
        demand: ReadDemand(
          maxItems: (MediaQuery.sizeOf(context).height / 64).ceil().clamp(
            1,
            100,
          ),
          maxBytes: 64 * 1024,
        ),
      );
      if (!eligible()) return;
      _retireMembers();
      setState(() {
        _page = page;
        _pageScope = scope;
      });
    } catch (error) {
      if (eligible()) {
        setState(() => _error = error);
      }
    } finally {
      if (eligible()) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.displays.remove(this);
    retire();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ExpansionTile(
    title: Text(switch (widget.reference.collection) {
      'tools' => '当前工具',
      'members' => '当前内容',
      'interactions' => '当前交互',
      _ => widget.reference.collection,
    }, key: StudioDriverKeys.currentCollection(widget.reference.collection)),
    onExpansionChanged: (expanded) {
      _expanded = expanded;
      if (expanded && _page == null && !_stale) unawaited(_load());
      if (!expanded) {
        retire();
      }
    },
    children: [
      if (_loading) const LinearProgressIndicator(),
      if (_stale) const Text('当前集合已更新，原版本已失效'),
      if (_error case final error?) Text(error.toString()),
      if (_stale || _error != null)
        TextButton(
          key: StudioDriverKeys.currentCollectionReload(
            widget.reference.collection,
          ),
          onPressed: () => unawaited(_load()),
          child: const Text('重新读取当前页'),
        ),
      for (final entry in _page?.entries ?? const <CurrentCollectionEntry>[])
        _entry(entry),
      if (_page?.continuation case final continuation?)
        TextButton(
          key: StudioDriverKeys.currentCollectionNext(
            widget.reference.collection,
          ),
          onPressed: _loading
              ? null
              : () => unawaited(_load(continuation: continuation)),
          child: const Text('下一页'),
        ),
    ],
  );

  Widget _entry(CurrentCollectionEntry entry) {
    final generation = _generation;
    final acceptedPage = _page;
    return _CurrentCollectionEntry(
      key: ValueKey((
        widget.reference.revision,
        generation,
        acceptedPage,
        entry.id,
      )),
      entry: entry,
      collection: widget.reference.collection,
      owner: widget.owner,
      retirements: _memberRetirements,
      bodyOwners: _memberOwners,
      isDisplayActive: () =>
          isCurrent &&
          generation == _generation &&
          identical(acceptedPage, page),
      registerWindowDisplay: _registerWindowDisplay,
    );
  }

  VoidCallback _registerWindowDisplay(TimelineCurrentWindowDisplay display) {
    _payloadWindows.add(display);
    return () => _payloadWindows.remove(display);
  }
}

class _CurrentCollectionEntry extends StatefulWidget {
  const _CurrentCollectionEntry({
    super.key,
    required this.entry,
    required this.collection,
    required this.owner,
    required this.retirements,
    required this.bodyOwners,
    required this.isDisplayActive,
    required this.registerWindowDisplay,
  });
  final CurrentCollectionEntry entry;
  final String collection;
  final ConversationCurrentOwner owner;
  final Set<VoidCallback> retirements;
  final Set<ConversationCurrentOwner> bodyOwners;
  final bool Function() isDisplayActive;
  final VoidCallback Function(TimelineCurrentWindowDisplay display)
  registerWindowDisplay;
  @override
  State<_CurrentCollectionEntry> createState() =>
      _CurrentCollectionEntryState();
}

class _CurrentCollectionEntryState extends State<_CurrentCollectionEntry> {
  ConversationCurrentOwner? _bodiesOwner;
  @override
  void initState() {
    super.initState();
    widget.retirements.add(_retireBodies);
  }

  void _retireBodies() {
    final owner = _bodiesOwner;
    _bodiesOwner = null;
    if (owner == null) return;
    widget.bodyOwners.remove(owner);
    // Called by the real expansion callback, before reverse animation/unmount.
    unawaited(owner.close());
    owner.dispose();
  }

  @override
  void dispose() {
    widget.retirements.remove(_retireBodies);
    _retireBodies();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final owner = widget.owner;
    final collection = widget.collection;
    final payload = entry.payload;
    if (payload is DeferredPayload) {
      return ChatItemView(
        key: StudioDriverKeys.currentCollectionEntry(collection, entry.id),
        item: ChatItemPresentation.decode(
          ChatMessage(id: entry.id, payload: payload),
        ),
        readContent: (reference, range) =>
            owner.queryScope.readContent(reference: reference, range: range),
        isDisplayActive: widget.isDisplayActive,
        registerWindowDisplay: widget.registerWindowDisplay,
      );
    }
    final bytes = (payload as InlinePayload).bytes;
    String text;
    try {
      text = utf8.decode(bytes);
      final decoded = jsonDecode(text);
      if (collection == 'members') {
        if (decoded is! List) {
          throw const FormatException('当前内容 manifest 必须是数组');
        }
        final sources = <CurrentWindowSource>[
          for (final body in decoded)
            CurrentWindowSource(
              id: entry.id,
              reference: ChatItemPresentation.contentReference(
                (body as Map<String, dynamic>)['reference'],
              ),
              text: '',
            ),
        ];
        return ExpansionTile(
          title: Text(
            entry.id,
            key: StudioDriverKeys.currentCollectionEntry(collection, entry.id),
          ),
          maintainState: false,
          onExpansionChanged: (expanded) {
            if (expanded && !widget.isDisplayActive()) return;
            setState(() {
              if (expanded) {
                _retireBodies();
                _bodiesOwner = ConversationCurrentOwner(owner.content)
                  ..synchronizeSources(sources);
                widget.bodyOwners.add(_bodiesOwner!);
              } else {
                _retireBodies();
              }
            });
          },
          children: [
            if (_bodiesOwner case final bodyOwner?)
              _ExpandedCurrentBodies(owner: bodyOwner),
          ],
        );
      }
      text = const JsonEncoder.withIndent('  ').convert(decoded);
    } on FormatException catch (error) {
      text = '当前集合内容格式错误：$error\n${utf8.decode(bytes, allowMalformed: true)}';
    } on TypeError catch (error) {
      text = '当前集合内容格式错误：$error\n${utf8.decode(bytes, allowMalformed: true)}';
    }
    return ExpansionTile(
      title: Text(
        entry.id,
        key: StudioDriverKeys.currentCollectionEntry(collection, entry.id),
      ),
      children: [SelectableText(text)],
    );
  }
}

/// Mounted only by a member disclosure. Reuses the same cancel/join owner rather
/// than reducing deltas or reading all collection bodies into another snapshot.
class _ExpandedCurrentBodies extends StatelessWidget {
  const _ExpandedCurrentBodies({required this.owner});
  final ConversationCurrentOwner owner;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: owner,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (owner.cleanupError case final error?) ...[
          Text('内容观察释放失败：$error'),
          TextButton(
            onPressed: owner.retryCleanup,
            child: const Text('重试释放内容观察'),
          ),
        ],
        for (final observation in owner.windows)
          _CurrentWindow(
            key: ValueKey(
              contentReferenceIdentity(observation.source.reference),
            ),
            observation: observation,
            onNext: () => owner.nextWindow(observation),
            onFirst: () => owner.firstWindow(observation),
          ),
      ],
    ),
  );
}
