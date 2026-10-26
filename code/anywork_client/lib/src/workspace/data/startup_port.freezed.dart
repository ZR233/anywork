// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'startup_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$StartupProgressFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupProgressFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StartupProgressFrameCopyWith<$Res>  {
$StartupProgressFrameCopyWith(StartupProgressFrame _, $Res Function(StartupProgressFrame) __);
}


/// Adds pattern-matching-related methods to [StartupProgressFrame].
extension StartupProgressFramePatterns on StartupProgressFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DataStartupProgressFrame value)?  data,TResult Function( FailureStartupProgressFrame value)?  failure,TResult Function( ClosedStartupProgressFrame value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DataStartupProgressFrame() when data != null:
return data(_that);case FailureStartupProgressFrame() when failure != null:
return failure(_that);case ClosedStartupProgressFrame() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DataStartupProgressFrame value)  data,required TResult Function( FailureStartupProgressFrame value)  failure,required TResult Function( ClosedStartupProgressFrame value)  closed,}){
final _that = this;
switch (_that) {
case DataStartupProgressFrame():
return data(_that);case FailureStartupProgressFrame():
return failure(_that);case ClosedStartupProgressFrame():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DataStartupProgressFrame value)?  data,TResult? Function( FailureStartupProgressFrame value)?  failure,TResult? Function( ClosedStartupProgressFrame value)?  closed,}){
final _that = this;
switch (_that) {
case DataStartupProgressFrame() when data != null:
return data(_that);case FailureStartupProgressFrame() when failure != null:
return failure(_that);case ClosedStartupProgressFrame() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  StartupStage stage)?  data,TResult Function( StudioFailure error)?  failure,TResult Function( StartupCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DataStartupProgressFrame() when data != null:
return data(_that.deliverySequence,_that.stage);case FailureStartupProgressFrame() when failure != null:
return failure(_that.error);case ClosedStartupProgressFrame() when closed != null:
return closed(_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  StartupStage stage)  data,required TResult Function( StudioFailure error)  failure,required TResult Function( StartupCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case DataStartupProgressFrame():
return data(_that.deliverySequence,_that.stage);case FailureStartupProgressFrame():
return failure(_that.error);case ClosedStartupProgressFrame():
return closed(_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  StartupStage stage)?  data,TResult? Function( StudioFailure error)?  failure,TResult? Function( StartupCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case DataStartupProgressFrame() when data != null:
return data(_that.deliverySequence,_that.stage);case FailureStartupProgressFrame() when failure != null:
return failure(_that.error);case ClosedStartupProgressFrame() when closed != null:
return closed(_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class DataStartupProgressFrame implements StartupProgressFrame {
  const DataStartupProgressFrame({required this.deliverySequence, required this.stage});


 final  int deliverySequence;
 final  StartupStage stage;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DataStartupProgressFrameCopyWith<DataStartupProgressFrame> get copyWith => _$DataStartupProgressFrameCopyWithImpl<DataStartupProgressFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DataStartupProgressFrame&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.stage, stage) || other.stage == stage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,stage);
}



}

/// @nodoc
abstract mixin class $DataStartupProgressFrameCopyWith<$Res> implements $StartupProgressFrameCopyWith<$Res> {
  factory $DataStartupProgressFrameCopyWith(DataStartupProgressFrame value, $Res Function(DataStartupProgressFrame) _then) = _$DataStartupProgressFrameCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, StartupStage stage
});




}
/// @nodoc
class _$DataStartupProgressFrameCopyWithImpl<$Res>
    implements $DataStartupProgressFrameCopyWith<$Res> {
  _$DataStartupProgressFrameCopyWithImpl(this._self, this._then);

  final DataStartupProgressFrame _self;
  final $Res Function(DataStartupProgressFrame) _then;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? stage = null,}) {
  return _then(DataStartupProgressFrame(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as StartupStage,
  ));
}


}

/// @nodoc


class FailureStartupProgressFrame implements StartupProgressFrame {
  const FailureStartupProgressFrame({required this.error});


