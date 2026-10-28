import 'dart:async';

import 'package:anywork_client/conversation_ports.dart'
    show ConversationCommandPort;
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import 'profile_native_pin.dart';
import 'scripted_feed.dart';
import 'workspace_selection_fixture.dart';

const agentReadOrigin = ProductReadOrigin(
  ownerEpoch: 'agent-read-runtime',
  incarnation: 1,
);
const agentPreparingExecution = AgentExecution(
  id: 'preparing-before-turn',
  phase: AgentExecutionPhase.preparing,
  turnId: null,
);

typedef AgentReadEntry = ({
  ProductEntityRef reference,
  AgentDirectoryEntryRead value,
});

final List<AgentReadEntry> preparingAgentEntries = List.unmodifiable([
  (
    reference: const ProductEntityRef(entry: 3, revision: 1),
    value: const AgentDirectoryEntryRead(
      id: ReadText.inline(text: 'root'),
      threadId: ReadText.inline(text: 'root'),
      rootThreadId: ReadText.inline(text: 'root'),
      path: ReadText.inline(text: 'root'),
      parentPath: null,
      role: ReadText.inline(text: 'root'),
      task: ReadText.inline(text: 'Preparing'),
      summary: null,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.balanced,
      frozenModel: null,
      depth: 0,
      state: AgentStateRead.idle(budgetPause: null),
      updatedAt: 1,
      execution: agentPreparingExecution,
      canStop: true,
      awaitingScheduling: false,
    ),
  ),
  (
    reference: const ProductEntityRef(entry: 4, revision: 1),
    value: const AgentDirectoryEntryRead(
      id: ReadText.inline(text: 'child'),
      threadId: ReadText.inline(text: 'child'),
      rootThreadId: ReadText.inline(text: 'root'),
      path: ReadText.inline(text: 'root/child'),
      parentPath: ReadText.inline(text: 'root'),
      role: ReadText.inline(text: 'executor'),
      task: ReadText.inline(text: 'Waiting'),
      summary: null,
      delegationMode: DelegationMode.automatic,
      delegationPreference: DelegationPreference.balanced,
      frozenModel: null,
      depth: 1,
      state: AgentStateRead.idle(budgetPause: null),
      updatedAt: 1,
      execution: null,
      canStop: false,
      awaitingScheduling: true,
    ),
  ),
]);

/// Immutable scripted native material. Every execution, entry and revision is
/// supplied by the test; this fixture has no stop admission or domain reducer.
final class AgentReadMaterial {
  AgentReadMaterial({
    required this.revision,
    required List<AgentReadEntry> entries,
    this.origin = agentReadOrigin,
    this.entityGate,
  }) : entries = List.unmodifiable(entries);
  final int revision;
  final ProductReadOrigin origin;
  final List<AgentReadEntry> entries;
  final Completer<void>? entityGate;
  final entityEntered = Completer<void>();
  AgentDirectoryReadRef get reference =>
      AgentDirectoryReadRef(entry: 1, revision: revision);
  ProductCollectionRef get collection =>
      ProductCollectionRef(entry: 2, revision: revision, total: entries.length);
  ProductProjectionStamp get stamp => profileStamp(origin, revision);
}

final class AgentMaterialPin extends ProfileNativePin
    implements AgentDirectoryReadConnection {
  AgentMaterialPin(this.material)
    : super('agent-read-${material.origin.ownerEpoch}-${material.revision}');
  final AgentReadMaterial material;
  @override
  Future<AgentDirectoryReadHeader> header() async {
    admit();
    return AgentDirectoryReadHeader(
      agents: TypedListRef(listId: 1, total: material.entries.length),
    );
  }

  @override
  Future<AgentDirectoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async {
    admit();
    final entries = material.entries
        .skip(offset)
        .take(limit)
        .map((entry) => entry.reference)
        .toList();
    final end = offset + entries.length;
    return AgentDirectoryEntryPage(
      collection: material.collection,
      offset: offset,
      items: entries,
      nextOffset: end == material.entries.length ? null : end,
    );
  }

  @override
  Future<AgentDirectoryEntityRead> entity(ProductEntityRef reference) => reply(
    Future.sync(() async {
      if (!material.entityEntered.isCompleted)
        material.entityEntered.complete();
      await material.entityGate?.future;
      return AgentDirectoryEntityRead(
        reference: reference,
        value: material.entries
            .singleWhere((entry) => entry.reference == reference)
            .value,
      );
    }),
  );
}

