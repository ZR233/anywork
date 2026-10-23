import 'dart:async';

import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/lsp_state.dart';
import 'lsp_collection.dart';
import 'lsp_mirror.dart';
import 'lsp_port.dart';
import 'lsp_reader.dart';

enum _Field { active, source }
typedef _Job = ({int generation, ProductReadOrigin? origin, LspReadRef? value,
  ProductSourceStatusRef? status, _Field field});

final class LspReads {
  LspReads(this.port, this.mirror, this.lifetime);
  final LspPort port;
  final LspMirror mirror;
  final ResourceLifetime lifetime;
  final Map<LspReadTarget, PinnedReadOwner<LspReadConnection>> _values = {};
  final Map<({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>> _sources = {};
  final Map<_Job, Future<void>> _jobs = {};

  void adopted(LspBinding binding) {
    for (final entry in List.of(_values.entries)) {
      if (entry.key.origin != binding.origin || entry.key.reference != binding.header.reference) {
        entry.value.retire();
        if (identical(_values[entry.key], entry.value)) _values.remove(entry.key);
      }
    }
    for (final entry in List.of(_sources.entries)) {
      if (entry.key.origin != binding.origin || entry.key.reference != binding.header.source.status) {
        entry.value.retire();
        if (identical(_sources[entry.key], entry.value)) _sources.remove(entry.key);
      }
    }
  }

  Future<T> use<T>(LspBinding binding, Future<T> Function(LspReadConnection) action,
      {void Function(PinnedReadOwner<LspReadConnection>)? onPin}) async {
    mirror.check(binding);
    final target = binding.target;
    final prior = _values[target];
    final pin = prior != null && prior.accepting ? prior : PinnedReadOwner<LspReadConnection>(
      lifetime: lifetime, owner: 'lsp-value-pin',
      open: () => port.openLspRead(target.reference, origin: target.origin),
      request: (value) => value.requestClose(), closeNative: (value) => value.close(),
      retryNative: (value) => value.retryClose());
    _values[target] = pin;
    try {
      onPin?.call(pin);
      return await pin.use(action);
    } finally {
      final current = mirror.current;
      if (!pin.accepting || current == null || current.generation != binding.generation ||
          current.origin != target.origin || current.header.reference != target.reference) {
        pin.retire();
        if (identical(_values[target], pin)) _values.remove(target);
      }
    }
  }

  bool _ready<T, R>(ReadValue<T, R>? value, ProductReadOrigin origin, R ref) =>
    value is ReadyReadValue<T, R> && value.current.origin == origin && value.current.reference == ref;

  Future<void> _job(_Job key, Future<void> Function(Future<void>? Function(_Job)) action,
      void Function(StudioFailure) failed) {
    if (_jobs[key] case final pending?) return pending;
    final done = Completer<void>();
    _jobs[key] = done.future;
    final keys = <_Job>{key};
    Future<void>? bind(_Job current) {
      final pending = _jobs[current];
      if (pending != null && !identical(pending, done.future)) return pending;
      _jobs[current] = done.future;
      keys.add(current);
      return null;
    }
    void remove() {
      for (final key in keys) { if (identical(_jobs[key], done.future)) _jobs.remove(key); }
    }
    Future<void>.sync(() => lifetime.run('lsp-read:${key.field.name}', () => action(bind))).then<void>((_) {
      remove();
      done.complete();
    }, onError: (Object error, StackTrace stack) {
      remove();
      final failure = resourceFailure(error);
      try { failed(failure); done.completeError(failure, stack); }
      catch (ownerError, ownerStack) {
        lifetime.lastCause = ownerError;
        lifetime.lastStack = ownerStack;
        done.completeError(resourceFailure(ownerError), ownerStack);
      }
    });
    done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return done.future;
  }

  Future<void> active() {
    final demand = mirror.capture();
    final frozen = demand.binding;
    final key = (generation: demand.generation, origin: frozen?.origin,
      value: frozen?.header.reference, status: null, field: _Field.active);
    LspBinding? original;
    return _job(key, (bind) async {
      LspBinding? binding;
      Future<void>? joined;
      await mirror.ready(demand, bind: (current) {
        final target = current.target;
        joined = bind((generation: current.generation, origin: target.origin,
          value: target.reference, status: null, field: _Field.active));
        if (joined == null) binding = current;
      });
      if (joined case final pending?) { await pending; return; }
      final current = binding!;
      original = current;
      final target = current.target;
      mirror.check(current);
      if (mirror.current!.header.reference != target.reference) throw lspSuperseded;
      final old = mirror.source.value.activeServerIds;
      if (_ready(old, target.origin, target.reference)) return;
      mirror.source.publish(mirror.source.value.copyWith(activeServerIds: ReadValue.loading(
        origin: target.origin, reference: target.reference, previous: lspPrevious(old))));
      final value = await use(current, (scope) async =>
        LspReader(scope).strings((await scope.header()).activeLspServers));
      mirror.check(current);
      if (mirror.current!.header.reference != target.reference) throw lspSuperseded;
      mirror.source.publish(mirror.source.value.copyWith(activeServerIds: ReadValue.ready(current:
        Materialized(origin: target.origin, reference: target.reference, value: value))));
    }, (failure) {
      final binding = original;
      final current = mirror.current;
      if (lifetime.sealed || binding == null || current == null || binding.generation != current.generation ||
          binding.origin != current.origin || binding.header.reference != current.header.reference) return;
      final old = mirror.source.value.activeServerIds;
      if (_ready(old, binding.origin, binding.target.reference)) return;
      mirror.source.publish(mirror.source.value.copyWith(activeServerIds: ReadValue.failed(
        origin: binding.origin, reference: binding.target.reference, error: failure, previous: lspPrevious(old))));
    });
  }

  Future<void> sourceStatus() {
    final demand = mirror.capture();
    final frozen = demand.binding;
    final key = (generation: demand.generation, origin: frozen?.origin,
      value: null, status: frozen?.header.source.status, field: _Field.source);
    LspBinding? original;
    return _job(key, (bind) async {
      LspBinding? binding;
      Future<void>? joined;
      await mirror.ready(demand, bind: (current) {
        joined = bind((generation: current.generation, origin: current.origin,
          value: null, status: current.header.source.status, field: _Field.source));
        if (joined == null) binding = current;
      });
      if (joined case final pending?) { await pending; return; }
      final current = binding!;
      original = current;
      final target = (origin: current.origin, reference: current.header.source.status);
      mirror.check(current);
      if (mirror.current!.header.source.status != target.reference) throw lspSuperseded;
      final old = mirror.source.value.sourceStatus;
      if (_ready(old, target.origin, target.reference)) return;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.loading(
        origin: target.origin, reference: target.reference, previous: lspPrevious(old))));
      final prior = _sources[target];
      final pin = prior != null && prior.accepting ? prior
          : PinnedReadOwner<ProductSourceStatusReadConnection>(lifetime: lifetime, owner: 'lsp-source-pin',
              open: () => port.openSourceStatus(target.reference, origin: target.origin),
              request: (value) => value.requestClose(), closeNative: (value) => value.close(),
              retryNative: (value) => value.retryClose());
      _sources[target] = pin;
      try {
        final value = await pin.use((scope) => materializeProductSourceStatus(scope,
          expected: current.header.source.brief));
        mirror.check(current);
        if (mirror.current!.header.source.status != target.reference) throw lspSuperseded;
        mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.ready(current:
          Materialized(origin: target.origin, reference: target.reference, value: value))));
      } finally {
        final latest = mirror.current;
        if (!pin.accepting || latest == null || latest.generation != current.generation ||
            latest.origin != target.origin || latest.header.source.status != target.reference) {
          pin.retire();
          if (identical(_sources[target], pin)) _sources.remove(target);
        }
      }
    }, (failure) {
      final binding = original;
      final current = mirror.current;
      if (lifetime.sealed || binding == null || current == null || binding.generation != current.generation ||
          binding.origin != current.origin || binding.header.source.status != current.header.source.status) return;
      final old = mirror.source.value.sourceStatus;
      if (_ready(old, binding.origin, binding.header.source.status)) return;
      mirror.source.publish(mirror.source.value.copyWith(sourceStatus: ReadValue.failed(
        origin: binding.origin, reference: binding.header.source.status, error: failure, previous: lspPrevious(old))));
    });
  }
}
