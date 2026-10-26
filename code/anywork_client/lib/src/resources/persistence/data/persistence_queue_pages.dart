import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_collection.dart';
import 'persistence_field_reads.dart';
import 'persistence_queue_mirror.dart';
import 'persistence_reader.dart';

typedef _PageKey = ({
  int generation,
  ProductReadOrigin? origin,
  PersistenceQueueReadRef? reference,
  ProductCollectionRef? collection,
  CollectionContinuation? continuation,
  int limit,
});

final class PersistenceQueuePages {
  PersistenceQueuePages(this.mirror, this.reads, this.lifetime);
  final PersistenceQueueMirror mirror;
  final PersistenceReads reads;
  final ResourceLifetime lifetime;
  final Map<_PageKey, Future<void>> _jobs = {};
  final Map<int, ({int generation, PersistenceIndexRead? read})> _active = {};
  int _sequence = 0;

  CollectionWindow<ThreadPersistenceSnapshot> _window(
    PersistenceQueueBinding binding,
  ) {
    final value = mirror.source.value.threads;
    return value is CurrentCollectionMirror<ThreadPersistenceSnapshot> &&
            value.window.origin == binding.origin &&
            value.window.reference == binding.collection
        ? value.window
        : persistenceEmptyWindow(binding.origin, binding.collection);
  }

  bool _ready(
    ReadValue<ThreadPersistenceSnapshot, ProductEntityRef>? value,
    ProductReadOrigin origin,
    ProductEntityRef ref,
  ) =>
      value is ReadyReadValue<ThreadPersistenceSnapshot, ProductEntityRef> &&
      value.current.origin == origin &&
      value.current.reference == ref;

  bool _loading(PersistenceQueueBinding binding, {int? except}) =>
      _active.entries.any((entry) {
        if (entry.key == except || entry.value.generation != binding.generation)
          return false;
        final read = entry.value.read;
        return read == null ||
            read.covers(binding.origin, binding.collection, binding.generation);
      });

  void adopted(PersistenceQueueBinding binding) {
    for (final read in List.of(mirror.reads)) {
      if (read.invalid) read.cancel?.call();
    }
  }

  void _refresh() {
    if (lifetime.sealed) return;
    final binding = mirror.current;
    final value = mirror.source.value.threads;
    if (binding == null ||
        value is! CurrentCollectionMirror<ThreadPersistenceSnapshot> ||
        value.window.origin != binding.origin ||
        value.window.reference != binding.collection)
      return;
    final loading = _loading(binding);
    if (value.window.loading != loading)
      mirror.source.publish(
        mirror.source.value.copyWith(
          threads: CollectionMirror.current(
            window: value.window.copyWith(loading: loading),
          ),
        ),
      );
  }

