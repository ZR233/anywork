import '../../../resources.dart';
import 'account_read_fields.dart';

CollectionWindow<T>? accountWindow<T>(CollectionMirror<T> mirror) =>
    switch (mirror) {
      CurrentCollectionMirror<T>(:final window) => window,
      UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
    };

CollectionWindow<T> emptyAccountWindow<T>(
  ProductReadOrigin origin,
  ProductCollectionRef collection,
) => CollectionWindow(
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
);

CollectionMirror<T> accountCollectionBaseline<T>(
  CollectionMirror<T> previous,
  ProductReadOrigin origin,
  ProductCollectionRef? collection,
) {
  final old = accountWindow(previous);
  if (collection == null) return CollectionMirror.unavailable(lastKnown: old);
  if (collection.total < 0)
    throw accountDataProtocol('A collection has an invalid length.');
  if (old?.origin == origin && old?.reference == collection)
    return CollectionMirror.current(window: old!);
  if (old != null && collection.total != 0)
    return CollectionMirror.unavailable(lastKnown: old);
  return CollectionMirror.current(
    window: emptyAccountWindow(origin, collection),
  );
}

CollectionMirror<T> accountCollectionChange<T>(
  CollectionMirror<T> previous,
  ProductReadOrigin origin,
  ProductCollectionRef? collection,
  List<ProductEntityRef> updates,
  List<int> removed,
) {
  if (updates.length + removed.length > 100 ||
      updates.map((item) => item.entry).toSet().length != updates.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => updates.any((item) => item.entry == entry)))
    throw accountDataProtocol(
      'A collection delta has inconsistent membership.',
    );
  if (collection == null) {
    if (updates.isNotEmpty || removed.isNotEmpty)
      throw accountDataProtocol('An unavailable source has entity changes.');
    return CollectionMirror.unavailable(lastKnown: accountWindow(previous));
  }
  if (previous is! CurrentCollectionMirror<T> ||
      previous.window.origin != origin)
    return accountCollectionBaseline(previous, origin, collection);
  final old = previous.window;
  if (collection.entry != old.reference.entry || collection.total < 0)
    throw accountDataProtocol('A collection delta changed its identity.');
  if (collection == old.reference && (updates.isNotEmpty || removed.isNotEmpty))
    throw accountDataProtocol(
      'An entity changed without advancing its collection.',
    );
  if (collection.total == 0)
    return CollectionMirror.current(
      window: emptyAccountWindow(origin, collection),
    );
  final rows = Map<int, ReadValue<T, ProductEntityRef>>.of(old.rows)
    ..removeWhere((entry, _) => removed.contains(entry));
  for (final reference in updates) {
    final known = accountPrevious(rows[reference.entry]);
    rows[reference.entry] = known == null
        ? ReadValue.unloaded(origin: origin, reference: reference)
        : known.reference == reference
        ? rows[reference.entry]!
        : ReadValue.failed(
            origin: origin,
            reference: reference,
            error: accountDataSuperseded,
            previous: known,
          );
  }
  final orderChanged =
      updates.isNotEmpty ||
      removed.isNotEmpty ||
      collection.total != old.reference.total;
  return CollectionMirror.current(
    window: old.copyWith(
      reference: collection,
      entries: orderChanged ? const [] : old.entries,
      rows: rows,
      continuation: orderChanged
          ? const CollectionContinuation.unknown()
          : old.continuation,
      complete: !orderChanged && old.complete,
      loading: orderChanged ? false : old.loading,
      error: null,
    ),
  );
}
