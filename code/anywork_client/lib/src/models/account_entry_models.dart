/// 同一“添加账号”入口下的 typed 分支聚合。
///
/// Native 模型账号与 ACP 接入共享产品入口，但各自保留封闭语义：模板选择与账号条目
/// 都以 sealed 分支表达，调用方按分支处理，不按显示名、模板 ID 或 baseUrl 猜协议。
library;

import 'account_models.dart';
import 'acp_models.dart';
import 'collection_equality.dart';
import 'collection_extensions.dart';

/// “添加账号/切换模板”的模板选择项。
sealed class AccountTemplateChoice {
  const AccountTemplateChoice();

  /// 稳定显示名。
  String get displayName;

  /// 一句话说明；ACP 分支用它表达“无需 API key”。
  String get description;

  /// 品牌图标键；缺失时由展示层回退到首字母。
  String? get iconKey;

  /// 是否为 ACP 接入模板。
  bool get isAcp;

  /// ACP 模板的协议身份；Native 模板不适用时为 null。
  AcpProviderView? get acpProvider;

  /// ACP 模板默认 argv；Native 模板为空。
  List<String> get defaultArgs;
}

/// Native 模型账号模板（HTTP 协议、模型目录、凭据语义）。
final class NativeAccountTemplateChoice extends AccountTemplateChoice {
  const NativeAccountTemplateChoice(this.template);

  final AccountTemplateView template;

  String get id => template.id;

  @override
  String get displayName => template.displayName;

  @override
  String get description => template.description;

  @override
  String? get iconKey => template.iconKey;

  @override
  bool get isAcp => false;

  @override
  AcpProviderView? get acpProvider => null;

  @override
  List<String> get defaultArgs => const [];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeAccountTemplateChoice && other.template.id == template.id;

  @override
  int get hashCode => Object.hash(0x0301, template.id);
}

/// ACP 接入模板（官方 server 程序与认证流程）。
final class AcpAccountTemplateChoice extends AccountTemplateChoice {
  const AcpAccountTemplateChoice(this.template);

  final AcpAccountTemplateView template;

  @override
  String get displayName => template.displayName;

  @override
  String get description => template.description;

  @override
  String? get iconKey => template.iconKey.isEmpty ? null : template.iconKey;

  @override
  bool get isAcp => true;

  @override
  AcpProviderView get acpProvider => template.provider;

  @override
  List<String> get defaultArgs => template.defaultArgs;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountTemplateChoice && other.template == template;

  @override
  int get hashCode => Object.hash(0x0302, template);
}

/// 账号列表条目：Native 模型账号或 ACP 接入。
sealed class AccountEntryView {
  const AccountEntryView();

  String get id;

  String get name;

  bool get isAcp;
}

final class NativeAccountEntryView extends AccountEntryView {
  const NativeAccountEntryView(this.account);

  final AccountSettingsView account;

  @override
  String get id => account.id;

  @override
  String get name => account.name;

  @override
  bool get isAcp => false;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NativeAccountEntryView && identical(other.account, account);

  @override
  int get hashCode => Object.hash(0x0303, identityHashCode(account));
}

final class AcpAccountEntryView extends AccountEntryView {
  const AcpAccountEntryView({
    required this.account,
    required this.auth,
    this.template,
  });

  final AcpAccountSettingsView account;

  /// 该接入的认证观察状态；没有条目时为 `Unchecked`，绝不推断为成功。
  final AcpAuthStateView auth;

  /// 目录里仍可解析的模板；目录未加载时为 null，展示层据此省略品牌与安装说明。
  final AcpAccountTemplateView? template;

  @override
  String get id => account.accountId;

  @override
  String get name => account.name;

  @override
  bool get isAcp => true;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AcpAccountEntryView &&
          other.account == account &&
          other.auth == auth &&
          other.template == template;

  @override
  int get hashCode => Object.hash(0x0304, account, auth, template);
}

/// 账号面板的聚合投影：Native 账号在前、ACP 接入随后，各自保持 canonical 顺序。
///
/// 这里只做 typed 合并与查找，不复制协议语义：Native 的模型、默认账号与用量仍由
/// Native 路径拥有，ACP 的认证状态只来自 `acpAuth` snapshot。
class AccountDirectoryView {
  AccountDirectoryView({
    required List<AccountEntryView> entries,
    required List<AccountTemplateChoice> templates,
    this.authRevision = 0,
  }) : entries = List.unmodifiable(entries),
       templates = List.unmodifiable(templates);

  factory AccountDirectoryView.from({
    List<AccountSettingsView> nativeAccounts = const [],
    List<AcpAccountSettingsView> acpAccounts = const [],
    AccountCatalogView nativeCatalog = const AccountCatalogView.empty(),
    AcpAccountCatalogView acpCatalog = const AcpAccountCatalogView.empty(),
    AcpAuthSnapshotView auth = const AcpAuthSnapshotView.empty(),
  }) {
    return AccountDirectoryView(
      entries: [
        for (final account in nativeAccounts) NativeAccountEntryView(account),
        for (final account in acpAccounts)
          AcpAccountEntryView(
            account: account,
            // 认证观察只在连接身份也匹配时套用；旧 program/args 的结果视为未检查。
            auth: auth.stateOf(
              account.accountId,
              connectionRevision: account.connectionRevision,
            ),
            template: acpCatalog.template(account.provider),
          ),
      ],
      templates: [
        for (final template in nativeCatalog.templates)
          NativeAccountTemplateChoice(template),
        for (final template in acpCatalog.templates)
          AcpAccountTemplateChoice(template),
      ],
      authRevision: auth.revision,
    );
  }

  final List<AccountEntryView> entries;
  final List<AccountTemplateChoice> templates;
  final int authRevision;

  List<NativeAccountEntryView> get nativeEntries =>
      entries.whereType<NativeAccountEntryView>().toList(growable: false);

  List<AcpAccountEntryView> get acpEntries =>
      entries.whereType<AcpAccountEntryView>().toList(growable: false);

  List<AccountTemplateChoice> get acpTemplates =>
      templates.where((choice) => choice.isAcp).toList(growable: false);

  AccountEntryView? entry(String id) =>
      entries.where((entry) => entry.id == id).firstOrNull;

  /// 该账号身份是否已被任一分支使用；保存前用于稳定 ID 分配。
  bool hasId(String id) => entries.any((entry) => entry.id == id);

  /// 在给定基础 ID 上分配一个未被占用的稳定账号 ID。
  String suggestId(String base) {
    if (!hasId(base)) return base;
    for (var index = 2; ; index += 1) {
      final candidate = '$base-$index';
      if (!hasId(candidate)) return candidate;
    }
  }

  bool get isEmpty => entries.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountDirectoryView &&
          authRevision == other.authRevision &&
          listEquals(entries, other.entries) &&
          listEquals(templates, other.templates);

  @override
  int get hashCode => Object.hash(
    authRevision,
    Object.hashAll(entries),
    Object.hashAll(templates),
  );
}
