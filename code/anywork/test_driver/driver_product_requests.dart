import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/app/app_graph.dart';
import 'package:anywork/src/l10n/studio_l10n.dart';
import 'package:anywork/src/shared/driver_projection.dart';
import 'package:anywork_client/account_usage.dart';
import 'package:anywork_client/mcp.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/statistics.dart';
import 'package:flutter/widgets.dart';

/// Explicit Driver actions and request-local product whitelists. No transport,
/// private SDK import, generic Client, registry or read-created domain owner.
final class DriverProductRequests {
  DriverProductRequests(this.graph);
  final AppGraph graph;
  Future<CommandResult<Unit>>? _fixtureAdmission;

  /// An explicit request owns one visibility lease and one passive observation.
  /// Ordinary snapshots never acquire this demand or synchronize the domain.
  Future<String> statistics() async {
    final repository = graph.statistics;
    final demand = repository.acquireVisibleDemand();
    Observation? observation;
    try {
      final ready = Completer<StatisticsSnapshot>();
      void consider(StatisticsState state) {
        if (ready.isCompleted) return;
        if (state.sync.phase == ResourceSyncPhase.failed) {
          // A retained last-good snapshot cannot hide this attempt's failure.
          ready.completeError(
            state.sync.error ??
                StateError('statistics failed without a typed failure'),
          );
        } else if (state.sync.phase == ResourceSyncPhase.closed) {
          ready.completeError(
            StateError('statistics closed before a complete ready snapshot'),
          );
        } else if (state.sync.phase == ResourceSyncPhase.ready) {
          final snapshot = state.snapshot;
          if (snapshot != null) ready.complete(snapshot);
        }
      }

      final watch = repository.state.watchLatest(consider);
      observation = watch.observation;
      consider(watch.value);
      final snapshot = await ready.future.timeout(const Duration(seconds: 30));
      return jsonEncode(_statisticsSnapshot(snapshot));
    } finally {
      try {
        observation?.cancel();
      } finally {
        // Release only this request's demand. The repository retires the last
        // shared demand's attempt and supervises its feed/read-scope join;
        // this request must not close an owner still used by another page.
        demand.release();
      }
    }
  }

  Future<String> admitFixtureImage() async {
    final selection = graph.workspace.state.value.selection;
    final project = selection.projectId;
    if (project == null || selection.needsOpen) {
      return _fixtureFailure('composer-not-ready');
    }
    final candidates = [
      File('test_driver/fixtures/tool-image.png'),
      File('code/anywork/test_driver/fixtures/tool-image.png'),
    ];
    File? fixture;
    for (final candidate in candidates) {
      if (await candidate.exists()) {
        fixture = candidate;
        break;
      }
    }
    if (fixture == null) return _fixtureFailure('fixture-not-found');
    final bytes = await fixture.readAsBytes();
    if (graph.workspace.state.value.selection != selection) {
      return _fixtureFailure('selection-changed');
    }
    // This is an explicit user-equivalent command, not a snapshot query. Its
    // operation and attachment cleanup remain owned by D1 and the exit graph.
    final ticket = selection.threadId == null
        ? graph.drafts.start(project).addClipboardImage(bytes)
        : graph.drafts.composer(selection.threadId!).addClipboardImage(bytes);
    final result = _fixtureAdmission = ticket.result;
    // Keep the exact result for the follow-up. ignore only marks it observed;
    // it does not replace, settle or discard the accepted operation's outcome.
    result.ignore();
    return jsonEncode({
      'ok': true,
      'hook': 'driver-fixture-clipboard-image',
      'stage': 'admission-started',
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
      'previewPending': null,
    });
  }