 final  StudioFailure error;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailureStartupProgressFrameCopyWith<FailureStartupProgressFrame> get copyWith => _$FailureStartupProgressFrameCopyWithImpl<FailureStartupProgressFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailureStartupProgressFrame&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $FailureStartupProgressFrameCopyWith<$Res> implements $StartupProgressFrameCopyWith<$Res> {
  factory $FailureStartupProgressFrameCopyWith(FailureStartupProgressFrame value, $Res Function(FailureStartupProgressFrame) _then) = _$FailureStartupProgressFrameCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$FailureStartupProgressFrameCopyWithImpl<$Res>
    implements $FailureStartupProgressFrameCopyWith<$Res> {
  _$FailureStartupProgressFrameCopyWithImpl(this._self, this._then);

  final FailureStartupProgressFrame _self;
  final $Res Function(FailureStartupProgressFrame) _then;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(FailureStartupProgressFrame(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of StartupProgressFrame
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


class ClosedStartupProgressFrame implements StartupProgressFrame {
  const ClosedStartupProgressFrame({required this.reason});


 final  StartupCloseReason reason;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ClosedStartupProgressFrameCopyWith<ClosedStartupProgressFrame> get copyWith => _$ClosedStartupProgressFrameCopyWithImpl<ClosedStartupProgressFrame>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ClosedStartupProgressFrame&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reason);
}



}

/// @nodoc
abstract mixin class $ClosedStartupProgressFrameCopyWith<$Res> implements $StartupProgressFrameCopyWith<$Res> {
  factory $ClosedStartupProgressFrameCopyWith(ClosedStartupProgressFrame value, $Res Function(ClosedStartupProgressFrame) _then) = _$ClosedStartupProgressFrameCopyWithImpl;
@useResult
$Res call({
 StartupCloseReason reason
});




}
/// @nodoc
class _$ClosedStartupProgressFrameCopyWithImpl<$Res>
    implements $ClosedStartupProgressFrameCopyWith<$Res> {
  _$ClosedStartupProgressFrameCopyWithImpl(this._self, this._then);

  final ClosedStartupProgressFrame _self;
  final $Res Function(ClosedStartupProgressFrame) _then;

/// Create a copy of StartupProgressFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? reason = null,}) {
  return _then(ClosedStartupProgressFrame(
reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as StartupCloseReason,
  ));
}


}

/// @nodoc
mixin _$RuntimeStartupScopeIdentity {

 String get scopeId; String get ownerEpoch; int get attemptId; int get revision;
/// Create a copy of RuntimeStartupScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStartupScopeIdentityCopyWith<RuntimeStartupScopeIdentity> get copyWith => _$RuntimeStartupScopeIdentityCopyWithImpl<RuntimeStartupScopeIdentity>(this as RuntimeStartupScopeIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeStartupScopeIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStartupScopeIdentity&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch)&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as RuntimeStartupScopeIdentity;
  return Object.hash(runtimeType,_this.scopeId,_this.ownerEpoch,_this.attemptId,_this.revision);
}

@override
String toString() {
  final _this = this as RuntimeStartupScopeIdentity;
  return 'RuntimeStartupScopeIdentity(scopeId: ${_this.scopeId}, ownerEpoch: ${_this.ownerEpoch}, attemptId: ${_this.attemptId}, revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $RuntimeStartupScopeIdentityCopyWith<$Res>  {
  factory $RuntimeStartupScopeIdentityCopyWith(RuntimeStartupScopeIdentity value, $Res Function(RuntimeStartupScopeIdentity) _then) = _$RuntimeStartupScopeIdentityCopyWithImpl;
@useResult
$Res call({
 String scopeId, String ownerEpoch, int attemptId, int revision
});




}
/// @nodoc
class _$RuntimeStartupScopeIdentityCopyWithImpl<$Res>
    implements $RuntimeStartupScopeIdentityCopyWith<$Res> {
  _$RuntimeStartupScopeIdentityCopyWithImpl(this._self, this._then);

  final RuntimeStartupScopeIdentity _self;
  final $Res Function(RuntimeStartupScopeIdentity) _then;

/// Create a copy of RuntimeStartupScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? ownerEpoch = null,Object? attemptId = null,Object? revision = null,}) {
  return _then(RuntimeStartupScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [RuntimeStartupScopeIdentity].
extension RuntimeStartupScopeIdentityPatterns on RuntimeStartupScopeIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeStartupScopeIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeStartupScopeIdentity value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeStartupScopeIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  String ownerEpoch,  int attemptId,  int revision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.ownerEpoch,_that.attemptId,_that.revision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  String ownerEpoch,  int attemptId,  int revision)  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity():
return $default(_that.scopeId,_that.ownerEpoch,_that.attemptId,_that.revision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  String ownerEpoch,  int attemptId,  int revision)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupScopeIdentity() when $default != null:
return $default(_that.scopeId,_that.ownerEpoch,_that.attemptId,_that.revision);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeStartupScopeIdentity implements RuntimeStartupScopeIdentity {
  const _RuntimeStartupScopeIdentity({required this.scopeId, required this.ownerEpoch, required this.attemptId, required this.revision});


@override final  String scopeId;
@override final  String ownerEpoch;
@override final  int attemptId;
@override final  int revision;

/// Create a copy of RuntimeStartupScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeStartupScopeIdentityCopyWith<_RuntimeStartupScopeIdentity> get copyWith => __$RuntimeStartupScopeIdentityCopyWithImpl<_RuntimeStartupScopeIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeStartupScopeIdentity&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch)&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.revision, revision) || other.revision == revision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,ownerEpoch,attemptId,revision);
}

@override
String toString() {
    return 'RuntimeStartupScopeIdentity(scopeId: $scopeId, ownerEpoch: $ownerEpoch, attemptId: $attemptId, revision: $revision)';
}


}

/// @nodoc
abstract mixin class _$RuntimeStartupScopeIdentityCopyWith<$Res> implements $RuntimeStartupScopeIdentityCopyWith<$Res> {
  factory _$RuntimeStartupScopeIdentityCopyWith(_RuntimeStartupScopeIdentity value, $Res Function(_RuntimeStartupScopeIdentity) _then) = __$RuntimeStartupScopeIdentityCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, String ownerEpoch, int attemptId, int revision
});




}
/// @nodoc
class __$RuntimeStartupScopeIdentityCopyWithImpl<$Res>
    implements _$RuntimeStartupScopeIdentityCopyWith<$Res> {
  __$RuntimeStartupScopeIdentityCopyWithImpl(this._self, this._then);

  final _RuntimeStartupScopeIdentity _self;
  final $Res Function(_RuntimeStartupScopeIdentity) _then;

/// Create a copy of RuntimeStartupScopeIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? ownerEpoch = null,Object? attemptId = null,Object? revision = null,}) {
  return _then(_RuntimeStartupScopeIdentity(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$RuntimeStateRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStateRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $RuntimeStateReadCopyWith<$Res>  {
$RuntimeStateReadCopyWith(RuntimeStateRead _, $Res Function(RuntimeStateRead) __);
}


/// Adds pattern-matching-related methods to [RuntimeStateRead].
extension RuntimeStateReadPatterns on RuntimeStateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UninitializedRuntimeStateRead value)?  uninitialized,TResult Function( InitializingRuntimeStateRead value)?  initializing,TResult Function( ReadyRuntimeStateRead value)?  ready,TResult Function( ShuttingDownRuntimeStateRead value)?  shuttingDown,TResult Function( StoppedRuntimeStateRead value)?  stopped,TResult Function( FailedRuntimeStateRead value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead() when uninitialized != null:
return uninitialized(_that);case InitializingRuntimeStateRead() when initializing != null:
return initializing(_that);case ReadyRuntimeStateRead() when ready != null:
return ready(_that);case ShuttingDownRuntimeStateRead() when shuttingDown != null:
return shuttingDown(_that);case StoppedRuntimeStateRead() when stopped != null:
return stopped(_that);case FailedRuntimeStateRead() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UninitializedRuntimeStateRead value)  uninitialized,required TResult Function( InitializingRuntimeStateRead value)  initializing,required TResult Function( ReadyRuntimeStateRead value)  ready,required TResult Function( ShuttingDownRuntimeStateRead value)  shuttingDown,required TResult Function( StoppedRuntimeStateRead value)  stopped,required TResult Function( FailedRuntimeStateRead value)  failed,}){
final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead():
return uninitialized(_that);case InitializingRuntimeStateRead():
return initializing(_that);case ReadyRuntimeStateRead():
return ready(_that);case ShuttingDownRuntimeStateRead():
return shuttingDown(_that);case StoppedRuntimeStateRead():
return stopped(_that);case FailedRuntimeStateRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UninitializedRuntimeStateRead value)?  uninitialized,TResult? Function( InitializingRuntimeStateRead value)?  initializing,TResult? Function( ReadyRuntimeStateRead value)?  ready,TResult? Function( ShuttingDownRuntimeStateRead value)?  shuttingDown,TResult? Function( StoppedRuntimeStateRead value)?  stopped,TResult? Function( FailedRuntimeStateRead value)?  failed,}){
final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead() when uninitialized != null:
return uninitialized(_that);case InitializingRuntimeStateRead() when initializing != null:
return initializing(_that);case ReadyRuntimeStateRead() when ready != null:
return ready(_that);case ShuttingDownRuntimeStateRead() when shuttingDown != null:
return shuttingDown(_that);case StoppedRuntimeStateRead() when stopped != null:
return stopped(_that);case FailedRuntimeStateRead() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int at)?  uninitialized,TResult Function( int at)?  initializing,TResult Function( int at)?  ready,TResult Function( int at)?  shuttingDown,TResult Function( int at)?  stopped,TResult Function( int failedAt,  SourceStateErrorRead error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead() when uninitialized != null:
return uninitialized(_that.at);case InitializingRuntimeStateRead() when initializing != null:
return initializing(_that.at);case ReadyRuntimeStateRead() when ready != null:
return ready(_that.at);case ShuttingDownRuntimeStateRead() when shuttingDown != null:
return shuttingDown(_that.at);case StoppedRuntimeStateRead() when stopped != null:
return stopped(_that.at);case FailedRuntimeStateRead() when failed != null:
return failed(_that.failedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int at)  uninitialized,required TResult Function( int at)  initializing,required TResult Function( int at)  ready,required TResult Function( int at)  shuttingDown,required TResult Function( int at)  stopped,required TResult Function( int failedAt,  SourceStateErrorRead error)  failed,}) {final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead():
return uninitialized(_that.at);case InitializingRuntimeStateRead():
return initializing(_that.at);case ReadyRuntimeStateRead():
return ready(_that.at);case ShuttingDownRuntimeStateRead():
return shuttingDown(_that.at);case StoppedRuntimeStateRead():
return stopped(_that.at);case FailedRuntimeStateRead():
return failed(_that.failedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int at)?  uninitialized,TResult? Function( int at)?  initializing,TResult? Function( int at)?  ready,TResult? Function( int at)?  shuttingDown,TResult? Function( int at)?  stopped,TResult? Function( int failedAt,  SourceStateErrorRead error)?  failed,}) {final _that = this;
switch (_that) {
case UninitializedRuntimeStateRead() when uninitialized != null:
return uninitialized(_that.at);case InitializingRuntimeStateRead() when initializing != null:
return initializing(_that.at);case ReadyRuntimeStateRead() when ready != null:
return ready(_that.at);case ShuttingDownRuntimeStateRead() when shuttingDown != null:
return shuttingDown(_that.at);case StoppedRuntimeStateRead() when stopped != null:
return stopped(_that.at);case FailedRuntimeStateRead() when failed != null:
return failed(_that.failedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class UninitializedRuntimeStateRead implements RuntimeStateRead {
  const UninitializedRuntimeStateRead({required this.at});


 final  int at;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UninitializedRuntimeStateReadCopyWith<UninitializedRuntimeStateRead> get copyWith => _$UninitializedRuntimeStateReadCopyWithImpl<UninitializedRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UninitializedRuntimeStateRead&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}



}

/// @nodoc
abstract mixin class $UninitializedRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $UninitializedRuntimeStateReadCopyWith(UninitializedRuntimeStateRead value, $Res Function(UninitializedRuntimeStateRead) _then) = _$UninitializedRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int at
});




}
/// @nodoc
class _$UninitializedRuntimeStateReadCopyWithImpl<$Res>
    implements $UninitializedRuntimeStateReadCopyWith<$Res> {
  _$UninitializedRuntimeStateReadCopyWithImpl(this._self, this._then);

  final UninitializedRuntimeStateRead _self;
  final $Res Function(UninitializedRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(UninitializedRuntimeStateRead(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class InitializingRuntimeStateRead implements RuntimeStateRead {
  const InitializingRuntimeStateRead({required this.at});


 final  int at;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InitializingRuntimeStateReadCopyWith<InitializingRuntimeStateRead> get copyWith => _$InitializingRuntimeStateReadCopyWithImpl<InitializingRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InitializingRuntimeStateRead&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}



}

/// @nodoc
abstract mixin class $InitializingRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $InitializingRuntimeStateReadCopyWith(InitializingRuntimeStateRead value, $Res Function(InitializingRuntimeStateRead) _then) = _$InitializingRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int at
});




}
/// @nodoc
class _$InitializingRuntimeStateReadCopyWithImpl<$Res>
    implements $InitializingRuntimeStateReadCopyWith<$Res> {
  _$InitializingRuntimeStateReadCopyWithImpl(this._self, this._then);

  final InitializingRuntimeStateRead _self;
  final $Res Function(InitializingRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(InitializingRuntimeStateRead(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReadyRuntimeStateRead implements RuntimeStateRead {
  const ReadyRuntimeStateRead({required this.at});


 final  int at;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyRuntimeStateReadCopyWith<ReadyRuntimeStateRead> get copyWith => _$ReadyRuntimeStateReadCopyWithImpl<ReadyRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyRuntimeStateRead&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}



}

/// @nodoc
abstract mixin class $ReadyRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $ReadyRuntimeStateReadCopyWith(ReadyRuntimeStateRead value, $Res Function(ReadyRuntimeStateRead) _then) = _$ReadyRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int at
});




}
/// @nodoc
class _$ReadyRuntimeStateReadCopyWithImpl<$Res>
    implements $ReadyRuntimeStateReadCopyWith<$Res> {
  _$ReadyRuntimeStateReadCopyWithImpl(this._self, this._then);

  final ReadyRuntimeStateRead _self;
  final $Res Function(ReadyRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(ReadyRuntimeStateRead(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ShuttingDownRuntimeStateRead implements RuntimeStateRead {
  const ShuttingDownRuntimeStateRead({required this.at});


 final  int at;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ShuttingDownRuntimeStateReadCopyWith<ShuttingDownRuntimeStateRead> get copyWith => _$ShuttingDownRuntimeStateReadCopyWithImpl<ShuttingDownRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ShuttingDownRuntimeStateRead&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}



}

/// @nodoc
abstract mixin class $ShuttingDownRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $ShuttingDownRuntimeStateReadCopyWith(ShuttingDownRuntimeStateRead value, $Res Function(ShuttingDownRuntimeStateRead) _then) = _$ShuttingDownRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int at
});




}
/// @nodoc
class _$ShuttingDownRuntimeStateReadCopyWithImpl<$Res>
    implements $ShuttingDownRuntimeStateReadCopyWith<$Res> {
  _$ShuttingDownRuntimeStateReadCopyWithImpl(this._self, this._then);

  final ShuttingDownRuntimeStateRead _self;
  final $Res Function(ShuttingDownRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(ShuttingDownRuntimeStateRead(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class StoppedRuntimeStateRead implements RuntimeStateRead {
  const StoppedRuntimeStateRead({required this.at});


 final  int at;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedRuntimeStateReadCopyWith<StoppedRuntimeStateRead> get copyWith => _$StoppedRuntimeStateReadCopyWithImpl<StoppedRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedRuntimeStateRead&&(identical(other.at, at) || other.at == at));
}


@override
int get hashCode {
    return Object.hash(runtimeType,at);
}



}

/// @nodoc
abstract mixin class $StoppedRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $StoppedRuntimeStateReadCopyWith(StoppedRuntimeStateRead value, $Res Function(StoppedRuntimeStateRead) _then) = _$StoppedRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int at
});




}
/// @nodoc
class _$StoppedRuntimeStateReadCopyWithImpl<$Res>
    implements $StoppedRuntimeStateReadCopyWith<$Res> {
  _$StoppedRuntimeStateReadCopyWithImpl(this._self, this._then);

  final StoppedRuntimeStateRead _self;
  final $Res Function(StoppedRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? at = null,}) {
  return _then(StoppedRuntimeStateRead(
at: null == at ? _self.at : at // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FailedRuntimeStateRead implements RuntimeStateRead {
  const FailedRuntimeStateRead({required this.failedAt, required this.error});


 final  int failedAt;
 final  SourceStateErrorRead error;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedRuntimeStateReadCopyWith<FailedRuntimeStateRead> get copyWith => _$FailedRuntimeStateReadCopyWithImpl<FailedRuntimeStateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedRuntimeStateRead&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}



}

/// @nodoc
abstract mixin class $FailedRuntimeStateReadCopyWith<$Res> implements $RuntimeStateReadCopyWith<$Res> {
  factory $FailedRuntimeStateReadCopyWith(FailedRuntimeStateRead value, $Res Function(FailedRuntimeStateRead) _then) = _$FailedRuntimeStateReadCopyWithImpl;
@useResult
$Res call({
 int failedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedRuntimeStateReadCopyWithImpl<$Res>
    implements $FailedRuntimeStateReadCopyWith<$Res> {
  _$FailedRuntimeStateReadCopyWithImpl(this._self, this._then);

  final FailedRuntimeStateRead _self;
  final $Res Function(FailedRuntimeStateRead) _then;

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(FailedRuntimeStateRead(
failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of RuntimeStateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$StartupRecoveryRead {

 ReadText get backupPath; ReadText get reason; int get createdAt;
/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupRecoveryReadCopyWith<StartupRecoveryRead> get copyWith => _$StartupRecoveryReadCopyWithImpl<StartupRecoveryRead>(this as StartupRecoveryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupRecoveryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupRecoveryRead&&(identical(other.backupPath, _this.backupPath) || other.backupPath == _this.backupPath)&&(identical(other.reason, _this.reason) || other.reason == _this.reason)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as StartupRecoveryRead;
  return Object.hash(runtimeType,_this.backupPath,_this.reason,_this.createdAt);
}



}

/// @nodoc
abstract mixin class $StartupRecoveryReadCopyWith<$Res>  {
  factory $StartupRecoveryReadCopyWith(StartupRecoveryRead value, $Res Function(StartupRecoveryRead) _then) = _$StartupRecoveryReadCopyWithImpl;
@useResult
$Res call({
 ReadText backupPath, ReadText reason, int createdAt
});


$ReadTextCopyWith<$Res> get backupPath;$ReadTextCopyWith<$Res> get reason;

}
/// @nodoc
class _$StartupRecoveryReadCopyWithImpl<$Res>
    implements $StartupRecoveryReadCopyWith<$Res> {
  _$StartupRecoveryReadCopyWithImpl(this._self, this._then);

  final StartupRecoveryRead _self;
  final $Res Function(StartupRecoveryRead) _then;

/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? backupPath = null,Object? reason = null,Object? createdAt = null,}) {
  return _then(StartupRecoveryRead(
backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as ReadText,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ReadText,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get backupPath {

  return $ReadTextCopyWith<$Res>(_self.backupPath, (value) {
    return _then(_self.copyWith(backupPath: value));
  });
}/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get reason {

  return $ReadTextCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartupRecoveryRead].
extension StartupRecoveryReadPatterns on StartupRecoveryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupRecoveryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupRecoveryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupRecoveryRead value)  $default,){
final _that = this;
switch (_that) {
case _StartupRecoveryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupRecoveryRead value)?  $default,){
final _that = this;
switch (_that) {
case _StartupRecoveryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText backupPath,  ReadText reason,  int createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupRecoveryRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText backupPath,  ReadText reason,  int createdAt)  $default,) {final _that = this;
switch (_that) {
case _StartupRecoveryRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText backupPath,  ReadText reason,  int createdAt)?  $default,) {final _that = this;
switch (_that) {
case _StartupRecoveryRead() when $default != null:
return $default(_that.backupPath,_that.reason,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _StartupRecoveryRead implements StartupRecoveryRead {
  const _StartupRecoveryRead({required this.backupPath, required this.reason, required this.createdAt});


@override final  ReadText backupPath;
@override final  ReadText reason;
@override final  int createdAt;

/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupRecoveryReadCopyWith<_StartupRecoveryRead> get copyWith => __$StartupRecoveryReadCopyWithImpl<_StartupRecoveryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupRecoveryRead&&(identical(other.backupPath, backupPath) || other.backupPath == backupPath)&&(identical(other.reason, reason) || other.reason == reason)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,backupPath,reason,createdAt);
}



}

/// @nodoc
abstract mixin class _$StartupRecoveryReadCopyWith<$Res> implements $StartupRecoveryReadCopyWith<$Res> {
  factory _$StartupRecoveryReadCopyWith(_StartupRecoveryRead value, $Res Function(_StartupRecoveryRead) _then) = __$StartupRecoveryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText backupPath, ReadText reason, int createdAt
});


@override $ReadTextCopyWith<$Res> get backupPath;@override $ReadTextCopyWith<$Res> get reason;

}
/// @nodoc
class __$StartupRecoveryReadCopyWithImpl<$Res>
    implements _$StartupRecoveryReadCopyWith<$Res> {
  __$StartupRecoveryReadCopyWithImpl(this._self, this._then);

  final _StartupRecoveryRead _self;
  final $Res Function(_StartupRecoveryRead) _then;

/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? backupPath = null,Object? reason = null,Object? createdAt = null,}) {
  return _then(_StartupRecoveryRead(
backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as ReadText,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ReadText,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get backupPath {

  return $ReadTextCopyWith<$Res>(_self.backupPath, (value) {
    return _then(_self.copyWith(backupPath: value));
  });
}/// Create a copy of StartupRecoveryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get reason {

  return $ReadTextCopyWith<$Res>(_self.reason, (value) {
    return _then(_self.copyWith(reason: value));
  });
}
}

/// @nodoc
mixin _$StartupActiveTurnRead {

 ReadText get threadId; ReadText get turnId;
/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupActiveTurnReadCopyWith<StartupActiveTurnRead> get copyWith => _$StartupActiveTurnReadCopyWithImpl<StartupActiveTurnRead>(this as StartupActiveTurnRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupActiveTurnRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupActiveTurnRead&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.turnId, _this.turnId) || other.turnId == _this.turnId));
}


@override
int get hashCode {
  final _this = this as StartupActiveTurnRead;
  return Object.hash(runtimeType,_this.threadId,_this.turnId);
}

@override
String toString() {
  final _this = this as StartupActiveTurnRead;
  return 'StartupActiveTurnRead(threadId: ${_this.threadId}, turnId: ${_this.turnId})';
}


}

/// @nodoc
abstract mixin class $StartupActiveTurnReadCopyWith<$Res>  {
  factory $StartupActiveTurnReadCopyWith(StartupActiveTurnRead value, $Res Function(StartupActiveTurnRead) _then) = _$StartupActiveTurnReadCopyWithImpl;
@useResult
$Res call({
 ReadText threadId, ReadText turnId
});


$ReadTextCopyWith<$Res> get threadId;$ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class _$StartupActiveTurnReadCopyWithImpl<$Res>
    implements $StartupActiveTurnReadCopyWith<$Res> {
  _$StartupActiveTurnReadCopyWithImpl(this._self, this._then);

  final StartupActiveTurnRead _self;
  final $Res Function(StartupActiveTurnRead) _then;

/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? turnId = null,}) {
  return _then(StartupActiveTurnRead(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartupActiveTurnRead].
extension StartupActiveTurnReadPatterns on StartupActiveTurnRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupActiveTurnRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupActiveTurnRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupActiveTurnRead value)  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupActiveTurnRead value)?  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText threadId,  ReadText turnId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupActiveTurnRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText threadId,  ReadText turnId)  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText threadId,  ReadText turnId)?  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnRead() when $default != null:
return $default(_that.threadId,_that.turnId);case _:
  return null;

}
}

}

