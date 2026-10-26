import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/mcp_state.dart';
import 'mcp_collection.dart';
import 'mcp_mirror.dart';
import 'mcp_port.dart';
import 'mcp_reader.dart';

enum _Field { active, desired, applied, source }

typedef _Job = ({
  int generation,
  ProductReadOrigin? origin,
  McpReadRef? value,
  ProductSourceStatusRef? status,
  _Field field,
});

/// MCP's named scalar demands share the same original-version business pin.
final class McpReads {
  McpReads(this.port, this.mirror, this.lifetime);
  final McpPort port;
  final McpMirror mirror;
  final ResourceLifetime lifetime;
  final Map<McpReadTarget, PinnedReadOwner<McpReadConnection>> _values = {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _sources = {};
  final Map<_Job, Future<void>> _jobs = {};

  void adopted(McpBinding binding) {
    for (final entry in List.of(_values.entries)) {
      if (entry.key.origin != binding.origin ||
          entry.key.reference != binding.header.reference) {
        entry.value.retire();
        if (identical(_values[entry.key], entry.value))
          _values.remove(entry.key);
      }
    }
    for (final entry in List.of(_sources.entries)) {
      if (entry.key.origin != binding.origin ||
          entry.key.reference != binding.header.source.status) {
        entry.value.retire();
        if (identical(_sources[entry.key], entry.value))
          _sources.remove(entry.key);
      }
    }
  }

  Future<T> use<T>(
    McpBinding binding,
    Future<T> Function(McpReadConnection) action, {
    void Function(PinnedReadOwner<McpReadConnection>)? onPin,
  }) async {
    mirror.check(binding);
    final target = binding.target;
    final prior = _values[target];
    final pin = prior != null && prior.accepting
        ? prior
        : PinnedReadOwner<McpReadConnection>(
            lifetime: lifetime,
            owner: 'mcp-value-pin',
            open: () =>
                port.openMcpRead(target.reference, origin: target.origin),
            request: (value) => value.requestClose(),
            closeNative: (value) => value.close(),
            retryNative: (value) => value.retryClose(),
          );
    _values[target] = pin;
    try {
      onPin?.call(pin);
      return await pin.use(action);
    } finally {
      final current = mirror.current;
      if (!pin.accepting ||
          current == null ||
          current.generation != binding.generation ||
          current.origin != target.origin ||
          current.header.reference != target.reference) {
        pin.retire();
        if (identical(_values[target], pin)) _values.remove(target);
      }
    }
  }

  Future<void> active() => _field<List<String>>(
    _Field.active,
    (state) => state.activeServerIds,
    (state, value) => state.copyWith(activeServerIds: value),
    (scope) async =>
        McpReader(scope)
            .activeIds((await scope.header()).health.activeMcpServers),
  );
  Future<void> desired() => _field<String>(
    _Field.desired,
    (state) => state.desiredConfigFingerprint,
    (state, value) => state.copyWith(desiredConfigFingerprint: value),
    (scope) async => materializeReadText(
      (await scope.header()).desiredConfigFingerprint,
      read: (field, offset) =>
          scope.text(field, offset: offset, maxBytes: 65536),
    ),
  );
  Future<void> applied() => _field<String>(
    _Field.applied,
    (state) => state.appliedConfigFingerprint,
    (state, value) => state.copyWith(appliedConfigFingerprint: value),
    (scope) async => materializeReadText(
      (await scope.header()).appliedConfigFingerprint,
      read: (field, offset) =>
          scope.text(field, offset: offset, maxBytes: 65536),
    ),
  );

  bool _ready<T, R>(ReadValue<T, R>? value, ProductReadOrigin origin, R ref) =>
      value is ReadyReadValue<T, R> &&
      value.current.origin == origin &&
      value.current.reference == ref;

  Future<void> _job(
    _Job key,
    Future<void> Function(Future<void>? Function(_Job)) action,
    void Function(StudioFailure) failed,
  ) {
    if (_jobs[key] case final pending?) return pending;
    final done = Completer<void>();
    _jobs[key] = done.future;
    final keys = <_Job>{key};
    Future<void>? bind(_Job current) {
      final pending = _jobs[current];
      if (pending != null && !identical(pending, done.future)) return pending;
      keys.add(current);
      _jobs[current] = done.future;
      return null;
    }

    void remove() {
      for (final key in keys) {
        if (identical(_jobs[key], done.future)) unawaited(_jobs.remove(key));
      }
    }

    unawaited(
      Future<void>.sync(
        () => lifetime.run('mcp-read:${key.field.name}', () => action(bind)),
      ).then<void>(
        (_) {
          remove();
          done.complete();
        },
        onError: (Object error, StackTrace stack) {
          remove();
          final failure = resourceFailure(error);
          try {
            failed(failure);
            done.completeError(failure, stack);
          } catch (ownerError, ownerStack) {
            lifetime.lastCause = ownerError;
            lifetime.lastStack = ownerStack;
            done.completeError(resourceFailure(ownerError), ownerStack);
          }
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  Future<void> _field<T>(
    _Field field,
    ReadValue<T, McpReadRef>? Function(McpState) get,
    McpState Function(McpState, ReadValue<T, McpReadRef>) set,
    Future<T> Function(McpReadConnection) read,
  ) {
    final demand = mirror.capture();
    final frozen = demand.binding;
    final key = (
      generation: demand.generation,
      origin: frozen?.origin,
      value: frozen?.header.reference,
      status: null,
      field: field,
    );
    McpBinding? original;
    return _job(
      key,
      (bind) async {
        final binding = await mirror.ready(demand);
        final target = binding.target;
        final joined = bind((
          generation: binding.generation,
          origin: target.origin,
          value: target.reference,
          status: null,
          field: field,
        ));
        if (joined != null) {
          await joined;
          return;
        }
        original = binding;
        mirror.check(binding);
        if (mirror.current!.header.reference != target.reference)
          throw mcpSuperseded;
        final old = get(mirror.source.value);
        if (_ready(old, target.origin, target.reference)) return;
        mirror.source.publish(
          set(
            mirror.source.value,
            ReadValue.loading(
              origin: target.origin,
              reference: target.reference,
              previous: mcpPrevious(old),
            ),
          ),
        );
        final value = await use(binding, read);
        mirror.check(binding);
        if (mirror.current!.header.reference != target.reference)
          throw mcpSuperseded;
        mirror.source.publish(
          set(
            mirror.source.value,
            ReadValue.ready(
              current: Materialized(
                origin: target.origin,
                reference: target.reference,
                value: value,
              ),
            ),
          ),
        );
      },
      (failure) {
        final binding = original;
        final current = mirror.current;
        if (lifetime.sealed ||
            binding == null ||
            current == null ||
            current.generation != binding.generation ||
            current.origin != binding.origin ||
            current.header.reference != binding.header.reference)
          return;
        final old = get(mirror.source.value);
        if (_ready(old, binding.origin, binding.target.reference)) return;
        mirror.source.publish(
          set(
            mirror.source.value,
            ReadValue.failed(
              origin: binding.origin,
              reference: binding.target.reference,
              error: failure,
              previous: mcpPrevious(old),
            ),
          ),
        );
      },
    );
  }

  Future<void> sourceStatus() {
    final demand = mirror.capture();
    final frozen = demand.binding;
    final key = (
      generation: demand.generation,
      origin: frozen?.origin,
      value: null,
      status: frozen?.header.source.status,
      field: _Field.source,
    );
    McpBinding? original;
    return _job(
      key,
      (bind) async {
        final binding = await mirror.ready(demand);
        final expected = binding.header.source.brief;
        final target = (
          origin: binding.origin,
          reference: binding.header.source.status,
        );
        final joined = bind((
          generation: binding.generation,
          origin: target.origin,
          value: null,
          status: target.reference,
          field: _Field.source,
        ));
        if (joined != null) {
          await joined;
          return;
        }
        original = binding;
        mirror.check(binding);
        if (mirror.current!.header.source.status != target.reference)
          throw mcpSuperseded;
        final old = mirror.source.value.sourceStatus;
        if (_ready(old, target.origin, target.reference)) return;
        mirror.source.publish(
          mirror.source.value.copyWith(
            sourceStatus: ReadValue.loading(
              origin: target.origin,
              reference: target.reference,
              previous: mcpPrevious(old),
            ),
          ),
        );
        final prior = _sources[target];
        final pin = prior != null && prior.accepting
            ? prior
            : PinnedReadOwner<ProductSourceStatusReadConnection>(
                lifetime: lifetime,
                owner: 'mcp-source-pin',
                open: () => port.openSourceStatus(
                  target.reference,
                  origin: target.origin,
                ),
                request: (value) => value.requestClose(),
                closeNative: (value) => value.close(),
                retryNative: (value) => value.retryClose(),
              );
        _sources[target] = pin;
        try {
          final value = await pin.use(
            (scope) =>
                materializeProductSourceStatus(scope, expected: expected),
          );
          mirror.check(binding);
          if (mirror.current!.header.source.status != target.reference)
            throw mcpSuperseded;
          mirror.source.publish(
            mirror.source.value.copyWith(
              sourceStatus: ReadValue.ready(
                current: Materialized(
                  origin: target.origin,
                  reference: target.reference,
                  value: value,
                ),
              ),
            ),
          );
        } finally {
          final current = mirror.current;
          if (!pin.accepting ||
              current == null ||
              current.generation != binding.generation ||
              current.origin != target.origin ||
              current.header.source.status != target.reference) {
            pin.retire();
            if (identical(_sources[target], pin)) _sources.remove(target);
          }
        }
      },
      (failure) {
        final binding = original;
        final current = mirror.current;
        if (lifetime.sealed ||
            binding == null ||
            current == null ||
            current.generation != binding.generation ||
            current.origin != binding.origin ||
            current.header.source.status != binding.header.source.status)
          return;
        final old = mirror.source.value.sourceStatus;
        if (_ready(old, binding.origin, binding.header.source.status)) return;
        mirror.source.publish(
          mirror.source.value.copyWith(
            sourceStatus: ReadValue.failed(
              origin: binding.origin,
              reference: binding.header.source.status,
              error: failure,
              previous: mcpPrevious(old),
            ),
          ),
        );
      },
    );
  }
}
