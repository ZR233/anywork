import 'dart:async';

import 'package:anywork_client/modes_ports.dart';
import 'package:anywork_client/operations_ports.dart';
import 'package:anywork_client/resources_ports.dart';

import 'scripted_feed.dart';

const modesFixtureOrigin = ProductReadOrigin(
  ownerEpoch: 'modes-fixture',
  incarnation: 1,
);

ModeDocument modeDocument({
  String id = 'mode.custom',
  String prompt = 'first',
}) => ModeDocument(
  definition: ModeDefinition(
    id: ThreadModeId(id),
    displayName: 'Custom',
    description: 'Custom mode',
    order: 3,
    prompt: prompt,
    workflow: const WorkflowDefinition(
      title: 'Workflow',
      goal: 'Finish',
      initialStateId: 'a',
      states: [
        WorkflowState(
          id: 'a',
          title: 'Work',
          instructions: 'Work',
          completionCriteria: ['done'],
          kind: WorkflowStateKind.atomic,
        ),
        WorkflowState(
          id: 'done',
          title: 'Done',
          instructions: 'Finish',
          completionCriteria: [],
          kind: WorkflowStateKind.finalState,
        ),
      ],
      transitions: [
        WorkflowTransition(
          sourceStateId: 'a',
          targetStateId: 'done',
          guard: 'done',
        ),
      ],
    ),
  ),
  editor: const ModeEditorLayout(
    nodes: [WorkflowNodePosition(stateId: 'a', x: 12, y: 34)],
  ),
);

final class ModesFixture {
  ModesFixture() {
    operations = OperationRegistry(clientId: 'mode-editor', budget: budget);
    repository = createModesRepository(
      port: port,
      budget: budget,
      operations: operations,
    );
  }
  final budget = ResourceBudget();
  final port = FixtureModesPort();
  late final OperationRegistry operations;
  late final ModesRepository repository;

  Future<void> establish({int revision = 1}) async {
    port.catalogs[revision] = const [];
    final loading = repository.loadModesPage();
    await port.feed.listened.future;
    port.feed.emit(
      ModeCatalogFrame.data(
        deliverySequence: 1,
        event: ModeCatalogEvent.baseline(
          identity: ProductFeedIdentity(
            feedId: port.feed.feedId,
            ownerEpoch: modesFixtureOrigin.ownerEpoch,
            incarnation: modesFixtureOrigin.incarnation,
            resource: ProductResource.modeCatalog,
          ),
          stamp: ProductProjectionStamp(
            ownerEpoch: modesFixtureOrigin.ownerEpoch,
            incarnation: modesFixtureOrigin.incarnation,
            revision: revision,
          ),
          value: ModeCatalogBaseline(
            header: modeCatalogHeader(revision),
            collection: modeCollection(revision, 0),
          ),
        ),
      ),
    );
    await loading;
    await port.feed.acknowledged(1);
  }
}

ModeCatalogHeader modeCatalogHeader(int revision) => ModeCatalogHeader(
  revision: revision,
  reference: ModeCatalogReadRef(entry: 1, revision: revision),
);
ProductCollectionRef modeCollection(int revision, int total) =>
    ProductCollectionRef(entry: 2, revision: revision, total: total);

final class ModeCommandCall {
  ModeCommandCall(
    this.kind,
    this.expectedRevision,
    this.operationId, {
    this.document,
    this.modeId,
  });
  final String kind;
  final int expectedRevision;
  final OperationId operationId;
  final ModeDocument? document;
  final String? modeId;
  final reply = Completer<ModeDefinitionCommandReply>();

  void complete({required int revision, ModeDefinitionSnapshot? definition}) =>
      reply.complete(
        ModeDefinitionCommandReply(
          catalog: ModeCatalogReadTarget(
            origin: modesFixtureOrigin,
            reference: ModeCatalogReadRef(entry: 1, revision: revision),
          ),
          definition: definition,
          receipt: CommitReceipt(
            operationId: operationId,
            disposition: CommitDisposition.applied,
            targets: [
              ResourceStamp(
                resourceKey: 'thread-mode-catalog',
                ownerEpoch: modesFixtureOrigin.ownerEpoch,
                revision: revision,
              ),
            ],
            effect: EffectPoint.nextTurn,
            effective: false,
            durable: false,
          ),
        ),
      );
}

/// Native authoring responses and immutable catalog pins only. No editor state,
/// validation algorithm, command lane, receipt observation or reducer lives here.
final class FixtureModesPort implements ModesPort {
  final feed = ScriptedFeed<ModeCatalogFrame>(
    feedId: 'modes-feed',
    sequenceOf: (frame) =>
        frame is ModeCatalogData ? frame.deliverySequence : null,
    isTerminal: (frame) => frame is! ModeCatalogData,
  );
  final definitions = <String, ModeDefinitionSnapshot>{};
  final catalogs = <int, List<ThreadModeDescriptorRead>>{};
  final definitionRequests = <String>[];
  final validationRequests = <String>[];
  final previewRequests = <WorkflowPreviewRequest>[];
  final commands = <ModeCommandCall>[];
  final _commandWaiters = <int, Completer<ModeCommandCall>>{};
  ModeValidationResult validation = const ModeValidationResult(
    document: null,
    issues: [],
  );
  WorkflowPreviewSnapshot previewResult = const WorkflowPreviewSnapshot(
    accepted: true,
    message: 'ok',
    currentState: null,
    transitions: [],
    path: [],
    terminal: false,
  );
  Completer<void>? queryEntered;
  Completer<void>? queryReceipt;
  int catalogOpens = 0;
  int readOpens = 0;
  int readCloses = 0;

