import 'package:anywork_client/acp.dart';
import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart' show AccountTemplate;

/// 统一“添加账号”入口的 typed 选项集合。
///
/// Native 模型账号模板与 ACP 接入模板来自两个 typed 目录，选择结果以 sealed
/// [AccountTemplateChoice] 返回，调用方按分支重建对应草稿——不按模板 ID 或显示名猜协议。
/// 这里只做合并与查找，不推断凭据、安装或认证语义。
List<AccountTemplateChoice> accountTemplateChoices({
  required List<AccountTemplate> native,
  required AcpAccountCatalog acp,
}) => [
  for (final template in native) AccountTemplateChoice.native(template),
  for (final template in acp.templates) AccountTemplateChoice.acp(template),
];

/// 选择器的稳定选项 token（Driver 键身份）。
///
/// Native 用模板 id；ACP 用 provider 的稳定身份值，不按显示名生成。
String accountTemplateChoiceToken(AccountTemplateChoice choice) =>
    switch (choice) {
      NativeAccountTemplateChoice(:final template) => template.id,
      AcpAccountTemplateChoice(:final template) =>
        'acp-${template.provider.name}',
    };

/// 在目录里解析某个接入的模板；目录未加载或该 provider 无模板时为 null。
///
/// 缺失模板不是“可用的默认模板”：调用方据此报告模板不可用，而不是合成发行事实。
AcpAccountTemplate? acpAccountTemplate(
  AcpAccountCatalog? catalog,
  AcpProvider provider,
) => catalog?.template(provider);
