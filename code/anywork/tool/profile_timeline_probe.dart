import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:anywork/src/capture/capture_protocol.dart';
import 'package:anywork/src/shared/studio_driver_key_values.dart';
import 'package:args/args.dart';
import 'package:flutter_driver/flutter_driver.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service_io;

const int _schemaVersion = 1;
const Duration _pollInterval = Duration(milliseconds: 100);

final ArgParser _parser = ArgParser()
  ..addFlag('help', abbr: 'h', negatable: false)
  ..addOption('vm-url')
  ..addOption('project-id')
  ..addOption('thread-id')
  ..addOption('mode')
  ..addOption('samples')
  ..addOption('output')
  ..addOption('other-thread-id')
  ..addOption('deadline-ms', defaultsTo: '30000');

class ProbeOptions {
  const ProbeOptions({
    required this.vmUrl,
    required this.projectId,
    required this.threadId,
    required this.mode,
    required this.samples,
    required this.outputPath,
    required this.deadline,
    this.otherThreadId,
  });

  final Uri vmUrl;
  final String projectId;
  final String threadId;
  final String mode;
  final int samples;
  final String outputPath;
  final Duration deadline;
  final String? otherThreadId;
}

ProbeOptions parseProbeOptions(List<String> arguments) {
  final ArgResults results;
  try {
    results = _parser.parse(arguments);
  } on FormatException catch (error) {
    throw FormatException('${error.message}\n${_parser.usage}');
  }
  if (results.flag('help')) {
    throw const FormatException('help requested');
  }

  String requiredOption(String name) {
    final value = results.option(name);
    if (value == null || value.isEmpty) {
      throw FormatException('Missing required option --$name');
    }
    return value;
  }

  final rawUri = requiredOption('vm-url');
  final uri = Uri.tryParse(rawUri);
  if (uri == null ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme != 'ws' && uri.scheme != 'wss')) {
    throw const FormatException('--vm-url must be a ws:// or wss:// URI');
  }

  final threadId = requiredOption('thread-id');
  final mode = requiredOption('mode');
  if (mode != 'cold' && mode != 'switch') {
    throw const FormatException('--mode must be cold or switch');
  }
  final samples = _parseBoundedInteger(
    requiredOption('samples'),
    name: 'samples',
    minimum: 1,
    maximum: 100,
  );
  if (mode == 'cold' && samples != 1) {
    throw const FormatException('cold mode requires --samples 1');
  }

  final otherThreadId = results.option('other-thread-id');
  if (mode == 'switch') {
    if (otherThreadId == null || otherThreadId.isEmpty) {
      throw const FormatException('switch mode requires --other-thread-id');
    }
    if (otherThreadId == threadId) {
      throw const FormatException(
        '--other-thread-id must differ from --thread-id',
      );
    }
  } else if (otherThreadId != null) {
    throw const FormatException(
      '--other-thread-id is only valid in switch mode',
    );
  }

  final deadlineMs = _parseBoundedInteger(
    requiredOption('deadline-ms'),
    name: 'deadline-ms',
    minimum: 1,
    maximum: 120000,
  );
  return ProbeOptions(
    vmUrl: uri,
    projectId: requiredOption('project-id'),
    threadId: threadId,
    mode: mode,
    samples: samples,
    outputPath: requiredOption('output'),
    deadline: Duration(milliseconds: deadlineMs),
    otherThreadId: otherThreadId,
  );
}

int _parseBoundedInteger(
  String raw, {
  required String name,
  required int minimum,
  required int maximum,
}) {
  final value = int.tryParse(raw);
  if (value == null || value < minimum || value > maximum) {
    throw FormatException(
      '--$name must be an integer from $minimum to $maximum',
    );
  }
  return value;
}

class TimelineSpan {
  const TimelineSpan({
    required this.selectionId,
    required this.generation,
    required this.itemId,
    required this.selectionStartedMicros,
    required this.layoutCompletedMicros,
    required this.elapsedMicros,
  });

  final int selectionId;
  final int generation;
  final String itemId;
  final int selectionStartedMicros;
  final int layoutCompletedMicros;
  final int elapsedMicros;

  Map<String, Object> toJson() => {
    'selectionId': selectionId,
    'generation': generation,
    'itemId': itemId,
    'selectionStartedMicros': selectionStartedMicros,
    'layoutCompletedMicros': layoutCompletedMicros,
    'elapsedMicros': elapsedMicros,
  };
}

