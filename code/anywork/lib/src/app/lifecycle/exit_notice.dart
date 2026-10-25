import 'dart:async';

import 'package:flutter/scheduler.dart';

/// One actual render opportunity and at most the original 1.2s reading budget.
/// Both consume the remaining first native deadline, never a new allowance.
Future<void> presentApplicationExitNotice(
  Duration remaining,
  bool allowReading,
) async {
  final clock = Stopwatch()..start();
  if (remaining <= Duration.zero) return;
  await SchedulerBinding.instance.endOfFrame.timeout(
    remaining < const Duration(milliseconds: 200)
        ? remaining
        : const Duration(milliseconds: 200),
    onTimeout: () {},
  );
  final left = remaining - clock.elapsed;
  if (!allowReading || left <= Duration.zero) return;
  await Future<void>.delayed(
    left < const Duration(milliseconds: 1200)
        ? left
        : const Duration(milliseconds: 1200),
  );
}
