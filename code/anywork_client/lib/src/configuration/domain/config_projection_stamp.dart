import 'package:freezed_annotation/freezed_annotation.dart';

part 'config_projection_stamp.freezed.dart';

/// A compatible pair published by the Rust configuration owner. These are
/// canonical source clocks, not Dart feed/delivery or projection revisions.
@freezed
abstract class ConfigProjectionStamp with _$ConfigProjectionStamp {
  const factory ConfigProjectionStamp({
    required int settingsRevision,
    required int modelCatalogRevision,
    required bool closing,
  }) = _ConfigProjectionStamp;
}
