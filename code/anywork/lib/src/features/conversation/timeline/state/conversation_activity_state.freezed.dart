// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_activity_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConversationActivityState {

 ConversationActivityView? get view; CurrentProjection? get current;
/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationActivityStateCopyWith<ConversationActivityState> get copyWith => _$ConversationActivityStateCopyWithImpl<ConversationActivityState>(this as ConversationActivityState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationActivityState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationActivityState&&(identical(other.view, _this.view) || other.view == _this.view)&&(identical(other.current, _this.current) || other.current == _this.current));
}


@override
int get hashCode {
  final _this = this as ConversationActivityState;
  return Object.hash(runtimeType,_this.view,_this.current);
}

@override
String toString() {
  final _this = this as ConversationActivityState;
  return 'ConversationActivityState(view: ${_this.view}, current: ${_this.current})';
}


}

/// @nodoc
abstract mixin class $ConversationActivityStateCopyWith<$Res>  {
  factory $ConversationActivityStateCopyWith(ConversationActivityState value, $Res Function(ConversationActivityState) _then) = _$ConversationActivityStateCopyWithImpl;
@useResult
$Res call({
 ConversationActivityView? view, CurrentProjection? current
});




}
/// @nodoc
class _$ConversationActivityStateCopyWithImpl<$Res>
    implements $ConversationActivityStateCopyWith<$Res> {
  _$ConversationActivityStateCopyWithImpl(this._self, this._then);

  final ConversationActivityState _self;
  final $Res Function(ConversationActivityState) _then;

/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? view = freezed,Object? current = freezed,}) {
  return _then(ConversationActivityState(
view: freezed == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as ConversationActivityView?,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as CurrentProjection?,
  ));
}

}


/// Adds pattern-matching-related methods to [ConversationActivityState].
extension ConversationActivityStatePatterns on ConversationActivityState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationActivityState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationActivityState value)  $default,){
final _that = this;
switch (_that) {
case _ConversationActivityState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationActivityState value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConversationActivityView? view,  CurrentProjection? current)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
return $default(_that.view,_that.current);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConversationActivityView? view,  CurrentProjection? current)  $default,) {final _that = this;
switch (_that) {
case _ConversationActivityState():
return $default(_that.view,_that.current);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConversationActivityView? view,  CurrentProjection? current)?  $default,) {final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
return $default(_that.view,_that.current);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationActivityState implements ConversationActivityState {
  const _ConversationActivityState({required this.view, this.current});


@override final  ConversationActivityView? view;
@override final  CurrentProjection? current;

/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationActivityStateCopyWith<_ConversationActivityState> get copyWith => __$ConversationActivityStateCopyWithImpl<_ConversationActivityState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationActivityState&&(identical(other.view, view) || other.view == view)&&(identical(other.current, current) || other.current == current));
}


@override
int get hashCode {
    return Object.hash(runtimeType,view,current);
}

@override
String toString() {
    return 'ConversationActivityState(view: $view, current: $current)';
}


}

/// @nodoc
abstract mixin class _$ConversationActivityStateCopyWith<$Res> implements $ConversationActivityStateCopyWith<$Res> {
  factory _$ConversationActivityStateCopyWith(_ConversationActivityState value, $Res Function(_ConversationActivityState) _then) = __$ConversationActivityStateCopyWithImpl;
@override @useResult
$Res call({
 ConversationActivityView? view, CurrentProjection? current
});




}
/// @nodoc
class __$ConversationActivityStateCopyWithImpl<$Res>
    implements _$ConversationActivityStateCopyWith<$Res> {
  __$ConversationActivityStateCopyWithImpl(this._self, this._then);

  final _ConversationActivityState _self;
  final $Res Function(_ConversationActivityState) _then;

/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? view = freezed,Object? current = freezed,}) {
  return _then(_ConversationActivityState(
view: freezed == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as ConversationActivityView?,current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as CurrentProjection?,
  ));
}


}

// dart format on
