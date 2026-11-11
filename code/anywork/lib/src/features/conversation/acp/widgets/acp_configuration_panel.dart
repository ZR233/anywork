import 'package:anywork_client/acp_sessions.dart';
import 'package:material_ui/material_ui.dart';

/// Protocol configuration, including unknown categories, in server order.
class AcpConfigurationPanel extends StatelessWidget {
  const AcpConfigurationPanel({
    super.key,
    required this.options,
    required this.modes,
    required this.pending,
    this.enabled = true,
    required this.onConfigure,
    required this.onMode,
  });

  final List<AcpSessionConfigOptionView>? options;
  final AcpSessionModeStateView? modes;
  final bool pending;
  final bool enabled;
  final void Function(AcpConfigId, AcpSessionConfigValueView) onConfigure;
  final ValueChanged<AcpModeId> onMode;

  @override
  Widget build(BuildContext context) {
    final options = this.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (pending) ...[
          const LinearProgressIndicator(),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('正在应用配置，完成前不能发送消息'),
          ),
        ],
        if (options != null)
          for (final option in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: AcpConfigurationOption(
                key: ValueKey(option.id),
                option: option,
                enabled: enabled && !pending,
                onChanged: (value) => onConfigure(option.id, value),
              ),
            )
        else if (modes case final modes?)
          _ModeOption(
            modes: modes,
            enabled: enabled && !pending,
            onChanged: onMode,
          ),
      ],
    );
  }
}

class AcpConfigurationOption extends StatelessWidget {
  const AcpConfigurationOption({
    super.key,
    required this.option,
    required this.enabled,
    required this.onChanged,
  });

  final AcpSessionConfigOptionView option;
  final bool enabled;
  final ValueChanged<AcpSessionConfigValueView> onChanged;

  @override
  Widget build(BuildContext context) {
    final description = option.description;
    return switch (option.kind) {
      AcpBooleanConfigView(:final currentValue) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(option.name),
        subtitle: description == null ? null : Text(description),
        value: currentValue,
        onChanged: enabled
            ? (value) => onChanged(AcpBooleanConfigValueView(value))
            : null,
      ),
      AcpSelectConfigView(:final currentValue, :final options) =>
        InputDecorator(
          decoration: InputDecoration(
            enabled: enabled,
            labelText: option.name,
            helperText: description,
            helperMaxLines: 6,
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<AcpConfigValueId>(
              // The displayed selection belongs to the Client, even when a command
              // is rejected or the server normalizes it to the unchanged value.
              value: currentValue,
              isExpanded: true,
              items: switch (options) {
                AcpUngroupedOptionsView(:final options) => [
                  for (final value in options) _selectItem(value),
                ],
                AcpGroupedOptionsView(:final groups) => [
                  for (final group in groups) ...[
                    DropdownMenuItem<AcpConfigValueId>(
                      enabled: false,
                      child: Text(
                        group.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    for (final value in group.options) _selectItem(value),
                  ],
                ],
              },
              selectedItemBuilder: (context) => switch (options) {
                AcpUngroupedOptionsView(:final options) => [
                  for (final value in options)
                    Text(value.name, overflow: TextOverflow.ellipsis),
                ],
                AcpGroupedOptionsView(:final groups) => [
                  for (final group in groups) ...[
                    Text(group.name),
                    for (final value in group.options)
                      Text(value.name, overflow: TextOverflow.ellipsis),
                  ],
                ],
              },
              onChanged: enabled
                  ? (value) {
                      if (value != null) {
                        onChanged(AcpSelectConfigValueView(value));
                      }
                    }
                  : null,
            ),
          ),
        ),
    };
  }

  DropdownMenuItem<AcpConfigValueId> _selectItem(AcpSelectOptionView value) =>
      DropdownMenuItem(
        value: value.value,
        child: Tooltip(
          message: value.description ?? value.name,
          child: Text(value.name, overflow: TextOverflow.ellipsis),
        ),
      );
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.modes,
    required this.enabled,
    required this.onChanged,
  });

  final AcpSessionModeStateView modes;
  final bool enabled;
  final ValueChanged<AcpModeId> onChanged;

  @override
  Widget build(BuildContext context) => InputDecorator(
    decoration: InputDecoration(labelText: '模式', enabled: enabled),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<AcpModeId>(
        value: modes.currentModeId,
        isExpanded: true,
        items: [
          for (final mode in modes.availableModes)
            DropdownMenuItem(
              value: mode.id,
              child: Tooltip(
                message: mode.description ?? mode.name,
                child: Text(mode.name, overflow: TextOverflow.ellipsis),
              ),
            ),
        ],
        onChanged: enabled
            ? (value) {
                if (value != null) onChanged(value);
              }
            : null,
      ),
    ),
  );
}