/// @nodoc


class _StartupActiveTurnRead implements StartupActiveTurnRead {
  const _StartupActiveTurnRead({required this.threadId, required this.turnId});


@override final  ReadText threadId;
@override final  ReadText turnId;

/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupActiveTurnReadCopyWith<_StartupActiveTurnRead> get copyWith => __$StartupActiveTurnReadCopyWithImpl<_StartupActiveTurnRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupActiveTurnRead&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.turnId, turnId) || other.turnId == turnId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,turnId);
}

@override
String toString() {
    return 'StartupActiveTurnRead(threadId: $threadId, turnId: $turnId)';
}


}

/// @nodoc
abstract mixin class _$StartupActiveTurnReadCopyWith<$Res> implements $StartupActiveTurnReadCopyWith<$Res> {
  factory _$StartupActiveTurnReadCopyWith(_StartupActiveTurnRead value, $Res Function(_StartupActiveTurnRead) _then) = __$StartupActiveTurnReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText threadId, ReadText turnId
});


@override $ReadTextCopyWith<$Res> get threadId;@override $ReadTextCopyWith<$Res> get turnId;

}
/// @nodoc
class __$StartupActiveTurnReadCopyWithImpl<$Res>
    implements _$StartupActiveTurnReadCopyWith<$Res> {
  __$StartupActiveTurnReadCopyWithImpl(this._self, this._then);

  final _StartupActiveTurnRead _self;
  final $Res Function(_StartupActiveTurnRead) _then;

/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? turnId = null,}) {
  return _then(_StartupActiveTurnRead(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as ReadText,turnId: null == turnId ? _self.turnId : turnId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get threadId {

  return $ReadTextCopyWith<$Res>(_self.threadId, (value) {
    return _then(_self.copyWith(threadId: value));
  });
}/// Create a copy of StartupActiveTurnRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get turnId {

  return $ReadTextCopyWith<$Res>(_self.turnId, (value) {
    return _then(_self.copyWith(turnId: value));
  });
}
}

/// @nodoc
mixin _$RuntimeStartupReadHeader {

 RuntimeStartupScopeIdentity get scope; RuntimeStartupReadRef get reference; int get revision; RuntimeStateRead get state; StartupRecoveryRead? get startupRecovery; int get activeTurnCount;
/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RuntimeStartupReadHeaderCopyWith<RuntimeStartupReadHeader> get copyWith => _$RuntimeStartupReadHeaderCopyWithImpl<RuntimeStartupReadHeader>(this as RuntimeStartupReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RuntimeStartupReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RuntimeStartupReadHeader&&(identical(other.scope, _this.scope) || other.scope == _this.scope)&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.startupRecovery, _this.startupRecovery) || other.startupRecovery == _this.startupRecovery)&&(identical(other.activeTurnCount, _this.activeTurnCount) || other.activeTurnCount == _this.activeTurnCount));
}


