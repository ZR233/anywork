part of 'studio_demo_api.dart';

// Public ports delegate lifecycle work to the actual owned scope entry. Never
// register these proxies as the resource in the entry they delegate to.
abstract base class _DemoPortProxy<R extends ClientResource>
    implements ClientResource {
  _DemoPortProxy(this.entry);

  final ClientAcquisition<R> entry;

  @override
  ClientResourceId get resourceId => entry.resourceId;

  @override
  void requestClose() => entry.requestClose();

  @override
  Future<void> close() => entry.close();

  @override
  Future<void> retryClose() => entry.retryClose();

  /// A closed entry ends the observation with `null` instead of an error.
  Future<T?> nextFrame<T>(Future<T?> Function(R resource) next) async {
    try {
      return await next(await entry.ready);
    } on ClientResourceClosed {
      return null;
    }
  }
}

final class _DemoAccountPort extends _DemoPortProxy<DemoAccountObservation>
    implements AccountDomainObservation {
  _DemoAccountPort(super.entry);

  @override
  Future<AccountDomainFrame?> next() =>
      nextFrame((resource) => resource.next());
}

final class _DemoThreadsPort extends _DemoPortProxy<_DemoThreadsObservation>
    implements ThreadsObservationHandle {
  _DemoThreadsPort(super.entry);

  @override
  Future<ThreadDirectoryFrame?> next() =>
      nextFrame((resource) => resource.next());
}

final class _DemoThreadPort extends _DemoPortProxy<_DemoThreadObservation>
    implements ThreadObservationHandle {
  _DemoThreadPort(super.entry);

  @override
  Future<ThreadMetadataFrame?> next() =>
      nextFrame((resource) => resource.next());
}

final class _DemoProductTopicPort
    extends _DemoPortProxy<_DemoProductTopicResource>
    implements ProductTopicObservation {
  _DemoProductTopicPort(super.entry);

  @override
  late final Stream<ProductTopicFrame> frames = _frames();

  Stream<ProductTopicFrame> _frames() async* {
    final resource = await entry.ready;
    yield* resource.frames;
  }
}

final class _DemoProductTopicResource implements ClientResource {
  _DemoProductTopicResource(this.transport, this.topic, this.resourceId) {
    _controller = StreamController<ProductTopicFrame>(onListen: _listen);
  }

  final DemoStudioTransport transport;
  final ProductTopic topic;
  @override
  final ClientResourceId resourceId;
  late final StreamController<ProductTopicFrame> _controller;
  final List<ProductTopicEventPayload> _pending = [];
  Future<void>? _producer;
  Future<void>? _streamClosed;
  bool _closed = false;
  bool _listened = false;
  bool _baselineEmitted = false;

  Stream<ProductTopicFrame> get frames => _controller.stream;

  void _listen() {
    _listened = true;
    if (_closed) {
      _streamClosed = _controller.close();
      return;
    }
    // Register the sink before reading the canonical baseline so no payload
    // published in between is lost. The scope owns this raw resource before
    // any producer can start.
    (transport._topicSinks[topic] ??=
            <void Function(ProductTopicEventPayload)>{})
        .add(_receive);
    if (transport.lspActivityLoop && topic == const LspTopic()) {
      transport._startLspActivityLoop();
    }
    _producer = _publishBaseline();
  }

  Future<void> _publishBaseline() async {
    try {
      final baseline = await transport._demoTopicBaseline(topic);
      if (_closed) return;
      _baselineEmitted = true;
      _controller.add(baseline);
      for (final payload in _pending) {
        transport._emitProductFrame(_controller, topic, payload);
      }
      _pending.clear();
    } catch (error, stack) {
      if (!_closed) _controller.addError(error, stack);
    }
  }

  void _receive(ProductTopicEventPayload payload) {
    if (_closed) return;
    if (!_baselineEmitted) {
      _pending.add(payload);
      return;
    }
    transport._emitProductFrame(_controller, topic, payload);
  }

  @override
  void requestClose() {
    if (_closed) return;
    _closed = true;
    final sinks = transport._topicSinks[topic];
    sinks?.remove(_receive);
    if (sinks != null && sinks.isEmpty) transport._topicSinks.remove(topic);
    _pending.clear();
    // An unlistened single-subscription controller cannot finish its done
    // Future. There is no producer/subscription to join in that case; a late
    // listener is closed synchronously by _listen instead of starting work.
    if (_listened) _streamClosed = _controller.close();
  }

  @override
  Future<void> close() async {
    requestClose();
    await _producer;
    await _streamClosed;
  }

  @override
  Future<void> retryClose() => close();
}
