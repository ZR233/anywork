import 'package:anywork_client/acp.dart';

/// 已保存接入的展示身份：认证视图模型与详情页的 family key。
///
/// [connectionRevision] 是 runtime 拥有的非密钥连接身份：只有 provider 或固定发行身份真正
/// 变化才改变，名称编辑不改变它。观察只采用账号身份**和**连接身份同时匹配的条目，因此
/// 删除后重建的同 ID 账号不会套用旧认证结果。
final class AcpAccountTarget {
  const AcpAccountTarget({
    required this.accountId,
    required this.connectionRevision,
    required this.provider,
  });

  final String accountId;
  final int connectionRevision;
  final AcpProvider provider;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountTarget &&
          other.accountId == accountId &&
          other.connectionRevision == connectionRevision &&
          other.provider == provider;

  @override
  int get hashCode => Object.hash(accountId, connectionRevision, provider);
}

/// 账号编辑页的 typed 分支：新建接入与编辑已保存接入共享同一入口，但保存语义不同。
///
/// 新建必须先由受管安装准备到就绪才能保存；编辑只改显示名，不触发准备、不触发认证、
/// 也不改连接身份。目标里没有 program/argv：受管服务器的启动配置由产品固定发行决定，
/// 不是账号字段。
sealed class AcpAccountEditorTarget {
  const AcpAccountEditorTarget();

  String get accountId;

  /// 该 provider 的目录模板；编辑页要求调用方先从 catalog 解析出模板，缺失时由调用方
  /// 报告“模板不可用”，不在这里合成 supportedVersion/installUrl 等发行事实。
  AcpAccountTemplate get template;

  bool get create;
}

/// 新建：账号 ID 由稳定的目录 ID 建议值给出，保存前还不存在于 canonical 配置。
final class AcpAccountCreateTarget extends AcpAccountEditorTarget {
  const AcpAccountCreateTarget({
    required this.accountId,
    required this.template,
  });

  @override
  final String accountId;

  @override
  final AcpAccountTemplate template;

  @override
  bool get create => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountCreateTarget &&
          other.accountId == accountId &&
          other.template == template;

  @override
  int get hashCode => Object.hash(0x0801, accountId, template);
}

/// 编辑：只改显示名；[account] 携带 canonical 连接身份。
final class AcpAccountEditTarget extends AcpAccountEditorTarget {
  const AcpAccountEditTarget({required this.account, required this.template});

  final AcpAccountSettings account;

  @override
  final AcpAccountTemplate template;

  @override
  String get accountId => account.accountId;

  @override
  bool get create => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountEditTarget &&
          other.account == account &&
          other.template == template;

  @override
  int get hashCode => Object.hash(0x0802, account, template);
}
