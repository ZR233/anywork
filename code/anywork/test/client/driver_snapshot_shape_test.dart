import 'dart:convert';

import 'package:anywork/src/diagnostics/contracts/timeline_diagnostics.dart';
import 'package:anywork/src/shared/driver_snapshot.dart';
import 'package:anywork/src/shared/driver_snapshot_json.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/conversation.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/persistence.dart';
import 'package:anywork_client/recovery.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/updates.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../anywork_client/test/support/conversation_fixture.dart'
    show fixtureThread;

void main() {
  test('threadStatus uses directory metadata while execution is running', () {
    final thread = fixtureThread('shape-thread');
    const execution = ThreadExecutionState(
      stamp: ThreadFacetStamp(
        runtimeEpoch: 'shape-runtime',
        incarnation: 1,
        facet: ThreadFacet.execution,
        revision: 1,
      ),
      sync: FacetSyncState(phase: FacetSyncPhase.ready),
      value: ThreadExecutionBaseline(
        status: ThreadStatus.running,
        activeTurn: null,
        recentTerminalTurn: null,
        interactions: InteractionIndexHeader(
          reference: InteractionIndexRef(entry: 1, revision: 1),
          total: 0,
          pending: 0,
        ),
        activity: null,
        storage: null,
      ),
    );

    final json = _json(_snapshot(thread: thread, execution: execution));
    final workspace = json['workspace'] as Map<String, dynamic>;
    expect(workspace['threadStatus'], 'idle');
    expect(workspace['isBusy'], isTrue);

    final unknown = _json(_snapshot(thread: null, execution: execution));
    expect(
      (unknown['workspace'] as Map<String, dynamic>)['threadStatus'],
      isNull,
      reason: 'Execution cannot reconstruct unavailable directory metadata.',
    );
  });

  test(
    'historyAttachments remains a castable empty list without a display',
    () {
      final json = _json(_snapshot(thread: fixtureThread('shape-thread')));
      expect(json['timeline'], isNull);
      final workspace = json['workspace'] as Map<String, dynamic>;
      final attachments = (workspace['historyAttachments'] as List)
          .cast<Map<String, dynamic>>();
      expect(attachments, isEmpty);
    },
  );
}

// Exercise the real Driver whitelist and JSON boundary, not a test projection.
// Unrelated domain inputs remain explicitly unavailable; no owner, native read
// or second cache is needed to verify these two serialization contracts.
Map<String, dynamic> _json(DriverSnapshot snapshot) =>
    jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>;

DriverSnapshot _snapshot({
  required WorkspaceThreadRecord? thread,
  ThreadExecutionState? execution,
}) => DriverSnapshot(
  selection: const WorkspaceSelection(
    projectId: 'project',
    threadId: 'shape-thread',
    needsOpen: false,
  ),
  project: null,
  thread: thread,
  rootThreadId: 'shape-thread',
  directory: thread == null ? null : [thread],
  directoryHasMore: null,
  agents: null,
  agentDirectoryError: null,
  execution: execution,
  metrics: null,
  context: null,
  threadConfiguration: null,
  authoring: null,
  interactions: null,
  startDraft: null,
  composer: null,
  configuration: ConfigurationState(
    projection: _unavailableProjection(),
    sourceStatus: null,
    accounts: const CollectionMirror.unavailable(lastKnown: null),
    defaultAccountId: null,
    modeRoutes: null,
    roles: null,
    permissionMode: null,
    instructions: null,
    skillsSettings: null,
    mcpConfigurations: null,
    general: null,
    delegation: null,
    webSearch: null,
    deepSeekSearch: null,
  ),
  models: ModelsState(
    projection: _unavailableProjection(),
    sourceStatus: null,
    accounts: const CollectionMirror.unavailable(lastKnown: null),
    webSearch: null,
    deepSeekSearch: null,
  ),
  operations: const [],
  persistence: PersistenceState(
    projection: _unavailableProjection(),
    value: null,
  ),
  recovery: RecoveryState(
    projection: _unavailableProjection(),
    sourceStatus: null,
    issues: const CollectionMirror.unavailable(lastKnown: null),
  ),
  updates: UpdatesState(projection: _unavailableProjection(), value: null),
  startup: const StartupState.idle(),
  display: const TimelineDiagnosticsSnapshot(
    timeline: null,
    timelineScroll: null,
  ),
  conversation: null,
  status: null,
  plan: null,
  bots: const DriverBotsUnknown('not observed'),
);

ProductProjection<H> _unavailableProjection<H>() => ProductProjection<H>(
  stamp: null,
  header: null,
  sync: const ResourceSyncState(
    phase: ResourceSyncPhase.idle,
    error: null,
    retryExhausted: false,
  ),
);
