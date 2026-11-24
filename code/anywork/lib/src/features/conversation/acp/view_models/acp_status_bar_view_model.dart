import 'package:anywork_client/accounts.dart';
import 'package:anywork_client/acp_sessions.dart';
import 'package:anywork_client/models.dart'
    show AcpAgentBackendView, tokenThroughput;
import 'package:riverpod/riverpod.dart' show Provider, ProviderListenableSelect;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../presentation/providers/account_domains.dart';
import '../../../../presentation/providers/thread_directory_store.dart';
import '../state/acp_view_state.dart';
import 'acp_configuration_view_model.dart';
import 'acp_session_view_model.dart';
import 'acp_timeline_view_model.dart';

part 'acp_status_bar_view_model.g.dart';

String? _trimOrNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

(AcpStopReasonKind?, String?) _mapStopReason(AcpCompletedRunView? completed) {
  if (completed == null) return (null, null);
  final result = completed.result;
  if (result case AcpSuccessView<AcpPromptResponseView>(:final value)) {
    return (
      switch (value.stopReason) {
        AcpStopReasonView.endTurn => AcpStopReasonKind.endTurn,
        AcpStopReasonView.maxTokens => AcpStopReasonKind.maxTokens,
        AcpStopReasonView.maxTurnRequests => AcpStopReasonKind.maxTurnRequests,
        AcpStopReasonView.refusal => AcpStopReasonKind.refusal,
        AcpStopReasonView.cancelled => AcpStopReasonKind.cancelled,
      },
      null,
    );
  }
  return (null, null);
}

(AcpStopReasonKind?, String?) _mapStopReasonWithFallback(
  AcpCompletedRunView? completed,
  String? rawStopReason,
) {
  final mapped = _mapStopReason(completed);
  if (mapped.$1 != null || mapped.$2 != null) return mapped;
  final raw = _trimOrNull(rawStopReason);
  if (raw == null) return (null, null);
  return switch (raw) {
    'end_turn' || 'endTurn' => (AcpStopReasonKind.endTurn, null),
    'max_tokens' || 'maxTokens' => (AcpStopReasonKind.maxTokens, null),
    'max_turn_requests' ||
    'maxTurnRequests' => (AcpStopReasonKind.maxTurnRequests, null),
    'refusal' => (AcpStopReasonKind.refusal, null),
    'cancelled' => (AcpStopReasonKind.cancelled, null),
    _ => (AcpStopReasonKind.other, raw),
  };
}

List<AcpCapabilityKind> _mapCapabilities(AcpAgentCapabilitiesView? caps) {
  if (caps == null) return const [];
  return [
    if (caps.image) AcpCapabilityKind.image,
    if (caps.audio) AcpCapabilityKind.audio,
    if (caps.embeddedContext) AcpCapabilityKind.embeddedContext,
    if (caps.loadSession) AcpCapabilityKind.loadSession,
    if (caps.resumeSession) AcpCapabilityKind.resumeSession,
    if (caps.listSessions) AcpCapabilityKind.listSessions,
  ];
}

List<AcpConfigReadoutItem> _mapDetailConfigItems(AcpConversationState? state) {
  if (state == null) return const [];
  if (state.configOptions != null || state.modes != null) {
    final controls = mapAcpConfigControls(
      options: state.configOptions,
      modes: state.modes,
    );
    return [
      for (final control in controls.take(8))
        switch (control) {
          AcpSelectConfigControl(:final name, :final currentLabel) =>
            AcpConfigReadoutItem(label: name, value: currentLabel),
          AcpBooleanConfigControl(:final name, :final currentValue) =>
            AcpConfigReadoutItem(
              label: name,
              value: '',
              booleanValue: currentValue,
            ),
          AcpLegacyModeConfigControl(:final currentModeLabel) =>
            AcpConfigReadoutItem(
              label: '',
              value: currentModeLabel,
              useModeFallbackLabel: true,
            ),
        },
    ];
  }
  return [
    for (final item in state.snapshotConfig.take(8))
      AcpConfigReadoutItem(
        label: item.name,
        value: item.valueLabel,
        booleanValue: item.valueId == 'true'
            ? true
            : item.valueId == 'false'
            ? false
            : null,
        useModeFallbackLabel: item.id == 'mode' && item.name == 'Mode',
      ),
  ];
}

@riverpod
AcpStatusBarViewState acpStatusBarViewModel(Ref ref, String threadId) {
  final selected = ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      return (
        loading: asyncState.isLoading || state?.openPending == true,
        ready: state?.ready ?? false,
        disconnected: state?.disconnected ?? false,
        ended: state?.observationEnded ?? false,
        isRunning: state?.activeRun != null,
        stopReason: _mapStopReason(state?.lastCompleted),
        history: state?.history,
      );
    }),
  );

  final (stopReason, stopReasonRaw) = selected.stopReason;
  final phase = selected.disconnected
      ? AcpSessionStatusPhase.disconnected
      : selected.ended
      ? AcpSessionStatusPhase.ended
      : selected.loading || !selected.ready
      ? AcpSessionStatusPhase.connecting
      : selected.isRunning
      ? AcpSessionStatusPhase.running
      : stopReason != null
      ? AcpSessionStatusPhase.completed
      : AcpSessionStatusPhase.ready;

  return AcpStatusBarViewState(
    phase: phase,
    stopReason: stopReason,
    stopReasonRaw: stopReasonRaw,
    provenance: mapAcpHistoryOrigin(selected.history),
  );
}

