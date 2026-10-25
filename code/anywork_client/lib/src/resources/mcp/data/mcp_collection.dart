import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_values.dart';

const mcpUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The MCP source has no current business value.',
  retryable: true,
  correlationId: 'mcp',
);
const mcpSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original MCP read is no longer current.',
  retryable: true,
  correlationId: 'mcp',
);

Materialized<T, R>? mcpPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? mcpRebind<T, R>(
  ReadValue<T, R>? old,
  ProductReadOrigin origin,
  R? ref,
) {
  if (ref == null) return mcpStale(old, mcpUnavailable);
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
  final previous = mcpPrevious(old);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: mcpSuperseded,
          previous: previous,
        );
}

ReadValue<T, R>? mcpRetire<T, R>(ReadValue<T, R>? value, StudioFailure error) =>
    switch (value) {
      LoadingReadValue<T, R>(
        :final origin,
        :final reference,
        :final previous,
      ) =>
        ReadValue.failed(
          origin: origin,
          reference: reference,
          error: error,
          previous: previous,
        ),
      _ => value,
    };

ReadValue<T, R>? mcpStale<T, R>(
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

CollectionWindow<McpServer>? mcpWindow(CollectionMirror<McpServer> value) =>
    switch (value) {
      CurrentCollectionMirror<McpServer>(:final window) => window,
      UnavailableCollectionMirror<McpServer>(:final lastKnown) => lastKnown,
    };

CollectionWindow<McpServer> mcpEmptyWindow(
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

CollectionMirror<McpServer> mcpServersBaseline(
  CollectionMirror<McpServer> old,
  ProductReadOrigin origin,
  ProductCollectionRef? ref,
) {
  final previous = mcpWindow(old);
  if (ref == null)
    return CollectionMirror.unavailable(
      lastKnown: previous?.copyWith(loading: false),
    );
  if (ref.total < 0) throw resourceProtocol('Invalid MCP collection length.');
  if (previous?.origin == origin && previous?.reference == ref) {
    return CollectionMirror.current(window: previous!.copyWith(loading: false));
  }
  if (previous != null && ref.total != 0) {
    return CollectionMirror.unavailable(
      lastKnown: previous.copyWith(loading: false),
    );
  }
  return CollectionMirror.current(window: mcpEmptyWindow(origin, ref));
}

CollectionMirror<McpServer> mcpServersChange(
  CollectionMirror<McpServer> old,
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
    throw resourceProtocol('MCP delta has duplicate or contradictory entries.');
  }
  if (next == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty) {
      throw resourceProtocol('Unavailable MCP source has an entity delta.');
    }
    return CollectionMirror.unavailable(
      lastKnown: mcpWindow(old)?.copyWith(loading: false),
    );
  }
  if (next.total < 0) throw resourceProtocol('Invalid MCP collection length.');
  if (old is! CurrentCollectionMirror<McpServer> ||
      old.window.origin != origin) {
    return mcpServersBaseline(old, origin, next);
  }
  final prior = old.window;
  if (prior.reference.revision != base)
    throw resourceProtocol('MCP collection revision gap.');
  if (prior.reference.entry != next.entry)
    return mcpServersBaseline(old, origin, next);
  final updates = {for (final ref in upserted) ref.entry: ref};
  final rows = Map<int, ReadValue<McpServer, ProductEntityRef>>.of(prior.rows)
    ..removeWhere((entry, _) => removed.contains(entry));
  for (final ref in upserted) {
    if (rows.containsKey(ref.entry))
      rows[ref.entry] = mcpRebind(rows[ref.entry], origin, ref)!;
  }
  // Native builds this list from BTreeMap<serverId, config>. Existing entry IDs
  // cannot move merely because health/text changes; membership changes require
  // the original index again. Dart does not sort or invent missing members.
  final membership = prior.reference.total != next.total || removed.isNotEmpty;
  return CollectionMirror.current(
    window: prior.copyWith(
      reference: next,
      entries: membership
          ? const []
          : [for (final ref in prior.entries) updates[ref.entry] ?? ref],
      rows: next.total == 0 ? const {} : rows,
      continuation: next.total == 0
          ? const CollectionContinuation.end()
          : membership
          ? const CollectionContinuation.unknown()
          : prior.continuation,
      complete: next.total == 0 || !membership && prior.complete,
      loading: !membership && prior.loading,
      error: null,
    ),
  );
}

/// A page-only bounded ref chain, not a second source or full payload cache.
final class McpIndexRead {
  McpIndexRead(this.origin, this.collection, this.generation)
    : _at = collection;
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final int generation;
  ProductCollectionRef _at;
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
      next == _at &&
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
        base != _at.revision ||
        next == null ||
        next.entry != _at.entry ||
        next.total != _at.total ||
        removed.isNotEmpty ||
        _updates.length == 32) {
      invalidate();
      return;
    }
    _updates.add(
      Map.unmodifiable({for (final ref in upserted) ref.entry: ref}),
    );
    _at = next;
  }

  List<ProductEntityRef> current(
    List<ProductEntityRef> refs,
    ProductReadOrigin source,
    ProductCollectionRef next,
    int currentGeneration,
  ) {
    if (invalid ||
        source != origin ||
        next != _at ||
        currentGeneration != generation)
      throw mcpSuperseded;
    var result = List<ProductEntityRef>.of(refs);
    for (final updates in _updates) {
      result = [for (final ref in result) updates[ref.entry] ?? ref];
    }
    return result;
  }
}