  Future<void> load({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100)
      throw const StudioFailure(
        code: StudioFailureCode.invalidArgument,
        message: 'A persistence queue page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'persistence',
      );
    final demand = mirror.capture();
    final binding = demand.binding;
    final snapshot = binding == null ? null : _window(binding);
    if (snapshot != null &&
        snapshot.complete &&
        snapshot.entries.every(
          (ref) => _ready(snapshot.rows[ref.entry], snapshot.origin, ref),
        ))
      return Future.value();
    final key = (
      generation: demand.generation,
      origin: binding?.origin,
      reference: binding?.header.reference,
      collection: binding?.collection,
      continuation: snapshot?.continuation,
      limit: limit,
    );
    if (_jobs[key] case final pending?) return pending;
    final done = Completer<void>();
    _jobs[key] = done.future;
    final keys = <_PageKey>{key};
    void remove() {
      for (final key in keys) {
        if (identical(_jobs[key], done.future)) unawaited(_jobs.remove(key));
      }
    }

    final task = ++_sequence;
    _active[task] = (generation: demand.generation, read: null);
    PersistenceQueueBinding? original;
    PersistenceIndexRead? index;
    CollectionWindow<ThreadPersistenceSnapshot>? frozenWindow;
    Future<void>? joined;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('persistence-queue-page', () async {
          final frozen = await mirror.ready(
            demand,
            bind: (binding) {
              final window = snapshot ?? _window(binding);
              final canonical = (
                generation: binding.generation,
                origin: binding.origin,
                reference: binding.header.reference,
                collection: binding.collection,
                continuation: window.continuation,
                limit: limit,
              );
              final pending = _jobs[canonical];
              if (pending != null && !identical(pending, done.future)) {
                joined = pending;
                return;
              }
              _jobs[canonical] = done.future;
              keys.add(canonical);
              original = binding;
              frozenWindow = window;
              index = PersistenceIndexRead(
                binding.origin,
                binding.collection,
                binding.generation,
              );
              _active[task] = (generation: binding.generation, read: index);
              mirror.reads.add(index!);
            },
          );
          if (joined case final pending?) {
            _active.remove(task);
            await pending;
            return;
          }
          final read = index!;
          try {
            mirror.check(frozen);
            if (read.invalid) throw persistenceSuperseded;
            final prior = frozenWindow!;
            final dirty = prior.entries
                .where(
                  (ref) => !_ready(prior.rows[ref.entry], prior.origin, ref),
                )
                .take(limit)
                .toList();
            if (prior.complete && dirty.isEmpty) return;
            final visible = mirror.source.value.threads;
            if (visible is CurrentCollectionMirror<ThreadPersistenceSnapshot> &&
                visible.window.origin == frozen.origin &&
                visible.window.reference == frozen.collection) {
              mirror.source.publish(
                mirror.source.value.copyWith(
                  threads: CollectionMirror.current(
                    window: visible.window.copyWith(loading: true, error: null),
                  ),
                ),
              );
            }
            await reads.useQueue(
              frozen,
              (scope) async {
                await readPersistenceQueueHeader(
                  scope,
                  frozen.header,
                  frozen.collection,
                );
                final refs = <ProductEntityRef>[];
                int? offset;
                int? nextOffset;
                if (dirty.isNotEmpty) {
                  refs.addAll(dirty);
                } else {
                  offset = switch (prior.continuation) {
                    OffsetCollectionContinuation(:final value) => value,
                    EndCollectionContinuation() => prior.reference.total,
                    _ => 0,
                  };
                  final page = await scope.entries(
                    offset: offset,
                    limit: limit,
                  );
                  refs.addAll(page.items);
                  final end = offset + refs.length;
                  if (page.collection != frozen.collection ||
                      page.offset != offset ||
                      refs.length > limit ||
                      end > frozen.collection.total ||
                      refs.any((ref) => ref.entry < 0 || ref.revision < 0) ||
                      refs.map((ref) => ref.entry).toSet().length !=
                          refs.length ||
                      page.nextOffset !=
                          (end == frozen.collection.total ? null : end) ||
                      end < frozen.collection.total && refs.isEmpty) {
                    throw resourceProtocol(
                      'Persistence queue index changed its original ordered window.',
                    );
                  }
                  nextOffset = page.nextOffset;
                }
                final loaded =
                    <
                      int,
                      ReadValue<ThreadPersistenceSnapshot, ProductEntityRef>
                    >{};
                StudioFailure? failure;
                StackTrace? failureStack;
                for (final ref in refs) {
                  if (read.invalid) throw persistenceSuperseded;
                  try {
                    final entity = await scope.entity(ref);
                    if (entity.reference != ref)
                      throw resourceProtocol(
                        'Persistence entity changed its frozen reference.',
                      );
                    final value = await readThreadPersistence(
                      scope,
                      entity.value,
                    );
                    final previous = persistencePrevious(prior.rows[ref.entry]);
                    if (previous?.origin == frozen.origin &&
                        previous?.reference.entry == ref.entry &&
                        previous!.value.threadId != value.threadId)
                      throw resourceProtocol(
                        'Persistence entry changed Thread identity.',
                      );
                    loaded[ref.entry] = ReadValue.ready(
                      current: Materialized(
                        origin: frozen.origin,
                        reference: ref,
                        value: value,
                      ),
                    );
                  } catch (error, stack) {
                    lifetime.lastCause = error;
                    lifetime.lastStack = stack;
                    final issue = resourceFailure(error);
                    failure ??= issue;
                    failureStack ??= stack;
                    loaded[ref.entry] = ReadValue.failed(
                      origin: frozen.origin,
                      reference: ref,
                      error: issue,
                      previous: persistencePrevious(prior.rows[ref.entry]),
                    );
                  }
                }
                if (lifetime.sealed && failure != null)
                  Error.throwWithStackTrace(failure, failureStack!);
                _commit(
                  frozen,
                  read,
                  prior,
                  refs,
                  loaded,
                  offset,
                  nextOffset,
                  task,
                );
                if (failure != null)
                  Error.throwWithStackTrace(failure, failureStack!);
              },
              onPin: (pin) {
                read.cancel = pin.requestClose;
                if (read.invalid) {
                  pin.requestClose();
                  throw persistenceSuperseded;
                }
              },
            );
          } finally {
            mirror.reads.remove(read);
          }
        }),
      ).then<void>(
        (_) {
          remove();
          _active.remove(task);
          _refresh();
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          remove();
          _active.remove(task);
          if (index != null) mirror.reads.remove(index);
          final failure = index?.invalid == true && !lifetime.sealed
              ? persistenceSuperseded
              : resourceFailure(error);
          final binding = original;
          final current = mirror.current;
          if (!lifetime.sealed &&
              binding != null &&
              current != null &&
              binding.generation == current.generation &&
              binding.origin == current.origin &&
              binding.header.reference == current.header.reference &&
              binding.collection == current.collection &&
              task == _sequence) {
            final visible = mirror.source.value.threads;
            if (visible is CurrentCollectionMirror<ThreadPersistenceSnapshot>)
              mirror.source.publish(
                mirror.source.value.copyWith(
                  threads: CollectionMirror.current(
                    window: visible.window.copyWith(
                      loading: _loading(current),
                      error: failure,
                    ),
                  ),
                ),
              );
          }
          _refresh();
          done.completeError(failure, stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  void _commit(
    PersistenceQueueBinding binding,
    PersistenceIndexRead read,
    CollectionWindow<ThreadPersistenceSnapshot> frozen,
    List<ProductEntityRef> refs,
    Map<int, ReadValue<ThreadPersistenceSnapshot, ProductEntityRef>> loaded,
    int? offset,
    int? nextOffset,
    int task,
  ) {
    mirror.check(binding);
    final current = mirror.current!;
    if (!read.covers(current.origin, current.collection, current.generation))
      throw persistenceSuperseded;
    final prefix = frozen.entries;
    final latest = _window(current);
    if (offset != null && prefix.length != offset) throw persistenceSuperseded;
    final candidate = offset == null ? prefix : [...prefix, ...refs];
    if (candidate.map((ref) => ref.entry).toSet().length != candidate.length) {
      throw resourceProtocol(
        'Persistence queue index repeated an entry across pages.',
      );
    }
    final overlap = candidate.length < latest.entries.length
        ? candidate.length
        : latest.entries.length;
    for (var index = 0; index < overlap; index++) {
      if (candidate[index] != latest.entries[index])
        throw persistenceSuperseded;
    }
    final expands = offset != null && candidate.length >= latest.entries.length;
    final entries = expands ? candidate : latest.entries;
    final rows =
        Map<int, ReadValue<ThreadPersistenceSnapshot, ProductEntityRef>>.of(
          latest.rows,
        );
    for (final ref in refs) {
      if (!_ready(rows[ref.entry], current.origin, ref))
        rows[ref.entry] = loaded[ref.entry]!;
    }
    StudioFailure? error;
    for (final ref in entries) {
      final value = rows[ref.entry];
      if (value is FailedReadValue<ThreadPersistenceSnapshot, ProductEntityRef>)
        error ??= value.error;
    }
    mirror.source.publish(
      mirror.source.value.copyWith(
        threads: CollectionMirror.current(
          window: CollectionWindow(
            origin: current.origin,
            reference: current.collection,
            entries: entries,
            rows: rows,
            continuation: expands
                ? nextOffset == null
                      ? const CollectionContinuation.end()
                      : CollectionContinuation.offset(value: nextOffset)
                : latest.continuation,
            complete: expands ? nextOffset == null : latest.complete,
            loading: _loading(current, except: task),
            error: error,
          ),
        ),
      ),
    );
  }
}
