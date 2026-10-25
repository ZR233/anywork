import 'package:anywork_client/studio_client.dart';

/// ACP 接入的新建/编辑草稿。
///
/// 草稿只保存表单意图：显示名与本表单对一次准备操作的认领。受管服务器的
/// program/argv 由产品固定发行与安装事实决定，不是账号配置；认证状态、安装
/// 事实与保存结果也都不写进草稿，避免把“已登录”“已安装”写成本地事实。
enum AcpAccountDraftMode { create, edit }

/// 每个草稿实例的稳定身份：换草稿就换身份，不会因复用同一 accountId 而误认亲。
int _nextFormId = 0;
String _newFormId() => 'acp-draft-${++_nextFormId}';

class AcpAccountDraft {
  /// 草稿实例带稳定 [formId]，因此构造不是 const：同一账号的新草稿也各有身份。
  AcpAccountDraft({
    required this.mode,
    required this.accountId,
    required this.template,
    required this.name,
    required this.intent,
    String? formId,
    this.connectionRevision = 0,
  }) : formId = formId ?? _newFormId();

  /// 以目录模板创建草稿：显示名与固定受管版本都来自 backend typed catalog。
  factory AcpAccountDraft.create({
    required AcpAccountTemplateView template,
    required String accountId,
  }) {
    return AcpAccountDraft(
      mode: AcpAccountDraftMode.create,
      accountId: accountId,
      template: template,
      name: template.displayName,
      intent: AcpPreparationIntent(provider: template.provider),
    );
  }

  /// 以已保存的接入创建编辑草稿：编辑只改显示名，不因改名触发准备或认证。
  factory AcpAccountDraft.edit({
    required AcpAccountSettingsView account,
    AcpAccountTemplateView? template,
  }) {
    final resolved =
        template ??
        AcpAccountTemplateView(
          provider: account.provider,
          displayName: account.name,
        );
    return AcpAccountDraft(
      mode: AcpAccountDraftMode.edit,
      accountId: account.accountId,
      template: resolved,
      name: account.name,
      intent: AcpPreparationIntent(provider: resolved.provider),
      connectionRevision: account.connectionRevision,
    );
  }

  final AcpAccountDraftMode mode;
  final String accountId;
  final AcpAccountTemplateView template;
  final String name;

  /// 本表单对准备操作的认领（provider + operation + 代次）。
  final AcpPreparationIntent intent;

  final int connectionRevision;

  /// 本表单实例的身份；迟到的 start 结果只允许回填同一实例。
  final String formId;

  bool get isCreate => mode == AcpAccountDraftMode.create;

  /// 该模板是否支持自动准备（当前宿主平台是否受支持）。
  bool get canPrepareAutomatically => template.automaticInstall.isAvailable;

  /// 产品固定的受管服务器版本（来自模板，客户端不硬编码）。
  String get supportedVersion => template.supportedVersion;

  AcpAccountDraft copyWith({String? name, AcpPreparationIntent? intent}) {
    return AcpAccountDraft(
      mode: mode,
      accountId: accountId,
      template: template,
      name: name ?? this.name,
      intent: intent ?? this.intent,
      formId: formId,
      connectionRevision: connectionRevision,
    );
  }

  /// 认领一个已知操作（本表单的受理结果，或用户显式使用已准备结果）。
  AcpAccountDraft claimOperation(String operationId) =>
      copyWith(intent: intent.claim(operationId));

  /// 提交给 Client 的写入意图：只有账号身份与显示名。
  ///
  /// 受管启动配置由产品固定发行与安装事实决定，不进账号配置；新建草稿是否
  /// 允许保存由界面按“准备未就绪不显示保存”决定，不在这里伪造安装事实。
  AcpAccountUpdateView toUpdate() => AcpAccountUpdateView(
    accountId: accountId,
    name: name.trim().isEmpty ? template.displayName : name.trim(),
    provider: template.provider,
  );
}

/// 一次 start 尝试的稳定身份。
///
/// 必须在 `await` **之前**捕获：账号、provider、来源、草稿代次、表单实例与尝试
/// 序号任一变化都说明这次回执已经过期，不得写回新草稿。
class AcpPreparationAttempt {
  const AcpPreparationAttempt({
    required this.formId,
    required this.accountId,
    required this.provider,
    required this.generation,
    required this.attempt,
  });

  factory AcpPreparationAttempt.of(
    AcpAccountDraft draft, {
    required int attempt,
  }) => AcpPreparationAttempt(
    formId: draft.formId,
    accountId: draft.accountId,
    provider: draft.template.provider,
    generation: draft.intent.generation,
    attempt: attempt,
  );

  final String formId;
  final String accountId;
  final AcpProviderView provider;
  final int generation;

  /// 同一表单内的尝试序号，避免同代次重复点击共用身份。
  final int attempt;

  /// 该尝试是否仍对应当前草稿与当前尝试序号（任一不等即过期）。
  ///
  /// [currentAttempt] 由协调器持有：即使草稿没变，重新发起过 start 也会让旧回执
  /// 失效，避免两次尝试共用同一条回填/错误通道。
  bool matches(AcpAccountDraft draft, {required int currentAttempt}) =>
      currentAttempt == attempt &&
      draft.formId == formId &&
      draft.accountId == accountId &&
      draft.template.provider == provider &&
      draft.intent.generation == generation;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpPreparationAttempt &&
          other.formId == formId &&
          other.accountId == accountId &&
          other.provider == provider &&
          other.generation == generation &&
          other.attempt == attempt;

