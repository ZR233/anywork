import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../domain/models/studio_models.dart';

/// App-level ordering for settings reads and writes.
///
/// A route can be popped while an operation is in flight. The lane is owned by
/// the controller, so route disposal cannot cancel or reorder a write accepted
/// by the UI, and a canonical read can be placed after all accepted writes.
final class SettingsOperationCoordinator {
  Future<void> _tail = Future<void>.value();

  Future<T> enqueue<T>(Future<T> Function() operation) {
    final task = _tail.then((_) => operation());
    // The tail is deliberately failure-free. A rejected command is returned to
    // its caller, while later commands remain executable.
    _tail = task.then<void>((_) {}, onError: (_) {});
    return task;
  }

  Future<bool> waitForIdle({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    try {
      await _tail.timeout(timeout);
      return true;
    } on TimeoutException {
      return false;
    }
  }
}

/// Structured merge telemetry exposed to the driver and debug logs.  It does
/// not contain credentials, prompts, or model content.
final class SettingsMergeDiagnostic {
  const SettingsMergeDiagnostic({
    required this.domain,
    required this.source,
    required this.currentRevision,
    required this.incomingRevision,
    required this.applied,
    required this.reason,
    this.operationId,
    this.pendingCount = 0,
  });

  final String domain;
  final String source;
  final int currentRevision;
  final int incomingRevision;
  final bool applied;
  final String reason;
  final String? operationId;
  final int pendingCount;

  Map<String, Object?> toJson() => {
    'domain': domain,
    'source': source,
    'currentRevision': currentRevision,
    'incomingRevision': incomingRevision,
    'applied': applied,
    'reason': reason,
    if (operationId != null) 'operationId': operationId,
    'pendingCount': pendingCount,
  };
}

/// 唯一一份 settings 合并实现：配置资源与模型目录资源各自按自己的水位前进。
///
/// Bridge 的直接响应会同时返回两个资源，topic 事件分别只携带一个资源；因此消费者必须
/// 分别比较：配置水位前进时只替换配置字段，目录水位前进时只替换 provider 的模型与目录
/// 状态。同一水位幂等丢弃，较低水位不得覆盖较新事实，任一资源缺失时不做半份合并。
///
/// repository（直接响应/全量 snapshot）、topic reducer 与 FRB 转换器都调用这一个函数，
/// 不存在第二套合并算法或第二份时钟。
SettingsStateSnapshot? mergeCanonicalSettingsSnapshots(
  SettingsStateSnapshot previous,
  SettingsStateSnapshot next, {
  bool mergeConfig = true,
  bool mergeCatalog = true,
}) {
  if (next.state.value == null || previous.state.value == null) return null;
  final nextConfigIsNewer = mergeConfig && next.revision > previous.revision;
  final nextCatalogIsNewer =
      mergeCatalog && next.modelCatalogRevision > previous.modelCatalogRevision;
  if (!nextConfigIsNewer && !nextCatalogIsNewer) {
    debugPrint(
      'settings_merge_dropped reason=stale-or-idempotent '
      'config=${next.revision}/${previous.revision} '
      'catalog=${next.modelCatalogRevision}/${previous.modelCatalogRevision}',
    );
    return null;
  }

  final previousData = previous.state.value!;
  final nextData = next.state.value!;
  final configData = nextConfigIsNewer ? nextData : previousData;
  final catalogData = nextCatalogIsNewer ? nextData : previousData;
  final catalogByProvider = {
    for (final provider in catalogData.providers) provider.id: provider,
  };
  final providers = [
    for (final provider in configData.providers)
      if (catalogByProvider[provider.id] case final catalogProvider?)
        provider.copyWith(
          models: catalogProvider.models,
          modelCatalog: catalogProvider.modelCatalog,
        )
      else
        provider,
  ];

  return SettingsStateSnapshot(
    providers: providers,
    defaultProviderId: configData.defaultProviderId,
    modeModelRoutes: configData.modeModelRoutes,
    roles: configData.roles,
    mcpServers: configData.mcpServers,
    instructions: configData.instructions,
    skills: configData.skills,
    general: configData.general,
    webSearch: configData.webSearch,
    deepSeekWebSearch: configData.deepSeekWebSearch,
    permissionMode: configData.permissionMode,
    revision: nextConfigIsNewer ? next.revision : previous.revision,
    modelCatalogRevision: nextCatalogIsNewer
        ? next.modelCatalogRevision
        : previous.modelCatalogRevision,
  );
}

/// App-level owner for the adopted settings projection.
///
/// It keeps exactly one clock fact — the last adopted canonical projection — and
/// delegates every merge decision to [mergeCanonicalSettingsSnapshots]. Direct
/// responses, topic frames and full snapshots all enter that same path, so a
/// lower revision from any transport is ignored without touching the other
/// resource, and no transport owns a second copy of the algorithm.
final class StudioSettingsRepository {
  SettingsStateSnapshot? _canonical;
  SettingsMergeDiagnostic? _lastMerge;

  SettingsMergeDiagnostic? get lastMerge => _lastMerge;

  void seed(SettingsStateSnapshot snapshot) {
    _canonical = snapshot;
  }

  SettingsStateSnapshot? merge(
    SettingsStateSnapshot incoming, {
    required String source,
    String? operationId,
    int pendingCount = 0,
  }) {
    final previous = _canonical;
    if (previous == null) {
      _canonical = incoming;
      _recordMerge(
        SettingsMergeDiagnostic(
          domain: 'config/catalog',
          source: source,
          currentRevision: 0,
          incomingRevision: incoming.revision,
          applied: true,
          reason: 'baseline',
          operationId: operationId,
          pendingCount: pendingCount,
        ),
      );
      return incoming;
    }

    final previousConfigRevision = previous.revision;
    final previousCatalogRevision = previous.modelCatalogRevision;
    final configIsNewer = incoming.revision > previousConfigRevision;
    final catalogIsNewer =
        incoming.modelCatalogRevision > previousCatalogRevision;
    // 合并是否发生只由这一份实现决定；下面的诊断只是在描述它的结论。
    final merged = mergeCanonicalSettingsSnapshots(previous, incoming);
    _canonical = merged ?? previous;
    _recordMerge(
      SettingsMergeDiagnostic(
        domain: configIsNewer && catalogIsNewer
            ? 'config/catalog'
            : configIsNewer
            ? 'config'
            : catalogIsNewer
            ? 'catalog'
            : 'config/catalog',
        source: source,
        currentRevision: configIsNewer
            ? previousConfigRevision
            : previousCatalogRevision,
        incomingRevision: configIsNewer
            ? incoming.revision
            : catalogIsNewer
            ? incoming.modelCatalogRevision
            : incoming.revision,
        applied: merged != null,
        reason: merged != null
            ? 'advanced'
            : incoming.state.value == null || previous.state.value == null
            ? 'missing-state-data'
            : 'stale-or-idempotent',
        operationId: operationId,
        pendingCount: pendingCount,
      ),
    );
    return merged;
  }

  SettingsStateSnapshot? applyTo(
    SettingsStateSnapshot current,
    SettingsStateSnapshot incoming, {
    required String source,
    String? operationId,
    int pendingCount = 0,
  }) {
    if (_canonical == null) seed(current);
    final merged = merge(
      incoming,
      source: source,
      operationId: operationId,
      pendingCount: pendingCount,
    );
    return merged ?? current;
  }

  void _recordMerge(SettingsMergeDiagnostic diagnostic) {
    _lastMerge = diagnostic;
    debugPrint('studio_settings_merge ${jsonEncode(diagnostic.toJson())}');
  }
}
