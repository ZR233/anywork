// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'conversation_activation_failure.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ConversationActivationFailure {

 String get threadId; int get selectionGeneration; StudioFailure get error;
/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConversationActivationFailureCopyWith<ConversationActivationFailure> get copyWith => _$ConversationActivationFailureCopyWithImpl<ConversationActivationFailure>(this as ConversationActivationFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConversationActivationFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationActivationFailure&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.selectionGeneration, _this.selectionGeneration) || other.selectionGeneration == _this.selectionGeneration)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ConversationActivationFailure;
  return Object.hash(runtimeType,_this.threadId,_this.selectionGeneration,_this.error);
}



}

/// @nodoc
abstract mixin class $ConversationActivationFailureCopyWith<$Res>  {
  factory $ConversationActivationFailureCopyWith(ConversationActivationFailure value, $Res Function(ConversationActivationFailure) _then) = _$ConversationActivationFailureCopyWithImpl;
@useResult
$Res call({
 String threadId, int selectionGeneration, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ConversationActivationFailureCopyWithImpl<$Res>
    implements $ConversationActivationFailureCopyWith<$Res> {
  _$ConversationActivationFailureCopyWithImpl(this._self, this._then);

  final ConversationActivationFailure _self;
  final $Res Function(ConversationActivationFailure) _then;

/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? selectionGeneration = null,Object? error = null,}) {
  return _then(ConversationActivationFailure(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,selectionGeneration: null == selectionGeneration ? _self.selectionGeneration : selectionGeneration // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}
/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConversationActivationFailure].
extension ConversationActivationFailurePatterns on ConversationActivationFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConversationActivationFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConversationActivationFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConversationActivationFailure value)  $default,){
final _that = this;
switch (_that) {
case _ConversationActivationFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConversationActivationFailure value)?  $default,){
final _that = this;
switch (_that) {
case _ConversationActivationFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int selectionGeneration,  StudioFailure error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConversationActivationFailure() when $default != null:
return $default(_that.threadId,_that.selectionGeneration,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int selectionGeneration,  StudioFailure error)  $default,) {final _that = this;
switch (_that) {
case _ConversationActivationFailure():
return $default(_that.threadId,_that.selectionGeneration,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int selectionGeneration,  StudioFailure error)?  $default,) {final _that = this;
switch (_that) {
case _ConversationActivationFailure() when $default != null:
return $default(_that.threadId,_that.selectionGeneration,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ConversationActivationFailure implements ConversationActivationFailure {
  const _ConversationActivationFailure({required this.threadId, required this.selectionGeneration, required this.error});


@override final  String threadId;
@override final  int selectionGeneration;
@override final  StudioFailure error;

/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConversationActivationFailureCopyWith<_ConversationActivationFailure> get copyWith => __$ConversationActivationFailureCopyWithImpl<_ConversationActivationFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConversationActivationFailure&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.selectionGeneration, selectionGeneration) || other.selectionGeneration == selectionGeneration)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,selectionGeneration,error);
}



}

/// @nodoc
abstract mixin class _$ConversationActivationFailureCopyWith<$Res> implements $ConversationActivationFailureCopyWith<$Res> {
  factory _$ConversationActivationFailureCopyWith(_ConversationActivationFailure value, $Res Function(_ConversationActivationFailure) _then) = __$ConversationActivationFailureCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int selectionGeneration, StudioFailure error
});


@override $StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class __$ConversationActivationFailureCopyWithImpl<$Res>
    implements _$ConversationActivationFailureCopyWith<$Res> {
  __$ConversationActivationFailureCopyWithImpl(this._self, this._then);

  final _ConversationActivationFailure _self;
  final $Res Function(_ConversationActivationFailure) _then;

/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? selectionGeneration = null,Object? error = null,}) {
  return _then(_ConversationActivationFailure(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,selectionGeneration: null == selectionGeneration ? _self.selectionGeneration : selectionGeneration // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ConversationActivationFailure
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
