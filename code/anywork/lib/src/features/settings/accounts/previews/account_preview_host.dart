import 'package:flutter/material.dart';

import '../../../../app/theme/material3_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../accounts_views.dart';

Widget accountPreviewHost(
  Widget Function(ValueChanged<String> record) builder, {
  required Object scenarioIdentity,
  double textScale = 1,
}) => _PreviewHost(
  builder: builder,
  scenarioIdentity: scenarioIdentity,
  textScale: textScale,
);
Widget accountListPreview(
  AccountsListPresentation value, {
  double textScale = 1,
}) => accountPreviewHost(
  (record) => _ListScenario(initial: value, record: record),
  scenarioIdentity: value,
  textScale: textScale,
);
Widget accountNativeEditorPreviewHost(
  NativeAccountEditorPresentation value, {
  double textScale = 1,
}) => accountPreviewHost(
  (record) => _NativeEditorScenario(initial: value, record: record),
  scenarioIdentity: value,
  textScale: textScale,
);
Widget accountAcpEditorPreviewHost(AcpAccountEditorPresentation value) =>
    accountPreviewHost(
      (record) => _AcpEditorScenario(initial: value, record: record),
      scenarioIdentity: value,
    );
Widget accountDetailsPreviewHost(
  AccountDetailsPresentation value, {
  double textScale = 1,
}) => accountPreviewHost(
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
    modelActions: accountPreviewModelActions(record),
    onAcpAction: (action) => record('ACP: ${action.name}'),
    onLoginMethodChanged: (id) => record('login method: $id'),
    onRetry: () => record('retry detail'),
  ),
  scenarioIdentity: value,
  textScale: textScale,
);

AccountModelActions accountPreviewModelActions(ValueChanged<String> record) =>
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
    modelActions: accountPreviewModelActions(widget.record),
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
