import 'dart:async';

/// 供应商标签在一次页面生命周期内的自动额度需求。
///
/// 只记录当前实例的 `(accountId → usageQueryRevision)` 已尝试身份；Client
/// 查询 owner 负责去重、在途任务与技术错误。本对象不持有额度 payload。
final class AccountUsageQueryIdentity {
  const AccountUsageQueryIdentity({
    required this.id,
    required this.usageQueryRevision,
  });

  final String id;
  final int usageQueryRevision;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountUsageQueryIdentity &&
          id == other.id &&
          usageQueryRevision == other.usageQueryRevision;

  @override
  int get hashCode => Object.hash(id, usageQueryRevision);
}

/// 当前配置里各实例的查询身份快照；值相等，避免 catalog 等无关水位误触发。
final class AccountUsageQueryIdentitySnapshot {
  const AccountUsageQueryIdentitySnapshot(this.identities);

  final List<AccountUsageQueryIdentity> identities;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AccountUsageQueryIdentitySnapshot) return false;
    if (other.identities.length != identities.length) return false;
    for (var index = 0; index < identities.length; index++) {
      if (other.identities[index] != identities[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(identities);
}

/// 标签可见性与查询身份变化时，决定要对哪些实例发起一次检查。
final class AccountUsageAutoDemand {
  final Map<String, int> _attemptedRevisions = <String, int>{};

  /// 返回此刻应启动查询的 account id，调用方须并行交给 Client 且不要互相等待。
  ///
  /// 发出即计入本轮已尝试（含随后失败）；隐藏时不产生新的自动请求，但会清掉
  /// 已删除实例。页面状态重建会得到新的 [AccountUsageAutoDemand]。
  List<String> sync({
    required bool visible,
    required Iterable<AccountUsageQueryIdentity> accounts,
  }) {
    final currentIds = <String>{};
    final needed = <String>[];
    for (final account in accounts) {
      currentIds.add(account.id);
      if (!visible) continue;
      if (_attemptedRevisions[account.id] == account.usageQueryRevision) {
        continue;
      }
      _attemptedRevisions[account.id] = account.usageQueryRevision;
      needed.add(account.id);
    }
    _attemptedRevisions.removeWhere((id, _) => !currentIds.contains(id));
    return needed;
  }

  List<String> apply({
    required bool visible,
    required Iterable<AccountUsageQueryIdentity> accounts,
    required void Function(String accountId) refresh,
  }) {
    final needed = sync(visible: visible, accounts: accounts);
    for (final id in needed) {
      refresh(id);
    }
    return needed;
  }
}

/// Client 已把技术失败写入 [AccountUsageQueries.state]；调用方只吞掉 Future，
/// 避免自动/单卡刷新把同一错误再打到 zone。
void ignoreAccountUsageQueryErrors(Future<void> future) {
  unawaited(future.catchError((Object _, StackTrace _) {}));
}
