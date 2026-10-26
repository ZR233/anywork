import 'dart:async';

import 'package:anywork_client/resources_ports.dart';
import 'package:anywork_client/workspace_ports.dart';

import '../../../../anywork_client/test/support/conversation_fixture.dart';
import '../../../../anywork_client/test/support/drafts_workspace_fixture.dart';
import '../../../../anywork_client/test/support/profile_native_pin.dart';
import '../../../../anywork_client/test/support/scripted_feed.dart';
import '../../../../anywork_client/test/support/workspace_port_fixture.dart';

const selectorDirectoryOrigin = ProductReadOrigin(
  ownerEpoch: 'selector-native',
  incarnation: 1,
);
const selectorProject = ProjectRecord(
  id: 'project',
  name: 'Saved project',
  path: '/workspace',
  sshAlias: null,
  updatedAt: 1,
);
const selectorForeignProject = ProjectRecord(
  id: 'foreign-project',
  name: 'Foreign project',
  path: '/foreign',
  sshAlias: null,
  updatedAt: 1,
);

/// Immutable native directory captures and gates, not a Workspace mirror. Each
/// feed/read is admitted through the public port; selection, membership checks,
/// navigation generations and query watermarks remain production-owned.
final class SelectorDirectoryPort implements WorkspacePort {
  SelectorDirectoryPort() {
    threads.addAll([
      fixtureThread('thread-main'),
      fixtureThread(
        'thread-reviewer',
        parentThreadId: 'thread-main',
        role: 'reviewer',
      ).copyWith(status: ThreadStatus.closed, agentPath: 'opaque-child'),
      fixtureThread('thread-alt'),
      fixtureThread(
        'cold-sibling',
        parentThreadId: 'thread-main',
        role: 'executor',
      ).copyWith(agentPath: 'opaque-sibling'),
    ]);
    agents = [for (final thread in threads) agentEntry(thread)];
  }

  final projects = [selectorProject, selectorForeignProject];
  final threads = <WorkspaceThreadRecord>[];
  late List<AgentDirectoryEntry> agents;
  final projectFeeds = <ScriptedFeed<ProjectDirectoryFrame>>[];
  final threadFeeds =
      <({ThreadDirectoryScope scope, WorkspaceNativeThreadFeed connection})>[];
  final agentFeeds = <ScriptedFeed<AgentDirectoryFrame>>[];
  final metadataReads = <String>[];
  final activations = <String>[];
  final restores = <String>[];
  Future<WorkspaceThreadRecord> Function(String)? onRestore;
  Future<ArchiveThreadCommandReply> Function(String, OperationId)? onArchiveThread;
  final archivedThreads = <String>[];
  final renamedThreads = <String>[];
  final archives = <String>[];
  final archiveReply = Completer<ProjectRecord>();
  final archiveEntered = Completer<void>();
  final _threadMaterials = <int, List<WorkspaceThreadRecord>>{};
  final _projectMaterials = <int, List<ProjectRecord>>{};
  final _projectEntries = <String, int>{};
  final _agentMaterials = <int, List<AgentDirectoryEntry>>{};
  Future<void> Function(int revision)? beforeAgentEntity;
  final _threadSequences = <String, int>{};
  Future<WorkspaceThreadRecord> Function(String)? respond;
  Future<void> Function(String)? onActivate;
  bool projectUnavailable = false;
  int _agentRevision = 1;
  int _threadRevision = 7;
  int _projectRevision = 1;

  static AgentDirectoryEntry agentEntry(WorkspaceThreadRecord thread) =>
      AgentDirectoryEntry(
        id: thread.id,
        threadId: thread.id,
        path: thread.agentPath,
        parentPath: thread.isRoot ? null : 'root',
        rootThreadId: thread.rootThreadId,
        depth: thread.isRoot ? 0 : 1,
        role: thread.role,
        task: thread.title,
        summary: null,
        state: thread.status == ThreadStatus.closed
            ? const AgentState.closed()
            : const AgentState.idle(budgetPause: null),
        delegationMode: thread.delegationMode,
        delegationPreference: thread.delegationPreference,
        frozenModel: thread.frozenModel,
        updatedAt: thread.updatedAt,
      );