  Future<String> fixtureImageOutcome() async {
    final pending = _fixtureAdmission;
    if (pending == null) return _fixtureFailure('admission-not-started');
    final outcome = await pending;
    final admitted =
        outcome is CommittedCommandResult<Unit> ||
        outcome is AcknowledgedCommandResult<Unit>;
    return jsonEncode({
      'ok': false,
      'hook': 'driver-fixture-clipboard-image-preview',
      'stage': admitted
          ? 'admission-complete-preview-unknown'
          : 'admission-failed',
      'reason': admitted
          ? 'preview-not-published-by-draft-metadata'
          : switch (outcome) {
              RejectedCommandResult<Unit>(:final error) ||
              UnknownOutcomeCommandResult<Unit>(:final error) ||
              SyncFailedCommandResult<Unit>(:final error) ||
              AcknowledgedSyncFailedCommandResult<Unit>(
                :final error,
              ) => error.code.name,
              _ => null,
            },
      'pasteSeam': 'unavailable',
      'systemClipboardTouched': false,
    });
  }

  String accountUsage({BuildContext? labelsContext}) {
    final configuration = graph.configuration.state.value;
    final usage = graph.accountUsage.state.value;
    final accounts =
        configuration.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(
            configuration.accounts,
            configuration.projection.stamp?.origin,
          )
        : null;
    final rows = usage.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(usage.usages, usage.projection.stamp?.origin)
        : null;
    final labels = labelsContext?.l10n;
    final checks = graph.accountUsage.checks.value;
    return jsonEncode({
      'accounts': accounts == null
          ? null
          : [
              for (final account in accounts)
                {
                  'id': account.accountId,
                  'name': account.name,
                  'templateId': account.templateId,
                  'protocol': account.protocol,
                  'usageQueryRevision': account.usageQueryRevision,
                  'hasBearerToken': account.hasBearerToken,
                },
            ],
      'revision': usage.projection.stamp?.revision,
      'usages': rows == null
          ? null
          : [
              for (final row in rows)
                {
                  'id': row.accountId,
                  ...switch (row.state) {
                    UsageUnsupported() => {'kind': 'unsupported'},
                    UsageMissingCredential() => {'kind': 'missingCredential'},
                    UsageFailed(:final error) => {
                      'kind': 'failed',
                      'code': error.code,
                      'retryable': error.retryable,
                    },
                    UsageReady(:final data) => {
                      'kind': 'ready',
                      ...switch (data) {
                        DeepSeekBalance(:final balances) => {
                          'balances': [
                            for (final balance in balances)
                              balance.totalBalance,
                          ],
                        },
                        ZhipuCodingPlan(:final limits) => {
                          'windows': [
                            for (final limit in limits)
                              switch (limit.window) {
                                FiveHourQuota() => 'fiveHour',
                                WeeklyQuota() => 'weekly',
                                McpMonthlyQuota() => 'mcpMonthly',
                                OtherQuota(:final value) => value,
                              },
                          ],
                        },
                      },
                    },
                  },
                },
            ],
      'loadingAccountIds': [
        for (final check in checks.values)
          if (check.ticket.state.value.isPending) check.accountId,
      ],
      'errorsByAccountId': {
        for (final check in checks.values)
          if (check.ticket.state.value.error case final error?)
            check.accountId: error.code.name,
      },
      if (labels != null)
        'labels': {
          'displayName': labels.settingsDisplayName,
          'delete': labels.settingsDeleteAccount,
          'setDefault': labels.settingsSetAsDefaultAccount,
        },
    });
  }

