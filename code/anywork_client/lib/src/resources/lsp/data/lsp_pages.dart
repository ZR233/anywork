import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_state.dart';
import '../domain/lsp_values.dart';
import 'lsp_collection.dart';
import 'lsp_field_reads.dart';
import 'lsp_mirror.dart';
import 'lsp_reader.dart';

typedef _PageKey = ({
  int generation,
  ProductReadOrigin? origin,
  LspReadRef? reference,
  ProductCollectionRef? collection,
  CollectionContinuation? continuation,
  int limit,
});

final class LspPages {
  LspPages(this.mirror, this.reads, this.lifetime);
  final LspMirror mirror;
  final LspReads reads;
  final ResourceLifetime lifetime;
  final Map<_PageKey, Future<void>> _jobs = {};
  final Map<int, ({int generation, LspIndexRead? read})> _active = {};
  int _sequence = 0;

  CollectionWindow<LspServer> _window(LspBinding binding) {
    final ref = binding.collection;
    if (ref == null) throw lspUnavailable;
    final value = mirror.source.value.servers;
    return value is CurrentCollectionMirror<LspServer> &&
            value.window.origin == binding.origin &&
            value.window.reference == ref
        ? value.window
        : lspEmptyWindow(binding.origin, ref);
  }

  bool _ready(
    ReadValue<LspServer, ProductEntityRef>? value,
    ProductReadOrigin origin,
    ProductEntityRef ref,
  ) =>
      value is ReadyReadValue<LspServer, ProductEntityRef> &&
      value.current.origin == origin &&
      value.current.reference == ref;

  bool _loading(LspBinding binding, {int? except}) =>
      _active.entries.any((entry) {
        if (entry.key == except || entry.value.generation != binding.generation)
          return false;
        final read = entry.value.read;
        return read == null ||
            read.covers(binding.origin, binding.collection, binding.generation);
      });

  void adopted(LspBinding binding) {
    for (final read in List.of(mirror.reads)) {
      if (read.invalid) read.cancel?.call();
    }
  }

