import 'package:anywork_client/resources.dart';
import 'package:anywork_client/resources_ports.dart';

const updatesUnavailable = StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'The Updates source has no current canonical value.',
  retryable: true,
  correlationId: 'updates',
);
const updatesSuperseded = StudioFailure(
  code: StudioFailureCode.superseded,
  message: 'The original Updates read is no longer current.',
  retryable: true,
  correlationId: 'updates',
);
const updatesNoSummary = StudioFailure(
  code: StudioFailureCode.notFound,
  message: 'The original Updates value has no summary.',
  retryable: false,
  correlationId: 'updates',
);
const updatesNoDetails = StudioFailure(
  code: StudioFailureCode.notFound,
  message: 'The original Updates value has no installer details.',
  retryable: false,
  correlationId: 'updates',
);

Materialized<T, R>? updatesPrevious<T, R>(ReadValue<T, R>? value) =>
    switch (value) {
      ReadyReadValue<T, R>(:final current) => current,
      LoadingReadValue<T, R>(:final previous) ||
      FailedReadValue<T, R>(:final previous) => previous,
      _ => null,
    };

ReadValue<T, R>? updatesStale<T, R>(
  ReadValue<T, R>? value,
  StudioFailure error,
) => switch (value) {
  ReadyReadValue<T, R>(:final current) => ReadValue.failed(
    origin: current.origin,
    reference: current.reference,
    error: error,
    previous: current,
  ),
  UnloadedReadValue<T, R>(:final origin, :final reference) => ReadValue.failed(
    origin: origin,
    reference: reference,
    error: error,
    previous: null,
  ),
  LoadingReadValue<T, R>(:final origin, :final reference, :final previous) ||
  FailedReadValue<T, R>(
    :final origin,
    :final reference,
    :final previous,
  ) => ReadValue.failed(
    origin: origin,
    reference: reference,
    error: error,
    previous: previous,
  ),
  null => null,
};

ReadValue<T, R> updatesRebind<T, R>(
  ReadValue<T, R>? old,
  ProductReadOrigin origin,
  R ref,
) {
  final same = switch (old) {
    ReadyReadValue<T, R>(:final current) =>
      current.origin == origin && current.reference == ref,
    UnloadedReadValue<T, R>(origin: final prior, reference: final reference) ||
    LoadingReadValue<T, R>(origin: final prior, reference: final reference) ||
    FailedReadValue<T, R>(
      origin: final prior,
      reference: final reference,
    ) => prior == origin && reference == ref,
    null => false,
  };
  if (same) return old!;
  final previous = updatesPrevious(old);
  return previous == null
      ? ReadValue.unloaded(origin: origin, reference: ref)
      : ReadValue.failed(
          origin: origin,
          reference: ref,
          error: updatesSuperseded,
          previous: previous,
        );
}
