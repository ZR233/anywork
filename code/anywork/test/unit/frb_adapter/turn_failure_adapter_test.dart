import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/domain/models/agent_workspace_view.dart';
import 'package:anywork/src/rust/api/studio/handlers/timeline.dart';
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
      'Feed preserves recovery values for the $phase product fixture',
      () async {
        final fixture = jsonDecode(
          File('test/fixtures/provider_recovery_notices.json')
              .readAsStringSync(),
        ) as Map<String, Object?>;
        final notice = fixture[phase] as Map<String, Object?>;
        final item = await _deliver(
          BridgeTimelineItem.assistantText(
            id: 'recovery:$phase',
            seq: BigInt.two,
            channel: 'assistant',
            text: '',
            isFinalTurnDelivery: false,
            outcome: 'failed',
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
          ),
        ) as TimelineAssistantText;
        expect(item.id, 'recovery:$phase');
        expect(item.modelRecovery?.effectiveWaitMillis, BigInt.parse(millis));
        expect(item.modelRecovery?.failure?.retryAfterMs, BigInt.parse(millis));
        expect(item.modelRecovery?.toJson(), notice);
      },
    );
  }

  final maxUnsignedWait = BigInt.parse('18446744073709551615');
  for (final (label, largeWait) in [
    ('shared failure fixture', false),
    ('waits wider than a signed Dart int', true),
  ]) {
    test(
      'Feed maps a bridge turn outcome to typed Client failure ($label)',
      () async {
        final fixture = jsonDecode(
          File('test/fixtures/provider_failure_retry.json').readAsStringSync(),
        ) as Map<String, Object?>;
        final data = fixture['data'] as Map<String, Object?>;
        final failure = data['failure'] as Map<String, Object?>;
        final retry = failure['retry'] as Map<String, Object?>;
        final recovery = failure['recovery'] as Map<String, Object?>;
        final item = await _deliver(
          BridgeTimelineItem.turnOutcome(
            id: 'failure',
            seq: BigInt.two,
            outcome: 'failed',
            turnId: 'turn',
            turnFailure: BridgeTurnFailureDto(
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
                    : BigInt.parse(recovery['effectiveWaitMillis'] as String),
                reason: recovery['reason'] as String,
                stopReason: recovery['stopReason'] as String,
                error: recovery['error'] as String?,
              ),
            ),
          ),
        ) as TimelineTurnOutcome;
        final turn = StudioTurnView(
          turnId: 'turn',
          threadId: 'thread',
          revision: 2,
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            (data['completedAt'] as int) * 1000,
            isUtc: true,
          ),
          state: FailedStudioTurnState(
            startedAt: data['startedAt'] as int,
            completedAt: data['completedAt'] as int,
            failure: item.turnFailure!,
          ),
        );
        expect(
          item.turnFailure,
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
        final driverFailure = _driverFailure(turn);
        expect(
          driverFailure['retryAfterMs'],
          largeWait ? '18446744073709551615' : '45000',
        );
        expect(
          (driverFailure['recovery']
              as Map<String, Object?>)['effectiveWaitMillis'],
          largeWait ? '18446744073709551614' : '47000',
        );
        expect(StudioTurnFailureView.fromJson(driverFailure), item.turnFailure);
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

Future<TimelineItem> _deliver(BridgeTimelineItem item) async {
  final transport = TestFrbStudioTransport(
    mockApi: _FeedApi(
      BridgeConversationEvent.timeline(
        patch: BridgeTimelinePatch.append(items: [item]),
      ),
    ),
  );
  final feed = await transport.openConversationFeed('thread', initialLimit: 5);
  try {
    final event = await feed.events.single as ConversationTimeline;
    return (event.patch as TimelineAppend).items.single;
  } finally {
    await feed.close();
  }
}

final class _FeedApi implements RustLibApi {
  _FeedApi(this.frame);
  final BridgeConversationEvent frame;

  @override
  Future<BridgeConversationFeed>
  crateApiStudioHandlersTimelineOpenConversationFeed({
    required String threadId,
    required int initialLimit,
  }) async => _Feed(frame);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Feed implements BridgeConversationFeed {
  _Feed(this.frame);
  BridgeConversationEvent? frame;

  @override
  String threadId() => 'thread';

  @override
  Future<BridgeConversationEvent?> nextEvent() async {
    final next = frame;
    frame = null;
    return next;
  }

  @override
  void requestClose() {}

  @override
  Future<void> close() async {}

  @override
  void dispose() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
