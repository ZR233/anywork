import 'package:flutter/material.dart';

import '../../../../l10n/studio_l10n.dart';
import '../../../../ui/feedback/studio_messages.dart';
import '../../widgets/settings_form_field.dart';
import '../../widgets/settings_pane.dart';
import '../../widgets/settings_source_status_view.dart';
import '../state/instructions_state.dart';

class InstructionsView extends StatelessWidget {
  const InstructionsView({required this.state, required this.errors,
    required this.onSection, required this.onEdit, required this.onRetryRead, super.key});

  final InstructionsViewState state;
  final List<String> errors;
  final ValueChanged<InstructionSection> onSection;
  final void Function(InstructionSection section, String raw) onEdit;
  final VoidCallback onRetryRead;

  @override
  Widget build(BuildContext context) {
    final labels = [context.l10n.settingsBaseInstructions,
      context.l10n.settingsDeveloperInstructions, context.l10n.settingsUserContext];
    final drafts = [state.base, state.developer, state.user];
    final section = state.section;
    return SettingsPane(
      title: context.l10n.settingsInstructionsTitle,
      subtitle: context.l10n.settingsInstructionsSubtitle,
      trailing: drafts.any((draft) => draft.action?.pending ?? false)
        ? const SizedBox(width: 80, child: LinearProgressIndicator()) : null,
      toolbar: Wrap(spacing: 8, runSpacing: 8, children: [
        for (final value in InstructionSection.values)
          TextButton(
            key: ValueKey('instruction-section-${value.index}'),
            onPressed: () => onSection(value),
            style: TextButton.styleFrom(backgroundColor: value == section
              ? Theme.of(context).colorScheme.surfaceContainer : null),
            child: Text(labels[value.index]),
          ),
      ]),
      child: ListView(children: [
        SettingsSourceStatusView(title: context.l10n.settingsInstructionsTitle,
          brief: state.source.projection.header?.source.brief, read: state.source.sourceStatus,
          origin: state.source.projection.stamp?.origin, reference: state.source.projection.header?.source.status,
          onRetry: onRetryRead),
        SettingsFormField(
          key: ValueKey('instruction-editor-${section.index}'),
          value: drafts[section.index].raw,
          label: labels[section.index],
          hint: context.l10n.settingsInstructionHint,
          minLines: 16, maxLines: null,
          onChanged: (raw) => onEdit(section, raw),
        ),
        for (final error in errors) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: StudioInlineMessage(icon: Icons.error_outline, message: error,
            color: Theme.of(context).colorScheme.error),
        ),
        if (state.readIssues.isNotEmpty) Align(alignment: Alignment.centerLeft,
          child: TextButton(onPressed: onRetryRead, child: Text(context.l10n.runtimeFatalRetry))),
      ]),
    );
  }
}
