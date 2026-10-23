import 'dart:async';

import '../../../resources.dart';
import '../../../resources_ports.dart';
import 'account_collection.dart';
import 'account_read_fields.dart';

typedef StatisticsDemand<R> = ({ProductReadOrigin? origin, R? reference, ProductCollectionRef? collection, Object? opening});
typedef StatisticsBinding<R> = ({ProductReadOrigin origin, R reference, ProductCollectionRef collection});
typedef StatisticsIndexPage = ({ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset});
typedef StatisticsMaterial<T, I> = ({T value, I refs});

/// Only bounded page mechanics shared by the two statistics collections. The
/// host's typed source is the canonical publisher; this object holds pending
/// requests and refs associated with its materialized rows, not a second store.
abstract interface class StatisticsPageHost<T, R, C> {
  ResourceLifetime get lifetime;
  StatisticsDemand<R> capture();
  Future<StatisticsBinding<R>> bind(StatisticsDemand<R> demand);
  bool current(StatisticsBinding<R> binding);
  PinnedReadOwner<C> pin(StatisticsBinding<R> binding);
  CollectionMirror<T> get mirror;
  void publish(CollectionMirror<T> value);
}

final class StatisticsPages<T, R, C, I> {
  StatisticsPages({required this.owner, required this.host, required this.entries, required this.materialize});
  final String owner;
  final StatisticsPageHost<T, R, C> host;
  final Future<StatisticsIndexPage> Function(C, int, int) entries;
  final Future<StatisticsMaterial<T, I>> Function(C, ProductReadOrigin, ProductEntityRef, T?, I?) materialize;
  final Map<({StatisticsDemand<R> demand, CollectionContinuation? continuation, int limit}), Future<void>> _pages = {};
  final Map<int, ({ProductReadOrigin origin, I refs})> _identities = {};
  int _generation = 0;

  void retain(ProductReadOrigin origin, CollectionMirror<T> mirror) {
    final known = accountWindow(mirror);
    _identities.removeWhere((entry, value) => value.origin != origin || known?.origin != origin || !known!.rows.containsKey(entry));
  }

  Future<void> page({int limit = 32}) {
    host.lifetime.admit();
    if (limit < 1 || limit > 100) throw const StudioFailure(code: StudioFailureCode.invalidArgument, message: 'A statistics page limit must be between 1 and 100.', retryable: false, correlationId: 'statistics');
    final demand = host.capture(); final mirror = host.mirror;
    final known = mirror is CurrentCollectionMirror<T> && mirror.window.origin == demand.origin && mirror.window.reference == demand.collection ? mirror.window : null;
    if (known != null && known.complete && known.error == null) return Future.value();
    final key = (demand: demand, continuation: known?.continuation, limit: limit);
    final pending = _pages[key]; if (pending != null) return pending;
    final done = Completer<void>(); _pages[key] = done.future; final generation = ++_generation;
    host.lifetime.run(owner, () async {
      final binding = await host.bind(demand);
      if (!host.current(binding)) throw accountDataSuperseded;
      final previous = accountWindow(host.mirror);
      final active = host.mirror;
      final window = active is CurrentCollectionMirror<T> && active.window.origin == binding.origin && active.window.reference == binding.collection ? active.window : emptyAccountWindow<T>(binding.origin, binding.collection);
      final offset = switch (window.continuation) { OffsetCollectionContinuation(:final value) => value, EndCollectionContinuation() => binding.collection.total, _ => 0 };
      host.publish(CollectionMirror.current(window: window.copyWith(loading: true, error: null)));
      try {
        await host.pin(binding).use((scope) async {
          final page = await entries(scope, offset, limit); final end = offset + page.items.length;
          if (page.collection != binding.collection || page.offset != offset || page.items.length > limit || end < offset || end > binding.collection.total || page.items.isEmpty && end < binding.collection.total || page.nextOffset != (end == binding.collection.total ? null : end)) throw accountDataProtocol('A statistics index page does not match its original collection.');
          final prefix = window.entries.take(offset).toList();
          if (prefix.length != offset) throw accountDataSuperseded;
          final seen = prefix.map((item) => item.entry).toSet();
          final rows = Map<int, ReadValue<T, ProductEntityRef>>.of(window.rows);
          final identities = <int, I>{}; StudioFailure? failure;
          for (final reference in page.items) {
            if (!seen.add(reference.entry)) throw accountDataProtocol('A statistics index page repeated an entry.');
            final prior = previous?.origin == binding.origin ? previous!.rows[reference.entry] : null;
            final old = accountPrevious(prior);
            if (prior is ReadyReadValue<T, ProductEntityRef> && prior.current.reference == reference) { rows[reference.entry] = prior; continue; }
            try {
              final refs = _identities[reference.entry];
              final material = await materialize(scope, binding.origin, reference, old?.value, refs?.origin == binding.origin ? refs!.refs : null);
              identities[reference.entry] = material.refs;
              rows[reference.entry] = ReadValue.ready(current: Materialized(origin: binding.origin, reference: reference, value: material.value));
            } catch (error) {
              failure ??= accountDataFailure(error);
              rows[reference.entry] = ReadValue.failed(origin: binding.origin, reference: reference, error: accountDataFailure(error), previous: old);
            }
          }
          if (host.lifetime.sealed) throw resourceCancelled;
          // Without a complete source delta chain, a changed collection is not
          // patched by offset guesses. Old pins finish but cannot replace it.
          if (generation != _generation || !host.current(binding)) throw accountDataSuperseded;
          for (final entry in identities.entries) { _identities[entry.key] = (origin: binding.origin, refs: entry.value); }
          final next = CollectionMirror<T>.current(window: window.copyWith(entries: [...prefix, ...page.items], rows: rows, continuation: failure != null ? CollectionContinuation.offset(value: offset) : page.nextOffset == null ? const CollectionContinuation.end() : CollectionContinuation.offset(value: page.nextOffset!), complete: failure == null && page.nextOffset == null && end == binding.collection.total, loading: false, error: failure));
          retain(binding.origin, next);
          host.publish(next);
          if (failure != null) throw failure;
        });
      } catch (error) {
        final latest = host.mirror;
        if (!host.lifetime.sealed && generation == _generation && host.current(binding) && latest is CurrentCollectionMirror<T>) host.publish(CollectionMirror.current(window: latest.window.copyWith(loading: false, error: accountDataFailure(error))));
        rethrow;
      }
    }).then((_) { _pages.remove(key); done.complete(); }, onError: (Object error, StackTrace stack) { _pages.remove(key); done.completeError(accountDataFailure(error), stack); });
    return done.future;
  }
}
