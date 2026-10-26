import 'package:freezed_annotation/freezed_annotation.dart';

import '../../models/domain/model_values.dart';
import '../../modes/domain/mode_values.dart';
import '../../resources/domain/failures.dart';
import 'configuration_state.dart';
import 'configuration_values.dart';

part 'start_route_values.freezed.dart';

/// Raw Start editing intent. Null/empty effort and explicit model identity are
/// preserved for the original native resolver, never normalized in Dart.
@freezed
abstract class StartRouteIntent with _$StartRouteIntent {
  const factory StartRouteIntent({
    required ThreadModeId mode,
    AccountModelKey? model,
    String? effort,
  }) = _StartRouteIntent;
}

@freezed
sealed class StartRouteQuery with _$StartRouteQuery {
  const factory StartRouteQuery.resolve({required StartRouteIntent intent}) =
      ResolveStartRouteQuery;
  const factory StartRouteQuery.selectModel({
    required StartRouteIntent intent,
    required AccountModelKey selected,
  }) = SelectModelStartRouteQuery;
}

/// Native business availability, not transport/source failure. Both variants
/// retain the original credential/query and the resulting editing identity.
/// Drafts must recheck their current sources and intent before adoption/submit.
@Freezed(toStringOverride: false)
sealed class StartRouteRead with _$StartRouteRead {
  const factory StartRouteRead.ready({
    required ConfigurationRoleReadTarget sources,
    required StartRouteQuery query,
    required StartRouteIntent intent,
    required ModelSelection route,
    required DelegationSettings defaults,
  }) = ReadyStartRouteRead;
  const factory StartRouteRead.unavailable({
    required ConfigurationRoleReadTarget sources,
    required StartRouteQuery query,
    required StartRouteIntent intent,
    required ModelSelection? desired,
    required DelegationSettings defaults,
    required StudioFailure error,
  }) = UnavailableStartRouteRead;
}
