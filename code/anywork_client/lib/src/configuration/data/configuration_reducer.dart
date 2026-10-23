import '../../../resources.dart';
import '../domain/configuration_state.dart';
import '../domain/configuration_values.dart';
import '../domain/profile_values.dart';
import 'configuration_frames.dart';
import 'configuration_read_fields.dart';

Materialized<T, R>? configurationPrevious<T, R>(ReadValue<T, R>? value) => switch (value) {
  ReadyReadValue<T, R>(:final current) => current,
  LoadingReadValue<T, R>(:final previous) || FailedReadValue<T, R>(:final previous) => previous,
  _ => null,
};

CollectionWindow<T>? configurationWindow<T>(CollectionMirror<T> value) => switch (value) {
  CurrentCollectionMirror<T>(:final window) => window,
  UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
};

ReadValue<T, R>? configurationField<T, R>(ReadValue<T, R>? previous, ProductReadOrigin origin, R? reference) {
  final known = configurationPrevious(previous);
  if (reference == null) {
    if (known == null) return previous;
    return ReadValue.failed(origin: known.origin, reference: known.reference, error: const StudioFailure(code: StudioFailureCode.unavailable, message: 'Configuration has no current source value; previous material is last-known only.', retryable: true, correlationId: 'configuration'), previous: known);
  }
  final currentReference = switch (previous) {
    UnloadedReadValue<T, R>(:final origin, :final reference) || LoadingReadValue<T, R>(:final origin, :final reference) || FailedReadValue<T, R>(:final origin, :final reference) => (origin: origin, reference: reference),
    ReadyReadValue<T, R>(:final current) => (origin: current.origin, reference: current.reference),
    null => null,
  };
  if (currentReference?.origin == origin && currentReference?.reference == reference) return previous;
  return known == null ? ReadValue.unloaded(origin: origin, reference: reference) : ReadValue.failed(origin: origin, reference: reference, error: configurationSuperseded, previous: known);
}

CollectionMirror<T> configurationCollectionBaseline<T>(CollectionMirror<T> previous, ProductReadOrigin origin, ProductCollectionRef? collection) {
  final old = configurationWindow(previous);
  if (collection == null) return CollectionMirror.unavailable(lastKnown: old);
  if (collection.total < 0) throw configurationProtocol('A configuration collection has an invalid length.');
  if (old?.origin == origin && old?.reference == collection) return CollectionMirror.current(window: old!);
  if (old != null && collection.total != 0) return CollectionMirror.unavailable(lastKnown: old);
  return CollectionMirror.current(window: CollectionWindow(origin: origin, reference: collection, entries: const [], rows: const {}, continuation: collection.total == 0 ? const CollectionContinuation.end() : const CollectionContinuation.unknown(), complete: collection.total == 0, loading: false, error: null));
}

CollectionMirror<T> configurationCollectionChange<T>(CollectionMirror<T> previous, ProductReadOrigin origin, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removed, {required bool orderStableForValueChanges}) {
  if (upserted.length + removed.length > 100 || upserted.map((item) => item.entry).toSet().length != upserted.length || removed.toSet().length != removed.length || removed.any((entry) => upserted.any((item) => item.entry == entry))) throw configurationProtocol('A configuration delta has inconsistent membership.');
  if (collection == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty) throw configurationProtocol('An unavailable configuration source has entity changes.');
    return CollectionMirror.unavailable(lastKnown: configurationWindow(previous));
  }
  if (previous is! CurrentCollectionMirror<T> || previous.window.origin != origin) return configurationCollectionBaseline(previous, origin, collection);
  final old = previous.window;
  if (old.reference.entry != collection.entry || collection.total < 0) throw configurationProtocol('A configuration delta changed the collection identity.');
  final updates = {for (final item in upserted) item.entry: item};
  final rows = Map<int, ReadValue<T, ProductEntityRef>>.of(old.rows)..removeWhere((entry, _) => removed.contains(entry));
  for (final update in updates.entries) {
    final known = configurationPrevious(rows[update.key]);
    if (known == null) { rows[update.key] = ReadValue.unloaded(origin: origin, reference: update.value); continue; }
    if (known.reference == update.value) continue;
    rows[update.key] = ReadValue.failed(origin: origin, reference: update.value, error: configurationSuperseded, previous: known);
  }
  final orderUnknown = removed.isNotEmpty || collection.total != old.reference.total || !orderStableForValueChanges && upserted.isNotEmpty;
  return CollectionMirror.current(window: old.copyWith(reference: collection, entries: orderUnknown ? const [] : [for (final reference in old.entries) updates[reference.entry] ?? reference], rows: collection.total == 0 ? const {} : Map.unmodifiable(rows), continuation: collection.total == 0 ? const CollectionContinuation.end() : orderUnknown ? const CollectionContinuation.unknown() : old.continuation, complete: collection.total == 0 || !orderUnknown && old.complete, loading: old.reference == collection && old.loading, error: null));
}

