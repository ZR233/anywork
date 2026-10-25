// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'settings_workspace_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SettingsWorkspaceState {

 WorkspaceState get source; bool get observing; StudioFailure? get observationError;
/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SettingsWorkspaceStateCopyWith<SettingsWorkspaceState> get copyWith => _$SettingsWorkspaceStateCopyWithImpl<SettingsWorkspaceState>(this as SettingsWorkspaceState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SettingsWorkspaceState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SettingsWorkspaceState&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.observing, _this.observing) || other.observing == _this.observing)&&(identical(other.observationError, _this.observationError) || other.observationError == _this.observationError));
}


@override
int get hashCode {
  final _this = this as SettingsWorkspaceState;
  return Object.hash(runtimeType,_this.source,_this.observing,_this.observationError);
}



}

/// @nodoc
abstract mixin class $SettingsWorkspaceStateCopyWith<$Res>  {
  factory $SettingsWorkspaceStateCopyWith(SettingsWorkspaceState value, $Res Function(SettingsWorkspaceState) _then) = _$SettingsWorkspaceStateCopyWithImpl;
@useResult
$Res call({
 WorkspaceState source, bool observing, StudioFailure? observationError
});


$WorkspaceStateCopyWith<$Res> get source;$StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class _$SettingsWorkspaceStateCopyWithImpl<$Res>
    implements $SettingsWorkspaceStateCopyWith<$Res> {
  _$SettingsWorkspaceStateCopyWithImpl(this._self, this._then);

  final SettingsWorkspaceState _self;
  final $Res Function(SettingsWorkspaceState) _then;

/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? observing = null,Object? observationError = freezed,}) {
  return _then(SettingsWorkspaceState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as WorkspaceState,observing: null == observing ? _self.observing : observing // ignore: cast_nullable_to_non_nullable
as bool,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get source {

  return $WorkspaceStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}


/// Adds pattern-matching-related methods to [SettingsWorkspaceState].
extension SettingsWorkspaceStatePatterns on SettingsWorkspaceState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SettingsWorkspaceState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SettingsWorkspaceState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SettingsWorkspaceState value)  $default,){
final _that = this;
switch (_that) {
case _SettingsWorkspaceState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SettingsWorkspaceState value)?  $default,){
final _that = this;
switch (_that) {
case _SettingsWorkspaceState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WorkspaceState source,  bool observing,  StudioFailure? observationError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SettingsWorkspaceState() when $default != null:
return $default(_that.source,_that.observing,_that.observationError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WorkspaceState source,  bool observing,  StudioFailure? observationError)  $default,) {final _that = this;
switch (_that) {
case _SettingsWorkspaceState():
return $default(_that.source,_that.observing,_that.observationError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WorkspaceState source,  bool observing,  StudioFailure? observationError)?  $default,) {final _that = this;
switch (_that) {
case _SettingsWorkspaceState() when $default != null:
return $default(_that.source,_that.observing,_that.observationError);case _:
  return null;

}
}

}

/// @nodoc


class _SettingsWorkspaceState extends SettingsWorkspaceState {
  const _SettingsWorkspaceState({required this.source, required this.observing, this.observationError}): super._();


@override final  WorkspaceState source;
@override final  bool observing;
@override final  StudioFailure? observationError;

/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SettingsWorkspaceStateCopyWith<_SettingsWorkspaceState> get copyWith => __$SettingsWorkspaceStateCopyWithImpl<_SettingsWorkspaceState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SettingsWorkspaceState&&(identical(other.source, source) || other.source == source)&&(identical(other.observing, observing) || other.observing == observing)&&(identical(other.observationError, observationError) || other.observationError == observationError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,observing,observationError);
}



}

/// @nodoc
abstract mixin class _$SettingsWorkspaceStateCopyWith<$Res> implements $SettingsWorkspaceStateCopyWith<$Res> {
  factory _$SettingsWorkspaceStateCopyWith(_SettingsWorkspaceState value, $Res Function(_SettingsWorkspaceState) _then) = __$SettingsWorkspaceStateCopyWithImpl;
@override @useResult
$Res call({
 WorkspaceState source, bool observing, StudioFailure? observationError
});


@override $WorkspaceStateCopyWith<$Res> get source;@override $StudioFailureCopyWith<$Res>? get observationError;

}
/// @nodoc
class __$SettingsWorkspaceStateCopyWithImpl<$Res>
    implements _$SettingsWorkspaceStateCopyWith<$Res> {
  __$SettingsWorkspaceStateCopyWithImpl(this._self, this._then);

  final _SettingsWorkspaceState _self;
  final $Res Function(_SettingsWorkspaceState) _then;

/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? observing = null,Object? observationError = freezed,}) {
  return _then(_SettingsWorkspaceState(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as WorkspaceState,observing: null == observing ? _self.observing : observing // ignore: cast_nullable_to_non_nullable
as bool,observationError: freezed == observationError ? _self.observationError : observationError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WorkspaceStateCopyWith<$Res> get source {

  return $WorkspaceStateCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of SettingsWorkspaceState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get observationError {
    if (_self.observationError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.observationError!, (value) {
    return _then(_self.copyWith(observationError: value));
  });
}
}

// dart format on