class TimelineObservation {
  const TimelineObservation({
    required this.buildMode,
    required this.status,
    required this.threadId,
    required this.selectionId,
    required this.generation,
    required this.firstContentLayout,
  });

  final String buildMode;
  final String status;
  final String? threadId;
  final int? selectionId;
  final int? generation;
  final TimelineSpan? firstContentLayout;

  bool get isObserved => status == 'observed';

  factory TimelineObservation.parse(Object? response) {
    final outer = _stringKeyMap(response, 'timeline layout response');
    _requireExactKeys(outer, const {
      'schemaVersion',
      'buildMode',
      'status',
      'threadId',
      'selectionId',
      'generation',
      'firstContentLayout',
    }, 'timeline layout response');
    if (_requiredInteger(outer['schemaVersion'], 'schemaVersion') !=
        _schemaVersion) {
      throw const FormatException('Unsupported timeline layout schemaVersion');
    }
    final buildMode = _requiredString(outer['buildMode'], 'buildMode');
    if (buildMode != 'profile') {
      throw FormatException('Expected profile buildMode, got $buildMode');
    }
    final status = _requiredString(outer['status'], 'status');
    if (status != 'unavailable' &&
        status != 'pending' &&
        status != 'observed') {
      throw FormatException('Unknown timeline layout status: $status');
    }
    final threadId = _nullableString(outer['threadId'], 'threadId');
    final selectionId = _nullableInteger(outer['selectionId'], 'selectionId');
    final generation = _nullableInteger(outer['generation'], 'generation');
    final rawLayout = outer['firstContentLayout'];

    if (status != 'observed') {
      if (rawLayout != null) {
        throw FormatException('$status response must not include a layout');
      }
      if (status == 'unavailable' &&
          (threadId != null || selectionId != null || generation != null)) {
        throw const FormatException(
          'unavailable response must not include selection identity',
        );
      }
      if (status == 'pending' &&
          (threadId == null || selectionId == null || generation == null)) {
        throw const FormatException(
          'pending response must include selection identity',
        );
      }
      return TimelineObservation(
        buildMode: buildMode,
        status: status,
        threadId: threadId,
        selectionId: selectionId,
        generation: generation,
        firstContentLayout: null,
      );
    }

    if (threadId == null || selectionId == null || generation == null) {
      throw const FormatException(
        'observed response requires complete selection identity',
      );
    }
    final layout = _stringKeyMap(rawLayout, 'firstContentLayout');
    _requireExactKeys(layout, const {
      'selectionId',
      'generation',
      'itemId',
      'selectionStartedMicros',
      'layoutCompletedMicros',
      'elapsedMicros',
    }, 'firstContentLayout');
    final span = TimelineSpan(
      selectionId: _requiredInteger(
        layout['selectionId'],
        'layout.selectionId',
      ),
      generation: _requiredInteger(layout['generation'], 'layout.generation'),
      itemId: _requiredString(layout['itemId'], 'layout.itemId'),
      selectionStartedMicros: _requiredInteger(
        layout['selectionStartedMicros'],
        'layout.selectionStartedMicros',
      ),
      layoutCompletedMicros: _requiredInteger(
        layout['layoutCompletedMicros'],
        'layout.layoutCompletedMicros',
      ),
      elapsedMicros: _requiredInteger(
        layout['elapsedMicros'],
        'layout.elapsedMicros',
      ),
    );
    if (span.itemId.isEmpty ||
        span.selectionStartedMicros < 0 ||
        span.layoutCompletedMicros < 0 ||
        span.selectionStartedMicros > span.layoutCompletedMicros ||
        span.elapsedMicros !=
            span.layoutCompletedMicros - span.selectionStartedMicros) {
      throw const FormatException('Invalid firstContentLayout timing span');
    }
    if (span.selectionId != selectionId || span.generation != generation) {
      throw const FormatException(
        'firstContentLayout identity does not match its selection',
      );
    }
    return TimelineObservation(
      buildMode: buildMode,
      status: status,
      threadId: threadId,
      selectionId: selectionId,
      generation: generation,
      firstContentLayout: span,
    );
  }
}

Map<String, Object?> _stringKeyMap(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw FormatException('$label keys must be strings');
    }
    result[entry.key as String] = entry.value;
  }
  return result;
}

