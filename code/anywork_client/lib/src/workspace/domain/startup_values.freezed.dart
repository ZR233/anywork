// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartupPhase {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupPhase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StartupPhase()';
}


}

/// @nodoc
class $StartupPhaseCopyWith<$Res>  {
$StartupPhaseCopyWith(StartupPhase _, $Res Function(StartupPhase) __);
}


/// Adds pattern-matching-related methods to [StartupPhase].
extension StartupPhasePatterns on StartupPhase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LoadingLibraryStartupPhase value)?  loadingLibrary,TResult Function( PreparingAttemptStartupPhase value)?  preparingAttempt,TResult Function( NativeStartupPhase value)?  native,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase() when loadingLibrary != null:
return loadingLibrary(_that);case PreparingAttemptStartupPhase() when preparingAttempt != null:
return preparingAttempt(_that);case NativeStartupPhase() when native != null:
return native(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LoadingLibraryStartupPhase value)  loadingLibrary,required TResult Function( PreparingAttemptStartupPhase value)  preparingAttempt,required TResult Function( NativeStartupPhase value)  native,}){
final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase():
return loadingLibrary(_that);case PreparingAttemptStartupPhase():
return preparingAttempt(_that);case NativeStartupPhase():
return native(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LoadingLibraryStartupPhase value)?  loadingLibrary,TResult? Function( PreparingAttemptStartupPhase value)?  preparingAttempt,TResult? Function( NativeStartupPhase value)?  native,}){
final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase() when loadingLibrary != null:
return loadingLibrary(_that);case PreparingAttemptStartupPhase() when preparingAttempt != null:
return preparingAttempt(_that);case NativeStartupPhase() when native != null:
return native(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  loadingLibrary,TResult Function()?  preparingAttempt,TResult Function( StartupStage stage)?  native,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase() when loadingLibrary != null:
return loadingLibrary();case PreparingAttemptStartupPhase() when preparingAttempt != null:
return preparingAttempt();case NativeStartupPhase() when native != null:
return native(_that.stage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  loadingLibrary,required TResult Function()  preparingAttempt,required TResult Function( StartupStage stage)  native,}) {final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase():
return loadingLibrary();case PreparingAttemptStartupPhase():
return preparingAttempt();case NativeStartupPhase():
return native(_that.stage);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  loadingLibrary,TResult? Function()?  preparingAttempt,TResult? Function( StartupStage stage)?  native,}) {final _that = this;
switch (_that) {
case LoadingLibraryStartupPhase() when loadingLibrary != null:
return loadingLibrary();case PreparingAttemptStartupPhase() when preparingAttempt != null:
return preparingAttempt();case NativeStartupPhase() when native != null:
return native(_that.stage);case _:
  return null;

}
}

}

/// @nodoc


class LoadingLibraryStartupPhase implements StartupPhase {
  const LoadingLibraryStartupPhase();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingLibraryStartupPhase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StartupPhase.loadingLibrary()';
}


}




/// @nodoc


class PreparingAttemptStartupPhase implements StartupPhase {
  const PreparingAttemptStartupPhase();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PreparingAttemptStartupPhase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'StartupPhase.preparingAttempt()';
}


}




/// @nodoc


class NativeStartupPhase implements StartupPhase {
  const NativeStartupPhase({required this.stage});


 final  StartupStage stage;

/// Create a copy of StartupPhase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeStartupPhaseCopyWith<NativeStartupPhase> get copyWith => _$NativeStartupPhaseCopyWithImpl<NativeStartupPhase>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeStartupPhase&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stage);
}

@override
String toString() {
    return 'StartupPhase.native(stage: $stage)';
}


}

/// @nodoc
abstract mixin class $NativeStartupPhaseCopyWith<$Res> implements $StartupPhaseCopyWith<$Res> {
  factory $NativeStartupPhaseCopyWith(NativeStartupPhase value, $Res Function(NativeStartupPhase) _then) = _$NativeStartupPhaseCopyWithImpl;
@useResult
$Res call({
 StartupStage stage
});




}
/// @nodoc
class _$NativeStartupPhaseCopyWithImpl<$Res>
    implements $NativeStartupPhaseCopyWith<$Res> {
  _$NativeStartupPhaseCopyWithImpl(this._self, this._then);

  final NativeStartupPhase _self;
  final $Res Function(NativeStartupPhase) _then;

/// Create a copy of StartupPhase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? stage = null,}) {
  return _then(NativeStartupPhase(
stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as StartupStage,
  ));
}


}

/// @nodoc
mixin _$StartupState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StartupStateCopyWith<$Res>  {
$StartupStateCopyWith(StartupState _, $Res Function(StartupState) __);
}


