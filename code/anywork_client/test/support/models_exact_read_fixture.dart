import 'dart:async';

import 'package:anywork_client/configuration_ports.dart';
import 'package:anywork_client/models_ports.dart';
import 'package:anywork_client/resources_ports.dart';

const exactModelTarget = DelegationModelReadTarget(
  sources: ConfigurationRoleReadTarget(
    reference: ConfigurationRoleReadRef(entry: 71, revision: 9),
    configuration: ConfigurationReadTarget(
      origin: ProductReadOrigin(ownerEpoch: 'exact-settings', incarnation: 2),
      reference: ConfigurationReadRef(entry: 3, revision: 6),
    ),
    catalog: ModelCatalogReadTarget(
      origin: ProductReadOrigin(ownerEpoch: 'exact-catalog', incarnation: 4),
      reference: ModelCatalogReadRef(entry: 11, revision: 8),
    ),
    stamp: ConfigProjectionStamp(
      settingsRevision: 30,
      modelCatalogRevision: 40,
      closing: false,
    ),
  ),
  model: AccountModelKey(accountId: 'exact-account', modelId: 'exact-model'),
);

const exactRawScopeId = 'original-exact-scope';
const exactModelIdentity = ProductReadScopeIdentity(
  scopeId: exactRawScopeId,
  ownerEpoch: 'exact-catalog',
  incarnation: 4,
  version: ProductReadVersion.value(entry: 11, revision: 8),
);

const exactMetadataFailure = StudioFailure(
  code: StudioFailureCode.protocol,
  message: 'The native full scope descriptor cannot be converted without loss.',
  retryable: false,
  correlationId: 'exact-descriptor-conversion',
);
const exactScopeClosed = StudioFailure(
  code: StudioFailureCode.cancelled,
  message: 'The original native exact scope no longer admits metadata queries.',
  retryable: false,
  correlationId: 'exact-scope-closed',
);

const exactModelHeader = DelegationModelReadHeader(
  scope: exactModelIdentity,
  target: exactModelTarget,
  accountName: ReadText.inline(text: 'Original exact account'),
  descriptor: ModelDescriptorRead(
    modelId: ReadText.inline(text: 'exact-model'),
    enabled: true,
    typeSupport: TypedListRef(listId: 1, total: 0),
    origin: ModelOrigin.manual,
    displayName: ReadText.inline(text: 'Typed exact model'),
    description: null,
    contextWindow: 4096,
    maxContextWindow: 4096,
    maxOutputTokens: 1024,
    context: ModelContextResolutionRead(
      unavailable: null,
      contextWindow: 4096,
      inputTokenLimit: 3072,
      autoCompactLimit: 2048,
      adjustment: null,
    ),
    transport: ModelTransportDescriptorRead(
      protocol: ReadText.inline(text: 'openai'),
      connectionModes: TypedListRef(listId: 2, total: 0),
      defaultConnectionMode: ReadText.inline(text: 'http'),
    ),
    capabilities: ModelCapabilitiesRead(
      input: TypedListRef(listId: 3, total: 0),
      output: TypedListRef(listId: 4, total: 0),
      streaming: true,
      temperature: false,
      reasoning: false,
      webSearch: false,
      functionCalling: false,
      parallelToolCalls: false,
      customTools: false,
      freeformTools: false,
      instructionSnapshotOverrides: false,
      nativeContextFamily: null,
    ),
    reasoning: null,
    pricing: null,
  ),
  available: true,
  unavailableReason: null,
  billingKind: BillingKind.subscription,
  guide: null,
  performance: LocalModelPerformanceSummary(
    sampleCount: 7,
    tokensPerSecond: 12.5,
    averageTtftMillis: 250,
    ttftSampleCount: 5,
    updatedAt: 100,
  ),
  evaluations: AgentEvaluationSummary(
    window: 10,
    ratedSamples: 0,
    passed: 0,
    failed: 0,
    notRated: 0,
    averageQuality: null,
    averageInstructionFollowing: null,
  ),
  recentEvaluations: TypedListRef(listId: 5, total: 0),
);

final class ExactModelOpen {
  ExactModelOpen(this.target);
  final DelegationModelReadTarget target;
  final reply = Completer<DelegationModelReadConnection>();
}

