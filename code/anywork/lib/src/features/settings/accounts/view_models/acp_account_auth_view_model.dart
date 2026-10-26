import 'dart:async';

import 'package:anywork_client/acp.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/acp_account_auth_state.dart';
import '../state/acp_account_target.dart';
import '../state/acp_command_notice.dart';

part 'acp_account_auth_view_model.g.dart';

/// 一个已保存接入的认证状态与命令。
///
/// 业务状态只来自 canonical `acpAuth` 观察：本 VM 持有自己的观察租约，离开页面/重建/返回
/// 只释放自身租约，不取消已受理的检查或登录，也不重启检查。命令只提交意图并记录受理与
/// 结果；`closing`/`cancelling` 是忙而不是终态，取消入口只由 canonical 的 operation 身份
/// 决定是否可达。
@riverpod
class AcpAccountAuthViewModel extends _$AcpAccountAuthViewModel {
  late AcpAuthRepository _auth;
  AcpObservationLease<AcpAuthObservation>? _lease;
  Observation? _commandObservation;
  Observation? _cancelObservation;
  int _lifetime = 0;
  int _intent = 0;
  bool _alive = true;
  bool _ready = false;

  @override
  Future<AcpAccountAuthViewState> build(AcpAccountTarget target) async {
    _alive = true;
    _ready = false;
    // 新的存活代次：旧观察的回调据此丢弃迟到事实。
    _lifetime++;
    _auth = ref.watch(acpAuthRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _ready = false;
      _releaseLease();
      _commandObservation?.cancel();
      _commandObservation = null;
      _cancelObservation?.cancel();
      _cancelObservation = null;
      // 已受理的检查/登录仍由 Repository 拥有：本 VM 只放弃自己的观察与订阅。
    });
    _ready = true;
    // 不在这里建立观察：设置页用 Offstage 保持 Tab 挂载，因此“已挂载”不等于
    // “用户可见”。隐藏时不产生 feed demand，等 setVisible(true) 再取租约。
    return AcpAccountAuthViewState(
      target: target,
      auth: const AcpAuthState.unchecked(),
    );
  }

  /// 打开本页面自己的观察租约并等待基线。
  ///
  /// 不发送任何认证命令：打开订阅不会启动外部程序，也不会产生检查。
  Future<StudioFailure?> _open(int lifetime, AcpAccountTarget target) async {
    _releaseLease();
    try {
      _lease = _auth.observe(
        onState: (observation) {
          if (!_ready || !_alive || lifetime != _lifetime) return;
          _publishAuth(
            observation.stateOf(
              target.accountId,
              connectionRevision: target.connectionRevision,
            ),
          );
        },
      );
    } on StudioFailure catch (error) {
      return error;
    }
    try {
      await _auth.synchronize();
    } on StudioFailure catch (error) {
      return error;
    }
    return null;
  }

  /// 可见需求：离开页面只释放本租约，返回时复用同一订阅（不重启检查）。
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

  Future<void> _reopen(int lifetime, AcpAccountTarget target) async {
    final error = await _open(lifetime, target);
    if (!_alive || lifetime != _lifetime || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        auth: _currentAuth(target),
        observationError: error,
      ),
    );
  }

  /// 显式重连被替换或失败的订阅；不重放任何已受理命令。
  Future<void> retryObservation() async {
    if (!_alive || !_ready || state.asData == null) return;
    if (_lease == null) return;
    final lifetime = _lifetime;
    final target = state.requireValue.target;
    StudioFailure? error;
    try {
      await _auth.retrySync();
    } on StudioFailure catch (failure) {
      error = failure;
    }
    if (!_alive || lifetime != _lifetime || state.asData == null) return;
    state = AsyncData(
      state.requireValue.copyWith(
        auth: _currentAuth(target),
        observationError: error,
      ),
    );
  }

  /// 连接检查：initialize + `session/new` 探测，不发送 prompt。
  Future<void> check() => _submit(
    cancel: false,
    admit: () => _auth.check(
      accountId: state.requireValue.target.accountId,
      expectedConnectionRevision: state.requireValue.target.connectionRevision,
    ),
  );

  /// 按服务端实际宣告的 agent 方法登录。
  Future<void> login(String methodId) => _submit(
    cancel: false,
    admit: () => _auth.authenticate(
      accountId: state.requireValue.target.accountId,
      expectedConnectionRevision: state.requireValue.target.connectionRevision,
      methodId: methodId,
    ),
  );

  /// 取消当前操作：只认 canonical 给出的 operation 身份，不与 start 排队。
  Future<void> cancel() => _submit(
    cancel: true,
    admit: () {
      final operationId = state.requireValue.auth.operationId;
      if (operationId == null) {
        // 没有 canonical 目标就没有可取消身份：不发无目标取消。
        throw const StudioFailure(
          code: StudioFailureCode.invalidArgument,
          message: 'The ACP operation identity is not observable.',
          retryable: false,
          correlationId: 'settings-acp-auth',
        );
      }
      return _auth.cancel(
        accountId: state.requireValue.target.accountId,
        targetOperationId: operationId,
      );
    },
  );

  Future<void> _submit({
    required bool cancel,
    required OperationTicket<AcpAuthSnapshot> Function() admit,
  }) async {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if ((cancel ? current.cancelBusy : current.busy)) return;
    final lifetime = _lifetime;
    final intent = ++_intent;
    // 新命令取代旧拒绝：认证类通知只在明确重试时清除。
    state = AsyncData(
      current.copyWith(
        latestIntent: intent,
        notice: null,
        checkAction: cancel
            ? current.checkAction
            : SettingsAction(intent: intent, pending: true),
        cancelAction: cancel
            ? SettingsAction(intent: intent, pending: true)
            : current.cancelAction,
      ),
    );
    bool owns() =>
        _alive &&
        _ready &&
        lifetime == _lifetime &&
        state.asData != null &&
        state.requireValue.latestIntent == intent;
    void update(SettingsAction action) {
      if (!owns()) return;
      state = AsyncData(
        cancel
            ? state.requireValue.copyWith(cancelAction: action)
            : state.requireValue.copyWith(checkAction: action),
      );
    }

    OperationTicket<AcpAuthSnapshot> ticket;
    try {
      ticket = admit();
    } on StudioFailure catch (error) {
      update(
        SettingsAction(
          intent: intent,
          outcome: SettingsActionOutcome.rejected,
          error: error,
        ),
      );
      _notice(error, cancel: cancel, intent: intent, lifetime: lifetime);
      return;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          final action = cancel
              ? state.requireValue.cancelAction
              : state.requireValue.checkAction;
          update(action!.copyWith(operation: operation));
        });
        if (owns()) {
          if (cancel) {
            _cancelObservation?.cancel();
            _cancelObservation = watch.observation;
          } else {
            _commandObservation?.cancel();
            _commandObservation = watch.observation;
          }
        } else {
          watch.observation.cancel();
        }
      } on StudioFailure catch (error) {
        observationError = error;
      }
      update(
        SettingsAction(
          intent: intent,
          pending: true,
          operation: ticket.state.value,
          observationError: observationError,
        ),
      );
    }
    final result = await ticket.result;
    if (!owns()) return;
    update(
      settledSettingsAction(
        intent,
        result,
        operation: ticket.state.value,
      ).copyWith(observationError: observationError),
    );
    // 命令层失败事实只从 typed 结算结果读取，不解析错误文案。
    final settledError = cancel
        ? state.requireValue.cancelAction?.error
        : state.requireValue.checkAction?.error;
    if (settledError != null) {
      _notice(settledError, cancel: cancel, intent: intent, lifetime: lifetime);
    }
  }

  /// 命令失败通知：重复输入（typed busy + 该账号仍在途）不记成红色失败。
  void _notice(
    StudioFailure error, {
    required bool cancel,
    required int intent,
    required int lifetime,
  }) {
    if (!_alive || !_ready || lifetime != _lifetime || state.asData == null) {
      return;
    }
    final current = state.requireValue;
    if (current.latestIntent != intent) return;
    if (isAcpAuthDuplicateWhileInFlight(
      error: error,
      requestConnectionRevision: current.target.connectionRevision,
      currentConnectionRevision: current.target.connectionRevision,
      auth: current.auth,
    )) {
      return;
    }
    state = AsyncData(
      current.copyWith(
        notice: AcpCommandNotice(
          kind: AcpCommandNoticeKind.authentication,
          accountId: current.target.accountId,
          connectionRevision: current.target.connectionRevision,
          failure: error,
          operationId: current.auth.operationId,
        ),
      ),
    );
  }

  AcpAuthState _currentAuth(AcpAccountTarget target) =>
      (_lease?.latest.value ?? AcpAuthObservation.idle).stateOf(
        target.accountId,
        connectionRevision: target.connectionRevision,
      );

  void _publishAuth(AcpAuthState auth) {
    if (!_alive || !_ready || state.asData == null) return;
    final current = state.requireValue;
    if (current.auth == auth) return;
    state = AsyncData(current.copyWith(auth: auth));
  }

  void _releaseLease() {
    _lease?.release();
    _lease = null;
  }
}
