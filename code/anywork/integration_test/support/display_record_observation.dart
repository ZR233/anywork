import 'package:anywork/src/features/conversation/timeline/state/timeline_display_unit.dart';

export 'display_record_expectations.dart';

String? completedOriginalId(DisplayRecord record) =>
    switch (record.contentSource) {
      CompletedOriginal(:final completionId) => completionId,
      CurrentAtomSource() || FrozenObservation() => null,
    };
