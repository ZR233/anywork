import 'package:anywork_client/resources_ports.dart';

const directoryUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The directory has no current canonical value.',
  retryable: true,
  correlationId: 'workspace',
);
const directorySuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original directory window is no longer current.',
  retryable: true,
  correlationId: 'workspace',
);

Materialized<T, R>? directoryPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? directoryStale<T, R>(
  ReadValue<T, R>? value,
  StudioFailure error,
) => switch (value) {
  ReadyReadValue<T, R>(:final current) => ReadValue.failed(
    origin: current.origin,
    reference: current.reference,
    error: error,
    previous: current,
  ),
  UnloadedReadValue<T, R>(:final origin, :final reference) => ReadValue.failed(
    origin: origin,
    reference: reference,
    error: error,
    previous: null,
  ),
  LoadingReadValue<T, R>(:final origin, :final reference, :final previous) ||
  FailedReadValue<T, R>(
    :final origin,
    :final reference,
    :final previous,
  ) => ReadValue.failed(
    origin: origin,
    reference: reference,
    error: error,
    previous: previous,
  ),
  null => null,
};

ReadValue<T, R>? directoryRebind<T, R>(
  ReadValue<T, R>? value,
  ProductReadOrigin origin,
  R? ref,
) {
  if (ref == null) return directoryStale(value, directoryUnavailable);
  final same = switch (value) {
    ReadyReadValue<T, R>(:final current) =>
      current.origin == origin && current.reference == ref,
    UnloadedReadValue<T, R>(origin: final prior, reference: final old) ||
    LoadingReadValue<T, R>(origin: final prior, reference: final old) ||
    FailedReadValue<T, R>(
      origin: final prior,
      reference: final old,
    ) => prior == origin && old == ref,
    null => false,
  };
  if (same) return value;
  final previous = directoryPrevious(value);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: directorySuperseded,
          previous: previous,
        );
}

bool directoryHasValue(ObservedBrief value) => switch (value) {
  ReadyObservedBrief() ||
  RefreshingObservedBrief() ||
  StaleObservedBrief() ||
  DegradedObservedBrief() => true,
  _ => false,
};

void validateDirectoryHeader(
  ObservedHeader source,
  ProductCollectionRef? collection, {
  required int? entry,
  required int? revision,
}) {
  final hasValue = directoryHasValue(source.brief);
  if (source.brief.revision < 0 ||
      source.status.entry < 0 ||
      source.status.revision < 0 ||
      (entry != null) != hasValue ||
      (revision != null) != hasValue ||
      (collection != null) != hasValue ||
      entry != null && entry < 0 ||
      revision != null && revision < 0 ||
      collection != null &&
          (collection.entry < 0 ||
              collection.revision < 0 ||
              collection.total < 0)) {
    throw resourceProtocol(
      'Directory availability, refs or source metadata are invalid.',
    );
  }
}

void directoryPageLimit(int limit) {
  if (limit < 1 || limit > 100)
    throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'A directory page limit must be between 1 and 100.',
      retryable: false,
      correlationId: 'workspace',
    );
}

CollectionWindow<T>? directoryWindow<T>(CollectionMirror<T> value) =>
    switch (value) {
      CurrentCollectionMirror<T>(:final window) => window,
      UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
    };

CollectionWindow<T> directoryEmpty<T>(
  ProductReadOrigin origin,
  ProductCollectionRef ref,
) => CollectionWindow(
  origin: origin,
  reference: ref,
  entries: const [],
  rows: const {},
  continuation: ref.total == 0
      ? const CollectionContinuation.end()
      : const CollectionContinuation.unknown(),
  complete: ref.total == 0,
  loading: false,
  error: null,
);

CollectionMirror<T> directoryBaseline<T>(
  CollectionMirror<T> old,
  ProductReadOrigin origin,
  ProductCollectionRef? ref,
) {
  final previous = directoryWindow(old);
  if (ref == null)
    return CollectionMirror.unavailable(
      lastKnown: previous?.copyWith(loading: false),
    );
  if (previous?.origin == origin && previous?.reference == ref) {
    return CollectionMirror.current(window: previous!.copyWith(loading: false));
  }
  if (previous != null && ref.total != 0) {
    return CollectionMirror.unavailable(
      lastKnown: previous.copyWith(loading: false),
    );
  }
  return CollectionMirror.current(window: directoryEmpty(origin, ref));
}

/// Ref-only deltas do not contain positions or pin ordinals. Never invent an
/// order from numeric entries or partially materialized names/timestamps.
CollectionMirror<T> directoryChanged<T>(
  CollectionMirror<T> old,
  ProductReadOrigin origin,
  int? base,
  ProductCollectionRef? next,
  List<ProductEntityRef> upserted,
  List<int> removed,
) {
  if (upserted.length + removed.length > 100 ||
      removed.any((entry) => entry < 0) ||
      upserted.any((ref) => ref.entry < 0 || ref.revision < 0) ||
      upserted.map((ref) => ref.entry).toSet().length != upserted.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => upserted.any((ref) => entry == ref.entry))) {
    throw resourceProtocol(
      'A directory delta has invalid or contradictory entries.',
    );
  }
  if (next == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty)
      throw resourceProtocol('An unavailable directory has entity changes.');
    return CollectionMirror.unavailable(
      lastKnown: directoryWindow(old)?.copyWith(loading: false),
    );
  }
  if (old is! CurrentCollectionMirror<T> || old.window.origin != origin)
    return directoryBaseline(old, origin, next);
  final prior = old.window;
  if (prior.reference.revision != base)
    throw resourceProtocol('The directory collection has a revision gap.');
  if (prior.reference.entry != next.entry)
    return directoryBaseline(old, origin, next);
  if (next == prior.reference && upserted.isEmpty && removed.isEmpty)
    return old;
  if (next.revision <= prior.reference.revision)
    throw resourceProtocol('A directory collection did not advance.');
  final rows = Map<int, ReadValue<T, ProductEntityRef>>.of(prior.rows)
    ..removeWhere((key, _) => removed.contains(key));
  for (final ref in upserted) {
    final prior = rows[ref.entry];
    final previous = directoryPrevious(prior);
    if (previous?.origin == origin &&
        previous!.reference.revision > ref.revision) {
      throw resourceProtocol('A directory entity ref moved backwards.');
    }
    if (prior != null) rows[ref.entry] = directoryRebind(prior, origin, ref)!;
  }
  // Native may have moved a member across this query's ordered/pinned window.
  // Preserve known field bodies, but require the original typed index again.
  return CollectionMirror.current(
    window: CollectionWindow(
      origin: origin,
      reference: next,
      entries: const [],
      rows: next.total == 0 ? const {} : rows,
      continuation: next.total == 0
          ? const CollectionContinuation.end()
          : const CollectionContinuation.unknown(),
      complete: next.total == 0,
      loading: false,
      error: null,
    ),
  );
}
