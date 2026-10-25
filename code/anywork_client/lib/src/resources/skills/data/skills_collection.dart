import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_values.dart';

const skillsUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The project Skills catalog has no current value.',
  retryable: true,
  correlationId: 'skills',
);
const skillsSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original Skills catalog read is no longer current.',
  retryable: true,
  correlationId: 'skills',
);

Materialized<T, R>? skillsPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? skillsStale<T, R>(
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

ReadValue<T, R>? skillsRebind<T, R>(
  ReadValue<T, R>? old,
  ProductReadOrigin origin,
  R? ref,
) {
  if (ref == null) return skillsStale(old, skillsUnavailable);
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
  if (same) return old;
  final previous = skillsPrevious(old);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: skillsSuperseded,
          previous: previous,
        );
}

CollectionWindow<SkillSummary>? skillsWindow(
  CollectionMirror<SkillSummary> value,
) => switch (value) {
  CurrentCollectionMirror<SkillSummary>(:final window) => window,
  UnavailableCollectionMirror<SkillSummary>(:final lastKnown) => lastKnown,
};

CollectionWindow<SkillSummary> skillsEmptyWindow(
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

CollectionMirror<SkillSummary> skillsBaseline(
  CollectionMirror<SkillSummary> old,
  ProductReadOrigin origin,
  ProductCollectionRef? ref,
) {
  final previous = skillsWindow(old);
  if (ref == null)
    return CollectionMirror.unavailable(
      lastKnown: previous?.copyWith(loading: false),
    );
  if (ref.entry < 0 || ref.revision < 0 || ref.total < 0)
    throw resourceProtocol('Invalid Skills collection.');
  if (previous?.origin == origin && previous?.reference == ref) {
    return CollectionMirror.current(window: previous!.copyWith(loading: false));
  }
  if (previous != null && ref.total != 0) {
    return CollectionMirror.unavailable(
      lastKnown: previous.copyWith(loading: false),
    );
  }
  return CollectionMirror.current(window: skillsEmptyWindow(origin, ref));
}

CollectionMirror<SkillSummary> skillsChange(
  CollectionMirror<SkillSummary> old,
  ProductReadOrigin origin,
  int? base,
  ProductCollectionRef? next,
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
      'Skills delta contains invalid or contradictory entries.',
    );
  }
  if (next == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty)
      throw resourceProtocol('Unavailable Skills catalog has a delta.');
    return CollectionMirror.unavailable(
      lastKnown: skillsWindow(old)?.copyWith(loading: false),
    );
  }
  if (next.entry < 0 || next.revision < 0 || next.total < 0)
    throw resourceProtocol('Invalid Skills collection.');
  if (old is! CurrentCollectionMirror<SkillSummary> ||
      old.window.origin != origin) {
    return skillsBaseline(old, origin, next);
  }
  final prior = old.window;
  if (prior.reference.revision != base)
    throw resourceProtocol('Skills collection revision gap.');
  if (prior.reference.entry != next.entry)
    return skillsBaseline(old, origin, next);
  final rows = Map<int, ReadValue<SkillSummary, ProductEntityRef>>.of(
    prior.rows,
  )..removeWhere((entry, _) => removed.contains(entry));
  for (final ref in upserted) {
    if (rows.containsKey(ref.entry))
      rows[ref.entry] = skillsRebind(rows[ref.entry], origin, ref)!;
  }
  // Catalog/provider winner order belongs to native. New membership or bodies
  // require its ordered index, never a Dart name sort or second winner policy.
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

/// One immutable native index; any intervening catalog delta invalidates it.
final class SkillsIndexRead {
  SkillsIndexRead(this.origin, this.collection, this.generation);
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
    ProductCollectionRef? next,
    int currentGeneration,
  ) =>
      !invalid &&
      source == origin &&
      next == collection &&
      currentGeneration == generation;
}
