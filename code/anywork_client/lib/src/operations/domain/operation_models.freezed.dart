// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'operation_models.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Unit {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is Unit);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Unit()';
}


}

/// @nodoc
class $UnitCopyWith<$Res>  {
$UnitCopyWith(Unit _, $Res Function(Unit) __);
}


/// Adds pattern-matching-related methods to [Unit].
extension UnitPatterns on Unit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Unit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Unit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Unit value)  $default,){
final _that = this;
switch (_that) {
case _Unit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Unit value)?  $default,){
final _that = this;
switch (_that) {
case _Unit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function()?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Unit() when $default != null:
return $default();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function()  $default,) {final _that = this;
switch (_that) {
case _Unit():
return $default();case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function()?  $default,) {final _that = this;
switch (_that) {
case _Unit() when $default != null:
return $default();case _:
  return null;

}
}

}

/// @nodoc


class _Unit implements Unit {
  const _Unit();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Unit);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'Unit()';
}


}




/// @nodoc
mixin _$CommitReceipt {


/// Create a copy of CommitReceipt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<CommitReceipt> get copyWith => _$CommitReceiptCopyWithImpl<CommitReceipt>(this as CommitReceipt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CommitReceipt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CommitReceipt&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.disposition, _this.disposition) || other.disposition == _this.disposition)&&const DeepCollectionEquality().equals(other.targets, _this.targets)&&(identical(other.effect, _this.effect) || other.effect == _this.effect)&&(identical(other.effective, _this.effective) || other.effective == _this.effective)&&(identical(other.durable, _this.durable) || other.durable == _this.durable)&&(identical(other.requiresIdentityObservation, _this.requiresIdentityObservation) || other.requiresIdentityObservation == _this.requiresIdentityObservation));
}


@override
int get hashCode {
  final _this = this as CommitReceipt;
  return Object.hash(runtimeType,_this.operationId,_this.disposition,const DeepCollectionEquality().hash(_this.targets),_this.effect,_this.effective,_this.durable,_this.requiresIdentityObservation);
}

@override
String toString() {
  final _this = this as CommitReceipt;
  return 'CommitReceipt(operationId: ${_this.operationId}, disposition: ${_this.disposition}, targets: ${_this.targets}, effect: ${_this.effect}, effective: ${_this.effective}, durable: ${_this.durable}, requiresIdentityObservation: ${_this.requiresIdentityObservation})';
}


}