@riverpod
AcpContextUsageViewState? acpContextUsageViewModel(Ref ref, String threadId) {
  return ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      if (state == null) return null;
      final usage = state.latestUsage;
      return (
        used: usage?.used,
        size: usage != null && usage.size > BigInt.zero ? usage.size : null,
        isLive: state.metricsLive,
      );
    }),
  );
}

@riverpod
AcpCostViewState? acpCostViewModel(Ref ref, String threadId) {
  return ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      return state?.latestCost ?? state?.latestUsage?.cost;
    }),
  );
}

/// Readout-only projection. Equal rates do not invalidate the speed widget.
final acpThroughputViewModelProvider = Provider.autoDispose
    .family<double?, String>((ref, threadId) {
      return ref.watch(
        acpConversationStateProvider(threadId).select((asyncState) {
          final sample = asyncState.value?.textPerformance;
          return tokenThroughput(
            sample?.estimatedOutputTokens,
            sample?.responseMillis,
          );
        }),
      );
    });

@riverpod
AcpContextDetailViewState acpContextDetailViewModel(Ref ref, String threadId) {
  final selected = ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      final usage = state?.latestUsage;
      return (
        used: usage?.used,
        size: usage != null && usage.size > BigInt.zero ? usage.size : null,
        previousUsed: state?.previousContextUsed,
        isLive: state?.metricsLive ?? false,
        updatedAt: state?.usageUpdatedAt,
      );
    }),
  );
  return AcpContextDetailViewState(
    used: selected.used,
    size: selected.size,
    previousUsed: selected.previousUsed,
    isLive: selected.isLive,
    updatedAt: selected.updatedAt,
  );
}

@riverpod
AcpThroughputDetailViewState acpThroughputDetailViewModel(
  Ref ref,
  String threadId,
) {
  final selected = ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      return (
        sample: state?.textPerformance,
        isLive: state?.metricsLive ?? false,
        updatedAt: state?.textPerformanceUpdatedAt,
      );
    }),
  );
  final sample = selected.sample;
  return AcpThroughputDetailViewState(
    tokensPerSecond: tokenThroughput(
      sample?.estimatedOutputTokens,
      sample?.responseMillis,
    ),
    estimatedOutputTokens: sample?.estimatedOutputTokens,
    responseMillis: sample?.responseMillis,
    isLive: selected.isLive,
    updatedAt: selected.updatedAt,
  );
}

@riverpod
AcpCostDetailViewState? acpCostDetailViewModel(Ref ref, String threadId) {
  final selected = ref.watch(
    acpConversationStateProvider(threadId).select((asyncState) {
      final state = asyncState.value;
      final cost = state?.latestCost ?? state?.latestUsage?.cost;
      return (
        cost: cost,
        isLive: state?.metricsLive ?? false,
        updatedAt: state?.costUpdatedAt,
      );
    }),
  );
  final cost = selected.cost;
  if (cost == null) return null;
  return AcpCostDetailViewState(
    amount: cost.amount,
    currency: cost.currency,
    isLive: selected.isLive,
    updatedAt: selected.updatedAt,
  );
}

@riverpod
AcpSessionDetailViewState acpSessionDetailViewModel(Ref ref, String threadId) {
  final state = ref.watch(acpConversationStateProvider(threadId)).value;
  final statusBar = ref.watch(acpStatusBarViewModelProvider(threadId));
  final backend = ref.watch(
    threadMetadataStoreProvider(threadId).select((s) => s.frame?.row?.backend),
  );
  final accounts = ref.watch(accountsStateProvider.select((s) => s.accounts));

  String? accountId;
  String? referenceSessionId;
  if (backend case AcpAgentBackendView(:final reference)) {
    accountId = reference.accountId;
    referenceSessionId = _trimOrNull(reference.acpSessionId);
  }

  String? serviceName;
  if (accountId != null) {
    for (final account in accounts) {
      if (account.identity case AcpAccountIdentity(accountId: final id)
          when id == accountId) {
        serviceName = _trimOrNull(account.name);
        break;
      }
    }
  }

  final server = state?.serverInfo;
  final serverName = _trimOrNull(server?.title) ?? _trimOrNull(server?.name);
  final serverVersion = _trimOrNull(server?.version);
  final (lastStopReason, lastStopReasonRaw) = _mapStopReasonWithFallback(
    state?.lastCompleted,
    state?.lastStopReasonRaw,
  );

  return AcpSessionDetailViewState(
    phase: statusBar.phase,
    isLive: state?.metricsLive ?? false,
    serviceName: serviceName,
    serverName: serverName,
    serverVersion: serverVersion,
    remoteSessionId:
        _trimOrNull(state?.remoteSessionId?.value) ?? referenceSessionId,
    lastStopReason: lastStopReason,
    lastStopReasonRaw: lastStopReasonRaw,
    completedTurns: state?.completedTurns,
    updatedAt: state?.snapshotUpdatedAt,
    configItems: _mapDetailConfigItems(state),
    capabilities: _mapCapabilities(state?.capabilities),
  );
}
