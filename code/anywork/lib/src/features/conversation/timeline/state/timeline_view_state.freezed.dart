// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'timeline_view_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$TimelineSessionViewState {

 String get threadId; int get generation; TimelineDisplayMode get mode; TimelineConnectionPhase get connection; Object? get connectionError; String? get olderCursor; bool get hasOlder; bool get isLoadingOlder; Object? get olderError; bool get hasNewOutput;
/// Create a copy of TimelineSessionViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineSessionViewStateCopyWith<TimelineSessionViewState> get copyWith => _$TimelineSessionViewStateCopyWithImpl<TimelineSessionViewState>(this as TimelineSessionViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineSessionViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineSessionViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&const DeepCollectionEquality().equals(other.connectionError, _this.connectionError)&&(identical(other.olderCursor, _this.olderCursor) || other.olderCursor == _this.olderCursor)&&(identical(other.hasOlder, _this.hasOlder) || other.hasOlder == _this.hasOlder)&&(identical(other.isLoadingOlder, _this.isLoadingOlder) || other.isLoadingOlder == _this.isLoadingOlder)&&const DeepCollectionEquality().equals(other.olderError, _this.olderError)&&(identical(other.hasNewOutput, _this.hasNewOutput) || other.hasNewOutput == _this.hasNewOutput));
}


@override
int get hashCode {
  final _this = this as TimelineSessionViewState;
  return Object.hash(runtimeType,_this.threadId,_this.generation,_this.mode,_this.connection,const DeepCollectionEquality().hash(_this.connectionError),_this.olderCursor,_this.hasOlder,_this.isLoadingOlder,const DeepCollectionEquality().hash(_this.olderError),_this.hasNewOutput);
}

@override
String toString() {
  final _this = this as TimelineSessionViewState;
  return 'TimelineSessionViewState(threadId: ${_this.threadId}, generation: ${_this.generation}, mode: ${_this.mode}, connection: ${_this.connection}, connectionError: ${_this.connectionError}, olderCursor: ${_this.olderCursor}, hasOlder: ${_this.hasOlder}, isLoadingOlder: ${_this.isLoadingOlder}, olderError: ${_this.olderError}, hasNewOutput: ${_this.hasNewOutput})';
}


}

