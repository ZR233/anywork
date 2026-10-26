import '../../models.dart';
import '../../model_directory.dart';
import 'stores/domain_sync.dart';

/// Display intent deliberately has no resource revision. A pending selection
/// must never be mistaken for an observed Thread model-route resource.
final class ModelRouteDisplay {
  const ModelRouteDisplay({
    required this.accountId,
    required this.modelId,
    required this.effort,
    required this.pending,
    required this.available,
    this.unavailableReason,
  });

  final String accountId;
  final String modelId;
  final String? effort;
  final bool pending;
  final bool available;
  final String? unavailableReason;

  @override
  bool operator ==(Object other) =>
      other is ModelRouteDisplay &&
      accountId == other.accountId &&
      modelId == other.modelId &&
      effort == other.effort &&
      pending == other.pending &&
      available == other.available &&
      unavailableReason == other.unavailableReason;

  @override
  int get hashCode => Object.hash(
    accountId,
    modelId,
    effort,
    pending,
    available,
    unavailableReason,
  );
}

final class StartRouteQuery {
  const StartRouteQuery({
    required this.canonical,
    required this.lane,
    required this.display,
    required this.pending,
    required this.failure,
  });

  final ModeModelRouteView? canonical;
  final ModeModelRouteView? lane;
  final ModeModelRouteView? display;
  final bool pending;
  final String? failure;
}

final class RoleRouteQuery {
  const RoleRouteQuery({
    required this.accountId,
    required this.modelId,
    required this.effort,
    required this.descriptor,
    required this.hasConfiguredRoute,
  });

  final String accountId;
  final String modelId;
  final String? effort;
  final AccountModelView? descriptor;
  final bool hasConfiguredRoute;

  bool get unavailable =>
      hasConfiguredRoute && (descriptor == null || !descriptor!.enabled);
}

final class ThreadStatusQuery {
  const ThreadStatusQuery({required this.thread, required this.runtime});
  final StudioThread? thread;
  final ThreadRuntimeView? runtime;
}

/// Route resolution shared by Client consumers. These queries preserve the
/// existing mode/default inheritance rules without publishing invented facts.
abstract final class ModelRouteQueries {
  static ModeModelRouteView? modeRoute(
    List<ModeModelRouteView> routes,
    ThreadModeId mode,
  ) =>
      routes.where((route) => route.modeId == mode).firstOrNull ??
      routes.where((route) => route.modeId == ThreadModeId.simple).firstOrNull;

  static AccountModelView? model(
    List<ModelSelectionAccount> accounts,
    String accountId,
    String modelId,
  ) {
    final account = accounts
        .where((candidate) => candidate.id == accountId)
        .firstOrNull;
    final models = account?.models;
    return models
        ?.where((candidate) => candidate.modelId == modelId)
        .firstOrNull;
  }

  /// A model selection keeps a supported effort, then uses the declared model
  /// default when it is still a candidate, then the first supported effort.
  static String? effortAfterModelSelection(
    AccountModelView? model,
    String? candidate,
  ) {
    if (model?.reasoningEfforts.contains(candidate) == true) return candidate;
    final declared = model?.defaultReasoningEffort;
    if (declared != null &&
        declared.isNotEmpty &&
        model!.reasoningEfforts.contains(declared)) {
      return declared;
    }
    return model?.reasoningEfforts.firstOrNull;
  }

  /// New Agent-profile drafts previously admitted only a supported default.
  static String? agentProfileEffort(
    AccountModelView? model,
    String? candidate,
  ) {
    if (model?.reasoningEfforts.contains(candidate) == true) return candidate;
    final declared = model?.defaultReasoningEffort;
    if (declared != null &&
        declared.isNotEmpty &&
        model!.reasoningEfforts.contains(declared)) {
      return declared;
    }
    return model?.reasoningEfforts.firstOrNull;
  }

  static StartRouteQuery startRoute({
    required List<ModeModelRouteView> routes,
    required Map<String, CommandStatus> commands,
    required StartSessionDraft draft,
    required ThreadModeId mode,
  }) {
    final canonical = modeRoute(routes, mode);
    final model = commands['new-thread-route:model:${mode.id}'];
    final effort = commands['new-thread-route:effort:${mode.id}'];
    var lane = canonical;
    if (model?.isPending == true &&
        model!.target.accountId != null &&
        model.target.modelId != null) {
      lane = ModeModelRouteView(
        modeId: mode,
        accountId: model.target.accountId!,
        modelId: model.target.modelId!,
        effort: model.target.effort ?? canonical?.effort ?? '',
      );
    } else if (effort?.isPending == true && canonical != null) {
      lane = ModeModelRouteView(
        modeId: mode,
        accountId: canonical.accountId,
        modelId: canonical.modelId,
        effort: effort!.target.effort ?? canonical.effort,
      );
    }
    final failure = [model, effort]
        .where((status) => status?.phase == CommandPhase.failed)
        .map((status) => status?.error?.message)
        .firstOrNull;
    return StartRouteQuery(
      canonical: canonical,
      lane: lane,
      display: overlayStartSessionRoute(
        mode: mode,
        laneRoute: lane,
        modelIntent: draft.modelIntentFor(mode),
        effortIntent: draft.effortIntentFor(mode),
      ),
      pending: model?.isPending == true || effort?.isPending == true,
      failure: failure,
    );
  }

