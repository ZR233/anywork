import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../accounts_views.dart';
import 'account_preview_fixtures.dart';
import 'account_preview_host.dart';
import 'account_template_preview_fixtures.dart';

// Sizes below are available MAIN CONTENT AREA, excluding the settings sidebar.
// First Web preview still compiles Flutter. No application graph is initialized.
@Preview(
  name: 'List / 1240 wide / mixed billing',
  group: 'Accounts · List',
  size: Size(1240, 920),
)
Widget accountsListWidePreview() =>
    accountListPreview(AccountPreviewFixtures.list);

@Preview(
  name: 'List / concept comparison / 960 main area',
  group: 'Accounts · List',
  size: Size(960, 920),
)
Widget accountsListConceptWidePreview() =>
    accountListPreview(AccountPreviewFixtures.list);

@Preview(
  name: 'List / 390 narrow',
  group: 'Accounts · List',
  size: Size(390, 844),
)
Widget accountsListNarrowPreview() =>
    accountListPreview(AccountPreviewFixtures.list);

@Preview(
  name: 'List / concept comparison / 408 main area',
  group: 'Accounts · List',
  size: Size(408, 844),
)
Widget accountsListConceptNarrowPreview() =>
    accountListPreview(AccountPreviewFixtures.list);

@Preview(
  name: 'List / English summary / 960 main area',
  group: 'Accounts · List',
  size: Size(960, 920),
)
Widget accountsListEnglishSummaryWidePreview() => accountListPreview(
  _englishSummaryListFixture(),
  locale: const Locale('en'),
);

@Preview(
  name: 'List / English summary / 408 main area',
  group: 'Accounts · List',
  size: Size(408, 844),
)
Widget accountsListEnglishSummaryNarrowPreview() => accountListPreview(
  _englishSummaryListFixture(),
  locale: const Locale('en'),
);

@Preview(
  name: 'List / long mixed last-good / 408 main area / 1.3',
  group: 'Accounts · List',
  size: Size(408, 1000),
)
Widget accountsListLongMixedLastGoodNarrowPreview() => accountListPreview(
  AccountsListPresentation(
    canRefresh: true,
    rows: [AccountPreviewFixtures.stackedLastGoodRow],
  ),
  textScale: 1.3,
);

@Preview(
  name: 'List / long names / text 1.3',
  group: 'Accounts · List',
  size: Size(780, 900),
)
Widget accountsListLargeTextPreview() => accountListPreview(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        name: '用于海外与研发环境的长账号名称 · 合成多币种余额与精确金额',
        content: const AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountPreviewFixtures.balance,
        ),
      ),
    ],
  ),
  textScale: 1.3,
);

@Preview(
  name: 'List / first loading',
  group: 'Accounts · List',
  size: Size(780, 600),
)
Widget accountsListLoadingPreview() => accountListPreview(
  const AccountsListPresentation(phase: AccountListPhase.loading),
);

@Preview(name: 'List / empty', group: 'Accounts · List', size: Size(780, 600))
Widget accountsListEmptyPreview() =>
    accountListPreview(const AccountsListPresentation());

@Preview(
  name: 'List / no search results',
  group: 'Accounts · List',
  size: Size(780, 600),
)
Widget accountsListNoSearchPreview() => accountListPreview(
  const AccountsListPresentation(
    search: 'no-such-account',
    searchHasNoResults: true,
  ),
);

@Preview(
  name: 'List / loading with data',
  group: 'Accounts · List',
  size: Size(1240, 700),
)
Widget accountsListRefreshingPreview() => accountListPreview(
  AccountPreviewFixtures.list.copyWith(
    refreshing: true,
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountPreviewFixtures.balance.copyWith(
            phase: AccountQueryPhase.loading,
          ),
        ),
      ),
    ],
  ),
);

