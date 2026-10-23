import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_values.dart';

const recoverySuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The frozen recovery read no longer describes the current query.',
  retryable: true,
  correlationId: 'recovery',
);

Materialized<T, R>? recoveryPrevious<T, R>(ReadValue<T, R>? value) => switch (value) {
  ReadyReadValue<T, R>(:final current) => current,
  LoadingReadValue<T, R>(:final previous) || FailedReadValue<T, R>(:final previous) => previous,
  _ => null,
};

ReadValue<T, R> recoveryRebind<T, R>(ReadValue<T, R>? old,
    ProductReadOrigin origin, R reference) {
  final same = switch (old) {
    ReadyReadValue<T, R>(:final current) => current.origin == origin && current.reference == reference,
    UnloadedReadValue<T, R>(origin: final prior, reference: final ref) ||
    LoadingReadValue<T, R>(origin: final prior, reference: final ref) ||
    FailedReadValue<T, R>(origin: final prior, reference: final ref) => prior == origin && ref == reference,
    null => false,
  };
  if (same) return old!;
  final previous = recoveryPrevious(old);
  return previous == null ? ReadValue.unloaded(origin: origin, reference: reference)
      : ReadValue.failed(origin: origin, reference: reference,
          error: recoverySuperseded, previous: previous);
}

CollectionWindow<RecoveryIssue>? recoveryWindow(CollectionMirror<RecoveryIssue> mirror) =>
    switch (mirror) {
      CurrentCollectionMirror<RecoveryIssue>(:final window) => window,
      UnavailableCollectionMirror<RecoveryIssue>(:final lastKnown) => lastKnown,
    };

CollectionMirror<RecoveryIssue> recoveryBaseline(CollectionMirror<RecoveryIssue> old,
    ProductReadOrigin origin, ProductCollectionRef? reference) {
  final prior = recoveryWindow(old);
  if (reference == null) return CollectionMirror.unavailable(lastKnown: prior?.copyWith(loading: false));
  if (reference.total < 0) throw resourceProtocol('Invalid recovery collection length.');
  if (prior?.origin == origin && prior?.reference == reference) {
    return CollectionMirror.current(window: prior!.copyWith(loading: false));
  }
  if (prior != null && reference.total != 0) {
    return CollectionMirror.unavailable(lastKnown: prior.copyWith(loading: false));
  }
  return CollectionMirror.current(window: recoveryEmptyWindow(origin, reference));
}

CollectionWindow<RecoveryIssue> recoveryEmptyWindow(
    ProductReadOrigin origin, ProductCollectionRef reference) => CollectionWindow(
  origin: origin, reference: reference, entries: const [], rows: const {},
  continuation: reference.total == 0 ? const CollectionContinuation.end()
      : const CollectionContinuation.unknown(),
  complete: reference.total == 0, loading: false, error: null,
);

void checkRecoveryDelta(List<ProductEntityRef> upserted, List<int> removed) {
  if (upserted.length + removed.length > 100 ||
      upserted.map((ref) => ref.entry).toSet().length != upserted.length ||
      removed.toSet().length != removed.length ||
      removed.any((entry) => upserted.any((ref) => ref.entry == entry))) {
    throw resourceProtocol('Recovery delta has duplicate or contradictory members.');
  }
}

CollectionMirror<RecoveryIssue> recoveryChange(CollectionMirror<RecoveryIssue> old,
    ProductReadOrigin origin, int? baseRevision, ProductCollectionRef? next,
    List<ProductEntityRef> upserted, List<int> removed) {
  checkRecoveryDelta(upserted, removed);
  if (next == null) {
    if (upserted.isNotEmpty || removed.isNotEmpty) {
      throw resourceProtocol('Unavailable recovery value contains an entity delta.');
    }
    return CollectionMirror.unavailable(lastKnown: recoveryWindow(old)?.copyWith(loading: false));
  }
  if (next.total < 0) throw resourceProtocol('Invalid recovery collection length.');
  if (old is! CurrentCollectionMirror<RecoveryIssue> || old.window.origin != origin) {
    return recoveryBaseline(old, origin, next);
  }
  final prior = old.window;
  if (prior.reference.entry != next.entry || prior.reference.revision != baseRevision) {
    throw resourceProtocol('Recovery collection revision gap.');
  }
  final updates = {for (final ref in upserted) ref.entry: ref};
  final rows = Map<int, ReadValue<RecoveryIssue, ProductEntityRef>>.of(prior.rows)
    ..removeWhere((entry, _) => removed.contains(entry));
  for (final entry in updates.entries) {
    if (rows.containsKey(entry.key)) {
      rows[entry.key] = recoveryRebind(rows[entry.key], origin, entry.value);
    }
  }
  // The native registry is a Vec: update_if_current removes an issue and
  // appends it. Even unchanged membership can reorder, so a new collection
  // identity requires its native index; only the same ordered window is patched.
  final membership = removed.isNotEmpty || prior.reference != next;
  return CollectionMirror.current(window: prior.copyWith(
    reference: next,
    entries: membership ? const [] : [for (final ref in prior.entries) updates[ref.entry] ?? ref],
    rows: next.total == 0 ? const {} : rows,
    continuation: next.total == 0 ? const CollectionContinuation.end()
        : membership ? const CollectionContinuation.unknown() : prior.continuation,
    complete: next.total == 0 || !membership && prior.complete,
    loading: !membership && prior.loading, error: null,
  ));
}

/// Only admitted page reads retain a chain. 32 native Data frames, each bounded
/// to 256KiB source JSON, stay within the 64-frame / 8MiB retention ceiling.
final class RecoveryIndexRead {
  RecoveryIndexRead(this.origin, this.collection, this.generation);
  final ProductReadOrigin origin;
  final ProductCollectionRef collection;
  final int generation;
  final List<RecoveryChangeRecord> changes = [];
  bool invalid = false;
  void Function()? cancel;

  void changed(ProductReadOrigin source, int? base, ProductCollectionRef? next,
      List<ProductEntityRef> upserted, List<int> removed) {
    if (invalid) return;
    if (source != origin || changes.length == 32 || next != collection || removed.isNotEmpty) {
      invalid = true;
      changes.clear();
      return;
    }
    changes.add(RecoveryChangeRecord(base, next,
      List.unmodifiable(upserted), List.unmodifiable(removed)));
  }

  List<ProductEntityRef> current(List<ProductEntityRef> entries,
      ProductReadOrigin source, ProductCollectionRef? next, int currentGeneration) {
    if (invalid || generation != currentGeneration || source != origin || next == null) {
      throw recoverySuperseded;
    }
    var reference = collection;
    final refs = List.of(entries);
    for (final delta in changes) {
      if (delta.base != reference.revision || delta.next == null ||
          delta.next!.entry != reference.entry || delta.removed.isNotEmpty ||
          delta.next!.total != reference.total) throw recoverySuperseded;
      final updates = {for (final ref in delta.upserted) ref.entry: ref};
      for (var index = 0; index < refs.length; index++) {
        refs[index] = updates[refs[index].entry] ?? refs[index];
      }
      reference = delta.next!;
    }
    if (reference != next) throw recoverySuperseded;
    return List.unmodifiable(refs);
  }
}

final class RecoveryChangeRecord {
  const RecoveryChangeRecord(this.base, this.next, this.upserted, this.removed);
  final int? base;
  final ProductCollectionRef? next;
  final List<ProductEntityRef> upserted;
  final List<int> removed;
}