@override
int get hashCode {
  final _this = this as RuntimeStartupReadHeader;
  return Object.hash(runtimeType,_this.scope,_this.reference,_this.revision,_this.state,_this.startupRecovery,_this.activeTurnCount);
}



}

/// @nodoc
abstract mixin class $RuntimeStartupReadHeaderCopyWith<$Res>  {
  factory $RuntimeStartupReadHeaderCopyWith(RuntimeStartupReadHeader value, $Res Function(RuntimeStartupReadHeader) _then) = _$RuntimeStartupReadHeaderCopyWithImpl;
@useResult
$Res call({
 RuntimeStartupScopeIdentity scope, RuntimeStartupReadRef reference, int revision, RuntimeStateRead state, StartupRecoveryRead? startupRecovery, int activeTurnCount
});


$RuntimeStartupScopeIdentityCopyWith<$Res> get scope;$RuntimeStartupReadRefCopyWith<$Res> get reference;$RuntimeStateReadCopyWith<$Res> get state;$StartupRecoveryReadCopyWith<$Res>? get startupRecovery;

}
/// @nodoc
class _$RuntimeStartupReadHeaderCopyWithImpl<$Res>
    implements $RuntimeStartupReadHeaderCopyWith<$Res> {
  _$RuntimeStartupReadHeaderCopyWithImpl(this._self, this._then);

  final RuntimeStartupReadHeader _self;
  final $Res Function(RuntimeStartupReadHeader) _then;

/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scope = null,Object? reference = null,Object? revision = null,Object? state = null,Object? startupRecovery = freezed,Object? activeTurnCount = null,}) {
  return _then(RuntimeStartupReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RuntimeStartupScopeIdentity,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as RuntimeStateRead,startupRecovery: freezed == startupRecovery ? _self.startupRecovery : startupRecovery // ignore: cast_nullable_to_non_nullable
as StartupRecoveryRead?,activeTurnCount: null == activeTurnCount ? _self.activeTurnCount : activeTurnCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupScopeIdentityCopyWith<$Res> get scope {

  return $RuntimeStartupScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get reference {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStateReadCopyWith<$Res> get state {

  return $RuntimeStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupRecoveryReadCopyWith<$Res>? get startupRecovery {
    if (_self.startupRecovery == null) {
    return null;
  }

  return $StartupRecoveryReadCopyWith<$Res>(_self.startupRecovery!, (value) {
    return _then(_self.copyWith(startupRecovery: value));
  });
}
}


/// Adds pattern-matching-related methods to [RuntimeStartupReadHeader].
extension RuntimeStartupReadHeaderPatterns on RuntimeStartupReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RuntimeStartupReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RuntimeStartupReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RuntimeStartupReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RuntimeStartupScopeIdentity scope,  RuntimeStartupReadRef reference,  int revision,  RuntimeStateRead state,  StartupRecoveryRead? startupRecovery,  int activeTurnCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader() when $default != null:
return $default(_that.scope,_that.reference,_that.revision,_that.state,_that.startupRecovery,_that.activeTurnCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RuntimeStartupScopeIdentity scope,  RuntimeStartupReadRef reference,  int revision,  RuntimeStateRead state,  StartupRecoveryRead? startupRecovery,  int activeTurnCount)  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader():
return $default(_that.scope,_that.reference,_that.revision,_that.state,_that.startupRecovery,_that.activeTurnCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RuntimeStartupScopeIdentity scope,  RuntimeStartupReadRef reference,  int revision,  RuntimeStateRead state,  StartupRecoveryRead? startupRecovery,  int activeTurnCount)?  $default,) {final _that = this;
switch (_that) {
case _RuntimeStartupReadHeader() when $default != null:
return $default(_that.scope,_that.reference,_that.revision,_that.state,_that.startupRecovery,_that.activeTurnCount);case _:
  return null;

}
}

}

/// @nodoc


class _RuntimeStartupReadHeader implements RuntimeStartupReadHeader {
  const _RuntimeStartupReadHeader({required this.scope, required this.reference, required this.revision, required this.state, required this.startupRecovery, required this.activeTurnCount});


@override final  RuntimeStartupScopeIdentity scope;
@override final  RuntimeStartupReadRef reference;
@override final  int revision;
@override final  RuntimeStateRead state;
@override final  StartupRecoveryRead? startupRecovery;
@override final  int activeTurnCount;

/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RuntimeStartupReadHeaderCopyWith<_RuntimeStartupReadHeader> get copyWith => __$RuntimeStartupReadHeaderCopyWithImpl<_RuntimeStartupReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RuntimeStartupReadHeader&&(identical(other.scope, scope) || other.scope == scope)&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.state, state) || other.state == state)&&(identical(other.startupRecovery, startupRecovery) || other.startupRecovery == startupRecovery)&&(identical(other.activeTurnCount, activeTurnCount) || other.activeTurnCount == activeTurnCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scope,reference,revision,state,startupRecovery,activeTurnCount);
}



}

