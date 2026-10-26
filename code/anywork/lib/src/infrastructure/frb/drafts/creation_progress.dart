part of 'new_thread_creation_port.dart';

/// Only latest native preparation information. No business result or terminal
/// progress event is synthesized, including when the progress stream ends.
final class _CreationProgress {
  final _latest = LatestValue<ThreadPreparationProgress?>(null);
  final _setup = Completer<void>();
  StreamSubscription<preparation.BridgeThreadPreparationProgress>?
  _subscription;
  StudioFailure? _failure;
  bool _sealed = false;

  ReadonlyLatestValue<ThreadPreparationProgress?> get readonly {
    if (_failure case final failure?) throw failure;
    return _latest.readonly;
  }

  void start(
    AdapterResourceOwner owner,
    Future<native.BridgeThreadCreation?> opening,
    wire.BridgeThreadCreationIdentity Function(native.BridgeThreadCreation)
    checkIdentity,
  ) {
    final finish = owner.registerOpening();
    unawaited(
      Future<void>.sync(() async {
        try {
          final handle = await opening;
          if (handle == null || owner.isClosing) return;
          checkIdentity(handle);
          owner.ensureOpen();
          _subscription = handle.progress().listen(
            (value) {
              if (_sealed || owner.isClosing || _failure != null) return;
              try {
                final identity = checkIdentity(handle);
                final progress = preparationProgressFromBridge(value);
                if (progress.projectId != identity.projectId ||
                    progress.inputId != identity.inputId) {
                  throw adapterProtocol('thread-creation-progress-target');
                }
                _latest.publish(progress);
              } on Object catch (error, stack) {
                _failure = owner.failure(error, stack, source: 'progress');
                _latest.close();
              }
            },
            onError: (Object error, StackTrace stack) {
              _failure = owner.failure(error, stack, source: 'progress');
              _latest.close();
            },
            onDone: () {
              // EOF only ends this observer; result() joins the actual native job.
            },
          );
        } on Object catch (error, stack) {
          _failure = owner.failure(error, stack, source: 'progress-open');
          _latest.close();
        } finally {
          _setup.complete();
          finish();
        }
      }),
    );
  }

  void seal() {
    _sealed = true;
    _latest.close();
  }

  Future<void> cancel() async {
    seal();
    await _setup.future;
    await _subscription?.cancel();
  }
}
