// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_timeline.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineConnectionState {

 String get threadId; TimelineConnectionPhase get phase; AttemptId? get attemptId; ViewStamp? get lastStamp; StudioFailure? get error; bool get retryExhausted;
/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineConnectionStateCopyWith<TimelineConnectionState> get copyWith => _$TimelineConnectionStateCopyWithImpl<TimelineConnectionState>(this as TimelineConnectionState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineConnectionState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineConnectionState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.lastStamp, _this.lastStamp) || other.lastStamp == _this.lastStamp)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.retryExhausted, _this.retryExhausted) || other.retryExhausted == _this.retryExhausted));
}


@override
int get hashCode {
  final _this = this as TimelineConnectionState;
  return Object.hash(runtimeType,_this.threadId,_this.phase,_this.attemptId,_this.lastStamp,_this.error,_this.retryExhausted);
}



}

/// @nodoc
abstract mixin class $TimelineConnectionStateCopyWith<$Res>  {
  factory $TimelineConnectionStateCopyWith(TimelineConnectionState value, $Res Function(TimelineConnectionState) _then) = _$TimelineConnectionStateCopyWithImpl;
@useResult
$Res call({
 String threadId, TimelineConnectionPhase phase, AttemptId? attemptId, ViewStamp? lastStamp, StudioFailure? error, bool retryExhausted
});


$AttemptIdCopyWith<$Res>? get attemptId;$ViewStampCopyWith<$Res>? get lastStamp;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$TimelineConnectionStateCopyWithImpl<$Res>
    implements $TimelineConnectionStateCopyWith<$Res> {
  _$TimelineConnectionStateCopyWithImpl(this._self, this._then);

  final TimelineConnectionState _self;
  final $Res Function(TimelineConnectionState) _then;

/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? phase = null,Object? attemptId = freezed,Object? lastStamp = freezed,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(TimelineConnectionState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as AttemptId?,lastStamp: freezed == lastStamp ? _self.lastStamp : lastStamp // ignore: cast_nullable_to_non_nullable
as ViewStamp?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttemptIdCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $AttemptIdCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ViewStampCopyWith<$Res>? get lastStamp {
    if (_self.lastStamp == null) {
    return null;
  }

  return $ViewStampCopyWith<$Res>(_self.lastStamp!, (value) {
    return _then(_self.copyWith(lastStamp: value));
  });
}/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineConnectionState].
extension TimelineConnectionStatePatterns on TimelineConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineConnectionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineConnectionState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineConnectionState value)  $default,){
final _that = this;
switch (_that) {
case _TimelineConnectionState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineConnectionState value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineConnectionState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  TimelineConnectionPhase phase,  AttemptId? attemptId,  ViewStamp? lastStamp,  StudioFailure? error,  bool retryExhausted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineConnectionState() when $default != null:
return $default(_that.threadId,_that.phase,_that.attemptId,_that.lastStamp,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  TimelineConnectionPhase phase,  AttemptId? attemptId,  ViewStamp? lastStamp,  StudioFailure? error,  bool retryExhausted)  $default,) {final _that = this;
switch (_that) {
case _TimelineConnectionState():
return $default(_that.threadId,_that.phase,_that.attemptId,_that.lastStamp,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  TimelineConnectionPhase phase,  AttemptId? attemptId,  ViewStamp? lastStamp,  StudioFailure? error,  bool retryExhausted)?  $default,) {final _that = this;
switch (_that) {
case _TimelineConnectionState() when $default != null:
return $default(_that.threadId,_that.phase,_that.attemptId,_that.lastStamp,_that.error,_that.retryExhausted);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineConnectionState implements TimelineConnectionState {
  const _TimelineConnectionState({required this.threadId, required this.phase, this.attemptId, this.lastStamp, this.error, this.retryExhausted = false});


@override final  String threadId;
@override final  TimelineConnectionPhase phase;
@override final  AttemptId? attemptId;
@override final  ViewStamp? lastStamp;
@override final  StudioFailure? error;
@override@JsonKey() final  bool retryExhausted;

/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineConnectionStateCopyWith<_TimelineConnectionState> get copyWith => __$TimelineConnectionStateCopyWithImpl<_TimelineConnectionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineConnectionState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.lastStamp, lastStamp) || other.lastStamp == lastStamp)&&(identical(other.error, error) || other.error == error)&&(identical(other.retryExhausted, retryExhausted) || other.retryExhausted == retryExhausted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,phase,attemptId,lastStamp,error,retryExhausted);
}



}

/// @nodoc
abstract mixin class _$TimelineConnectionStateCopyWith<$Res> implements $TimelineConnectionStateCopyWith<$Res> {
  factory _$TimelineConnectionStateCopyWith(_TimelineConnectionState value, $Res Function(_TimelineConnectionState) _then) = __$TimelineConnectionStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, TimelineConnectionPhase phase, AttemptId? attemptId, ViewStamp? lastStamp, StudioFailure? error, bool retryExhausted
});


@override $AttemptIdCopyWith<$Res>? get attemptId;@override $ViewStampCopyWith<$Res>? get lastStamp;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$TimelineConnectionStateCopyWithImpl<$Res>
    implements _$TimelineConnectionStateCopyWith<$Res> {
  __$TimelineConnectionStateCopyWithImpl(this._self, this._then);

  final _TimelineConnectionState _self;
  final $Res Function(_TimelineConnectionState) _then;

/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? phase = null,Object? attemptId = freezed,Object? lastStamp = freezed,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(_TimelineConnectionState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as AttemptId?,lastStamp: freezed == lastStamp ? _self.lastStamp : lastStamp // ignore: cast_nullable_to_non_nullable
as ViewStamp?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AttemptIdCopyWith<$Res>? get attemptId {
    if (_self.attemptId == null) {
    return null;
  }

  return $AttemptIdCopyWith<$Res>(_self.attemptId!, (value) {
    return _then(_self.copyWith(attemptId: value));
  });
}/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ViewStampCopyWith<$Res>? get lastStamp {
    if (_self.lastStamp == null) {
    return null;
  }

  return $ViewStampCopyWith<$Res>(_self.lastStamp!, (value) {
    return _then(_self.copyWith(lastStamp: value));
  });
}/// Create a copy of TimelineConnectionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
