import 'package:anywork_client/statistics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Composition roots must inject the AppGraph-owned repository explicitly.
final statisticsRepositoryProvider = Provider<StatisticsRepository>(
  (ref) => throw StateError(
    'StatisticsRepository must be injected by the application composition root',
  ),
  name: 'statisticsRepositoryProvider',
);
