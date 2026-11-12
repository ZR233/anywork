import 'dart:async';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../presentation/providers/client_provider.dart';
import '../../presentation/providers/account_domains.dart';
import '../../presentation/providers/mcp_store.dart';
import '../../presentation/providers/observe_client.dart';
import '../../presentation/providers/thread_directory_store.dart';
import '../../presentation/providers/thread_session_store.dart';
import '../../presentation/providers/settings_store.dart';

import 'package:anywork_client/studio_client.dart';

import '../../domain/models/studio_models.dart';
import 'started_items_state.dart';

part 'status_view.g.dart';

const statusEmptyRuntime = ThreadRuntimeView(
  modelId: '',
  contextTokens: 0,
  contextWindow: 0,
  totalTokens: 0,
  costLabel: '',
  activeSkills: [],
  activeMcpServers: [],
  activeLspServers: [],
);

/// A display observation only: Client remains the sole owner of topic streams.
@riverpod
class StartedItemsViewModel extends _$StartedItemsViewModel {
  final _pending = <String>{};
  final _errors = <String, String>{};
  void Function()? _closeRetention;
  bool _refreshScheduled = false;

  @override
  FutureOr<StartedItemsState> build(String threadId) {
    // Listen without invalidating this command owner. A canonical provider may
    // rebuild while an operation is pending and the menu has no listeners.
    ref.listen(threadSessionStoreProvider(threadId), (previous, next) {
      if (!_sameStrings(
        previous?.runtime?.activeSkills ?? const [],
        next.runtime?.activeSkills ?? const [],
      )) {
        _scheduleRefresh();
      }
    });
    ref.listen(threadMcpProvider(threadId), (_, _) => _scheduleRefresh());
    return _project();
  }

  void refreshObservedLsp() => _scheduleRefresh();

  void _scheduleRefresh() {
    if (_refreshScheduled) return;
    _refreshScheduled = true;
    // A paused canonical provider may flush while the menu is mounting.
    // Publish after that build, coalescing only notifications from this turn.
    scheduleMicrotask(() {
      _refreshScheduled = false;
      _refresh();
    });
  }

  void _refresh() {
    if (!ref.mounted) return;
    try {
      state = AsyncData(_project());
    } catch (error, stack) {
      state = AsyncError(error, stack);
    }
  }

  StartedItemsState _project() {
    final skills = ref
        .read(threadSessionStoreProvider(threadId))
        .runtime
        ?.activeSkills;
    final mcp = ref.read(threadMcpProvider(threadId));
    final lspState = ref
        .read(anyworkClientProvider)
        .existingThreadLsp(threadId)
        ?.state;
    final lspSnapshot = lspState?.value;
    final bindingId = lspSnapshot?.bindingId;
    final lspErrors = <String, String>{
      for (final entry in _errors.entries)
        if (entry.key.startsWith('lsp:$bindingId:'))
          'lsp:${entry.key.substring('lsp:$bindingId:'.length)}': entry.value,
    };
    final lspPending = <String>{
      for (final key in _pending)
        if (key.startsWith('lsp:$bindingId:'))
          'lsp:${key.substring('lsp:$bindingId:'.length)}',
    };
    return StartedItemsState(
      skills: skills ?? const [],
      mcp: [
        for (final server
            in mcp.value?.servers ?? const <ThreadMcpServerState>[])
          StartedService(
            id: server.id,
            name: server.id,
            status: switch (server.lifecycle) {
              ThreadMcpLifecycleKind.available => StartedServiceStatus.ready,
              ThreadMcpLifecycleKind.connecting =>
                StartedServiceStatus.connecting,
              ThreadMcpLifecycleKind.shuttingDown =>
                StartedServiceStatus.stopping,
              ThreadMcpLifecycleKind.unavailable => StartedServiceStatus.failed,
              ThreadMcpLifecycleKind.unsupported =>
                StartedServiceStatus.unsupported,
            },
            diagnostic: server.message,
          ),
      ],
      lsp: [
        for (final server
            in lspSnapshot?.servers ?? const <LspServerStateView>[])
          _lspService(server),
      ],
      mcpSync: mcp.sync,
      lspSync: lspState?.sync ?? const DomainSyncStatus(),
      pending: Set.unmodifiable({
        ..._pending.where((key) => !key.startsWith('lsp:')),
        ...lspPending,
      }),
      errors: Map.unmodifiable({
        for (final entry in _errors.entries)
          if (!entry.key.startsWith('lsp:')) entry.key: entry.value,
        ...lspErrors,
      }),
    );
  }

  Future<void> reconnectMcp([String? serverId]) =>
      _run(serverId == null ? 'mcp' : 'mcp:$serverId', () async {
        await ref
            .read(anyworkClientProvider)
            .directoryCommands
            .reconnectThreadMcp(threadId: threadId, serverId: serverId);
      });

  Future<void> reconnectLsp(String serverId) {
    final client = ref.read(anyworkClientProvider);
    final snapshot = client.existingThreadLsp(threadId)?.state.value;
    final bindingId = snapshot?.bindingId;
    if (bindingId == null)
      return Future.error(StateError('No active LSP binding'));
    return _run('lsp:$bindingId:$serverId', () async {
      await client.directoryCommands.resetThreadLspServer(
        threadId: threadId,
        bindingId: bindingId,
        serverId: serverId,
      );
    });
  }

  Future<void> compact() => _run(
    'compact',
    () =>
        ref.read(anyworkClientProvider).threadCommands.compactThread(threadId),
  );

