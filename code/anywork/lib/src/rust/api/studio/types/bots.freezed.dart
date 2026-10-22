// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeBotConnectionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotConnectionState()';
}


}

/// @nodoc
class $BridgeBotConnectionStateCopyWith<$Res>  {
$BridgeBotConnectionStateCopyWith(BridgeBotConnectionState _, $Res Function(BridgeBotConnectionState) __);
}


/// Adds pattern-matching-related methods to [BridgeBotConnectionState].
extension BridgeBotConnectionStatePatterns on BridgeBotConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotConnectionState_Disabled value)?  disabled,TResult Function( BridgeBotConnectionState_Connecting value)?  connecting,TResult Function( BridgeBotConnectionState_Connected value)?  connected,TResult Function( BridgeBotConnectionState_Reconnecting value)?  reconnecting,TResult Function( BridgeBotConnectionState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled() when disabled != null:
return disabled(_that);case BridgeBotConnectionState_Connecting() when connecting != null:
return connecting(_that);case BridgeBotConnectionState_Connected() when connected != null:
return connected(_that);case BridgeBotConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case BridgeBotConnectionState_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotConnectionState_Disabled value)  disabled,required TResult Function( BridgeBotConnectionState_Connecting value)  connecting,required TResult Function( BridgeBotConnectionState_Connected value)  connected,required TResult Function( BridgeBotConnectionState_Reconnecting value)  reconnecting,required TResult Function( BridgeBotConnectionState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled():
return disabled(_that);case BridgeBotConnectionState_Connecting():
return connecting(_that);case BridgeBotConnectionState_Connected():
return connected(_that);case BridgeBotConnectionState_Reconnecting():
return reconnecting(_that);case BridgeBotConnectionState_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotConnectionState_Disabled value)?  disabled,TResult? Function( BridgeBotConnectionState_Connecting value)?  connecting,TResult? Function( BridgeBotConnectionState_Connected value)?  connected,TResult? Function( BridgeBotConnectionState_Reconnecting value)?  reconnecting,TResult? Function( BridgeBotConnectionState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled() when disabled != null:
return disabled(_that);case BridgeBotConnectionState_Connecting() when connecting != null:
return connecting(_that);case BridgeBotConnectionState_Connected() when connected != null:
return connected(_that);case BridgeBotConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that);case BridgeBotConnectionState_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disabled,TResult Function()?  connecting,TResult Function()?  connected,TResult Function( PlatformInt64? nextAttemptAt,  int attempt)?  reconnecting,TResult Function( String code,  String message,  bool retryable,  String? platformCode)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled() when disabled != null:
return disabled();case BridgeBotConnectionState_Connecting() when connecting != null:
return connecting();case BridgeBotConnectionState_Connected() when connected != null:
return connected();case BridgeBotConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.nextAttemptAt,_that.attempt);case BridgeBotConnectionState_Failed() when failed != null:
return failed(_that.code,_that.message,_that.retryable,_that.platformCode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disabled,required TResult Function()  connecting,required TResult Function()  connected,required TResult Function( PlatformInt64? nextAttemptAt,  int attempt)  reconnecting,required TResult Function( String code,  String message,  bool retryable,  String? platformCode)  failed,}) {final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled():
return disabled();case BridgeBotConnectionState_Connecting():
return connecting();case BridgeBotConnectionState_Connected():
return connected();case BridgeBotConnectionState_Reconnecting():
return reconnecting(_that.nextAttemptAt,_that.attempt);case BridgeBotConnectionState_Failed():
return failed(_that.code,_that.message,_that.retryable,_that.platformCode);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disabled,TResult? Function()?  connecting,TResult? Function()?  connected,TResult? Function( PlatformInt64? nextAttemptAt,  int attempt)?  reconnecting,TResult? Function( String code,  String message,  bool retryable,  String? platformCode)?  failed,}) {final _that = this;
switch (_that) {
case BridgeBotConnectionState_Disabled() when disabled != null:
return disabled();case BridgeBotConnectionState_Connecting() when connecting != null:
return connecting();case BridgeBotConnectionState_Connected() when connected != null:
return connected();case BridgeBotConnectionState_Reconnecting() when reconnecting != null:
return reconnecting(_that.nextAttemptAt,_that.attempt);case BridgeBotConnectionState_Failed() when failed != null:
return failed(_that.code,_that.message,_that.retryable,_that.platformCode);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotConnectionState_Disabled extends BridgeBotConnectionState {
  const BridgeBotConnectionState_Disabled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState_Disabled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotConnectionState.disabled()';
}


}




/// @nodoc


class BridgeBotConnectionState_Connecting extends BridgeBotConnectionState {
  const BridgeBotConnectionState_Connecting(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState_Connecting);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotConnectionState.connecting()';
}


}




/// @nodoc


class BridgeBotConnectionState_Connected extends BridgeBotConnectionState {
  const BridgeBotConnectionState_Connected(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState_Connected);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotConnectionState.connected()';
}


}




/// @nodoc


class BridgeBotConnectionState_Reconnecting extends BridgeBotConnectionState {
  const BridgeBotConnectionState_Reconnecting({this.nextAttemptAt, required this.attempt}): super._();


 final  PlatformInt64? nextAttemptAt;
 final  int attempt;

/// Create a copy of BridgeBotConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotConnectionState_ReconnectingCopyWith<BridgeBotConnectionState_Reconnecting> get copyWith => _$BridgeBotConnectionState_ReconnectingCopyWithImpl<BridgeBotConnectionState_Reconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState_Reconnecting&&(identical(other.nextAttemptAt, nextAttemptAt) || other.nextAttemptAt == nextAttemptAt)&&(identical(other.attempt, attempt) || other.attempt == attempt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,nextAttemptAt,attempt);
}

@override
String toString() {
    return 'BridgeBotConnectionState.reconnecting(nextAttemptAt: $nextAttemptAt, attempt: $attempt)';
}


}

