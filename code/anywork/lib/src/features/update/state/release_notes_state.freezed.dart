// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'release_notes_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReleaseNotesState {

 bool get opening; StudioFailure? get error;
/// Create a copy of ReleaseNotesState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReleaseNotesStateCopyWith<ReleaseNotesState> get copyWith => _$ReleaseNotesStateCopyWithImpl<ReleaseNotesState>(this as ReleaseNotesState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ReleaseNotesState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReleaseNotesState&&(identical(other.opening, _this.opening) || other.opening == _this.opening)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ReleaseNotesState;
  return Object.hash(runtimeType,_this.opening,_this.error);
}



}

/// @nodoc
abstract mixin class $ReleaseNotesStateCopyWith<$Res>  {
  factory $ReleaseNotesStateCopyWith(ReleaseNotesState value, $Res Function(ReleaseNotesState) _then) = _$ReleaseNotesStateCopyWithImpl;
@useResult
$Res call({
 bool opening, StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ReleaseNotesStateCopyWithImpl<$Res>
    implements $ReleaseNotesStateCopyWith<$Res> {
  _$ReleaseNotesStateCopyWithImpl(this._self, this._then);

  final ReleaseNotesState _self;
  final $Res Function(ReleaseNotesState) _then;

/// Create a copy of ReleaseNotesState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? opening = null,Object? error = freezed,}) {
  return _then(ReleaseNotesState(
opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ReleaseNotesState
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


/// Adds pattern-matching-related methods to [ReleaseNotesState].
extension ReleaseNotesStatePatterns on ReleaseNotesState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReleaseNotesState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReleaseNotesState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReleaseNotesState value)  $default,){
final _that = this;
switch (_that) {
case _ReleaseNotesState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReleaseNotesState value)?  $default,){
final _that = this;
switch (_that) {
case _ReleaseNotesState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool opening,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReleaseNotesState() when $default != null:
return $default(_that.opening,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool opening,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _ReleaseNotesState():
return $default(_that.opening,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool opening,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _ReleaseNotesState() when $default != null:
return $default(_that.opening,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ReleaseNotesState implements ReleaseNotesState {
  const _ReleaseNotesState({this.opening = false, this.error});


@override@JsonKey() final  bool opening;
@override final  StudioFailure? error;

/// Create a copy of ReleaseNotesState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReleaseNotesStateCopyWith<_ReleaseNotesState> get copyWith => __$ReleaseNotesStateCopyWithImpl<_ReleaseNotesState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReleaseNotesState&&(identical(other.opening, opening) || other.opening == opening)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,opening,error);
}



}

/// @nodoc
abstract mixin class _$ReleaseNotesStateCopyWith<$Res> implements $ReleaseNotesStateCopyWith<$Res> {
  factory _$ReleaseNotesStateCopyWith(_ReleaseNotesState value, $Res Function(_ReleaseNotesState) _then) = __$ReleaseNotesStateCopyWithImpl;
@override @useResult
$Res call({
 bool opening, StudioFailure? error
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ReleaseNotesStateCopyWithImpl<$Res>
    implements _$ReleaseNotesStateCopyWith<$Res> {
  __$ReleaseNotesStateCopyWithImpl(this._self, this._then);

  final _ReleaseNotesState _self;
  final $Res Function(_ReleaseNotesState) _then;

/// Create a copy of ReleaseNotesState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? opening = null,Object? error = freezed,}) {
  return _then(_ReleaseNotesState(
opening: null == opening ? _self.opening : opening // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ReleaseNotesState
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
