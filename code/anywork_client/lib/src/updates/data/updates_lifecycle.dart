import 'package:anywork_client/operations.dart';

/// Composition-only automatic work. VM build/observation has no such side effect.
abstract interface class UpdatesLifecycle {
  OperationTicket<Unit> startAutomaticOnce();
}