/// @nodoc
abstract mixin class _$RuntimeStartupReadHeaderCopyWith<$Res> implements $RuntimeStartupReadHeaderCopyWith<$Res> {
  factory _$RuntimeStartupReadHeaderCopyWith(_RuntimeStartupReadHeader value, $Res Function(_RuntimeStartupReadHeader) _then) = __$RuntimeStartupReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 RuntimeStartupScopeIdentity scope, RuntimeStartupReadRef reference, int revision, RuntimeStateRead state, StartupRecoveryRead? startupRecovery, int activeTurnCount
});


@override $RuntimeStartupScopeIdentityCopyWith<$Res> get scope;@override $RuntimeStartupReadRefCopyWith<$Res> get reference;@override $RuntimeStateReadCopyWith<$Res> get state;@override $StartupRecoveryReadCopyWith<$Res>? get startupRecovery;

}
/// @nodoc
class __$RuntimeStartupReadHeaderCopyWithImpl<$Res>
    implements _$RuntimeStartupReadHeaderCopyWith<$Res> {
  __$RuntimeStartupReadHeaderCopyWithImpl(this._self, this._then);

  final _RuntimeStartupReadHeader _self;
  final $Res Function(_RuntimeStartupReadHeader) _then;

/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scope = null,Object? reference = null,Object? revision = null,Object? state = null,Object? startupRecovery = freezed,Object? activeTurnCount = null,}) {
  return _then(_RuntimeStartupReadHeader(
scope: null == scope ? _self.scope : scope // ignore: cast_nullable_to_non_nullable
as RuntimeStartupScopeIdentity,reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as RuntimeStartupReadRef,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as RuntimeStateRead,startupRecovery: freezed == startupRecovery ? _self.startupRecovery : startupRecovery // ignore: cast_nullable_to_non_nullable
as StartupRecoveryRead?,activeTurnCount: null == activeTurnCount ? _self.activeTurnCount : activeTurnCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupScopeIdentityCopyWith<$Res> get scope {

  return $RuntimeStartupScopeIdentityCopyWith<$Res>(_self.scope, (value) {
    return _then(_self.copyWith(scope: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStartupReadRefCopyWith<$Res> get reference {

  return $RuntimeStartupReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RuntimeStateReadCopyWith<$Res> get state {

  return $RuntimeStateReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}/// Create a copy of RuntimeStartupReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartupRecoveryReadCopyWith<$Res>? get startupRecovery {
    if (_self.startupRecovery == null) {
    return null;
  }

  return $StartupRecoveryReadCopyWith<$Res>(_self.startupRecovery!, (value) {
    return _then(_self.copyWith(startupRecovery: value));
  });
}
}

/// @nodoc
mixin _$StartupActiveTurnReadPage {

 int get offset; int get total; List<StartupActiveTurnRead> get items; int? get nextOffset;
/// Create a copy of StartupActiveTurnReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartupActiveTurnReadPageCopyWith<StartupActiveTurnReadPage> get copyWith => _$StartupActiveTurnReadPageCopyWithImpl<StartupActiveTurnReadPage>(this as StartupActiveTurnReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartupActiveTurnReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartupActiveTurnReadPage&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as StartupActiveTurnReadPage;
  return Object.hash(runtimeType,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as StartupActiveTurnReadPage;
  return 'StartupActiveTurnReadPage(offset: ${_this.offset}, total: ${_this.total}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $StartupActiveTurnReadPageCopyWith<$Res>  {
  factory $StartupActiveTurnReadPageCopyWith(StartupActiveTurnReadPage value, $Res Function(StartupActiveTurnReadPage) _then) = _$StartupActiveTurnReadPageCopyWithImpl;
@useResult
$Res call({
 int offset, int total, List<StartupActiveTurnRead> items, int? nextOffset
});




}
/// @nodoc
class _$StartupActiveTurnReadPageCopyWithImpl<$Res>
    implements $StartupActiveTurnReadPageCopyWith<$Res> {
  _$StartupActiveTurnReadPageCopyWithImpl(this._self, this._then);

  final StartupActiveTurnReadPage _self;
  final $Res Function(StartupActiveTurnReadPage) _then;

/// Create a copy of StartupActiveTurnReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(StartupActiveTurnReadPage(
offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<StartupActiveTurnRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [StartupActiveTurnReadPage].
extension StartupActiveTurnReadPagePatterns on StartupActiveTurnReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartupActiveTurnReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartupActiveTurnReadPage value)  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartupActiveTurnReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int offset,  int total,  List<StartupActiveTurnRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage() when $default != null:
return $default(_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int offset,  int total,  List<StartupActiveTurnRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage():
return $default(_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int offset,  int total,  List<StartupActiveTurnRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _StartupActiveTurnReadPage() when $default != null:
return $default(_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _StartupActiveTurnReadPage implements StartupActiveTurnReadPage {
  const _StartupActiveTurnReadPage({required this.offset, required this.total, required  List<StartupActiveTurnRead> items, required this.nextOffset}): _items = items;


@override final  int offset;
@override final  int total;
 final  List<StartupActiveTurnRead> _items;
@override List<StartupActiveTurnRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of StartupActiveTurnReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartupActiveTurnReadPageCopyWith<_StartupActiveTurnReadPage> get copyWith => __$StartupActiveTurnReadPageCopyWithImpl<_StartupActiveTurnReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartupActiveTurnReadPage&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'StartupActiveTurnReadPage(offset: $offset, total: $total, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$StartupActiveTurnReadPageCopyWith<$Res> implements $StartupActiveTurnReadPageCopyWith<$Res> {
  factory _$StartupActiveTurnReadPageCopyWith(_StartupActiveTurnReadPage value, $Res Function(_StartupActiveTurnReadPage) _then) = __$StartupActiveTurnReadPageCopyWithImpl;
@override @useResult
$Res call({
 int offset, int total, List<StartupActiveTurnRead> items, int? nextOffset
});




}
/// @nodoc
class __$StartupActiveTurnReadPageCopyWithImpl<$Res>
    implements _$StartupActiveTurnReadPageCopyWith<$Res> {
  __$StartupActiveTurnReadPageCopyWithImpl(this._self, this._then);

  final _StartupActiveTurnReadPage _self;
  final $Res Function(_StartupActiveTurnReadPage) _then;

/// Create a copy of StartupActiveTurnReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_StartupActiveTurnReadPage(
offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<StartupActiveTurnRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
