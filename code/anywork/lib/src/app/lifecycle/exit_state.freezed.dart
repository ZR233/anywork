// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'exit_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ApplicationExitState {

 ApplicationExitPhase get phase; ExitIntent? get intent; String? get readyUpdateVersion; List<UnresolvedResource> get unresolved; List<StudioShutdownIssue> get externalIssues; StudioExitReport? get report; StudioShutdownIssue? get diagnosticsIssue;
/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ApplicationExitStateCopyWith<ApplicationExitState> get copyWith => _$ApplicationExitStateCopyWithImpl<ApplicationExitState>(this as ApplicationExitState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ApplicationExitState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ApplicationExitState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.readyUpdateVersion, _this.readyUpdateVersion) || other.readyUpdateVersion == _this.readyUpdateVersion)&&const DeepCollectionEquality().equals(other.unresolved, _this.unresolved)&&const DeepCollectionEquality().equals(other.externalIssues, _this.externalIssues)&&(identical(other.report, _this.report) || other.report == _this.report)&&(identical(other.diagnosticsIssue, _this.diagnosticsIssue) || other.diagnosticsIssue == _this.diagnosticsIssue));
}


@override
int get hashCode {
  final _this = this as ApplicationExitState;
  return Object.hash(runtimeType,_this.phase,_this.intent,_this.readyUpdateVersion,const DeepCollectionEquality().hash(_this.unresolved),const DeepCollectionEquality().hash(_this.externalIssues),_this.report,_this.diagnosticsIssue);
}



}

/// @nodoc
abstract mixin class $ApplicationExitStateCopyWith<$Res>  {
  factory $ApplicationExitStateCopyWith(ApplicationExitState value, $Res Function(ApplicationExitState) _then) = _$ApplicationExitStateCopyWithImpl;
@useResult
$Res call({
 ApplicationExitPhase phase, ExitIntent? intent, String? readyUpdateVersion, List<UnresolvedResource> unresolved, List<StudioShutdownIssue> externalIssues, StudioExitReport? report, StudioShutdownIssue? diagnosticsIssue
});


$StudioExitReportCopyWith<$Res>? get report;$StudioShutdownIssueCopyWith<$Res>? get diagnosticsIssue;

}
/// @nodoc
class _$ApplicationExitStateCopyWithImpl<$Res>
    implements $ApplicationExitStateCopyWith<$Res> {
  _$ApplicationExitStateCopyWithImpl(this._self, this._then);

  final ApplicationExitState _self;
  final $Res Function(ApplicationExitState) _then;

/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? intent = freezed,Object? readyUpdateVersion = freezed,Object? unresolved = null,Object? externalIssues = null,Object? report = freezed,Object? diagnosticsIssue = freezed,}) {
  return _then(ApplicationExitState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ApplicationExitPhase,intent: freezed == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as ExitIntent?,readyUpdateVersion: freezed == readyUpdateVersion ? _self.readyUpdateVersion : readyUpdateVersion // ignore: cast_nullable_to_non_nullable
as String?,unresolved: null == unresolved ? _self.unresolved : unresolved // ignore: cast_nullable_to_non_nullable
as List<UnresolvedResource>,externalIssues: null == externalIssues ? _self.externalIssues : externalIssues // ignore: cast_nullable_to_non_nullable
as List<StudioShutdownIssue>,report: freezed == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as StudioExitReport?,diagnosticsIssue: freezed == diagnosticsIssue ? _self.diagnosticsIssue : diagnosticsIssue // ignore: cast_nullable_to_non_nullable
as StudioShutdownIssue?,
  ));
}
/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioExitReportCopyWith<$Res>? get report {
    if (_self.report == null) {
    return null;
  }

  return $StudioExitReportCopyWith<$Res>(_self.report!, (value) {
    return _then(_self.copyWith(report: value));
  });
}/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownIssueCopyWith<$Res>? get diagnosticsIssue {
    if (_self.diagnosticsIssue == null) {
    return null;
  }

  return $StudioShutdownIssueCopyWith<$Res>(_self.diagnosticsIssue!, (value) {
    return _then(_self.copyWith(diagnosticsIssue: value));
  });
}
}


/// Adds pattern-matching-related methods to [ApplicationExitState].
extension ApplicationExitStatePatterns on ApplicationExitState {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ApplicationExitState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ApplicationExitState() when $default != null:
return $default(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ApplicationExitState value)  $default,){
final _that = this;
switch (_that) {
case _ApplicationExitState():
return $default(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ApplicationExitState value)?  $default,){
final _that = this;
switch (_that) {
case _ApplicationExitState() when $default != null:
return $default(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ApplicationExitPhase phase,  ExitIntent? intent,  String? readyUpdateVersion,  List<UnresolvedResource> unresolved,  List<StudioShutdownIssue> externalIssues,  StudioExitReport? report,  StudioShutdownIssue? diagnosticsIssue)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ApplicationExitState() when $default != null:
return $default(_that.phase,_that.intent,_that.readyUpdateVersion,_that.unresolved,_that.externalIssues,_that.report,_that.diagnosticsIssue);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ApplicationExitPhase phase,  ExitIntent? intent,  String? readyUpdateVersion,  List<UnresolvedResource> unresolved,  List<StudioShutdownIssue> externalIssues,  StudioExitReport? report,  StudioShutdownIssue? diagnosticsIssue)  $default,) {final _that = this;
switch (_that) {
case _ApplicationExitState():
return $default(_that.phase,_that.intent,_that.readyUpdateVersion,_that.unresolved,_that.externalIssues,_that.report,_that.diagnosticsIssue);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ApplicationExitPhase phase,  ExitIntent? intent,  String? readyUpdateVersion,  List<UnresolvedResource> unresolved,  List<StudioShutdownIssue> externalIssues,  StudioExitReport? report,  StudioShutdownIssue? diagnosticsIssue)?  $default,) {final _that = this;
switch (_that) {
case _ApplicationExitState() when $default != null:
return $default(_that.phase,_that.intent,_that.readyUpdateVersion,_that.unresolved,_that.externalIssues,_that.report,_that.diagnosticsIssue);case _:
  return null;

}
}

}

