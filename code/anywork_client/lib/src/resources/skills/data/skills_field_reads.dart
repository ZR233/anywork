import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/skills_state.dart';
import 'skills_collection.dart';
import 'skills_mirror.dart';
import 'skills_port.dart';
import 'skills_reader.dart';
import 'skills_reads.dart';

enum _Field { warnings, directory, fingerprint, source }

typedef _Job = ({
  int generation,
  ProductReadOrigin? origin,
  SkillsReadRef? value,
  ProductSourceStatusRef? status,
  _Field field,
});

final class SkillsReads {
  SkillsReads(this.port, this.mirror, this.lifetime);
  final SkillsPort port;
  final SkillsMirror mirror;
  final ResourceLifetime lifetime;
  final Map<SkillsReadTarget, PinnedReadOwner<SkillsReadConnection>> _values =
      {};
  final Map<
    ({ProductReadOrigin origin, ProductSourceStatusRef reference}),
    PinnedReadOwner<ProductSourceStatusReadConnection>
  >
  _sources = {};
  final Map<_Job, Future<void>> _jobs = {};

  void adopted(SkillsBinding binding) {
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
    SkillsBinding binding,
    Future<T> Function(SkillsReadConnection) action, {
    void Function(PinnedReadOwner<SkillsReadConnection>)? onPin,
  }) async {
    mirror.check(binding);
    final target = binding.target;
    final prior = _values[target];
    final pin = prior != null && prior.accepting
        ? prior
        : PinnedReadOwner<SkillsReadConnection>(
            lifetime: lifetime,
            owner: 'skills-value-pin:${mirror.projectId}',
            open: () =>
                port.openSkillsRead(target.reference, origin: target.origin),
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

  Future<SkillsReadHeader> header(
    SkillsReadConnection scope,
    SkillsBinding binding,
  ) {
    if (binding.header.reference == null || binding.collection == null)
      throw skillsUnavailable;
    return SkillsReader(scope).header(
      projectId: mirror.projectId,
      catalogRevision: binding.header.catalogRevision!,
      complete: binding.header.complete!,
      total: binding.collection!.total,
    );
  }

  Future<void> warnings() => _field<List<String>>(
    _Field.warnings,
    (state) => state.warnings,
    (state, value) => state.copyWith(warnings: value),
    (scope, header) => SkillsReader(scope).strings(header.catalog.warnings),
  );
  Future<void> directory() => _field<String>(
    _Field.directory,
    (state) => state.projectDirectory,
    (state, value) => state.copyWith(projectDirectory: value),
    (scope, header) => materializeReadText(
      header.catalog.projectDir,
      read: (field, offset) =>
          scope.text(field, offset: offset, maxBytes: 65536),
    ),
  );
  Future<void> fingerprint() => _field<String>(
    _Field.fingerprint,
    (state) => state.configFingerprint,
    (state, value) => state.copyWith(configFingerprint: value),
    (scope, header) => materializeReadText(
      header.configFingerprint,
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
        () => lifetime.run(
          'skills-read:${mirror.projectId}:${key.field.name}',
          () => action(bind),
        ),
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
    ReadValue<T, SkillsReadRef>? Function(SkillsState) get,
    SkillsState Function(SkillsState, ReadValue<T, SkillsReadRef>) set,
    Future<T> Function(SkillsReadConnection, SkillsReadHeader) read,
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
    SkillsBinding? original;
    return _job(
      key,
      (bind) async {
        Future<void>? joined;
        final binding = await mirror.ready(
          demand,
          bind: (current) {
            joined = bind((
              generation: current.generation,
              origin: current.origin,
              value: current.header.reference,
              status: null,
              field: field,
            ));
            if (joined == null) original = current;
          },
        );
        if (joined case final pending?) {
          await pending;
          return;
        }
        final target = binding.target;
        mirror.check(binding);
        if (mirror.current!.header.reference != target.reference)
          throw skillsSuperseded;
        final old = get(mirror.source.value);
        if (_ready(old, target.origin, target.reference)) return;
        mirror.source.publish(
          set(
            mirror.source.value,
            ReadValue.loading(
              origin: target.origin,
              reference: target.reference,
              previous: skillsPrevious(old),
            ),
          ),
        );
        final value = await use(
          binding,
          (scope) async => read(scope, await header(scope, binding)),
        );
        mirror.check(binding);
        if (mirror.current!.header.reference != target.reference)
          throw skillsSuperseded;
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
            binding.header.reference == null ||
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
              previous: skillsPrevious(old),
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
    SkillsBinding? original;
    return _job(
      key,
      (bind) async {
        Future<void>? joined;
        final binding = await mirror.ready(
          demand,
          bind: (current) {
            joined = bind((
              generation: current.generation,
              origin: current.origin,
              value: null,
              status: current.header.source.status,
              field: _Field.source,
            ));
            if (joined == null) original = current;
          },
        );
        if (joined case final pending?) {
          await pending;
          return;
        }
        final expected = binding.header.source.brief;
        final target = (
          origin: binding.origin,
          reference: binding.header.source.status,
        );
        mirror.check(binding);
        if (mirror.current!.header.source.status != target.reference)
          throw skillsSuperseded;
        final old = mirror.source.value.sourceStatus;
        if (_ready(old, target.origin, target.reference)) return;
        mirror.source.publish(
          mirror.source.value.copyWith(
            sourceStatus: ReadValue.loading(
              origin: target.origin,
              reference: target.reference,
              previous: skillsPrevious(old),
            ),
          ),
        );
        final prior = _sources[target];
        final pin = prior != null && prior.accepting
            ? prior
            : PinnedReadOwner<ProductSourceStatusReadConnection>(
                lifetime: lifetime,
                owner: 'skills-source-pin:${mirror.projectId}',
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
            throw skillsSuperseded;
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
              previous: skillsPrevious(old),
            ),
          ),
        );
      },
    );
  }
}