  @override
  Future<FeedConnection<ProjectDirectoryFrame>> openProjectDirectory() async {
    if (projectUnavailable) {
      throw const StudioFailure(
        code: StudioFailureCode.unavailable,
        message: 'directory offline',
        retryable: false,
        correlationId: 'directory-offline',
      );
    }
    final feed = ScriptedFeed<ProjectDirectoryFrame>(
      feedId: 'selector-projects-${projectFeeds.length}',
      sequenceOf: (frame) =>
          frame is ProjectDirectoryData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! ProjectDirectoryData,
    );
    projectFeeds.add(feed);
    final revision = _projectRevision;
    for (final project in projects) {
      _projectEntries.putIfAbsent(
        project.id,
        () => _projectEntries.length + 10,
      );
    }
    _projectMaterials[revision] = List.unmodifiable(projects);
    unawaited(
      feed.listened.future.then((_) {
        feed.emit(
          ProjectDirectoryFrame.data(
            deliverySequence: 1,
            event: ProjectDirectoryEvent.baseline(
              identity: profileIdentity(
                feed.feedId,
                selectorDirectoryOrigin,
                ProductResource.projectDirectory,
              ),
              stamp: profileStamp(selectorDirectoryOrigin, revision),
              value: ProjectDirectoryBaseline(
                header: ProjectDirectoryHeader(
                  source: profileSource(revision),
                  reference: ProjectDirectoryReadRef(
                    entry: 1,
                    revision: revision,
                  ),
                ),
                collection: profileCollection(revision, projects.length),
              ),
            ),
          ),
        );
      }),
    );
    return feed;
  }

  Future<void> publishProjects(List<ProjectRecord> values) async {
    final previous = _projectRevision++;
    final oldValues = List<ProjectRecord>.of(projects);
    for (final project in values) {
      _projectEntries.putIfAbsent(
        project.id,
        () => _projectEntries.length + 10,
      );
    }
    projects
      ..clear()
      ..addAll(values);
    _projectMaterials[_projectRevision] = List.unmodifiable(values);
    for (final feed in projectFeeds) {
      feed.emit(
        ProjectDirectoryFrame.data(
          deliverySequence: _projectRevision,
          event: ProjectDirectoryEvent.change(
            stamp: profileStamp(selectorDirectoryOrigin, _projectRevision),
            baseRevision: previous,
            value: ProjectDirectoryChange(
              header: ProjectDirectoryHeader(
                source: profileSource(_projectRevision),
                reference: ProjectDirectoryReadRef(
                  entry: 1,
                  revision: _projectRevision,
                ),
              ),
              baseCollectionRevision: previous,
              collection: profileCollection(_projectRevision, values.length),
              upserted: [
                for (final value in values)
                  ProductEntityRef(
                    entry: _projectEntries[value.id]!,
                    revision: _projectRevision,
                  ),
              ],
              removedEntries: [
                for (final value in oldValues)
                  if (!values.any((next) => next.id == value.id))
                    _projectEntries[value.id]!,
              ],
            ),
          ),
        ),
      );
      await feed.acknowledged(_projectRevision);
    }
  }

  void failProjects() {
    projectUnavailable = true;
    final feed = projectFeeds.last;
    feed.emit(
      ProjectDirectoryFrame.failure(
        identity: profileIdentity(
          feed.feedId,
          selectorDirectoryOrigin,
          ProductResource.projectDirectory,
        ),
        error: const StudioFailure(
          code: StudioFailureCode.unavailable,
          message: 'directory offline',
          retryable: false,
          correlationId: 'directory-offline',
        ),
      ),
    );
  }