  void _refresh() {
    if (lifetime.sealed) return;
    final binding = mirror.current;
    final value = mirror.source.value.servers;
    if (binding == null ||
        value is! CurrentCollectionMirror<LspServer> ||
        value.window.origin != binding.origin ||
        value.window.reference != binding.collection)
      return;
    final loading = _loading(binding);
    if (value.window.loading != loading)
      mirror.source.publish(
        mirror.source.value.copyWith(
          servers: CollectionMirror.current(
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
        message: 'An LSP page limit must be between 1 and 100.',
        retryable: false,
        correlationId: 'lsp',
      );
    final demand = mirror.capture();
    final binding = demand.binding;
    final snapshot = binding?.collection == null ? null : _window(binding!);
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
    LspBinding? original;
    LspIndexRead? index;
    CollectionWindow<LspServer>? frozenWindow;
    Future<void>? joined;
    unawaited(
      Future<void>.sync(
        () => lifetime.run('lsp-servers-page', () async {
          final frozen = await mirror.ready(
            demand,
            bind: (binding) {
              if (binding.collection == null ||
                  binding.header.reference == null)
                throw lspUnavailable;
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
              index = LspIndexRead(
                binding.origin,
                binding.collection!,
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
            if (read.invalid) throw lspSuperseded;
            final prior = frozenWindow!;
            final dirty = prior.entries
                .where(
                  (ref) => !_ready(prior.rows[ref.entry], prior.origin, ref),
                )
                .take(limit)
                .toList();
            if (prior.complete && dirty.isEmpty) return;
            final visible = mirror.source.value.servers;
            if (visible is CurrentCollectionMirror<LspServer> &&
                visible.window.origin == frozen.origin &&
                visible.window.reference == frozen.collection) {
              mirror.source.publish(
                mirror.source.value.copyWith(
                  servers: CollectionMirror.current(
                    window: visible.window.copyWith(loading: true, error: null),
                  ),
                ),
              );
            }
            await reads.use(
              frozen,
              (scope) async {
                final header = await scope.header();
                if (header.lspServers.total != frozen.collection!.total ||
                    header.lspServers.listId < 0) {
                  throw resourceProtocol(
                    'LSP root header changed its frozen collection.',
                  );
                }
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
                      end > frozen.collection!.total ||
                      refs.map((ref) => ref.entry).toSet().length !=
                          refs.length ||
                      page.nextOffset !=
                          (end == frozen.collection!.total ? null : end) ||
                      end < frozen.collection!.total && refs.isEmpty) {
                    throw resourceProtocol(
                      'LSP index page changed its original ordered window.',
                    );
                  }
                  nextOffset = page.nextOffset;
                }
                final loaded = <int, ReadValue<LspServer, ProductEntityRef>>{};
                StudioFailure? failure;
                StackTrace? failureStack;
                for (final ref in refs) {
                  if (read.invalid) throw lspSuperseded;
                  try {
                    final entity = await scope.entity(ref);
                    if (entity.reference != ref)
                      throw resourceProtocol(
                        'LSP entity changed its frozen reference.',
                      );
                    final value = await LspReader(scope).server(entity.value);
                    final previous = lspPrevious(prior.rows[ref.entry]);
                    if (previous?.origin == frozen.origin &&
                        previous?.reference.entry == ref.entry &&
                        previous!.value.id != value.id)
                      throw resourceProtocol(
                        'LSP reused an entry for another server.',
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
                      previous: lspPrevious(prior.rows[ref.entry]),
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
                  throw lspSuperseded;
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
              ? lspSuperseded
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
            final visible = mirror.source.value.servers;
            if (visible is CurrentCollectionMirror<LspServer>)
              mirror.source.publish(
                mirror.source.value.copyWith(
                  servers: CollectionMirror.current(
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
    LspBinding binding,
    LspIndexRead read,
    CollectionWindow<LspServer> frozen,
    List<ProductEntityRef> refs,
    Map<int, ReadValue<LspServer, ProductEntityRef>> loaded,
    int? offset,
    int? nextOffset,
    int task,
  ) {
    mirror.check(binding);
    final current = mirror.current!;
    final collection = current.collection;
    if (collection == null) throw lspSuperseded;
    final prefix = read.current(
      frozen.entries,
      current.origin,
      collection,
      current.generation,
    );
    final members = read.current(
      refs,
      current.origin,
      collection,
      current.generation,
    );
    final latest = _window(current);
    if (offset != null && prefix.length != offset) throw lspSuperseded;
    final candidate = offset == null ? prefix : [...prefix, ...members];
    if (candidate.map((ref) => ref.entry).toSet().length != candidate.length) {
      throw resourceProtocol('LSP index repeated an entry across pages.');
    }
    final overlap = candidate.length < latest.entries.length
        ? candidate.length
        : latest.entries.length;
    for (var index = 0; index < overlap; index++) {
      if (candidate[index] != latest.entries[index]) throw lspSuperseded;
    }
    final expands = offset != null && candidate.length >= latest.entries.length;
    final entries = expands ? candidate : latest.entries;
    final rows = Map<int, ReadValue<LspServer, ProductEntityRef>>.of(
      latest.rows,
    );
    for (var index = 0; index < members.length; index++) {
      final ref = members[index];
      final original = refs[index];
      final prior = rows[ref.entry];
      if (_ready(prior, current.origin, ref)) continue;
      final incoming = loaded[original.entry]!;
      if (incoming is ReadyReadValue<LspServer, ProductEntityRef> &&
          incoming.current.origin == current.origin &&
          incoming.current.reference == ref) {
        rows[ref.entry] = incoming;
      } else {
        final body = lspPrevious(incoming);
        var previous = lspPrevious(prior);
        if (body != null &&
            (previous == null ||
                previous.origin != current.origin ||
                body.origin == current.origin &&
                    body.reference.revision > previous.reference.revision))
          previous = body;
        rows[ref.entry] = ReadValue.failed(
          origin: current.origin,
          reference: ref,
          error:
              ref == original &&
                  incoming is FailedReadValue<LspServer, ProductEntityRef>
              ? incoming.error
              : lspSuperseded,
          previous: previous,
        );
      }
    }
    StudioFailure? error;
    for (final ref in entries) {
      final value = rows[ref.entry];
      if (value is FailedReadValue<LspServer, ProductEntityRef>)
        error ??= value.error;
    }
    mirror.source.publish(
      mirror.source.value.copyWith(
        servers: CollectionMirror.current(
          window: CollectionWindow(
            origin: current.origin,
            reference: collection,
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