@Preview(
  name: 'List / credentials / insufficient',
  group: 'Accounts · List',
  size: Size(1240, 700),
)
Widget accountsListHealthPreview() => accountListPreview(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        name: '凭据缺失',
        content: const AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountUsagePresentation(
            phase: AccountQueryPhase.missingCredential,
          ),
        ),
      ),
      AccountPreviewFixtures.list.rows.first.copyWith(
        key: const AccountDisplayKey(
          kind: AccountKind.native,
          id: 'synthetic-insufficient',
        ),
        name: '余额不足',
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountPreviewFixtures.balance.copyWith(
            balanceHealth: AccountBalanceHealth.insufficient,
            balances: const [
              AccountCurrencyBalance(currency: 'CNY', total: '-0.0001'),
            ],
          ),
        ),
      ),
    ],
  ),
);

@Preview(
  name: 'List / initial failure',
  group: 'Accounts · List',
  size: Size(780, 600),
)
Widget accountsListFailurePreview() => accountListPreview(
  const AccountsListPresentation(
    phase: AccountListPhase.failed,
    error: '合成读取错误：账号列表暂时不可用。',
  ),
);

@Preview(
  name: 'Details / full main area',
  group: 'Accounts · Detail',
  size: Size(1180, 1100),
)
Widget accountDetailsWidePreview() =>
    accountDetailsPreviewHost(AccountPreviewFixtures.details);

@Preview(
  name: 'Details / concept comparison / 960 main area',
  group: 'Accounts · Detail',
  size: Size(960, 1100),
)
Widget accountDetailsConceptWidePreview() =>
    accountDetailsPreviewHost(AccountPreviewFixtures.conceptDetails);

@Preview(
  name: 'Details / 390 narrow',
  group: 'Accounts · Detail',
  size: Size(390, 844),
)
Widget accountDetailsNarrowPreview() =>
    accountDetailsPreviewHost(AccountPreviewFixtures.details);

@Preview(
  name: 'Details / concept comparison / 408 main area',
  group: 'Accounts · Detail',
  size: Size(408, 900),
)
Widget accountDetailsConceptNarrowPreview() =>
    accountDetailsPreviewHost(AccountPreviewFixtures.conceptDetails);

@Preview(
  name: 'Details / long name / text 1.3',
  group: 'Accounts · Detail',
  size: Size(720, 1000),
)
Widget accountDetailsLargeTextPreview() => accountDetailsPreviewHost(
  AccountPreviewFixtures.details.copyWith(name: '研发专用长账号名称 · 不截断的详情标题'),
  textScale: 1.3,
);

@Preview(
  name: 'Details / subscription',
  group: 'Accounts · Detail',
  size: Size(1100, 1000),
)
Widget accountDetailsSubscriptionPreview() => accountDetailsPreviewHost(
  _withNative(
    AccountTemplatePreviewFixtures.details('zhipu-coding-plan'),
    usage: AccountPreviewFixtures.subscription,
    billing: const AccountBillingPresentation(
      effective: AccountBilling.subscription,
      billingKindOverride: AccountBilling.subscription,
      allowedOverrides: AccountPreviewFixtures.billingOverrides,
    ),
  ),
);

@Preview(
  name: 'List / multi-currency / full decimal precision',
  group: 'Accounts · List',
  size: Size(1240, 700),
)
Widget accountsListMultiCurrencyPreview() => accountListPreview(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        content: const AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountPreviewFixtures.balance,
        ),
      ),
    ],
  ),
);

@Preview(
  name: 'List / failed last-good / retry',
  group: 'Accounts · List',
  size: Size(1240, 700),
)
Widget accountsListLastGoodPreview() => accountListPreview(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        content: AccountRowContent.native(
          billing: AccountBilling.metered,
          usage: AccountPreviewFixtures.balance.copyWith(
            phase: AccountQueryPhase.failed,
            canRetry: true,
            error: '合成网络错误，请重试。',
          ),
        ),
      ),
    ],
  ),
);

