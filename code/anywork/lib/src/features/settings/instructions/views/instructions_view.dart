import 'package:flutter/material.dart';

import '../../../../app/theme/studio_tokens.dart';
import '../../../../l10n/studio_l10n.dart';
import '../../widgets/settings_feedback.dart';
import '../../widgets/settings_pane.dart';
import '../state/instructions_state.dart';

class InstructionsView extends StatelessWidget {
  const InstructionsView({
    required this.state,
    required this.errors,
    required this.onSection,
    required this.onEdit,
    super.key,
  });

  final InstructionsViewState state;
  final List<String> errors;
  final ValueChanged<InstructionSection> onSection;
  final void Function(InstructionSection section, String raw) onEdit;

  @override
  Widget build(BuildContext context) {
    final labels = [
      context.l10n.settingsBaseInstructions,
      context.l10n.settingsDeveloperInstructions,
      context.l10n.settingsUserContext,
    ];
    final drafts = [state.base, state.developer, state.user];
    final section = state.section;
    return SettingsPane.scrolling(
      title: context.l10n.settingsInstructionsTitle,
      subtitle: context.l10n.settingsInstructionsSubtitle,
      trailing: drafts.any((draft) => draft.action?.pending ?? false)
          ? const SizedBox(width: 80, child: LinearProgressIndicator())
          : null,
      toolbar: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final value in InstructionSection.values)
            TextButton(
              key: ValueKey('instruction-section-${value.index}'),
              onPressed: () => onSection(value),
              style: TextButton.styleFrom(
                foregroundColor: value == section
                    ? context.colors.primary
                    : context.colors.onSurfaceVariant,
                backgroundColor: value == section
                    ? context.colors.surfaceContainer
                    : Colors.transparent,
              ),
              child: Text(labels[value.index]),
            ),
        ],
      ),
      children: [
        _InstructionsEditor(
          key: ValueKey('instruction-editor-${section.index}'),
          label: labels[section.index],
          hint: context.l10n.settingsInstructionHint,
          value: drafts[section.index].raw,
          onChanged: (raw) => onEdit(section, raw),
        ),
        if (errors.isNotEmpty) SettingsInlineError(message: errors.join('\n')),
      ],
    );
  }
}

/// Instruction editor keeps the pre-refactor typography: a 16-line minimum, a
/// 1.7 line height and 20 of inner padding.
class _InstructionsEditor extends StatefulWidget {
  const _InstructionsEditor({
    required this.label,
    required this.hint,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String hint;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_InstructionsEditor> createState() => _InstructionsEditorState();
}

class _InstructionsEditorState extends State<_InstructionsEditor> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );

  @override
  void didUpdateWidget(covariant _InstructionsEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value || _controller.text == widget.value) {
      return;
    }
    final selection = _controller.selection;
    _controller.value = TextEditingValue(
      text: widget.value,
      selection: TextSelection(
        baseOffset: selection.baseOffset.clamp(0, widget.value.length),
        extentOffset: selection.extentOffset.clamp(0, widget.value.length),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _controller,
    minLines: 16,
    maxLines: null,
    style: context.text.bodyMedium?.copyWith(height: 1.7),
    decoration: InputDecoration(
      labelText: widget.label,
      hintText: widget.hint,
      alignLabelWithHint: true,
      contentPadding: const EdgeInsets.all(20),
    ),
    onChanged: widget.onChanged,
  );
}
