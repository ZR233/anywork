import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_values.dart';

const lspUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The LSP source has no current business value.',
  retryable: true,
  correlationId: 'lsp',
);
const lspSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original LSP read is no longer current.',
  retryable: true,
  correlationId: 'lsp',
);

Materialized<T, R>? lspPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? lspStale<T, R>(
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

ReadValue<T, R>? lspRebind<T, R>(
  ReadValue<T, R>? old,
  ProductReadOrigin origin,
  R? ref,
) {
  if (ref == null) return lspStale(old, lspUnavailable);
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
  final previous = lspPrevious(old);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: lspSuperseded,
          previous: previous,
        );
}

CollectionWindow<LspServer>? lspWindow(CollectionMirror<LspServer> value) =>
    switch (value) {
      CurrentCollectionMirror<LspServer>(:final window) => window,
      UnavailableCollectionMirror<LspServer>(:final lastKnown) => lastKnown,
    };

CollectionWindow<LspServer> lspEmptyWindow(
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

CollectionMirror<LspServer> lspBaseline(
  CollectionMirror<LspServer> old,
  ProductReadOrigin origin,
  ProductCollectionRef? ref,
) {
  final previous = lspWindow(old);
  if (ref == null)
    return CollectionMirror.unavailable(
      lastKnown: previous?.copyWith(loading: false),
    );
  if (ref.total < 0) throw resourceProtocol('Invalid LSP collection length.');
  if (previous?.origin == origin && previous?.reference == ref) {
    return CollectionMirror.current(window: previous!.copyWith(loading: false));
  }
  if (previous != null && ref.total != 0) {
    return CollectionMirror.unavailable(
      lastKnown: previous.copyWith(loading: false),
    );
  }
  return CollectionMirror.current(window: lspEmptyWindow(origin, ref));
}

CollectionMirror<LspServer> lspChange(
  CollectionMirror<LspServer> old,
  ProductReadOrigin origin,
  int? base,
  ProductCollectionRef? next,
  List<ProductEntityRef> upserted,
  List<int> removed,
) {
  if (upserted.length + removed.length > 100 ||
      upserted.map((ref) => ref.entry).toSet().length != upserted.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => upserted.any((ref) => ref.entry == entry))) {
    throw resourceProtocol('LSP delta has duplicate or contradictory entries.');
  }
  if (next == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty)
      throw resourceProtocol('Unavailable LSP source has an entity delta.');
    return CollectionMirror.unavailable(
      lastKnown: lspWindow(old)?.copyWith(loading: false),
    );
  }
  if (next.total < 0) throw resourceProtocol('Invalid LSP collection length.');
  if (old is! CurrentCollectionMirror<LspServer> || old.window.origin != origin)
    return lspBaseline(old, origin, next);
  final prior = old.window;
  if (prior.reference.revision != base)
    throw resourceProtocol('LSP collection revision gap.');
  if (prior.reference.entry != next.entry)
    return lspBaseline(old, origin, next);
  final updates = {for (final ref in upserted) ref.entry: ref};
  final rows = Map<int, ReadValue<LspServer, ProductEntityRef>>.of(prior.rows)
    ..removeWhere((entry, _) => removed.contains(entry));
  for (final ref in upserted) {
    if (rows.containsKey(ref.entry))
      rows[ref.entry] = lspRebind(rows[ref.entry], origin, ref)!;
  }
  // Native concatenates workspace snapshots. Equal public server IDs across
  // workspaces are not interchangeable; a new ordered collection needs its
  // native index. Never sort/deduplicate by the visible server ID in Dart.
  final reset = prior.reference != next || removed.isNotEmpty;
  return CollectionMirror.current(
    window: prior.copyWith(
      reference: next,
      entries: reset
          ? const []
          : [for (final ref in prior.entries) updates[ref.entry] ?? ref],
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

/// Only an admitted page retains this bounded, same-ordered-window ref chain.
final class LspIndexRead {
  LspIndexRead(this.origin, this.collection, this.generation);
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final int generation;
  final List<Map<int, ProductEntityRef>> _updates = [];
  bool invalid = false;
  void Function()? cancel;
  void invalidate() {
    invalid = true;
    _updates.clear();
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

  void changed(
    ProductReadOrigin source,
    int? base,
    ProductCollectionRef? next,
    List<ProductEntityRef> upserted,
    List<int> removed,
  ) {
    if (invalid) return;
    if (source != origin ||
        next != collection ||
        base != collection.revision ||
        removed.isNotEmpty ||
        _updates.length == 32) {
      invalidate();
      return;
    }
    _updates.add(
      Map.unmodifiable({for (final ref in upserted) ref.entry: ref}),
    );
  }

  List<ProductEntityRef> current(
    List<ProductEntityRef> refs,
    ProductReadOrigin source,
    ProductCollectionRef next,
    int currentGeneration,
  ) {
    if (!covers(source, next, currentGeneration)) throw lspSuperseded;
    var result = List<ProductEntityRef>.of(refs);
    for (final updates in _updates) {
      result = [for (final ref in result) updates[ref.entry] ?? ref];
    }
    return result;
  }
}