  @override
  int get hashCode =>
      Object.hash(formId, accountId, provider, generation, attempt);
}

/// start 成功回执的接续规则：只有尝试仍是当前草稿时才认领 operation。
///
/// 返回 null 表示本次回执与当前草稿无关：调用方只保留全局 canonical 快照，
/// 不改写新草稿的字段，也不把旧 operation 写进新意图。
AcpAccountDraft? claimFromStartReply({
  required AcpAccountDraft? current,
  required AcpPreparationAttempt attempt,
  required AcpInstallSnapshotView snapshot,
  required int currentAttempt,
}) {
  final draft = current;
  if (draft == null ||
      !attempt.matches(draft, currentAttempt: currentAttempt)) {
    return null;
  }
  final operationId = snapshot.stateOf(attempt.provider).operationId;
  if (operationId == null) return null;
  return draft.claimOperation(operationId);
}

/// start 失败是否仍应显示在当前草稿上；过期尝试不得污染新草稿的错误位。
bool acceptsStartFailure({
  required AcpAccountDraft? current,
  required AcpPreparationAttempt attempt,
  required int currentAttempt,
}) {
  final draft = current;
  return draft != null &&
      attempt.matches(draft, currentAttempt: currentAttempt);
}

/// 一次准备的最终结论：只有仍属当前意图时才给出需写回的事实。
///
/// [stale] 为 true 表示这次回执与当前草稿/尝试无关：调用方只保留全局 canonical，
/// 不写草稿、不写错误，也不解除新的在途状态。
class AcpPreparationOutcome {
  const AcpPreparationOutcome({
    required this.attempt,
    this.claimed,
    this.error,
    this.stale = false,
  });

  final AcpPreparationAttempt attempt;

  /// 应写回的草稿（已认领 operation）；null 表示不改草稿。
  final AcpAccountDraft? claimed;

  /// 应就地显示的错误；[stale] 为 true 时必为 null。
  final Object? error;

  final bool stale;
}

/// 生产用的准备协调器：拥有尝试序号、在途门控与回填判断，直接调用 Client 动作。
///
/// AccountsTab 只提交草稿并应用结论；命令调用、异常捕获、过期判定与 pending 解除
/// 都在这里完成，因此可以用可控 transport 完整驱动其行为，而不需要在测试里重写
/// 回调流程。同一时刻最多一个在途尝试（重复调用返回 null），与 Client 端的
/// provider 级去重共同保证“不重叠 start”。
class AcpPreparationCoordinator {
  AcpPreparationCoordinator({required this.commands});

  final AcpInstallCommands commands;

  int _sequence = 0;
  AcpPreparationAttempt? _inFlight;

  bool get isPending => _inFlight != null;

  /// 发起一次准备；已有在途尝试时返回 null，不产生第二个 start。
  Future<AcpPreparationOutcome?> prepare({
    required AcpAccountDraft draft,
    required AcpAccountDraft? Function() currentDraft,
  }) async {
    if (_inFlight != null) return null;
    final attempt = AcpPreparationAttempt.of(draft, attempt: ++_sequence);
    _inFlight = attempt;
    try {
      final snapshot = await commands.start(draft.template.provider);
      final current = currentDraft();
      if (!_isCurrent(attempt) ||
          current == null ||
          !attempt.matches(current, currentAttempt: _sequence)) {
        return AcpPreparationOutcome(attempt: attempt, stale: true);
      }
      return AcpPreparationOutcome(
        attempt: attempt,
        claimed: claimFromStartReply(
          current: current,
          attempt: attempt,
          snapshot: snapshot,
          currentAttempt: _sequence,
        ),
      );
    } on Object catch (error) {
      final current = currentDraft();
      if (!_isCurrent(attempt) ||
          !acceptsStartFailure(
            current: current,
            attempt: attempt,
            currentAttempt: _sequence,
          )) {
        return AcpPreparationOutcome(attempt: attempt, stale: true);
      }
      return AcpPreparationOutcome(attempt: attempt, error: error);
    } finally {
      // 只有仍是这次尝试才解除在途：迟到结论不得放行第二个 start。
      if (identical(_inFlight, attempt)) _inFlight = null;
    }
  }

  /// 显式认领另一操作的就绪结果。
  ///
  /// 准备请求在途期间一律拒绝：否则迟到的 start 回执会覆盖用户刚刚显式选中的
  /// Ready。UI 也同步禁用入口，但真正的门控在这里，保证同一生产入口对
  /// 页面与测试一致生效。
  AcpAccountDraft? claim({
    required AcpAccountDraft draft,
    required AcpAccountDraft? Function() currentDraft,
    required String operationId,
  }) {
    if (_inFlight != null) return null;
    final current = currentDraft();
    if (current == null || current.formId != draft.formId) return null;
    return current.claimOperation(operationId);
  }

  bool _isCurrent(AcpPreparationAttempt attempt) =>
      identical(_inFlight, attempt) && attempt.attempt == _sequence;
}
