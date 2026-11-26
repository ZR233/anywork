import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/rust/api/studio/handlers/timeline.dart';
import 'package:anywork/src/rust/api/studio/types/chat.dart';
import 'package:anywork/src/rust/api/studio/types/delegation.dart';
import 'package:anywork/src/rust/api/studio/types/presentation.dart';
import 'package:anywork/src/rust/api/studio/types/thread_stream.dart';
import 'package:anywork/src/rust/frb_generated.dart' show RustLibApi;
import 'package:anywork/src/shared/studio_driver_state.dart';
import 'package:anywork_client/studio_client.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/frb_test_lifecycle.dart';
import '../../support/chat_fixtures.dart';

void main() {
  for (final (phase, millis) in [
    ('waiting', '45000'),
    ('recovered', '9007199254740993'),
    ('cancelled', '18446744073709551615'),
  ]) {
    test(
      'small and paged Current agree for the $phase product fixture',
      () async {
        final fixture = jsonDecode(
          File('test/fixtures/provider_recovery_notices.json')
              .readAsStringSync(),
        ) as Map<String, Object?>;
        final notice = fixture[phase] as Map<String, Object?>;
        final frame = BridgeCurrentFrame.projection(
          revision: BridgeCurrentRevision(
            ownerId: 'owner',
            revision: BigInt.two,
          ),
          projection: BridgeCurrentProjection(
            logicalStatus: BridgeThreadStatus.running,
            executionPresent: true,
            sources: const [],
            atoms: [
              BridgeCurrentAtom(
                id: 'recovery:$phase',
                source: const BridgeChatSourceId.foregroundTurn(turnId: 'turn'),
                kind: BridgeChatAtomKind.text,
                delivery: BridgeChatDeliveryKind.foreground,
                lifecycle: const BridgeChatAtomLifecycle.active(
                  status: BridgeChatActiveStatus.waiting,
                ),
                modelRecovery: BridgeModelRecoveryNotice(
                  phase: BridgeModelRecoveryPhase.values.byName(
                    notice['phase'] as String,
                  ),
                  failureKind: notice['failureKind'] as String,
                  reason: notice['reason'] as String,
                  retryCount: notice['retryCount'] as int,
                  maxRetries: notice['maxRetries'] as int,
                  effectiveWaitMillis: BigInt.parse(
                    notice['effectiveWaitMillis'] as String,
                  ),
                  failure: _bridgeFailure(
                    notice['failure'] as Map<String, Object?>,
                  ),
                ),
                contents: const [],
              ),
            ],
            previews: const [],
            collections: const [],
          ),
        );
        final delivered = await _deliver(frame) as ProjectionCurrentFrame;
        final small = delivered.projection.atoms.single;
        final paged = decodeCurrentAtomPayload(
          InlineCurrentPayload(
            bytes: utf8.encode(
              jsonEncode({
                'id': 'recovery:$phase',
                'source': {'kind': 'foregroundTurn', 'turnId': 'turn'},
                'kind': 'text',
                'delivery': 'foreground',
                'lifecycle': {'kind': 'active', 'status': 'waiting'},
                'modelRecovery': notice,
                'contents': const <Object?>[],
              }),
            ),
          ),
        );
        expect(small.id, paged.id);
        expect(small.modelRecovery, paged.modelRecovery);
        expect(paged.modelRecovery?.effectiveWaitMillis, BigInt.parse(millis));
        expect(
          paged.modelRecovery?.failure?.retryAfterMs,
          BigInt.parse(millis),
        );
        expect(small.modelRecovery?.toJson(), notice);
      },
    );
  }

  final maxUnsignedWait = BigInt.parse('18446744073709551615');
  for (final (label, largeWait) in [
    ('shared failure fixture', false),
    ('waits wider than a signed Dart int', true),
  ]) {
    test(
      'Current maps a bridge completion to typed Client failure ($label)',
      () async {
        final fixture = jsonDecode(
          File('test/fixtures/provider_failure_retry.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final data = fixture['data'] as Map<String, Object?>;
        final failure = data['failure'] as Map<String, Object?>;
        final retry = failure['retry'] as Map<String, Object?>;
        final recovery = failure['recovery'] as Map<String, Object?>;
        final frame = BridgeCurrentFrame.notification(
          revision: BridgeCurrentRevision(
            ownerId: 'owner',
            revision: BigInt.two,
          ),
          notification: BridgeThreadNotificationEnvelope(
            threadId: 'thread',
            epoch: BigInt.one,
            baseRevision: BigInt.one,
            revision: BigInt.two,
            emittedAt: data['completedAt'] as int,
            notification: BridgeThreadNotification.turnCompleted(
              turn: BridgeTurn(
                id: 'turn',
                threadId: 'thread',
                revision: BigInt.two,
                updatedAt: data['completedAt'] as int,
                state: BridgeTurnState.failed(
                  startedAt: data['startedAt'] as int,
                  completedAt: data['completedAt'] as int,
                  failure: BridgeTurnFailureDto(
                    category: failure['category'] as String,
                    providerKind: failure['providerKind'] as String,
                    code: failure['code'] as String,
                    httpStatus: failure['httpStatus'] as int,
                    message: failure['message'] as String,
                    retryDisposition: retry['kind'] as String,
                    retryAfterMs: largeWait
                        ? maxUnsignedWait
                        : BigInt.parse(retry['retryAfterMs'] as String),
                    errorType: failure['errorType'] as String,
                    requestId: failure['requestId'] as String,
                    stage: failure['stage'] as String,
                    recovery: BridgeModelRecoveryInfo(
                      retryCount: recovery['retryCount'] as int,
                      maxRetries: recovery['maxRetries'] as int,
                      effectiveWaitMillis: largeWait
                          ? maxUnsignedWait - BigInt.one
                          : BigInt.parse(
                              recovery['effectiveWaitMillis'] as String,
                            ),
                      reason: recovery['reason'] as String,
                      stopReason: recovery['stopReason'] as String,
                      error: recovery['error'] as String?,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        final delivered = await _deliver(frame) as NotificationCurrentFrame;
        final update = delivered.notification.update as ThreadTurnUpdate;
        expect(
          update.turn.failure,
          StudioTurnFailureView(
            category: 'provider',
            providerKind: 'rateLimit',
            code: 'rate_limit_exceeded',
            httpStatus: 429,
            message: 'Temporarily rate limited',
            retryDisposition: StudioRetryDisposition.retryable,
            retryAfterMs: largeWait ? maxUnsignedWait : BigInt.from(45000),
            errorType: 'rate_limit_error',
            requestId: 'req-rate-limit-fixture',
            stage: StudioProviderFailureStage.request,
            recovery: StudioModelRecoveryInfo(
              retryCount: 2,
              maxRetries: 2,
              effectiveWaitMillis: largeWait
                  ? maxUnsignedWait - BigInt.one
                  : BigInt.from(47000),
              reason: StudioProviderRecovery.none,
              stopReason: StudioModelRecoveryStopReason.budgetExhausted,
            ),
          ),
        );
        final driverFailure = _driverFailure(update.turn);
        expect(
          driverFailure['retryAfterMs'],
          largeWait ? '18446744073709551615' : '45000',
        );
        expect(
          (driverFailure['recovery']
              as Map<String, Object?>)['effectiveWaitMillis'],
          largeWait ? '18446744073709551614' : '47000',
        );
        expect(
          StudioTurnFailureView.fromJson(driverFailure),
          update.turn.failure,
        );
      },
    );
  }
}

BridgeTurnFailureDto _bridgeFailure(Map<String, Object?> raw) {
  final retry = raw['retry'] as Map<String, Object?>;
  return BridgeTurnFailureDto(
    category: raw['category'] as String,
    providerKind: raw['providerKind'] as String,
    code: raw['code'] as String,
    httpStatus: raw['httpStatus'] as int,
    message: raw['message'] as String,
    retryDisposition: retry['kind'] as String,
    retryAfterMs: BigInt.parse(retry['retryAfterMs'] as String),
    errorType: raw['errorType'] as String,
    requestId: raw['requestId'] as String,
    stage: raw['stage'] as String,
  );
}

Map<String, Object?> _driverFailure(StudioTurnView turn) {
  final row = SessionDirectoryRow(
    sessionId: 'session',
    agentId: 'agent',
    threadId: turn.threadId,
    workspaceId: 'workspace',
    title: 'Provider recovery',
    mode: ThreadModeId.auto,
    delegationMode: DelegationMode.profile,
    delegationPreference: DelegationPreference.balanced,
    workspacePath: '/workspace',
    backend: const NativeAgentBackendView(
      config: NativeAgentConfigView(),
      status: ThreadStatusView.idle,
    ),
    updatedAt: turn.updatedAt,
  );
  final snapshot = StudioDriverState.snapshotJson(
    observed: StudioDriverFacts(
      acpAuthLoaded: false,
      workspace: AgentWorkspaceView(
        row: row,
        rootRow: row,
        syncState: AgentWorkspaceSyncState.ready,
        runtime: chatWorkspace(turn.threadId).runtime,
        turn: null,
        lastTurn: turn,
        activeInteraction: null,
        composer: const ComposerThreadState.idle(),
        composerMode: AgentComposerMode.editable,
        accounts: const [],
        roles: const [],
        agents: const [],
      ),
    ),
  );
  final decoded = jsonDecode(snapshot) as Map<String, Object?>;
  final workspace = decoded['workspace'] as Map<String, Object?>;
  final lastTurn = workspace['lastTurn'] as Map<String, Object?>;
  return lastTurn['failure'] as Map<String, Object?>;
}

Future<CurrentFrame> _deliver(BridgeCurrentFrame frame) async {
  final transport = TestFrbStudioTransport(mockApi: _CurrentApi(frame));
  const demand = ReadDemand(maxItems: 5, maxBytes: 4096);
  final reader = await transport.openCurrentReader(
    'thread',
    currentProtocolVersion: currentProtocolVersion,
    demand: demand,
  );
  final watch = await reader.watch(demand: demand);
  return watch.frames.single;
}

final class _CurrentApi implements RustLibApi {
  _CurrentApi(this.frame);

  final BridgeCurrentFrame frame;

  @override
  Future<BridgeCurrentReader> crateApiStudioHandlersTimelineOpenCurrentReader({
    required String threadId,
    required int currentProtocolVersion,
    required BridgeReadDemand demand,
  }) async => _Reader(frame);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Reader implements BridgeCurrentReader {
  _Reader(this.frame);

  final BridgeCurrentFrame frame;

  @override
  String threadId() => 'thread';

  @override
  BridgeOpenCurrentReader metadata() => const BridgeOpenCurrentReader(
    readerId: 'reader',
    currentProtocolVersion: currentProtocolVersion,
    currentOwnerId: 'owner',
  );

  @override
  BridgeCurrentView initialView() => BridgeCurrentView(
    revision: BridgeCurrentRevision(ownerId: 'owner', revision: BigInt.one),
    state: BridgeThreadSnapshot(
      schemaVersion: threadSchemaVersion,
      revision: BigInt.one,
      thread: const BridgeThread(
        id: 'thread',
        workspaceId: 'workspace',
        title: 'Title',
        delegationMode: BridgeDelegationMode.profile,
        delegationPreference: BridgeDelegationPreference.economy,
        workspaceMode: 'local',
        workspacePath: '/workspace',
        rootThreadId: 'thread',
        role: 'assistant',
        agentPath: 'root',
        status: BridgeThreadStatus.running,
        createdAt: 1000,
        updatedAt: 1000,
        archived: false,
      ),
      businessRefs: const BridgeThreadBusinessRefs(),
      interactions: const [],
      runtimeAvailability: BridgeThreadRuntimeAvailability.active,
    ),
    projection: const BridgeCurrentProjection(
      logicalStatus: BridgeThreadStatus.running,
      executionPresent: true,
      sources: [],
      atoms: [],
      previews: [],
      collections: [],
    ),
  );

  @override
  Future<BridgeCurrentWatch> watch({
    BridgeCurrentRevision? after,
    required BridgeReadDemand demand,
  }) async => _Watch(frame);

  @override
  Future<void> close() async {}

  @override
  void requestClose() {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Watch implements BridgeCurrentWatch {
  _Watch(this.frame);

  BridgeCurrentFrame? frame;

  @override
  Future<BridgeCurrentFrame?> next() async {
    final value = frame;
    frame = null;
    return value;
  }

  @override
  Future<void> close() async {}

  @override
  void requestClose() {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