/// Only a native open reply. No catalog, selection, read owner or cleanup
/// algorithm is substituted for the public ModelsRepository under test.
final class ExactModelsPort implements ModelsPort {
  final opens = <ExactModelOpen>[];
  final firstOpen = Completer<ExactModelOpen>();
  final _openWaiters = <int, Completer<ExactModelOpen>>{};

  /// Every original native open in order, so a test can drive the second and
  /// later windows of the same target without assuming call order.
  Future<ExactModelOpen> openAt(int index) => index < opens.length
      ? Future.value(opens[index])
      : _openWaiters.putIfAbsent(index, Completer<ExactModelOpen>.new).future;

  @override
  Future<DelegationModelReadConnection> openDelegationModelRead(
    DelegationModelReadTarget target,
  ) {
    final call = ExactModelOpen(target);
    final index = opens.length;
    opens.add(call);
    _openWaiters.remove(index)?.complete(call);
    if (!firstOpen.isCompleted) firstOpen.complete(call);
    return call.reply.future;
  }

  void refusePendingOpensForTeardown() {
    for (final call in opens) {
      if (!call.reply.isCompleted) call.reply.completeError(exactScopeClosed);
    }
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected exact Models capability: ${invocation.memberName}',
  );
}

final class ExactModelNativeClose {
  ExactModelNativeClose(this.scope, {required this.retry});
  final ExactModelScope scope;
  final bool retry;
  final reply = Completer<FeedCloseReport>();

  void completeClean() => reply.complete(
    FeedCloseReport(
      feedId: exactRawScopeId,
      outcome: const FeedCloseOutcome.clean(),
    ),
  );
}

/// A fixed native material with metadata admission separate from the original
/// raw handle identity. Each native close/retry has its own response barrier;
/// it never releases a ResourceBudget permit or decides a Repository report.
final class ExactModelScope implements DelegationModelReadConnection {
  ExactModelScope({this.metadataFailure});
  final StudioFailure? metadataFailure;
  final identityEntered = Completer<void>();
  final headerEntered = Completer<void>();
  final headerReply = Completer<DelegationModelReadHeader>();
  final closes = <ExactModelNativeClose>[];
  final _closeWaiters = <int, Completer<ExactModelNativeClose>>{};
  bool closing = false;
  bool disposed = false;
  bool _teardownResponses = false;

  void _admitMetadata() {
    if (closing || disposed) throw exactScopeClosed;
    if (metadataFailure case final failure?) throw failure;
  }

  @override
  String get scopeId => exactRawScopeId; // Independent of full descriptor/report.

  @override
  ProductReadScopeIdentity get identity {
    if (!identityEntered.isCompleted) identityEntered.complete();
    _admitMetadata();
    return exactModelIdentity;
  }

  @override
  DelegationModelReadTarget get target {
    _admitMetadata();
    return exactModelTarget;
  }

  @override
  Future<DelegationModelReadHeader> header() {
    _admitMetadata();
    if (!headerEntered.isCompleted) headerEntered.complete();
    if (_teardownResponses && !headerReply.isCompleted)
      headerReply.complete(exactModelHeader);
    return headerReply.future;
  }

  Future<ExactModelNativeClose> closed(int index) => index < closes.length
      ? Future.value(closes[index])
      : _closeWaiters
            .putIfAbsent(index, Completer<ExactModelNativeClose>.new)
            .future;

  @override
  void requestClose() => closing = true;

  @override
  Future<FeedCloseReport> close() => _close(retry: false);

  @override
  Future<FeedCloseReport> retryClose() => _close(retry: true);

  Future<FeedCloseReport> _close({required bool retry}) async {
    closing = true;
    final call = ExactModelNativeClose(this, retry: retry);
    closes.add(call);
    _closeWaiters.remove(closes.length - 1)?.complete(call);
    if (_teardownResponses) call.completeClean();
    final report = await call.reply.future;
    if (report.outcome is CleanFeedCloseOutcome) disposed = true;
    return report;
  }

  /// Failure-safe environment drain only. Test-body oracles explicitly answer
  /// every close before this is enabled; teardown still requires real SDK Clean
  /// and zero budget, never accepts an arbitrary Unresolved report as success.
  void releaseResponsesForTeardown() {
    _teardownResponses = true;
    if (headerEntered.isCompleted && !headerReply.isCompleted)
      headerReply.complete(exactModelHeader);
    for (final call in closes) {
      if (!call.reply.isCompleted) call.completeClean();
    }
  }

  @override
  Never noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected exact model body read: ${invocation.memberName}',
  );
}