void _requireExactKeys(
  Map<String, Object?> map,
  Set<String> expected,
  String label,
) {
  if (map.keys.length != expected.length ||
      !map.keys.toSet().containsAll(expected)) {
    throw FormatException('$label has missing or unexpected fields');
  }
}

String _requiredString(Object? value, String field) {
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string');
  }
  return value;
}

String? _nullableString(Object? value, String field) {
  if (value == null) return null;
  if (value is! String || value.isEmpty) {
    throw FormatException('$field must be a non-empty string or null');
  }
  return value;
}

int _requiredInteger(Object? value, String field) {
  if (value is! int) throw FormatException('$field must be an integer');
  return value;
}

int? _nullableInteger(Object? value, String field) {
  if (value == null) return null;
  return _requiredInteger(value, field);
}

TimelineSpan requireFreshObservation(
  TimelineObservation observation, {
  required String threadId,
  required int afterSelectionId,
  required int afterGeneration,
}) {
  if (!observation.isObserved ||
      observation.threadId != threadId ||
      observation.selectionId == null ||
      observation.generation == null ||
      observation.firstContentLayout == null) {
    throw FormatException('Expected an observed layout for thread $threadId');
  }
  final span = observation.firstContentLayout!;
  if (span.selectionId <= afterSelectionId ||
      span.generation <= afterGeneration) {
    throw FormatException('Observed layout for $threadId is stale');
  }
  return span;
}

bool isFreshObservation(
  TimelineObservation observation, {
  required String threadId,
  required int afterSelectionId,
  required int afterGeneration,
}) =>
    observation.isObserved &&
    observation.threadId == threadId &&
    observation.selectionId != null &&
    observation.generation != null &&
    observation.selectionId! > afterSelectionId &&
    observation.generation! > afterGeneration &&
    observation.firstContentLayout != null;

class _DriverConnectionScope {
  vm_service.VmService? _service;
  Future<vm_service.VmService>? _serviceFuture;
  Future<void>? _closeFuture;
  bool _abandoned = false;
  bool _connectionSettled = false;

  bool get hasService => _service != null;
  bool get hasUnsettledConnection =>
      _serviceFuture != null && !_connectionSettled;

