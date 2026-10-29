import 'dart:convert';

import 'package:anywork_client/studio_client.dart'
    show
        ModeDocument,
        ModeEditorLayout,
        ThreadModeDescriptorView,
        isValidModeId;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/routing/app_route.dart' show ModeWorkspaceRoute;
import '../../../app/theme/studio_tokens.dart';
import '../../../l10n/studio_l10n.dart';
import '../../../presentation/providers/client_provider.dart';
import '../../../presentation/providers/mode_catalog_store.dart';
import '../../settings/settings_scope.dart';
import '../mode_editor_dialogs.dart';
import '../mode_editor_support.dart';

/// 设置页「工作模式」tab：模式目录列表，点击进入全屏工作区。
///
/// 只承载目录浏览、搜索、新建与导入；编辑现场归工作区路由页所有。
class ModeCatalogTab extends ConsumerStatefulWidget {
  const ModeCatalogTab({super.key, required this.tabIndex});

  /// This tab's index in the settings shell. Display observation is gated on
  /// visibility, while the Client keeps the draft across navigation.
  final int tabIndex;

  @override
  ConsumerState<ModeCatalogTab> createState() => _ModeCatalogTabState();
}

class _ModeCatalogTabState extends ConsumerState<ModeCatalogTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final visible = ref.watch(settingsVisibleTabProvider) == widget.tabIndex;
    final client = ref.watch(anyworkClientProvider);
    final catalogState = visible
        ? ref.watch(modeCatalogStoreProvider)
        : client.modeCatalog.state;
    final editor = client.modeEditor.state;
    final catalog =
        catalogState.value?.modes ?? const <ThreadModeDescriptorView>[];
    final openId = editor.document?.definition.id;
    final filtered = _filteredCatalog(catalog);
    final builtIn = filtered.where((mode) => mode.readOnly).toList();
    final custom = filtered.where((mode) => !mode.readOnly).toList();

    return KeyedSubtree(
      key: ModeEditorKeys.page,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.modeEditorTitle,
                  style: context.text.titleSmall?.copyWith(
                    color: context.colors.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                key: ModeEditorKeys.importJson,
                tooltip: context.l10n.modeEditorImportJson,
                onPressed: () => _importMode(catalog),
                icon: const Icon(Icons.data_object, size: 18),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                key: ModeEditorKeys.create,
                onPressed: () => _createMode(catalog),
                icon: const Icon(Icons.add, size: 18),
                label: Text(context.l10n.modeEditorNewMode),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: ModeEditorKeys.search,
            decoration: InputDecoration(
              isDense: true,
              hintText: context.l10n.modeEditorSearchHint,
              prefixIcon: const Icon(Icons.search, size: 17),
            ),
            onChanged: (value) => setState(() => _query = value),
          ),
          const SizedBox(height: 8),
          _groupLabel(context, context.l10n.modeEditorBuiltInGroup),
          for (final mode in builtIn)
            _modeTile(context, mode, openId, editor.dirty),
          _groupLabel(context, context.l10n.modeEditorMyModesGroup),
          for (final mode in custom)
            _modeTile(context, mode, openId, editor.dirty),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(
                context.l10n.modeEditorNoMatches,
                style: context.text.bodySmall?.copyWith(
                  color: context.colors.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            context.l10n.modeEditorCatalogReadOnlyHint,
            style: context.text.labelSmall?.copyWith(
              color: context.colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<ThreadModeDescriptorView> _filteredCatalog(
    List<ThreadModeDescriptorView> catalog,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return catalog;
    return catalog
        .where(
          (mode) =>
              mode.displayName.toLowerCase().contains(query) ||
              mode.id.toLowerCase().contains(query) ||
              mode.description.toLowerCase().contains(query),
        )
        .toList(growable: false);
  }

  Widget _groupLabel(BuildContext context, String label) => Padding(
    padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
    child: Text(
      label,
      style: context.text.labelSmall?.copyWith(
        color: context.colors.onSurfaceVariant,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _modeTile(
    BuildContext context,
    ThreadModeDescriptorView mode,
    String? openId,
    bool dirty,
  ) {
    final selected = mode.id == openId;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected
            ? context.colors.surfaceContainerHigh
            : Colors.transparent,
        borderRadius: BorderRadius.circular(StudioRadii.sm),
        child: InkWell(
          key: ModeEditorKeys.catalogItem(mode.id),
          borderRadius: BorderRadius.circular(StudioRadii.sm),
          onTap: () => _openWorkspace(mode.id),
          child: Container(
            padding: const EdgeInsets.fromLTRB(9, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(
                  color: selected ? context.colors.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              borderRadius: BorderRadius.circular(StudioRadii.sm),
            ),
            child: Row(
              children: [
                Icon(
                  mode.readOnly
                      ? Icons.lock_outline
                      : mode.hasWorkflow
                      ? Icons.account_tree_outlined
                      : Icons.notes_outlined,
                  size: 16,
                  color: context.colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        mode.displayName.isEmpty ? mode.id : mode.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.bodyMedium?.copyWith(
                          color: context.colors.onSurface,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                        ),
                      ),
                      Text(
                        mode.id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.text.labelSmall?.copyWith(
                          color: context.colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected && dirty)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text(
                      context.l10n.modeEditorUnsaved,
                      style: context.text.labelSmall?.copyWith(
                        color: context.colors.tertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: context.colors.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openWorkspace(String id) async {
    final owner = ref.read(anyworkClientProvider).modeEditor;
    final same = owner.state.document?.definition.id == id;
    if (!same) {
      if (!await confirmLeaveModeEditor(context) || !mounted) return;
      final opened = await owner.open(id);
      if (!mounted) return;
      if (!opened) {
        final error = owner.state.error;
        if (error != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(error)));
        }
        return;
      }
    }
    if (!mounted) return;
    ModeWorkspaceRoute(modeId: id).push(context);
  }

  Future<void> _createMode(List<ThreadModeDescriptorView> catalog) async {
    final result = await showCreateModeDialog(
      context,
      existingIds: catalog.map((mode) => mode.id).toSet(),
    );
    if (result == null || !mounted) return;
    if (!await confirmLeaveModeEditor(context) || !mounted) return;
    final l10n = context.l10n;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    var order = 10;
    for (final mode in catalog) {
      if (mode.order >= order) order = mode.order + 10;
    }
    final definition = newModeDefinition(
      id: result.id,
      displayName: result.displayName,
      order: order,
      template: result.template,
      l10n: l10n,
    );
    owner.create(
      id: result.id,
      displayName: result.displayName,
      template: ModeDocument(
        definition: definition,
        editor: const ModeEditorLayout(nodes: []),
      ),
    );
    if (!mounted) return;
    ModeWorkspaceRoute(modeId: result.id).push(context);
  }

  Future<void> _importMode(List<ThreadModeDescriptorView> catalog) async {
    final raw = await showImportModeDialog(context);
    if (raw == null || !mounted) return;
    final l10n = context.l10n;
    ModeDocument document;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        _showError(l10n.modeEditorImportObjectRequired);
        return;
      }
      document = ModeDocument.fromJson(decoded);
    } catch (error) {
      _showError(l10n.modeEditorImportReadFailed('$error'));
      return;
    }
    final id = document.definition.id;
    if (!isValidModeId(id)) {
      _showError(l10n.modeEditorInvalidModeId);
      return;
    }
    ThreadModeDescriptorView? existing;
    for (final mode in catalog) {
      if (mode.id == id) {
        existing = mode;
        break;
      }
    }
    if (existing?.readOnly ?? false) {
      _showError(l10n.modeEditorBuiltInCannotOverwrite);
      return;
    }
    if (!await confirmLeaveModeEditor(context) || !mounted) return;
    final owner = ref.read(anyworkClientProvider).modeEditor;
    if (existing == null) {
      owner.create(
        id: id,
        displayName: document.definition.displayName,
        template: document,
      );
    } else {
      if (!await owner.open(id) || !mounted) return;
    }
    // Preserve the authored source for Rust validation; parsing a display
    // draft must not drop fields.
    owner.editJson(raw);
    await owner.applyJson();
    if (!mounted) return;
    ModeWorkspaceRoute(modeId: id).push(context);
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
