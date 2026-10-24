part of 'attachment_drafts.dart';

/// One input operation bound to the draft that existed before platform I/O.
/// Callers await preparation and may only use this scope until it returns.
final class AttachmentDraftInput {
  AttachmentDraftInput._(
    this._owner, {
    required String targetKey,
    required AttachmentAdmissionContext context,
    required ComposerDraftBinding binding,
    required String? projectId,
    required String? threadId,
    required bool Function() targetCurrent,
    required int generation,
  }) : _targetKey = targetKey,
       _context = context,
       _binding = binding,
       _projectId = projectId,
       _threadId = threadId,
       _targetCurrent = targetCurrent,
       _generation = generation;

  final AttachmentDraftsOwner _owner;
  final String _targetKey;
  final AttachmentAdmissionContext _context;
  final ComposerDraftBinding _binding;
  final String? _projectId;
  final String? _threadId;
  final bool Function() _targetCurrent;
  final int _generation;
  final Completer<void> _invalidated = Completer<void>();
  final List<Observation> _validityWatches = [];
  bool _active = true;

  /// Signals retirement even when a platform read is suspended. Readers must
  /// cancel and join their actual subscriptions, not just stop awaiting data.
  Future<void> get whenInvalidated => _invalidated.future;

  bool get isCurrent =>
      _active &&
      !_owner._closed &&
      !_owner._admissionsSealed &&
      _binding.mounted() &&
      _binding.generation() == _generation &&
      _targetCurrent();

  void _watchTarget() {
    void validate() {
      if (!isCurrent) _invalidate();
    }

    final client = _owner._client;
    if (_threadId case final threadId?) {
      _validityWatches.add(
        client.threadDirectory.source.watch((_) => validate()),
      );
      final session = client.existingSession(threadId);
      if (session != null) {
        _validityWatches.add(session.source.watch((_) => validate()));
      }
    } else {
      _validityWatches.add(client.project.source.watch((_) => validate()));
    }
  }

  void _invalidate() {
    _active = false;
    if (!_invalidated.isCompleted) _invalidated.complete();
  }

  void _finish() {
    _invalidate();
    for (final watch in _validityWatches) {
      watch.cancel();
    }
    _validityWatches.clear();
  }

  Future<void> admit(List<AttachmentDraftSource> sources) {
    if (!isCurrent) return Future<void>.value();
    final frozen = List<AttachmentDraftSource>.unmodifiable(sources);
    return _owner._track(
      () => _owner._admit(
        targetKey: _targetKey,
        context: _context,
        sources: frozen,
        binding: _binding,
        projectId: _projectId,
        threadId: _threadId,
        targetCurrent: () => isCurrent,
      ),
    );
  }

  Future<void> addLocalFiles(List<String> paths) =>
      admit([for (final path in paths) AttachmentDraftSource.localFile(path)]);

  Future<void> addClipboardImage(Uint8List pngBytes) {
    if (!isCurrent) return Future<void>.value();
    if (pngBytes.isEmpty) {
      return _reportFailure(StateError('Clipboard image is empty.'));
    }
    if (pngBytes.length > AttachmentInputLimits.maxFileBytes) {
      return _reportFailure(
        StateError('Clipboard image exceeds the attachment file-size limit.'),
      );
    }
    final stage = _owner.clipboardImageStager;
    final cleanup = _owner.clipboardImageCleanup;
    if (stage == null || cleanup == null) {
      return _reportFailure(
        StateError('Clipboard image staging is unavailable.'),
      );
    }
    final bytes = Uint8List.fromList(pngBytes);
    return withLocalStaging(
      create: () => stage(bytes),
      cleanup: cleanup,
      use: (path) => addLocalFiles([path]),
    );
  }

  /// A nonempty higher-priority representation is final, even if its admission
  /// fails. File-list paths are borrowed originals, never cleanup candidates.
  Future<void> paste(
    ComposerClipboardReader clipboard, {
    required void Function(String text) onText,
  }) async {
    if (!isCurrent) return;
    final files = await clipboard.readFiles();
    if (!isCurrent) return;
    if (files.isNotEmpty) {
      await addLocalFiles(files);
      return;
    }
    final image = await clipboard.readImage();
    if (!isCurrent) return;
    if (image != null && image.isNotEmpty) {
      await addClipboardImage(image);
      return;
    }
    final text = await clipboard.readText();
    if (isCurrent && text != null && text.isNotEmpty) onText(text);
  }

  /// Only for a directory/file created by this operation, never user files.
  /// Creation is reserved before dispatch; cleanup failures remain owned and
  /// retryable after the platform callback or the view has returned.
  Future<void> withLocalStaging({
    required Future<String?> Function() create,
    required Future<void> Function(String path) cleanup,
    required Future<void> Function(String path) use,
  }) {
    if (!isCurrent) return Future<void>.value();
    return _owner._track(
      () => _owner._withStaging(
        create: create,
        cleanup: cleanup,
        use: (path) async {
          if (isCurrent) await use(path);
        },
        reportFailure: _reportFailure,
      ),
    );
  }

  Future<void> _reportFailure(Object error) =>
      _owner._lane(_targetKey).enqueue(() async {
        if (!isCurrent) return;
        _binding.write(_binding.read().reportAttachmentFailure(error));
      });
}
