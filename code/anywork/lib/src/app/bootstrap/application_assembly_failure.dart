import 'package:anywork_client/resources.dart';

/// A failed construction still owns its original cleanup capabilities. The
/// startup VM presents [cause] through its existing typed error channel, and
/// must join this responsibility before admitting another factory attempt.
final class ApplicationAssemblyFailure implements Exception {
  ApplicationAssemblyFailure({
    required this.cause,
    required this.stack,
    required this._report,
    required this._retryCleanup,
  });

  final Object cause;
  final StackTrace stack;
  final Future<CloseReport> Function() _retryCleanup;
  CloseReport _report;

  CloseReport get report => _report;

  Future<CloseReport> retryCleanup() async {
    _report = await _retryCleanup();
    return _report;
  }
}