/// @nodoc
abstract mixin class $BridgeBotConnectionState_ReconnectingCopyWith<$Res> implements $BridgeBotConnectionStateCopyWith<$Res> {
  factory $BridgeBotConnectionState_ReconnectingCopyWith(BridgeBotConnectionState_Reconnecting value, $Res Function(BridgeBotConnectionState_Reconnecting) _then) = _$BridgeBotConnectionState_ReconnectingCopyWithImpl;
@useResult
$Res call({
 PlatformInt64? nextAttemptAt, int attempt
});




}
/// @nodoc
class _$BridgeBotConnectionState_ReconnectingCopyWithImpl<$Res>
    implements $BridgeBotConnectionState_ReconnectingCopyWith<$Res> {
  _$BridgeBotConnectionState_ReconnectingCopyWithImpl(this._self, this._then);

  final BridgeBotConnectionState_Reconnecting _self;
  final $Res Function(BridgeBotConnectionState_Reconnecting) _then;

/// Create a copy of BridgeBotConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nextAttemptAt = freezed,Object? attempt = null,}) {
  return _then(BridgeBotConnectionState_Reconnecting(
nextAttemptAt: freezed == nextAttemptAt ? _self.nextAttemptAt : nextAttemptAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeBotConnectionState_Failed extends BridgeBotConnectionState {
  const BridgeBotConnectionState_Failed({required this.code, required this.message, required this.retryable, this.platformCode}): super._();


 final  String code;
 final  String message;
 final  bool retryable;
 final  String? platformCode;

/// Create a copy of BridgeBotConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotConnectionState_FailedCopyWith<BridgeBotConnectionState_Failed> get copyWith => _$BridgeBotConnectionState_FailedCopyWithImpl<BridgeBotConnectionState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotConnectionState_Failed&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable)&&(identical(other.platformCode, platformCode) || other.platformCode == platformCode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable,platformCode);
}

@override
String toString() {
    return 'BridgeBotConnectionState.failed(code: $code, message: $message, retryable: $retryable, platformCode: $platformCode)';
}


}

/// @nodoc
abstract mixin class $BridgeBotConnectionState_FailedCopyWith<$Res> implements $BridgeBotConnectionStateCopyWith<$Res> {
  factory $BridgeBotConnectionState_FailedCopyWith(BridgeBotConnectionState_Failed value, $Res Function(BridgeBotConnectionState_Failed) _then) = _$BridgeBotConnectionState_FailedCopyWithImpl;
@useResult
$Res call({
 String code, String message, bool retryable, String? platformCode
});




}
/// @nodoc
class _$BridgeBotConnectionState_FailedCopyWithImpl<$Res>
    implements $BridgeBotConnectionState_FailedCopyWith<$Res> {
  _$BridgeBotConnectionState_FailedCopyWithImpl(this._self, this._then);

  final BridgeBotConnectionState_Failed _self;
  final $Res Function(BridgeBotConnectionState_Failed) _then;

/// Create a copy of BridgeBotConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? platformCode = freezed,}) {
  return _then(BridgeBotConnectionState_Failed(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,platformCode: freezed == platformCode ? _self.platformCode : platformCode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BridgeBotCredentialOperation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCredentialOperation);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCredentialOperation()';
}


}

/// @nodoc
class $BridgeBotCredentialOperationCopyWith<$Res>  {
$BridgeBotCredentialOperationCopyWith(BridgeBotCredentialOperation _, $Res Function(BridgeBotCredentialOperation) __);
}


/// Adds pattern-matching-related methods to [BridgeBotCredentialOperation].
extension BridgeBotCredentialOperationPatterns on BridgeBotCredentialOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotCredentialOperation_Idle value)?  idle,TResult Function( BridgeBotCredentialOperation_Preparing value)?  preparing,TResult Function( BridgeBotCredentialOperation_CommitUncertain value)?  commitUncertain,TResult Function( BridgeBotCredentialOperation_CleanupPending value)?  cleanupPending,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle() when idle != null:
return idle(_that);case BridgeBotCredentialOperation_Preparing() when preparing != null:
return preparing(_that);case BridgeBotCredentialOperation_CommitUncertain() when commitUncertain != null:
return commitUncertain(_that);case BridgeBotCredentialOperation_CleanupPending() when cleanupPending != null:
return cleanupPending(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotCredentialOperation_Idle value)  idle,required TResult Function( BridgeBotCredentialOperation_Preparing value)  preparing,required TResult Function( BridgeBotCredentialOperation_CommitUncertain value)  commitUncertain,required TResult Function( BridgeBotCredentialOperation_CleanupPending value)  cleanupPending,}){
final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle():
return idle(_that);case BridgeBotCredentialOperation_Preparing():
return preparing(_that);case BridgeBotCredentialOperation_CommitUncertain():
return commitUncertain(_that);case BridgeBotCredentialOperation_CleanupPending():
return cleanupPending(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotCredentialOperation_Idle value)?  idle,TResult? Function( BridgeBotCredentialOperation_Preparing value)?  preparing,TResult? Function( BridgeBotCredentialOperation_CommitUncertain value)?  commitUncertain,TResult? Function( BridgeBotCredentialOperation_CleanupPending value)?  cleanupPending,}){
final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle() when idle != null:
return idle(_that);case BridgeBotCredentialOperation_Preparing() when preparing != null:
return preparing(_that);case BridgeBotCredentialOperation_CommitUncertain() when commitUncertain != null:
return commitUncertain(_that);case BridgeBotCredentialOperation_CleanupPending() when cleanupPending != null:
return cleanupPending(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String operationId)?  preparing,TResult Function( String operationId)?  commitUncertain,TResult Function( String operationId,  bool configCommitted)?  cleanupPending,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle() when idle != null:
return idle();case BridgeBotCredentialOperation_Preparing() when preparing != null:
return preparing(_that.operationId);case BridgeBotCredentialOperation_CommitUncertain() when commitUncertain != null:
return commitUncertain(_that.operationId);case BridgeBotCredentialOperation_CleanupPending() when cleanupPending != null:
return cleanupPending(_that.operationId,_that.configCommitted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String operationId)  preparing,required TResult Function( String operationId)  commitUncertain,required TResult Function( String operationId,  bool configCommitted)  cleanupPending,}) {final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle():
return idle();case BridgeBotCredentialOperation_Preparing():
return preparing(_that.operationId);case BridgeBotCredentialOperation_CommitUncertain():
return commitUncertain(_that.operationId);case BridgeBotCredentialOperation_CleanupPending():
return cleanupPending(_that.operationId,_that.configCommitted);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String operationId)?  preparing,TResult? Function( String operationId)?  commitUncertain,TResult? Function( String operationId,  bool configCommitted)?  cleanupPending,}) {final _that = this;
switch (_that) {
case BridgeBotCredentialOperation_Idle() when idle != null:
return idle();case BridgeBotCredentialOperation_Preparing() when preparing != null:
return preparing(_that.operationId);case BridgeBotCredentialOperation_CommitUncertain() when commitUncertain != null:
return commitUncertain(_that.operationId);case BridgeBotCredentialOperation_CleanupPending() when cleanupPending != null:
return cleanupPending(_that.operationId,_that.configCommitted);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotCredentialOperation_Idle extends BridgeBotCredentialOperation {
  const BridgeBotCredentialOperation_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCredentialOperation_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotCredentialOperation.idle()';
}


}




/// @nodoc


class BridgeBotCredentialOperation_Preparing extends BridgeBotCredentialOperation {
  const BridgeBotCredentialOperation_Preparing({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCredentialOperation_PreparingCopyWith<BridgeBotCredentialOperation_Preparing> get copyWith => _$BridgeBotCredentialOperation_PreparingCopyWithImpl<BridgeBotCredentialOperation_Preparing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCredentialOperation_Preparing&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeBotCredentialOperation.preparing(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCredentialOperation_PreparingCopyWith<$Res> implements $BridgeBotCredentialOperationCopyWith<$Res> {
  factory $BridgeBotCredentialOperation_PreparingCopyWith(BridgeBotCredentialOperation_Preparing value, $Res Function(BridgeBotCredentialOperation_Preparing) _then) = _$BridgeBotCredentialOperation_PreparingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeBotCredentialOperation_PreparingCopyWithImpl<$Res>
    implements $BridgeBotCredentialOperation_PreparingCopyWith<$Res> {
  _$BridgeBotCredentialOperation_PreparingCopyWithImpl(this._self, this._then);

  final BridgeBotCredentialOperation_Preparing _self;
  final $Res Function(BridgeBotCredentialOperation_Preparing) _then;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeBotCredentialOperation_Preparing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotCredentialOperation_CommitUncertain extends BridgeBotCredentialOperation {
  const BridgeBotCredentialOperation_CommitUncertain({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCredentialOperation_CommitUncertainCopyWith<BridgeBotCredentialOperation_CommitUncertain> get copyWith => _$BridgeBotCredentialOperation_CommitUncertainCopyWithImpl<BridgeBotCredentialOperation_CommitUncertain>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCredentialOperation_CommitUncertain&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeBotCredentialOperation.commitUncertain(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCredentialOperation_CommitUncertainCopyWith<$Res> implements $BridgeBotCredentialOperationCopyWith<$Res> {
  factory $BridgeBotCredentialOperation_CommitUncertainCopyWith(BridgeBotCredentialOperation_CommitUncertain value, $Res Function(BridgeBotCredentialOperation_CommitUncertain) _then) = _$BridgeBotCredentialOperation_CommitUncertainCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeBotCredentialOperation_CommitUncertainCopyWithImpl<$Res>
    implements $BridgeBotCredentialOperation_CommitUncertainCopyWith<$Res> {
  _$BridgeBotCredentialOperation_CommitUncertainCopyWithImpl(this._self, this._then);

  final BridgeBotCredentialOperation_CommitUncertain _self;
  final $Res Function(BridgeBotCredentialOperation_CommitUncertain) _then;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeBotCredentialOperation_CommitUncertain(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotCredentialOperation_CleanupPending extends BridgeBotCredentialOperation {
  const BridgeBotCredentialOperation_CleanupPending({required this.operationId, required this.configCommitted}): super._();


 final  String operationId;
 final  bool configCommitted;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotCredentialOperation_CleanupPendingCopyWith<BridgeBotCredentialOperation_CleanupPending> get copyWith => _$BridgeBotCredentialOperation_CleanupPendingCopyWithImpl<BridgeBotCredentialOperation_CleanupPending>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotCredentialOperation_CleanupPending&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.configCommitted, configCommitted) || other.configCommitted == configCommitted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,configCommitted);
}

@override
String toString() {
    return 'BridgeBotCredentialOperation.cleanupPending(operationId: $operationId, configCommitted: $configCommitted)';
}


}

/// @nodoc
abstract mixin class $BridgeBotCredentialOperation_CleanupPendingCopyWith<$Res> implements $BridgeBotCredentialOperationCopyWith<$Res> {
  factory $BridgeBotCredentialOperation_CleanupPendingCopyWith(BridgeBotCredentialOperation_CleanupPending value, $Res Function(BridgeBotCredentialOperation_CleanupPending) _then) = _$BridgeBotCredentialOperation_CleanupPendingCopyWithImpl;
@useResult
$Res call({
 String operationId, bool configCommitted
});




}
/// @nodoc
class _$BridgeBotCredentialOperation_CleanupPendingCopyWithImpl<$Res>
    implements $BridgeBotCredentialOperation_CleanupPendingCopyWith<$Res> {
  _$BridgeBotCredentialOperation_CleanupPendingCopyWithImpl(this._self, this._then);

  final BridgeBotCredentialOperation_CleanupPending _self;
  final $Res Function(BridgeBotCredentialOperation_CleanupPending) _then;

/// Create a copy of BridgeBotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? configCommitted = null,}) {
  return _then(BridgeBotCredentialOperation_CleanupPending(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,configCommitted: null == configCommitted ? _self.configCommitted : configCommitted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeBotMessageBody {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotMessageBody);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotMessageBody()';
}


}

/// @nodoc
class $BridgeBotMessageBodyCopyWith<$Res>  {
$BridgeBotMessageBodyCopyWith(BridgeBotMessageBody _, $Res Function(BridgeBotMessageBody) __);
}


/// Adds pattern-matching-related methods to [BridgeBotMessageBody].
extension BridgeBotMessageBodyPatterns on BridgeBotMessageBody {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotMessageBody_Text value)?  text,TResult Function( BridgeBotMessageBody_Post value)?  post,TResult Function( BridgeBotMessageBody_Unsupported value)?  unsupported,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text() when text != null:
return text(_that);case BridgeBotMessageBody_Post() when post != null:
return post(_that);case BridgeBotMessageBody_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotMessageBody_Text value)  text,required TResult Function( BridgeBotMessageBody_Post value)  post,required TResult Function( BridgeBotMessageBody_Unsupported value)  unsupported,}){
final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text():
return text(_that);case BridgeBotMessageBody_Post():
return post(_that);case BridgeBotMessageBody_Unsupported():
return unsupported(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotMessageBody_Text value)?  text,TResult? Function( BridgeBotMessageBody_Post value)?  post,TResult? Function( BridgeBotMessageBody_Unsupported value)?  unsupported,}){
final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text() when text != null:
return text(_that);case BridgeBotMessageBody_Post() when post != null:
return post(_that);case BridgeBotMessageBody_Unsupported() when unsupported != null:
return unsupported(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  text,TResult Function( String text)?  post,TResult Function( String msgType,  String notice)?  unsupported,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text() when text != null:
return text(_that.text);case BridgeBotMessageBody_Post() when post != null:
return post(_that.text);case BridgeBotMessageBody_Unsupported() when unsupported != null:
return unsupported(_that.msgType,_that.notice);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  text,required TResult Function( String text)  post,required TResult Function( String msgType,  String notice)  unsupported,}) {final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text():
return text(_that.text);case BridgeBotMessageBody_Post():
return post(_that.text);case BridgeBotMessageBody_Unsupported():
return unsupported(_that.msgType,_that.notice);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  text,TResult? Function( String text)?  post,TResult? Function( String msgType,  String notice)?  unsupported,}) {final _that = this;
switch (_that) {
case BridgeBotMessageBody_Text() when text != null:
return text(_that.text);case BridgeBotMessageBody_Post() when post != null:
return post(_that.text);case BridgeBotMessageBody_Unsupported() when unsupported != null:
return unsupported(_that.msgType,_that.notice);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotMessageBody_Text extends BridgeBotMessageBody {
  const BridgeBotMessageBody_Text({required this.text}): super._();


 final  String text;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotMessageBody_TextCopyWith<BridgeBotMessageBody_Text> get copyWith => _$BridgeBotMessageBody_TextCopyWithImpl<BridgeBotMessageBody_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotMessageBody_Text&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'BridgeBotMessageBody.text(text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeBotMessageBody_TextCopyWith<$Res> implements $BridgeBotMessageBodyCopyWith<$Res> {
  factory $BridgeBotMessageBody_TextCopyWith(BridgeBotMessageBody_Text value, $Res Function(BridgeBotMessageBody_Text) _then) = _$BridgeBotMessageBody_TextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BridgeBotMessageBody_TextCopyWithImpl<$Res>
    implements $BridgeBotMessageBody_TextCopyWith<$Res> {
  _$BridgeBotMessageBody_TextCopyWithImpl(this._self, this._then);

  final BridgeBotMessageBody_Text _self;
  final $Res Function(BridgeBotMessageBody_Text) _then;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BridgeBotMessageBody_Text(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotMessageBody_Post extends BridgeBotMessageBody {
  const BridgeBotMessageBody_Post({required this.text}): super._();


 final  String text;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotMessageBody_PostCopyWith<BridgeBotMessageBody_Post> get copyWith => _$BridgeBotMessageBody_PostCopyWithImpl<BridgeBotMessageBody_Post>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotMessageBody_Post&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}

@override
String toString() {
    return 'BridgeBotMessageBody.post(text: $text)';
}


}

/// @nodoc
abstract mixin class $BridgeBotMessageBody_PostCopyWith<$Res> implements $BridgeBotMessageBodyCopyWith<$Res> {
  factory $BridgeBotMessageBody_PostCopyWith(BridgeBotMessageBody_Post value, $Res Function(BridgeBotMessageBody_Post) _then) = _$BridgeBotMessageBody_PostCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$BridgeBotMessageBody_PostCopyWithImpl<$Res>
    implements $BridgeBotMessageBody_PostCopyWith<$Res> {
  _$BridgeBotMessageBody_PostCopyWithImpl(this._self, this._then);

  final BridgeBotMessageBody_Post _self;
  final $Res Function(BridgeBotMessageBody_Post) _then;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(BridgeBotMessageBody_Post(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotMessageBody_Unsupported extends BridgeBotMessageBody {
  const BridgeBotMessageBody_Unsupported({required this.msgType, required this.notice}): super._();


 final  String msgType;
 final  String notice;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotMessageBody_UnsupportedCopyWith<BridgeBotMessageBody_Unsupported> get copyWith => _$BridgeBotMessageBody_UnsupportedCopyWithImpl<BridgeBotMessageBody_Unsupported>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotMessageBody_Unsupported&&(identical(other.msgType, msgType) || other.msgType == msgType)&&(identical(other.notice, notice) || other.notice == notice));
}


@override
int get hashCode {
    return Object.hash(runtimeType,msgType,notice);
}

@override
String toString() {
    return 'BridgeBotMessageBody.unsupported(msgType: $msgType, notice: $notice)';
}


}

/// @nodoc
abstract mixin class $BridgeBotMessageBody_UnsupportedCopyWith<$Res> implements $BridgeBotMessageBodyCopyWith<$Res> {
  factory $BridgeBotMessageBody_UnsupportedCopyWith(BridgeBotMessageBody_Unsupported value, $Res Function(BridgeBotMessageBody_Unsupported) _then) = _$BridgeBotMessageBody_UnsupportedCopyWithImpl;
@useResult
$Res call({
 String msgType, String notice
});




}
/// @nodoc
class _$BridgeBotMessageBody_UnsupportedCopyWithImpl<$Res>
    implements $BridgeBotMessageBody_UnsupportedCopyWith<$Res> {
  _$BridgeBotMessageBody_UnsupportedCopyWithImpl(this._self, this._then);

  final BridgeBotMessageBody_Unsupported _self;
  final $Res Function(BridgeBotMessageBody_Unsupported) _then;

/// Create a copy of BridgeBotMessageBody
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? msgType = null,Object? notice = null,}) {
  return _then(BridgeBotMessageBody_Unsupported(
msgType: null == msgType ? _self.msgType : msgType // ignore: cast_nullable_to_non_nullable
as String,notice: null == notice ? _self.notice : notice // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeBotRegistrationStatus {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotRegistrationStatus()';
}


}

/// @nodoc
class $BridgeBotRegistrationStatusCopyWith<$Res>  {
$BridgeBotRegistrationStatusCopyWith(BridgeBotRegistrationStatus _, $Res Function(BridgeBotRegistrationStatus) __);
}


/// Adds pattern-matching-related methods to [BridgeBotRegistrationStatus].
extension BridgeBotRegistrationStatusPatterns on BridgeBotRegistrationStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotRegistrationStatus_Idle value)?  idle,TResult Function( BridgeBotRegistrationStatus_Preparing value)?  preparing,TResult Function( BridgeBotRegistrationStatus_Waiting value)?  waiting,TResult Function( BridgeBotRegistrationStatus_SlowDown value)?  slowDown,TResult Function( BridgeBotRegistrationStatus_Completed value)?  completed,TResult Function( BridgeBotRegistrationStatus_Committing value)?  committing,TResult Function( BridgeBotRegistrationStatus_Denied value)?  denied,TResult Function( BridgeBotRegistrationStatus_Expired value)?  expired,TResult Function( BridgeBotRegistrationStatus_Cancelled value)?  cancelled,TResult Function( BridgeBotRegistrationStatus_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle() when idle != null:
return idle(_that);case BridgeBotRegistrationStatus_Preparing() when preparing != null:
return preparing(_that);case BridgeBotRegistrationStatus_Waiting() when waiting != null:
return waiting(_that);case BridgeBotRegistrationStatus_SlowDown() when slowDown != null:
return slowDown(_that);case BridgeBotRegistrationStatus_Completed() when completed != null:
return completed(_that);case BridgeBotRegistrationStatus_Committing() when committing != null:
return committing(_that);case BridgeBotRegistrationStatus_Denied() when denied != null:
return denied(_that);case BridgeBotRegistrationStatus_Expired() when expired != null:
return expired(_that);case BridgeBotRegistrationStatus_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeBotRegistrationStatus_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotRegistrationStatus_Idle value)  idle,required TResult Function( BridgeBotRegistrationStatus_Preparing value)  preparing,required TResult Function( BridgeBotRegistrationStatus_Waiting value)  waiting,required TResult Function( BridgeBotRegistrationStatus_SlowDown value)  slowDown,required TResult Function( BridgeBotRegistrationStatus_Completed value)  completed,required TResult Function( BridgeBotRegistrationStatus_Committing value)  committing,required TResult Function( BridgeBotRegistrationStatus_Denied value)  denied,required TResult Function( BridgeBotRegistrationStatus_Expired value)  expired,required TResult Function( BridgeBotRegistrationStatus_Cancelled value)  cancelled,required TResult Function( BridgeBotRegistrationStatus_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle():
return idle(_that);case BridgeBotRegistrationStatus_Preparing():
return preparing(_that);case BridgeBotRegistrationStatus_Waiting():
return waiting(_that);case BridgeBotRegistrationStatus_SlowDown():
return slowDown(_that);case BridgeBotRegistrationStatus_Completed():
return completed(_that);case BridgeBotRegistrationStatus_Committing():
return committing(_that);case BridgeBotRegistrationStatus_Denied():
return denied(_that);case BridgeBotRegistrationStatus_Expired():
return expired(_that);case BridgeBotRegistrationStatus_Cancelled():
return cancelled(_that);case BridgeBotRegistrationStatus_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotRegistrationStatus_Idle value)?  idle,TResult? Function( BridgeBotRegistrationStatus_Preparing value)?  preparing,TResult? Function( BridgeBotRegistrationStatus_Waiting value)?  waiting,TResult? Function( BridgeBotRegistrationStatus_SlowDown value)?  slowDown,TResult? Function( BridgeBotRegistrationStatus_Completed value)?  completed,TResult? Function( BridgeBotRegistrationStatus_Committing value)?  committing,TResult? Function( BridgeBotRegistrationStatus_Denied value)?  denied,TResult? Function( BridgeBotRegistrationStatus_Expired value)?  expired,TResult? Function( BridgeBotRegistrationStatus_Cancelled value)?  cancelled,TResult? Function( BridgeBotRegistrationStatus_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle() when idle != null:
return idle(_that);case BridgeBotRegistrationStatus_Preparing() when preparing != null:
return preparing(_that);case BridgeBotRegistrationStatus_Waiting() when waiting != null:
return waiting(_that);case BridgeBotRegistrationStatus_SlowDown() when slowDown != null:
return slowDown(_that);case BridgeBotRegistrationStatus_Completed() when completed != null:
return completed(_that);case BridgeBotRegistrationStatus_Committing() when committing != null:
return committing(_that);case BridgeBotRegistrationStatus_Denied() when denied != null:
return denied(_that);case BridgeBotRegistrationStatus_Expired() when expired != null:
return expired(_that);case BridgeBotRegistrationStatus_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeBotRegistrationStatus_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String attemptId)?  preparing,TResult Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)?  waiting,TResult Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)?  slowDown,TResult Function( String attemptId)?  completed,TResult Function( String attemptId,  String botId)?  committing,TResult Function( String attemptId,  String message)?  denied,TResult Function( String attemptId)?  expired,TResult Function( String attemptId)?  cancelled,TResult Function( String attemptId,  String code,  String message,  bool retryable)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle() when idle != null:
return idle();case BridgeBotRegistrationStatus_Preparing() when preparing != null:
return preparing(_that.attemptId);case BridgeBotRegistrationStatus_Waiting() when waiting != null:
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_SlowDown() when slowDown != null:
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_Completed() when completed != null:
return completed(_that.attemptId);case BridgeBotRegistrationStatus_Committing() when committing != null:
return committing(_that.attemptId,_that.botId);case BridgeBotRegistrationStatus_Denied() when denied != null:
return denied(_that.attemptId,_that.message);case BridgeBotRegistrationStatus_Expired() when expired != null:
return expired(_that.attemptId);case BridgeBotRegistrationStatus_Cancelled() when cancelled != null:
return cancelled(_that.attemptId);case BridgeBotRegistrationStatus_Failed() when failed != null:
return failed(_that.attemptId,_that.code,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String attemptId)  preparing,required TResult Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)  waiting,required TResult Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)  slowDown,required TResult Function( String attemptId)  completed,required TResult Function( String attemptId,  String botId)  committing,required TResult Function( String attemptId,  String message)  denied,required TResult Function( String attemptId)  expired,required TResult Function( String attemptId)  cancelled,required TResult Function( String attemptId,  String code,  String message,  bool retryable)  failed,}) {final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle():
return idle();case BridgeBotRegistrationStatus_Preparing():
return preparing(_that.attemptId);case BridgeBotRegistrationStatus_Waiting():
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_SlowDown():
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_Completed():
return completed(_that.attemptId);case BridgeBotRegistrationStatus_Committing():
return committing(_that.attemptId,_that.botId);case BridgeBotRegistrationStatus_Denied():
return denied(_that.attemptId,_that.message);case BridgeBotRegistrationStatus_Expired():
return expired(_that.attemptId);case BridgeBotRegistrationStatus_Cancelled():
return cancelled(_that.attemptId);case BridgeBotRegistrationStatus_Failed():
return failed(_that.attemptId,_that.code,_that.message,_that.retryable);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String attemptId)?  preparing,TResult? Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)?  waiting,TResult? Function( String attemptId,  String verificationUrl,  PlatformInt64 expiresAt,  int intervalSeconds)?  slowDown,TResult? Function( String attemptId)?  completed,TResult? Function( String attemptId,  String botId)?  committing,TResult? Function( String attemptId,  String message)?  denied,TResult? Function( String attemptId)?  expired,TResult? Function( String attemptId)?  cancelled,TResult? Function( String attemptId,  String code,  String message,  bool retryable)?  failed,}) {final _that = this;
switch (_that) {
case BridgeBotRegistrationStatus_Idle() when idle != null:
return idle();case BridgeBotRegistrationStatus_Preparing() when preparing != null:
return preparing(_that.attemptId);case BridgeBotRegistrationStatus_Waiting() when waiting != null:
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_SlowDown() when slowDown != null:
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BridgeBotRegistrationStatus_Completed() when completed != null:
return completed(_that.attemptId);case BridgeBotRegistrationStatus_Committing() when committing != null:
return committing(_that.attemptId,_that.botId);case BridgeBotRegistrationStatus_Denied() when denied != null:
return denied(_that.attemptId,_that.message);case BridgeBotRegistrationStatus_Expired() when expired != null:
return expired(_that.attemptId);case BridgeBotRegistrationStatus_Cancelled() when cancelled != null:
return cancelled(_that.attemptId);case BridgeBotRegistrationStatus_Failed() when failed != null:
return failed(_that.attemptId,_that.code,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotRegistrationStatus_Idle extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Idle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Idle);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotRegistrationStatus.idle()';
}


}




/// @nodoc


class BridgeBotRegistrationStatus_Preparing extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Preparing({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_PreparingCopyWith<BridgeBotRegistrationStatus_Preparing> get copyWith => _$BridgeBotRegistrationStatus_PreparingCopyWithImpl<BridgeBotRegistrationStatus_Preparing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Preparing&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.preparing(attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_PreparingCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_PreparingCopyWith(BridgeBotRegistrationStatus_Preparing value, $Res Function(BridgeBotRegistrationStatus_Preparing) _then) = _$BridgeBotRegistrationStatus_PreparingCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_PreparingCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_PreparingCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_PreparingCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Preparing _self;
  final $Res Function(BridgeBotRegistrationStatus_Preparing) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BridgeBotRegistrationStatus_Preparing(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Waiting extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Waiting({required this.attemptId, required this.verificationUrl, required this.expiresAt, required this.intervalSeconds}): super._();


 final  String attemptId;
 final  String verificationUrl;
 final  PlatformInt64 expiresAt;
 final  int intervalSeconds;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_WaitingCopyWith<BridgeBotRegistrationStatus_Waiting> get copyWith => _$BridgeBotRegistrationStatus_WaitingCopyWithImpl<BridgeBotRegistrationStatus_Waiting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Waiting&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.verificationUrl, verificationUrl) || other.verificationUrl == verificationUrl)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.intervalSeconds, intervalSeconds) || other.intervalSeconds == intervalSeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,verificationUrl,expiresAt,intervalSeconds);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.waiting(attemptId: $attemptId, verificationUrl: $verificationUrl, expiresAt: $expiresAt, intervalSeconds: $intervalSeconds)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_WaitingCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_WaitingCopyWith(BridgeBotRegistrationStatus_Waiting value, $Res Function(BridgeBotRegistrationStatus_Waiting) _then) = _$BridgeBotRegistrationStatus_WaitingCopyWithImpl;
@useResult
$Res call({
 String attemptId, String verificationUrl, PlatformInt64 expiresAt, int intervalSeconds
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_WaitingCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_WaitingCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_WaitingCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Waiting _self;
  final $Res Function(BridgeBotRegistrationStatus_Waiting) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? verificationUrl = null,Object? expiresAt = null,Object? intervalSeconds = null,}) {
  return _then(BridgeBotRegistrationStatus_Waiting(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,verificationUrl: null == verificationUrl ? _self.verificationUrl : verificationUrl // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,intervalSeconds: null == intervalSeconds ? _self.intervalSeconds : intervalSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_SlowDown extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_SlowDown({required this.attemptId, required this.verificationUrl, required this.expiresAt, required this.intervalSeconds}): super._();


 final  String attemptId;
 final  String verificationUrl;
 final  PlatformInt64 expiresAt;
 final  int intervalSeconds;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_SlowDownCopyWith<BridgeBotRegistrationStatus_SlowDown> get copyWith => _$BridgeBotRegistrationStatus_SlowDownCopyWithImpl<BridgeBotRegistrationStatus_SlowDown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_SlowDown&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.verificationUrl, verificationUrl) || other.verificationUrl == verificationUrl)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.intervalSeconds, intervalSeconds) || other.intervalSeconds == intervalSeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,verificationUrl,expiresAt,intervalSeconds);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.slowDown(attemptId: $attemptId, verificationUrl: $verificationUrl, expiresAt: $expiresAt, intervalSeconds: $intervalSeconds)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_SlowDownCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_SlowDownCopyWith(BridgeBotRegistrationStatus_SlowDown value, $Res Function(BridgeBotRegistrationStatus_SlowDown) _then) = _$BridgeBotRegistrationStatus_SlowDownCopyWithImpl;
@useResult
$Res call({
 String attemptId, String verificationUrl, PlatformInt64 expiresAt, int intervalSeconds
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_SlowDownCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_SlowDownCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_SlowDownCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_SlowDown _self;
  final $Res Function(BridgeBotRegistrationStatus_SlowDown) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? verificationUrl = null,Object? expiresAt = null,Object? intervalSeconds = null,}) {
  return _then(BridgeBotRegistrationStatus_SlowDown(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,verificationUrl: null == verificationUrl ? _self.verificationUrl : verificationUrl // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,intervalSeconds: null == intervalSeconds ? _self.intervalSeconds : intervalSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Completed extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Completed({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_CompletedCopyWith<BridgeBotRegistrationStatus_Completed> get copyWith => _$BridgeBotRegistrationStatus_CompletedCopyWithImpl<BridgeBotRegistrationStatus_Completed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Completed&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.completed(attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_CompletedCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_CompletedCopyWith(BridgeBotRegistrationStatus_Completed value, $Res Function(BridgeBotRegistrationStatus_Completed) _then) = _$BridgeBotRegistrationStatus_CompletedCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_CompletedCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_CompletedCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_CompletedCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Completed _self;
  final $Res Function(BridgeBotRegistrationStatus_Completed) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BridgeBotRegistrationStatus_Completed(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Committing extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Committing({required this.attemptId, required this.botId}): super._();


 final  String attemptId;
 final  String botId;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_CommittingCopyWith<BridgeBotRegistrationStatus_Committing> get copyWith => _$BridgeBotRegistrationStatus_CommittingCopyWithImpl<BridgeBotRegistrationStatus_Committing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Committing&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.botId, botId) || other.botId == botId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,botId);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.committing(attemptId: $attemptId, botId: $botId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_CommittingCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_CommittingCopyWith(BridgeBotRegistrationStatus_Committing value, $Res Function(BridgeBotRegistrationStatus_Committing) _then) = _$BridgeBotRegistrationStatus_CommittingCopyWithImpl;
@useResult
$Res call({
 String attemptId, String botId
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_CommittingCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_CommittingCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_CommittingCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Committing _self;
  final $Res Function(BridgeBotRegistrationStatus_Committing) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? botId = null,}) {
  return _then(BridgeBotRegistrationStatus_Committing(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Denied extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Denied({required this.attemptId, required this.message}): super._();


 final  String attemptId;
 final  String message;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_DeniedCopyWith<BridgeBotRegistrationStatus_Denied> get copyWith => _$BridgeBotRegistrationStatus_DeniedCopyWithImpl<BridgeBotRegistrationStatus_Denied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Denied&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,message);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.denied(attemptId: $attemptId, message: $message)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_DeniedCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_DeniedCopyWith(BridgeBotRegistrationStatus_Denied value, $Res Function(BridgeBotRegistrationStatus_Denied) _then) = _$BridgeBotRegistrationStatus_DeniedCopyWithImpl;
@useResult
$Res call({
 String attemptId, String message
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_DeniedCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_DeniedCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_DeniedCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Denied _self;
  final $Res Function(BridgeBotRegistrationStatus_Denied) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? message = null,}) {
  return _then(BridgeBotRegistrationStatus_Denied(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Expired extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Expired({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_ExpiredCopyWith<BridgeBotRegistrationStatus_Expired> get copyWith => _$BridgeBotRegistrationStatus_ExpiredCopyWithImpl<BridgeBotRegistrationStatus_Expired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Expired&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.expired(attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_ExpiredCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_ExpiredCopyWith(BridgeBotRegistrationStatus_Expired value, $Res Function(BridgeBotRegistrationStatus_Expired) _then) = _$BridgeBotRegistrationStatus_ExpiredCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_ExpiredCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_ExpiredCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_ExpiredCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Expired _self;
  final $Res Function(BridgeBotRegistrationStatus_Expired) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BridgeBotRegistrationStatus_Expired(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Cancelled extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Cancelled({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_CancelledCopyWith<BridgeBotRegistrationStatus_Cancelled> get copyWith => _$BridgeBotRegistrationStatus_CancelledCopyWithImpl<BridgeBotRegistrationStatus_Cancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Cancelled&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.cancelled(attemptId: $attemptId)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_CancelledCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_CancelledCopyWith(BridgeBotRegistrationStatus_Cancelled value, $Res Function(BridgeBotRegistrationStatus_Cancelled) _then) = _$BridgeBotRegistrationStatus_CancelledCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_CancelledCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_CancelledCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_CancelledCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Cancelled _self;
  final $Res Function(BridgeBotRegistrationStatus_Cancelled) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BridgeBotRegistrationStatus_Cancelled(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotRegistrationStatus_Failed extends BridgeBotRegistrationStatus {
  const BridgeBotRegistrationStatus_Failed({required this.attemptId, required this.code, required this.message, required this.retryable}): super._();


 final  String attemptId;
 final  String code;
 final  String message;
 final  bool retryable;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotRegistrationStatus_FailedCopyWith<BridgeBotRegistrationStatus_Failed> get copyWith => _$BridgeBotRegistrationStatus_FailedCopyWithImpl<BridgeBotRegistrationStatus_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotRegistrationStatus_Failed&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,code,message,retryable);
}

@override
String toString() {
    return 'BridgeBotRegistrationStatus.failed(attemptId: $attemptId, code: $code, message: $message, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $BridgeBotRegistrationStatus_FailedCopyWith<$Res> implements $BridgeBotRegistrationStatusCopyWith<$Res> {
  factory $BridgeBotRegistrationStatus_FailedCopyWith(BridgeBotRegistrationStatus_Failed value, $Res Function(BridgeBotRegistrationStatus_Failed) _then) = _$BridgeBotRegistrationStatus_FailedCopyWithImpl;
@useResult
$Res call({
 String attemptId, String code, String message, bool retryable
});




}
/// @nodoc
class _$BridgeBotRegistrationStatus_FailedCopyWithImpl<$Res>
    implements $BridgeBotRegistrationStatus_FailedCopyWith<$Res> {
  _$BridgeBotRegistrationStatus_FailedCopyWithImpl(this._self, this._then);

  final BridgeBotRegistrationStatus_Failed _self;
  final $Res Function(BridgeBotRegistrationStatus_Failed) _then;

/// Create a copy of BridgeBotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(BridgeBotRegistrationStatus_Failed(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BridgeBotSecretUpdate {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotSecretUpdate);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotSecretUpdate()';
}


}

/// @nodoc
class $BridgeBotSecretUpdateCopyWith<$Res>  {
$BridgeBotSecretUpdateCopyWith(BridgeBotSecretUpdate _, $Res Function(BridgeBotSecretUpdate) __);
}


/// Adds pattern-matching-related methods to [BridgeBotSecretUpdate].
extension BridgeBotSecretUpdatePatterns on BridgeBotSecretUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeBotSecretUpdate_Preserve value)?  preserve,TResult Function( BridgeBotSecretUpdate_Replace value)?  replace,TResult Function( BridgeBotSecretUpdate_Clear value)?  clear,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve() when preserve != null:
return preserve(_that);case BridgeBotSecretUpdate_Replace() when replace != null:
return replace(_that);case BridgeBotSecretUpdate_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeBotSecretUpdate_Preserve value)  preserve,required TResult Function( BridgeBotSecretUpdate_Replace value)  replace,required TResult Function( BridgeBotSecretUpdate_Clear value)  clear,}){
final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve():
return preserve(_that);case BridgeBotSecretUpdate_Replace():
return replace(_that);case BridgeBotSecretUpdate_Clear():
return clear(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeBotSecretUpdate_Preserve value)?  preserve,TResult? Function( BridgeBotSecretUpdate_Replace value)?  replace,TResult? Function( BridgeBotSecretUpdate_Clear value)?  clear,}){
final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve() when preserve != null:
return preserve(_that);case BridgeBotSecretUpdate_Replace() when replace != null:
return replace(_that);case BridgeBotSecretUpdate_Clear() when clear != null:
return clear(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  preserve,TResult Function( String value)?  replace,TResult Function()?  clear,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve() when preserve != null:
return preserve();case BridgeBotSecretUpdate_Replace() when replace != null:
return replace(_that.value);case BridgeBotSecretUpdate_Clear() when clear != null:
return clear();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  preserve,required TResult Function( String value)  replace,required TResult Function()  clear,}) {final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve():
return preserve();case BridgeBotSecretUpdate_Replace():
return replace(_that.value);case BridgeBotSecretUpdate_Clear():
return clear();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  preserve,TResult? Function( String value)?  replace,TResult? Function()?  clear,}) {final _that = this;
switch (_that) {
case BridgeBotSecretUpdate_Preserve() when preserve != null:
return preserve();case BridgeBotSecretUpdate_Replace() when replace != null:
return replace(_that.value);case BridgeBotSecretUpdate_Clear() when clear != null:
return clear();case _:
  return null;

}
}

}

/// @nodoc


class BridgeBotSecretUpdate_Preserve extends BridgeBotSecretUpdate {
  const BridgeBotSecretUpdate_Preserve(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotSecretUpdate_Preserve);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotSecretUpdate.preserve()';
}


}




/// @nodoc


class BridgeBotSecretUpdate_Replace extends BridgeBotSecretUpdate {
  const BridgeBotSecretUpdate_Replace({required this.value}): super._();


 final  String value;

/// Create a copy of BridgeBotSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeBotSecretUpdate_ReplaceCopyWith<BridgeBotSecretUpdate_Replace> get copyWith => _$BridgeBotSecretUpdate_ReplaceCopyWithImpl<BridgeBotSecretUpdate_Replace>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotSecretUpdate_Replace&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'BridgeBotSecretUpdate.replace(value: $value)';
}


}

/// @nodoc
abstract mixin class $BridgeBotSecretUpdate_ReplaceCopyWith<$Res> implements $BridgeBotSecretUpdateCopyWith<$Res> {
  factory $BridgeBotSecretUpdate_ReplaceCopyWith(BridgeBotSecretUpdate_Replace value, $Res Function(BridgeBotSecretUpdate_Replace) _then) = _$BridgeBotSecretUpdate_ReplaceCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$BridgeBotSecretUpdate_ReplaceCopyWithImpl<$Res>
    implements $BridgeBotSecretUpdate_ReplaceCopyWith<$Res> {
  _$BridgeBotSecretUpdate_ReplaceCopyWithImpl(this._self, this._then);

  final BridgeBotSecretUpdate_Replace _self;
  final $Res Function(BridgeBotSecretUpdate_Replace) _then;

/// Create a copy of BridgeBotSecretUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(BridgeBotSecretUpdate_Replace(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeBotSecretUpdate_Clear extends BridgeBotSecretUpdate {
  const BridgeBotSecretUpdate_Clear(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeBotSecretUpdate_Clear);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeBotSecretUpdate.clear()';
}


}




// dart format on
