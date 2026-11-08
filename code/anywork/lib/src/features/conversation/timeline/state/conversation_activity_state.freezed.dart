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

 ConversationActivityView? get view; ActivitySnapshot? get activity;
/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationActivityStateCopyWith<ConversationActivityState> get copyWith => _$ConversationActivityStateCopyWithImpl<ConversationActivityState>(this as ConversationActivityState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationActivityState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationActivityState&&(identical(other.view, _this.view) || other.view == _this.view)&&(identical(other.activity, _this.activity) || other.activity == _this.activity));
}


@override
int get hashCode {
  final _this = this as ConversationActivityState;
  return Object.hash(runtimeType,_this.view,_this.activity);
}

@override
String toString() {
  final _this = this as ConversationActivityState;
  return 'ConversationActivityState(view: ${_this.view}, activity: ${_this.activity})';
}


}

/// @nodoc
abstract mixin class $ConversationActivityStateCopyWith<$Res>  {
  factory $ConversationActivityStateCopyWith(ConversationActivityState value, $Res Function(ConversationActivityState) _then) = _$ConversationActivityStateCopyWithImpl;
@useResult
$Res call({
 ConversationActivityView? view, ActivitySnapshot? activity
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
@pragma('vm:prefer-inline') @override $Res call({Object? view = freezed,Object? activity = freezed,}) {
  return _then(ConversationActivityState(
view: freezed == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as ConversationActivityView?,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivitySnapshot?,
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConversationActivityView? view,  ActivitySnapshot? activity)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
return $default(_that.view,_that.activity);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConversationActivityView? view,  ActivitySnapshot? activity)  $default,) {final _that = this;
switch (_that) {
case _ConversationActivityState():
return $default(_that.view,_that.activity);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConversationActivityView? view,  ActivitySnapshot? activity)?  $default,) {final _that = this;
switch (_that) {
case _ConversationActivityState() when $default != null:
return $default(_that.view,_that.activity);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationActivityState implements ConversationActivityState {
  const _ConversationActivityState({required this.view, this.activity});


@override final  ConversationActivityView? view;
@override final  ActivitySnapshot? activity;

/// Create a copy of ConversationActivityState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationActivityStateCopyWith<_ConversationActivityState> get copyWith => __$ConversationActivityStateCopyWithImpl<_ConversationActivityState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationActivityState&&(identical(other.view, view) || other.view == view)&&(identical(other.activity, activity) || other.activity == activity));
}


@override
int get hashCode {
    return Object.hash(runtimeType,view,activity);
}

@override
String toString() {
    return 'ConversationActivityState(view: $view, activity: $activity)';
}


}

/// @nodoc
abstract mixin class _$ConversationActivityStateCopyWith<$Res> implements $ConversationActivityStateCopyWith<$Res> {
  factory _$ConversationActivityStateCopyWith(_ConversationActivityState value, $Res Function(_ConversationActivityState) _then) = __$ConversationActivityStateCopyWithImpl;
@override @useResult
$Res call({
 ConversationActivityView? view, ActivitySnapshot? activity
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
@override @pragma('vm:prefer-inline') $Res call({Object? view = freezed,Object? activity = freezed,}) {
  return _then(_ConversationActivityState(
view: freezed == view ? _self.view : view // ignore: cast_nullable_to_non_nullable
as ConversationActivityView?,activity: freezed == activity ? _self.activity : activity // ignore: cast_nullable_to_non_nullable
as ActivitySnapshot?,
  ));
}


}

// dart format on
