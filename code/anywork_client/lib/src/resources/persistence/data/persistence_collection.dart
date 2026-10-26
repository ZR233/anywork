import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_values.dart';

const persistenceUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The persistence feed is not currently available.',
  retryable: true,
  correlationId: 'persistence',
);
const persistenceSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original persistence read is no longer current.',
  retryable: true,
  correlationId: 'persistence',
);

Materialized<T, R>? persistencePrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? persistenceStale<T, R>(
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

ReadValue<T, R> persistenceRebind<T, R>(
  ReadValue<T, R>? old,
  ProductReadOrigin origin,
  R ref,
) {
  final same = switch (old) {
    ReadyReadValue<T, R>(:final current) =>
      current.origin == origin && current.reference == ref,
    UnloadedReadValue<T, R>(origin: final prior, reference: final reference) ||
    LoadingReadValue<T, R>(origin: final prior, reference: final reference) ||
    FailedReadValue<T, R>(
      origin: final prior,
      reference: final reference,
    ) => prior == origin && reference == ref,
    null => false,
  };
  if (same) return old!;
  final previous = persistencePrevious(old);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: persistenceSuperseded,
          previous: previous,
        );
}

CollectionWindow<ThreadPersistenceSnapshot>? persistenceWindow(
  CollectionMirror<ThreadPersistenceSnapshot> value,
) => switch (value) {
  CurrentCollectionMirror<ThreadPersistenceSnapshot>(:final window) => window,
  UnavailableCollectionMirror<ThreadPersistenceSnapshot>(:final lastKnown) =>
    lastKnown,
};

CollectionWindow<ThreadPersistenceSnapshot> persistenceEmptyWindow(
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

CollectionMirror<ThreadPersistenceSnapshot> persistenceBaseline(
  CollectionMirror<ThreadPersistenceSnapshot> old,
  ProductReadOrigin origin,
  ProductCollectionRef ref,
) {
  final previous = persistenceWindow(old);
  if (ref.entry < 0 || ref.revision < 0 || ref.total < 0)
    throw resourceProtocol('Invalid persistence collection.');
  if (previous?.origin == origin && previous?.reference == ref) {
    return CollectionMirror.current(window: previous!.copyWith(loading: false));
  }
  if (previous != null && ref.total != 0) {
    return CollectionMirror.unavailable(
      lastKnown: previous.copyWith(loading: false),
    );
  }
  return CollectionMirror.current(window: persistenceEmptyWindow(origin, ref));
}

CollectionMirror<ThreadPersistenceSnapshot> persistenceChange(
  CollectionMirror<ThreadPersistenceSnapshot> old,
  ProductReadOrigin origin,
  int? base,
  ProductCollectionRef next,
  List<ProductEntityRef> upserted,
  List<int> removed,
) {
  if (upserted.length + removed.length > 100 ||
      upserted.any((ref) => ref.entry < 0 || ref.revision < 0) ||
      removed.any((entry) => entry < 0) ||
      upserted.map((ref) => ref.entry).toSet().length != upserted.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => upserted.any((ref) => ref.entry == entry))) {
    throw resourceProtocol(
      'Persistence queue delta has invalid or contradictory entries.',
    );
  }
  if (next.entry < 0 || next.revision < 0 || next.total < 0)
    throw resourceProtocol('Invalid persistence collection.');
  if (old is! CurrentCollectionMirror<ThreadPersistenceSnapshot> ||
      old.window.origin != origin) {
    return persistenceBaseline(old, origin, next);
  }
  final prior = old.window;
  if (prior.reference.revision != base)
    throw resourceProtocol('Persistence queue collection revision gap.');
  if (prior.reference.entry != next.entry)
    return persistenceBaseline(old, origin, next);
  final rows =
      Map<int, ReadValue<ThreadPersistenceSnapshot, ProductEntityRef>>.of(
        prior.rows,
      )..removeWhere((entry, _) => removed.contains(entry));
  for (final ref in upserted) {
    if (rows.containsKey(ref.entry))
      rows[ref.entry] = persistenceRebind(rows[ref.entry], origin, ref);
  }
  final reset =
      prior.reference != next || upserted.isNotEmpty || removed.isNotEmpty;
  return CollectionMirror.current(
    window: prior.copyWith(
      reference: next,
      entries: reset ? const [] : prior.entries,
      rows: next.total == 0 ? const {} : rows,
      continuation: next.total == 0
          ? const CollectionContinuation.end()
          : reset
          ? const CollectionContinuation.unknown()
          : prior.continuation,
      complete: next.total == 0 || !reset && prior.complete,
      loading: !reset && prior.loading,
      error: null,
    ),
  );
}

final class PersistenceIndexRead {
  PersistenceIndexRead(this.origin, this.collection, this.generation);
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final int generation;
  bool invalid = false;
  void Function()? cancel;
  void invalidate() {
    invalid = true;
  }

  bool covers(
    ProductReadOrigin source,
    ProductCollectionRef next,
    int currentGeneration,
  ) =>
      !invalid &&
      source == origin &&
      next == collection &&
      currentGeneration == generation;
}
