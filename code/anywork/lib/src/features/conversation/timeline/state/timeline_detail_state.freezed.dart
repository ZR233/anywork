// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_detail_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineDetailState {

 String get text; bool get loading; bool get complete; bool get terminal; Object? get error;
/// Create a copy of TimelineDetailState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineDetailStateCopyWith<TimelineDetailState> get copyWith => _$TimelineDetailStateCopyWithImpl<TimelineDetailState>(this as TimelineDetailState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineDetailState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineDetailState&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.complete, _this.complete) || other.complete == _this.complete)&&(identical(other.terminal, _this.terminal) || other.terminal == _this.terminal)&&const DeepCollectionEquality().equals(other.error, _this.error));
}


@override
int get hashCode {
  final _this = this as TimelineDetailState;
  return Object.hash(runtimeType,_this.text,_this.loading,_this.complete,_this.terminal,const DeepCollectionEquality().hash(_this.error));
}

@override
String toString() {
  final _this = this as TimelineDetailState;
  return 'TimelineDetailState(text: ${_this.text}, loading: ${_this.loading}, complete: ${_this.complete}, terminal: ${_this.terminal}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $TimelineDetailStateCopyWith<$Res>  {
  factory $TimelineDetailStateCopyWith(TimelineDetailState value, $Res Function(TimelineDetailState) _then) = _$TimelineDetailStateCopyWithImpl;
@useResult
$Res call({
 String text, bool loading, bool complete, bool terminal, Object? error
});




}
/// @nodoc
class _$TimelineDetailStateCopyWithImpl<$Res>
    implements $TimelineDetailStateCopyWith<$Res> {
  _$TimelineDetailStateCopyWithImpl(this._self, this._then);

  final TimelineDetailState _self;
  final $Res Function(TimelineDetailState) _then;

/// Create a copy of TimelineDetailState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? text = null,Object? loading = null,Object? complete = null,Object? terminal = null,Object? error = freezed,}) {
  return _then(TimelineDetailState(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,
  ));
}

}


/// Adds pattern-matching-related methods to [TimelineDetailState].
extension TimelineDetailStatePatterns on TimelineDetailState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineDetailState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineDetailState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineDetailState value)  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineDetailState value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineDetailState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String text,  bool loading,  bool complete,  bool terminal,  Object? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineDetailState() when $default != null:
return $default(_that.text,_that.loading,_that.complete,_that.terminal,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String text,  bool loading,  bool complete,  bool terminal,  Object? error)  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailState():
return $default(_that.text,_that.loading,_that.complete,_that.terminal,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String text,  bool loading,  bool complete,  bool terminal,  Object? error)?  $default,) {final _that = this;
switch (_that) {
case _TimelineDetailState() when $default != null:
return $default(_that.text,_that.loading,_that.complete,_that.terminal,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineDetailState implements TimelineDetailState {
  const _TimelineDetailState({this.text = '', this.loading = false, this.complete = false, this.terminal = false, this.error});


@override@JsonKey() final  String text;
@override@JsonKey() final  bool loading;
@override@JsonKey() final  bool complete;
@override@JsonKey() final  bool terminal;
@override final  Object? error;

/// Create a copy of TimelineDetailState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineDetailStateCopyWith<_TimelineDetailState> get copyWith => __$TimelineDetailStateCopyWithImpl<_TimelineDetailState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineDetailState&&(identical(other.text, text) || other.text == text)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.complete, complete) || other.complete == complete)&&(identical(other.terminal, terminal) || other.terminal == terminal)&&const DeepCollectionEquality().equals(other.error, error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,loading,complete,terminal,const DeepCollectionEquality().hash(error));
}

@override
String toString() {
    return 'TimelineDetailState(text: $text, loading: $loading, complete: $complete, terminal: $terminal, error: $error)';
}


}

/// @nodoc
abstract mixin class _$TimelineDetailStateCopyWith<$Res> implements $TimelineDetailStateCopyWith<$Res> {
  factory _$TimelineDetailStateCopyWith(_TimelineDetailState value, $Res Function(_TimelineDetailState) _then) = __$TimelineDetailStateCopyWithImpl;
@override @useResult
$Res call({
 String text, bool loading, bool complete, bool terminal, Object? error
});




}
/// @nodoc
class __$TimelineDetailStateCopyWithImpl<$Res>
    implements _$TimelineDetailStateCopyWith<$Res> {
  __$TimelineDetailStateCopyWithImpl(this._self, this._then);

  final _TimelineDetailState _self;
  final $Res Function(_TimelineDetailState) _then;

/// Create a copy of TimelineDetailState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? loading = null,Object? complete = null,Object? terminal = null,Object? error = freezed,}) {
  return _then(_TimelineDetailState(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,terminal: null == terminal ? _self.terminal : terminal // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error ,
  ));
}


}

// dart format on
