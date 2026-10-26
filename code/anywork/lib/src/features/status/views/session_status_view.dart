import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:flutter/material.dart';

import '../../../l10n/studio_l10n.dart';
import '../../../ui/labels/delegation_labels.dart';
import '../../../ui/menus/studio_menu_label.dart';
import '../projections/selector_values.dart';

/// Frozen metadata is explicitly labelled. It never masquerades as a live
/// Thread route or grants an edit capability absent from the public SDK.
class SessionStatusView extends StatelessWidget {
  SessionStatusView({
    required this.selection,
    required List<ThreadModeDescriptor> modes,
    required this.model,
    super.key,
  }) : modes = List.unmodifiable(modes);
  final SelectedSessionStatus selection;
  final List<ThreadModeDescriptor> modes;
  final ModelDescriptor? model;

  @override
  Widget build(BuildContext context) {
    final thread = selection.thread;
    final agent = selection.agent;
    final mode = thread?.mode;
    final route = agent?.frozenModel ?? thread?.frozenModel;
    final delegationMode = agent?.delegationMode ?? thread?.delegationMode;
    final preference =
        agent?.delegationPreference ?? thread?.delegationPreference;
    if (thread == null && agent == null) return const SizedBox.shrink();
    final summary = delegationMode == null || preference == null
        ? null
        : context.delegationSummary(
            DelegationSettings(mode: delegationMode, preference: preference),
          );
    final modelLabel = route == null
        ? context.l10n.delegationModelNotRecorded
        : model?.displayName.isNotEmpty == true
        ? model!.displayName
        : route.model.modelId;
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (mode != null)
          Tooltip(
            message: context.l10n.delegationFrozen,
            child: StudioMenuLabel(
              label:
                  modes
                      .where((item) => item.id == mode)
                      .firstOrNull
                      ?.displayName ??
                  context.compileModeLabel(mode),
              enabled: false,
              maxWidth: 120,
            ),
          ),
        Tooltip(
          message: context.l10n.delegationFrozen,
          child: StudioMenuLabel(
            label: modelLabel,
            enabled: false,
            maxWidth: 180,
          ),
        ),
        if (route?.effort case final effort?)
          StudioMenuLabel(label: effort, enabled: false, maxWidth: 100),
        if (summary != null)
          Tooltip(message: context.l10n.delegationFrozen, child: Text(summary)),
        if (model?.enabled == false)
          Tooltip(
            message: context.l10n.settingsModelDisabled,
            child: Icon(
              Icons.warning_amber_outlined,
              color: Theme.of(context).colorScheme.error,
              size: 18,
            ),
          ),
      ],
    );
  }
}
