import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/features/conversation/timeline/state/timeline_outcome_presentation.dart';
import 'package:anywork_client/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the failure payload verified against Rust serialization', () {
    final payload = jsonDecode(
      File('test/fixtures/provider_failure_retry.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final summary = parseTimelineOutcome(payload);
    expect(summary.failure!.providerKind, 'rateLimit');
    expect(summary.failure!.httpStatus, 429);
    expect(summary.failure!.isRetryable, isTrue);
    expect(summary.failure!.retryAfterSeconds, BigInt.from(45));
    expect(summary.failure!.errorType, 'rate_limit_error');
    expect(summary.failure!.requestId, 'req-rate-limit-fixture');
    expect(summary.failure!.stage, StudioProviderFailureStage.request);
    expect(
      summary.failure!.recovery,
      StudioModelRecoveryInfo(
        retryCount: 2,
        maxRetries: 2,
        effectiveWaitMillis: BigInt.from(47000),
        reason: StudioProviderRecovery.none,
        stopReason: StudioModelRecoveryStopReason.budgetExhausted,
      ),
    );
    expect(summary.durationSeconds, 5);
  });

  test(
    'parses provider turn failure with retryable and permanent metadata',
    () {
      final summary = parseTimelineOutcome({
        'kind': 'failed',
        'data': {
          'startedAt': 1795483393,
          'completedAt': 1795483527,
          'failure': {
            'category': 'provider',
            'providerKind': 'unknown',
            'code': 'overloaded',
            'message': '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]',
            'retry': {'kind': 'permanent'},
          },
        },
      });

      expect(summary.kind, 'failed');
      expect(summary.durationSeconds, 134);
      expect(summary.failure, isNotNull);
      expect(summary.failure!.category, 'provider');
      expect(summary.failure!.providerKind, 'unknown');
      expect(summary.failure!.hasVisibleProviderKind, isFalse);
      expect(summary.failure!.code, 'overloaded');
      expect(
        summary.failure!.message,
        '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]',
      );
      expect(summary.failure!.retryKind, 'permanent');
      expect(summary.failure!.isRetryable, isFalse);
      expect(summary.failure!.recovery, isNull);
      expect(
        summary.plainDiagnostic,
        '该模型当前访问量过大，请您稍后再试[2026112409252610a0f9ae03204283]\noverloaded',
      );
    },
  );

  test('parses retryable failure with httpStatus and retryAfterMs', () {
    final summary = parseTimelineOutcome({
      'kind': 'failed',
      'data': {
        'startedAt': 1000,
        'completedAt': 1005,
        'failure': {
          'category': 'providerCapacity',
          'providerKind': 'transport',
          'code': 'service_unavailable',
          'httpStatus': 503,
          'message': 'Upstream gateway temporarily unavailable',
          'retry': {'kind': 'retryable', 'retryAfterMs': '4200'},
        },
      },
    });

    expect(summary.durationSeconds, 5);
    expect(summary.failure!.hasVisibleProviderKind, isTrue);
    expect(summary.failure!.providerKind, 'transport');
    expect(summary.failure!.httpStatus, 503);
    expect(summary.failure!.isRetryable, isTrue);
    expect(summary.failure!.retryAfterSeconds, BigInt.from(5));
    expect(
      summary.plainDiagnostic,
      'Upstream gateway temporarily unavailable\nservice_unavailable · HTTP 503',
    );
  });

  test('parses flat agent/inference/test fallback payloads', () {
    final flatMessage = parseTimelineOutcome({
      'kind': 'failed',
      'data': {'message': 'flat-failure-message'},
    });
    expect(flatMessage.failure?.message, 'flat-failure-message');
    expect(flatMessage.failure?.hasTechnicalDetails, isFalse);

    final agentError = parseTimelineOutcome({
      'kind': 'failed',
      'data': {'failedAt': 100, 'error': 'subagent crashed'},
    });
    expect(agentError.failure?.message, 'subagent crashed');

    final deniedReason = parseTimelineOutcome({
      'kind': 'denied',
      'data': {'deniedAt': 100, 'reason': 'approval rejected'},
    });
    expect(deniedReason.failure?.message, 'approval rejected');
  });

  test('parses budgetLimited turn outcome and usage snapshot', () {
    final summary = parseTimelineOutcome({
      'kind': 'budgetLimited',
      'data': {
        'startedAt': 1000,
        'completedAt': 1145,
        'limit': {
          'kind': 'modelStep',
          'usage': {
            'modelSteps': 24,
            'toolCalls': 41,
            'waitCalls': 2,
            'elapsedMs': 145000,
          },
        },
        'rollover': {
          'kind': 'failed',
          'data': {'error': 'context snapshot locked'},
        },
      },
    });

    expect(summary.kind, 'budgetLimited');
    expect(summary.durationSeconds, 145);
    expect(summary.budget?.limitKind, 'modelStep');
    expect(summary.budget?.modelSteps, 24);
    expect(summary.budget?.toolCalls, 41);
    expect(budgetCalls(summary), (24, 41, 2));
    expect(summary.budget?.rolloverKind, 'failed');
    expect(summary.budget?.rolloverError, 'context snapshot locked');
  });

  test('parses cancelled turn cause and rejects negative durations', () {
    final summary = parseTimelineOutcome({
      'kind': 'cancelled',
      'data': {
        'startedAt': 200,
        'completedAt': 100,
        'cause': {
          'kind': 'coalesced',
          'data': {'targetTurnId': 'turn-next'},
        },
      },
    });

    expect(summary.kind, 'cancelled');
    expect(summary.durationSeconds, isNull);
    expect(summary.cancellation?.causeKind, 'coalesced');
    expect(summary.cancellation?.targetTurnId, 'turn-next');
  });

  test('completed/succeeded outcomes produce null plainDiagnostic', () {
    expect(parseTimelineOutcome({'kind': 'completed'}).plainDiagnostic, isNull);
    expect(parseTimelineOutcome({'kind': 'succeeded'}).plainDiagnostic, isNull);
    expect(parseTimelineOutcome(null).plainDiagnostic, isNull);
  });
}

(int?, int?, int?) budgetCalls(TimelineOutcomeSummary summary) => (
  summary.budget?.modelSteps,
  summary.budget?.toolCalls,
  summary.budget?.waitCalls,
);
