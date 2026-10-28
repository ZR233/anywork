// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_options_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionOptionsState {

 int get intent; bool get waiting; OperationState? get operation; StudioFailure? get error; String? get explanation; StartRoutePreferences? get preferences;
/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionOptionsStateCopyWith<SessionOptionsState> get copyWith => _$SessionOptionsStateCopyWithImpl<SessionOptionsState>(this as SessionOptionsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionOptionsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionOptionsState&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.waiting, _this.waiting) || other.waiting == _this.waiting)&&(identical(other.operation, _this.operation) || other.operation == _this.operation)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.explanation, _this.explanation) || other.explanation == _this.explanation)&&(identical(other.preferences, _this.preferences) || other.preferences == _this.preferences));
}


@override
int get hashCode {
  final _this = this as SessionOptionsState;
  return Object.hash(runtimeType,_this.intent,_this.waiting,_this.operation,_this.error,_this.explanation,_this.preferences);
}



}

/// @nodoc
abstract mixin class $SessionOptionsStateCopyWith<$Res>  {
  factory $SessionOptionsStateCopyWith(SessionOptionsState value, $Res Function(SessionOptionsState) _then) = _$SessionOptionsStateCopyWithImpl;
@useResult
$Res call({
 int intent, bool waiting, OperationState? operation, StudioFailure? error, String? explanation, StartRoutePreferences? preferences
});


$OperationStateCopyWith<$Res>? get operation;$StudioFailureCopyWith<$Res>? get error;$StartRoutePreferencesCopyWith<$Res>? get preferences;

}
/// @nodoc
class _$SessionOptionsStateCopyWithImpl<$Res>
    implements $SessionOptionsStateCopyWith<$Res> {
  _$SessionOptionsStateCopyWithImpl(this._self, this._then);

  final SessionOptionsState _self;
  final $Res Function(SessionOptionsState) _then;

/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? waiting = null,Object? operation = freezed,Object? error = freezed,Object? explanation = freezed,Object? preferences = freezed,}) {
  return _then(SessionOptionsState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,waiting: null == waiting ? _self.waiting : waiting // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,preferences: freezed == preferences ? _self.preferences : preferences // ignore: cast_nullable_to_non_nullable
as StartRoutePreferences?,
  ));
}
/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of SessionOptionsState
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
}/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRoutePreferencesCopyWith<$Res>? get preferences {
    if (_self.preferences == null) {
    return null;
  }

  return $StartRoutePreferencesCopyWith<$Res>(_self.preferences!, (value) {
    return _then(_self.copyWith(preferences: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionOptionsState].
extension SessionOptionsStatePatterns on SessionOptionsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SessionOptionsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SessionOptionsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SessionOptionsState value)  $default,){
final _that = this;
switch (_that) {
case _SessionOptionsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SessionOptionsState value)?  $default,){
final _that = this;
switch (_that) {
case _SessionOptionsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? error,  String? explanation,  StartRoutePreferences? preferences)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SessionOptionsState() when $default != null:
return $default(_that.intent,_that.waiting,_that.operation,_that.error,_that.explanation,_that.preferences);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? error,  String? explanation,  StartRoutePreferences? preferences)  $default,) {final _that = this;
switch (_that) {
case _SessionOptionsState():
return $default(_that.intent,_that.waiting,_that.operation,_that.error,_that.explanation,_that.preferences);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int intent,  bool waiting,  OperationState? operation,  StudioFailure? error,  String? explanation,  StartRoutePreferences? preferences)?  $default,) {final _that = this;
switch (_that) {
case _SessionOptionsState() when $default != null:
return $default(_that.intent,_that.waiting,_that.operation,_that.error,_that.explanation,_that.preferences);case _:
  return null;

}
}

}

/// @nodoc


class _SessionOptionsState extends SessionOptionsState {
  const _SessionOptionsState({this.intent = 0, this.waiting = false, this.operation, this.error, this.explanation, this.preferences}): super._();


@override@JsonKey() final  int intent;
@override@JsonKey() final  bool waiting;
@override final  OperationState? operation;
@override final  StudioFailure? error;
@override final  String? explanation;
@override final  StartRoutePreferences? preferences;

/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SessionOptionsStateCopyWith<_SessionOptionsState> get copyWith => __$SessionOptionsStateCopyWithImpl<_SessionOptionsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SessionOptionsState&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.waiting, waiting) || other.waiting == waiting)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error)&&(identical(other.explanation, explanation) || other.explanation == explanation)&&(identical(other.preferences, preferences) || other.preferences == preferences));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,waiting,operation,error,explanation,preferences);
}



}

/// @nodoc
abstract mixin class _$SessionOptionsStateCopyWith<$Res> implements $SessionOptionsStateCopyWith<$Res> {
  factory _$SessionOptionsStateCopyWith(_SessionOptionsState value, $Res Function(_SessionOptionsState) _then) = __$SessionOptionsStateCopyWithImpl;
@override @useResult
$Res call({
 int intent, bool waiting, OperationState? operation, StudioFailure? error, String? explanation, StartRoutePreferences? preferences
});


@override $OperationStateCopyWith<$Res>? get operation;@override $StudioFailureCopyWith<$Res>? get error;@override $StartRoutePreferencesCopyWith<$Res>? get preferences;

}
/// @nodoc
class __$SessionOptionsStateCopyWithImpl<$Res>
    implements _$SessionOptionsStateCopyWith<$Res> {
  __$SessionOptionsStateCopyWithImpl(this._self, this._then);

  final _SessionOptionsState _self;
  final $Res Function(_SessionOptionsState) _then;

/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? waiting = null,Object? operation = freezed,Object? error = freezed,Object? explanation = freezed,Object? preferences = freezed,}) {
  return _then(_SessionOptionsState(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as int,waiting: null == waiting ? _self.waiting : waiting // ignore: cast_nullable_to_non_nullable
as bool,operation: freezed == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as OperationState?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,explanation: freezed == explanation ? _self.explanation : explanation // ignore: cast_nullable_to_non_nullable
as String?,preferences: freezed == preferences ? _self.preferences : preferences // ignore: cast_nullable_to_non_nullable
as StartRoutePreferences?,
  ));
}

/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationStateCopyWith<$Res>? get operation {
    if (_self.operation == null) {
    return null;
  }

  return $OperationStateCopyWith<$Res>(_self.operation!, (value) {
    return _then(_self.copyWith(operation: value));
  });
}/// Create a copy of SessionOptionsState
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
}/// Create a copy of SessionOptionsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRoutePreferencesCopyWith<$Res>? get preferences {
    if (_self.preferences == null) {
    return null;
  }

  return $StartRoutePreferencesCopyWith<$Res>(_self.preferences!, (value) {
    return _then(_self.copyWith(preferences: value));
  });
}
}

// dart format on
