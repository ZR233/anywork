import 'package:anywork_client/resources.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../state/settings_action.dart';

part 'acp_account_save_state.freezed.dart';

/// 保存编排对用户可见的阶段。
///
/// 把“配置写入在途”“已保存且连接检查在途”“已保存且检查失败可重试”“已连接”分开：
/// 检查在途时重试入口必须禁用（命令端也会拒收），检查失败后才是可重试的唯一时机。
enum AcpAccountSavePhase {
  /// 还没有保存：表单按草稿编辑。
  editing,

  /// 配置写入受理中（未结算）。
  saving,

  /// 配置已保存，连接检查在途：显示进度，不提供可点的重试。
  savedChecking,

  /// 配置已保存、连接检查失败：保留草稿，只允许重试连接检查。
  savedCheckFailed,

  /// 配置已保存且连接通过：调用方进入详情。
  savedConnected,
}

/// 一次 ACP 账号保存编排的展示状态。
///
/// 保存与连接是两个先后独立的命令：[saveAction] 记录配置写入受理与结果，[checkAction] 记录
/// 保存成功后的连接检查。两者都不改变对方的事实——检查失败不撤销保存，保存失败不启动检查，
/// 也不保留任何“已登录”的本地推断。
@Freezed(toStringOverride: false)
abstract class AcpAccountSaveViewState with _$AcpAccountSaveViewState {
  const AcpAccountSaveViewState._();

  const factory AcpAccountSaveViewState({
    required String accountId,
    @Default(0) int latestIntent,
    SettingsAction? saveAction,
    SettingsAction? checkAction,
    StudioFailure? saveError,
    StudioFailure? checkError,

    /// 配置写入已成功结算（canonical 事实成立）。
    @Default(false) bool saved,

    /// 保存后解析到的连接代次；0 表示尚未解析到。
    @Default(0) int connectionRevision,
  }) = _AcpAccountSaveViewState;

  /// 配置写入未结算：期间不再发起第二次保存。
  bool get saving => saveAction?.pending == true;

  /// 保存成功后的连接检查在途。
  bool get checking => checkAction?.pending == true;

  bool get busy => saving || checking;

  /// 未结算、未知结果或同步失败都阻止重复提交，直到显式重试。
  bool get blocksResubmission =>
      (saveAction?.preventsResubmission ?? false) ||
      (checkAction?.preventsResubmission ?? false);

  /// 对用户可见的阶段（判定只依赖 typed 事实，不靠本地布尔猜测）。
  AcpAccountSavePhase get phase {
    if (saving) return AcpAccountSavePhase.saving;
    if (!saved) return AcpAccountSavePhase.editing;
    if (checking) return AcpAccountSavePhase.savedChecking;
    if (checkError != null) return AcpAccountSavePhase.savedCheckFailed;
    return AcpAccountSavePhase.savedConnected;
  }
}

/// 一次保存编排的最终结论。
///
/// [stale] 表示回执与当前表单/意图无关：调用方既不写错误位也不导航。
/// [saved] 为 true 时配置事实已成立；[checkFailure] 非空表示“账号已保存，连接未完成”，
/// 调用方不得回滚保存或重发保存。
final class AcpAccountSaveOutcome {
  const AcpAccountSaveOutcome({
    required this.saved,
    this.connectionRevision = 0,
    this.saveFailure,
    this.checkFailure,
    this.stale = false,
  });

  const AcpAccountSaveOutcome.stale()
    : saved = false,
      connectionRevision = 0,
      saveFailure = null,
      checkFailure = null,
      stale = true;

  final bool saved;

  /// 保存后解析到的连接代次；0 表示未能解析（连接未完成）。
  final int connectionRevision;

  final StudioFailure? saveFailure;
  final StudioFailure? checkFailure;
  final bool stale;
}

/// 只有“保存成功且连接检查通过”才允许离开编辑器进入详情。
///
/// 连接失败不撤销保存，但也不清空草稿：表单保持打开，只提供“重试连接检查”。
bool acpSaveCompletesEditor(AcpAccountSaveOutcome outcome) =>
    outcome.saved && !outcome.stale && outcome.checkFailure == null;

/// 保存已成立但连接未完成：保留草稿，不再提交保存。
bool acpSaveKeepsDraft(AcpAccountSaveOutcome outcome) =>
    !outcome.stale && outcome.saved && outcome.checkFailure != null;