ConfigurationState reduceConfigurationBaseline(ConfigurationState previous, ProductProjectionStamp stamp, ConfigurationBaseline value) => _configuration(previous, stamp, value.header, configurationCollectionBaseline(previous.accounts, stamp.origin, value.collection));

ConfigurationState reduceConfigurationChange(ConfigurationState previous, ProductProjectionStamp stamp, ConfigurationChange value) => _configuration(previous, stamp, value.header, configurationCollectionChange(previous.accounts, stamp.origin, value.collection, value.upserted, value.removedEntries, orderStableForValueChanges: true));

ConfigurationState _configuration(ConfigurationState previous, ProductProjectionStamp stamp, ConfigurationHeader header, CollectionMirror<AccountConfiguration> accounts) {
  return previous.copyWith(
    projection: ProductProjection(stamp: stamp, header: header, sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)),
    sourceStatus: configurationField(previous.sourceStatus, stamp.origin, header.source.status), accounts: accounts,
    defaultAccountId: configurationField(previous.defaultAccountId, stamp.origin, header.reference),
    modeRoutes: configurationField(previous.modeRoutes, stamp.origin, header.reference), roles: configurationField(previous.roles, stamp.origin, header.reference),
    permissionMode: configurationField(previous.permissionMode, stamp.origin, header.reference), instructions: configurationField(previous.instructions, stamp.origin, header.reference),
    skillsSettings: configurationField(previous.skillsSettings, stamp.origin, header.reference), mcpConfigurations: configurationField(previous.mcpConfigurations, stamp.origin, header.reference),
    general: configurationField(previous.general, stamp.origin, header.reference), webSearch: configurationField(previous.webSearch, stamp.origin, header.reference), deepSeekSearch: configurationField(previous.deepSeekSearch, stamp.origin, header.reference),
  );
}

ProfilesState reduceProfilesBaseline(ProfilesState previous, ProductProjectionStamp stamp, AgentProfilesBaseline value) {
  final old = configurationWindow(previous.profiles);
  final keepDetails = old?.origin == stamp.origin && old?.reference == value.collection;
  return _profiles(previous, stamp, value.header, configurationCollectionBaseline(previous.profiles, stamp.origin, value.collection), keepDetails ? previous.details : const {});
}

ProfilesState reduceProfilesChange(ProfilesState previous, ProductProjectionStamp stamp, AgentProfilesChange value) {
  final old = configurationWindow(previous.profiles);
  final details = old?.origin == stamp.origin ? Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>>.of(previous.details) : <int, ReadValue<AgentProfileSnapshot, ProductEntityRef>>{};
  details.removeWhere((entry, _) => value.removedEntries.contains(entry));
  for (final reference in value.upserted) {
    if (details.containsKey(reference.entry)) details[reference.entry] = configurationField(details[reference.entry], stamp.origin, reference)!;
  }
  if (value.collection?.total == 0) details.clear();
  return _profiles(previous, stamp, value.header, configurationCollectionChange(previous.profiles, stamp.origin, value.collection, value.upserted, value.removedEntries, orderStableForValueChanges: false), Map.unmodifiable(details));
}

ProfilesState _profiles(ProfilesState previous, ProductProjectionStamp stamp, AgentProfilesHeader header, CollectionMirror<AgentProfileSummary> profiles, Map<int, ReadValue<AgentProfileSnapshot, ProductEntityRef>> details) => previous.copyWith(projection: ProductProjection(stamp: stamp, header: header, sync: const ResourceSyncState(phase: ResourceSyncPhase.ready, error: null, retryExhausted: false)), sourceStatus: configurationField(previous.sourceStatus, stamp.origin, header.source.status), profiles: profiles, diagnostics: configurationField(previous.diagnostics, stamp.origin, header.reference), details: Map.unmodifiable(details));