/// @nodoc


class _ApplicationExitState extends ApplicationExitState {
  const _ApplicationExitState({required this.phase, required this.intent, required this.readyUpdateVersion, required  List<UnresolvedResource> unresolved, required  List<StudioShutdownIssue> externalIssues, required this.report, required this.diagnosticsIssue}): _unresolved = unresolved,_externalIssues = externalIssues,super._();


@override final  ApplicationExitPhase phase;
@override final  ExitIntent? intent;
@override final  String? readyUpdateVersion;
 final  List<UnresolvedResource> _unresolved;
@override List<UnresolvedResource> get unresolved {
  if (_unresolved is EqualUnmodifiableListView) return _unresolved;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_unresolved);
}

 final  List<StudioShutdownIssue> _externalIssues;
@override List<StudioShutdownIssue> get externalIssues {
  if (_externalIssues is EqualUnmodifiableListView) return _externalIssues;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_externalIssues);
}

@override final  StudioExitReport? report;
@override final  StudioShutdownIssue? diagnosticsIssue;

/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ApplicationExitStateCopyWith<_ApplicationExitState> get copyWith => __$ApplicationExitStateCopyWithImpl<_ApplicationExitState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ApplicationExitState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.readyUpdateVersion, readyUpdateVersion) || other.readyUpdateVersion == readyUpdateVersion)&&const DeepCollectionEquality().equals(other.unresolved, _unresolved)&&const DeepCollectionEquality().equals(other.externalIssues, _externalIssues)&&(identical(other.report, report) || other.report == report)&&(identical(other.diagnosticsIssue, diagnosticsIssue) || other.diagnosticsIssue == diagnosticsIssue));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,intent,readyUpdateVersion,const DeepCollectionEquality().hash(_unresolved),const DeepCollectionEquality().hash(_externalIssues),report,diagnosticsIssue);
}



}

/// @nodoc
abstract mixin class _$ApplicationExitStateCopyWith<$Res> implements $ApplicationExitStateCopyWith<$Res> {
  factory _$ApplicationExitStateCopyWith(_ApplicationExitState value, $Res Function(_ApplicationExitState) _then) = __$ApplicationExitStateCopyWithImpl;
@override @useResult
$Res call({
 ApplicationExitPhase phase, ExitIntent? intent, String? readyUpdateVersion, List<UnresolvedResource> unresolved, List<StudioShutdownIssue> externalIssues, StudioExitReport? report, StudioShutdownIssue? diagnosticsIssue
});


@override $StudioExitReportCopyWith<$Res>? get report;@override $StudioShutdownIssueCopyWith<$Res>? get diagnosticsIssue;

}
/// @nodoc
class __$ApplicationExitStateCopyWithImpl<$Res>
    implements _$ApplicationExitStateCopyWith<$Res> {
  __$ApplicationExitStateCopyWithImpl(this._self, this._then);

  final _ApplicationExitState _self;
  final $Res Function(_ApplicationExitState) _then;

/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? intent = freezed,Object? readyUpdateVersion = freezed,Object? unresolved = null,Object? externalIssues = null,Object? report = freezed,Object? diagnosticsIssue = freezed,}) {
  return _then(_ApplicationExitState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as ApplicationExitPhase,intent: freezed == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as ExitIntent?,readyUpdateVersion: freezed == readyUpdateVersion ? _self.readyUpdateVersion : readyUpdateVersion // ignore: cast_nullable_to_non_nullable
as String?,unresolved: null == unresolved ? _self._unresolved : unresolved // ignore: cast_nullable_to_non_nullable
as List<UnresolvedResource>,externalIssues: null == externalIssues ? _self._externalIssues : externalIssues // ignore: cast_nullable_to_non_nullable
as List<StudioShutdownIssue>,report: freezed == report ? _self.report : report // ignore: cast_nullable_to_non_nullable
as StudioExitReport?,diagnosticsIssue: freezed == diagnosticsIssue ? _self.diagnosticsIssue : diagnosticsIssue // ignore: cast_nullable_to_non_nullable
as StudioShutdownIssue?,
  ));
}

/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioExitReportCopyWith<$Res>? get report {
    if (_self.report == null) {
    return null;
  }

  return $StudioExitReportCopyWith<$Res>(_self.report!, (value) {
    return _then(_self.copyWith(report: value));
  });
}/// Create a copy of ApplicationExitState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownIssueCopyWith<$Res>? get diagnosticsIssue {
    if (_self.diagnosticsIssue == null) {
    return null;
  }

  return $StudioShutdownIssueCopyWith<$Res>(_self.diagnosticsIssue!, (value) {
    return _then(_self.copyWith(diagnosticsIssue: value));
  });
}
}

// dart format on