  Future<void> _run(String key, Future<void> Function() command) async {
    if (!_pending.add(key)) return;
    // Keep presentation of an admitted command alive until its real completion.
    // Closing the popover never cancels Client's command or shared resources.
    _closeRetention ??= ref.keepAlive().close;
    _errors.remove(key);
    _publishCommands();
    try {
      await command();
    } catch (error) {
      _errors[key] = error.toString();
    } finally {
      _pending.remove(key);
      if (ref.mounted) _publishCommands();
      if (_pending.isEmpty) {
        _closeRetention?.call();
        _closeRetention = null;
      }
    }
  }

  void _publishCommands() {
    _refresh();
  }
}

StartedService _lspService(LspServerStateView server) {
  final state = server.state;
  final activity = state is LspAvailableState ? state.activity : null;
  return StartedService(
    id: server.id,
    name: server.displayName,
    status: switch (state) {
      LspCheckingState() => switch (server.phase) {
        'initializing' => StartedServiceStatus.initializing,
        'starting' => StartedServiceStatus.starting,
        'loading' => StartedServiceStatus.loading,
        'probing' => StartedServiceStatus.probing,
        _ => StartedServiceStatus.checking,
      },
      LspDisabledState() => StartedServiceStatus.disabled,
      LspUnavailableState() => StartedServiceStatus.failed,
      LspAvailableState(activity: LspIdleActivity()) =>
        StartedServiceStatus.ready,
      LspAvailableState(activity: LspIndexingActivity()) =>
        StartedServiceStatus.indexing,
      LspAvailableState(activity: LspBusyActivity()) =>
        StartedServiceStatus.busy,
    },
    percentage: switch (activity) {
      LspIndexingActivity(:final percentage) ||
      LspBusyActivity(:final percentage) => percentage,
      _ => null,
    },
    diagnostic: switch (state) {
      LspCheckingState(:final message) ||
      LspDisabledState(:final message) ||
      LspUnavailableState(:final message) => message,
      LspAvailableState() => switch (activity) {
        LspIndexingActivity(:final title, :final message) ||
        LspBusyActivity(
          :final title,
          :final message,
        ) => [?title, ?message].join('\n'),
        _ => null,
      },
    },
    canReconnect: state is! LspDisabledState,
  );
}

/// Stable status-bar fields for one Thread. Throughput and context are not
/// part of this value, so response-timing updates cannot rebuild the chrome.
@riverpod
StatusBarView? statusBarView(Ref ref, String threadId) {
  final row = _threadIdentity(ref, threadId);
  if (row == null) return null;
  final accounts = ref.watch(modelSelectionAccountsProvider);
  final roles = ref.watch(settingsStoreProvider).canonical?.roles;
  final chrome =
      _observeSession(
        ref,
        threadId,
        _chromeFromSession,
        equals: _chromeEquals,
      ) ??
      (isBusy: false, modelRoute: null, workflowRun: null);
  return StatusBarView(
    row: row,
    accounts: accounts,
    roles: roles ?? const [],
    isBusy: chrome.isBusy,
    modelRoute: chrome.modelRoute,
    workflowRun: chrome.workflowRun,
  );
}

@riverpod
StudioContextProjection? statusContextProjection(Ref ref, String threadId) {
  final accounts = ref.watch(modelSelectionAccountsProvider);
  return _observeSession(
    ref,
    threadId,
    (session) => StudioContextProjection.fromRuntime(
      threadId,
      session.runtime ?? statusEmptyRuntime,
      modelRoute: session.modelRoute,
      accounts: accounts,
      isBusy: session.activeTurn?.state.isBusy ?? false,
    ),
  );
}

@riverpod
StudioThroughputProjection? statusThroughputProjection(
  Ref ref,
  String threadId,
) {
  return _observeSession(ref, threadId, (session) {
    final runtime = session.runtime ?? statusEmptyRuntime;
    final source = ModelRouteQueries.throughputSource(runtime);
    return StudioThroughputProjection(
      threadId: threadId,
      completionTokens: source?.outputTokens ?? 0,
      responseMillis: source?.responseMillis ?? 0,
    );
  });
}

typedef _StatusChrome = ({
  bool isBusy,
  ThreadModelRouteView? modelRoute,
  WorkflowRunView? workflowRun,
});

_StatusChrome _chromeFromSession(ThreadSessionState session) {
  final runtime = session.runtime ?? statusEmptyRuntime;
  return (
    isBusy: session.activeTurn?.state.isBusy ?? false,
    modelRoute: session.modelRoute,
    workflowRun: runtime.workflow?.currentRun,
  );
}

bool _chromeEquals(_StatusChrome left, _StatusChrome right) {
  return left.isBusy == right.isBusy &&
      left.modelRoute == right.modelRoute &&
      left.workflowRun == right.workflowRun;
}

bool _sameStrings(List<String> left, List<String> right) {
  if (identical(left, right)) return true;
  if (left.length != right.length) return false;
  for (var index = 0; index < left.length; index++) {
    if (left[index] != right[index]) return false;
  }
  return true;
}

T? _observeSession<T>(
  Ref ref,
  String threadId,
  T Function(ThreadSessionState session) project, {
  bool Function(T left, T right)? equals,
}) {
  final owner = ref
      .read(anyworkClientProvider)
      .conversations
      .existingSession(threadId);
  if (owner == null) {
    observeClientDemand(
      ref,
      ownsFailure: (owner) => owner == 'session:$threadId',
    );
    return null;
  }
  late final T current;
  current = project(
    observeClient(ref, owner.source, (next) {
      final projected = project(next);
      final unchanged = equals == null
          ? projected == current
          : equals(projected, current);
      if (!unchanged) ref.invalidateSelf();
    }),
  );
  return current;
}

SessionDirectoryRow? _threadIdentity(Ref ref, String threadId) {
  return ref.watch(threadMetadataStoreProvider(threadId)).frame?.row;
}
