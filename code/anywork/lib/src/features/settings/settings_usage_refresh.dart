import '../../domain/models/studio_models.dart';

/// 用量刷新按钮的 widget 临时态。
///
/// canonical 用量只来自 [ProviderUsageView]；这里只记本次刷新的 loading / error。
/// store revision 或单条 Ready 用量 revision 前进后，旧 error 不再显示。
class SettingsUsageRefreshError {
  const SettingsUsageRefreshError({
    required this.message,
    required this.requestGeneration,
    required this.baselineRevision,
    required this.baselineRevisions,
  });

  final String message;
  final int requestGeneration;
  final int baselineRevision;
  final Map<String, int> baselineRevisions;

  bool appliesTo(String providerId) =>
      baselineRevisions.containsKey(providerId);

  bool isObsoleteFor(
    String providerId,
    ProviderUsageView? usage,
    int storeRevision,
  ) {
    if (storeRevision > baselineRevision) return true;
    if (usage == null || usage.state is! ReadyProviderUsageView) {
      return false;
    }
    final baseline = baselineRevisions[providerId];
    return baseline == null || usage.revision > baseline;
  }
}

class SettingsUsageRefreshState {
  const SettingsUsageRefreshState({
    this.loadingGenerationByProviderId = const {},
    this.latestRequestGenerationByProviderId = const {},
    this.errorsByProviderId = const {},
  });

  final Map<String, int> loadingGenerationByProviderId;
  final Map<String, int> latestRequestGenerationByProviderId;
  final Map<String, SettingsUsageRefreshError> errorsByProviderId;

  Set<String> get loadingProviderIds =>
      loadingGenerationByProviderId.keys.toSet();

  Map<String, String> visibleErrorsByProviderId({
    required Iterable<String> providerIds,
    required Iterable<ProviderUsageView> canonicalUsages,
    required int storeRevision,
  }) {
    final usageByProviderId = {
      for (final usage in canonicalUsages) usage.providerId: usage,
    };
    final visible = <String, String>{};
    for (final providerId in providerIds) {
      final latestRequest = latestRequestGenerationByProviderId[providerId];
      final candidate =
          [errorsByProviderId[providerId], errorsByProviderId['*']]
              .whereType<SettingsUsageRefreshError>()
              .where((error) {
                return error.appliesTo(providerId) &&
                    (latestRequest == null ||
                        error.requestGeneration >= latestRequest);
              })
              .fold<SettingsUsageRefreshError?>(null, (current, error) {
                if (current == null ||
                    error.requestGeneration > current.requestGeneration) {
                  return error;
                }
                return current;
              });
      if (candidate != null &&
          !candidate.isObsoleteFor(
            providerId,
            usageByProviderId[providerId],
            storeRevision,
          )) {
        visible[providerId] = candidate.message;
      }
    }
    return visible;
  }
}

class SettingsUsageRefresh {
  Future<void> _refreshTail = Future<void>.value();
  int _nextRequestGeneration = 0;
  SettingsUsageRefreshState state = const SettingsUsageRefreshState();

  Future<void> refresh({
    String? providerId,
    required Set<String> providerIds,
    required int Function() readStoreRevision,
    required Map<String, int> Function() readUsageRevisions,
    required Future<void> Function() refreshCanonical,
    required void Function() onChanged,
  }) {
    final requestGeneration = ++_nextRequestGeneration;
    _markRefreshStarted(
      providerId: providerId,
      providerIds: providerIds,
      requestGeneration: requestGeneration,
    );
    onChanged();
    final operation = _refreshTail.then<void>(
      (_) => _runRefresh(
        providerId: providerId,
        providerIds: providerIds,
        requestGeneration: requestGeneration,
        readStoreRevision: readStoreRevision,
        readUsageRevisions: readUsageRevisions,
        refreshCanonical: refreshCanonical,
        onChanged: onChanged,
      ),
    );
    _refreshTail = operation.catchError((Object _, StackTrace _) {
      // Keep the serial queue usable; the original operation is returned to its
      // caller and _runRefresh records the visible error for this generation.
    });
    return operation;
  }

