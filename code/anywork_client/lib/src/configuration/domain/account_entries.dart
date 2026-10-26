/// Configuration 领域的账号条目值：ACP 账号的 canonical 读取、模板/账号的 typed 分支聚合。
///
/// Native 模型账号与 ACP 接入共享产品入口，但各自保留封闭语义：模板选择与账号条目
/// 都以 sealed 分支表达，调用方按分支处理，不按显示名、模板 ID 或 baseUrl 猜协议。
/// ACP 账号由 Settings 快照承载（与 Native 账号同一 revision 收敛），本领域不另建
/// 认证/安装 canonical：认证状态来自 `acpAuth` 快照，安装事实来自 `acpInstall` 快照。
library;

import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:anywork_client/acp.dart';

// Full import: the generated `$ProductReadOriginCopyWith` is referenced from
// account_entries.freezed.dart, so a narrow `show` would hide it.
import '../../../resources.dart';
// AccountTemplate 的定义库必须完整可见：生成的 `$AccountTemplateCopyWith` 在
// account_entries.freezed.dart 里被引用，窄 `show` 会把它藏掉。
import '../../models/domain/template_values.dart';
import 'configuration_state.dart';
import 'configuration_values.dart';

part 'account_entries.freezed.dart';

/// 配置材料里 ACP 接入目录的固定读取结果。
///
/// 它来自配置领域既有读取作用域的固定原目标（材料引用 + 分页行），不是整份设置/模型
/// 快照，也不是第二份 canonical：读取只交回调用方，不写回配置投影。
///
/// [revision] 与 [updatedAt] 取自捕获时与材料引用同一快照的配置 header，分别是 Settings
/// 业务版本与当时的更新时间；材料引用版本不是 Settings revision，SDK 也不为目录时间补造
/// 值。每行只有稳定 ID、名称、类型化 provider 与该设置版本捕获的连接代次——连接代次由
/// ACP 身份所有者提供，不从这里推导，也不含 program/args/版本或自定义路径。
///
/// [origin] 与 [reference] 是成功读取时冻结的读取来源：原 owner（ownerEpoch +
/// incarnation）与材料引用（entry + revision），与 [revision]/[updatedAt] 取自同一个
/// header 快照。调用方据此判断这份材料是否仍属于当前 owner；未完成读取用 null 表达，
/// 不构造零值 sentinel。材料引用版本与 Settings 业务版本是不同事实，不要求相等。
@Freezed(toStringOverride: false)
abstract class AcpAccountDirectory with _$AcpAccountDirectory {
  const AcpAccountDirectory._();

  const factory AcpAccountDirectory({
    required ProductReadOrigin origin,
    required ConfigurationReadRef reference,
    required int revision,
    required int updatedAt,
    required List<AcpAccountSettings> accounts,
  }) = _AcpAccountDirectory;

  bool get isEmpty => accounts.isEmpty;

  AcpAccountSettings? account(String accountId) {
    for (final account in accounts) {
      if (account.accountId == accountId) return account;
    }
    return null;
  }
}

/// “添加账号/切换模板”的模板选择项。
@Freezed(toStringOverride: false)
sealed class AccountTemplateChoice with _$AccountTemplateChoice {
  const AccountTemplateChoice._();

  /// Native 模型账号模板（HTTP 协议、模型目录、凭据语义）。
  const factory AccountTemplateChoice.native(AccountTemplate template) =
      NativeAccountTemplateChoice;

  /// ACP 接入模板（固定受管发行与认证流程）。
  const factory AccountTemplateChoice.acp(AcpAccountTemplate template) =
      AcpAccountTemplateChoice;

  /// 稳定显示名。
  String get displayName => switch (this) {
    NativeAccountTemplateChoice(:final template) => template.displayName,
    AcpAccountTemplateChoice(:final template) => template.displayName,
  };

  /// 一句话说明；ACP 分支用它表达“无需 API key”。
  String get description => switch (this) {
    NativeAccountTemplateChoice(:final template) => template.description ?? '',
    AcpAccountTemplateChoice(:final template) => template.description,
  };

  /// 品牌图标键；缺失时由展示层回退到首字母。
  String? get iconKey => switch (this) {
    NativeAccountTemplateChoice(:final template) => template.iconKey,
    AcpAccountTemplateChoice(:final template) =>
      template.iconKey.isEmpty ? null : template.iconKey,
  };

  /// 是否为 ACP 接入模板。
  bool get isAcp => this is AcpAccountTemplateChoice;