@Preview(
  name: 'Details / failed last-good / catalog retry',
  group: 'Accounts · Detail',
  size: Size(1100, 1100),
)
Widget accountDetailsFailurePreview() => accountDetailsPreviewHost(
  _withNative(
    AccountPreviewFixtures.details,
    usage: AccountPreviewFixtures.balance.copyWith(
      phase: AccountQueryPhase.failed,
      canRetry: true,
      error: '合成超时：最近成功数据仍然可用。',
    ),
    catalog: AccountPreviewFixtures.catalog.copyWith(
      error: '同步失败；保留最近目录与手动模型。',
      canRetry: true,
    ),
  ),
);

@Preview(
  name: 'Usage / first failure / no last-good',
  group: 'Accounts · Components',
  size: Size(640, 400),
)
Widget accountUsageFirstFailurePreview() => accountPreviewHost(
  (record) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      AccountUsageView(
        value: const AccountUsagePresentation(
          phase: AccountQueryPhase.failed,
          hasLastGood: false,
          canRetry: true,
          error: '合成查询超时，尚无成功查询记录。',
        ),
        onRetry: () => record('retry first usage query'),
      ),
    ],
  ),
  scenarioIdentity: 'usage-first-failure',
);

@Preview(
  name: 'Details / ACP login methods',
  group: 'Accounts · Detail',
  size: Size(800, 900),
)
Widget accountDetailsAcpPreview() => accountDetailsPreviewHost(
  AccountDetailsPresentation(
    key: AccountPreviewFixtures.acpKey,
    name: '官方 ACP 接入',
    content: const AccountDetailsContent.acp(AccountPreviewFixtures.acp),
    canEdit: true,
    canDelete: true,
  ),
);

@Preview(
  name: 'Editor / Native / existing credential',
  group: 'Accounts · Editor',
  size: Size(900, 1100),
)
Widget accountNativeEditorPreview() =>
    accountNativeEditorPreviewHost(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / concept comparison / 960 main area',
  group: 'Accounts · Editor',
  size: Size(960, 1100),
)
Widget accountNativeEditorConceptWidePreview() =>
    accountNativeEditorPreviewHost(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / 390 narrow',
  group: 'Accounts · Editor',
  size: Size(390, 844),
)
Widget accountNativeEditorNarrowPreview() =>
    accountNativeEditorPreviewHost(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / concept comparison / 408 main area',
  group: 'Accounts · Editor',
  size: Size(408, 900),
)
Widget accountNativeEditorConceptNarrowPreview() =>
    accountNativeEditorPreviewHost(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / validation & failed save',
  group: 'Accounts · Editor',
  size: Size(800, 1100),
)
Widget accountNativeEditorInvalidPreview() => accountNativeEditorPreviewHost(
  AccountPreviewFixtures.editor.copyWith(
    error: '保存失败，原始输入保持不变。',
    endpoint: const AccountTextPresentation(
      raw: 'not-an-endpoint',
      error: '请输入有效的 HTTPS 地址。',
    ),
    canSave: false,
    manualModels: [
      AccountPreviewFixtures.editor.manualModels.first.copyWith(
        connection: AccountConnection.webSocket,
        error: '此协议不允许 Chat WebSocket。',
      ),
    ],
  ),
);

@Preview(
  name: 'Editor / Native / creating / text 1.3',
  group: 'Accounts · Editor',
  size: Size(720, 1000),
)
Widget accountNativeEditorCreatePreview() => accountNativeEditorPreviewHost(
  AccountPreviewFixtures.editor.copyWith(
    accountKey: null,
    canChangeTemplate: true,
    hasStoredCredential: false,
    name: const AccountTextPresentation(),
  ),
  textScale: 1.3,
);

@Preview(
  name: 'Editor / ACP / unprepared / prepare primary',
  group: 'Accounts · Editor',
  size: Size(800, 900),
)
Widget accountAcpEditorUnpreparedPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    preparation: const AcpAccountPresentation(
      phase: AcpPresentationPhase.idle,
      status: '尚未准备服务器',
      primaryAction: AcpAccountAction.prepare,
      availableActions: [
        AcpAccountAction.prepare,
        AcpAccountAction.openGuide,
        AcpAccountAction.openTerms,
      ],
    ),
  ),
);