/// @nodoc
abstract mixin class $TimelineSessionViewStateCopyWith<$Res>  {
  factory $TimelineSessionViewStateCopyWith(TimelineSessionViewState value, $Res Function(TimelineSessionViewState) _then) = _$TimelineSessionViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, int generation, TimelineDisplayMode mode, TimelineConnectionPhase connection, Object? connectionError, String? olderCursor, bool hasOlder, bool isLoadingOlder, Object? olderError, bool hasNewOutput
});




}
/// @nodoc
class _$TimelineSessionViewStateCopyWithImpl<$Res>
    implements $TimelineSessionViewStateCopyWith<$Res> {
  _$TimelineSessionViewStateCopyWithImpl(this._self, this._then);

  final TimelineSessionViewState _self;
  final $Res Function(TimelineSessionViewState) _then;

/// Create a copy of TimelineSessionViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? generation = null,Object? mode = null,Object? connection = null,Object? connectionError = freezed,Object? olderCursor = freezed,Object? hasOlder = null,Object? isLoadingOlder = null,Object? olderError = freezed,Object? hasNewOutput = null,}) {
  return _then(TimelineSessionViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as TimelineDisplayMode,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,connectionError: freezed == connectionError ? _self.connectionError : connectionError ,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,isLoadingOlder: null == isLoadingOlder ? _self.isLoadingOlder : isLoadingOlder // ignore: cast_nullable_to_non_nullable
as bool,olderError: freezed == olderError ? _self.olderError : olderError ,hasNewOutput: null == hasNewOutput ? _self.hasNewOutput : hasNewOutput // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TimelineSessionViewState].
extension TimelineSessionViewStatePatterns on TimelineSessionViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineSessionViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineSessionViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineSessionViewState value)  $default,){
final _that = this;
switch (_that) {
case _TimelineSessionViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineSessionViewState value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineSessionViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int generation,  TimelineDisplayMode mode,  TimelineConnectionPhase connection,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool isLoadingOlder,  Object? olderError,  bool hasNewOutput)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineSessionViewState() when $default != null:
return $default(_that.threadId,_that.generation,_that.mode,_that.connection,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.isLoadingOlder,_that.olderError,_that.hasNewOutput);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int generation,  TimelineDisplayMode mode,  TimelineConnectionPhase connection,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool isLoadingOlder,  Object? olderError,  bool hasNewOutput)  $default,) {final _that = this;
switch (_that) {
case _TimelineSessionViewState():
return $default(_that.threadId,_that.generation,_that.mode,_that.connection,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.isLoadingOlder,_that.olderError,_that.hasNewOutput);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int generation,  TimelineDisplayMode mode,  TimelineConnectionPhase connection,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool isLoadingOlder,  Object? olderError,  bool hasNewOutput)?  $default,) {final _that = this;
switch (_that) {
case _TimelineSessionViewState() when $default != null:
return $default(_that.threadId,_that.generation,_that.mode,_that.connection,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.isLoadingOlder,_that.olderError,_that.hasNewOutput);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineSessionViewState implements TimelineSessionViewState {
  const _TimelineSessionViewState({required this.threadId, required this.generation, required this.mode, required this.connection, this.connectionError, this.olderCursor, this.hasOlder = false, this.isLoadingOlder = false, this.olderError, this.hasNewOutput = false});


@override final  String threadId;
@override final  int generation;
@override final  TimelineDisplayMode mode;
@override final  TimelineConnectionPhase connection;
@override final  Object? connectionError;
@override final  String? olderCursor;
@override@JsonKey() final  bool hasOlder;
@override@JsonKey() final  bool isLoadingOlder;
@override final  Object? olderError;
@override@JsonKey() final  bool hasNewOutput;

/// Create a copy of TimelineSessionViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineSessionViewStateCopyWith<_TimelineSessionViewState> get copyWith => __$TimelineSessionViewStateCopyWithImpl<_TimelineSessionViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineSessionViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.mode, mode) || other.mode == mode)&&(identical(other.connection, connection) || other.connection == connection)&&const DeepCollectionEquality().equals(other.connectionError, connectionError)&&(identical(other.olderCursor, olderCursor) || other.olderCursor == olderCursor)&&(identical(other.hasOlder, hasOlder) || other.hasOlder == hasOlder)&&(identical(other.isLoadingOlder, isLoadingOlder) || other.isLoadingOlder == isLoadingOlder)&&const DeepCollectionEquality().equals(other.olderError, olderError)&&(identical(other.hasNewOutput, hasNewOutput) || other.hasNewOutput == hasNewOutput));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,generation,mode,connection,const DeepCollectionEquality().hash(connectionError),olderCursor,hasOlder,isLoadingOlder,const DeepCollectionEquality().hash(olderError),hasNewOutput);
}

@override
String toString() {
    return 'TimelineSessionViewState(threadId: $threadId, generation: $generation, mode: $mode, connection: $connection, connectionError: $connectionError, olderCursor: $olderCursor, hasOlder: $hasOlder, isLoadingOlder: $isLoadingOlder, olderError: $olderError, hasNewOutput: $hasNewOutput)';
}


}

/// @nodoc
abstract mixin class _$TimelineSessionViewStateCopyWith<$Res> implements $TimelineSessionViewStateCopyWith<$Res> {
  factory _$TimelineSessionViewStateCopyWith(_TimelineSessionViewState value, $Res Function(_TimelineSessionViewState) _then) = __$TimelineSessionViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int generation, TimelineDisplayMode mode, TimelineConnectionPhase connection, Object? connectionError, String? olderCursor, bool hasOlder, bool isLoadingOlder, Object? olderError, bool hasNewOutput
});




}
/// @nodoc
class __$TimelineSessionViewStateCopyWithImpl<$Res>
    implements _$TimelineSessionViewStateCopyWith<$Res> {
  __$TimelineSessionViewStateCopyWithImpl(this._self, this._then);

  final _TimelineSessionViewState _self;
  final $Res Function(_TimelineSessionViewState) _then;

/// Create a copy of TimelineSessionViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? generation = null,Object? mode = null,Object? connection = null,Object? connectionError = freezed,Object? olderCursor = freezed,Object? hasOlder = null,Object? isLoadingOlder = null,Object? olderError = freezed,Object? hasNewOutput = null,}) {
  return _then(_TimelineSessionViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as TimelineDisplayMode,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,connectionError: freezed == connectionError ? _self.connectionError : connectionError ,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,isLoadingOlder: null == isLoadingOlder ? _self.isLoadingOlder : isLoadingOlder // ignore: cast_nullable_to_non_nullable
as bool,olderError: freezed == olderError ? _self.olderError : olderError ,hasNewOutput: null == hasNewOutput ? _self.hasNewOutput : hasNewOutput // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