  /// ACP 模板的协议身份；Native 模板不适用时为 null。
  AcpProvider? get acpProvider => switch (this) {
    AcpAccountTemplateChoice(:final template) => template.provider,
    NativeAccountTemplateChoice() => null,
  };
}

/// 账号列表条目：Native 模型账号或 ACP 接入。
@Freezed(toStringOverride: false)
sealed class AccountEntryView with _$AccountEntryView {
  const AccountEntryView._();

  const factory AccountEntryView.native(AccountConfiguration account) =
      NativeAccountEntryView;

  const factory AccountEntryView.acp({
    required AcpAccountSettings account,

    /// 该接入的认证观察状态；没有匹配条目时为未检查，绝不推断为成功。
    required AcpAuthState auth,

    /// 目录里仍可解析的模板；目录未加载时为 null，展示层据此省略品牌与安装说明。
    required AcpAccountTemplate? template,
  }) = AcpAccountEntryView;

  String get id => switch (this) {
    NativeAccountEntryView(:final account) => account.accountId,
    AcpAccountEntryView(:final account) => account.accountId,
  };

  String get name => switch (this) {
    NativeAccountEntryView(:final account) => account.name,
    AcpAccountEntryView(:final account) => account.name,
  };

  bool get isAcp => this is AcpAccountEntryView;
}

/// 账号面板的聚合投影：Native 账号在前、ACP 接入随后，各自保持 canonical 顺序。
///
/// 这里的 ACP 认证条目只在连接身份（accountId + connectionRevision）匹配时套用；
/// 受管启动配置由产品固定发行决定，不是账号配置的一部分。
@Freezed(toStringOverride: false)
abstract class AccountDirectoryView with _$AccountDirectoryView {
  const AccountDirectoryView._();

  const factory AccountDirectoryView({
    required List<AccountEntryView> entries,
    required List<AccountTemplateChoice> templates,

    /// 该投影套用的 `acpAuth` 水位；0 表示没有可用的认证观察。
    required int authRevision,
  }) = _AccountDirectoryView;

  /// 由 configuration canonical 值与 ACP 资源快照组合出目录。
  ///
  /// [acpAccounts] 是 Settings 快照的 canonical 读取结果（不是调用方自建的列表）；
  /// 未完成固定读取时为 null：此时不产生 ACP 条目，也不制造「空目录」事实或第二份
  /// canonical；已给出的目录按原顺序逐条投影，认证默认仍是未检查。
  /// [auth] 是可选的 `acpAuth` 快照。这里不做任何读取、不启动命令。
  static AccountDirectoryView from({
    AcpAccountDirectory? acpAccounts,
    List<AccountConfiguration> nativeAccounts = const [],
    List<AccountTemplate> nativeTemplates = const [],
    AcpAccountCatalog acpCatalog = AcpAccountCatalog.empty,
    AcpAuthSnapshot? auth,
  }) {
    final snapshot = auth;
    final directory = acpAccounts;
    return AccountDirectoryView(
      entries: <AccountEntryView>[
        for (final account in nativeAccounts) AccountEntryView.native(account),
        for (final account
            in directory?.accounts ?? const <AcpAccountSettings>[])
          AccountEntryView.acp(
            account: account,
            auth:
                snapshot?.stateOf(
                  account.accountId,
                  connectionRevision: account.connectionRevision,
                ) ??
                const AcpAuthState.unchecked(),
            template: acpCatalog.template(account.provider),
          ),
      ],
      templates: <AccountTemplateChoice>[
        for (final template in nativeTemplates)
          AccountTemplateChoice.native(template),
        for (final template in acpCatalog.templates)
          AccountTemplateChoice.acp(template),
      ],
      authRevision: snapshot?.revision ?? 0,
    );
  }

  List<NativeAccountEntryView> get nativeEntries =>
      entries.whereType<NativeAccountEntryView>().toList(growable: false);

  List<AcpAccountEntryView> get acpEntries =>
      entries.whereType<AcpAccountEntryView>().toList(growable: false);

  List<AccountTemplateChoice> get acpTemplates =>
      templates.where((choice) => choice.isAcp).toList(growable: false);

  AccountEntryView? entry(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// 该账号身份是否已被任一分支使用；保存前用于稳定 ID 分配。
  bool hasId(String id) => entry(id) != null;

  /// 在给定基础 ID 上分配一个未被占用的稳定账号 ID。
  String suggestId(String base) {
    if (!hasId(base)) return base;
    for (var index = 2; ; index += 1) {
      final candidate = '$base-$index';
      if (!hasId(candidate)) return candidate;
    }
  }

  bool get isEmpty => entries.isEmpty;
}
