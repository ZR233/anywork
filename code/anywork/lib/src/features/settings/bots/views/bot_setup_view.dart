import 'package:flutter/material.dart';

import '../../../../diagnostics/studio_driver_keys.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_layout.dart';
import '../../widgets/settings_rows.dart';
import '../state/bot_setup_state.dart';
import 'bot_secret_owner.dart';

/// One bot create/edit surface, matching the overview layout it replaces:
///
/// * creation is the in-page "首次配置" section (risk statement, permission
///   scope, default model availability, name, risk acknowledgement,
///   "创建并连接飞书应用" / "连接已有应用", then the manual App ID/Secret entry and
///   its save button);
/// * editing is the "编辑配置" dialog with name, App ID and the App Secret
///   replacement (an empty field preserves the stored secret), nothing else.
///
/// The [secret] owner is the only holder of the App Secret; this widget renders
/// its obscured field and never reads, copies or echoes its contents.
class BotSetupView extends StatelessWidget {
  const BotSetupView({
    required this.state,
    required this.secret,
    required this.errors,
    required this.modelAvailability,
    required this.onName,
    required this.onAppId,
    required this.onRiskAcknowledged,
    required this.onManual,
    required this.onSecretIntent,
    required this.onStartRegistration,
    required this.onOpenConsole,
    required this.onCancel,
    required this.onSave,
    super.key,
  });

  final BotSetupViewState state;
  final BotSecretOwner secret;
  final List<String> errors;

  /// Statement of the default model availability. Saving a platform app never
  /// proves model connectivity, so the page states the real evidence instead.
  final String modelAvailability;

  final ValueChanged<String> onName;
  final ValueChanged<String> onAppId;
  final ValueChanged<bool> onRiskAcknowledged;
  final VoidCallback onManual;
  final ValueChanged<BotSecretIntent> onSecretIntent;
  final VoidCallback onStartRegistration;
  final VoidCallback onOpenConsole;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) =>
      state.create ? _setupSection(context) : _editDialog(context);

  /// In-page "首次配置" section. Its order and wording follow the overview page:
  /// risk and permission statement, the default model availability, name, risk
  /// acknowledgement, the two entries, then the manual App ID/Secret entry
  /// revealed by "连接已有应用".
  Widget _setupSection(BuildContext context) {
    final editable = state.editable;
    return SettingsSectionPanel(
      title: context.l10n.settingsBotsSetupTitle,
      trailing: TextButton(
        onPressed: onCancel,
        child: Text(context.l10n.settingsBotsSetupClose),
      ),
      children: [
        ..._errors(context),
        if (state.saving) const LinearProgressIndicator(),
        Text(
          context.l10n.settingsBotsRisk,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(
          context.l10n.settingsBotsPermissions,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Text(modelAvailability),
        const SizedBox(height: 12),
        SettingsFormField(
          key: StudioDriverKeys.botsName,
          value: state.name,
          label: context.l10n.settingsBotsName,
          enabled: editable,
          error: _issue(context, state.nameIssue),
          onChanged: onName,
        ),
        const SizedBox(height: 10),
        SettingsToggleRow(
          key: StudioDriverKeys.botsRiskAck,
          icon: Icons.warning_amber_outlined,
          title: context.l10n.settingsBotsRiskAck,
          value: state.riskAcknowledged,
          onChanged: editable ? onRiskAcknowledged : (_) {},
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              key: StudioDriverKeys.botsScan,
              onPressed: state.canStartRegistration
                  ? onStartRegistration
                  : null,
              child: Text(context.l10n.settingsBotsScan),
            ),
            OutlinedButton(
              key: StudioDriverKeys.botsManual,
              onPressed: editable ? onManual : null,
              child: Text(context.l10n.settingsBotsManual),
            ),
          ],
        ),
        if (state.manualOpen) ...[
          const SizedBox(height: 16),
          Text(context.l10n.settingsBotsManualGuide),
          const SizedBox(height: 8),
          Text(
            context.l10n.settingsBotsOpenConsoleHint,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: StudioDriverKeys.botsOpenConsoleManual,
              onPressed: onOpenConsole,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(context.l10n.settingsBotsOpenConsole),
            ),
          ),
          const SizedBox(height: 10),
          SettingsFormField(
            key: StudioDriverKeys.botsAppId,
            value: state.appId,
            label: context.l10n.settingsBotsAppId,
            code: true,
            enabled: editable,
            error: _issue(context, state.appIdIssue),
            onChanged: onAppId,
          ),
          const SizedBox(height: 10),
          _secretField(context, editable: editable && !_clearing),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              key: StudioDriverKeys.botsSave,
              onPressed: state.canSave ? onSave : null,
              child: Text(context.l10n.settingsBotsSave),
            ),
          ),
        ],
      ],
    );
  }

  /// "编辑配置" dialog: name, App ID (read-only once a platform identity exists)
  /// and the App Secret. Enablement and project tools keep their own detail
  /// actions, exactly like the previous editor.
  Widget _editDialog(BuildContext context) {
    final editable = state.editable;
    return AlertDialog(
      title: Text(context.l10n.settingsBotsEdit),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._errors(context),
              SettingsFormField(
                key: StudioDriverKeys.botsName,
                value: state.name,
                label: context.l10n.settingsBotsName,
                enabled: editable,
                error: _issue(context, state.nameIssue),
                onChanged: onName,
              ),
              const SizedBox(height: 12),
              SettingsFormField(
                key: StudioDriverKeys.botsAppId,
                value: state.appId,
                label: context.l10n.settingsBotsAppId,
                enabled: editable && state.canChangeAppId,
                code: true,
                error: _issue(context, state.appIdIssue),
                // Read-only for an established platform identity; the
                // ViewModel also refuses the edit.
                onChanged: onAppId,
              ),
              if (!state.canChangeAppId)
                Text(
                  context.l10n.settingsBotsAppIdLocked,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              const SizedBox(height: 12),
              _secretField(
                context,
                editable: editable && !_clearing,
                helper: context.l10n.settingsBotsPreserveSecret,
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _clearing,
                title: Text(context.l10n.settingsBotsClearSecret),
                onChanged: editable
                    ? (value) => onSecretIntent(
                        (value ?? false)
                            ? BotSecretIntent.clear
                            : BotSecretIntent.preserve,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          child: Text(context.l10n.settingsBotsDismiss),
        ),
        FilledButton(
          key: StudioDriverKeys.botsSave,
          onPressed: state.canSave ? onSave : null,
          child: Text(context.l10n.settingsBotsSave),
        ),
      ],
    );
  }

  bool get _clearing => state.secretIntent == BotSecretIntent.clear;

  Widget _secretField(
    BuildContext context, {
    required bool editable,
    String? helper,
  }) => TextField(
    key: StudioDriverKeys.botsSecret,
    controller: secret.controller,
    enabled: editable,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: context.l10n.settingsBotsSecret,
      helperText: helper,
      helperMaxLines: 2,
      errorText: _issue(context, state.secretIssue),
    ),
  );

  String? _issue(BuildContext context, BotSetupValidation? issue) =>
      switch (issue) {
        BotSetupValidation.required =>
          context.l10n.settingsAgentProfileRequired,
        null => null,
      };

  Iterable<Widget> _errors(BuildContext context) => [
    for (final error in errors)
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: SettingsInlineError(message: error),
      ),
  ];
}
