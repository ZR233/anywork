import 'package:anywork_client/resources.dart';

/// Called by Smart connectors, never by VM or raw-secret diagnostics.
String settingsFailureText(StudioFailure failure) =>
    '${failure.message} [${failure.code.name}: ${failure.correlationId}]';
