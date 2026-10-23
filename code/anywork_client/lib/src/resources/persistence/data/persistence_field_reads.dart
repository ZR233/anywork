import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/persistence_state.dart';
import '../domain/persistence_values.dart';
import 'persistence_collection.dart';
import 'persistence_mirror.dart';
import 'persistence_port.dart';
import 'persistence_queue_mirror.dart';
import 'persistence_reader.dart';

typedef _ValueKey = ({int generation, ProductReadOrigin? origin, PersistenceReadRef? reference});
typedef _QueueKey = ({int generation, ProductReadOrigin? origin, PersistenceQueueReadRef? reference});

/// Both demands use the same lifetime and original immutable scopes as pages.
final class PersistenceReads {
  PersistenceReads(this.port, this.valueMirror, this.queueMirror, this.lifetime);
  final PersistencePort port;
  final PersistenceMirror valueMirror;
  final PersistenceQueueMirror queueMirror;
  final ResourceLifetime lifetime;
  final Map<PersistenceReadTarget, PinnedReadOwner<PersistenceReadConnection>> _values = {};
  final Map<({ProductReadOrigin origin, PersistenceQueueReadRef reference}),
    PinnedReadOwner<PersistenceQueueReadConnection>> _queues = {};
  final Map<_ValueKey, Future<void>> _valueJobs = {};
  final Map<_QueueKey, Future<void>> _queueJobs = {};

  void adoptedValue(PersistenceBinding binding) {
    for (final entry in List.of(_values.entries)) {
      if (entry.key.origin != binding.origin || entry.key.reference != binding.header.reference) {
        entry.value.retire();
        if (identical(_values[entry.key], entry.value)) _values.remove(entry.key);
      }
    }
  }

  void adoptedQueue(PersistenceQueueBinding binding) {
    for (final entry in List.of(_queues.entries)) {
      if (entry.key.origin != binding.origin || entry.key.reference != binding.header.reference) {
        entry.value.retire();
        if (identical(_queues[entry.key], entry.value)) _queues.remove(entry.key);
      }
    }
  }

  Future<T> useQueue<T>(PersistenceQueueBinding binding,
      Future<T> Function(PersistenceQueueReadConnection) action,
      {void Function(PinnedReadOwner<PersistenceQueueReadConnection>)? onPin}) async {
    queueMirror.check(binding);
    final target = (origin: binding.origin, reference: binding.header.reference);
    final prior = _queues[target];
    final pin = prior != null && prior.accepting ? prior : PinnedReadOwner<PersistenceQueueReadConnection>(
      lifetime: lifetime, owner: 'persistence-queue-pin',
      open: () => port.openPersistenceQueueRead(target.reference, origin: target.origin),
      request: (value) => value.requestClose(), closeNative: (value) => value.close(),
      retryNative: (value) => value.retryClose());
    _queues[target] = pin;
    try {
      onPin?.call(pin);
      return await pin.use(action);
    } finally {
      final current = queueMirror.current;
      if (!pin.accepting || current == null || current.generation != binding.generation ||
          current.origin != target.origin || current.header.reference != target.reference) {
        pin.retire();
        if (identical(_queues[target], pin)) _queues.remove(target);
      }
    }
  }

  bool _ready<T, R>(ReadValue<T, R>? value, ProductReadOrigin origin, R ref) =>
    value is ReadyReadValue<T, R> && value.current.origin == origin && value.current.reference == ref;

