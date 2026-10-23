import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/recovery_state.dart';
import '../domain/recovery_values.dart';
import 'recovery_index.dart';
import 'recovery_mirror.dart';
import 'recovery_port.dart';
import 'recovery_reader.dart';

typedef _PageKey = ({int generation, ProductReadOrigin? origin,
  RecoveryReadRef? reference, ProductCollectionRef? collection,
  CollectionContinuation? continuation, int limit});

final class RecoveryPages {
  RecoveryPages(this.port, this.mirror, this.lifetime);
  final RecoveryPort port;
  final RecoveryMirror mirror;
  final ResourceLifetime lifetime;
  final Map<RecoveryReadTarget, PinnedReadOwner<RecoveryReadConnection>> _scopes = {};
  final Map<_PageKey, Future<void>> _jobs = {};
  final Map<int, ({int generation, RecoveryIndexRead? read})> _active = {};
  int _pageSequence = 0;

  bool _loadingFor(RecoveryBinding binding, {int? except}) => _active.entries.any((entry) {
    if (entry.key == except || entry.value.generation != binding.generation) return false;
    final read = entry.value.read;
    return read == null || !read.invalid && read.origin == binding.origin &&
        read.collection == binding.collection;
  });

  void _refreshLoading() {
    if (lifetime.sealed) return;
    final binding = mirror.current;
    final value = mirror.source.value.issues;
    if (binding == null || value is! CurrentCollectionMirror<RecoveryIssue> ||
        value.window.origin != binding.origin || value.window.reference != binding.collection) return;
    final loading = _loadingFor(binding);
    if (value.window.loading != loading) {
      mirror.source.publish(mirror.source.value.copyWith(issues: CollectionMirror.current(
        window: value.window.copyWith(loading: loading))));
    }
  }

  void adopted(RecoveryBinding binding) {
    final target = binding.header.reference == null ? null : binding.target;
    for (final entry in List.of(_scopes.entries)) {
      if (entry.key != target) {
        entry.value.retire();
        if (identical(_scopes[entry.key], entry.value)) _scopes.remove(entry.key);
      }
    }
    for (final read in List.of(mirror.reads)) {
      if (read.invalid) read.cancel?.call();
    }
  }

  PinnedReadOwner<RecoveryReadConnection> _scope(RecoveryReadTarget target) {
    final old = _scopes[target];
    if (old != null && old.accepting) return old;
    final owner = PinnedReadOwner<RecoveryReadConnection>(
      lifetime: lifetime, owner: 'recovery-value-pin',
      open: () => port.openRecoveryRead(target.reference, origin: target.origin),
      request: (scope) => scope.requestClose(), closeNative: (scope) => scope.close(),
      retryNative: (scope) => scope.retryClose(),
    );
    _scopes[target] = owner;
    return owner;
  }

  CollectionWindow<RecoveryIssue> _window(RecoveryBinding binding) {
    final collection = binding.collection;
    if (collection == null) throw recoveryUnavailable;
    final value = mirror.source.value.issues;
    if (value is CurrentCollectionMirror<RecoveryIssue> &&
        value.window.origin == binding.origin && value.window.reference == collection) {
      return value.window;
    }
    return recoveryEmptyWindow(binding.origin, collection);
  }

  bool _readyRow(ReadValue<RecoveryIssue, ProductEntityRef>? row,
      ProductReadOrigin origin, ProductEntityRef reference) =>
    row is ReadyReadValue<RecoveryIssue, ProductEntityRef> &&
    row.current.origin == origin && row.current.reference == reference;

