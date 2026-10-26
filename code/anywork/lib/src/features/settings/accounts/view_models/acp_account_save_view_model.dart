import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/operations.dart';
import 'package:anywork_client/resources.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../../app/app_bindings.dart';
import '../../state/settings_action.dart';
import '../state/acp_account_save_state.dart';

part 'acp_account_save_view_model.g.dart';

/// ACP 账号“保存并连接”的编排 owner。
///
/// 保存写入属于 `configuration`，连接检查属于 `acpAuth`；本 VM 是唯一同时持有两者的地方，
/// 因此编辑 VM 不需要第二个资源。两步严格顺序执行：
/// 1. 提交配置写入并等它**结算**（canonical 事实成立，不只是受理）；
/// 2. 重新读取 ACP 目录解析该账号的连接代次，再以冻结的代次提交连接检查。
///
/// 第二步失败只表达“账号已保存，连接未完成”：不回滚保存、不清空调用方草稿、不重发保存，
/// 也不从本地布尔值推断登录成功。名称编辑（非新建）只写配置，不发起检查。
@riverpod
class AcpAccountSaveViewModel extends _$AcpAccountSaveViewModel {
  late ConfigurationRepository _configuration;
  late AcpAuthRepository _acp;
  Observation? _saveObservation;
  Observation? _checkObservation;
  int _lifetime = 0;
  int _intent = 0;
  bool _alive = true;
  bool _ready = false;

  @override
  Future<AcpAccountSaveViewState> build(String accountId) async {
    _alive = true;
    _ready = false;
    final lifetime = ++_lifetime;
    _configuration = ref.watch(configurationRepositoryProvider);
    _acp = ref.watch(acpAuthRepositoryProvider);
    ref.onDispose(() {
      _alive = false;
      _lifetime++;
      _ready = false;
      _saveObservation?.cancel();
      _saveObservation = null;
      _checkObservation?.cancel();
      _checkObservation = null;
      // 已受理的写入与检查仍由各自 Repository 拥有，本 VM 只放弃自己的观察。
    });
    if (lifetime != _lifetime) {
      return AcpAccountSaveViewState(accountId: accountId);
    }
    _ready = true;
    return AcpAccountSaveViewState(accountId: accountId);
  }

  bool _owns(int lifetime, int intent) =>
      _alive &&
      _ready &&
      lifetime == _lifetime &&
      state.asData != null &&
      state.requireValue.latestIntent == intent;

  /// 保存（新建/改名），新建时随后提交一次连接检查。
  ///
  /// [update] 只含稳定身份与显示名：受管 program/argv 不是账号字段。
  Future<AcpAccountSaveOutcome> save(
    AcpAccountUpdate update, {
    required bool create,
  }) async {
    if (!_alive || !_ready || state.asData == null) {
      return const AcpAccountSaveOutcome.stale();
    }
    final current = state.requireValue;
    if (current.busy || current.blocksResubmission) {
      return const AcpAccountSaveOutcome.stale();
    }
    final lifetime = _lifetime;
    final intent = ++_intent;
    state = AsyncData(
      current.copyWith(
        latestIntent: intent,
        saveError: null,
        checkError: null,
        saveAction: SettingsAction(intent: intent, pending: true),
        checkAction: null,
        saved: false,
        connectionRevision: 0,
      ),
    );

    // 第一步：配置写入。只有结算成功才继续，受理本身不算保存成功。
    final saveAction = await _admit<Unit>(
      intent: intent,
      lifetime: lifetime,
      admit: () => _configuration.saveAcpAccount(update),
      isCheck: false,
    );
    if (saveAction == null) return const AcpAccountSaveOutcome.stale();
    final saveFailure = saveAction.error;
    if (!saveAction.succeeded) {
      if (!_owns(lifetime, intent)) return const AcpAccountSaveOutcome.stale();
      state = AsyncData(state.requireValue.copyWith(saveError: saveFailure));
      return AcpAccountSaveOutcome(saved: false, saveFailure: saveFailure);
    }
    if (!_owns(lifetime, intent)) return const AcpAccountSaveOutcome.stale();
    if (!create) {
      // 名称编辑不改变连接代次，也不发起检查。
      state = AsyncData(state.requireValue.copyWith(saved: true));
      return const AcpAccountSaveOutcome(saved: true);
    }

    // 保存已结算、检查尚未提交：立即进入真实的“检查在途”。
    // 否则解析目录期间 `phase` 会因 `saved && !checking && checkError == null`
    // 误判成 `savedConnected`，界面上既没有进度也没有任何可点的主操作。
    state = AsyncData(
      state.requireValue.copyWith(
        saved: true,
        checkAction: SettingsAction(intent: intent, pending: true),
      ),
    );

    // 第二步：重新解析连接代次。解析不出来时结算本次检查并保留真实原因，
    // 绝不把“没查到”当成“已连接”。
    final resolution = await _resolveAccount(update.accountId);
    if (!_owns(lifetime, intent)) return const AcpAccountSaveOutcome.stale();
    return switch (resolution) {
      _AcpAccountResolved(:final account) => await _connect(
        lifetime: lifetime,
        intent: intent,
        account: account,
      ),
      _AcpAccountUnobservable(:final failure) => _abandonCheck(
        lifetime: lifetime,
        intent: intent,
        connectionRevision: 0,
        failure: failure,
      ),
      _AcpAccountReadFailed(:final failure) => _abandonCheck(
        lifetime: lifetime,
        intent: intent,
        connectionRevision: 0,
        failure: failure,
      ),
    };
  }