  @override
  Future<ThreadDirectoryConnection> openThreadDirectory(
    ThreadDirectoryScope scope,
  ) async {
    final index = threadFeeds.length;
    final connection = WorkspaceNativeThreadFeed(index);
    _threadSequences[connection.feed.feedId] = 1;
    threadFeeds.add((scope: scope, connection: connection));
    final values = switch (scope) {
      SingleThreadDirectoryScope(:final threadId) =>
        threads.where((value) => value.id == threadId).toList(),
      _ => threads.where((value) => value.isRoot && !value.archived).toList(),
    };
    final entry = index + 100;
    _threadMaterials[entry] = List.unmodifiable(values);
    final revision = _threadRevision;
    unawaited(
      connection.feed.listened.future.then((_) {
        connection.feed.emit(
          ThreadDirectoryFrame.data(
            deliverySequence: 1,
            event: ThreadDirectoryEvent.baseline(
              identity: profileIdentity(
                connection.feed.feedId,
                selectorDirectoryOrigin,
                ProductResource.threadDirectory,
              ),
              stamp: profileStamp(selectorDirectoryOrigin, revision),
              value: ThreadDirectoryBaseline(
                header: ThreadDirectoryHeader(
                  source: profileSource(revision),
                  reference: ThreadDirectoryReadRef(
                    entry: entry,
                    revision: revision,
                  ),
                  directoryRevision: revision,
                  searchProjectRevision: null,
                  hasMore: false,
                  nextCursor: null,
                ),
                collection: profileCollection(revision, values.length),
              ),
            ),
          ),
        );
      }),
    );
    return connection;
  }

  @override
  Future<FeedConnection<AgentDirectoryFrame>> openAgentDirectory() async {
    final feed = ScriptedFeed<AgentDirectoryFrame>(
      feedId: 'selector-agents-${agentFeeds.length}',
      sequenceOf: (frame) =>
          frame is AgentDirectoryData ? frame.deliverySequence : null,
      isTerminal: (frame) => frame is! AgentDirectoryData,
    );
    agentFeeds.add(feed);
    _agentMaterials[_agentRevision] = List.unmodifiable(agents);
    unawaited(
      feed.listened.future.then(
        (_) => feed.emit(
          AgentDirectoryFrame.data(
            deliverySequence: 1,
            event: AgentDirectoryEvent.baseline(
              identity: profileIdentity(
                feed.feedId,
                selectorDirectoryOrigin,
                ProductResource.agentDirectory,
              ),
              stamp: profileStamp(selectorDirectoryOrigin, _agentRevision),
              value: AgentDirectoryBaseline(
                header: AgentDirectoryHeader(
                  source: profileSource(_agentRevision),
                  reference: AgentDirectoryReadRef(
                    entry: 1,
                    revision: _agentRevision,
                  ),
                ),
                collection: profileCollection(_agentRevision, agents.length),
              ),
            ),
          ),
        ),
      ),
    );
    return feed;
  }

  Future<void> publishAgents(List<AgentDirectoryEntry> values) async {
    final previous = _agentRevision++;
    agents = List.unmodifiable(values);
    _agentMaterials[_agentRevision] = agents;
    for (final feed in agentFeeds) {
      feed.emit(
        AgentDirectoryFrame.data(
          deliverySequence: _agentRevision,
          event: AgentDirectoryEvent.change(
            stamp: profileStamp(selectorDirectoryOrigin, _agentRevision),
            baseRevision: previous,
            value: AgentDirectoryChange(
              header: AgentDirectoryHeader(
                source: profileSource(_agentRevision),
                reference: AgentDirectoryReadRef(
                  entry: 1,
                  revision: _agentRevision,
                ),
              ),
              baseCollectionRevision: previous,
              collection: profileCollection(_agentRevision, values.length),
              upserted: [
                for (var i = 0; i < values.length; i++)
                  ProductEntityRef(entry: i + 10, revision: _agentRevision),
              ],
              removedEntries: [
                for (
                  var i = values.length;
                  i < _agentMaterials[previous]!.length;
                  i++
                )
                  i + 10,
              ],
            ),
          ),
        ),
      );
      await feed.acknowledged(_agentRevision);
    }
  }