/// Adds pattern-matching-related methods to [StartupState].
extension StartupStatePatterns on StartupState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleStartupState value)?  idle,TResult Function( StartingStartupState value)?  starting,TResult Function( ReadyStartupState value)?  ready,TResult Function( FailedStartupState value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleStartupState() when idle != null:
return idle(_that);case StartingStartupState() when starting != null:
return starting(_that);case ReadyStartupState() when ready != null:
return ready(_that);case FailedStartupState() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleStartupState value)  idle,required TResult Function( StartingStartupState value)  starting,required TResult Function( ReadyStartupState value)  ready,required TResult Function( FailedStartupState value)  failed,}){
final _that = this;
switch (_that) {
case IdleStartupState():
return idle(_that);case StartingStartupState():
return starting(_that);case ReadyStartupState():
return ready(_that);case FailedStartupState():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleStartupState value)?  idle,TResult? Function( StartingStartupState value)?  starting,TResult? Function( ReadyStartupState value)?  ready,TResult? Function( FailedStartupState value)?  failed,}){
final _that = this;
switch (_that) {
case IdleStartupState() when idle != null:
return idle(_that);case StartingStartupState() when starting != null:
return starting(_that);case ReadyStartupState() when ready != null:
return ready(_that);case FailedStartupState() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( int? attemptId,  StartupPhase phase)?  starting,TResult Function( int attemptId,  RuntimeReady result)?  ready,TResult Function( int? attemptId,  StudioFailure error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleStartupState() when idle != null:
return idle();case StartingStartupState() when starting != null:
return starting(_that.attemptId,_that.phase);case ReadyStartupState() when ready != null:
return ready(_that.attemptId,_that.result);case FailedStartupState() when failed != null:
return failed(_that.attemptId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( int? attemptId,  StartupPhase phase)  starting,required TResult Function( int attemptId,  RuntimeReady result)  ready,required TResult Function( int? attemptId,  StudioFailure error)  failed,}) {final _that = this;
switch (_that) {
case IdleStartupState():
return idle();case StartingStartupState():
return starting(_that.attemptId,_that.phase);case ReadyStartupState():
return ready(_that.attemptId,_that.result);case FailedStartupState():
return failed(_that.attemptId,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( int? attemptId,  StartupPhase phase)?  starting,TResult? Function( int attemptId,  RuntimeReady result)?  ready,TResult? Function( int? attemptId,  StudioFailure error)?  failed,}) {final _that = this;
switch (_that) {
case IdleStartupState() when idle != null:
return idle();case StartingStartupState() when starting != null:
return starting(_that.attemptId,_that.phase);case ReadyStartupState() when ready != null:
return ready(_that.attemptId,_that.result);case FailedStartupState() when failed != null:
return failed(_that.attemptId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class IdleStartupState implements StartupState {
  const IdleStartupState();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleStartupState);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class StartingStartupState implements StartupState {
  const StartingStartupState({required this.attemptId, required this.phase});


 final  int? attemptId;
 final  StartupPhase phase;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartingStartupStateCopyWith<StartingStartupState> get copyWith => _$StartingStartupStateCopyWithImpl<StartingStartupState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartingStartupState&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.phase, phase) || other.phase == phase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,phase);
}



}

/// @nodoc
abstract mixin class $StartingStartupStateCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $StartingStartupStateCopyWith(StartingStartupState value, $Res Function(StartingStartupState) _then) = _$StartingStartupStateCopyWithImpl;
@useResult
$Res call({
 int? attemptId, StartupPhase phase
});


$StartupPhaseCopyWith<$Res> get phase;

}
/// @nodoc
class _$StartingStartupStateCopyWithImpl<$Res>
    implements $StartingStartupStateCopyWith<$Res> {
  _$StartingStartupStateCopyWithImpl(this._self, this._then);

  final StartingStartupState _self;
  final $Res Function(StartingStartupState) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = freezed,Object? phase = null,}) {
  return _then(StartingStartupState(
attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as int?,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as StartupPhase,
  ));
}

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupPhaseCopyWith<$Res> get phase {

  return $StartupPhaseCopyWith<$Res>(_self.phase, (value) {
    return _then(_self.copyWith(phase: value));
  });
}
}

/// @nodoc


class ReadyStartupState implements StartupState {
  const ReadyStartupState({required this.attemptId, required this.result});


 final  int attemptId;
 final  RuntimeReady result;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyStartupStateCopyWith<ReadyStartupState> get copyWith => _$ReadyStartupStateCopyWithImpl<ReadyStartupState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyStartupState&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.result, result) || other.result == result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,result);
}



}

/// @nodoc
abstract mixin class $ReadyStartupStateCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $ReadyStartupStateCopyWith(ReadyStartupState value, $Res Function(ReadyStartupState) _then) = _$ReadyStartupStateCopyWithImpl;
@useResult
$Res call({
 int attemptId, RuntimeReady result
});


$RuntimeReadyCopyWith<$Res> get result;

}
/// @nodoc
class _$ReadyStartupStateCopyWithImpl<$Res>
    implements $ReadyStartupStateCopyWith<$Res> {
  _$ReadyStartupStateCopyWithImpl(this._self, this._then);

  final ReadyStartupState _self;
  final $Res Function(ReadyStartupState) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? result = null,}) {
  return _then(ReadyStartupState(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as int,result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as RuntimeReady,
  ));
}

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeReadyCopyWith<$Res> get result {

  return $RuntimeReadyCopyWith<$Res>(_self.result, (value) {
    return _then(_self.copyWith(result: value));
  });
}
}

/// @nodoc


class FailedStartupState implements StartupState {
  const FailedStartupState({required this.attemptId, required this.error});


 final  int? attemptId;
 final  StudioFailure error;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedStartupStateCopyWith<FailedStartupState> get copyWith => _$FailedStartupStateCopyWithImpl<FailedStartupState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedStartupState&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,error);
}



}