  String mcp() {
    final state = graph.mcp.state.value;
    final origin = state.projection.sync.phase == ResourceSyncPhase.ready
        ? state.projection.stamp?.origin
        : null;
    final rows = state.projection.sync.phase == ResourceSyncPhase.ready
        ? currentDriverRows(state.servers, origin)
        : null;
    return jsonEncode({
      'ok': rows != null,
      'revision': state.projection.stamp?.revision,
      'desiredConfigFingerprint': currentDriverRead(
        state.desiredConfigFingerprint,
        origin,
      ),
      'appliedConfigFingerprint': currentDriverRead(
        state.appliedConfigFingerprint,
        origin,
      ),
      'activeServers': currentDriverRead(state.activeServerIds, origin),
      'servers': rows == null
          ? null
          : [
              for (final server in rows)
                {
                  'id': server.id,
                  'transport': server.transport,
                  'endpoint': _endpoint(server.endpoint),
                  'sourceKind': server.sourceKind,
                  'mutationPolicy': server.mutationPolicy,
                  'state': switch (server.state) {
                    DisabledMcpServerState(:final message) => {
                      'kind': 'disabled',
                      'message': message,
                    },
                    MissingCredentialMcpServerState(:final message) => {
                      'kind': 'missingCredential',
                      'message': message,
                    },
                    CheckingMcpServerState(:final message) => {
                      'kind': 'checking',
                      'message': message,
                    },
                    AvailableMcpServerState(
                      :final checkedAt,
                      :final toolCount,
                    ) =>
                      {
                        'kind': 'available',
                        'checkedAt': checkedAt,
                        'toolCount': toolCount,
                      },
                    UnavailableMcpServerState(:final checkedAt, :final error) =>
                      {
                        'kind': 'unavailable',
                        'checkedAt': checkedAt,
                        'code': error.code,
                        'message': error.message,
                        'retryable': error.retryable,
                      },
                  },
                },
            ],
    });
  }
}

String _fixtureFailure(String reason) => jsonEncode({
  'ok': false,
  'hook': 'driver-fixture-clipboard-image',
  'reason': reason,
  'pasteSeam': 'unavailable',
  'systemClipboardTouched': false,
});

Map<String, Object?> _statisticsSnapshot(StatisticsSnapshot snapshot) => {
  'loaded': true,
  'syncPhase': ResourceSyncPhase.ready.name,
  'syncError': null,
  'ownerEpoch': snapshot.origin.ownerEpoch,
  'incarnation': snapshot.origin.incarnation,
  'revision': snapshot.revision,
  'summariesReference': {
    'entry': snapshot.summariesReference.entry,
    'revision': snapshot.summariesReference.revision,
  },
  'historyReference': {
    'entry': snapshot.historyReference.entry,
    'revision': snapshot.historyReference.revision,
  },
  'statisticsPending': snapshot.statisticsPending,
  'statisticsGap': snapshot.statisticsGap,
  'readFailed': snapshot.readFailed,
  'summaries': [
    for (final summary in snapshot.summaries)
      {
        'accountId': summary.identity.accountId,
        'accountDisplayName': summary.identity.accountDisplayName,
        'modelId': summary.identity.modelId,
        ..._performanceCounters(summary.counters),
        'effortBreakdowns': [
          for (final effort in summary.effortBreakdowns)
            {
              'effort': effort.identity.effort,
              ..._performanceCounters(effort.counters),
            },
        ],
      },
  ],
  'history': [
    for (final sample in snapshot.history)
      {
        'accountId': sample.identity.accountId,
        'accountDisplayName': sample.identity.accountDisplayName,
        'modelId': sample.identity.modelId,
        'sentModel': sample.identity.sentModel,
        'reportedModel': sample.identity.reportedModel,
        'matchState': sample.identity.modelMatchState.name,
        'effort': sample.identity.effort,
        'tokens': sample.counters.completionTokens,
        'ttftMillis': sample.counters.ttftMillis,
        'decodeMillis': sample.counters.decodeMillis,
        'responseMillis': sample.counters.totalResponseMillis,
        'tokensPerSecond': sample.counters.tokensPerSecond,
      },
  ],
};

Map<String, Object?> _performanceCounters(PerformanceCounters counters) => {
  'samples': counters.sampleCount,
  'tokens': counters.completionTokens,
  'tokensPerSecond': counters.tokensPerSecond,
  'ttftSampleCount': counters.ttftSampleCount,
  'averageTtftMillis': counters.averageTtftMillis,
};

String? _endpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  return uri.replace(userInfo: '', query: '', fragment: '').toString();
}
