import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../accounts_views.dart';
import 'account_preview_fixtures.dart';

// Sizes below are available MAIN CONTENT AREA, excluding the settings sidebar.
// First Web preview still compiles Flutter. No application graph is initialized.
@Preview(
  name: 'List / 1240 wide / mixed billing',
  group: 'Accounts · List',
  size: Size(1240, 920),
)
Widget accountsListWidePreview() => _list(AccountPreviewFixtures.list);

@Preview(
  name: 'List / 390 narrow',
  group: 'Accounts · List',
  size: Size(390, 844),
)
Widget accountsListNarrowPreview() => _list(AccountPreviewFixtures.list);

@Preview(
  name: 'List / long names / text 1.3',
  group: 'Accounts · List',
  size: Size(780, 900),
)
Widget accountsListLargeTextPreview() => _list(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        name: '用于海外与研发环境的长账号名称 · 合成多币种余额与精确金额',
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
Widget accountsListLoadingPreview() =>
    _list(const AccountsListPresentation(phase: AccountListPhase.loading));

@Preview(name: 'List / empty', group: 'Accounts · List', size: Size(780, 600))
Widget accountsListEmptyPreview() => _list(const AccountsListPresentation());

@Preview(
  name: 'List / no search results',
  group: 'Accounts · List',
  size: Size(780, 600),
)
Widget accountsListNoSearchPreview() => _list(
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
Widget accountsListRefreshingPreview() => _list(
  AccountPreviewFixtures.list.copyWith(
    refreshing: true,
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        usage: AccountPreviewFixtures.balance.copyWith(
          phase: AccountQueryPhase.loading,
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
Widget accountsListHealthPreview() => _list(
  AccountPreviewFixtures.list.copyWith(
    rows: [
      AccountPreviewFixtures.list.rows.first.copyWith(
        name: '凭据缺失',
        usage: const AccountUsagePresentation(
          phase: AccountQueryPhase.missingCredential,
        ),
      ),
      AccountPreviewFixtures.list.rows.first.copyWith(
        key: const AccountDisplayKey(
          kind: AccountKind.native,
          id: 'synthetic-insufficient',
        ),
        name: '余额不足',
        usage: AccountPreviewFixtures.balance.copyWith(
          balanceHealth: AccountBalanceHealth.insufficient,
          balances: const [
            AccountCurrencyBalance(currency: 'CNY', total: '-0.0001'),
          ],
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
Widget accountsListFailurePreview() => _list(
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
Widget accountDetailsWidePreview() => _details(AccountPreviewFixtures.details);

@Preview(
  name: 'Details / 390 narrow',
  group: 'Accounts · Detail',
  size: Size(390, 844),
)
Widget accountDetailsNarrowPreview() =>
    _details(AccountPreviewFixtures.details);

@Preview(
  name: 'Details / long name / text 1.3',
  group: 'Accounts · Detail',
  size: Size(720, 1000),
)
Widget accountDetailsLargeTextPreview() => _details(
  AccountPreviewFixtures.details.copyWith(name: '研发专用长账号名称 · 不截断的详情标题'),
  textScale: 1.3,
);

@Preview(
  name: 'Details / subscription',
  group: 'Accounts · Detail',
  size: Size(1100, 1000),
)
Widget accountDetailsSubscriptionPreview() => _details(
  _withNative(
    AccountPreviewFixtures.details,
    usage: AccountPreviewFixtures.subscription,
    billing: const AccountBillingPresentation(
      effective: AccountBilling.subscription,
      billingKindOverride: AccountBilling.subscription,
      allowedOverrides: AccountPreviewFixtures.billingOverrides,
    ),
  ).copyWith(name: 'Zhipu Coding Plan', iconKey: 'zhipu'),
);

@Preview(
  name: 'Details / failed last-good / catalog retry',
  group: 'Accounts · Detail',
  size: Size(1100, 1100),
)
Widget accountDetailsFailurePreview() => _details(
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
Widget accountUsageFirstFailurePreview() => _host(
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
Widget accountDetailsAcpPreview() => _details(
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
    _nativeEditor(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / 390 narrow',
  group: 'Accounts · Editor',
  size: Size(390, 844),
)
Widget accountNativeEditorNarrowPreview() =>
    _nativeEditor(AccountPreviewFixtures.editor);

@Preview(
  name: 'Editor / Native / validation & failed save',
  group: 'Accounts · Editor',
  size: Size(800, 1100),
)
Widget accountNativeEditorInvalidPreview() => _nativeEditor(
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
Widget accountNativeEditorCreatePreview() => _nativeEditor(
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
Widget accountAcpEditorUnpreparedPreview() => _acpEditor(
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
    _acpEditor(AccountPreviewFixtures.acpEditor);

@Preview(
  name: 'Editor / ACP / login primary / save secondary',
  group: 'Accounts · Editor',
  size: Size(720, 900),
)
Widget accountAcpEditorLoginPreview() => _acpEditor(
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
Widget accountAcpEditorPreparedPreview() => _acpEditor(
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
Widget accountAcpEditorReadyPreview() => _acpEditor(
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
  name: 'Editor / ACP / failure recovery',
  group: 'Accounts · Editor',
  size: Size(720, 900),
)
Widget accountAcpEditorFailedPreview() => _acpEditor(
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
Widget accountModelExpandedPreview() => _host(
  (record) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      Card(
        child: AccountModelTile(
          value: AccountPreviewFixtures.model,
          actions: _modelActions(record),
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
Widget accountCompactInvalidPreview() => _host(
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
Widget accountAcpVerifyPreview() => _host(
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
Widget accountTemplatePickerPreview() => _host(
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
Widget accountUnsavedDialogPreview() => _host(
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
Widget accountDeleteDialogPreview() => _host(
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

Widget _host(
  Widget Function(ValueChanged<String> record) builder, {
  required Object scenarioIdentity,
  double textScale = 1,
}) => _PreviewHost(
  builder: builder,
  scenarioIdentity: scenarioIdentity,
  textScale: textScale,
);
Widget _list(AccountsListPresentation value, {double textScale = 1}) => _host(
  (record) => _ListScenario(initial: value, record: record),
  scenarioIdentity: value,
  textScale: textScale,
);
Widget _nativeEditor(
  NativeAccountEditorPresentation value, {
  double textScale = 1,
}) => _host(
  (record) => _NativeEditorScenario(initial: value, record: record),
  scenarioIdentity: value,
  textScale: textScale,
);
Widget _acpEditor(AcpAccountEditorPresentation value) => _host(
  (record) => _AcpEditorScenario(initial: value, record: record),
  scenarioIdentity: value,
);
Widget _details(AccountDetailsPresentation value, {double textScale = 1}) =>
    _host(
      (record) => AccountDetailsView(
        value: value,
        onBack: () => record('back'),
        onEdit: () => record('edit'),
        onDelete: () => record('delete'),
        onSetDefault: () => record('set default'),
        onRefreshUsage: () => record('refresh usage'),
        onBillingChanged: (billing) => record('billing: ${billing.name}'),
        onResetBilling: () => record('reset billing'),
        onSyncModels: () => record('sync models'),
        modelActions: _modelActions(record),
        onAcpAction: (action) => record('ACP: ${action.name}'),
        onLoginMethodChanged: (id) => record('login method: $id'),
        onRetry: () => record('retry detail'),
      ),
      scenarioIdentity: value,
      textScale: textScale,
    );

AccountModelActions _modelActions(ValueChanged<String> record) =>
    AccountModelActions(
      onEnabledChanged: (key, enabled) =>
          record('${key.modelId}: enabled $enabled'),
      onConnectionChanged: (key, connection) =>
          record('${key.modelId}: ${connection.name}'),
      onCompactChanged: (key, raw) => record('${key.modelId}: threshold $raw'),
      onAction: (key, action) => record('${key.modelId}: ${action.name}'),
    );

class _PreviewHost extends StatefulWidget {
  const _PreviewHost({
    required this.builder,
    required this.scenarioIdentity,
    required this.textScale,
  });
  final Widget Function(ValueChanged<String>) builder;

  /// Immutable fixture value or stable component label, never callback identity.
  final Object scenarioIdentity;
  final double textScale;
  @override
  State<_PreviewHost> createState() => _PreviewHostState();
}

class _PreviewHostState extends State<_PreviewHost> {
  static const _initialAction =
      'Synthetic data · actions are recorded locally only';
  String _lastAction = _initialAction;

  @override
  void didUpdateWidget(covariant _PreviewHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scenarioIdentity != widget.scenarioIdentity ||
        oldWidget.textScale != widget.textScale) {
      _lastAction = _initialAction;
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('zh'),
    theme: pureStudioTheme(locale: const Locale('zh')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(widget.textScale)),
      // MaterialApp's builder context is below the production Theme. Reset the
      // Previewer's explicit ListTileTheme rather than inheriting its dark tiles.
      child: ListTileTheme(
        data: Theme.of(context).listTileTheme,
        child: child!,
      ),
    ),
    home: Scaffold(
      body: widget.builder((action) => setState(() => _lastAction = action)),
      bottomNavigationBar: Material(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            _lastAction,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11),
          ),
        ),
      ),
    ),
  );
}

class _ListScenario extends StatefulWidget {
  const _ListScenario({required this.initial, required this.record});
  final AccountsListPresentation initial;
  final ValueChanged<String> record;
  @override
  State<_ListScenario> createState() => _ListScenarioState();
}

class _ListScenarioState extends State<_ListScenario> {
  late String _search = widget.initial.search;

  @override
  void didUpdateWidget(covariant _ListScenario oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _search = widget.initial.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.initial.rows
        .where((row) => row.name.toLowerCase().contains(_search.toLowerCase()))
        .toList();
    return AccountsListView(
      value: widget.initial.copyWith(
        search: _search,
        rows: rows,
        searchHasNoResults: _search.isNotEmpty && rows.isEmpty,
      ),
      onSearchChanged: (raw) => setState(() => _search = raw),
      onAdd: () => widget.record('add account'),
      onRefreshAll: () => widget.record('refresh all'),
      onOpen: (key) => widget.record('open: ${key.kind.name}/${key.id}'),
      onRowAction: (key, action) =>
          widget.record('${key.kind.name}/${key.id}: ${action.name}'),
      onRetry: () => widget.record('retry list'),
    );
  }
}

class _NativeEditorScenario extends StatefulWidget {
  const _NativeEditorScenario({required this.initial, required this.record});
  final NativeAccountEditorPresentation initial;
  final ValueChanged<String> record;
  @override
  State<_NativeEditorScenario> createState() => _NativeEditorScenarioState();
}

class _NativeEditorScenarioState extends State<_NativeEditorScenario> {
  late NativeAccountEditorPresentation _value = widget.initial;

  @override
  void didUpdateWidget(covariant _NativeEditorScenario oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) => NativeAccountEditorView(
    value: _value,
    onFieldChanged: (field, raw) => setState(() {
      _value = switch (field) {
        NativeAccountField.name => _value.copyWith(
          name: _value.name.copyWith(raw: raw),
        ),
        NativeAccountField.endpoint => _value.copyWith(
          endpoint: _value.endpoint.copyWith(raw: raw),
        ),
        NativeAccountField.credential => _value.copyWith(
          credential: _value.credential.copyWith(raw: raw),
        ),
      };
    }),
    onTemplateChanged: (key) =>
        widget.record('template: ${key.kind.name}/${key.id}'),
    onBillingChanged: (billing) => widget.record('billing: ${billing.name}'),
    onResetBilling: () => widget.record('reset billing'),
    onAddModel: () => widget.record('add manual model'),
    onManualModelFieldChanged: (key, field, raw) =>
        widget.record('$key: ${field.name} $raw'),
    onManualModelConnectionChanged: (key, connection) =>
        widget.record('$key: ${connection.name}'),
    onManualModelWireApiChanged: (key, wireApi) =>
        widget.record('$key: ${wireApi.name}'),
    onRemoveManualModel: (key) => widget.record('remove manual: $key'),
    modelActions: _modelActions(widget.record),
    onSave: () => widget.record('save (not persisted)'),
    onCancel: () => widget.record('cancel editor'),
  );
}

class _AcpEditorScenario extends StatefulWidget {
  const _AcpEditorScenario({required this.initial, required this.record});
  final AcpAccountEditorPresentation initial;
  final ValueChanged<String> record;
  @override
  State<_AcpEditorScenario> createState() => _AcpEditorScenarioState();
}

class _AcpEditorScenarioState extends State<_AcpEditorScenario> {
  late AcpAccountEditorPresentation _value = widget.initial;

  @override
  void didUpdateWidget(covariant _AcpEditorScenario oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initial != widget.initial) {
      _value = widget.initial;
    }
  }

  @override
  Widget build(BuildContext context) => AcpAccountEditorView(
    value: _value,
    onNameChanged: (raw) => setState(
      () => _value = _value.copyWith(name: _value.name.copyWith(raw: raw)),
    ),
    onAction: (action) => widget.record('ACP: ${action.name}'),
    onLoginMethodChanged: (method) => widget.record('method: $method'),
    onSave: () => widget.record('save ACP (not persisted)'),
    onCancel: () => widget.record('cancel ACP editor'),
  );
}
