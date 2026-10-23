import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

import '../domain/updates_state.dart';
import 'updates_mirror.dart';
import 'updates_port.dart';

typedef _Key<R> = ({ProductReadOrigin origin, R reference});

/// Typed caches of D0's real immutable scope owners, all in the same lifetime.
final class UpdatesReadPins {
  UpdatesReadPins(this.port, this.mirror, this.lifetime);
  final UpdatesPort port;
  final UpdatesMirror mirror;
  final ResourceLifetime lifetime;
  final Map<_Key<UpdatesReadRef>, PinnedReadOwner<UpdatesReadConnection>> _roots = {};
  final Map<_Key<UpdateSummaryReadRef>, PinnedReadOwner<UpdateSummaryReadConnection>> _summaries = {};
  final Map<_Key<UpdateDetailsReadRef>, PinnedReadOwner<UpdateDetailsReadConnection>> _details = {};

  void adopted(UpdatesBinding binding) {
    _retire(_roots, binding.origin, binding.header.reference);
    _retire(_summaries, binding.origin, binding.header.summary);
    _retire(_details, binding.origin, binding.header.details);
  }

  void _retire<R, C>(Map<_Key<R>, PinnedReadOwner<C>> values, ProductReadOrigin origin, R? reference) {
    for (final entry in List.of(values.entries)) {
      if (entry.key.origin != origin || entry.key.reference != reference) {
        entry.value.retire();
        if (identical(values[entry.key], entry.value)) values.remove(entry.key);
      }
    }
  }

  Future<T> root<T>(UpdatesReadTarget target, Future<T> Function(UpdatesReadConnection) read) => _use(
    _roots, target.origin, target.reference, 'updates-value-pin',
    () => port.openUpdatesRead(target.reference, origin: target.origin),
    (value) => value.requestClose(), (value) => value.close(), (value) => value.retryClose(),
    (binding) => binding.header.reference == target.reference, read);

  Future<T> summary<T>(ProductReadOrigin origin, UpdateSummaryReadRef reference,
      Future<T> Function(UpdateSummaryReadConnection) read) => _use(
    _summaries, origin, reference, 'updates-summary-pin', () => port.openSummary(reference, origin: origin),
    (value) => value.requestClose(), (value) => value.close(), (value) => value.retryClose(),
    (binding) => binding.header.summary == reference, read);

  Future<T> details<T>(ProductReadOrigin origin, UpdateDetailsReadRef reference,
      Future<T> Function(UpdateDetailsReadConnection) read) => _use(
    _details, origin, reference, 'updates-details-pin', () => port.openDetails(reference, origin: origin),
    (value) => value.requestClose(), (value) => value.close(), (value) => value.retryClose(),
    (binding) => binding.header.details == reference, read);

  Future<T> _use<R, C, T>(Map<_Key<R>, PinnedReadOwner<C>> values,
      ProductReadOrigin origin, R reference, String owner, Future<C> Function() open,
      void Function(C) request, Future<FeedCloseReport> Function(C) close,
      Future<FeedCloseReport> Function(C) retry, bool Function(UpdatesBinding) current,
      Future<T> Function(C) read) async {
    lifetime.admit();
    final key = (origin: origin, reference: reference);
    final prior = values[key];
    final pin = prior != null && prior.accepting ? prior : PinnedReadOwner<C>(
      lifetime: lifetime, owner: owner, open: open, request: request, closeNative: close, retryNative: retry);
    values[key] = pin;
    try {
      return await pin.use(read);
    } finally {
      final latest = mirror.current;
      if (!pin.accepting || latest == null || latest.origin != origin || !current(latest)) {
        pin.retire();
        if (identical(values[key], pin)) values.remove(key);
      }
    }
  }
}