  Future<void> value() {
    final demand = valueMirror.capture();
    final frozen = demand.binding;
    final key = (generation: demand.generation, origin: frozen?.origin, reference: frozen?.header.reference);
    PersistenceBinding? original;
    return _job(_valueJobs, key, 'persistence-value', (bind) async {
      Future<void>? joined;
      final binding = await valueMirror.ready(demand, bind: (current) {
        joined = bind((generation: current.generation, origin: current.origin, reference: current.header.reference));
        if (joined == null) original = current;
      });
      if (joined case final pending?) { await pending; return; }
      final target = binding.target;
      valueMirror.check(binding);
      if (valueMirror.current!.header.reference != target.reference) throw persistenceSuperseded;
      final old = valueMirror.source.value.value;
      if (_ready(old, target.origin, target.reference)) return;
      valueMirror.source.publish(valueMirror.source.value.copyWith(value: ReadValue.loading(
        origin: target.origin, reference: target.reference, previous: persistencePrevious(old))));
      final prior = _values[target];
      final pin = prior != null && prior.accepting ? prior : PinnedReadOwner<PersistenceReadConnection>(
        lifetime: lifetime, owner: 'persistence-value-pin',
        open: () => port.openPersistenceRead(target.reference, origin: target.origin),
        request: (value) => value.requestClose(), closeNative: (value) => value.close(),
        retryNative: (value) => value.retryClose());
      _values[target] = pin;
      try {
        final value = await pin.use((scope) => readPersistenceValue(scope, binding.header));
        valueMirror.check(binding);
        if (valueMirror.current!.header.reference != target.reference) throw persistenceSuperseded;
        valueMirror.source.publish(valueMirror.source.value.copyWith(value: ReadValue.ready(current:
          Materialized(origin: target.origin, reference: target.reference, value: value))));
      } finally {
        final current = valueMirror.current;
        if (!pin.accepting || current == null || current.generation != binding.generation ||
            current.origin != target.origin || current.header.reference != target.reference) {
          pin.retire();
          if (identical(_values[target], pin)) _values.remove(target);
        }
      }
    }, (failure) {
      final binding = original;
      final current = valueMirror.current;
      if (lifetime.sealed || binding == null || current == null || current.generation != binding.generation ||
          current.origin != binding.origin || current.header.reference != binding.header.reference) return;
      final old = valueMirror.source.value.value;
      if (_ready(old, binding.origin, binding.header.reference)) return;
      valueMirror.source.publish(valueMirror.source.value.copyWith(value: ReadValue.failed(
        origin: binding.origin, reference: binding.header.reference, error: failure, previous: persistencePrevious(old))));
    });
  }

  Future<void> lastError() {
    final demand = queueMirror.capture();
    final frozen = demand.binding;
    final key = (generation: demand.generation, origin: frozen?.origin, reference: frozen?.header.reference);
    PersistenceQueueBinding? original;
    return _job(_queueJobs, key, 'persistence-queue-error', (bind) async {
      Future<void>? joined;
      final binding = await queueMirror.ready(demand, bind: (current) {
        joined = bind((generation: current.generation, origin: current.origin, reference: current.header.reference));
        if (joined == null) original = current;
      });
      if (joined case final pending?) { await pending; return; }
      final reference = binding.header.reference;
      queueMirror.check(binding);
      if (queueMirror.current!.header.reference != reference) throw persistenceSuperseded;
      final old = queueMirror.source.value.lastError;
      if (_ready(old, binding.origin, reference)) return;
      queueMirror.source.publish(queueMirror.source.value.copyWith(lastError: ReadValue.loading(
        origin: binding.origin, reference: reference, previous: persistencePrevious(old))));
      final value = await useQueue<String?>(binding, (scope) async {
        final header = await readPersistenceQueueHeader(scope, binding.header, binding.collection);
        final text = header.queue.lastError;
        return text == null ? null : await materializeReadText(text,
          read: (field, offset) => scope.text(field, offset: offset, maxBytes: 65536));
      });
      queueMirror.check(binding);
      if (queueMirror.current!.header.reference != reference) throw persistenceSuperseded;
      queueMirror.source.publish(queueMirror.source.value.copyWith(lastError: ReadValue.ready(current:
        Materialized(origin: binding.origin, reference: reference, value: value))));
    }, (failure) {
      final binding = original;
      final current = queueMirror.current;
      if (lifetime.sealed || binding == null || current == null || current.generation != binding.generation ||
          current.origin != binding.origin || current.header.reference != binding.header.reference) return;
      final old = queueMirror.source.value.lastError;
      if (_ready(old, binding.origin, binding.header.reference)) return;
      queueMirror.source.publish(queueMirror.source.value.copyWith(lastError: ReadValue.failed(
        origin: binding.origin, reference: binding.header.reference, error: failure, previous: persistencePrevious(old))));
    });
  }

  Future<void> _job<K>(Map<K, Future<void>> jobs, K key, String label,
      Future<void> Function(Future<void>? Function(K)) action, void Function(StudioFailure) failed) {
    if (jobs[key] case final pending?) return pending;
    final done = Completer<void>();
    jobs[key] = done.future;
    final keys = <K>{key};
    Future<void>? bind(K current) {
      final pending = jobs[current];
      if (pending != null && !identical(pending, done.future)) return pending;
      keys.add(current);
      jobs[current] = done.future;
      return null;
    }
    void remove() {
      for (final key in keys) { if (identical(jobs[key], done.future)) jobs.remove(key); }
    }
    Future<void>.sync(() => lifetime.run(label, () => action(bind))).then<void>((_) {
      remove(); done.complete();
    }, onError: (Object error, StackTrace stack) {
      remove();
      final failure = resourceFailure(error);
      try { failed(failure); done.completeError(failure, stack); }
      catch (ownerError, ownerStack) {
        lifetime.lastCause = ownerError; lifetime.lastStack = ownerStack;
        done.completeError(resourceFailure(ownerError), ownerStack);
      }
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }
}