/// @nodoc
abstract mixin class $FailedStartupStateCopyWith<$Res> implements $StartupStateCopyWith<$Res> {
  factory $FailedStartupStateCopyWith(FailedStartupState value, $Res Function(FailedStartupState) _then) = _$FailedStartupStateCopyWithImpl;
@useResult
$Res call({
 int? attemptId, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedStartupStateCopyWithImpl<$Res>
    implements $FailedStartupStateCopyWith<$Res> {
  _$FailedStartupStateCopyWithImpl(this._self, this._then);

  final FailedStartupState _self;
  final $Res Function(FailedStartupState) _then;

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = freezed,Object? error = null,}) {
  return _then(FailedStartupState(
attemptId: freezed == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as int?,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of StartupState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$RuntimeStartupReadRef {

 int get entry; int get revision;
/// Create a copy of RuntimeStartupReadRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<RuntimeStartupReadRef> get copyWith => _$RuntimeStartupReadRefCopyWithImpl<RuntimeStartupReadRef>(this as RuntimeStartupReadRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeStartupReadRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStartupReadRef&&(identical(other.entry, _this.entry) || other.entry == _this.entry)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as RuntimeStartupReadRef;
  return Object.hash(runtimeType,_this.entry,_this.revision);
}

@override
String toString() {
  final _this = this as RuntimeStartupReadRef;
  return 'RuntimeStartupReadRef(entry: ${_this.entry}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $RuntimeStartupReadRefCopyWith<$Res>  {
  factory $RuntimeStartupReadRefCopyWith(RuntimeStartupReadRef value, $Res Function(RuntimeStartupReadRef) _then) = _$RuntimeStartupReadRefCopyWithImpl;
@useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class _$RuntimeStartupReadRefCopyWithImpl<$Res>
    implements $RuntimeStartupReadRefCopyWith<$Res> {
  _$RuntimeStartupReadRefCopyWithImpl(this._self, this._then);

  final RuntimeStartupReadRef _self;
  final $Res Function(RuntimeStartupReadRef) _then;

/// Create a copy of RuntimeStartupReadRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(RuntimeStartupReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeStartupReadRef].
extension RuntimeStartupReadRefPatterns on RuntimeStartupReadRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeStartupReadRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeStartupReadRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeStartupReadRef value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupReadRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeStartupReadRef value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupReadRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int entry,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeStartupReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int entry,  int revision)  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupReadRef():
return $default(_that.entry,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int entry,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupReadRef() when $default != null:
return $default(_that.entry,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeStartupReadRef implements RuntimeStartupReadRef {
  const _RuntimeStartupReadRef({required this.entry, required this.revision});


@override final  int entry;
@override final  int revision;

/// Create a copy of RuntimeStartupReadRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeStartupReadRefCopyWith<_RuntimeStartupReadRef> get copyWith => __$RuntimeStartupReadRefCopyWithImpl<_RuntimeStartupReadRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeStartupReadRef&&(identical(other.entry, entry) || other.entry == entry)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,entry,revision);
}

@override
String toString() {
    return 'RuntimeStartupReadRef(entry: $entry, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$RuntimeStartupReadRefCopyWith<$Res> implements $RuntimeStartupReadRefCopyWith<$Res> {
  factory _$RuntimeStartupReadRefCopyWith(_RuntimeStartupReadRef value, $Res Function(_RuntimeStartupReadRef) _then) = __$RuntimeStartupReadRefCopyWithImpl;
@override @useResult
$Res call({
 int entry, int revision
});




}
/// @nodoc
class __$RuntimeStartupReadRefCopyWithImpl<$Res>
    implements _$RuntimeStartupReadRefCopyWith<$Res> {
  __$RuntimeStartupReadRefCopyWithImpl(this._self, this._then);

  final _RuntimeStartupReadRef _self;
  final $Res Function(_RuntimeStartupReadRef) _then;

/// Create a copy of RuntimeStartupReadRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? entry = null,Object? revision = null,}) {
  return _then(_RuntimeStartupReadRef(
entry: null == entry ? _self.entry : entry // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RuntimeReady {

 int get revision; int get readyAt; RuntimeStartupReadRef get details;
/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeReadyCopyWith<RuntimeReady> get copyWith => _$RuntimeReadyCopyWithImpl<RuntimeReady>(this as RuntimeReady, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeReady;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeReady&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.readyAt, _this.readyAt) || other.readyAt == _this.readyAt)&&(identical(other.details, _this.details) || other.details == _this.details));
}


@override
int get hashCode {
  final _this = this as RuntimeReady;
  return Object.hash(runtimeType,_this.revision,_this.readyAt,_this.details);
}

@override
String toString() {
  final _this = this as RuntimeReady;
  return 'RuntimeReady(revision: ${_this.revision}, readyAt: ${_this.readyAt}, details: ${_this.details})';
}


}

/// @nodoc
abstract mixin class $RuntimeReadyCopyWith<$Res>  {
  factory $RuntimeReadyCopyWith(RuntimeReady value, $Res Function(RuntimeReady) _then) = _$RuntimeReadyCopyWithImpl;
@useResult
$Res call({
 int revision, int readyAt, RuntimeStartupReadRef details
});


$RuntimeStartupReadRefCopyWith<$Res> get details;

}
/// @nodoc
class _$RuntimeReadyCopyWithImpl<$Res>
    implements $RuntimeReadyCopyWith<$Res> {
  _$RuntimeReadyCopyWithImpl(this._self, this._then);

  final RuntimeReady _self;
  final $Res Function(RuntimeReady) _then;

/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? readyAt = null,Object? details = null,}) {
  return _then(RuntimeReady(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,
  ));
}
/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get details {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}


/// Adds pattern-matching-related methods to [RuntimeReady].
extension RuntimeReadyPatterns on RuntimeReady {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeReady value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeReady() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeReady value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeReady():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeReady value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeReady() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int readyAt,  RuntimeStartupReadRef details)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeReady() when $default != null:
return $default(_that.revision,_that.readyAt,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int readyAt,  RuntimeStartupReadRef details)  $default,) {final _that = this;
switch (_that) {
case _RuntimeReady():
return $default(_that.revision,_that.readyAt,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int readyAt,  RuntimeStartupReadRef details)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeReady() when $default != null:
return $default(_that.revision,_that.readyAt,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeReady implements RuntimeReady {
  const _RuntimeReady({required this.revision, required this.readyAt, required this.details});


@override final  int revision;
@override final  int readyAt;
@override final  RuntimeStartupReadRef details;

/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeReadyCopyWith<_RuntimeReady> get copyWith => __$RuntimeReadyCopyWithImpl<_RuntimeReady>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeReady&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt)&&(identical(other.details, details) || other.details == details));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt,details);
}

@override
String toString() {
    return 'RuntimeReady(revision: $revision, readyAt: $readyAt, details: $details)';
}


}

/// @nodoc
abstract mixin class _$RuntimeReadyCopyWith<$Res> implements $RuntimeReadyCopyWith<$Res> {
  factory _$RuntimeReadyCopyWith(_RuntimeReady value, $Res Function(_RuntimeReady) _then) = __$RuntimeReadyCopyWithImpl;
@override @useResult
$Res call({
 int revision, int readyAt, RuntimeStartupReadRef details
});


@override $RuntimeStartupReadRefCopyWith<$Res> get details;

}
/// @nodoc
class __$RuntimeReadyCopyWithImpl<$Res>
    implements _$RuntimeReadyCopyWith<$Res> {
  __$RuntimeReadyCopyWithImpl(this._self, this._then);

  final _RuntimeReady _self;
  final $Res Function(_RuntimeReady) _then;

/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,Object? details = null,}) {
  return _then(_RuntimeReady(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,details: null == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,
  ));
}

/// Create a copy of RuntimeReady
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get details {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.details, (value) {
    return _then(_self.copyWith(details: value));
  });
}
}

/// @nodoc
mixin _$StartupRecovery {

 String get backupPath; String get reason; int get createdAt;
/// Create a copy of StartupRecovery
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupRecoveryCopyWith<StartupRecovery> get copyWith => _$StartupRecoveryCopyWithImpl<StartupRecovery>(this as StartupRecovery, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupRecovery;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupRecovery&&(identical(other.backupPath, _this.backupPath) || other.backupPath == _this.backupPath)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as StartupRecovery;
  return Object.hash(runtimeType,_this.backupPath,_this.reason,_this.createdAt);
}



}

/// @nodoc
abstract mixin class $StartupRecoveryCopyWith<$Res>  {
  factory $StartupRecoveryCopyWith(StartupRecovery value, $Res Function(StartupRecovery) _then) = _$StartupRecoveryCopyWithImpl;
@useResult
$Res call({
 String backupPath, String reason, int createdAt
});




}
/// @nodoc
class _$StartupRecoveryCopyWithImpl<$Res>
    implements $StartupRecoveryCopyWith<$Res> {
  _$StartupRecoveryCopyWithImpl(this._self, this._then);

  final StartupRecovery _self;
  final $Res Function(StartupRecovery) _then;

/// Create a copy of StartupRecovery
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? backupPath = null,Object? reason = null,Object? createdAt = null,}) {
  return _then(StartupRecovery(
backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [StartupRecovery].
extension StartupRecoveryPatterns on StartupRecovery {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupRecovery value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupRecovery() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupRecovery value)  $default,){
final _that = this;
switch (_that) {
case _StartupRecovery():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupRecovery value)?  $default,){
final _that = this;
switch (_that) {
case _StartupRecovery() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String backupPath,  String reason,  int createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupRecovery() when $default != null:
return $default(_that.backupPath,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String backupPath,  String reason,  int createdAt)  $default,) {final _that = this;
switch (_that) {
case _StartupRecovery():
return $default(_that.backupPath,_that.reason,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String backupPath,  String reason,  int createdAt)?  $default,) {final _that = this;
switch (_that) {
case _StartupRecovery() when $default != null:
return $default(_that.backupPath,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _StartupRecovery implements StartupRecovery {
  const _StartupRecovery({required this.backupPath, required this.reason, required this.createdAt});


@override final  String backupPath;
@override final  String reason;
@override final  int createdAt;

/// Create a copy of StartupRecovery
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupRecoveryCopyWith<_StartupRecovery> get copyWith => __$StartupRecoveryCopyWithImpl<_StartupRecovery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupRecovery&&(identical(other.backupPath, backupPath) || other.backupPath == backupPath)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,backupPath,reason,createdAt);
}



}

/// @nodoc
abstract mixin class _$StartupRecoveryCopyWith<$Res> implements $StartupRecoveryCopyWith<$Res> {
  factory _$StartupRecoveryCopyWith(_StartupRecovery value, $Res Function(_StartupRecovery) _then) = __$StartupRecoveryCopyWithImpl;
@override @useResult
$Res call({
 String backupPath, String reason, int createdAt
});




}
/// @nodoc
class __$StartupRecoveryCopyWithImpl<$Res>
    implements _$StartupRecoveryCopyWith<$Res> {
  __$StartupRecoveryCopyWithImpl(this._self, this._then);

  final _StartupRecovery _self;
  final $Res Function(_StartupRecovery) _then;

/// Create a copy of StartupRecovery
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? backupPath = null,Object? reason = null,Object? createdAt = null,}) {
  return _then(_StartupRecovery(
backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as String,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$StartupActiveTurn {

 String get threadId; String get turnId;
/// Create a copy of StartupActiveTurn
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupActiveTurnCopyWith<StartupActiveTurn> get copyWith => _$StartupActiveTurnCopyWithImpl<StartupActiveTurn>(this as StartupActiveTurn, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupActiveTurn;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupActiveTurn&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId));
}


@override
int get hashCode {
  final _this = this as StartupActiveTurn;
  return Object.hash(runtimeType,_this.threadId,_this.turnId);
}

@override
String toString() {
  final _this = this as StartupActiveTurn;
  return 'StartupActiveTurn(threadId: ${_this.threadId}, turnId: ${_this.turnId})';
}


}

/// @nodoc
abstract mixin class $StartupActiveTurnCopyWith<$Res>  {
  factory $StartupActiveTurnCopyWith(StartupActiveTurn value, $Res Function(StartupActiveTurn) _then) = _$StartupActiveTurnCopyWithImpl;
@useResult
$Res call({
 String threadId, String turnId
});




}
/// @nodoc
class _$StartupActiveTurnCopyWithImpl<$Res>
    implements $StartupActiveTurnCopyWith<$Res> {
  _$StartupActiveTurnCopyWithImpl(this._self, this._then);

  final StartupActiveTurn _self;
  final $Res Function(StartupActiveTurn) _then;

/// Create a copy of StartupActiveTurn
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? turnId = null,}) {
  return _then(StartupActiveTurn(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StartupActiveTurn].
extension StartupActiveTurnPatterns on StartupActiveTurn {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupActiveTurn value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupActiveTurn() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupActiveTurn value)  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurn():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupActiveTurn value)?  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurn() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  String turnId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupActiveTurn() when $default != null:
return $default(_that.threadId,_that.turnId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  String turnId)  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurn():
return $default(_that.threadId,_that.turnId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  String turnId)?  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurn() when $default != null:
return $default(_that.threadId,_that.turnId);case _:
  return null;

}
}

}

/// @nodoc


class _StartupActiveTurn implements StartupActiveTurn {
  const _StartupActiveTurn({required this.threadId, required this.turnId});


@override final  String threadId;
@override final  String turnId;

/// Create a copy of StartupActiveTurn
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupActiveTurnCopyWith<_StartupActiveTurn> get copyWith => __$StartupActiveTurnCopyWithImpl<_StartupActiveTurn>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupActiveTurn&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,turnId);
}

@override
String toString() {
    return 'StartupActiveTurn(threadId: $threadId, turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class _$StartupActiveTurnCopyWith<$Res> implements $StartupActiveTurnCopyWith<$Res> {
  factory _$StartupActiveTurnCopyWith(_StartupActiveTurn value, $Res Function(_StartupActiveTurn) _then) = __$StartupActiveTurnCopyWithImpl;
@override @useResult
$Res call({
 String threadId, String turnId
});




}
/// @nodoc
class __$StartupActiveTurnCopyWithImpl<$Res>
    implements _$StartupActiveTurnCopyWith<$Res> {
  __$StartupActiveTurnCopyWithImpl(this._self, this._then);

  final _StartupActiveTurn _self;
  final $Res Function(_StartupActiveTurn) _then;

/// Create a copy of StartupActiveTurn
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? turnId = null,}) {
  return _then(_StartupActiveTurn(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StartupActiveTurnPage {

 RuntimeStartupReadRef get reference; int get offset; int get total; List<StartupActiveTurn> get items; int? get nextOffset;
/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupActiveTurnPageCopyWith<StartupActiveTurnPage> get copyWith => _$StartupActiveTurnPageCopyWithImpl<StartupActiveTurnPage>(this as StartupActiveTurnPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupActiveTurnPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupActiveTurnPage&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as StartupActiveTurnPage;
  return Object.hash(runtimeType,_this.reference,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as StartupActiveTurnPage;
  return 'StartupActiveTurnPage(reference: ${_this.reference}, offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $StartupActiveTurnPageCopyWith<$Res>  {
  factory $StartupActiveTurnPageCopyWith(StartupActiveTurnPage value, $Res Function(StartupActiveTurnPage) _then) = _$StartupActiveTurnPageCopyWithImpl;
@useResult
$Res call({
 RuntimeStartupReadRef reference, int offset, int total, List<StartupActiveTurn> items, int? nextOffset
});


$RuntimeStartupReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$StartupActiveTurnPageCopyWithImpl<$Res>
    implements $StartupActiveTurnPageCopyWith<$Res> {
  _$StartupActiveTurnPageCopyWithImpl(this._self, this._then);

  final StartupActiveTurnPage _self;
  final $Res Function(StartupActiveTurnPage) _then;

/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(StartupActiveTurnPage(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<StartupActiveTurn>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get reference {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartupActiveTurnPage].
extension StartupActiveTurnPagePatterns on StartupActiveTurnPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupActiveTurnPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupActiveTurnPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupActiveTurnPage value)  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupActiveTurnPage value)?  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RuntimeStartupReadRef reference,  int offset,  int total,  List<StartupActiveTurn> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupActiveTurnPage() when $default != null:
return $default(_that.reference,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RuntimeStartupReadRef reference,  int offset,  int total,  List<StartupActiveTurn> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnPage():
return $default(_that.reference,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RuntimeStartupReadRef reference,  int offset,  int total,  List<StartupActiveTurn> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnPage() when $default != null:
return $default(_that.reference,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _StartupActiveTurnPage implements StartupActiveTurnPage {
  const _StartupActiveTurnPage({required this.reference, required this.offset, required this.total, required  List<StartupActiveTurn> items, required this.nextOffset}): _items = items;


@override final  RuntimeStartupReadRef reference;
@override final  int offset;
@override final  int total;
 final  List<StartupActiveTurn> _items;
@override List<StartupActiveTurn> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupActiveTurnPageCopyWith<_StartupActiveTurnPage> get copyWith => __$StartupActiveTurnPageCopyWithImpl<_StartupActiveTurnPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupActiveTurnPage&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'StartupActiveTurnPage(reference: $reference, offset: $offset, total: $total, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$StartupActiveTurnPageCopyWith<$Res> implements $StartupActiveTurnPageCopyWith<$Res> {
  factory _$StartupActiveTurnPageCopyWith(_StartupActiveTurnPage value, $Res Function(_StartupActiveTurnPage) _then) = __$StartupActiveTurnPageCopyWithImpl;
@override @useResult
$Res call({
 RuntimeStartupReadRef reference, int offset, int total, List<StartupActiveTurn> items, int? nextOffset
});


@override $RuntimeStartupReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$StartupActiveTurnPageCopyWithImpl<$Res>
    implements _$StartupActiveTurnPageCopyWith<$Res> {
  __$StartupActiveTurnPageCopyWithImpl(this._self, this._then);

  final _StartupActiveTurnPage _self;
  final $Res Function(_StartupActiveTurnPage) _then;

/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_StartupActiveTurnPage(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<StartupActiveTurn>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of StartupActiveTurnPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get reference {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$PendingPersistence {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PendingPersistence);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PendingPersistence()';
}


}

/// @nodoc
class $PendingPersistenceCopyWith<$Res>  {
$PendingPersistenceCopyWith(PendingPersistence _, $Res Function(PendingPersistence) __);
}


/// Adds pattern-matching-related methods to [PendingPersistence].
extension PendingPersistencePatterns on PendingPersistence {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnknownPendingPersistence value)?  unknown,TResult Function( CountPendingPersistence value)?  pending,TResult Function( DrainedPendingPersistence value)?  drained,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnknownPendingPersistence() when unknown != null:
return unknown(_that);case CountPendingPersistence() when pending != null:
return pending(_that);case DrainedPendingPersistence() when drained != null:
return drained(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnknownPendingPersistence value)  unknown,required TResult Function( CountPendingPersistence value)  pending,required TResult Function( DrainedPendingPersistence value)  drained,}){
final _that = this;
switch (_that) {
case UnknownPendingPersistence():
return unknown(_that);case CountPendingPersistence():
return pending(_that);case DrainedPendingPersistence():
return drained(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnknownPendingPersistence value)?  unknown,TResult? Function( CountPendingPersistence value)?  pending,TResult? Function( DrainedPendingPersistence value)?  drained,}){
final _that = this;
switch (_that) {
case UnknownPendingPersistence() when unknown != null:
return unknown(_that);case CountPendingPersistence() when pending != null:
return pending(_that);case DrainedPendingPersistence() when drained != null:
return drained(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unknown,TResult Function( int count)?  pending,TResult Function()?  drained,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnknownPendingPersistence() when unknown != null:
return unknown();case CountPendingPersistence() when pending != null:
return pending(_that.count);case DrainedPendingPersistence() when drained != null:
return drained();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unknown,required TResult Function( int count)  pending,required TResult Function()  drained,}) {final _that = this;
switch (_that) {
case UnknownPendingPersistence():
return unknown();case CountPendingPersistence():
return pending(_that.count);case DrainedPendingPersistence():
return drained();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unknown,TResult? Function( int count)?  pending,TResult? Function()?  drained,}) {final _that = this;
switch (_that) {
case UnknownPendingPersistence() when unknown != null:
return unknown();case CountPendingPersistence() when pending != null:
return pending(_that.count);case DrainedPendingPersistence() when drained != null:
return drained();case _:
  return null;

}
}

}

/// @nodoc


class UnknownPendingPersistence implements PendingPersistence {
  const UnknownPendingPersistence();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownPendingPersistence);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PendingPersistence.unknown()';
}


}




/// @nodoc


class CountPendingPersistence implements PendingPersistence {
  const CountPendingPersistence({required this.count});


 final  int count;

/// Create a copy of PendingPersistence
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CountPendingPersistenceCopyWith<CountPendingPersistence> get copyWith => _$CountPendingPersistenceCopyWithImpl<CountPendingPersistence>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CountPendingPersistence&&(identical(other.count, count) || other.count == count));
}


@override
int get hashCode {
    return Object.hash(runtimeType,count);
}

@override
String toString() {
    return 'PendingPersistence.pending(count: $count)';
}


}

/// @nodoc
abstract mixin class $CountPendingPersistenceCopyWith<$Res> implements $PendingPersistenceCopyWith<$Res> {
  factory $CountPendingPersistenceCopyWith(CountPendingPersistence value, $Res Function(CountPendingPersistence) _then) = _$CountPendingPersistenceCopyWithImpl;
@useResult
$Res call({
 int count
});




}
/// @nodoc
class _$CountPendingPersistenceCopyWithImpl<$Res>
    implements $CountPendingPersistenceCopyWith<$Res> {
  _$CountPendingPersistenceCopyWithImpl(this._self, this._then);

  final CountPendingPersistence _self;
  final $Res Function(CountPendingPersistence) _then;

/// Create a copy of PendingPersistence
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? count = null,}) {
  return _then(CountPendingPersistence(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class DrainedPendingPersistence implements PendingPersistence {
  const DrainedPendingPersistence();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DrainedPendingPersistence);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'PendingPersistence.drained()';
}


}




/// @nodoc
mixin _$StudioShutdownReport {


/// Create a copy of StudioShutdownReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioShutdownReportCopyWith<StudioShutdownReport> get copyWith => _$StudioShutdownReportCopyWithImpl<StudioShutdownReport>(this as StudioShutdownReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioShutdownReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioShutdownReport&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&const DeepCollectionEquality().equals(other.issues, _this.issues)&&(identical(other.persistence, _this.persistence) || other.persistence == _this.persistence));
}


@override
int get hashCode {
  final _this = this as StudioShutdownReport;
  return Object.hash(runtimeType,_this.outcome,const DeepCollectionEquality().hash(_this.issues),_this.persistence);
}



}

/// @nodoc
abstract mixin class $StudioShutdownReportCopyWith<$Res>  {
  factory $StudioShutdownReportCopyWith(StudioShutdownReport value, $Res Function(StudioShutdownReport) _then) = _$StudioShutdownReportCopyWithImpl;
@useResult
$Res call({
 ShutdownOutcome outcome, List<StudioShutdownIssue> issues, PendingPersistence persistence
});


$PendingPersistenceCopyWith<$Res> get persistence;

}
/// @nodoc
class _$StudioShutdownReportCopyWithImpl<$Res>
    implements $StudioShutdownReportCopyWith<$Res> {
  _$StudioShutdownReportCopyWithImpl(this._self, this._then);

  final StudioShutdownReport _self;
  final $Res Function(StudioShutdownReport) _then;

/// Create a copy of StudioShutdownReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outcome = null,Object? issues = null,Object? persistence = null,}) {
  return _then(StudioShutdownReport(
outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as ShutdownOutcome,issues: null == issues ? _self.issues : issues // ignore: cast_nullable_to_non_nullable
as List<StudioShutdownIssue>,persistence: null == persistence ? _self.persistence : persistence // ignore: cast_nullable_to_non_nullable
as PendingPersistence,
  ));
}
/// Create a copy of StudioShutdownReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PendingPersistenceCopyWith<$Res> get persistence {

  return $PendingPersistenceCopyWith<$Res>(_self.persistence, (value) {
    return _then(_self.copyWith(persistence: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioShutdownReport].
extension StudioShutdownReportPatterns on StudioShutdownReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({required TResult orElse(),}){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(){
final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({required TResult orElse(),}) {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>() {final _that = this;
switch (_that) {
case _:
  return null;

}
}

}

/// @nodoc
mixin _$UpdateHandoff {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateHandoff);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $UpdateHandoffCopyWith<$Res>  {
$UpdateHandoffCopyWith(UpdateHandoff _, $Res Function(UpdateHandoff) __);
}


/// Adds pattern-matching-related methods to [UpdateHandoff].
extension UpdateHandoffPatterns on UpdateHandoff {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NotRequestedUpdateHandoff value)?  notRequested,TResult Function( LaunchedUpdateHandoff value)?  launched,TResult Function( FailedUpdateHandoff value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff() when notRequested != null:
return notRequested(_that);case LaunchedUpdateHandoff() when launched != null:
return launched(_that);case FailedUpdateHandoff() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NotRequestedUpdateHandoff value)  notRequested,required TResult Function( LaunchedUpdateHandoff value)  launched,required TResult Function( FailedUpdateHandoff value)  failed,}){
final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff():
return notRequested(_that);case LaunchedUpdateHandoff():
return launched(_that);case FailedUpdateHandoff():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NotRequestedUpdateHandoff value)?  notRequested,TResult? Function( LaunchedUpdateHandoff value)?  launched,TResult? Function( FailedUpdateHandoff value)?  failed,}){
final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff() when notRequested != null:
return notRequested(_that);case LaunchedUpdateHandoff() when launched != null:
return launched(_that);case FailedUpdateHandoff() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  notRequested,TResult Function( String version)?  launched,TResult Function( SourceStateError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff() when notRequested != null:
return notRequested();case LaunchedUpdateHandoff() when launched != null:
return launched(_that.version);case FailedUpdateHandoff() when failed != null:
return failed(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  notRequested,required TResult Function( String version)  launched,required TResult Function( SourceStateError error)  failed,}) {final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff():
return notRequested();case LaunchedUpdateHandoff():
return launched(_that.version);case FailedUpdateHandoff():
return failed(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  notRequested,TResult? Function( String version)?  launched,TResult? Function( SourceStateError error)?  failed,}) {final _that = this;
switch (_that) {
case NotRequestedUpdateHandoff() when notRequested != null:
return notRequested();case LaunchedUpdateHandoff() when launched != null:
return launched(_that.version);case FailedUpdateHandoff() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class NotRequestedUpdateHandoff implements UpdateHandoff {
  const NotRequestedUpdateHandoff();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NotRequestedUpdateHandoff);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class LaunchedUpdateHandoff implements UpdateHandoff {
  const LaunchedUpdateHandoff({required this.version});


 final  String version;

/// Create a copy of UpdateHandoff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LaunchedUpdateHandoffCopyWith<LaunchedUpdateHandoff> get copyWith => _$LaunchedUpdateHandoffCopyWithImpl<LaunchedUpdateHandoff>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LaunchedUpdateHandoff&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version);
}



}

/// @nodoc
abstract mixin class $LaunchedUpdateHandoffCopyWith<$Res> implements $UpdateHandoffCopyWith<$Res> {
  factory $LaunchedUpdateHandoffCopyWith(LaunchedUpdateHandoff value, $Res Function(LaunchedUpdateHandoff) _then) = _$LaunchedUpdateHandoffCopyWithImpl;
@useResult
$Res call({
 String version
});




}
/// @nodoc
class _$LaunchedUpdateHandoffCopyWithImpl<$Res>
    implements $LaunchedUpdateHandoffCopyWith<$Res> {
  _$LaunchedUpdateHandoffCopyWithImpl(this._self, this._then);

  final LaunchedUpdateHandoff _self;
  final $Res Function(LaunchedUpdateHandoff) _then;

/// Create a copy of UpdateHandoff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? version = null,}) {
  return _then(LaunchedUpdateHandoff(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FailedUpdateHandoff implements UpdateHandoff {
  const FailedUpdateHandoff({required this.error});


 final  SourceStateError error;

/// Create a copy of UpdateHandoff
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedUpdateHandoffCopyWith<FailedUpdateHandoff> get copyWith => _$FailedUpdateHandoffCopyWithImpl<FailedUpdateHandoff>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedUpdateHandoff&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $FailedUpdateHandoffCopyWith<$Res> implements $UpdateHandoffCopyWith<$Res> {
  factory $FailedUpdateHandoffCopyWith(FailedUpdateHandoff value, $Res Function(FailedUpdateHandoff) _then) = _$FailedUpdateHandoffCopyWithImpl;
@useResult
$Res call({
 SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedUpdateHandoffCopyWithImpl<$Res>
    implements $FailedUpdateHandoffCopyWith<$Res> {
  _$FailedUpdateHandoffCopyWithImpl(this._self, this._then);

  final FailedUpdateHandoff _self;
  final $Res Function(FailedUpdateHandoff) _then;

/// Create a copy of UpdateHandoff
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(FailedUpdateHandoff(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of UpdateHandoff
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$StudioExitReport {

 StudioShutdownReport get shutdown; UpdateHandoff get updateHandoff;
/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioExitReportCopyWith<StudioExitReport> get copyWith => _$StudioExitReportCopyWithImpl<StudioExitReport>(this as StudioExitReport, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioExitReport;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioExitReport&&(identical(other.shutdown, _this.shutdown) || other.shutdown == _this.shutdown)&&(identical(other.updateHandoff, _this.updateHandoff) || other.updateHandoff == _this.updateHandoff));
}


@override
int get hashCode {
  final _this = this as StudioExitReport;
  return Object.hash(runtimeType,_this.shutdown,_this.updateHandoff);
}



}

/// @nodoc
abstract mixin class $StudioExitReportCopyWith<$Res>  {
  factory $StudioExitReportCopyWith(StudioExitReport value, $Res Function(StudioExitReport) _then) = _$StudioExitReportCopyWithImpl;
@useResult
$Res call({
 StudioShutdownReport shutdown, UpdateHandoff updateHandoff
});


$StudioShutdownReportCopyWith<$Res> get shutdown;$UpdateHandoffCopyWith<$Res> get updateHandoff;

}
/// @nodoc
class _$StudioExitReportCopyWithImpl<$Res>
    implements $StudioExitReportCopyWith<$Res> {
  _$StudioExitReportCopyWithImpl(this._self, this._then);

  final StudioExitReport _self;
  final $Res Function(StudioExitReport) _then;

/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? shutdown = null,Object? updateHandoff = null,}) {
  return _then(StudioExitReport(
shutdown: null == shutdown ? _self.shutdown : shutdown // ignore: cast_nullable_to_non_nullable
as StudioShutdownReport,updateHandoff: null == updateHandoff ? _self.updateHandoff : updateHandoff // ignore: cast_nullable_to_non_nullable
as UpdateHandoff,
  ));
}
/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownReportCopyWith<$Res> get shutdown {

  return $StudioShutdownReportCopyWith<$Res>(_self.shutdown, (value) {
    return _then(_self.copyWith(shutdown: value));
  });
}/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateHandoffCopyWith<$Res> get updateHandoff {

  return $UpdateHandoffCopyWith<$Res>(_self.updateHandoff, (value) {
    return _then(_self.copyWith(updateHandoff: value));
  });
}
}


/// Adds pattern-matching-related methods to [StudioExitReport].
extension StudioExitReportPatterns on StudioExitReport {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StudioExitReport value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StudioExitReport() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StudioExitReport value)  $default,){
final _that = this;
switch (_that) {
case _StudioExitReport():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StudioExitReport value)?  $default,){
final _that = this;
switch (_that) {
case _StudioExitReport() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( StudioShutdownReport shutdown,  UpdateHandoff updateHandoff)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StudioExitReport() when $default != null:
return $default(_that.shutdown,_that.updateHandoff);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( StudioShutdownReport shutdown,  UpdateHandoff updateHandoff)  $default,) {final _that = this;
switch (_that) {
case _StudioExitReport():
return $default(_that.shutdown,_that.updateHandoff);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( StudioShutdownReport shutdown,  UpdateHandoff updateHandoff)?  $default,) {final _that = this;
switch (_that) {
case _StudioExitReport() when $default != null:
return $default(_that.shutdown,_that.updateHandoff);case _:
  return null;

}
}

}

/// @nodoc


class _StudioExitReport implements StudioExitReport {
  const _StudioExitReport({required this.shutdown, required this.updateHandoff});


@override final  StudioShutdownReport shutdown;
@override final  UpdateHandoff updateHandoff;

/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StudioExitReportCopyWith<_StudioExitReport> get copyWith => __$StudioExitReportCopyWithImpl<_StudioExitReport>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StudioExitReport&&(identical(other.shutdown, shutdown) || other.shutdown == shutdown)&&(identical(other.updateHandoff, updateHandoff) || other.updateHandoff == updateHandoff));
}


@override
int get hashCode {
    return Object.hash(runtimeType,shutdown,updateHandoff);
}



}

/// @nodoc
abstract mixin class _$StudioExitReportCopyWith<$Res> implements $StudioExitReportCopyWith<$Res> {
  factory _$StudioExitReportCopyWith(_StudioExitReport value, $Res Function(_StudioExitReport) _then) = __$StudioExitReportCopyWithImpl;
@override @useResult
$Res call({
 StudioShutdownReport shutdown, UpdateHandoff updateHandoff
});


@override $StudioShutdownReportCopyWith<$Res> get shutdown;@override $UpdateHandoffCopyWith<$Res> get updateHandoff;

}
/// @nodoc
class __$StudioExitReportCopyWithImpl<$Res>
    implements _$StudioExitReportCopyWith<$Res> {
  __$StudioExitReportCopyWithImpl(this._self, this._then);

  final _StudioExitReport _self;
  final $Res Function(_StudioExitReport) _then;

/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? shutdown = null,Object? updateHandoff = null,}) {
  return _then(_StudioExitReport(
shutdown: null == shutdown ? _self.shutdown : shutdown // ignore: cast_nullable_to_non_nullable
as StudioShutdownReport,updateHandoff: null == updateHandoff ? _self.updateHandoff : updateHandoff // ignore: cast_nullable_to_non_nullable
as UpdateHandoff,
  ));
}

/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioShutdownReportCopyWith<$Res> get shutdown {

  return $StudioShutdownReportCopyWith<$Res>(_self.shutdown, (value) {
    return _then(_self.copyWith(shutdown: value));
  });
}/// Create a copy of StudioExitReport
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateHandoffCopyWith<$Res> get updateHandoff {

  return $UpdateHandoffCopyWith<$Res>(_self.updateHandoff, (value) {
    return _then(_self.copyWith(updateHandoff: value));
  });
}
}

// dart format on