  Future<void> publishThread(WorkspaceThreadRecord value) async {
    final previous = _threadRevision++;
    final index = threads.indexWhere((thread) => thread.id == value.id);
    threads[index] = value;
    for (var i = 0; i < threadFeeds.length; i++) {
      final opening = threadFeeds[i];
      final feed = opening.connection.feed;
      if (feed.requestCloseCalls != 0) continue;
      final entry = i + 100;
      final sequence = _threadSequences.update(
        feed.feedId,
        (value) => value + 1,
      );
      final values = [
        for (final thread in _threadMaterials[entry]!)
          thread.id == value.id ? value : thread,
      ];
      _threadMaterials[entry] = values;
      feed.emit(
        ThreadDirectoryFrame.data(
          deliverySequence: sequence,
          event: ThreadDirectoryEvent.change(
            stamp: profileStamp(selectorDirectoryOrigin, _threadRevision),
            baseRevision: previous,
            value: ThreadDirectoryChange(
              header: ThreadDirectoryHeader(
                source: profileSource(_threadRevision),
                reference: ThreadDirectoryReadRef(
                  entry: entry,
                  revision: _threadRevision,
                ),
                directoryRevision: _threadRevision,
                searchProjectRevision: null,
                hasMore: false,
                nextCursor: null,
              ),
              baseCollectionRevision: previous,
              collection: profileCollection(_threadRevision, values.length),
              upserted: [
                for (var j = 0; j < values.length; j++)
                  ProductEntityRef(entry: j + 10, revision: _threadRevision),
              ],
              removedEntries: const [],
            ),
          ),
        ),
      );
      await feed.acknowledged(sequence);
    }
  }

