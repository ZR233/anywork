import 'dart:async';

import 'package:anywork_client/resources_ports.dart';

import '../domain/update_values.dart';
import '../domain/updates_state.dart';
import 'updates_materialization.dart';
import 'updates_mirror.dart';
import 'updates_read_pins.dart';
import 'updates_state_helpers.dart';

enum _Field { value, summary, details }

typedef _Job = ({
  int generation,
  ProductReadOrigin? origin,
  UpdatesReadRef? value,
  UpdateSummaryReadRef? summary,
  UpdateDetailsReadRef? details,
  _Field field,
});

final class UpdatesReads {
  UpdatesReads(this.mirror, this.pins, this.lifetime);
  final UpdatesMirror mirror;
  final UpdatesReadPins pins;
  final ResourceLifetime lifetime;
  final Map<_Job, Future<UpdatesValue>> _values = {};
  final Map<_Job, Future<UpdateSummary>> _summaries = {};
  final Map<_Job, Future<UpdateDetails>> _details = {};
  final Map<UpdatesReadTarget, Future<UpdatesValue>> _targets = {};

  _Job _key(UpdatesDemand demand, _Field field) {
    final binding = demand.binding;
    return (
      generation: demand.generation,
      origin: binding?.origin,
      value: field == _Field.value ? binding?.header.reference : null,
      summary: field == _Field.summary ? binding?.header.summary : null,
      details: field == _Field.details ? binding?.header.details : null,
      field: field,
    );
  }

  Future<void> value() {
    final demand = mirror.capture();
    UpdatesBinding? original;
    return _job<UpdatesValue>(_values, demand, _Field.value, (binding) async {
      original = binding;
      final old = mirror.source.value.value;
      if (old is ReadyReadValue<UpdatesValue, UpdatesReadRef> &&
          old.current.origin == binding.origin &&
          old.current.reference == binding.header.reference) {
        return old.current.value;
      }
      if (mirror.current?.header.reference == binding.header.reference) {
        mirror.source.publish(
          mirror.source.value.copyWith(
            value: ReadValue.loading(
              origin: binding.origin,
              reference: binding.header.reference,
              previous: updatesPrevious(old),
            ),
          ),
        );
      }
      final result = await at(binding.target, expected: binding.header);
      mirror.offerValue(binding, result);
      return result;
    }).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final binding = original;
        final current = mirror.current;
        final old = mirror.source.value.value;
        final ready =
            old is ReadyReadValue<UpdatesValue, UpdatesReadRef> &&
            old.current.origin == binding?.origin &&
            old.current.reference == binding?.header.reference;
        if (!lifetime.sealed &&
            binding != null &&
            current != null &&
            binding.generation == current.generation &&
            binding.origin == current.origin &&
            binding.header.reference == current.header.reference &&
            !ready) {
          mirror.source.publish(
            mirror.source.value.copyWith(
              value: ReadValue.failed(
                origin: binding.origin,
                reference: binding.header.reference,
                error: resourceFailure(error),
                previous: updatesPrevious(old),
              ),
            ),
          );
        }
        Error.throwWithStackTrace(resourceFailure(error), stack);
      },
    );
  }

  Future<UpdateSummary> summary() {
    final demand = mirror.capture();
    return _job(_summaries, demand, _Field.summary, (binding) async {
      final ref = binding.header.summary;
      if (ref == null) throw updatesNoSummary;
      final prior = mirror.summary(binding);
      if (prior != null) return prior;
      final value = await pins.summary(
        binding.origin,
        ref,
        (scope) async => readUpdateSummary(
          await scope.header(),
          (field, offset) => scope.text(field, offset: offset, maxBytes: 65536),
        ),
      );
      mirror.offerSummary(binding, value);
      return value;
    });
  }

  Future<UpdateDetails> details() {
    final demand = mirror.capture();
    return _job(_details, demand, _Field.details, (binding) async {
      final ref = binding.header.details;
      if (ref == null) throw updatesNoDetails;
      final value = await pins.details(
        binding.origin,
        ref,
        (scope) async => readUpdateDetails(
          await scope.header(),
          (field, offset) => scope.text(field, offset: offset, maxBytes: 65536),
        ),
      );
      mirror.offerSummary(binding, value.summary);
      return value;
    });
  }

  /// A native finish target is an original immutable scope, not a request to
  /// read whichever version the feed happens to expose after an await.
  Future<UpdatesValue> at(UpdatesReadTarget target, {UpdatesHeader? expected}) {
    lifetime.admit();
    if (_targets[target] case final pending?)
      return pending.then((value) {
        if (expected != null) _checkValue(value, expected);
        return value;
      });
    final done = Completer<UpdatesValue>();
    _targets[target] = done.future;
    unawaited(
      Future<UpdatesValue>.sync(
        () => lifetime.run(
          'updates-original-value',
          () => pins.root(
            target,
            (scope) => readUpdatesValue(scope, expected: expected),
          ),
        ),
      ).then<void>(
        (value) {
          if (identical(_targets[target], done.future))
            unawaited(_targets.remove(target));
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          if (identical(_targets[target], done.future))
            unawaited(_targets.remove(target));
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }

  void _checkValue(UpdatesValue value, UpdatesHeader expected) {
    if (updatesFromBrief(
          expected.brief,
          summary: updatesSummary(value),
          operationId: value is CheckingUpdatesValue ? value.operationId : null,
          error: updatesError(value),
        ) !=
        value) {
      throw resourceProtocol(
        'An Updates scope disagrees with its frozen header.',
      );
    }
  }

  Future<T> _job<T>(
    Map<_Job, Future<T>> jobs,
    UpdatesDemand demand,
    _Field field,
    Future<T> Function(UpdatesBinding) read,
  ) {
    final key = _key(demand, field);
    if (jobs[key] case final pending?) return pending;
    final done = Completer<T>();
    jobs[key] = done.future;
    final keys = <_Job>{key};
    void remove() {
      for (final key in keys) {
        if (identical(jobs[key], done.future)) unawaited(jobs.remove(key));
      }
    }

    unawaited(
      Future<T>.sync(
        () => lifetime.run('updates-read:${field.name}', () async {
          Future<T>? joined;
          final binding = await mirror.ready(
            demand,
            bind: (current) {
              final canonical = _key((
                generation: current.generation,
                binding: current,
              ), field);
              final pending = jobs[canonical];
              if (pending != null && !identical(pending, done.future)) {
                joined = pending;
                return;
              }
              keys.add(canonical);
              jobs[canonical] = done.future;
            },
          );
          if (joined case final pending?) return await pending;
          mirror.check(binding);
          return await read(binding);
        }),
      ).then<void>(
        (value) {
          remove();
          done.complete(value);
        },
        onError: (Object error, StackTrace stack) {
          remove();
          done.completeError(resourceFailure(error), stack);
        },
      ),
    );
    unawaited(
      done.future.then<void>((_) {}, onError: (Object _, StackTrace __) {}),
    );
    return done.future;
  }
}