  Future<void> load({int limit = 32}) {
    lifetime.admit();
    if (limit < 1 || limit > 100) throw const StudioFailure(
      code: StudioFailureCode.invalidArgument,
      message: 'A recovery page limit must be between 1 and 100.',
      retryable: false, correlationId: 'recovery',
    );
    final demand = mirror.capture();
    final binding = demand.binding;
    final window = binding?.collection == null ? null : _window(binding!);
    if (window != null && window.complete && window.entries.every(
        (ref) => _readyRow(window.rows[ref.entry], window.origin, ref))) return Future.value();
    final key = (generation: demand.generation, origin: binding?.origin,
      reference: binding?.header.reference, collection: binding?.collection,
      continuation: window?.continuation, limit: limit);
    if (_jobs[key] case final pending?) return pending;
    final done = Completer<void>();
    _jobs[key] = done.future;
    final keys = <_PageKey>{key};
    void removeAliases() {
      for (final key in keys) {
        if (identical(_jobs[key], done.future)) _jobs.remove(key);
      }
    }
    final task = ++_pageSequence;
    _active[task] = (generation: demand.generation, read: null);
    RecoveryBinding? original;
    RecoveryIndexRead? index;
    CollectionWindow<RecoveryIssue>? snapshot;
    Future<void>? joined;
    Future<void>.sync(() => lifetime.run('recovery-issues-page', () async {
      lifetime.admit();
      final frozen = await mirror.ready(demand, bind: (binding) {
        final collection = binding.collection;
        if (collection == null || binding.header.reference == null) throw recoveryUnavailable;
        final boundWindow = window ?? _window(binding);
        final canonical = (generation: binding.generation, origin: binding.origin,
          reference: binding.header.reference, collection: collection,
          continuation: boundWindow.continuation, limit: limit);
        final pending = _jobs[canonical];
        if (pending != null && !identical(pending, done.future)) {
          joined = pending;
          return;
        }
        _jobs[canonical] = done.future;
        keys.add(canonical);
        original = binding;
        snapshot = boundWindow;
        index = RecoveryIndexRead(binding.origin, collection, binding.generation);
        _active[task] = (generation: binding.generation, read: index);
        mirror.reads.add(index!);
      });
      if (joined case final pending?) {
        _active.remove(task);
        await pending;
        return;
      }
      final read = index!;
      PinnedReadOwner<RecoveryReadConnection>? pin;
      try {
        mirror.check(frozen);
        if (read.invalid) throw recoverySuperseded;
        final prior = snapshot!;
        final dirty = prior.entries.where(
          (ref) => !_readyRow(prior.rows[ref.entry], prior.origin, ref)).take(limit).toList();
        if (prior.complete && dirty.isEmpty) return;
        final value = mirror.source.value.issues;
        if (value is CurrentCollectionMirror<RecoveryIssue> &&
            value.window.origin == frozen.origin && value.window.reference == frozen.collection) {
          mirror.source.publish(mirror.source.value.copyWith(
            issues: CollectionMirror.current(window: value.window.copyWith(loading: true, error: null))));
        }
        final scope = _scope(frozen.target);
        pin = scope;
        read.cancel = scope.requestClose;
        if (read.invalid) {
          scope.requestClose();
          throw recoverySuperseded;
        }
        await scope.use((connection) async {
          final root = await connection.header();
          if (root.issues.total != frozen.collection!.total || root.issues.listId < 0) {
            throw resourceProtocol('Recovery read header belongs to another collection.');
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
            final page = await connection.entries(offset: offset, limit: limit);
            refs.addAll(List.of(page.items));
            final end = offset + refs.length;
            if (page.collection != frozen.collection || page.offset != offset ||
                refs.length > limit || end > frozen.collection!.total ||
                refs.map((ref) => ref.entry).toSet().length != refs.length ||
                page.nextOffset != (end == frozen.collection!.total ? null : end) ||
                (end < frozen.collection!.total && refs.isEmpty)) {
              throw resourceProtocol('Recovery index page does not match its frozen window.');
            }
            nextOffset = page.nextOffset;
          }
          final rows = <int, ReadValue<RecoveryIssue, ProductEntityRef>>{};
          StudioFailure? failure;
          StackTrace? failureStack;
          for (final reference in refs) {
            if (read.invalid) throw recoverySuperseded;
            try {
              final entity = await connection.entity(reference);
              if (entity.reference != reference) {
                throw resourceProtocol('Recovery entity reply changed its frozen reference.');
              }
              final value = await RecoveryReader(connection).issue(entity.value);
              final previous = recoveryPrevious(prior.rows[reference.entry]);
              if (previous?.origin == frozen.origin && previous?.reference.entry == reference.entry &&
                  previous!.value.id != value.id) {
                throw resourceProtocol('Recovery reused an entity entry for another issue.');
              }
              rows[reference.entry] = ReadValue.ready(current: Materialized(
                origin: frozen.origin, reference: reference, value: value));
            } catch (error, stack) {
              lifetime.lastCause = error;
              lifetime.lastStack = stack;
              final issue = resourceFailure(error);
              failure ??= issue;
              failureStack ??= stack;
              rows[reference.entry] = ReadValue.failed(origin: frozen.origin,
                reference: reference, error: issue, previous: recoveryPrevious(prior.rows[reference.entry]));
            }
          }
          if (lifetime.sealed && failure != null) {
            Error.throwWithStackTrace(failure, failureStack!);
          }
          _commit(frozen, read, prior, refs, rows, offset, nextOffset, task);
          if (failure != null) Error.throwWithStackTrace(failure, failureStack!);
        });
      } finally {
        mirror.reads.remove(read);
        // A reentrant open can advance the source before this scope is cached,
        // so that adoption cannot have retired it yet. The original use still
        // joins; only the stale cache entry/permit is retired here.
        final scope = pin;
        final current = mirror.current;
        if (scope != null && (!scope.accepting || current == null ||
            current.header.reference == null || current.target != frozen.target)) {
          scope.retire();
          if (identical(_scopes[frozen.target], scope)) _scopes.remove(frozen.target);
      }
      }
    })).then<void>((_) {
      removeAliases();
      _active.remove(task);
      _refreshLoading();
      done.complete();
    }, onError: (Object error, StackTrace stack) {
      removeAliases();
      _active.remove(task);
      final binding = original;
      final current = mirror.current;
      final failure = index?.invalid == true && !lifetime.sealed
          ? recoverySuperseded : resourceFailure(error);
      if (!lifetime.sealed && binding != null && current != null &&
          binding.generation == current.generation && binding.origin == current.origin &&
          binding.collection == current.collection &&
          binding.header.reference == current.header.reference && task == _pageSequence) {
        final value = mirror.source.value.issues;
        if (value is CurrentCollectionMirror<RecoveryIssue>) {
          mirror.source.publish(mirror.source.value.copyWith(issues: CollectionMirror.current(
            window: value.window.copyWith(loading: _loadingFor(current), error: failure))));
        }
      }
      if (index != null) mirror.reads.remove(index);
      _refreshLoading();
      done.completeError(failure, stack);
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }

  void _commit(RecoveryBinding binding, RecoveryIndexRead read,
      CollectionWindow<RecoveryIssue> frozen, List<ProductEntityRef> refs,
      Map<int, ReadValue<RecoveryIssue, ProductEntityRef>> loaded,
      int? offset, int? nextOffset, int task) {
    mirror.check(binding);
    final current = mirror.current!;
    final collection = current.collection;
    if (collection == null) throw recoverySuperseded;
    final originalPrefix = read.current(frozen.entries, current.origin, collection, mirror.generation);
    final members = read.current(refs, current.origin, collection, mirror.generation);
    final latest = _window(current);
    final candidate = offset == null ? originalPrefix : [
      ...originalPrefix.take(offset), ...members,
    ];
    if (offset != null && originalPrefix.length != offset) throw recoverySuperseded;
    if (candidate.map((ref) => ref.entry).toSet().length != candidate.length) {
      throw resourceProtocol('Recovery index repeated an entry across pages.');
    }
    final overlap = candidate.length < latest.entries.length ? candidate.length : latest.entries.length;
    for (var index = 0; index < overlap; index++) {
      if (candidate[index] != latest.entries[index]) throw recoverySuperseded;
    }
    final expands = offset != null && candidate.length >= latest.entries.length;
    final entries = expands ? candidate : latest.entries;
    final rows = Map<int, ReadValue<RecoveryIssue, ProductEntityRef>>.of(latest.rows);
    for (var index = 0; index < members.length; index++) {
      final reference = members[index];
      final original = refs[index];
      final prior = rows[reference.entry];
      if (_readyRow(prior, current.origin, reference)) continue;
      final incoming = loaded[original.entry]!;
      final body = recoveryPrevious(incoming);
      if (incoming is ReadyReadValue<RecoveryIssue, ProductEntityRef> &&
          incoming.current.origin == current.origin && incoming.current.reference == reference) {
        rows[reference.entry] = incoming;
      } else {
        var previous = recoveryPrevious(prior);
        if (body != null && (previous == null ||
            previous.origin != current.origin || body.origin == current.origin &&
                body.reference.entry == previous.reference.entry &&
                body.reference.revision > previous.reference.revision)) previous = body;
        final error = reference == original && incoming is FailedReadValue<RecoveryIssue, ProductEntityRef>
            ? incoming.error : recoverySuperseded;
        rows[reference.entry] = ReadValue.failed(origin: current.origin,
          reference: reference, error: error, previous: previous);
      }
    }
    final continuation = expands
        ? nextOffset == null ? const CollectionContinuation.end()
            : CollectionContinuation.offset(value: nextOffset)
        : latest.continuation;
    final complete = expands ? nextOffset == null : latest.complete;
    StudioFailure? error;
    for (final ref in entries) {
      final row = rows[ref.entry];
      if (row is FailedReadValue<RecoveryIssue, ProductEntityRef>) error ??= row.error;
    }
    mirror.source.publish(mirror.source.value.copyWith(issues: CollectionMirror.current(
      window: CollectionWindow(origin: current.origin, reference: collection,
        entries: entries, rows: rows, continuation: continuation,
        complete: complete, loading: _loadingFor(current, except: task), error: error))));
  }

  /// Command synchronization only observes this domain's original target. It
  /// neither publishes a reply snapshot nor loads every issue/worktree body.
  Future<void> synchronize(RecoveryReadTarget target) {
    final demand = mirror.capture();
    return Future<void>.sync(() => lifetime.run('recovery-command-observation', () async {
      final binding = await mirror.ready(demand);
      mirror.check(binding);
      await mirror.source.waitFor((_) {
        lifetime.admit();
        final current = mirror.current;
        if (current == null) {
          final sync = mirror.source.value.projection.sync;
          if (sync.phase == ResourceSyncPhase.failed) throw sync.error!;
          return false;
        }
        if (current.origin != target.origin) throw recoverySuperseded;
        final reference = current.header.reference;
        if (reference == null) throw recoveryUnavailable;
        if (reference.entry != target.reference.entry) throw recoverySuperseded;
        return reference.revision >= target.reference.revision;
      });
    }));
  }
}
