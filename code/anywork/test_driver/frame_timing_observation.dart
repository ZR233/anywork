import 'dart:ui' show FramePhase, FrameTiming;

/// Raw finish timestamps are observations, not selection-to-layout latency.
/// Engine time, wall time and Dart Stopwatch must not be directly subtracted.
Map<String, num> frameTimingSample(FrameTiming timing) => {
  'rasterFinishMicros': timing.timestampInMicroseconds(FramePhase.rasterFinish),
  'rasterFinishWallTimeMicros': timing.timestampInMicroseconds(
    FramePhase.rasterFinishWallTime,
  ),
  'totalMillis': timing.totalSpan.inMicroseconds / 1000,
  'vsyncOverheadMillis': timing.vsyncOverhead.inMicroseconds / 1000,
  'buildMillis': timing.buildDuration.inMicroseconds / 1000,
  'rasterMillis': timing.rasterDuration.inMicroseconds / 1000,
};
