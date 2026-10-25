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
mixin _$TimelineViewState {

 String get threadId; int get generation; TimelineDisplayMode get displayMode; TimelineConnectionPhase get connectionPhase; Object? get connectionError; String? get olderCursor; bool get hasOlder; bool get olderLoading;/// Diagnosis of the last failed older-page read. A canonical failure keeps
/// its typed projection; an unknown exception keeps the original object so
/// the identity and runtime type stay observable instead of being replaced
/// by a synthesized internal failure (design/26 §26.9).
 Object? get olderError; bool get hasNewOutput; bool get preparingLive; bool get ready;
/// Create a copy of TimelineViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineViewStateCopyWith<TimelineViewState> get copyWith => _$TimelineViewStateCopyWithImpl<TimelineViewState>(this as TimelineViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.generation, _this.generation) || other.generation == _this.generation)&&(identical(other.displayMode, _this.displayMode) || other.displayMode == _this.displayMode)&&(identical(other.connectionPhase, _this.connectionPhase) || other.connectionPhase == _this.connectionPhase)&&const DeepCollectionEquality().equals(other.connectionError, _this.connectionError)&&(identical(other.olderCursor, _this.olderCursor) || other.olderCursor == _this.olderCursor)&&(identical(other.hasOlder, _this.hasOlder) || other.hasOlder == _this.hasOlder)&&(identical(other.olderLoading, _this.olderLoading) || other.olderLoading == _this.olderLoading)&&const DeepCollectionEquality().equals(other.olderError, _this.olderError)&&(identical(other.hasNewOutput, _this.hasNewOutput) || other.hasNewOutput == _this.hasNewOutput)&&(identical(other.preparingLive, _this.preparingLive) || other.preparingLive == _this.preparingLive)&&(identical(other.ready, _this.ready) || other.ready == _this.ready));
}


@override
int get hashCode {
  final _this = this as TimelineViewState;
  return Object.hash(runtimeType,_this.threadId,_this.generation,_this.displayMode,_this.connectionPhase,const DeepCollectionEquality().hash(_this.connectionError),_this.olderCursor,_this.hasOlder,_this.olderLoading,const DeepCollectionEquality().hash(_this.olderError),_this.hasNewOutput,_this.preparingLive,_this.ready);
}



}

/// @nodoc
abstract mixin class $TimelineViewStateCopyWith<$Res>  {
  factory $TimelineViewStateCopyWith(TimelineViewState value, $Res Function(TimelineViewState) _then) = _$TimelineViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, int generation, TimelineDisplayMode displayMode, TimelineConnectionPhase connectionPhase, Object? connectionError, String? olderCursor, bool hasOlder, bool olderLoading, Object? olderError, bool hasNewOutput, bool preparingLive, bool ready
});




}
/// @nodoc
class _$TimelineViewStateCopyWithImpl<$Res>
    implements $TimelineViewStateCopyWith<$Res> {
  _$TimelineViewStateCopyWithImpl(this._self, this._then);

  final TimelineViewState _self;
  final $Res Function(TimelineViewState) _then;

/// Create a copy of TimelineViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? generation = null,Object? displayMode = null,Object? connectionPhase = null,Object? connectionError = freezed,Object? olderCursor = freezed,Object? hasOlder = null,Object? olderLoading = null,Object? olderError = freezed,Object? hasNewOutput = null,Object? preparingLive = null,Object? ready = null,}) {
  return _then(TimelineViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,displayMode: null == displayMode ? _self.displayMode : displayMode // ignore: cast_nullable_to_non_nullable
as TimelineDisplayMode,connectionPhase: null == connectionPhase ? _self.connectionPhase : connectionPhase // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,connectionError: freezed == connectionError ? _self.connectionError : connectionError ,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,olderLoading: null == olderLoading ? _self.olderLoading : olderLoading // ignore: cast_nullable_to_non_nullable
as bool,olderError: freezed == olderError ? _self.olderError : olderError ,hasNewOutput: null == hasNewOutput ? _self.hasNewOutput : hasNewOutput // ignore: cast_nullable_to_non_nullable
as bool,preparingLive: null == preparingLive ? _self.preparingLive : preparingLive // ignore: cast_nullable_to_non_nullable
as bool,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [TimelineViewState].
extension TimelineViewStatePatterns on TimelineViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TimelineViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TimelineViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TimelineViewState value)  $default,){
final _that = this;
switch (_that) {
case _TimelineViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TimelineViewState value)?  $default,){
final _that = this;
switch (_that) {
case _TimelineViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  int generation,  TimelineDisplayMode displayMode,  TimelineConnectionPhase connectionPhase,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool olderLoading,  Object? olderError,  bool hasNewOutput,  bool preparingLive,  bool ready)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TimelineViewState() when $default != null:
return $default(_that.threadId,_that.generation,_that.displayMode,_that.connectionPhase,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.olderLoading,_that.olderError,_that.hasNewOutput,_that.preparingLive,_that.ready);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  int generation,  TimelineDisplayMode displayMode,  TimelineConnectionPhase connectionPhase,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool olderLoading,  Object? olderError,  bool hasNewOutput,  bool preparingLive,  bool ready)  $default,) {final _that = this;
switch (_that) {
case _TimelineViewState():
return $default(_that.threadId,_that.generation,_that.displayMode,_that.connectionPhase,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.olderLoading,_that.olderError,_that.hasNewOutput,_that.preparingLive,_that.ready);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  int generation,  TimelineDisplayMode displayMode,  TimelineConnectionPhase connectionPhase,  Object? connectionError,  String? olderCursor,  bool hasOlder,  bool olderLoading,  Object? olderError,  bool hasNewOutput,  bool preparingLive,  bool ready)?  $default,) {final _that = this;
switch (_that) {
case _TimelineViewState() when $default != null:
return $default(_that.threadId,_that.generation,_that.displayMode,_that.connectionPhase,_that.connectionError,_that.olderCursor,_that.hasOlder,_that.olderLoading,_that.olderError,_that.hasNewOutput,_that.preparingLive,_that.ready);case _:
  return null;

}
}

}