  void _markRefreshStarted({
    required String? providerId,
    required Set<String> providerIds,
    required int requestGeneration,
  }) {
    final current = state;
    final loading = {...current.loadingGenerationByProviderId};
    final latestRequests = {...current.latestRequestGenerationByProviderId};
    for (final id in providerIds) {
      loading[id] = requestGeneration;
      latestRequests[id] = requestGeneration;
    }
    final errors = {...current.errorsByProviderId};
    errors.remove(providerId ?? '*');
    state = SettingsUsageRefreshState(
      loadingGenerationByProviderId: loading,
      latestRequestGenerationByProviderId: latestRequests,
      errorsByProviderId: errors,
    );
  }

  Future<void> _runRefresh({
    required String? providerId,
    required Set<String> providerIds,
    required int requestGeneration,
    required int Function() readStoreRevision,
    required Map<String, int> Function() readUsageRevisions,
    required Future<void> Function() refreshCanonical,
    required void Function() onChanged,
  }) async {
    final baselineRevision = readStoreRevision();
    final baselineRevisions = readUsageRevisions();
    try {
      await refreshCanonical();
      _finishRefresh(
        providerId: providerId,
        providerIds: providerIds,
        requestGeneration: requestGeneration,
      );
    } catch (error) {
      _recordRefreshFailure(
        providerId: providerId,
        providerIds: providerIds,
        baselineRevision: baselineRevision,
        baselineRevisions: baselineRevisions,
        requestGeneration: requestGeneration,
        message: error.toString(),
      );
    }
    onChanged();
  }

  void _finishRefresh({
    required String? providerId,
    required Set<String> providerIds,
    required int requestGeneration,
  }) {
    final current = state;
    final loading = {...current.loadingGenerationByProviderId};
    for (final id in providerIds) {
      if (loading[id] == requestGeneration) loading.remove(id);
    }
    final errors = {...current.errorsByProviderId};
    final errorKey = providerId ?? '*';
    if (errors[errorKey]?.requestGeneration == requestGeneration) {
      errors.remove(errorKey);
    }
    state = SettingsUsageRefreshState(
      loadingGenerationByProviderId: loading,
      latestRequestGenerationByProviderId:
          current.latestRequestGenerationByProviderId,
      errorsByProviderId: errors,
    );
  }

  void _recordRefreshFailure({
    required String? providerId,
    required Set<String> providerIds,
    required int baselineRevision,
    required Map<String, int> baselineRevisions,
    required int requestGeneration,
    required String message,
  }) {
    final current = state;
    final reportableProviderIds = providerIds
        .where(
          (id) =>
              current.latestRequestGenerationByProviderId[id] ==
              requestGeneration,
        )
        .toSet();
    final loading = {...current.loadingGenerationByProviderId};
    for (final id in providerIds) {
      if (loading[id] == requestGeneration) loading.remove(id);
    }
    final errors = {...current.errorsByProviderId};
    final errorKey = providerId ?? '*';
    if (reportableProviderIds.isEmpty) {
      if (errors[errorKey]?.requestGeneration == requestGeneration) {
        errors.remove(errorKey);
      }
    } else {
      errors[errorKey] = SettingsUsageRefreshError(
        message: message,
        requestGeneration: requestGeneration,
        baselineRevision: baselineRevision,
        baselineRevisions: {
          for (final id in reportableProviderIds) id: baselineRevisions[id]!,
        },
      );
    }
    state = SettingsUsageRefreshState(
      loadingGenerationByProviderId: loading,
      latestRequestGenerationByProviderId:
          current.latestRequestGenerationByProviderId,
      errorsByProviderId: errors,
    );
  }
}