  @override
  Future<ProjectDirectoryReadConnection> openProjectDirectoryRead(
    ProjectDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async => _ProjectPin(
    _projectMaterials[reference.revision]!,
    reference.revision,
    Map.unmodifiable(_projectEntries),
  );
  @override
  Future<ThreadDirectoryReadConnection> openThreadDirectoryRead(
    ThreadDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async =>
      _ThreadPin(this, _threadMaterials[reference.entry]!, reference.revision);
  @override
  Future<AgentDirectoryReadConnection> openAgentDirectoryRead(
    AgentDirectoryReadRef reference, {
    required ProductReadOrigin origin,
  }) async =>
      _AgentPin(_agentMaterials[reference.revision]!, reference.revision, beforeAgentEntity);
  @override
  Future<ProductSourceStatusReadConnection> openSourceStatus(
    ProductSourceStatusRef reference, {
    required ProductReadOrigin origin,
  }) async => ProfileSourcePin(reference.revision);
  @override
  Future<void> activateProject(String projectId) async {
    activations.add(projectId);
    await onActivate?.call(projectId);
  }

  @override
  Future<ProjectRecord> openProject(String path) async => selectorProject;
  @override
  Future<ProjectRecord> openRemoteProject(String alias, String path) async =>
      selectorProject.copyWith(sshAlias: alias);
  @override
  Future<WorkspaceThreadRecord> restoreThread(String threadId) async {
    restores.add(threadId);
    if (onRestore case final restore?) return restore(threadId);
    throw const StudioFailure(
      code: StudioFailureCode.storage,
      message: 'restore failed',
      retryable: false,
      correlationId: 'selector-restore',
    );
  }

  @override
  Future<ProjectRecord> archiveProject(String projectId) {
    archives.add(projectId);
    if (!archiveEntered.isCompleted) archiveEntered.complete();
    return archiveReply.future;
  }

  @override
  Future<ArchiveThreadCommandReply> archiveThread(String threadId, {required OperationId operationId}) {
    archivedThreads.add(threadId);
    final action = onArchiveThread;
    if (action == null) throw UnsupportedError('Unscripted native Thread archive');
    return action(threadId, operationId);
  }

  @override
  Future<RenameThreadCommandReply> renameThread(String threadId, String title, {required OperationId operationId}) {
    renamedThreads.add(threadId);
    throw UnsupportedError('Unscripted native Thread rename');
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unscripted selector directory: ${invocation.memberName}',
  );
}

final class _ProjectPin extends ProfileNativePin
    implements ProjectDirectoryReadConnection {
  _ProjectPin(this.values, this.revision, this.references)
    : super('selector-project-pin');
  final List<ProjectRecord> values;
  final int revision;
  final Map<String, int> references;
  @override
  Future<ProjectDirectoryReadHeader> header() async =>
      ProjectDirectoryReadHeader(
        projects: TypedListRef(listId: 1, total: values.length),
      );
  @override
  Future<ProjectDirectoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => ProjectDirectoryEntryPage(
    collection: profileCollection(revision, values.length),
    offset: offset,
    items: [
      for (var i = offset; i < values.length && i < offset + limit; i++)
        ProductEntityRef(entry: references[values[i].id]!, revision: revision),
    ],
    nextOffset: null,
  );
  @override
  Future<ProductEntityRef?> lookupProject(String id) async {
    final index = values.indexWhere((value) => value.id == id);
    return index < 0
        ? null
        : ProductEntityRef(
            entry: references[values[index].id]!,
            revision: revision,
          );
  }

  @override
  Future<ProjectDirectoryEntityRead> entity(ProductEntityRef reference) async {
    final value = values.singleWhere(
      (value) => references[value.id] == reference.entry,
    );
    return ProjectDirectoryEntityRead(
      reference: reference,
      value: ProjectRecordRead(
        id: ReadText.inline(text: value.id),
        name: ReadText.inline(text: value.name),
        path: ReadText.inline(text: value.path),
        sshAlias: null,
        updatedAt: value.updatedAt,
      ),
    );
  }
}

final class _ThreadPin extends ProfileNativePin
    implements ThreadDirectoryReadConnection {
  _ThreadPin(this.port, this.values, this.revision)
    : super('selector-thread-pin');
  final SelectorDirectoryPort port;
  final List<WorkspaceThreadRecord> values;
  final int revision;
  @override
  Future<ThreadDirectoryReadHeader> header() async => ThreadDirectoryReadHeader(
    threads: TypedListRef(listId: 1, total: values.length),
    nextCursor: null,
    hasMore: false,
  );
  @override
  Future<ThreadDirectoryEntryPage> entries({
    String? cursor,
    int limit = 32,
  }) async => ThreadDirectoryEntryPage(
    collection: profileCollection(revision, values.length),
    items: [
      for (var i = 0; i < values.length; i++)
        ProductEntityRef(entry: i + 10, revision: revision),
    ],
    nextCursor: null,
    hasMore: false,
  );
  @override
  Future<ProductEntityRef?> lookupThread(String id) async {
    final index = values.indexWhere((value) => value.id == id);
    return index < 0
        ? null
        : ProductEntityRef(entry: index + 10, revision: revision);
  }

  @override
  Future<ThreadDirectoryEntityRead> entity(ProductEntityRef reference) async {
    var value = values[reference.entry - 10];
    port.metadataReads.add(value.id);
    value = await port.respond?.call(value.id) ?? value;
    return ThreadDirectoryEntityRead(
      reference: reference,
      value: draftThreadRead(value),
    );
  }
}

final class _AgentPin extends ProfileNativePin
    implements AgentDirectoryReadConnection {
  _AgentPin(this.values, this.revision, this.beforeEntity) : super('selector-agent-pin');
  final List<AgentDirectoryEntry> values;
  final int revision;
  final Future<void> Function(int revision)? beforeEntity;
  @override
  Future<AgentDirectoryReadHeader> header() async => AgentDirectoryReadHeader(
    agents: TypedListRef(listId: 1, total: values.length),
  );
  @override
  Future<AgentDirectoryEntryPage> entries({
    int offset = 0,
    int limit = 32,
  }) async => AgentDirectoryEntryPage(
    collection: profileCollection(revision, values.length),
    offset: offset,
    items: [
      for (var i = offset; i < values.length; i++)
        ProductEntityRef(entry: i + 10, revision: revision),
    ],
    nextOffset: null,
  );
  @override
  Future<AgentDirectoryEntityRead> entity(ProductEntityRef reference) => reply(Future<AgentDirectoryEntityRead>.sync(() async {
    await beforeEntity?.call(revision);
    final value = values[reference.entry - 10];
    ReadText text(String value) => ReadText.inline(text: value);
    ReadText? optional(String? value) => value == null ? null : text(value);
    SourceStateErrorRead error(SourceStateError value) => SourceStateErrorRead(
      code: text(value.code),
      message: text(value.message),
      retryable: value.retryable,
    );
    final state = switch (value.state) {
      IdleAgentState(:final budgetPause) => AgentStateRead.idle(
        budgetPause: budgetPause == null
            ? null
            : AgentBudgetPauseRead(
                turnId: text(budgetPause.turnId),
                limit: budgetPause.limit,
                pausedAt: budgetPause.pausedAt,
              ),
      ),
      QueuedAgentState(:final turnId) => AgentStateRead.queued(
        turnId: text(turnId),
      ),
      RunningAgentState(:final turnId) => AgentStateRead.running(
        turnId: text(turnId),
      ),
      WaitingToolAgentState(:final turnId) => AgentStateRead.waitingTool(
        turnId: text(turnId),
      ),
      WaitingInteractionAgentState(:final turnId, :final interactionId) =>
        AgentStateRead.waitingInteraction(
          turnId: text(turnId),
          interactionId: text(interactionId),
        ),
      CancellingAgentState(:final turnId) => AgentStateRead.cancelling(
        turnId: text(turnId),
      ),
      ClosingAgentState(
        :final workspaceDisposition,
        :final turnId,
        error: final failure,
      ) =>
        AgentStateRead.closing(
          workspaceDisposition: workspaceDisposition,
          turnId: optional(turnId),
          error: failure == null ? null : error(failure),
        ),
      ClosedAgentState() => const AgentStateRead.closed(),
      FaultedAgentState(
        :final turnId,
        :final classification,
        error: final failure,
      ) =>
        AgentStateRead.faulted(
          turnId: optional(turnId),
          classification: classification,
          error: error(failure),
        ),
    };
    final frozen = value.frozenModel;
    return AgentDirectoryEntityRead(
      reference: reference,
      value: AgentDirectoryEntryRead(
        id: ReadText.inline(text: value.id),
        threadId: ReadText.inline(text: value.threadId),
        path: ReadText.inline(text: value.path),
        parentPath: value.parentPath == null
            ? null
            : ReadText.inline(text: value.parentPath!),
        rootThreadId: ReadText.inline(text: value.rootThreadId),
        depth: value.depth,
        role: ReadText.inline(text: value.role),
        task: ReadText.inline(text: value.task),
        summary: optional(value.summary),
        state: state,
        execution: value.execution,
        canStop: value.canStop,
        awaitingScheduling: value.awaitingScheduling,
        delegationMode: value.delegationMode,
        delegationPreference: value.delegationPreference,
        frozenModel: frozen == null
            ? null
            : FrozenModelSelectionRead(
                accountId: text(frozen.model.accountId),
                modelId: text(frozen.model.modelId),
                effort: optional(frozen.effort),
              ),
        updatedAt: value.updatedAt,
      ),
    );
  }));
}