/// @nodoc
abstract mixin class $CommitReceiptCopyWith<$Res>  {
  factory $CommitReceiptCopyWith(CommitReceipt value, $Res Function(CommitReceipt) _then) = _$CommitReceiptCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, CommitDisposition disposition, List<ObservationStamp> targets, EffectPoint effect, bool effective, bool durable, bool requiresIdentityObservation
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$CommitReceiptCopyWithImpl<$Res>
    implements $CommitReceiptCopyWith<$Res> {
  _$CommitReceiptCopyWithImpl(this._self, this._then);

  final CommitReceipt _self;
  final $Res Function(CommitReceipt) _then;

/// Create a copy of CommitReceipt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? disposition = null,Object? targets = null,Object? effect = null,Object? effective = null,Object? durable = null,Object? requiresIdentityObservation = null,}) {
  return _then(CommitReceipt(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,disposition: null == disposition ? _self.disposition : disposition // ignore: cast_nullable_to_non_nullable
as CommitDisposition,targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as List<ObservationStamp>,effect: null == effect ? _self.effect : effect // ignore: cast_nullable_to_non_nullable
as EffectPoint,effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as bool,durable: null == durable ? _self.durable : durable // ignore: cast_nullable_to_non_nullable
as bool,requiresIdentityObservation: null == requiresIdentityObservation ? _self.requiresIdentityObservation : requiresIdentityObservation // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of CommitReceipt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [CommitReceipt].
extension CommitReceiptPatterns on CommitReceipt {
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
mixin _$CommandResult<T> {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CommandResult<T>);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $CommandResultCopyWith<T,$Res>  {
$CommandResultCopyWith(CommandResult<T> _, $Res Function(CommandResult<T>) __);
}


/// Adds pattern-matching-related methods to [CommandResult].
extension CommandResultPatterns<T> on CommandResult<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( CommittedCommandResult<T> value)?  committed,TResult Function( AcknowledgedCommandResult<T> value)?  acknowledged,TResult Function( RejectedCommandResult<T> value)?  rejected,TResult Function( UnknownOutcomeCommandResult<T> value)?  unknownOutcome,TResult Function( SyncFailedCommandResult<T> value)?  syncFailed,TResult Function( AcknowledgedSyncFailedCommandResult<T> value)?  acknowledgedSyncFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case CommittedCommandResult() when committed != null:
return committed(_that);case AcknowledgedCommandResult() when acknowledged != null:
return acknowledged(_that);case RejectedCommandResult() when rejected != null:
return rejected(_that);case UnknownOutcomeCommandResult() when unknownOutcome != null:
return unknownOutcome(_that);case SyncFailedCommandResult() when syncFailed != null:
return syncFailed(_that);case AcknowledgedSyncFailedCommandResult() when acknowledgedSyncFailed != null:
return acknowledgedSyncFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( CommittedCommandResult<T> value)  committed,required TResult Function( AcknowledgedCommandResult<T> value)  acknowledged,required TResult Function( RejectedCommandResult<T> value)  rejected,required TResult Function( UnknownOutcomeCommandResult<T> value)  unknownOutcome,required TResult Function( SyncFailedCommandResult<T> value)  syncFailed,required TResult Function( AcknowledgedSyncFailedCommandResult<T> value)  acknowledgedSyncFailed,}){
final _that = this;
switch (_that) {
case CommittedCommandResult():
return committed(_that);case AcknowledgedCommandResult():
return acknowledged(_that);case RejectedCommandResult():
return rejected(_that);case UnknownOutcomeCommandResult():
return unknownOutcome(_that);case SyncFailedCommandResult():
return syncFailed(_that);case AcknowledgedSyncFailedCommandResult():
return acknowledgedSyncFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( CommittedCommandResult<T> value)?  committed,TResult? Function( AcknowledgedCommandResult<T> value)?  acknowledged,TResult? Function( RejectedCommandResult<T> value)?  rejected,TResult? Function( UnknownOutcomeCommandResult<T> value)?  unknownOutcome,TResult? Function( SyncFailedCommandResult<T> value)?  syncFailed,TResult? Function( AcknowledgedSyncFailedCommandResult<T> value)?  acknowledgedSyncFailed,}){
final _that = this;
switch (_that) {
case CommittedCommandResult() when committed != null:
return committed(_that);case AcknowledgedCommandResult() when acknowledged != null:
return acknowledged(_that);case RejectedCommandResult() when rejected != null:
return rejected(_that);case UnknownOutcomeCommandResult() when unknownOutcome != null:
return unknownOutcome(_that);case SyncFailedCommandResult() when syncFailed != null:
return syncFailed(_that);case AcknowledgedSyncFailedCommandResult() when acknowledgedSyncFailed != null:
return acknowledgedSyncFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( T value,  CommitReceipt receipt)?  committed,TResult Function( T value)?  acknowledged,TResult Function( StudioFailure error)?  rejected,TResult Function( StudioFailure error)?  unknownOutcome,TResult Function( T? value,  CommitReceipt receipt,  StudioFailure error)?  syncFailed,TResult Function( T? value,  StudioFailure error)?  acknowledgedSyncFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case CommittedCommandResult() when committed != null:
return committed(_that.value,_that.receipt);case AcknowledgedCommandResult() when acknowledged != null:
return acknowledged(_that.value);case RejectedCommandResult() when rejected != null:
return rejected(_that.error);case UnknownOutcomeCommandResult() when unknownOutcome != null:
return unknownOutcome(_that.error);case SyncFailedCommandResult() when syncFailed != null:
return syncFailed(_that.value,_that.receipt,_that.error);case AcknowledgedSyncFailedCommandResult() when acknowledgedSyncFailed != null:
return acknowledgedSyncFailed(_that.value,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( T value,  CommitReceipt receipt)  committed,required TResult Function( T value)  acknowledged,required TResult Function( StudioFailure error)  rejected,required TResult Function( StudioFailure error)  unknownOutcome,required TResult Function( T? value,  CommitReceipt receipt,  StudioFailure error)  syncFailed,required TResult Function( T? value,  StudioFailure error)  acknowledgedSyncFailed,}) {final _that = this;
switch (_that) {
case CommittedCommandResult():
return committed(_that.value,_that.receipt);case AcknowledgedCommandResult():
return acknowledged(_that.value);case RejectedCommandResult():
return rejected(_that.error);case UnknownOutcomeCommandResult():
return unknownOutcome(_that.error);case SyncFailedCommandResult():
return syncFailed(_that.value,_that.receipt,_that.error);case AcknowledgedSyncFailedCommandResult():
return acknowledgedSyncFailed(_that.value,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( T value,  CommitReceipt receipt)?  committed,TResult? Function( T value)?  acknowledged,TResult? Function( StudioFailure error)?  rejected,TResult? Function( StudioFailure error)?  unknownOutcome,TResult? Function( T? value,  CommitReceipt receipt,  StudioFailure error)?  syncFailed,TResult? Function( T? value,  StudioFailure error)?  acknowledgedSyncFailed,}) {final _that = this;
switch (_that) {
case CommittedCommandResult() when committed != null:
return committed(_that.value,_that.receipt);case AcknowledgedCommandResult() when acknowledged != null:
return acknowledged(_that.value);case RejectedCommandResult() when rejected != null:
return rejected(_that.error);case UnknownOutcomeCommandResult() when unknownOutcome != null:
return unknownOutcome(_that.error);case SyncFailedCommandResult() when syncFailed != null:
return syncFailed(_that.value,_that.receipt,_that.error);case AcknowledgedSyncFailedCommandResult() when acknowledgedSyncFailed != null:
return acknowledgedSyncFailed(_that.value,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class CommittedCommandResult<T> implements CommandResult<T> {
  const CommittedCommandResult({required this.value, required this.receipt});


 final  T value;
 final  CommitReceipt receipt;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CommittedCommandResultCopyWith<T, CommittedCommandResult<T>> get copyWith => _$CommittedCommandResultCopyWithImpl<T, CommittedCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CommittedCommandResult<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.receipt, receipt) || other.receipt == receipt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value),receipt);
}



}

/// @nodoc
abstract mixin class $CommittedCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $CommittedCommandResultCopyWith(CommittedCommandResult<T> value, $Res Function(CommittedCommandResult<T>) _then) = _$CommittedCommandResultCopyWithImpl;
@useResult
$Res call({
 T value, CommitReceipt receipt
});


$CommitReceiptCopyWith<$Res> get receipt;

}
/// @nodoc
class _$CommittedCommandResultCopyWithImpl<T,$Res>
    implements $CommittedCommandResultCopyWith<T, $Res> {
  _$CommittedCommandResultCopyWithImpl(this._self, this._then);

  final CommittedCommandResult<T> _self;
  final $Res Function(CommittedCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,Object? receipt = null,}) {
  return _then(CommittedCommandResult<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,
  ));
}

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}
}

