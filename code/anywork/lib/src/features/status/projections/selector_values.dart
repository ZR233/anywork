import 'package:anywork_client/configuration.dart';
import 'package:anywork_client/models.dart';
import 'package:anywork_client/modes.dart';
import 'package:anywork_client/resources.dart';
import 'package:anywork_client/workspace.dart';
import 'package:flutter/foundation.dart';

import '../../../ui/selectors/model_selection_option.dart';
import '../state/selector_catalog_state.dart';

/// Current rows are evidence only for the supplied original product identity.
/// Partial catalogs never imply absence or a global first/default candidate.
List<T> selectorRows<T>(CollectionMirror<T> source, ProductReadOrigin? origin) {
  if (origin == null || source is! CurrentCollectionMirror<T>) return const [];
  final window = source.window;
  if (window.origin != origin) return const [];
  return List.unmodifiable([
    for (final reference in window.entries)
      if (window.rows[reference.entry] case ReadyReadValue<T, ProductEntityRef>(
        :final current,
      ))
        if (current.origin == origin && current.reference == reference)
          current.value,
  ]);
}

List<ThreadModeDescriptor> selectorModes(SelectorCatalogState state) =>
    state.modes.projection.sync.phase == ResourceSyncPhase.ready
    ? selectorRows(state.modes.modes, state.modes.projection.stamp?.origin)
    : const [];

/// Account names are display metadata, never a reconstructed config/catalog
/// compatibility credential. Eligibility comes from Rust's model descriptors.
List<ModelSelectionOption> selectorModels(SelectorCatalogState state) {
  if (state.models.projection.sync.phase != ResourceSyncPhase.ready) {
    return const [];
  }
  final names = {
    for (final account in selectorRows(
      state.configuration.accounts,
      state.configuration.projection.stamp?.origin,
    ))
      account.accountId: account.name,
  };
  final seen = <(String, String)>{};
  return List.unmodifiable([
    for (final account in selectorRows(
      state.models.accounts,
      state.models.projection.stamp?.origin,
    ))
      for (final model in account.effectiveModels)
        if (model.enabled &&
            model.typeSupport.any(
              (support) =>
                  support.modelType == ModelType.text &&
                  support.exclusions.isEmpty,
            ) &&
            seen.add((account.accountId, model.modelId)))
          ModelSelectionOption(
            accountId: account.accountId,
            accountName: names[account.accountId] ?? account.accountId,
            descriptor: model,
          ),
  ]);
}

ModelDescriptor? selectedDescriptor(
  ModelsState state,
  String accountId,
  String modelId,
) {
  if (state.projection.sync.phase != ResourceSyncPhase.ready) return null;
  for (final account in selectorRows(
    state.accounts,
    state.projection.stamp?.origin,
  )) {
    if (account.accountId != accountId) continue;
    return account.effectiveModels
        .where((model) => model.modelId == modelId)
        .firstOrNull;
  }
  return null;
}

DelegationSettings? selectorDelegation(ConfigurationState state) {
  final read = state.delegation;
  final reference = state.projection.header?.reference;
  if (state.projection.sync.phase != ResourceSyncPhase.ready ||
      reference == null ||
      read is! ReadyReadValue<DelegationSettings, ConfigurationReadRef> ||
      read.current.origin != state.projection.stamp?.origin ||
      read.current.reference != reference) {
    return null;
  }
  return read.current.value;
}

@immutable
final class SelectedSessionStatus {
  const SelectedSessionStatus({
    required this.selection,
    required this.thread,
    required this.agent,
  });
  final WorkspaceSelection selection;
  final WorkspaceThreadRecord? thread;
  final AgentDirectoryEntry? agent;
}

/// No root discovery or navigation generation. Both identities are selected
/// directly from the Workspace owner's already-published selection.
SelectedSessionStatus projectSelectedSession({
  required WorkspaceSelection selection,
  required WorkspaceThreadRecord? metadata,
  required Iterable<AgentDirectoryEntry> agents,
}) => SelectedSessionStatus(
  selection: selection,
  thread: metadata?.id == selection.threadId ? metadata : null,
  agent: agents
      .where((entry) => entry.threadId == selection.threadId)
      .firstOrNull,
);