  Future<ModeCommandCall> command(int index) => index < commands.length
      ? Future.value(commands[index])
      : _commandWaiters
            .putIfAbsent(index, Completer<ModeCommandCall>.new)
            .future;

  Future<ModeDefinitionCommandReply> _command(ModeCommandCall call) {
    final index = commands.length;
    commands.add(call);
    _commandWaiters.remove(index)?.complete(call);
    return call.reply.future;
  }

  Future<void> _holdQuery() async {
    final entered = queryEntered;
    if (entered != null && !entered.isCompleted) entered.complete();
    await queryReceipt?.future;
  }

  @override
  Future<FeedConnection<ModeCatalogFrame>> openModeCatalog() async {
    catalogOpens++;
    return feed;
  }

  @override
  Future<ModeCatalogReadConnection> openModeCatalogRead(
    ModeCatalogReadRef reference, {
    required ProductReadOrigin origin,
  }) async {
    final rows = catalogs[reference.revision];
    if (origin != modesFixtureOrigin || rows == null)
      throw const StudioFailure(
        code: StudioFailureCode.superseded,
        message: 'Unscripted catalog version',
        retryable: false,
        correlationId: 'modes-fixture',
      );
    return _ModeCatalogPin(
      'mode-read-${++readOpens}',
      reference.revision,
      List.unmodifiable(rows),
      () => readCloses++,
    );
  }

  @override
  Future<ModeDefinitionSnapshot> readDefinition(String modeId) async {
    definitionRequests.add(modeId);
    final snapshot = definitions[modeId];
    await _holdQuery();
    if (snapshot == null)
      throw const StudioFailure(
        code: StudioFailureCode.notFound,
        message: 'The mode was deleted',
        retryable: false,
        correlationId: 'mode-not-found',
      );
    return snapshot;
  }

  @override
  Future<ModeValidationResult> validate(String rawJson) async {
    validationRequests.add(rawJson);
    await _holdQuery();
    return validation;
  }

  @override
  Future<String> schema() async {
    await _holdQuery();
    return '{}';
  }

  @override
  Future<WorkflowPreviewSnapshot> preview(
    WorkflowPreviewRequest request,
  ) async {
    previewRequests.add(request);
    await _holdQuery();
    return previewResult;
  }

  @override
  Future<ModeDefinitionCommandReply> save(
    ModeDocument document, {
    required int expectedRevision,
    required OperationId operationId,
  }) => _command(
    ModeCommandCall('save', expectedRevision, operationId, document: document),
  );
  @override
  Future<ModeDefinitionCommandReply> delete(
    String modeId, {
    required int expectedRevision,
    required OperationId operationId,
  }) => _command(
    ModeCommandCall('delete', expectedRevision, operationId, modeId: modeId),
  );
  @override
  Future<ModeDefinitionCommandReply> reload({
    required int expectedRevision,
    required OperationId operationId,
  }) => _command(ModeCommandCall('reload', expectedRevision, operationId));

  void publishChange({
    required int deliverySequence,
    required int from,
    required int to,
    List<ThreadModeDescriptorRead> rows = const [],
  }) {
    catalogs[to] = List.unmodifiable(rows);
    feed.emit(
      ModeCatalogFrame.data(
        deliverySequence: deliverySequence,
        event: ModeCatalogEvent.change(
          stamp: ProductProjectionStamp(
            ownerEpoch: modesFixtureOrigin.ownerEpoch,
            incarnation: modesFixtureOrigin.incarnation,
            revision: to,
          ),
          baseRevision: from,
          value: ModeCatalogChange(
            header: modeCatalogHeader(to),
            baseCollectionRevision: from,
            collection: modeCollection(to, rows.length),
            upserted: [
              for (var index = 0; index < rows.length; index++)
                ProductEntityRef(entry: index + 100, revision: to),
            ],
            removedEntries: const [],
          ),
        ),
      ),
    );
  }
}

final class _ModeCatalogPin implements ModeCatalogReadConnection {
  _ModeCatalogPin(this.id, this.revision, this.rows, this.onClose);
  final String id;
  final int revision;
  final List<ThreadModeDescriptorRead> rows;
  final void Function() onClose;
  bool _closing = false;
  bool _closed = false;
  void _ensureReadable() {
    if (_closing)
      throw const StudioFailure(
        code: StudioFailureCode.cancelled,
        message: 'The original catalog pin is sealed',
        retryable: false,
        correlationId: 'modes-pin',
      );
  }

  @override
  Future<ModeCatalogReadHeader> header() async {
    _ensureReadable();
    return ModeCatalogReadHeader(
      revision: revision,
      modes: TypedListRef(listId: 1, total: rows.length),
    );
  }

  @override
  Future<ModeCatalogEntryPage> entries({int offset = 0, int limit = 32}) async {
    _ensureReadable();
    final end = (offset + limit).clamp(0, rows.length);
    return ModeCatalogEntryPage(
      collection: modeCollection(revision, rows.length),
      offset: offset,
      items: [
        for (var index = offset; index < end; index++)
          ProductEntityRef(entry: index + 100, revision: revision),
      ],
      nextOffset: end == rows.length ? null : end,
    );
  }

  @override
  Future<ModeCatalogEntityRead> entity(ProductEntityRef reference) async {
    _ensureReadable();
    return ModeCatalogEntityRead(
      reference: reference,
      value: rows[reference.entry - 100],
    );
  }

  @override
  void requestClose() => _closing = true;
  @override
  Future<FeedCloseReport> close() async {
    requestClose();
    if (!_closed) {
      _closed = true;
      onClose();
    }
    return FeedCloseReport(feedId: id, outcome: const FeedCloseOutcome.clean());
  }

  @override
  Future<FeedCloseReport> retryClose() => close();
  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted Mode catalog field: ${invocation.memberName}',
  );
}
