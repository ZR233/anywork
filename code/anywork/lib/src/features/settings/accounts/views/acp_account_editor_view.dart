import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';
import '../state/account_presentations.dart';
import '../state/account_view_key_values.dart';
import '../widgets/account_editor_fields.dart';
import '../widgets/account_sections.dart';
import '../widgets/acp_account_panel.dart';
import 'native_account_editor_view.dart' show AccountEditorFooter;

class AcpAccountEditorView extends StatelessWidget {
  const AcpAccountEditorView({
    required this.value,
    required this.onNameChanged,
    required this.onAction,
    required this.onLoginMethodChanged,
    required this.onSave,
    required this.onCancel,
    this.onSourceChanged,
    this.onCommandChanged,
    this.onArgsChanged,
    this.onEnvironmentChanged,
    this.onEnabledChanged,
    this.onRefreshDetection,
    this.scrollController,
    this.templateSelector,
    super.key,
  });
  final AcpAccountEditorPresentation value;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<AcpAccountAction> onAction;
  final ValueChanged<String> onLoginMethodChanged;
  final ValueChanged<AcpAccountSource>? onSourceChanged;
  final ValueChanged<String>? onCommandChanged;
  final ValueChanged<List<String>>? onArgsChanged;
  final ValueChanged<List<AcpEnvironmentEntry>>? onEnvironmentChanged;
  final ValueChanged<bool>? onEnabledChanged;
  final VoidCallback? onRefreshDetection;
  final VoidCallback onSave;
  final VoidCallback onCancel;
  final ScrollController? scrollController;
  final Widget? templateSelector;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final editable = !value.saving;
    final managed = value.source == AcpAccountSource.managed;
    final local = value.source == AcpAccountSource.local;
    final detecting =
        value.detectionPhase == AcpDetectionPhase.checking ||
        value.detectionPhase == AcpDetectionPhase.cancelling;
    final status = switch (value.detectionPhase) {
      AcpDetectionPhase.idle => l10n.acpDetectionIdle,
      AcpDetectionPhase.checking => l10n.acpDetectionChecking,
      AcpDetectionPhase.available => value.detectedProgram,
      AcpDetectionPhase.missing => l10n.acpDetectionMissing,
      AcpDetectionPhase.unsupported => l10n.acpDetectionUnsupported,
      AcpDetectionPhase.failed =>
        value.detectionError ?? l10n.acpDetectionFailed,
      AcpDetectionPhase.cancelling => l10n.acpDetectionCancelling,
      AcpDetectionPhase.cancelled => l10n.acpDetectionCancelled,
    };
    return AccountEditorScaffold(
      title: value.accountKey == null
          ? l10n.settingsAddAccount
          : l10n.settingsEditAccount,
      // Dirty remains in the leave guard; it is not a second heading description.
      scrollKey: PageStorageKey<String>(
        AccountViewKeyValues.editorScroll(AccountKind.acp.name, value.editorId),
      ),
      scrollController: scrollController,
      children: [
        if (templateSelector != null) ...[
          templateSelector!,
          const SizedBox(height: 24),
        ],
        DropdownButtonFormField<AcpAccountSource>(
          key: ValueKey('acp-source:${value.editorId}:${value.source.name}'),
          initialValue: value.source,
          decoration: InputDecoration(labelText: l10n.acpAccountSource),
          items: [
            DropdownMenuItem(
              value: AcpAccountSource.local,
              child: Text(l10n.acpSourceLocal),
            ),
            DropdownMenuItem(
              value: AcpAccountSource.command,
              child: Text(l10n.acpSourceCommand),
            ),
            DropdownMenuItem(
              value: AcpAccountSource.managed,
              child: Text(l10n.acpSourceManaged),
            ),
          ],
          onChanged: editable && onSourceChanged != null
              ? (source) {
                  if (source != null) onSourceChanged!(source);
                }
              : null,
        ),
        const SizedBox(height: 20),
        AccountRawTextField(
          key: ValueKey(
            AccountViewKeyValues.editorField(value.editorId, 'name'),
          ),
          value: value.name,
          label: l10n.settingsDisplayName,
          enabled: editable,
          onChanged: onNameChanged,
        ),
        if (local) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              if (detecting) ...[
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: status == null
                    ? const SizedBox.shrink()
                    : Tooltip(
                        message: status,
                        child: Text(
                          status,
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
              ),
              if (value.detectedVersion case final version?
                  when value.detectionPhase == AcpDetectionPhase.available &&
                      version.trim().isNotEmpty) ...[
                const SizedBox(width: 12),
                Text(version, maxLines: 1, softWrap: false),
              ],
              IconButton(
                tooltip: l10n.acpDetectionRefresh,
                onPressed: detecting ? null : onRefreshDetection,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          if (value.detectionError != null &&
              value.detectionPhase != AcpDetectionPhase.failed)
            AccountInlineError(message: value.detectionError!),
        ],
        if (!managed) ...[
          const SizedBox(height: 16),
          AccountRawTextField(
            key: ValueKey(
              AccountViewKeyValues.editorField(value.editorId, 'command'),
            ),
            value: AccountTextPresentation(raw: value.command),
            label: l10n.acpCommandLabel,
            enabled: editable,
            onChanged: (raw) => onCommandChanged?.call(raw),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.acpArgsLabel,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (var i = 0; i < value.args.length; i++)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: AccountRawTextField(
                      key: ValueKey(
                        AccountViewKeyValues.editorField(
                          value.editorId,
                          'arg:$i',
                        ),
                      ),
                      value: AccountTextPresentation(raw: value.args[i]),
                      label: '${l10n.acpArgumentLabel} ${i + 1}',
                      enabled: editable,
                      onChanged: (raw) {
                        final args = [...value.args];
                        args[i] = raw;
                        onArgsChanged?.call(args);
                      },
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.acpRemoveEntry,
                    onPressed: editable
                        ? () =>
                              onArgsChanged?.call([...value.args]..removeAt(i))
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: editable
                  ? () => onArgsChanged?.call([...value.args, ''])
                  : null,
              icon: const Icon(Icons.add),
              label: Text(l10n.acpAddArgument),
            ),
          ),
        ],
        ExpansionTile(
          key: PageStorageKey('acp-env:${value.editorId}'),
          tilePadding: EdgeInsets.zero,
          title: Text(l10n.acpEnvironmentLabel),
          children: [
            for (var i = 0; i < value.environment.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: AccountRawTextField(
                        key: ValueKey(
                          AccountViewKeyValues.editorField(
                            value.editorId,
                            'env-key:$i',
                          ),
                        ),
                        value: AccountTextPresentation(
                          raw: value.environment[i].key,
                        ),
                        label: l10n.acpEnvironmentKey,
                        enabled: editable,
                        onChanged: (raw) {
                          final entries = [...value.environment];
                          entries[i] = entries[i].copyWith(key: raw);
                          onEnvironmentChanged?.call(entries);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AccountRawTextField(
                        key: ValueKey(
                          AccountViewKeyValues.editorField(
                            value.editorId,
                            'env-value:$i',
                          ),
                        ),
                        value: AccountTextPresentation(
                          raw: value.environment[i].value,
                        ),
                        label: l10n.acpEnvironmentValue,
                        enabled: editable,
                        obscure: true,
                        onChanged: (raw) {
                          final entries = [...value.environment];
                          entries[i] = entries[i].copyWith(value: raw);
                          onEnvironmentChanged?.call(entries);
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: l10n.acpRemoveEntry,
                      onPressed: editable
                          ? () => onEnvironmentChanged?.call(
                              [...value.environment]..removeAt(i),
                            )
                          : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: editable
                    ? () => onEnvironmentChanged?.call([
                        ...value.environment,
                        const AcpEnvironmentEntry(key: '', value: ''),
                      ])
                    : null,
                icon: const Icon(Icons.add),
                label: Text(l10n.acpAddEnvironment),
              ),
            ),
          ],
        ),
        if (value.accountKey != null)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.acpAccountEnabled),
            value: value.enabled,
            onChanged: editable ? onEnabledChanged : null,
          ),
        if (value.error != null) AccountInlineError(message: value.error!),
        if (managed || value.accountKey != null) ...[
          const SizedBox(height: 16),
          AcpAccountPanel(
            value: value.preparation,
            onAction: onAction,
            onLoginMethodChanged: onLoginMethodChanged,
          ),
        ],
        const SizedBox(height: 24),
        AccountEditorFooter(
          saving: value.saving,
          canSave: value.canSave,
          saveIsPrimary: true,
          onSave: onSave,
          onCancel: onCancel,
          saveLabel: value.saveAndConnect
              ? l10n.acpAccountSaveAndConnect
              : l10n.commonSave,
        ),
      ],
    );
  }
}
