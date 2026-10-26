import 'package:anywork_client/resources.dart';

/// A display selector, not current-version evidence or a canonical writer.
/// The containing ViewState retains the original Repository state/origins.
T? displayReadValue<T, R>(ReadValue<T, R>? value) => switch (value) {
  ReadyReadValue<T, R>(:final current) => current.value,
  LoadingReadValue<T, R>(:final previous) => previous?.value,
  FailedReadValue<T, R>(:final previous) => previous?.value,
  _ => null,
};

bool isCurrentRead<T, R>(
  ReadValue<T, R>? value,
  R? reference,
  ProductReadOrigin? origin,
) =>
    reference != null &&
    origin != null &&
    switch (value) {
      ReadyReadValue<T, R>(:final current) =>
        current.reference == reference && current.origin == origin,
      _ => false,
    };

(ProductReadOrigin, R)? failedReadIdentity<T, R extends Object>(
  ReadValue<T, R>? value,
) => switch (value) {
  FailedReadValue<T, R>(:final origin, :final reference) => (origin, reference),
  _ => null,
};

StudioFailure settingsUnavailable(String target) => StudioFailure(
  code: StudioFailureCode.unavailable,
  message: 'Canonical $target is not available',
  retryable: true,
  correlationId: 'settings-canonical-unavailable',
);