@Preview(
  name: 'Editor / ACP / preparing',
  group: 'Accounts · Editor',
  size: Size(800, 900),
)
Widget accountAcpEditorPreparingPreview() =>
    accountAcpEditorPreviewHost(AccountPreviewFixtures.acpEditor);

@Preview(
  name: 'Editor / ACP / login primary / save secondary',
  group: 'Accounts · Editor',
  size: Size(720, 900),
)
Widget accountAcpEditorLoginPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    accountKey: AccountPreviewFixtures.acpKey,
    canSave: true,
    preparation: AccountPreviewFixtures.acp,
  ),
);

@Preview(
  name: 'Editor / ACP / claim prepared installation',
  group: 'Accounts · Editor',
  size: Size(390, 844),
)
Widget accountAcpEditorPreparedPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    preparation: const AcpAccountPresentation(
      phase: AcpPresentationPhase.ready,
      status: '另一个准备操作已完成，可显式使用已有安装。',
      primaryAction: AcpAccountAction.usePrepared,
      availableActions: [
        AcpAccountAction.usePrepared,
        AcpAccountAction.openTerms,
      ],
    ),
  ),
);

@Preview(
  name: 'Editor / ACP / save and connect',
  group: 'Accounts · Editor',
  size: Size(800, 900),
)
Widget accountAcpEditorReadyPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    canSave: true,
    saveAndConnect: true,
    preparation: const AcpAccountPresentation(
      phase: AcpPresentationPhase.ready,
      status: '服务器准备就绪',
      message: '准备不会保存账号，也不会自动登录。',
    ),
  ),
);

@Preview(
  name: 'Editor / ACP / 408 main area',
  group: 'Accounts · Editor',
  size: Size(408, 844),
)
Widget accountAcpEditorNarrowPreview() =>
    accountAcpEditorPreviewHost(AccountPreviewFixtures.acpEditor);

@Preview(
  name: 'Editor / ACP / failure recovery',
  group: 'Accounts · Editor',
  size: Size(720, 900),
)
Widget accountAcpEditorFailedPreview() => accountAcpEditorPreviewHost(
  AccountPreviewFixtures.acpEditor.copyWith(
    error: '下载失败，账号尚未保存。',
    preparation: const AcpAccountPresentation(
      phase: AcpPresentationPhase.failed,
      status: '准备失败',
      error: '合成网络错误',
      primaryAction: AcpAccountAction.prepare,
      availableActions: [AcpAccountAction.prepare, AcpAccountAction.openGuide],
    ),
  ),
);

@Preview(
  name: 'Model / expanded / prices / evaluations',
  group: 'Accounts · Components',
  size: Size(900, 1300),
)
Widget accountModelExpandedPreview() => accountPreviewHost(
  (record) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: AccountModelListItem(
          value: AccountPreviewFixtures.model,
          actions: accountPreviewModelActions(record),
          initiallyExpanded: true,
        ),
      ),
    ],
  ),
  scenarioIdentity: 'model-expanded',
);

@Preview(
  name: 'Model / invalid exact raw threshold / 390',
  group: 'Accounts · Components',
  size: Size(390, 900),
)
Widget accountCompactInvalidPreview() => accountPreviewHost(
  (record) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      AccountCompactView(
        value: const AccountCompactPresentation(
          raw: '12.5',
          overridden: true,
          automatic: '800000',
          effective: '475000',
          error: '请输入精确的正整数。',
          canEdit: true,
          canReset: true,
          canRetry: true,
        ),
        onChanged: (raw) => record('threshold: $raw'),
        onPreset: (percent) => record('preset: $percent'),
        onSave: () => record('save threshold'),
        onReset: () => record('reset threshold'),
        onRetry: () => record('retry threshold'),
      ),
    ],
  ),
  scenarioIdentity: 'compact-invalid',
);

