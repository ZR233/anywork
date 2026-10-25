import '../../../resources.dart';
import '../../../resources_ports.dart' show resourceProtocol;

Materialized<T, R>? modelPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

CollectionWindow<T>? modelWindow<T>(CollectionMirror<T> mirror) =>
    switch (mirror) {
      CurrentCollectionMirror<T>(:final window) => window,
      UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
    };

CollectionMirror<T> modelCollectionBaseline<T>(
  CollectionMirror<T> previous,
  ProductReadOrigin origin,
  ProductCollectionRef? collection,
) {
  final old = modelWindow(previous);
  if (collection == null) return CollectionMirror.unavailable(lastKnown: old);
  if (collection.total < 0)
    throw resourceProtocol('A model collection has an invalid length.');
  if (old?.origin == origin && old?.reference == collection)
    return CollectionMirror.current(window: old!);
  if (old != null && collection.total != 0)
    return CollectionMirror.unavailable(lastKnown: old);
  return CollectionMirror.current(
    window: CollectionWindow(
      origin: origin,
      reference: collection,
      entries: const [],
      rows: const {},
      continuation: collection.total == 0
          ? const CollectionContinuation.end()
          : const CollectionContinuation.unknown(),
      complete: collection.total == 0,
      loading: false,
      error: null,
    ),
  );
}

CollectionMirror<T> modelCollectionChange<T>(
  CollectionMirror<T> previous,
  ProductReadOrigin origin,
  int? baseRevision,
  ProductCollectionRef? collection,
  List<ProductEntityRef> upserted,
  List<int> removed,
) {
  if (upserted.length + removed.length > 100 ||
      upserted.map((item) => item.entry).toSet().length != upserted.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => upserted.any((item) => item.entry == entry))) {
    throw resourceProtocol(
      'A model collection delta has inconsistent members.',
    );
  }
  final old = previous is CurrentCollectionMirror<T> ? previous.window : null;
  if (collection == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty)
      throw resourceProtocol(
        'An unavailable model collection has an entity delta.',
      );
    return CollectionMirror.unavailable(lastKnown: modelWindow(previous));
  }
  if (collection.total < 0)
    throw resourceProtocol('A model collection has an invalid length.');
  if (old == null || old.origin != origin)
    return modelCollectionBaseline(previous, origin, collection);
  if (baseRevision != old.reference.revision ||
      old.reference.entry != collection.entry)
    throw resourceProtocol('A model collection delta has a revision gap.');
  final updates = {for (final item in upserted) item.entry: item};
  final rows = Map<int, ReadValue<T, ProductEntityRef>>.of(old.rows)
    ..removeWhere((entry, _) => removed.contains(entry));
  for (final entry in updates.entries) {
    final oldRow = rows[entry.key];
    if (oldRow == null || modelPrevious(oldRow)?.reference == entry.value)
      continue;
    rows[entry.key] = ReadValue.failed(
      origin: origin,
      reference: entry.value,
      error: modelsSuperseded,
      previous: modelPrevious(oldRow),
    );
  }
  // Accounts are canonically ordered by their stable BTreeMap account ID. A
  // value-only change preserves that order. Membership changes require a new
  // index page; guessed insertion positions must not become canonical order.
  final membershipChanged =
      removed.isNotEmpty || collection.total != old.reference.total;
  return CollectionMirror.current(
    window: old.copyWith(
      reference: collection,
      entries: membershipChanged
          ? const []
          : [for (final item in old.entries) updates[item.entry] ?? item],
      rows: collection.total == 0 ? const {} : rows,
      continuation: collection.total == 0
          ? const CollectionContinuation.end()
          : membershipChanged
          ? const CollectionContinuation.unknown()
          : old.continuation,
      complete: collection.total == 0 || !membershipChanged && old.complete,
      loading: old.reference == collection && old.loading,
      error: null,
    ),
  );
}

const modelsSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The requested model collection version has advanced.',
  retryable: true,
  correlationId: 'models-read',
);

/// Only active reads retain deltas. Each native Data is at most 256KiB source
/// JSON, so 32 retained frames conservatively stay within the 8MiB/64-frame
/// ceiling, without inventing a wire-byte/RSS measurement or another codec.
final class ModelCollectionRead {
  ModelCollectionRead(this.origin, this.collection);
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final List<ModelReadDelta> _changes = [];
  bool _overflow = false;

  void changed(
    ProductReadOrigin source,
    int? baseRevision,
    ProductCollectionRef? next,
    List<ProductEntityRef> upserted,
    List<int> removed,
  ) {
    if (_overflow) return;
    if (source != origin || _changes.length == 32) {
      _overflow = true;
      _changes.clear();
      return;
    }
    _changes.add(
      ModelReadDelta(
        baseRevision,
        next,
        List.unmodifiable(upserted),
        List.unmodifiable(removed),
      ),
    );
  }

  List<ModelReadDelta> chain(
    ProductReadOrigin currentOrigin,
    ProductCollectionRef? current,
  ) {
    if (_overflow || currentOrigin != origin || current == null)
      throw modelsSuperseded;
    var reference = collection;
    for (final change in _changes) {
      if (change.baseRevision != reference.revision ||
          change.next == null ||
          change.next!.entry != reference.entry)
        throw modelsSuperseded;
      reference = change.next!;
    }
    if (reference != current) throw modelsSuperseded;
    return _changes;
  }

  ProductEntityRef? currentEntity(
    ProductEntityRef reference,
    ProductReadOrigin currentOrigin,
    ProductCollectionRef? current,
  ) {
    ProductEntityRef? result = reference;
    for (final delta in chain(currentOrigin, current)) {
      if (delta.removed.contains(reference.entry)) result = null;
      for (final update in delta.upserted) {
        if (update.entry == reference.entry) result = update;
      }
    }
    if (current?.total == 0) return null;
    return result;
  }

  List<ProductEntityRef> page(
    List<ProductEntityRef> entries,
    ProductReadOrigin currentOrigin,
    ProductCollectionRef? current,
  ) {
    var total = collection.total;
    final refs = List<ProductEntityRef>.of(entries);
    for (final delta in chain(currentOrigin, current)) {
      if (delta.removed.isNotEmpty || delta.next!.total != total)
        throw modelsSuperseded;
      final updates = {for (final item in delta.upserted) item.entry: item};
      for (var index = 0; index < refs.length; index++) {
        refs[index] = updates[refs[index].entry] ?? refs[index];
      }
      total = delta.next!.total;
    }
    return List.unmodifiable(refs);
  }
}

final class ModelReadDelta {
  const ModelReadDelta(
    this.baseRevision,
    this.next,
    this.upserted,
    this.removed,
  );
  final int? baseRevision;
  final ProductCollectionRef? next;
  final List<ProductEntityRef> upserted;
  final List<int> removed;
}
