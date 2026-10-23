import '../../../resources.dart';
import 'configuration_read_fields.dart';

/// Query-local source changes only. 32 maximum-size native Data frames remain
/// within the original 8MiB/64-frame source-JSON ceiling; no wire/RSS claim.
final class ConfigurationReadChain {
  ConfigurationReadChain(this.origin, this.collection, {required this.orderStableForValueChanges});
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final bool orderStableForValueChanges;
  final List<_ConfigurationDelta> _changes = [];
  bool _overflow = false;

  void change(ProductReadOrigin source, int? base, ProductCollectionRef? next, List<ProductEntityRef> updates, List<int> removed) {
    if (_overflow) return;
    if (source != origin || _changes.length == 32) { _overflow = true; _changes.clear(); return; }
    _changes.add(_ConfigurationDelta(base, next, List.unmodifiable(updates), List.unmodifiable(removed)));
  }

  List<_ConfigurationDelta> _chain(ProductReadOrigin currentOrigin, ProductCollectionRef? current) {
    if (_overflow || currentOrigin != origin || current == null) throw configurationSuperseded;
    var previous = collection;
    for (final delta in _changes) {
      if (delta.base != previous.revision || delta.next == null || delta.next!.entry != previous.entry) throw configurationSuperseded;
      previous = delta.next!;
    }
    if (previous != current) throw configurationSuperseded;
    return _changes;
  }

  ProductEntityRef? entity(ProductEntityRef reference, ProductReadOrigin currentOrigin, ProductCollectionRef? current) {
    ProductEntityRef? latest = reference;
    for (final delta in _chain(currentOrigin, current)) {
      if (delta.removed.contains(reference.entry)) latest = null;
      for (final update in delta.updates) { if (update.entry == reference.entry) latest = update; }
    }
    return current?.total == 0 ? null : latest;
  }

  List<ProductEntityRef> page(List<ProductEntityRef> entries, ProductReadOrigin currentOrigin, ProductCollectionRef? current) {
    final values = List<ProductEntityRef>.of(entries);
    var total = collection.total;
    for (final delta in _chain(currentOrigin, current)) {
      if (delta.removed.isNotEmpty || delta.next!.total != total || !orderStableForValueChanges && delta.updates.isNotEmpty) throw configurationSuperseded;
      final changed = {for (final item in delta.updates) item.entry: item};
      for (var index = 0; index < values.length; index++) { values[index] = changed[values[index].entry] ?? values[index]; }
      total = delta.next!.total;
    }
    return List.unmodifiable(values);
  }
}

final class _ConfigurationDelta {
  const _ConfigurationDelta(this.base, this.next, this.updates, this.removed);
  final int? base;
  final ProductCollectionRef? next;
  final List<ProductEntityRef> updates;
  final List<int> removed;
}
