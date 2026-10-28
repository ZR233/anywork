import 'dart:async';

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/acp_account_editor_state.dart';
import '../state/acp_account_target.dart';

part 'acp_account_editor_view_model.g.dart';

/// ACP 接入新建/编辑表单的状态与受管安装准备编排。
///
/// 表单持有自己的 `acpInstall` 观察租约：离开页面/重建/返回只释放自身租约，不取消已受理
/// 的准备，也不重新发起准备。安装事实只来自 canonical 快照；本 VM 不从进度推断就绪，也
/// 不在准备成功时创建账号——保存与写入属于配置领域，由调用方在准备就绪后显式提交。
@riverpod
class AcpAccountEditorViewModel extends _$AcpAccountEditorViewModel {
  late AcpInstallRepository _install;
  AcpObservationLease<AcpInstallObservation>? _lease;
  Observation? _prepareObservation;
  Observation? _cancelObservation;
  int _lifetime = 0;
  int _intentSequence = 0;
  bool _alive = true;
  bool _ready = false;

  @override
  Future<AcpAccountEditorViewState> build(AcpAccountEditorTarget target) async {
    _alive = true;
    _ready = false;
    final intent = AcpPreparationIntent.fresh(
      provider: target.template.provider,
    );
    // 新的存活代次：旧观察的回调据此丢弃迟到事实。
    _lifetime++;
    _install = ref.watch(acpInstallRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _ready = false;
      _releaseLease();
      _prepareObservation?.cancel();
      _prepareObservation = null;
      _cancelObservation?.cancel();
      _cancelObservation = null;
      // 已受理的准备仍由 Repository 拥有：表单只放弃自己的观察与租约。
    });
    _ready = true;
    // 隐藏时不建立安装观察：设置页用 Offstage 保持 Tab 挂载，“已挂载”不等于可见。
    // 表单先返回 idle（未加载）状态，等 setVisible(true) 再取租约。
    return AcpAccountEditorViewState(
      target: target,
      name: _initialName(target),
      intent: intent,
      install: const AcpInstallState.idle(),
    );
  }

  String _initialName(AcpAccountEditorTarget target) => switch (target) {
    AcpAccountCreateTarget(:final template) => template.displayName,
    AcpAccountEditTarget(:final account) => account.name,
  };

  /// 打开本表单自己的观察租约并等待基线；不发起任何准备。
  Future<StudioFailure?> _open(
    int lifetime,
    AcpAccountEditorTarget target,
  ) async {
    _releaseLease();
    final provider = target.template.provider;
    try {
      _lease = _install.observe(
        onState: (observation) {
          if (!_ready || !_alive || lifetime != _lifetime) return;
          _publishInstall(observation.stateOf(provider));
        },
      );
    } on StudioFailure catch (error) {
      return error;
    }
    try {
      await _install.synchronize();
    } on StudioFailure catch (error) {
      return error;
    }
    return null;
  }

  /// 可见需求：离开页面只释放本租约，返回时复用同一订阅（不重启准备）。
  void setVisible(bool visible) {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.visible == visible) return;
    state = AsyncData(current.copyWith(visible: visible));
    if (!visible) {
      _releaseLease();
      return;
    }
    final lifetime = _lifetime;
    unawaited(_reopen(lifetime, current.target));
  }

  Future<void> _reopen(int lifetime, AcpAccountEditorTarget target) async {
    final error = await _open(lifetime, target);
    if (!_alive || lifetime != _lifetime || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        install: _currentInstall(target),
        observationError: error,
      ),
    );
  }

  /// 显式重连被替换或失败的订阅；不重放已受理的准备。
  Future<void> retryObservation() async {
    if (!_alive || !_ready || state.asData == null) return;
    if (_lease == null) return;
    final lifetime = _lifetime;
    final target = state.requireValue.target;
    StudioFailure? error;
    try {
      await _install.retrySync();
    } on StudioFailure catch (failure) {
      error = failure;
    }
    if (!_alive || lifetime != _lifetime || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        install: _currentInstall(target),
        observationError: error,
      ),
    );
  }

  /// 只改显示名：编辑名称不触发准备、不触发认证、不改连接身份。
  void setName(String value) {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.name == value) return;
    state = AsyncData(
      current.copyWith(name: value, draftRevision: current.draftRevision + 1),
    );
  }

  /// “下载并准备”：只受理共享操作并把 operation 绑定到本草稿。
  ///
  /// 不保存账号、不检查连接；终态与进度全部由 `acpInstall` topic 推进。同一时刻最多一个
  /// 在途受理：本表单的 start 未回执或阶段仍在途时不再发起第二个 start。
  Future<void> prepare() async {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.preparing ||
        (current.prepareAction?.preventsResubmission ?? false) ||
        current.install.isBusy ||
        !current.canPrepareAutomatically) {
      return;
    }
    final lifetime = _lifetime;
    final intent = ++_intentSequence;
    final provider = current.provider;
    final preparationIntent = current.intent;
    _prepareObservation?.cancel();
    _prepareObservation = null;
    state = AsyncData(
      current.copyWith(
        latestIntent: intent,
        prepareAction: SettingsAction(intent: intent, pending: true),
        observationError: null,
      ),
    );
    // start 与 cancel 各自按原动作结算：后发取消不能废弃合法的 start 受理回执。
    bool owns() =>
        _alive &&
        _ready &&
        lifetime == _lifetime &&
        state.asData != null &&
        state.requireValue.provider == provider &&
        state.requireValue.intent.provider == preparationIntent.provider &&
        state.requireValue.intent.generation == preparationIntent.generation &&
        state.requireValue.prepareAction?.intent == intent;
    OperationTicket<AcpInstallSnapshot> ticket;
    try {
      ticket = _install.prepare(provider);
    } on StudioFailure catch (error) {
      _settlePrepare(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
        owns: owns,
        preparationIntent: preparationIntent,
      );
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (!owns()) return;
          final action = state.requireValue.prepareAction;
          if (action == null) return;
          state = AsyncData(
            state.requireValue.copyWith(
              prepareAction: action.copyWith(operation: operation),
            ),
          );
        });
        if (owns()) {
          _prepareObservation = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
    }
    final result = await ticket.result;
    if (!owns()) return;
    _settlePrepare(
      settledSettingsAction(
        intent,
        result,
        operation: ticket.state.value,
      ).copyWith(observationError: observationError),
      owns: owns,
      preparationIntent: preparationIntent,
      // 只有受理成功的回执才认领 operation：失败不创建账号、不绑定意图。
      reply: _replySnapshot(result),
    );
  }

  /// 失败/受理结果的就地结算：成功受理时认领回执里的 operation 身份。
  void _settlePrepare(
    SettingsAction action, {
    required bool Function() owns,
    required AcpPreparationIntent preparationIntent,
    AcpInstallSnapshot? reply,
  }) {
    if (!owns()) return;
    var current = state.requireValue.copyWith(
      prepareAction: action,
      // 受理失败时保留 observationError 之外的全部事实；失败不写草稿。
      observationError:
          action.observationError ?? state.requireValue.observationError,
    );
    final claimed = reply == null
        ? null
        : _claimFromReply(reply, preparationIntent);
    if (claimed != null) {
      current = current.copyWith(intent: claimed);
    }
    state = AsyncData(current);
  }

  /// 受理回执 → 认领的意图。
  ///
  /// 只认 provider 与回执快照里该 provider 当前 operation 身份都匹配的结果；没有 operation
  /// 身份时不认领（不按时间或先后顺序猜归属）。
  AcpPreparationIntent? _claimFromReply(
    AcpInstallSnapshot reply,
    AcpPreparationIntent intent,
  ) {
    final operationId = reply.stateOf(intent.provider).operationId;
    return operationId == null ? null : intent.claim(operationId);
  }

  /// 显式认领同一 provider 已就绪的结果（来自另一个操作）。
  ///
  /// 只有用户按下“使用已准备结果”才绑定该 operation：同名品牌或相似路径都不是认领依据。
  /// 本表单 start 仍在途时一律拒绝，避免迟到的回执覆盖用户刚显式选中的就绪结果。
  void usePrepared() {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.preparing ||
        (current.prepareAction?.preventsResubmission ?? false)) {
      return;
    }
    final available = current.availableElsewhere;
    final operationId = current.install.operationId;
    if (available == null || operationId == null) return;
    state = AsyncData(
      current.copyWith(intent: current.intent.claim(operationId)),
    );
  }

  /// 取消当前共享准备：只认 canonical 给出的 operation 身份，独立于 start 的在途标志。
  Future<void> cancelPrepare() async {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    final target = current.install.operationId;
    if (current.cancelPending || target == null) return;
    final lifetime = _lifetime;
    final intent = ++_intentSequence;
    final provider = current.provider;
    // 新目标只替换本表单的观察；旧票据仍由 Repository 拥有并继续结算。
    _cancelObservation?.cancel();
    _cancelObservation = null;
    state = AsyncData(
      current.copyWith(
        latestIntent: intent,
        cancelAction: SettingsAction(intent: intent, pending: true),
        cancelTargetOperationId: target,
      ),
    );
    bool owns() =>
        _alive &&
        _ready &&
        lifetime == _lifetime &&
        state.asData != null &&
        state.requireValue.provider == provider &&
        state.requireValue.cancelTargetOperationId == target &&
        state.requireValue.cancelAction?.intent == intent;
    OperationTicket<AcpInstallSnapshot> ticket;
    try {
      ticket = _install.cancel(provider, targetOperationId: target);
    } on StudioFailure catch (error) {
      if (owns()) {
        state = AsyncData(
          state.requireValue.copyWith(
            cancelAction: SettingsAction(
              intent: intent,
              outcome: SettingsActionOutcome.rejected,
              error: error,
            ),
          ),
        );
      }
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (!owns()) return;
          final action = state.requireValue.cancelAction;
          if (action == null) return;
          state = AsyncData(
            state.requireValue.copyWith(
              cancelAction: action.copyWith(operation: operation),
            ),
          );
        });
        if (owns()) {
          _cancelObservation = watch.observation;
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
    }
    final result = await ticket.result;
    if (!owns()) return;
    state = AsyncData(
      state.requireValue.copyWith(
        cancelAction: settledSettingsAction(
          intent,
          result,
          operation: ticket.state.value,
        ).copyWith(observationError: observationError),
      ),
    );
  }

  /// 一次保存/更新意图：只有账号身份与显示名。
  ///
  /// 受管 program/argv 由产品固定发行与安装事实决定，不进账号配置；该值不包含连接身份，
  /// 由配置领域的回执解析。写入命令本身由调用方提交（账号写入属于配置领域）。
  AcpAccountUpdate toUpdate() {
    final current = state.requireValue;
    final template = current.template;
    return AcpAccountUpdate(
      accountId: current.accountId,
      name: current.name.trim().isEmpty
          ? template.displayName
          : current.name.trim(),
      provider: current.provider,
    );
  }

  AcpInstallSnapshot? _replySnapshot(
    CommandResult<AcpInstallSnapshot> result,
  ) => switch (result) {
    RejectedCommandResult<AcpInstallSnapshot>() ||
    UnknownOutcomeCommandResult<AcpInstallSnapshot>() => null,
    CommittedCommandResult<AcpInstallSnapshot>(:final value) => value,
    AcknowledgedCommandResult<AcpInstallSnapshot>(:final value) => value,
    SyncFailedCommandResult<AcpInstallSnapshot>(:final value) => value,
    AcknowledgedSyncFailedCommandResult<AcpInstallSnapshot>(:final value) =>
      value,
  };

  AcpInstallState _currentInstall(AcpAccountEditorTarget target) =>
      (_lease?.latest.value ?? AcpInstallObservation.idle).stateOf(
        target.template.provider,
      );

  void _publishInstall(AcpInstallState install) {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.install == install) return;
    state = AsyncData(current.copyWith(install: install));
  }

  void _releaseLease() {
    _lease?.release();
    _lease = null;
  }
}