/// @nodoc


class _TimelineViewState implements TimelineViewState {
  const _TimelineViewState({required this.threadId, this.generation = 0, this.displayMode = TimelineDisplayMode.live, this.connectionPhase = TimelineConnectionPhase.idle, this.connectionError, this.olderCursor, this.hasOlder = false, this.olderLoading = false, this.olderError, this.hasNewOutput = false, this.preparingLive = false, this.ready = false});


@override final  String threadId;
@override@JsonKey() final  int generation;
@override@JsonKey() final  TimelineDisplayMode displayMode;
@override@JsonKey() final  TimelineConnectionPhase connectionPhase;
@override final  Object? connectionError;
@override final  String? olderCursor;
@override@JsonKey() final  bool hasOlder;
@override@JsonKey() final  bool olderLoading;
/// Diagnosis of the last failed older-page read. A canonical failure keeps
/// its typed projection; an unknown exception keeps the original object so
/// the identity and runtime type stay observable instead of being replaced
/// by a synthesized internal failure (design/26 §26.9).
@override final  Object? olderError;
@override@JsonKey() final  bool hasNewOutput;
@override@JsonKey() final  bool preparingLive;
@override@JsonKey() final  bool ready;

/// Create a copy of TimelineViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TimelineViewStateCopyWith<_TimelineViewState> get copyWith => __$TimelineViewStateCopyWithImpl<_TimelineViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TimelineViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.generation, generation) || other.generation == generation)&&(identical(other.displayMode, displayMode) || other.displayMode == displayMode)&&(identical(other.connectionPhase, connectionPhase) || other.connectionPhase == connectionPhase)&&const DeepCollectionEquality().equals(other.connectionError, connectionError)&&(identical(other.olderCursor, olderCursor) || other.olderCursor == olderCursor)&&(identical(other.hasOlder, hasOlder) || other.hasOlder == hasOlder)&&(identical(other.olderLoading, olderLoading) || other.olderLoading == olderLoading)&&const DeepCollectionEquality().equals(other.olderError, olderError)&&(identical(other.hasNewOutput, hasNewOutput) || other.hasNewOutput == hasNewOutput)&&(identical(other.preparingLive, preparingLive) || other.preparingLive == preparingLive)&&(identical(other.ready, ready) || other.ready == ready));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,generation,displayMode,connectionPhase,const DeepCollectionEquality().hash(connectionError),olderCursor,hasOlder,olderLoading,const DeepCollectionEquality().hash(olderError),hasNewOutput,preparingLive,ready);
}



}

/// @nodoc
abstract mixin class _$TimelineViewStateCopyWith<$Res> implements $TimelineViewStateCopyWith<$Res> {
  factory _$TimelineViewStateCopyWith(_TimelineViewState value, $Res Function(_TimelineViewState) _then) = __$TimelineViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, int generation, TimelineDisplayMode displayMode, TimelineConnectionPhase connectionPhase, Object? connectionError, String? olderCursor, bool hasOlder, bool olderLoading, Object? olderError, bool hasNewOutput, bool preparingLive, bool ready
});




}
/// @nodoc
class __$TimelineViewStateCopyWithImpl<$Res>
    implements _$TimelineViewStateCopyWith<$Res> {
  __$TimelineViewStateCopyWithImpl(this._self, this._then);

  final _TimelineViewState _self;
  final $Res Function(_TimelineViewState) _then;

/// Create a copy of TimelineViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? generation = null,Object? displayMode = null,Object? connectionPhase = null,Object? connectionError = freezed,Object? olderCursor = freezed,Object? hasOlder = null,Object? olderLoading = null,Object? olderError = freezed,Object? hasNewOutput = null,Object? preparingLive = null,Object? ready = null,}) {
  return _then(_TimelineViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,generation: null == generation ? _self.generation : generation // ignore: cast_nullable_to_non_nullable
as int,displayMode: null == displayMode ? _self.displayMode : displayMode // ignore: cast_nullable_to_non_nullable
as TimelineDisplayMode,connectionPhase: null == connectionPhase ? _self.connectionPhase : connectionPhase // ignore: cast_nullable_to_non_nullable
as TimelineConnectionPhase,connectionError: freezed == connectionError ? _self.connectionError : connectionError ,olderCursor: freezed == olderCursor ? _self.olderCursor : olderCursor // ignore: cast_nullable_to_non_nullable
as String?,hasOlder: null == hasOlder ? _self.hasOlder : hasOlder // ignore: cast_nullable_to_non_nullable
as bool,olderLoading: null == olderLoading ? _self.olderLoading : olderLoading // ignore: cast_nullable_to_non_nullable
as bool,olderError: freezed == olderError ? _self.olderError : olderError ,hasNewOutput: null == hasNewOutput ? _self.hasNewOutput : hasNewOutput // ignore: cast_nullable_to_non_nullable
as bool,preparingLive: null == preparingLive ? _self.preparingLive : preparingLive // ignore: cast_nullable_to_non_nullable
as bool,ready: null == ready ? _self.ready : ready // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