  static ModelRouteDisplay? threadRoute({
    required ThreadModelRouteView? canonical,
    required CommandStatus? command,
    required List<ModelSelectionAccount> accounts,
  }) {
    final target = command?.isPending == true ? command?.target : null;
    final pending = target?.accountId != null && target?.modelId != null;
    final accountId = pending ? target!.accountId : canonical?.accountId;
    final modelId = pending ? target!.modelId : canonical?.modelId;
    if (accountId == null || modelId == null) return null;
    return ModelRouteDisplay(
      accountId: accountId,
      modelId: modelId,
      effort: pending ? target!.effort ?? canonical?.effort : canonical?.effort,
      pending: pending,
      available: pending
          ? model(accounts, accountId, modelId)?.enabled == true &&
                model(
                      accounts,
                      accountId,
                      modelId,
                    )?.matchesType(ModelType.text) ==
                    true
          : canonical!.available &&
                model(accounts, accountId, modelId)?.enabled != false,
      unavailableReason: pending ? null : canonical?.unavailableReason,
    );
  }

  static RoleRouteQuery roleRoute({
    required List<ModelSelectionAccount> accounts,
    required List<RoleSettingsView> roles,
    required String role,
  }) {
    final configured = roles.where((value) => value.key == role).firstOrNull;
    final hasRoute =
        configured != null &&
        (configured.accountId.isNotEmpty || configured.modelId.isNotEmpty);
    if (hasRoute) {
      final descriptor = model(
        accounts,
        configured.accountId,
        configured.modelId,
      );
      return RoleRouteQuery(
        accountId: configured.accountId,
        modelId: configured.modelId,
        effort: configured.effort.isEmpty
            ? effortAfterModelSelection(descriptor, null)
            : configured.effort,
        descriptor: descriptor,
        hasConfiguredRoute: true,
      );
    }
    for (final account in accounts) {
      final descriptor = account
          .modelsFor(type: ModelType.text)
          .where((candidate) => candidate.modelId.isNotEmpty)
          .firstOrNull;
      if (descriptor == null) continue;
      return RoleRouteQuery(
        accountId: account.id,
        modelId: descriptor.modelId,
        effort: effortAfterModelSelection(descriptor, null),
        descriptor: descriptor,
        hasConfiguredRoute: false,
      );
    }
    return const RoleRouteQuery(
      accountId: '',
      modelId: '',
      effort: null,
      descriptor: null,
      hasConfiguredRoute: false,
    );
  }

  static RoleRouteQuery newAgentProfileRoute(
    List<ModelSelectionAccount> accounts,
  ) {
    return roleRoute(accounts: accounts, roles: const [], role: '');
  }

  static StudioThread? threadIdentity({
    required String threadId,
    required List<StudioThread> directory,
  }) => directory.where((thread) => thread.id == threadId).firstOrNull;

  static ThreadStatusQuery threadStatus({
    required String threadId,
    required List<StudioThread> directory,
    required ThreadRuntimeView? runtime,
  }) => ThreadStatusQuery(
    thread: threadIdentity(threadId: threadId, directory: directory),
    runtime: runtime,
  );

  /// 输出吞吐含首字等待：`输出词元 × 1000 ÷ 总响应毫秒`。
  ///
  /// A complete live pair replaces the display. Otherwise the canonical Turn
  /// pair is adopted as a whole. The two samples are never mixed.
  static double? throughput(ThreadRuntimeView runtime) {
    return throughputSource(runtime)?.tokensPerSecond;
  }

  /// Live pair first, otherwise the canonical Turn pair. Never cross samples.
  ///
  /// 两侧都使用含首字等待的总响应耗时；decode 不再作为分母，未知首字也不阻止计算。
  static ({int outputTokens, int responseMillis, double tokensPerSecond})?
  throughputSource(ThreadRuntimeView runtime) {
    final live = runtime.liveUsage;
    return _completeThroughputPair(
          live?.completionTokens,
          live?.responseMillis,
        ) ??
        _completeThroughputPair(
          runtime.turnCompletionTokens,
          runtime.turnResponseMillis,
        );
  }

  static ({int outputTokens, int responseMillis, double tokensPerSecond})?
  _completeThroughputPair(int? tokens, int? millis) {
    if (tokens == null || tokens <= 0 || millis == null || millis <= 0) {
      return null;
    }
    return (
      outputTokens: tokens,
      responseMillis: millis,
      tokensPerSecond: tokens * 1000 / millis,
    );
  }

  /// 删除账号时若被删者仍是默认账号，按稳定顺序选择首个剩余账号。
  static String? accountAfterRemoval({
    required List<ModelSelectionAccount> accounts,
    required String? currentDefault,
    required String removed,
  }) => currentDefault == removed
      ? accounts.where((account) => account.id != removed).firstOrNull?.id
      : currentDefault;
}