/// Real Workspace and Conversation owners, including their real materializer.
/// Feed framing/delivery and native snapshots are the only scripted boundaries.
final class WorkspaceAgentFixture {
  WorkspaceAgentFixture({ConversationCommandPort? commands})
    : selection = WorkspaceSelectionFixture(commands: commands) {
    selection.directory.onOpenAgents = () async => feed;
    selection.directory.onReadAgents = (reference, origin) async {
      final material = _materials[(origin, reference)];
      if (material == null)
        throw StateError('Unscripted AgentDirectory material');
      final pin = AgentMaterialPin(material);
      pins.add(pin);
      return pin;
    };
  }
  final WorkspaceSelectionFixture selection;
  final List<AgentMaterialPin> pins = [];
  final Map<(ProductReadOrigin, AgentDirectoryReadRef), AgentReadMaterial>
  _materials = {};
  ScriptedFeed<AgentDirectoryFrame> feed = _feed(0);
  late AgentReadMaterial current;
  int _sequence = 0;
  int _generation = 0;
  WorkspaceRepository get workspace => selection.workspace;
  ResourceBudget get budget => selection.budget;

  static ScriptedFeed<AgentDirectoryFrame> _feed(int generation) =>
      ScriptedFeed(
        feedId: 'agent-materialization-$generation',
        sequenceOf: (frame) =>
            frame is AgentDirectoryData ? frame.deliverySequence : null,
        isTerminal: (frame) => frame is! AgentDirectoryData,
      );
  ProductFeedIdentity _identity(
    AgentReadMaterial material,
    ScriptedFeed<AgentDirectoryFrame> source,
  ) => profileIdentity(
    source.feedId,
    material.origin,
    ProductResource.agentDirectory,
  );
  AgentDirectoryHeader _header(AgentReadMaterial material) =>
      AgentDirectoryHeader(
        source: profileSource(material.revision),
        reference: material.reference,
      );
  void _register(AgentReadMaterial material) {
    current = material;
    _materials[(material.origin, material.reference)] = material;
  }

  Future<void> establish({int? pageLimit, AgentReadMaterial? initial}) async {
    _register(
      initial ?? AgentReadMaterial(revision: 1, entries: preparingAgentEntries),
    );
    final loading = pageLimit == null
        ? workspace.loadAgents()
        : workspace.loadAgentsPage(limit: pageLimit);
    await feed.listened.future;
    _baseline();
    await loading;
    await feed.acknowledged(1);
  }

  void _baseline() {
    _sequence = 1;
    feed.emit(
      AgentDirectoryFrame.data(
        deliverySequence: 1,
        event: AgentDirectoryEvent.baseline(
          identity: _identity(current, feed),
          stamp: current.stamp,
          value: AgentDirectoryBaseline(
            header: _header(current),
            collection: current.collection,
          ),
        ),
      ),
    );
  }

  Future<void> publish(AgentReadMaterial material) async {
    final previous = current;
    if (material.origin != previous.origin)
      throw StateError('Use replaceOwner for a new native owner');
    _register(material);
    final refs = material.entries.map((entry) => entry.reference).toList();
    final old = previous.entries.map((entry) => entry.reference).toList();
    feed.emit(
      AgentDirectoryFrame.data(
        deliverySequence: ++_sequence,
        event: AgentDirectoryEvent.change(
          stamp: material.stamp,
          baseRevision: previous.revision,
          value: AgentDirectoryChange(
            header: _header(material),
            baseCollectionRevision: previous.collection.revision,
            collection: material.collection,
            upserted: refs.where((ref) => !old.contains(ref)).toList(),
            removedEntries: old
                .where((ref) => !refs.any((next) => next.entry == ref.entry))
                .map((ref) => ref.entry)
                .toList(),
          ),
        ),
      ),
    );
    await feed.acknowledged(_sequence);
  }

  Future<void> replaceOwner(AgentReadMaterial material) async {
    final oldFeed = feed;
    final oldIdentity = _identity(current, oldFeed);
    feed = _feed(++_generation);
    _register(material);
    oldFeed.emit(
      AgentDirectoryFrame.resyncRequired(
        identity: oldIdentity,
        reason: ProductResyncReason.sourceLagged,
      ),
    );
    await feed.listened.future;
    final loading = workspace.loadAgents();
    _baseline();
    await loading;
    await feed.acknowledged(1);
  }

  Future<CloseReport> close() async {
    for (final material in _materials.values) {
      final gate = material.entityGate;
      if (gate != null && !gate.isCompleted) gate.complete();
    }
    return selection.close();
  }
}
