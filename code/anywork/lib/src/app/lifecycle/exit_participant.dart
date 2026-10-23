import 'package:anywork_client/resources.dart';

/// A close capability captured by the composition root from an actual owner.
/// Not a Repository facade and not a second resource registry: original owners
/// retain handles, accepted operations, cleanup attempts and permits.
final class ApplicationCloseParticipant {
  const ApplicationCloseParticipant({
    required this.name,
    required this.seal,
    required this.close,
    required this.retryCleanup,
  });

  final String name;
  final void Function() seal;
  final Future<CloseReport> Function({DateTime? deadline}) close;
  final Future<CloseReport> Function({DateTime? deadline}) retryCleanup;
}

/// Auto-save producers hand off already-formed valid intents synchronously,
/// before repositories/operations are sealed. Manual forms are not auto-saved.
abstract interface class ApplicationEditProducer {
  void sealAndHandoff();
}

/// Instance-scoped registration of existing auto-save producers, not an
/// operation registry. The sealed snapshot owns the exit responsibility even
/// when a route unregisters while handoff is in progress.
final class ApplicationEditProducerRegistry {
  final Map<ApplicationEditProducer, _ApplicationEditRegistration> _entries =
      Map.identity();
  List<ApplicationEditProducer>? _snapshot;

  ApplicationEditRegistration register(ApplicationEditProducer producer) {
    if (_snapshot != null) throw const StudioFailure(
      code: StudioFailureCode.cancelled,
      message: 'Application edit registration is sealed.',
      retryable: false,
      correlationId: '',
    );
    return _entries.putIfAbsent(
      producer, () => _ApplicationEditRegistration(this, producer),
    );
  }

  List<ApplicationEditProducer> sealAndSnapshot() =>
      _snapshot ??= List<ApplicationEditProducer>.unmodifiable(_entries.keys);

  void _unregister(_ApplicationEditRegistration registration) {
    if (identical(_entries[registration.producer], registration)) {
      _entries.remove(registration.producer);
    }
  }
}

abstract interface class ApplicationEditRegistration {
  void unregister();
}

final class _ApplicationEditRegistration implements ApplicationEditRegistration {
  _ApplicationEditRegistration(this.registry, this.producer);

  final ApplicationEditProducerRegistry registry;
  final ApplicationEditProducer producer;
  bool _unregistered = false;

  @override
  void unregister() {
    if (_unregistered) return;
    _unregistered = true;
    registry._unregister(this);
  }
}
