import 'package:anywork_client/resources.dart';

import 'read_values.dart';

CollectionWindow<T>? displayCollection<T>(CollectionMirror<T> mirror) =>
    switch (mirror) {
      CurrentCollectionMirror<T>(:final window) => window,
      UnavailableCollectionMirror<T>(:final lastKnown) => lastKnown,
    };

List<T> displayCollectionRows<T>(CollectionMirror<T> mirror) {
  final window = displayCollection(mirror);
  return [
    if (window != null)
      for (final reference in window.entries)
        ?displayReadValue(window.rows[reference.entry]),
  ];
}

Materialized<T, ProductEntityRef>? currentCollectionRow<T>(
  CollectionMirror<T> mirror,
  ProductReadOrigin? origin,
  bool Function(T value) predicate,
) {
  if (mirror is! CurrentCollectionMirror<T> || mirror.window.origin != origin) {
    return null;
  }
  final window = mirror.window;
  for (final reference in window.entries) {
    final row = window.rows[reference.entry];
    if (row is ReadyReadValue<T, ProductEntityRef> &&
        row.current.origin == origin &&
        row.current.reference == reference &&
        predicate(row.current.value)) {
      return row.current;
    }
  }
  return null;
}

bool collectionComplete<T>(
  CollectionMirror<T> mirror,
  ProductReadOrigin? origin,
) {
  if (mirror is! CurrentCollectionMirror<T> || mirror.window.origin != origin) {
    return false;
  }
  final window = mirror.window;
  return window.complete &&
      window.entries.length == window.reference.total &&
      window.entries.every((reference) {
        final row = window.rows[reference.entry];
        return row is ReadyReadValue<T, ProductEntityRef> &&
            row.current.origin == origin &&
            row.current.reference == reference;
      });
}