@Preview(
  name: 'ACP / verification in progress / cancel',
  group: 'Accounts · Components',
  size: Size(720, 700),
)
Widget accountAcpVerifyPreview() => accountPreviewHost(
  (record) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      AcpAccountPanel(
        value: AccountPreviewFixtures.acp.copyWith(
          phase: AcpPresentationPhase.verifying,
          status: '验证登录中',
          primaryAction: null,
          loginMethods: const [],
          selectedLoginMethod: null,
          canSelectLoginMethod: false,
          availableActions: const [
            AcpAccountAction.cancelAuthentication,
            AcpAccountAction.openGuide,
          ],
        ),
        onAction: (action) => record(action.name),
        onLoginMethodChanged: record,
      ),
    ],
  ),
  scenarioIdentity: 'acp-verifying',
);

@Preview(
  name: 'Picker / 8 Native + Antigravity',
  group: 'Accounts · Components',
  size: Size(720, 800),
)
Widget accountTemplatePickerPreview() => accountPreviewHost(
  (record) => AccountTemplatePickerView(
    templates: AccountPreviewFixtures.templates,
    onSelected: (key) => record('template: ${key.kind.name}/${key.id}'),
    onCancel: () => record('cancel template'),
  ),
  scenarioIdentity: 'template-picker',
);

@Preview(
  name: 'Picker / 8 Native + Antigravity / 390',
  group: 'Accounts · Components',
  size: Size(390, 844),
)
Widget accountTemplatePickerNarrowPreview() => accountTemplatePickerPreview();

@Preview(
  name: 'Dialog / unsaved / failure preserves raw',
  group: 'Accounts · Components',
  size: Size(640, 480),
)
Widget accountUnsavedDialogPreview() => accountPreviewHost(
  (record) => Center(
    child: AccountUnsavedChangesDialog(
      error: '合成保存失败，请重试或继续编辑。',
      onChoice: (choice) => record(choice.name),
    ),
  ),
  scenarioIdentity: 'unsaved-dialog',
);

@Preview(
  name: 'Dialog / manual model deletion',
  group: 'Accounts · Components',
  size: Size(640, 480),
)
Widget accountDeleteDialogPreview() => accountPreviewHost(
  (record) => Center(
    child: AccountDeleteDialog(
      name: '合成手动模型',
      manualModel: true,
      onConfirm: () => record('confirm delete'),
      onCancel: () => record('cancel delete'),
    ),
  ),
  scenarioIdentity: 'delete-dialog',
);

AccountDetailsPresentation _withNative(
  AccountDetailsPresentation details, {
  AccountUsagePresentation? usage,
  AccountBillingPresentation? billing,
  AccountCatalogPresentation? catalog,
}) {
  final native = (details.content as NativeAccountDetailsContent).value;
  return details.copyWith(
    content: AccountDetailsContent.native(
      native.copyWith(
        usage: usage ?? native.usage,
        billing: billing ?? native.billing,
        catalog: catalog ?? native.catalog,
      ),
    ),
  );
}

AccountsListPresentation _englishSummaryListFixture() {
  final source = AccountPreviewFixtures.list;
  return source.copyWith(
    rows: [for (final row in source.rows) _withEnglishQuotaLabels(row)],
  );
}

AccountRowPresentation _withEnglishQuotaLabels(AccountRowPresentation row) {
  final content = row.content;
  if (content is! NativeAccountRowContent || content.usage.quotas.isEmpty) {
    return row;
  }
  return row.copyWith(
    content: AccountRowContent.native(
      billing: content.billing,
      usage: content.usage.copyWith(
        quotas: [
          for (final quota in content.usage.quotas)
            quota.copyWith(
              label: switch (quota.label) {
                '5 小时额度' => '5-hour quota',
                '每周额度' => 'Weekly quota',
                'MCP 额度' => 'MCP quota',
                _ => quota.label,
              },
            ),
        ],
      ),
      displayEndpoint: content.displayEndpoint,
    ),
  );
}