  Future<vm_service.VmService> connectOnce(
    String url,
    Map<String, dynamic>? headers,
  ) {
    if (headers != null) {
      throw UnsupportedError('VM Service headers are not used by this probe');
    }
    final future = vm_service_io.vmServiceConnectUri(url);
    _serviceFuture = future;
    return future.then(
      (service) {
        _connectionSettled = true;
        _service = service;
        if (_abandoned) _closeLate(service);
        return service;
      },
      onError: (Object error, StackTrace stackTrace) {
        _connectionSettled = true;
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  void transferToDriver() {
    _abandoned = false;
  }

  Future<void> closeAfterFailedConnect() async {
    _abandoned = true;
    final service = _service;
    if (service != null) {
      await _closeService(service);
    } else if (_serviceFuture != null) {
      // A timed-out WebSocket handshake cannot be cancelled through the
      // public connector API. Own its completion and close any late service.
      unawaited(
        _serviceFuture!.then<void>(
          _closeLate,
          onError: (Object error, StackTrace stackTrace) {
            _connectionSettled = true;
            stderr.writeln(
              'Late VM Service connection failed (${error.runtimeType})',
            );
          },
        ),
      );
    }
  }

  Future<void> closeServiceAfterDriverFailure() async {
    final service = _service;
    if (service != null) await _closeService(service);
  }

  void consumeLateDriver(Future<FlutterDriver> connection) {
    unawaited(
      connection.then<void>(
        (lateDriver) async {
          try {
            await lateDriver.close();
          } catch (error) {
            stderr.writeln(
              'Late FlutterDriver cleanup failed (${error.runtimeType})',
            );
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          stderr.writeln(
            'Late FlutterDriver connection failed (${error.runtimeType})',
          );
        },
      ),
    );
  }

  Future<void> _closeLate(vm_service.VmService service) async {
    try {
      await _closeService(service);
    } catch (error) {
      stderr.writeln('Late VM Service cleanup failed (${error.runtimeType})');
    }
  }

  Future<void> _closeService(vm_service.VmService service) =>
      _closeFuture ??= () async {
        await service.dispose();
        await service.onDone;
      }();
}

class _OperationDeadline {
  _OperationDeadline(this.duration) : _stopwatch = Stopwatch()..start();

  final Duration duration;
  final Stopwatch _stopwatch;

  Duration get remaining => duration - _stopwatch.elapsed;

  Future<T> run<T>(Future<T> future, String operation) {
    final timeLeft = remaining;
    if (timeLeft <= Duration.zero) {
      throw TimeoutException('$operation exceeded its deadline');
    }
    return future.timeout(
      timeLeft,
      onTimeout: () =>
          throw TimeoutException('$operation exceeded its deadline'),
    );
  }
}

Map<String, Object?> _sampleJson(
  int index,
  String threadId, {
  TimelineSpan? span,
  TimelineSpan? viaOtherThread,
  String? failure,
}) {
  return {
    'index': index,
    'status': failure == null ? 'observed' : 'failed',
    'threadId': threadId,
    ...?span?.toJson(),
    'viaOtherThread': viaOtherThread?.toJson(),
    'failure': ?failure,
  };
}

String _failureText(String operation, Object error) =>
    error is _ObservationDeadlineExceeded
    ? '$operation failed (${error.runtimeType}): ${error.message}'
    : '$operation failed (${error.runtimeType})';

class _ObservationDeadlineExceeded extends TimeoutException {
  _ObservationDeadlineExceeded(super.message);
}

Map<String, Object?> _observationSummary(TimelineObservation observation) => {
  'status': observation.status,
  'threadId': observation.threadId,
  'selectionId': observation.selectionId,
  'generation': observation.generation,
  'firstContentLayout': observation.firstContentLayout?.toJson(),
};

Future<int> runProbe(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    stdout
      ..writeln(
        'Usage: profile_timeline_probe.dart --vm-url <URI> --project-id <P> --thread-id <A> '
        '--mode cold|switch --samples <1..100> --output <JSON file> '
        '[--other-thread-id <B>] [--deadline-ms <1..120000>]',
      )
      ..write(_parser.usage);
    return 0;
  }

  final ProbeOptions options;
  try {
    options = parseProbeOptions(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln(_parser.usage);
    return 64;
  }

  final report = <String, Object?>{
    'schemaVersion': _schemaVersion,
    'mode': options.mode,
    'requestedSamples': options.samples,
    'completed': false,
    'samples': <Map<String, Object?>>[],
    'cleanup': <String, Object?>{
      'driverClosed': false,
      'vmServiceClosed': null,
    },
  };
  final connectionScope = _DriverConnectionScope();
  final originalConnector = vmServiceConnectFunction;
  vmServiceConnectFunction = connectionScope.connectOnce;
  Future<FlutterDriver>? driverConnection;
  FlutterDriver? driver;
  String? failure;
  try {
    final connectDeadline = _OperationDeadline(options.deadline);
    driverConnection = FlutterDriver.connect(
      dartVmServiceUrl: options.vmUrl.toString(),
      printCommunication: false,
      logCommunicationToFile: false,
    );
    driver = await connectDeadline.run(driverConnection, 'Driver connection');
    if (driver is! VMServiceFlutterDriver) {
      throw UnsupportedError('Only native VM Service Driver is supported');
    }
    connectionScope.transferToDriver();
    if (connectionScope.hasService) {
      (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'] = false;
    }
    report['stage'] = 'projectExpansion';
    report['projectId'] = options.projectId;
    report['threadId'] = options.threadId;
    final initial = await _readObservation(driver, options.deadline);
    report['initialObservation'] = {
      'status': initial.status,
      'threadId': initial.threadId,
      'selectionId': initial.selectionId,
      'generation': initial.generation,
    };
    // Fresh profile applications start with ordinary projects collapsed. Only
    // expanding the real sidebar owner mounts its Thread rows; no Thread is
    // selected here, so the owner selection-to-layout timing remains unchanged.
    await _OperationDeadline(options.deadline).run(
      driver.tap(
        find.byValueKey('project-expand-${options.projectId}'),
        timeout: options.deadline,
      ),
      'Expanding seed project',
    );
    report['stage'] = 'sampling';
    if (options.mode == 'cold') {
      final sample = await _coldSample(driver, options);
      (report['samples']! as List<Map<String, Object?>>).add(sample);
    } else {
      await _switchSamples(driver, options, report);
    }
  } catch (error) {
    failure = _failureText('Timeline probe', error);
    report['failure'] = failure;
    final samples = report['samples']! as List<Map<String, Object?>>;
    if (samples.isEmpty || samples.last['status'] != 'failed') {
      final nextIndex = samples.length + 1;
      if (nextIndex <= options.samples) {
        samples.add(
          _sampleJson(
            nextIndex,
            options.threadId,
            failure: _failureText('Sample setup', error),
          ),
        );
      }
    }
  } finally {
    vmServiceConnectFunction = originalConnector;
    if (driver != null) {
      try {
        await driver.close();
        (report['cleanup']! as Map<String, Object?>)
          ..['driverClosed'] = true
          ..['vmServiceClosed'] = connectionScope.hasService
              ? true
              : (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'];
      } catch (error) {
        final cleanupFailure = _failureText('Driver/VM Service cleanup', error);
        failure = failure == null
            ? cleanupFailure
            : '$failure; $cleanupFailure';
        report['failure'] = failure;
        try {
          await connectionScope.closeServiceAfterDriverFailure();
          if (connectionScope.hasService) {
            (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'] =
                true;
          }
        } catch (serviceError) {
          final serviceFailure = _failureText(
            'Owned VM Service cleanup',
            serviceError,
          );
          failure = '$failure; $serviceFailure';
          report['failure'] = failure;
        }
      }
    } else {
      if (driverConnection != null) {
        connectionScope.consumeLateDriver(driverConnection);
      }
      try {
        await connectionScope.closeAfterFailedConnect();
        if (connectionScope.hasService) {
          (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'] =
              true;
        } else if (connectionScope.hasUnsettledConnection) {
          (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'] =
              false;
        }
      } catch (error) {
        final cleanupFailure = _failureText('Owned VM Service cleanup', error);
        failure = failure == null
            ? cleanupFailure
            : '$failure; $cleanupFailure';
        report['failure'] = failure;
        if (connectionScope.hasService) {
          (report['cleanup']! as Map<String, Object?>)['vmServiceClosed'] =
              false;
        }
      }
    }
  }

  final samples = report['samples']! as List<Map<String, Object?>>;
  final cleanup = report['cleanup']! as Map<String, Object?>;
  final allObserved =
      samples.length == options.samples &&
      samples.every((sample) => sample['status'] == 'observed');
  report['completed'] =
      failure == null &&
      allObserved &&
      cleanup['driverClosed'] == true &&
      cleanup['vmServiceClosed'] == true;
  if (report['completed'] != true && report['failure'] == null) {
    report['failure'] = 'Probe did not complete all requested samples';
    failure = report['failure'] as String;
  }

  try {
    await File(
      options.outputPath,
    ).writeAsString('${const JsonEncoder.withIndent('  ').convert(report)}\n');
  } catch (error) {
    stderr.writeln(_failureText('Writing probe report', error));
    return 70;
  }
  if (failure != null || report['completed'] != true) {
    stderr.writeln(report['failure']);
    return 70;
  }
  return 0;
}

Future<Map<String, Object?>> _coldSample(
  FlutterDriver driver,
  ProbeOptions options,
) async {
  final observation = await _readObservation(driver, options.deadline);
  TimelineSpan span;
  if (observation.isObserved && observation.threadId == options.threadId) {
    span = observation.firstContentLayout!;
  } else if (observation.status == 'pending' &&
      observation.threadId == options.threadId) {
    final fresh = await _waitForObserved(
      driver,
      options.threadId,
      options.deadline,
      afterSelectionId: observation.selectionId! - 1,
      afterGeneration: observation.generation! - 1,
    );
    span = fresh.firstContentLayout!;
  } else {
    await _tapThread(driver, options.threadId, options.deadline);
    final fresh = await _waitForObserved(
      driver,
      options.threadId,
      options.deadline,
      afterSelectionId: observation.selectionId ?? -1,
      afterGeneration: observation.generation ?? -1,
    );
    span = fresh.firstContentLayout!;
  }
  return _sampleJson(1, options.threadId, span: span);
}

Future<void> _switchSamples(
  FlutterDriver driver,
  ProbeOptions options,
  Map<String, Object?> report,
) async {
  final otherThreadId = options.otherThreadId!;
  var current = await _readObservation(driver, options.deadline);
  if (current.isObserved && current.threadId == options.threadId) {
    // The already observed owner is the A baseline for this process.
  } else if (current.status == 'pending' &&
      current.threadId == options.threadId) {
    current = await _waitForObserved(
      driver,
      options.threadId,
      options.deadline,
      afterSelectionId: current.selectionId! - 1,
      afterGeneration: current.generation! - 1,
    );
  } else {
    await _tapThread(driver, options.threadId, options.deadline);
    current = await _waitForObserved(
      driver,
      options.threadId,
      options.deadline,
      afterSelectionId: current.selectionId ?? -1,
      afterGeneration: current.generation ?? -1,
    );
  }
  var lastSelectionId = current.selectionId!;
  var lastGeneration = current.generation!;
  final samples = report['samples']! as List<Map<String, Object?>>;

  for (var index = 1; index <= options.samples; index++) {
    TimelineSpan? otherSpan;
    try {
      await _tapThread(driver, otherThreadId, options.deadline);
      final other = await _waitForObserved(
        driver,
        otherThreadId,
        options.deadline,
        afterSelectionId: lastSelectionId,
        afterGeneration: lastGeneration,
      );
      otherSpan = other.firstContentLayout!;
      lastSelectionId = otherSpan.selectionId;
      lastGeneration = otherSpan.generation;

      await _tapThread(driver, options.threadId, options.deadline);
      final target = await _waitForObserved(
        driver,
        options.threadId,
        options.deadline,
        afterSelectionId: lastSelectionId,
        afterGeneration: lastGeneration,
      );
      final span = target.firstContentLayout!;
      lastSelectionId = span.selectionId;
      lastGeneration = span.generation;
      samples.add(
        _sampleJson(
          index,
          options.threadId,
          span: span,
          viaOtherThread: otherSpan,
        ),
      );
    } catch (error) {
      samples.add(
        _sampleJson(
          index,
          options.threadId,
          viaOtherThread: otherSpan,
          failure: _failureText('Switch sample $index', error),
        ),
      );
      rethrow;
    }
  }
}

Future<TimelineObservation> _readObservation(
  FlutterDriver driver,
  Duration deadline,
) async {
  final operationDeadline = _OperationDeadline(deadline);
  final response = await operationDeadline.run(
    driver.serviceClient.callServiceExtension(
      kTimelineLayoutExtensionName,
      isolateId: driver.appIsolate.id!,
      args: const {},
    ),
    'Timeline layout RPC',
  );
  return TimelineObservation.parse(response.json);
}

Future<TimelineObservation> _waitForObserved(
  FlutterDriver driver,
  String threadId,
  Duration deadline, {
  required int afterSelectionId,
  required int afterGeneration,
}) async {
  final waitDeadline = _OperationDeadline(deadline);
  TimelineObservation? lastObservation;
  while (true) {
    final remaining = waitDeadline.remaining;
    if (remaining <= Duration.zero) {
      throw _ObservationDeadlineExceeded(
        'Waiting for layout of $threadId exceeded deadline; '
        'lastObservation=${lastObservation == null ? 'none' : jsonEncode(_observationSummary(lastObservation))}',
      );
    }
    final TimelineObservation observation;
    try {
      observation = await _readObservation(driver, remaining);
    } on TimeoutException {
      throw _ObservationDeadlineExceeded(
        'Waiting for layout of $threadId exceeded deadline; '
        'lastObservation=${lastObservation == null ? 'none' : jsonEncode(_observationSummary(lastObservation))}',
      );
    }
    lastObservation = observation;
    if (isFreshObservation(
      observation,
      threadId: threadId,
      afterSelectionId: afterSelectionId,
      afterGeneration: afterGeneration,
    )) {
      requireFreshObservation(
        observation,
        threadId: threadId,
        afterSelectionId: afterSelectionId,
        afterGeneration: afterGeneration,
      );
      return observation;
    }
    final sleep = remaining < _pollInterval ? remaining : _pollInterval;
    await Future<void>.delayed(sleep);
  }
}

Future<void> _tapThread(
  FlutterDriver driver,
  String threadId,
  Duration deadline,
) async {
  final operationDeadline = _OperationDeadline(deadline);
  final finder = find.byValueKey(StudioDriverKeyValues.threadRow(threadId));
  await operationDeadline.run(
    driver.tap(finder, timeout: deadline),
    'Tapping thread row',
  );
}

Future<void> main(List<String> arguments) async {
  exitCode = await runProbe(arguments);
}