  /// 一条命令的受理、观察与结算；返回 null 表示观察事实已过期。
  Future<SettingsAction?> _admit<T>({
    required int intent,
    required int lifetime,
    required OperationTicket<T> Function() admit,
    required bool isCheck,
  }) async {
    bool owns() => _owns(lifetime, intent);
    void update(SettingsAction action) {
      if (!owns()) return;
      state = AsyncData(
        isCheck
            ? state.requireValue.copyWith(checkAction: action)
            : state.requireValue.copyWith(saveAction: action),
      );
    }

    OperationTicket<T> ticket;
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
      return state.asData == null
          ? null
          : isCheck
          ? state.requireValue.checkAction
          : state.requireValue.saveAction;
    }
    StudioFailure? observationError;
    if (owns()) {
      try {
        final watch = ticket.state.watchLatest((operation) {
          if (!owns()) return;
          final action = isCheck
              ? state.requireValue.checkAction
              : state.requireValue.saveAction;
          if (action == null) return;
          update(action.copyWith(operation: operation));
        });
        if (owns()) {
          if (isCheck) {
            _checkObservation?.cancel();
            _checkObservation = watch.observation;
          } else {
            _saveObservation?.cancel();
            _saveObservation = watch.observation;
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
    if (!owns()) return null;
    final action = settledSettingsAction(
      intent,
      result,
      operation: ticket.state.value,
    ).copyWith(observationError: observationError);
    update(action);
    return action;
  }

  /// 只重试连接检查：配置事实已经成立，不再提交保存。
  ///
  /// 允许在没有第二次保存的前提下重新解析连接代次并 `check()`；保存命令一次也不会重放，
  /// 因此“保存成功 + 连接失败”可以反复重试连接而不产生重复写入。
  Future<AcpAccountSaveOutcome> retryCheck() async {
    if (!_alive || !_ready || state.asData == null) {
      return const AcpAccountSaveOutcome.stale();
    }
    final current = state.requireValue;
    // 只有“已保存”才允许只重试连接；未保存时必须走 save()。
    if (!current.saved || current.busy) {
      return const AcpAccountSaveOutcome.stale();
    }
    final lifetime = _lifetime;
    final intent = ++_intent;
    state = AsyncData(
      current.copyWith(
        latestIntent: intent,
        checkError: null,
        checkAction: SettingsAction(intent: intent, pending: true),
      ),
    );
    final resolution = await _resolveAccount(current.accountId);
    if (!_owns(lifetime, intent)) {
      return const AcpAccountSaveOutcome.stale();
    }
    return switch (resolution) {
      _AcpAccountResolved(:final account) => await _connect(
        lifetime: lifetime,
        intent: intent,
        account: account,
      ),
      _AcpAccountUnobservable(:final failure) => _abandonCheck(
        lifetime: lifetime,
        intent: intent,
        connectionRevision: current.connectionRevision,
        failure: failure,
      ),
      _AcpAccountReadFailed(:final failure) => _abandonCheck(
        lifetime: lifetime,
        intent: intent,
        connectionRevision: current.connectionRevision,
        failure: failure,
      ),
    };
  }

  /// 代次已解析：冻结代次并提交唯一一次连接检查。
  Future<AcpAccountSaveOutcome> _connect({
    required int lifetime,
    required int intent,
    required AcpAccountSettings account,
  }) async {
    if (!_owns(lifetime, intent)) return const AcpAccountSaveOutcome.stale();
    state = AsyncData(
      state.requireValue.copyWith(
        connectionRevision: account.connectionRevision,
      ),
    );
    final checkAction = await _admit<AcpAuthSnapshot>(
      intent: intent,
      lifetime: lifetime,
      admit: () => _acp.check(
        accountId: account.accountId,
        expectedConnectionRevision: account.connectionRevision,
      ),
      isCheck: true,
    );
    // `_admit` 只在本次意图仍拥有状态时返回结算结果；为 null 说明检查结论已属于
    // 更新的一次提交或本 VM 已销毁，此时不覆盖新表单，也不伪造“连接未完成”。
    if (checkAction == null || !_owns(lifetime, intent)) {
      return const AcpAccountSaveOutcome.stale();
    }
    final checkFailure = checkAction.error;
    state = AsyncData(state.requireValue.copyWith(checkError: checkFailure));
    return AcpAccountSaveOutcome(
      saved: true,
      connectionRevision: account.connectionRevision,
      checkFailure: checkFailure,
    );
  }

  /// 检查未能提交时**结算原 action**并如实带回原因。
  ///
  /// 不结算会让 `checking` 永远为真：`phase` 优先判定 pending，界面停在“检查在途”，
  /// 重试入口也被忙碌态永久禁用。[connectionRevision] 保留已知代次，不清零。
  AcpAccountSaveOutcome _abandonCheck({
    required int lifetime,
    required int intent,
    required int connectionRevision,
    required StudioFailure failure,
  }) {
    if (_owns(lifetime, intent)) {
      state = AsyncData(
        state.requireValue.copyWith(
          checkAction: SettingsAction(
            intent: intent,
            outcome: SettingsActionOutcome.rejected,
            error: failure,
          ),
          checkError: failure,
        ),
      );
    }
    return AcpAccountSaveOutcome(
      saved: true,
      connectionRevision: connectionRevision,
      checkFailure: failure,
    );
  }

  /// 保存后从 Settings canonical 目录解析该账号的连接代次。
  ///
  /// 三个分支必须分开：读取失败沿用原始 [StudioFailure]（可恢复信息不丢），
  /// 只有“读取成功但账号不在目录里”才是身份不可观察。
  Future<_AcpAccountResolution> _resolveAccount(String accountId) async {
    try {
      final directory = await _configuration.loadAcpAccounts();
      final account = directory.account(accountId);
      return account == null
          ? _AcpAccountUnobservable(_unresolvedConnection(accountId))
          : _AcpAccountResolved(account);
    } on StudioFailure catch (failure) {
      return _AcpAccountReadFailed(failure);
    }
  }

  /// 连接代次不可观察：连接未完成，但保存事实不变。
  static StudioFailure _unresolvedConnection(String accountId) => StudioFailure(
    code: StudioFailureCode.superseded,
    message: 'The saved ACP account identity was not observable: $accountId',
    retryable: true,
    correlationId: 'settings-acp-save',
  );
}

/// 保存/重试时解析连接代次的结果。
///
/// 调用方不需要猜测“为什么没查到”：读取失败与账号缺失是两种事实，
/// 前者保留原始失败（含可恢复信息），后者才是身份不可观察。
sealed class _AcpAccountResolution {
  const _AcpAccountResolution();
}

final class _AcpAccountResolved extends _AcpAccountResolution {
  const _AcpAccountResolved(this.account);

  final AcpAccountSettings account;
}

final class _AcpAccountUnobservable extends _AcpAccountResolution {
  const _AcpAccountUnobservable(this.failure);

  final StudioFailure failure;
}

final class _AcpAccountReadFailed extends _AcpAccountResolution {
  const _AcpAccountReadFailed(this.failure);

  final StudioFailure failure;
}
