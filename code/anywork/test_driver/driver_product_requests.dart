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
import 'package:flutter/widgets.dart';

/// Explicit Driver actions and request-local product whitelists. No transport,
/// private SDK import, generic Client, registry or read-created domain owner.
final class DriverProductRequests {
  DriverProductRequests(this.graph);
  final AppGraph graph;
  Future<CommandResult<Unit>>? _fixtureAdmission;

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

String? _endpoint(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  return uri.replace(userInfo: '', query: '', fragment: '').toString();
}