/// @nodoc


class AcknowledgedCommandResult<T> implements CommandResult<T> {
  const AcknowledgedCommandResult({required this.value});


 final  T value;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcknowledgedCommandResultCopyWith<T, AcknowledgedCommandResult<T>> get copyWith => _$AcknowledgedCommandResultCopyWithImpl<T, AcknowledgedCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcknowledgedCommandResult<T>&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class $AcknowledgedCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $AcknowledgedCommandResultCopyWith(AcknowledgedCommandResult<T> value, $Res Function(AcknowledgedCommandResult<T>) _then) = _$AcknowledgedCommandResultCopyWithImpl;
@useResult
$Res call({
 T value
});




}
/// @nodoc
class _$AcknowledgedCommandResultCopyWithImpl<T,$Res>
    implements $AcknowledgedCommandResultCopyWith<T, $Res> {
  _$AcknowledgedCommandResultCopyWithImpl(this._self, this._then);

  final AcknowledgedCommandResult<T> _self;
  final $Res Function(AcknowledgedCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,}) {
  return _then(AcknowledgedCommandResult<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class RejectedCommandResult<T> implements CommandResult<T> {
  const RejectedCommandResult({required this.error});


 final  StudioFailure error;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RejectedCommandResultCopyWith<T, RejectedCommandResult<T>> get copyWith => _$RejectedCommandResultCopyWithImpl<T, RejectedCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RejectedCommandResult<T>&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $RejectedCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $RejectedCommandResultCopyWith(RejectedCommandResult<T> value, $Res Function(RejectedCommandResult<T>) _then) = _$RejectedCommandResultCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$RejectedCommandResultCopyWithImpl<T,$Res>
    implements $RejectedCommandResultCopyWith<T, $Res> {
  _$RejectedCommandResultCopyWithImpl(this._self, this._then);

  final RejectedCommandResult<T> _self;
  final $Res Function(RejectedCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(RejectedCommandResult<T>(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandResult
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


class UnknownOutcomeCommandResult<T> implements CommandResult<T> {
  const UnknownOutcomeCommandResult({required this.error});


 final  StudioFailure error;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownOutcomeCommandResultCopyWith<T, UnknownOutcomeCommandResult<T>> get copyWith => _$UnknownOutcomeCommandResultCopyWithImpl<T, UnknownOutcomeCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownOutcomeCommandResult<T>&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $UnknownOutcomeCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $UnknownOutcomeCommandResultCopyWith(UnknownOutcomeCommandResult<T> value, $Res Function(UnknownOutcomeCommandResult<T>) _then) = _$UnknownOutcomeCommandResultCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$UnknownOutcomeCommandResultCopyWithImpl<T,$Res>
    implements $UnknownOutcomeCommandResultCopyWith<T, $Res> {
  _$UnknownOutcomeCommandResultCopyWithImpl(this._self, this._then);

  final UnknownOutcomeCommandResult<T> _self;
  final $Res Function(UnknownOutcomeCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(UnknownOutcomeCommandResult<T>(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandResult
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


class SyncFailedCommandResult<T> implements CommandResult<T> {
  const SyncFailedCommandResult({required this.value, required this.receipt, required this.error});


 final  T? value;
 final  CommitReceipt receipt;
 final  StudioFailure error;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SyncFailedCommandResultCopyWith<T, SyncFailedCommandResult<T>> get copyWith => _$SyncFailedCommandResultCopyWithImpl<T, SyncFailedCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SyncFailedCommandResult<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value),receipt,error);
}



}

/// @nodoc
abstract mixin class $SyncFailedCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $SyncFailedCommandResultCopyWith(SyncFailedCommandResult<T> value, $Res Function(SyncFailedCommandResult<T>) _then) = _$SyncFailedCommandResultCopyWithImpl;
@useResult
$Res call({
 T? value, CommitReceipt receipt, StudioFailure error
});


$CommitReceiptCopyWith<$Res> get receipt;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$SyncFailedCommandResultCopyWithImpl<T,$Res>
    implements $SyncFailedCommandResultCopyWith<T, $Res> {
  _$SyncFailedCommandResultCopyWithImpl(this._self, this._then);

  final SyncFailedCommandResult<T> _self;
  final $Res Function(SyncFailedCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,Object? receipt = null,Object? error = null,}) {
  return _then(SyncFailedCommandResult<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T?,receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of CommandResult
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


class AcknowledgedSyncFailedCommandResult<T> implements CommandResult<T> {
  const AcknowledgedSyncFailedCommandResult({required this.value, required this.error});


 final  T? value;
 final  StudioFailure error;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcknowledgedSyncFailedCommandResultCopyWith<T, AcknowledgedSyncFailedCommandResult<T>> get copyWith => _$AcknowledgedSyncFailedCommandResultCopyWithImpl<T, AcknowledgedSyncFailedCommandResult<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcknowledgedSyncFailedCommandResult<T>&&const DeepCollectionEquality().equals(other.value, value)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(value),error);
}



}

/// @nodoc
abstract mixin class $AcknowledgedSyncFailedCommandResultCopyWith<T,$Res> implements $CommandResultCopyWith<T, $Res> {
  factory $AcknowledgedSyncFailedCommandResultCopyWith(AcknowledgedSyncFailedCommandResult<T> value, $Res Function(AcknowledgedSyncFailedCommandResult<T>) _then) = _$AcknowledgedSyncFailedCommandResultCopyWithImpl;
@useResult
$Res call({
 T? value, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AcknowledgedSyncFailedCommandResultCopyWithImpl<T,$Res>
    implements $AcknowledgedSyncFailedCommandResultCopyWith<T, $Res> {
  _$AcknowledgedSyncFailedCommandResultCopyWithImpl(this._self, this._then);

  final AcknowledgedSyncFailedCommandResult<T> _self;
  final $Res Function(AcknowledgedSyncFailedCommandResult<T>) _then;

/// Create a copy of CommandResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = freezed,Object? error = null,}) {
  return _then(AcknowledgedSyncFailedCommandResult<T>(
value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T?,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of CommandResult
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
mixin _$OperationState {

 OperationId get id; String get target; DraftStamp? get draft; CommitReceipt? get receipt; bool get acknowledged; bool get observed; bool get effective; bool get durable; OperationFailurePhase? get failurePhase; StudioFailure? get error; StudioFailure? get evidenceError;
/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OperationStateCopyWith<OperationState> get copyWith => _$OperationStateCopyWithImpl<OperationState>(this as OperationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as OperationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is OperationState&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.draft, _this.draft) || other.draft == _this.draft)&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.acknowledged, _this.acknowledged) || other.acknowledged == _this.acknowledged)&&(identical(other.observed, _this.observed) || other.observed == _this.observed)&&(identical(other.effective, _this.effective) || other.effective == _this.effective)&&(identical(other.durable, _this.durable) || other.durable == _this.durable)&&(identical(other.failurePhase, _this.failurePhase) || other.failurePhase == _this.failurePhase)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.evidenceError, _this.evidenceError) || other.evidenceError == _this.evidenceError));
}


@override
int get hashCode {
  final _this = this as OperationState;
  return Object.hash(runtimeType,_this.id,_this.target,_this.draft,_this.receipt,_this.acknowledged,_this.observed,_this.effective,_this.durable,_this.failurePhase,_this.error,_this.evidenceError);
}



}

/// @nodoc
abstract mixin class $OperationStateCopyWith<$Res>  {
  factory $OperationStateCopyWith(OperationState value, $Res Function(OperationState) _then) = _$OperationStateCopyWithImpl;
@useResult
$Res call({
 OperationId id, String target, DraftStamp? draft, CommitReceipt? receipt, bool acknowledged, bool observed, bool effective, bool durable, OperationFailurePhase? failurePhase, StudioFailure? error, StudioFailure? evidenceError
});


$OperationIdCopyWith<$Res> get id;$DraftStampCopyWith<$Res>? get draft;$CommitReceiptCopyWith<$Res>? get receipt;$StudioFailureCopyWith<$Res>? get error;$StudioFailureCopyWith<$Res>? get evidenceError;

}
/// @nodoc
class _$OperationStateCopyWithImpl<$Res>
    implements $OperationStateCopyWith<$Res> {
  _$OperationStateCopyWithImpl(this._self, this._then);

  final OperationState _self;
  final $Res Function(OperationState) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? target = null,Object? draft = freezed,Object? receipt = freezed,Object? acknowledged = null,Object? observed = null,Object? effective = null,Object? durable = null,Object? failurePhase = freezed,Object? error = freezed,Object? evidenceError = freezed,}) {
  return _then(OperationState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as OperationId,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as DraftStamp?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt?,acknowledged: null == acknowledged ? _self.acknowledged : acknowledged // ignore: cast_nullable_to_non_nullable
as bool,observed: null == observed ? _self.observed : observed // ignore: cast_nullable_to_non_nullable
as bool,effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as bool,durable: null == durable ? _self.durable : durable // ignore: cast_nullable_to_non_nullable
as bool,failurePhase: freezed == failurePhase ? _self.failurePhase : failurePhase // ignore: cast_nullable_to_non_nullable
as OperationFailurePhase?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,evidenceError: freezed == evidenceError ? _self.evidenceError : evidenceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get id {

  return $OperationIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftStampCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $DraftStampCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res>? get receipt {
    if (_self.receipt == null) {
    return null;
  }

  return $CommitReceiptCopyWith<$Res>(_self.receipt!, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of OperationState
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
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get evidenceError {
    if (_self.evidenceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.evidenceError!, (value) {
    return _then(_self.copyWith(evidenceError: value));
  });
}
}


/// Adds pattern-matching-related methods to [OperationState].
extension OperationStatePatterns on OperationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _OperationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _OperationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _OperationState value)  $default,){
final _that = this;
switch (_that) {
case _OperationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _OperationState value)?  $default,){
final _that = this;
switch (_that) {
case _OperationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId id,  String target,  DraftStamp? draft,  CommitReceipt? receipt,  bool acknowledged,  bool observed,  bool effective,  bool durable,  OperationFailurePhase? failurePhase,  StudioFailure? error,  StudioFailure? evidenceError)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _OperationState() when $default != null:
return $default(_that.id,_that.target,_that.draft,_that.receipt,_that.acknowledged,_that.observed,_that.effective,_that.durable,_that.failurePhase,_that.error,_that.evidenceError);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId id,  String target,  DraftStamp? draft,  CommitReceipt? receipt,  bool acknowledged,  bool observed,  bool effective,  bool durable,  OperationFailurePhase? failurePhase,  StudioFailure? error,  StudioFailure? evidenceError)  $default,) {final _that = this;
switch (_that) {
case _OperationState():
return $default(_that.id,_that.target,_that.draft,_that.receipt,_that.acknowledged,_that.observed,_that.effective,_that.durable,_that.failurePhase,_that.error,_that.evidenceError);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId id,  String target,  DraftStamp? draft,  CommitReceipt? receipt,  bool acknowledged,  bool observed,  bool effective,  bool durable,  OperationFailurePhase? failurePhase,  StudioFailure? error,  StudioFailure? evidenceError)?  $default,) {final _that = this;
switch (_that) {
case _OperationState() when $default != null:
return $default(_that.id,_that.target,_that.draft,_that.receipt,_that.acknowledged,_that.observed,_that.effective,_that.durable,_that.failurePhase,_that.error,_that.evidenceError);case _:
  return null;

}
}

}

/// @nodoc


class _OperationState extends OperationState {
  const _OperationState({required this.id, required this.target, this.draft, this.receipt, this.acknowledged = false, this.observed = false, this.effective = false, this.durable = false, this.failurePhase, this.error, this.evidenceError}): super._();


@override final  OperationId id;
@override final  String target;
@override final  DraftStamp? draft;
@override final  CommitReceipt? receipt;
@override@JsonKey() final  bool acknowledged;
@override@JsonKey() final  bool observed;
@override@JsonKey() final  bool effective;
@override@JsonKey() final  bool durable;
@override final  OperationFailurePhase? failurePhase;
@override final  StudioFailure? error;
@override final  StudioFailure? evidenceError;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$OperationStateCopyWith<_OperationState> get copyWith => __$OperationStateCopyWithImpl<_OperationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _OperationState&&(identical(other.id, id) || other.id == id)&&(identical(other.target, target) || other.target == target)&&(identical(other.draft, draft) || other.draft == draft)&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.acknowledged, acknowledged) || other.acknowledged == acknowledged)&&(identical(other.observed, observed) || other.observed == observed)&&(identical(other.effective, effective) || other.effective == effective)&&(identical(other.durable, durable) || other.durable == durable)&&(identical(other.failurePhase, failurePhase) || other.failurePhase == failurePhase)&&(identical(other.error, error) || other.error == error)&&(identical(other.evidenceError, evidenceError) || other.evidenceError == evidenceError));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,target,draft,receipt,acknowledged,observed,effective,durable,failurePhase,error,evidenceError);
}



}

/// @nodoc
abstract mixin class _$OperationStateCopyWith<$Res> implements $OperationStateCopyWith<$Res> {
  factory _$OperationStateCopyWith(_OperationState value, $Res Function(_OperationState) _then) = __$OperationStateCopyWithImpl;
@override @useResult
$Res call({
 OperationId id, String target, DraftStamp? draft, CommitReceipt? receipt, bool acknowledged, bool observed, bool effective, bool durable, OperationFailurePhase? failurePhase, StudioFailure? error, StudioFailure? evidenceError
});


@override $OperationIdCopyWith<$Res> get id;@override $DraftStampCopyWith<$Res>? get draft;@override $CommitReceiptCopyWith<$Res>? get receipt;@override $StudioFailureCopyWith<$Res>? get error;@override $StudioFailureCopyWith<$Res>? get evidenceError;

}
/// @nodoc
class __$OperationStateCopyWithImpl<$Res>
    implements _$OperationStateCopyWith<$Res> {
  __$OperationStateCopyWithImpl(this._self, this._then);

  final _OperationState _self;
  final $Res Function(_OperationState) _then;

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? target = null,Object? draft = freezed,Object? receipt = freezed,Object? acknowledged = null,Object? observed = null,Object? effective = null,Object? durable = null,Object? failurePhase = freezed,Object? error = freezed,Object? evidenceError = freezed,}) {
  return _then(_OperationState(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as OperationId,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,draft: freezed == draft ? _self.draft : draft // ignore: cast_nullable_to_non_nullable
as DraftStamp?,receipt: freezed == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt?,acknowledged: null == acknowledged ? _self.acknowledged : acknowledged // ignore: cast_nullable_to_non_nullable
as bool,observed: null == observed ? _self.observed : observed // ignore: cast_nullable_to_non_nullable
as bool,effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as bool,durable: null == durable ? _self.durable : durable // ignore: cast_nullable_to_non_nullable
as bool,failurePhase: freezed == failurePhase ? _self.failurePhase : failurePhase // ignore: cast_nullable_to_non_nullable
as OperationFailurePhase?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,evidenceError: freezed == evidenceError ? _self.evidenceError : evidenceError // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get id {

  return $OperationIdCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftStampCopyWith<$Res>? get draft {
    if (_self.draft == null) {
    return null;
  }

  return $DraftStampCopyWith<$Res>(_self.draft!, (value) {
    return _then(_self.copyWith(draft: value));
  });
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res>? get receipt {
    if (_self.receipt == null) {
    return null;
  }

  return $CommitReceiptCopyWith<$Res>(_self.receipt!, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of OperationState
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
}/// Create a copy of OperationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get evidenceError {
    if (_self.evidenceError == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.evidenceError!, (value) {
    return _then(_self.copyWith(evidenceError: value));
  });
}
}

// dart format on
