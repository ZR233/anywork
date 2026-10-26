// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bot_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotModelRoute {

 String get accountId; String get modelId; String? get effort;
/// Create a copy of BotModelRoute
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<BotModelRoute> get copyWith => _$BotModelRouteCopyWithImpl<BotModelRoute>(this as BotModelRoute, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotModelRoute;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotModelRoute&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.effort, _this.effort) || other.effort == _this.effort));
}


@override
int get hashCode {
  final _this = this as BotModelRoute;
  return Object.hash(runtimeType,_this.accountId,_this.modelId,_this.effort);
}

@override
String toString() {
  final _this = this as BotModelRoute;
  return 'BotModelRoute(accountId: ${_this.accountId}, modelId: ${_this.modelId}, effort: ${_this.effort})';
}


}

/// @nodoc
abstract mixin class $BotModelRouteCopyWith<$Res>  {
  factory $BotModelRouteCopyWith(BotModelRoute value, $Res Function(BotModelRoute) _then) = _$BotModelRouteCopyWithImpl;
@useResult
$Res call({
 String accountId, String modelId, String? effort
});




}
/// @nodoc
class _$BotModelRouteCopyWithImpl<$Res>
    implements $BotModelRouteCopyWith<$Res> {
  _$BotModelRouteCopyWithImpl(this._self, this._then);

  final BotModelRoute _self;
  final $Res Function(BotModelRoute) _then;

/// Create a copy of BotModelRoute
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? modelId = null,Object? effort = freezed,}) {
  return _then(BotModelRoute(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotModelRoute].
extension BotModelRoutePatterns on BotModelRoute {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotModelRoute value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotModelRoute() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotModelRoute value)  $default,){
final _that = this;
switch (_that) {
case _BotModelRoute():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotModelRoute value)?  $default,){
final _that = this;
switch (_that) {
case _BotModelRoute() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String modelId,  String? effort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotModelRoute() when $default != null:
return $default(_that.accountId,_that.modelId,_that.effort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String modelId,  String? effort)  $default,) {final _that = this;
switch (_that) {
case _BotModelRoute():
return $default(_that.accountId,_that.modelId,_that.effort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String modelId,  String? effort)?  $default,) {final _that = this;
switch (_that) {
case _BotModelRoute() when $default != null:
return $default(_that.accountId,_that.modelId,_that.effort);case _:
  return null;

}
}

}

/// @nodoc


class _BotModelRoute implements BotModelRoute {
  const _BotModelRoute({required this.accountId, required this.modelId, required this.effort});


@override final  String accountId;
@override final  String modelId;
@override final  String? effort;

/// Create a copy of BotModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotModelRouteCopyWith<_BotModelRoute> get copyWith => __$BotModelRouteCopyWithImpl<_BotModelRoute>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotModelRoute&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.effort, effort) || other.effort == effort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId,effort);
}

@override
String toString() {
    return 'BotModelRoute(accountId: $accountId, modelId: $modelId, effort: $effort)';
}


}

/// @nodoc
abstract mixin class _$BotModelRouteCopyWith<$Res> implements $BotModelRouteCopyWith<$Res> {
  factory _$BotModelRouteCopyWith(_BotModelRoute value, $Res Function(_BotModelRoute) _then) = __$BotModelRouteCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String modelId, String? effort
});




}
/// @nodoc
class __$BotModelRouteCopyWithImpl<$Res>
    implements _$BotModelRouteCopyWith<$Res> {
  __$BotModelRouteCopyWithImpl(this._self, this._then);

  final _BotModelRoute _self;
  final $Res Function(_BotModelRoute) _then;

/// Create a copy of BotModelRoute
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,Object? effort = freezed,}) {
  return _then(_BotModelRoute(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,effort: freezed == effort ? _self.effort : effort // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BotConnectionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotConnectionStateCopyWith<$Res>  {
$BotConnectionStateCopyWith(BotConnectionState _, $Res Function(BotConnectionState) __);
}


/// Adds pattern-matching-related methods to [BotConnectionState].
extension BotConnectionStatePatterns on BotConnectionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotConnectionDisabled value)?  disabled,TResult Function( BotConnectionConnecting value)?  connecting,TResult Function( BotConnectionConnected value)?  connected,TResult Function( BotConnectionReconnecting value)?  reconnecting,TResult Function( BotConnectionFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotConnectionDisabled() when disabled != null:
return disabled(_that);case BotConnectionConnecting() when connecting != null:
return connecting(_that);case BotConnectionConnected() when connected != null:
return connected(_that);case BotConnectionReconnecting() when reconnecting != null:
return reconnecting(_that);case BotConnectionFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotConnectionDisabled value)  disabled,required TResult Function( BotConnectionConnecting value)  connecting,required TResult Function( BotConnectionConnected value)  connected,required TResult Function( BotConnectionReconnecting value)  reconnecting,required TResult Function( BotConnectionFailed value)  failed,}){
final _that = this;
switch (_that) {
case BotConnectionDisabled():
return disabled(_that);case BotConnectionConnecting():
return connecting(_that);case BotConnectionConnected():
return connected(_that);case BotConnectionReconnecting():
return reconnecting(_that);case BotConnectionFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotConnectionDisabled value)?  disabled,TResult? Function( BotConnectionConnecting value)?  connecting,TResult? Function( BotConnectionConnected value)?  connected,TResult? Function( BotConnectionReconnecting value)?  reconnecting,TResult? Function( BotConnectionFailed value)?  failed,}){
final _that = this;
switch (_that) {
case BotConnectionDisabled() when disabled != null:
return disabled(_that);case BotConnectionConnecting() when connecting != null:
return connecting(_that);case BotConnectionConnected() when connected != null:
return connected(_that);case BotConnectionReconnecting() when reconnecting != null:
return reconnecting(_that);case BotConnectionFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  disabled,TResult Function()?  connecting,TResult Function()?  connected,TResult Function( int? nextAttemptAt,  int attempt)?  reconnecting,TResult Function( String code,  String message,  bool retryable,  String? platformCode)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BotConnectionDisabled() when disabled != null:
return disabled();case BotConnectionConnecting() when connecting != null:
return connecting();case BotConnectionConnected() when connected != null:
return connected();case BotConnectionReconnecting() when reconnecting != null:
return reconnecting(_that.nextAttemptAt,_that.attempt);case BotConnectionFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  disabled,required TResult Function()  connecting,required TResult Function()  connected,required TResult Function( int? nextAttemptAt,  int attempt)  reconnecting,required TResult Function( String code,  String message,  bool retryable,  String? platformCode)  failed,}) {final _that = this;
switch (_that) {
case BotConnectionDisabled():
return disabled();case BotConnectionConnecting():
return connecting();case BotConnectionConnected():
return connected();case BotConnectionReconnecting():
return reconnecting(_that.nextAttemptAt,_that.attempt);case BotConnectionFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  disabled,TResult? Function()?  connecting,TResult? Function()?  connected,TResult? Function( int? nextAttemptAt,  int attempt)?  reconnecting,TResult? Function( String code,  String message,  bool retryable,  String? platformCode)?  failed,}) {final _that = this;
switch (_that) {
case BotConnectionDisabled() when disabled != null:
return disabled();case BotConnectionConnecting() when connecting != null:
return connecting();case BotConnectionConnected() when connected != null:
return connected();case BotConnectionReconnecting() when reconnecting != null:
return reconnecting(_that.nextAttemptAt,_that.attempt);case BotConnectionFailed() when failed != null:
return failed(_that.code,_that.message,_that.retryable,_that.platformCode);case _:
  return null;

}
}

}

/// @nodoc


class BotConnectionDisabled implements BotConnectionState {
  const BotConnectionDisabled();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionDisabled);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotConnectionConnecting implements BotConnectionState {
  const BotConnectionConnecting();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionConnecting);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotConnectionConnected implements BotConnectionState {
  const BotConnectionConnected();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionConnected);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotConnectionReconnecting implements BotConnectionState {
  const BotConnectionReconnecting({required this.nextAttemptAt, required this.attempt});


 final  int? nextAttemptAt;
 final  int attempt;

/// Create a copy of BotConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConnectionReconnectingCopyWith<BotConnectionReconnecting> get copyWith => _$BotConnectionReconnectingCopyWithImpl<BotConnectionReconnecting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionReconnecting&&(identical(other.nextAttemptAt, nextAttemptAt) || other.nextAttemptAt == nextAttemptAt)&&(identical(other.attempt, attempt) || other.attempt == attempt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,nextAttemptAt,attempt);
}



}

/// @nodoc
abstract mixin class $BotConnectionReconnectingCopyWith<$Res> implements $BotConnectionStateCopyWith<$Res> {
  factory $BotConnectionReconnectingCopyWith(BotConnectionReconnecting value, $Res Function(BotConnectionReconnecting) _then) = _$BotConnectionReconnectingCopyWithImpl;
@useResult
$Res call({
 int? nextAttemptAt, int attempt
});




}
/// @nodoc
class _$BotConnectionReconnectingCopyWithImpl<$Res>
    implements $BotConnectionReconnectingCopyWith<$Res> {
  _$BotConnectionReconnectingCopyWithImpl(this._self, this._then);

  final BotConnectionReconnecting _self;
  final $Res Function(BotConnectionReconnecting) _then;

/// Create a copy of BotConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? nextAttemptAt = freezed,Object? attempt = null,}) {
  return _then(BotConnectionReconnecting(
nextAttemptAt: freezed == nextAttemptAt ? _self.nextAttemptAt : nextAttemptAt // ignore: cast_nullable_to_non_nullable
as int?,attempt: null == attempt ? _self.attempt : attempt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BotConnectionFailed implements BotConnectionState {
  const BotConnectionFailed({required this.code, required this.message, required this.retryable, required this.platformCode});


 final  String code;
 final  String message;
 final  bool retryable;
 final  String? platformCode;

/// Create a copy of BotConnectionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConnectionFailedCopyWith<BotConnectionFailed> get copyWith => _$BotConnectionFailedCopyWithImpl<BotConnectionFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConnectionFailed&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable)&&(identical(other.platformCode, platformCode) || other.platformCode == platformCode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable,platformCode);
}



}

/// @nodoc
abstract mixin class $BotConnectionFailedCopyWith<$Res> implements $BotConnectionStateCopyWith<$Res> {
  factory $BotConnectionFailedCopyWith(BotConnectionFailed value, $Res Function(BotConnectionFailed) _then) = _$BotConnectionFailedCopyWithImpl;
@useResult
$Res call({
 String code, String message, bool retryable, String? platformCode
});




}
/// @nodoc
class _$BotConnectionFailedCopyWithImpl<$Res>
    implements $BotConnectionFailedCopyWith<$Res> {
  _$BotConnectionFailedCopyWithImpl(this._self, this._then);

  final BotConnectionFailed _self;
  final $Res Function(BotConnectionFailed) _then;

/// Create a copy of BotConnectionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? platformCode = freezed,}) {
  return _then(BotConnectionFailed(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,platformCode: freezed == platformCode ? _self.platformCode : platformCode // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BotCredentialOperation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotCredentialOperation);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotCredentialOperationCopyWith<$Res>  {
$BotCredentialOperationCopyWith(BotCredentialOperation _, $Res Function(BotCredentialOperation) __);
}


/// Adds pattern-matching-related methods to [BotCredentialOperation].
extension BotCredentialOperationPatterns on BotCredentialOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotCredentialOperationIdle value)?  idle,TResult Function( BotCredentialOperationPreparing value)?  preparing,TResult Function( BotCredentialOperationCommitUncertain value)?  commitUncertain,TResult Function( BotCredentialOperationCleanupPending value)?  cleanupPending,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotCredentialOperationIdle() when idle != null:
return idle(_that);case BotCredentialOperationPreparing() when preparing != null:
return preparing(_that);case BotCredentialOperationCommitUncertain() when commitUncertain != null:
return commitUncertain(_that);case BotCredentialOperationCleanupPending() when cleanupPending != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotCredentialOperationIdle value)  idle,required TResult Function( BotCredentialOperationPreparing value)  preparing,required TResult Function( BotCredentialOperationCommitUncertain value)  commitUncertain,required TResult Function( BotCredentialOperationCleanupPending value)  cleanupPending,}){
final _that = this;
switch (_that) {
case BotCredentialOperationIdle():
return idle(_that);case BotCredentialOperationPreparing():
return preparing(_that);case BotCredentialOperationCommitUncertain():
return commitUncertain(_that);case BotCredentialOperationCleanupPending():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotCredentialOperationIdle value)?  idle,TResult? Function( BotCredentialOperationPreparing value)?  preparing,TResult? Function( BotCredentialOperationCommitUncertain value)?  commitUncertain,TResult? Function( BotCredentialOperationCleanupPending value)?  cleanupPending,}){
final _that = this;
switch (_that) {
case BotCredentialOperationIdle() when idle != null:
return idle(_that);case BotCredentialOperationPreparing() when preparing != null:
return preparing(_that);case BotCredentialOperationCommitUncertain() when commitUncertain != null:
return commitUncertain(_that);case BotCredentialOperationCleanupPending() when cleanupPending != null:
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
case BotCredentialOperationIdle() when idle != null:
return idle();case BotCredentialOperationPreparing() when preparing != null:
return preparing(_that.operationId);case BotCredentialOperationCommitUncertain() when commitUncertain != null:
return commitUncertain(_that.operationId);case BotCredentialOperationCleanupPending() when cleanupPending != null:
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
case BotCredentialOperationIdle():
return idle();case BotCredentialOperationPreparing():
return preparing(_that.operationId);case BotCredentialOperationCommitUncertain():
return commitUncertain(_that.operationId);case BotCredentialOperationCleanupPending():
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
case BotCredentialOperationIdle() when idle != null:
return idle();case BotCredentialOperationPreparing() when preparing != null:
return preparing(_that.operationId);case BotCredentialOperationCommitUncertain() when commitUncertain != null:
return commitUncertain(_that.operationId);case BotCredentialOperationCleanupPending() when cleanupPending != null:
return cleanupPending(_that.operationId,_that.configCommitted);case _:
  return null;

}
}

}

/// @nodoc


class BotCredentialOperationIdle implements BotCredentialOperation {
  const BotCredentialOperationIdle();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotCredentialOperationIdle);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotCredentialOperationPreparing implements BotCredentialOperation {
  const BotCredentialOperationPreparing({required this.operationId});


 final  String operationId;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotCredentialOperationPreparingCopyWith<BotCredentialOperationPreparing> get copyWith => _$BotCredentialOperationPreparingCopyWithImpl<BotCredentialOperationPreparing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotCredentialOperationPreparing&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $BotCredentialOperationPreparingCopyWith<$Res> implements $BotCredentialOperationCopyWith<$Res> {
  factory $BotCredentialOperationPreparingCopyWith(BotCredentialOperationPreparing value, $Res Function(BotCredentialOperationPreparing) _then) = _$BotCredentialOperationPreparingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BotCredentialOperationPreparingCopyWithImpl<$Res>
    implements $BotCredentialOperationPreparingCopyWith<$Res> {
  _$BotCredentialOperationPreparingCopyWithImpl(this._self, this._then);

  final BotCredentialOperationPreparing _self;
  final $Res Function(BotCredentialOperationPreparing) _then;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BotCredentialOperationPreparing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotCredentialOperationCommitUncertain implements BotCredentialOperation {
  const BotCredentialOperationCommitUncertain({required this.operationId});


 final  String operationId;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotCredentialOperationCommitUncertainCopyWith<BotCredentialOperationCommitUncertain> get copyWith => _$BotCredentialOperationCommitUncertainCopyWithImpl<BotCredentialOperationCommitUncertain>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotCredentialOperationCommitUncertain&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $BotCredentialOperationCommitUncertainCopyWith<$Res> implements $BotCredentialOperationCopyWith<$Res> {
  factory $BotCredentialOperationCommitUncertainCopyWith(BotCredentialOperationCommitUncertain value, $Res Function(BotCredentialOperationCommitUncertain) _then) = _$BotCredentialOperationCommitUncertainCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BotCredentialOperationCommitUncertainCopyWithImpl<$Res>
    implements $BotCredentialOperationCommitUncertainCopyWith<$Res> {
  _$BotCredentialOperationCommitUncertainCopyWithImpl(this._self, this._then);

  final BotCredentialOperationCommitUncertain _self;
  final $Res Function(BotCredentialOperationCommitUncertain) _then;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BotCredentialOperationCommitUncertain(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotCredentialOperationCleanupPending implements BotCredentialOperation {
  const BotCredentialOperationCleanupPending({required this.operationId, required this.configCommitted});


 final  String operationId;
 final  bool configCommitted;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotCredentialOperationCleanupPendingCopyWith<BotCredentialOperationCleanupPending> get copyWith => _$BotCredentialOperationCleanupPendingCopyWithImpl<BotCredentialOperationCleanupPending>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotCredentialOperationCleanupPending&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.configCommitted, configCommitted) || other.configCommitted == configCommitted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,configCommitted);
}



}

/// @nodoc
abstract mixin class $BotCredentialOperationCleanupPendingCopyWith<$Res> implements $BotCredentialOperationCopyWith<$Res> {
  factory $BotCredentialOperationCleanupPendingCopyWith(BotCredentialOperationCleanupPending value, $Res Function(BotCredentialOperationCleanupPending) _then) = _$BotCredentialOperationCleanupPendingCopyWithImpl;
@useResult
$Res call({
 String operationId, bool configCommitted
});




}
/// @nodoc
class _$BotCredentialOperationCleanupPendingCopyWithImpl<$Res>
    implements $BotCredentialOperationCleanupPendingCopyWith<$Res> {
  _$BotCredentialOperationCleanupPendingCopyWithImpl(this._self, this._then);

  final BotCredentialOperationCleanupPending _self;
  final $Res Function(BotCredentialOperationCleanupPending) _then;

/// Create a copy of BotCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? configCommitted = null,}) {
  return _then(BotCredentialOperationCleanupPending(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,configCommitted: null == configCommitted ? _self.configCommitted : configCommitted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BotRegistrationStatus {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationStatus);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotRegistrationStatusCopyWith<$Res>  {
$BotRegistrationStatusCopyWith(BotRegistrationStatus _, $Res Function(BotRegistrationStatus) __);
}


/// Adds pattern-matching-related methods to [BotRegistrationStatus].
extension BotRegistrationStatusPatterns on BotRegistrationStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotRegistrationIdle value)?  idle,TResult Function( BotRegistrationPreparing value)?  preparing,TResult Function( BotRegistrationWaiting value)?  waiting,TResult Function( BotRegistrationSlowDown value)?  slowDown,TResult Function( BotRegistrationCompleted value)?  completed,TResult Function( BotRegistrationCommitting value)?  committing,TResult Function( BotRegistrationDenied value)?  denied,TResult Function( BotRegistrationExpired value)?  expired,TResult Function( BotRegistrationCancelled value)?  cancelled,TResult Function( BotRegistrationFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotRegistrationIdle() when idle != null:
return idle(_that);case BotRegistrationPreparing() when preparing != null:
return preparing(_that);case BotRegistrationWaiting() when waiting != null:
return waiting(_that);case BotRegistrationSlowDown() when slowDown != null:
return slowDown(_that);case BotRegistrationCompleted() when completed != null:
return completed(_that);case BotRegistrationCommitting() when committing != null:
return committing(_that);case BotRegistrationDenied() when denied != null:
return denied(_that);case BotRegistrationExpired() when expired != null:
return expired(_that);case BotRegistrationCancelled() when cancelled != null:
return cancelled(_that);case BotRegistrationFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotRegistrationIdle value)  idle,required TResult Function( BotRegistrationPreparing value)  preparing,required TResult Function( BotRegistrationWaiting value)  waiting,required TResult Function( BotRegistrationSlowDown value)  slowDown,required TResult Function( BotRegistrationCompleted value)  completed,required TResult Function( BotRegistrationCommitting value)  committing,required TResult Function( BotRegistrationDenied value)  denied,required TResult Function( BotRegistrationExpired value)  expired,required TResult Function( BotRegistrationCancelled value)  cancelled,required TResult Function( BotRegistrationFailed value)  failed,}){
final _that = this;
switch (_that) {
case BotRegistrationIdle():
return idle(_that);case BotRegistrationPreparing():
return preparing(_that);case BotRegistrationWaiting():
return waiting(_that);case BotRegistrationSlowDown():
return slowDown(_that);case BotRegistrationCompleted():
return completed(_that);case BotRegistrationCommitting():
return committing(_that);case BotRegistrationDenied():
return denied(_that);case BotRegistrationExpired():
return expired(_that);case BotRegistrationCancelled():
return cancelled(_that);case BotRegistrationFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotRegistrationIdle value)?  idle,TResult? Function( BotRegistrationPreparing value)?  preparing,TResult? Function( BotRegistrationWaiting value)?  waiting,TResult? Function( BotRegistrationSlowDown value)?  slowDown,TResult? Function( BotRegistrationCompleted value)?  completed,TResult? Function( BotRegistrationCommitting value)?  committing,TResult? Function( BotRegistrationDenied value)?  denied,TResult? Function( BotRegistrationExpired value)?  expired,TResult? Function( BotRegistrationCancelled value)?  cancelled,TResult? Function( BotRegistrationFailed value)?  failed,}){
final _that = this;
switch (_that) {
case BotRegistrationIdle() when idle != null:
return idle(_that);case BotRegistrationPreparing() when preparing != null:
return preparing(_that);case BotRegistrationWaiting() when waiting != null:
return waiting(_that);case BotRegistrationSlowDown() when slowDown != null:
return slowDown(_that);case BotRegistrationCompleted() when completed != null:
return completed(_that);case BotRegistrationCommitting() when committing != null:
return committing(_that);case BotRegistrationDenied() when denied != null:
return denied(_that);case BotRegistrationExpired() when expired != null:
return expired(_that);case BotRegistrationCancelled() when cancelled != null:
return cancelled(_that);case BotRegistrationFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( String attemptId)?  preparing,TResult Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)?  waiting,TResult Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)?  slowDown,TResult Function( String attemptId)?  completed,TResult Function( String attemptId,  String botId)?  committing,TResult Function( String attemptId,  String message)?  denied,TResult Function( String attemptId)?  expired,TResult Function( String attemptId)?  cancelled,TResult Function( String attemptId,  String code,  String message,  bool retryable)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BotRegistrationIdle() when idle != null:
return idle();case BotRegistrationPreparing() when preparing != null:
return preparing(_that.attemptId);case BotRegistrationWaiting() when waiting != null:
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationSlowDown() when slowDown != null:
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationCompleted() when completed != null:
return completed(_that.attemptId);case BotRegistrationCommitting() when committing != null:
return committing(_that.attemptId,_that.botId);case BotRegistrationDenied() when denied != null:
return denied(_that.attemptId,_that.message);case BotRegistrationExpired() when expired != null:
return expired(_that.attemptId);case BotRegistrationCancelled() when cancelled != null:
return cancelled(_that.attemptId);case BotRegistrationFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( String attemptId)  preparing,required TResult Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)  waiting,required TResult Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)  slowDown,required TResult Function( String attemptId)  completed,required TResult Function( String attemptId,  String botId)  committing,required TResult Function( String attemptId,  String message)  denied,required TResult Function( String attemptId)  expired,required TResult Function( String attemptId)  cancelled,required TResult Function( String attemptId,  String code,  String message,  bool retryable)  failed,}) {final _that = this;
switch (_that) {
case BotRegistrationIdle():
return idle();case BotRegistrationPreparing():
return preparing(_that.attemptId);case BotRegistrationWaiting():
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationSlowDown():
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationCompleted():
return completed(_that.attemptId);case BotRegistrationCommitting():
return committing(_that.attemptId,_that.botId);case BotRegistrationDenied():
return denied(_that.attemptId,_that.message);case BotRegistrationExpired():
return expired(_that.attemptId);case BotRegistrationCancelled():
return cancelled(_that.attemptId);case BotRegistrationFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( String attemptId)?  preparing,TResult? Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)?  waiting,TResult? Function( String attemptId,  String verificationUrl,  int expiresAt,  int intervalSeconds)?  slowDown,TResult? Function( String attemptId)?  completed,TResult? Function( String attemptId,  String botId)?  committing,TResult? Function( String attemptId,  String message)?  denied,TResult? Function( String attemptId)?  expired,TResult? Function( String attemptId)?  cancelled,TResult? Function( String attemptId,  String code,  String message,  bool retryable)?  failed,}) {final _that = this;
switch (_that) {
case BotRegistrationIdle() when idle != null:
return idle();case BotRegistrationPreparing() when preparing != null:
return preparing(_that.attemptId);case BotRegistrationWaiting() when waiting != null:
return waiting(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationSlowDown() when slowDown != null:
return slowDown(_that.attemptId,_that.verificationUrl,_that.expiresAt,_that.intervalSeconds);case BotRegistrationCompleted() when completed != null:
return completed(_that.attemptId);case BotRegistrationCommitting() when committing != null:
return committing(_that.attemptId,_that.botId);case BotRegistrationDenied() when denied != null:
return denied(_that.attemptId,_that.message);case BotRegistrationExpired() when expired != null:
return expired(_that.attemptId);case BotRegistrationCancelled() when cancelled != null:
return cancelled(_that.attemptId);case BotRegistrationFailed() when failed != null:
return failed(_that.attemptId,_that.code,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class BotRegistrationIdle extends BotRegistrationStatus {
  const BotRegistrationIdle(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationIdle);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BotRegistrationPreparing extends BotRegistrationStatus {
  const BotRegistrationPreparing({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationPreparingCopyWith<BotRegistrationPreparing> get copyWith => _$BotRegistrationPreparingCopyWithImpl<BotRegistrationPreparing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationPreparing&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationPreparingCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationPreparingCopyWith(BotRegistrationPreparing value, $Res Function(BotRegistrationPreparing) _then) = _$BotRegistrationPreparingCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BotRegistrationPreparingCopyWithImpl<$Res>
    implements $BotRegistrationPreparingCopyWith<$Res> {
  _$BotRegistrationPreparingCopyWithImpl(this._self, this._then);

  final BotRegistrationPreparing _self;
  final $Res Function(BotRegistrationPreparing) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BotRegistrationPreparing(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationWaiting extends BotRegistrationStatus {
  const BotRegistrationWaiting({required this.attemptId, required this.verificationUrl, required this.expiresAt, required this.intervalSeconds}): super._();


 final  String attemptId;
 final  String verificationUrl;
 final  int expiresAt;
 final  int intervalSeconds;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationWaitingCopyWith<BotRegistrationWaiting> get copyWith => _$BotRegistrationWaitingCopyWithImpl<BotRegistrationWaiting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationWaiting&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.verificationUrl, verificationUrl) || other.verificationUrl == verificationUrl)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.intervalSeconds, intervalSeconds) || other.intervalSeconds == intervalSeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,verificationUrl,expiresAt,intervalSeconds);
}



}

/// @nodoc
abstract mixin class $BotRegistrationWaitingCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationWaitingCopyWith(BotRegistrationWaiting value, $Res Function(BotRegistrationWaiting) _then) = _$BotRegistrationWaitingCopyWithImpl;
@useResult
$Res call({
 String attemptId, String verificationUrl, int expiresAt, int intervalSeconds
});




}
/// @nodoc
class _$BotRegistrationWaitingCopyWithImpl<$Res>
    implements $BotRegistrationWaitingCopyWith<$Res> {
  _$BotRegistrationWaitingCopyWithImpl(this._self, this._then);

  final BotRegistrationWaiting _self;
  final $Res Function(BotRegistrationWaiting) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? verificationUrl = null,Object? expiresAt = null,Object? intervalSeconds = null,}) {
  return _then(BotRegistrationWaiting(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,verificationUrl: null == verificationUrl ? _self.verificationUrl : verificationUrl // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as int,intervalSeconds: null == intervalSeconds ? _self.intervalSeconds : intervalSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BotRegistrationSlowDown extends BotRegistrationStatus {
  const BotRegistrationSlowDown({required this.attemptId, required this.verificationUrl, required this.expiresAt, required this.intervalSeconds}): super._();


 final  String attemptId;
 final  String verificationUrl;
 final  int expiresAt;
 final  int intervalSeconds;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationSlowDownCopyWith<BotRegistrationSlowDown> get copyWith => _$BotRegistrationSlowDownCopyWithImpl<BotRegistrationSlowDown>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationSlowDown&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.verificationUrl, verificationUrl) || other.verificationUrl == verificationUrl)&&(identical(other.expiresAt, expiresAt) || other.expiresAt == expiresAt)&&(identical(other.intervalSeconds, intervalSeconds) || other.intervalSeconds == intervalSeconds));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,verificationUrl,expiresAt,intervalSeconds);
}



}

/// @nodoc
abstract mixin class $BotRegistrationSlowDownCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationSlowDownCopyWith(BotRegistrationSlowDown value, $Res Function(BotRegistrationSlowDown) _then) = _$BotRegistrationSlowDownCopyWithImpl;
@useResult
$Res call({
 String attemptId, String verificationUrl, int expiresAt, int intervalSeconds
});




}
/// @nodoc
class _$BotRegistrationSlowDownCopyWithImpl<$Res>
    implements $BotRegistrationSlowDownCopyWith<$Res> {
  _$BotRegistrationSlowDownCopyWithImpl(this._self, this._then);

  final BotRegistrationSlowDown _self;
  final $Res Function(BotRegistrationSlowDown) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? verificationUrl = null,Object? expiresAt = null,Object? intervalSeconds = null,}) {
  return _then(BotRegistrationSlowDown(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,verificationUrl: null == verificationUrl ? _self.verificationUrl : verificationUrl // ignore: cast_nullable_to_non_nullable
as String,expiresAt: null == expiresAt ? _self.expiresAt : expiresAt // ignore: cast_nullable_to_non_nullable
as int,intervalSeconds: null == intervalSeconds ? _self.intervalSeconds : intervalSeconds // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class BotRegistrationCompleted extends BotRegistrationStatus {
  const BotRegistrationCompleted({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationCompletedCopyWith<BotRegistrationCompleted> get copyWith => _$BotRegistrationCompletedCopyWithImpl<BotRegistrationCompleted>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationCompleted&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationCompletedCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationCompletedCopyWith(BotRegistrationCompleted value, $Res Function(BotRegistrationCompleted) _then) = _$BotRegistrationCompletedCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BotRegistrationCompletedCopyWithImpl<$Res>
    implements $BotRegistrationCompletedCopyWith<$Res> {
  _$BotRegistrationCompletedCopyWithImpl(this._self, this._then);

  final BotRegistrationCompleted _self;
  final $Res Function(BotRegistrationCompleted) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BotRegistrationCompleted(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationCommitting extends BotRegistrationStatus {
  const BotRegistrationCommitting({required this.attemptId, required this.botId}): super._();


 final  String attemptId;
 final  String botId;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationCommittingCopyWith<BotRegistrationCommitting> get copyWith => _$BotRegistrationCommittingCopyWithImpl<BotRegistrationCommitting>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationCommitting&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.botId, botId) || other.botId == botId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,botId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationCommittingCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationCommittingCopyWith(BotRegistrationCommitting value, $Res Function(BotRegistrationCommitting) _then) = _$BotRegistrationCommittingCopyWithImpl;
@useResult
$Res call({
 String attemptId, String botId
});




}
/// @nodoc
class _$BotRegistrationCommittingCopyWithImpl<$Res>
    implements $BotRegistrationCommittingCopyWith<$Res> {
  _$BotRegistrationCommittingCopyWithImpl(this._self, this._then);

  final BotRegistrationCommitting _self;
  final $Res Function(BotRegistrationCommitting) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? botId = null,}) {
  return _then(BotRegistrationCommitting(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationDenied extends BotRegistrationStatus {
  const BotRegistrationDenied({required this.attemptId, required this.message}): super._();


 final  String attemptId;
 final  String message;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationDeniedCopyWith<BotRegistrationDenied> get copyWith => _$BotRegistrationDeniedCopyWithImpl<BotRegistrationDenied>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationDenied&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,message);
}



}

/// @nodoc
abstract mixin class $BotRegistrationDeniedCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationDeniedCopyWith(BotRegistrationDenied value, $Res Function(BotRegistrationDenied) _then) = _$BotRegistrationDeniedCopyWithImpl;
@useResult
$Res call({
 String attemptId, String message
});




}
/// @nodoc
class _$BotRegistrationDeniedCopyWithImpl<$Res>
    implements $BotRegistrationDeniedCopyWith<$Res> {
  _$BotRegistrationDeniedCopyWithImpl(this._self, this._then);

  final BotRegistrationDenied _self;
  final $Res Function(BotRegistrationDenied) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? message = null,}) {
  return _then(BotRegistrationDenied(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationExpired extends BotRegistrationStatus {
  const BotRegistrationExpired({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationExpiredCopyWith<BotRegistrationExpired> get copyWith => _$BotRegistrationExpiredCopyWithImpl<BotRegistrationExpired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationExpired&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationExpiredCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationExpiredCopyWith(BotRegistrationExpired value, $Res Function(BotRegistrationExpired) _then) = _$BotRegistrationExpiredCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BotRegistrationExpiredCopyWithImpl<$Res>
    implements $BotRegistrationExpiredCopyWith<$Res> {
  _$BotRegistrationExpiredCopyWithImpl(this._self, this._then);

  final BotRegistrationExpired _self;
  final $Res Function(BotRegistrationExpired) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BotRegistrationExpired(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationCancelled extends BotRegistrationStatus {
  const BotRegistrationCancelled({required this.attemptId}): super._();


 final  String attemptId;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationCancelledCopyWith<BotRegistrationCancelled> get copyWith => _$BotRegistrationCancelledCopyWithImpl<BotRegistrationCancelled>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationCancelled&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationCancelledCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationCancelledCopyWith(BotRegistrationCancelled value, $Res Function(BotRegistrationCancelled) _then) = _$BotRegistrationCancelledCopyWithImpl;
@useResult
$Res call({
 String attemptId
});




}
/// @nodoc
class _$BotRegistrationCancelledCopyWithImpl<$Res>
    implements $BotRegistrationCancelledCopyWith<$Res> {
  _$BotRegistrationCancelledCopyWithImpl(this._self, this._then);

  final BotRegistrationCancelled _self;
  final $Res Function(BotRegistrationCancelled) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,}) {
  return _then(BotRegistrationCancelled(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BotRegistrationFailed extends BotRegistrationStatus {
  const BotRegistrationFailed({required this.attemptId, required this.code, required this.message, required this.retryable}): super._();


 final  String attemptId;
 final  String code;
 final  String message;
 final  bool retryable;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationFailedCopyWith<BotRegistrationFailed> get copyWith => _$BotRegistrationFailedCopyWithImpl<BotRegistrationFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationFailed&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,code,message,retryable);
}



}

/// @nodoc
abstract mixin class $BotRegistrationFailedCopyWith<$Res> implements $BotRegistrationStatusCopyWith<$Res> {
  factory $BotRegistrationFailedCopyWith(BotRegistrationFailed value, $Res Function(BotRegistrationFailed) _then) = _$BotRegistrationFailedCopyWithImpl;
@useResult
$Res call({
 String attemptId, String code, String message, bool retryable
});




}
/// @nodoc
class _$BotRegistrationFailedCopyWithImpl<$Res>
    implements $BotRegistrationFailedCopyWith<$Res> {
  _$BotRegistrationFailedCopyWithImpl(this._self, this._then);

  final BotRegistrationFailed _self;
  final $Res Function(BotRegistrationFailed) _then;

/// Create a copy of BotRegistrationStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(BotRegistrationFailed(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$BotPairingRequest {

 String get requestId; String get botId; String get openId; String? get displayName; int get createdAt;
/// Create a copy of BotPairingRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotPairingRequestCopyWith<BotPairingRequest> get copyWith => _$BotPairingRequestCopyWithImpl<BotPairingRequest>(this as BotPairingRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotPairingRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotPairingRequest&&(identical(other.requestId, _this.requestId) || other.requestId == _this.requestId)&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.openId, _this.openId) || other.openId == _this.openId)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt));
}


@override
int get hashCode {
  final _this = this as BotPairingRequest;
  return Object.hash(runtimeType,_this.requestId,_this.botId,_this.openId,_this.displayName,_this.createdAt);
}



}

/// @nodoc
abstract mixin class $BotPairingRequestCopyWith<$Res>  {
  factory $BotPairingRequestCopyWith(BotPairingRequest value, $Res Function(BotPairingRequest) _then) = _$BotPairingRequestCopyWithImpl;
@useResult
$Res call({
 String requestId, String botId, String openId, String? displayName, int createdAt
});




}
/// @nodoc
class _$BotPairingRequestCopyWithImpl<$Res>
    implements $BotPairingRequestCopyWith<$Res> {
  _$BotPairingRequestCopyWithImpl(this._self, this._then);

  final BotPairingRequest _self;
  final $Res Function(BotPairingRequest) _then;

/// Create a copy of BotPairingRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? requestId = null,Object? botId = null,Object? openId = null,Object? displayName = freezed,Object? createdAt = null,}) {
  return _then(BotPairingRequest(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,openId: null == openId ? _self.openId : openId // ignore: cast_nullable_to_non_nullable
as String,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [BotPairingRequest].
extension BotPairingRequestPatterns on BotPairingRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotPairingRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotPairingRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotPairingRequest value)  $default,){
final _that = this;
switch (_that) {
case _BotPairingRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotPairingRequest value)?  $default,){
final _that = this;
switch (_that) {
case _BotPairingRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String requestId,  String botId,  String openId,  String? displayName,  int createdAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotPairingRequest() when $default != null:
return $default(_that.requestId,_that.botId,_that.openId,_that.displayName,_that.createdAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String requestId,  String botId,  String openId,  String? displayName,  int createdAt)  $default,) {final _that = this;
switch (_that) {
case _BotPairingRequest():
return $default(_that.requestId,_that.botId,_that.openId,_that.displayName,_that.createdAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String requestId,  String botId,  String openId,  String? displayName,  int createdAt)?  $default,) {final _that = this;
switch (_that) {
case _BotPairingRequest() when $default != null:
return $default(_that.requestId,_that.botId,_that.openId,_that.displayName,_that.createdAt);case _:
  return null;

}
}

}

/// @nodoc


class _BotPairingRequest implements BotPairingRequest {
  const _BotPairingRequest({required this.requestId, required this.botId, required this.openId, required this.displayName, required this.createdAt});


@override final  String requestId;
@override final  String botId;
@override final  String openId;
@override final  String? displayName;
@override final  int createdAt;

/// Create a copy of BotPairingRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotPairingRequestCopyWith<_BotPairingRequest> get copyWith => __$BotPairingRequestCopyWithImpl<_BotPairingRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotPairingRequest&&(identical(other.requestId, requestId) || other.requestId == requestId)&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.openId, openId) || other.openId == openId)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,requestId,botId,openId,displayName,createdAt);
}



}

/// @nodoc
abstract mixin class _$BotPairingRequestCopyWith<$Res> implements $BotPairingRequestCopyWith<$Res> {
  factory _$BotPairingRequestCopyWith(_BotPairingRequest value, $Res Function(_BotPairingRequest) _then) = __$BotPairingRequestCopyWithImpl;
@override @useResult
$Res call({
 String requestId, String botId, String openId, String? displayName, int createdAt
});




}
/// @nodoc
class __$BotPairingRequestCopyWithImpl<$Res>
    implements _$BotPairingRequestCopyWith<$Res> {
  __$BotPairingRequestCopyWithImpl(this._self, this._then);

  final _BotPairingRequest _self;
  final $Res Function(_BotPairingRequest) _then;

/// Create a copy of BotPairingRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? requestId = null,Object? botId = null,Object? openId = null,Object? displayName = freezed,Object? createdAt = null,}) {
  return _then(_BotPairingRequest(
requestId: null == requestId ? _self.requestId : requestId // ignore: cast_nullable_to_non_nullable
as String,botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,openId: null == openId ? _self.openId : openId // ignore: cast_nullable_to_non_nullable
as String,displayName: freezed == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String?,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$BotDiagnostic {

 String get code; String get message; bool get retryable; String? get platformCode; String? get guidance;
/// Create a copy of BotDiagnostic
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<BotDiagnostic> get copyWith => _$BotDiagnosticCopyWithImpl<BotDiagnostic>(this as BotDiagnostic, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotDiagnostic;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotDiagnostic&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable)&&(identical(other.platformCode, _this.platformCode) || other.platformCode == _this.platformCode)&&(identical(other.guidance, _this.guidance) || other.guidance == _this.guidance));
}


@override
int get hashCode {
  final _this = this as BotDiagnostic;
  return Object.hash(runtimeType,_this.code,_this.message,_this.retryable,_this.platformCode,_this.guidance);
}



}

/// @nodoc
abstract mixin class $BotDiagnosticCopyWith<$Res>  {
  factory $BotDiagnosticCopyWith(BotDiagnostic value, $Res Function(BotDiagnostic) _then) = _$BotDiagnosticCopyWithImpl;
@useResult
$Res call({
 String code, String message, bool retryable, String? platformCode, String? guidance
});




}
/// @nodoc
class _$BotDiagnosticCopyWithImpl<$Res>
    implements $BotDiagnosticCopyWith<$Res> {
  _$BotDiagnosticCopyWithImpl(this._self, this._then);

  final BotDiagnostic _self;
  final $Res Function(BotDiagnostic) _then;

/// Create a copy of BotDiagnostic
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? platformCode = freezed,Object? guidance = freezed,}) {
  return _then(BotDiagnostic(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,platformCode: freezed == platformCode ? _self.platformCode : platformCode // ignore: cast_nullable_to_non_nullable
as String?,guidance: freezed == guidance ? _self.guidance : guidance // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BotDiagnostic].
extension BotDiagnosticPatterns on BotDiagnostic {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotDiagnostic value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotDiagnostic() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotDiagnostic value)  $default,){
final _that = this;
switch (_that) {
case _BotDiagnostic():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotDiagnostic value)?  $default,){
final _that = this;
switch (_that) {
case _BotDiagnostic() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String message,  bool retryable,  String? platformCode,  String? guidance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotDiagnostic() when $default != null:
return $default(_that.code,_that.message,_that.retryable,_that.platformCode,_that.guidance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String message,  bool retryable,  String? platformCode,  String? guidance)  $default,) {final _that = this;
switch (_that) {
case _BotDiagnostic():
return $default(_that.code,_that.message,_that.retryable,_that.platformCode,_that.guidance);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String message,  bool retryable,  String? platformCode,  String? guidance)?  $default,) {final _that = this;
switch (_that) {
case _BotDiagnostic() when $default != null:
return $default(_that.code,_that.message,_that.retryable,_that.platformCode,_that.guidance);case _:
  return null;

}
}

}

/// @nodoc


class _BotDiagnostic implements BotDiagnostic {
  const _BotDiagnostic({required this.code, required this.message, required this.retryable, required this.platformCode, required this.guidance});


@override final  String code;
@override final  String message;
@override final  bool retryable;
@override final  String? platformCode;
@override final  String? guidance;

/// Create a copy of BotDiagnostic
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotDiagnosticCopyWith<_BotDiagnostic> get copyWith => __$BotDiagnosticCopyWithImpl<_BotDiagnostic>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotDiagnostic&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable)&&(identical(other.platformCode, platformCode) || other.platformCode == platformCode)&&(identical(other.guidance, guidance) || other.guidance == guidance));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable,platformCode,guidance);
}



}

/// @nodoc
abstract mixin class _$BotDiagnosticCopyWith<$Res> implements $BotDiagnosticCopyWith<$Res> {
  factory _$BotDiagnosticCopyWith(_BotDiagnostic value, $Res Function(_BotDiagnostic) _then) = __$BotDiagnosticCopyWithImpl;
@override @useResult
$Res call({
 String code, String message, bool retryable, String? platformCode, String? guidance
});




}
/// @nodoc
class __$BotDiagnosticCopyWithImpl<$Res>
    implements _$BotDiagnosticCopyWith<$Res> {
  __$BotDiagnosticCopyWithImpl(this._self, this._then);

  final _BotDiagnostic _self;
  final $Res Function(_BotDiagnostic) _then;

/// Create a copy of BotDiagnostic
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,Object? platformCode = freezed,Object? guidance = freezed,}) {
  return _then(_BotDiagnostic(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,platformCode: freezed == platformCode ? _self.platformCode : platformCode // ignore: cast_nullable_to_non_nullable
as String?,guidance: freezed == guidance ? _self.guidance : guidance // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$BotSnapshot {


/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotSnapshotCopyWith<BotSnapshot> get copyWith => _$BotSnapshotCopyWithImpl<BotSnapshot>(this as BotSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotSnapshot&&(identical(other.lastActivityAt, _this.lastActivityAt) || other.lastActivityAt == _this.lastActivityAt)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.appId, _this.appId) || other.appId == _this.appId)&&(identical(other.platform, _this.platform) || other.platform == _this.platform)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.toolsEnabled, _this.toolsEnabled) || other.toolsEnabled == _this.toolsEnabled)&&(identical(other.modelRoute, _this.modelRoute) || other.modelRoute == _this.modelRoute)&&(identical(other.workspacePath, _this.workspacePath) || other.workspacePath == _this.workspacePath)&&(identical(other.configRevision, _this.configRevision) || other.configRevision == _this.configRevision)&&const DeepCollectionEquality().equals(other.trustedOpenIds, _this.trustedOpenIds)&&const DeepCollectionEquality().equals(other.trustedChatIds, _this.trustedChatIds)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&(identical(other.credential, _this.credential) || other.credential == _this.credential)&&(identical(other.credentialOperation, _this.credentialOperation) || other.credentialOperation == _this.credentialOperation)&&const DeepCollectionEquality().equals(other.pairing, _this.pairing)&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic)&&(identical(other.canChangeProject, _this.canChangeProject) || other.canChangeProject == _this.canChangeProject)&&(identical(other.canChangeAppId, _this.canChangeAppId) || other.canChangeAppId == _this.canChangeAppId)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as BotSnapshot;
  return Object.hashAll([runtimeType,_this.lastActivityAt,_this.id,_this.name,_this.projectId,_this.appId,_this.platform,_this.enabled,_this.toolsEnabled,_this.modelRoute,_this.workspacePath,_this.configRevision,const DeepCollectionEquality().hash(_this.trustedOpenIds),const DeepCollectionEquality().hash(_this.trustedChatIds),_this.connection,_this.credential,_this.credentialOperation,const DeepCollectionEquality().hash(_this.pairing),_this.diagnostic,_this.canChangeProject,_this.canChangeAppId,_this.createdAt,_this.updatedAt]);
}



}

/// @nodoc
abstract mixin class $BotSnapshotCopyWith<$Res>  {
  factory $BotSnapshotCopyWith(BotSnapshot value, $Res Function(BotSnapshot) _then) = _$BotSnapshotCopyWithImpl;
@useResult
$Res call({
 int? lastActivityAt, String id, String name, String projectId, String appId, BotPlatform platform, bool enabled, bool toolsEnabled, BotModelRoute? modelRoute, String workspacePath, int configRevision, List<String> trustedOpenIds, List<String> trustedChatIds, BotConnectionState connection, BotCredentialAvailability credential, BotCredentialOperation credentialOperation, List<BotPairingRequest> pairing, BotDiagnostic? diagnostic, bool canChangeProject, bool canChangeAppId, int createdAt, int updatedAt
});


$BotModelRouteCopyWith<$Res>? get modelRoute;$BotConnectionStateCopyWith<$Res> get connection;$BotCredentialOperationCopyWith<$Res> get credentialOperation;$BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class _$BotSnapshotCopyWithImpl<$Res>
    implements $BotSnapshotCopyWith<$Res> {
  _$BotSnapshotCopyWithImpl(this._self, this._then);

  final BotSnapshot _self;
  final $Res Function(BotSnapshot) _then;

/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? lastActivityAt = freezed,Object? id = null,Object? name = null,Object? projectId = null,Object? appId = null,Object? platform = null,Object? enabled = null,Object? toolsEnabled = null,Object? modelRoute = freezed,Object? workspacePath = null,Object? configRevision = null,Object? trustedOpenIds = null,Object? trustedChatIds = null,Object? connection = null,Object? credential = null,Object? credentialOperation = null,Object? pairing = null,Object? diagnostic = freezed,Object? canChangeProject = null,Object? canChangeAppId = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(BotSnapshot(
lastActivityAt: freezed == lastActivityAt ? _self.lastActivityAt : lastActivityAt // ignore: cast_nullable_to_non_nullable
as int?,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,appId: null == appId ? _self.appId : appId // ignore: cast_nullable_to_non_nullable
as String,platform: null == platform ? _self.platform : platform // ignore: cast_nullable_to_non_nullable
as BotPlatform,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,toolsEnabled: null == toolsEnabled ? _self.toolsEnabled : toolsEnabled // ignore: cast_nullable_to_non_nullable
as bool,modelRoute: freezed == modelRoute ? _self.modelRoute : modelRoute // ignore: cast_nullable_to_non_nullable
as BotModelRoute?,workspacePath: null == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as String,configRevision: null == configRevision ? _self.configRevision : configRevision // ignore: cast_nullable_to_non_nullable
as int,trustedOpenIds: null == trustedOpenIds ? _self.trustedOpenIds : trustedOpenIds // ignore: cast_nullable_to_non_nullable
as List<String>,trustedChatIds: null == trustedChatIds ? _self.trustedChatIds : trustedChatIds // ignore: cast_nullable_to_non_nullable
as List<String>,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as BotConnectionState,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as BotCredentialAvailability,credentialOperation: null == credentialOperation ? _self.credentialOperation : credentialOperation // ignore: cast_nullable_to_non_nullable
as BotCredentialOperation,pairing: null == pairing ? _self.pairing : pairing // ignore: cast_nullable_to_non_nullable
as List<BotPairingRequest>,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,canChangeProject: null == canChangeProject ? _self.canChangeProject : canChangeProject // ignore: cast_nullable_to_non_nullable
as bool,canChangeAppId: null == canChangeAppId ? _self.canChangeAppId : canChangeAppId // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotModelRouteCopyWith<$Res>? get modelRoute {
    if (_self.modelRoute == null) {
    return null;
  }

  return $BotModelRouteCopyWith<$Res>(_self.modelRoute!, (value) {
    return _then(_self.copyWith(modelRoute: value));
  });
}/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConnectionStateCopyWith<$Res> get connection {

  return $BotConnectionStateCopyWith<$Res>(_self.connection, (value) {
    return _then(_self.copyWith(connection: value));
  });
}/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotCredentialOperationCopyWith<$Res> get credentialOperation {

  return $BotCredentialOperationCopyWith<$Res>(_self.credentialOperation, (value) {
    return _then(_self.copyWith(credentialOperation: value));
  });
}/// Create a copy of BotSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotSnapshot].
extension BotSnapshotPatterns on BotSnapshot {
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
mixin _$BotPendingCredentialOperation {

 String get botId; BotCredentialOperation get credentialOperation; BotDiagnostic? get diagnostic;
/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotPendingCredentialOperationCopyWith<BotPendingCredentialOperation> get copyWith => _$BotPendingCredentialOperationCopyWithImpl<BotPendingCredentialOperation>(this as BotPendingCredentialOperation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotPendingCredentialOperation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotPendingCredentialOperation&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.credentialOperation, _this.credentialOperation) || other.credentialOperation == _this.credentialOperation)&&(identical(other.diagnostic, _this.diagnostic) || other.diagnostic == _this.diagnostic));
}


@override
int get hashCode {
  final _this = this as BotPendingCredentialOperation;
  return Object.hash(runtimeType,_this.botId,_this.credentialOperation,_this.diagnostic);
}



}

/// @nodoc
abstract mixin class $BotPendingCredentialOperationCopyWith<$Res>  {
  factory $BotPendingCredentialOperationCopyWith(BotPendingCredentialOperation value, $Res Function(BotPendingCredentialOperation) _then) = _$BotPendingCredentialOperationCopyWithImpl;
@useResult
$Res call({
 String botId, BotCredentialOperation credentialOperation, BotDiagnostic? diagnostic
});


$BotCredentialOperationCopyWith<$Res> get credentialOperation;$BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class _$BotPendingCredentialOperationCopyWithImpl<$Res>
    implements $BotPendingCredentialOperationCopyWith<$Res> {
  _$BotPendingCredentialOperationCopyWithImpl(this._self, this._then);

  final BotPendingCredentialOperation _self;
  final $Res Function(BotPendingCredentialOperation) _then;

/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? credentialOperation = null,Object? diagnostic = freezed,}) {
  return _then(BotPendingCredentialOperation(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,credentialOperation: null == credentialOperation ? _self.credentialOperation : credentialOperation // ignore: cast_nullable_to_non_nullable
as BotCredentialOperation,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,
  ));
}
/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotCredentialOperationCopyWith<$Res> get credentialOperation {

  return $BotCredentialOperationCopyWith<$Res>(_self.credentialOperation, (value) {
    return _then(_self.copyWith(credentialOperation: value));
  });
}/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotPendingCredentialOperation].
extension BotPendingCredentialOperationPatterns on BotPendingCredentialOperation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotPendingCredentialOperation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotPendingCredentialOperation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotPendingCredentialOperation value)  $default,){
final _that = this;
switch (_that) {
case _BotPendingCredentialOperation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotPendingCredentialOperation value)?  $default,){
final _that = this;
switch (_that) {
case _BotPendingCredentialOperation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String botId,  BotCredentialOperation credentialOperation,  BotDiagnostic? diagnostic)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotPendingCredentialOperation() when $default != null:
return $default(_that.botId,_that.credentialOperation,_that.diagnostic);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String botId,  BotCredentialOperation credentialOperation,  BotDiagnostic? diagnostic)  $default,) {final _that = this;
switch (_that) {
case _BotPendingCredentialOperation():
return $default(_that.botId,_that.credentialOperation,_that.diagnostic);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String botId,  BotCredentialOperation credentialOperation,  BotDiagnostic? diagnostic)?  $default,) {final _that = this;
switch (_that) {
case _BotPendingCredentialOperation() when $default != null:
return $default(_that.botId,_that.credentialOperation,_that.diagnostic);case _:
  return null;

}
}

}

/// @nodoc


class _BotPendingCredentialOperation implements BotPendingCredentialOperation {
  const _BotPendingCredentialOperation({required this.botId, required this.credentialOperation, required this.diagnostic});


@override final  String botId;
@override final  BotCredentialOperation credentialOperation;
@override final  BotDiagnostic? diagnostic;

/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotPendingCredentialOperationCopyWith<_BotPendingCredentialOperation> get copyWith => __$BotPendingCredentialOperationCopyWithImpl<_BotPendingCredentialOperation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotPendingCredentialOperation&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.credentialOperation, credentialOperation) || other.credentialOperation == credentialOperation)&&(identical(other.diagnostic, diagnostic) || other.diagnostic == diagnostic));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,credentialOperation,diagnostic);
}



}

/// @nodoc
abstract mixin class _$BotPendingCredentialOperationCopyWith<$Res> implements $BotPendingCredentialOperationCopyWith<$Res> {
  factory _$BotPendingCredentialOperationCopyWith(_BotPendingCredentialOperation value, $Res Function(_BotPendingCredentialOperation) _then) = __$BotPendingCredentialOperationCopyWithImpl;
@override @useResult
$Res call({
 String botId, BotCredentialOperation credentialOperation, BotDiagnostic? diagnostic
});


@override $BotCredentialOperationCopyWith<$Res> get credentialOperation;@override $BotDiagnosticCopyWith<$Res>? get diagnostic;

}
/// @nodoc
class __$BotPendingCredentialOperationCopyWithImpl<$Res>
    implements _$BotPendingCredentialOperationCopyWith<$Res> {
  __$BotPendingCredentialOperationCopyWithImpl(this._self, this._then);

  final _BotPendingCredentialOperation _self;
  final $Res Function(_BotPendingCredentialOperation) _then;

/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = null,Object? credentialOperation = null,Object? diagnostic = freezed,}) {
  return _then(_BotPendingCredentialOperation(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,credentialOperation: null == credentialOperation ? _self.credentialOperation : credentialOperation // ignore: cast_nullable_to_non_nullable
as BotCredentialOperation,diagnostic: freezed == diagnostic ? _self.diagnostic : diagnostic // ignore: cast_nullable_to_non_nullable
as BotDiagnostic?,
  ));
}

/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotCredentialOperationCopyWith<$Res> get credentialOperation {

  return $BotCredentialOperationCopyWith<$Res>(_self.credentialOperation, (value) {
    return _then(_self.copyWith(credentialOperation: value));
  });
}/// Create a copy of BotPendingCredentialOperation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotDiagnosticCopyWith<$Res>? get diagnostic {
    if (_self.diagnostic == null) {
    return null;
  }

  return $BotDiagnosticCopyWith<$Res>(_self.diagnostic!, (value) {
    return _then(_self.copyWith(diagnostic: value));
  });
}
}

/// @nodoc
mixin _$BotRegistrationAttempt {

 String get attemptId; String get name; String get projectId; BotRegistrationStatus get status; String? get completedBotId;
/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotRegistrationAttemptCopyWith<BotRegistrationAttempt> get copyWith => _$BotRegistrationAttemptCopyWithImpl<BotRegistrationAttempt>(this as BotRegistrationAttempt, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotRegistrationAttempt;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotRegistrationAttempt&&(identical(other.attemptId, _this.attemptId) || other.attemptId == _this.attemptId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.completedBotId, _this.completedBotId) || other.completedBotId == _this.completedBotId));
}


@override
int get hashCode {
  final _this = this as BotRegistrationAttempt;
  return Object.hash(runtimeType,_this.attemptId,_this.name,_this.projectId,_this.status,_this.completedBotId);
}



}

/// @nodoc
abstract mixin class $BotRegistrationAttemptCopyWith<$Res>  {
  factory $BotRegistrationAttemptCopyWith(BotRegistrationAttempt value, $Res Function(BotRegistrationAttempt) _then) = _$BotRegistrationAttemptCopyWithImpl;
@useResult
$Res call({
 String attemptId, String name, String projectId, BotRegistrationStatus status, String? completedBotId
});


$BotRegistrationStatusCopyWith<$Res> get status;

}
/// @nodoc
class _$BotRegistrationAttemptCopyWithImpl<$Res>
    implements $BotRegistrationAttemptCopyWith<$Res> {
  _$BotRegistrationAttemptCopyWithImpl(this._self, this._then);

  final BotRegistrationAttempt _self;
  final $Res Function(BotRegistrationAttempt) _then;

/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? attemptId = null,Object? name = null,Object? projectId = null,Object? status = null,Object? completedBotId = freezed,}) {
  return _then(BotRegistrationAttempt(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BotRegistrationStatus,completedBotId: freezed == completedBotId ? _self.completedBotId : completedBotId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotRegistrationStatusCopyWith<$Res> get status {

  return $BotRegistrationStatusCopyWith<$Res>(_self.status, (value) {
    return _then(_self.copyWith(status: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotRegistrationAttempt].
extension BotRegistrationAttemptPatterns on BotRegistrationAttempt {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotRegistrationAttempt value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotRegistrationAttempt() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotRegistrationAttempt value)  $default,){
final _that = this;
switch (_that) {
case _BotRegistrationAttempt():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotRegistrationAttempt value)?  $default,){
final _that = this;
switch (_that) {
case _BotRegistrationAttempt() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String attemptId,  String name,  String projectId,  BotRegistrationStatus status,  String? completedBotId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotRegistrationAttempt() when $default != null:
return $default(_that.attemptId,_that.name,_that.projectId,_that.status,_that.completedBotId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String attemptId,  String name,  String projectId,  BotRegistrationStatus status,  String? completedBotId)  $default,) {final _that = this;
switch (_that) {
case _BotRegistrationAttempt():
return $default(_that.attemptId,_that.name,_that.projectId,_that.status,_that.completedBotId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String attemptId,  String name,  String projectId,  BotRegistrationStatus status,  String? completedBotId)?  $default,) {final _that = this;
switch (_that) {
case _BotRegistrationAttempt() when $default != null:
return $default(_that.attemptId,_that.name,_that.projectId,_that.status,_that.completedBotId);case _:
  return null;

}
}

}

/// @nodoc


class _BotRegistrationAttempt implements BotRegistrationAttempt {
  const _BotRegistrationAttempt({required this.attemptId, required this.name, required this.projectId, required this.status, required this.completedBotId});


@override final  String attemptId;
@override final  String name;
@override final  String projectId;
@override final  BotRegistrationStatus status;
@override final  String? completedBotId;

/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotRegistrationAttemptCopyWith<_BotRegistrationAttempt> get copyWith => __$BotRegistrationAttemptCopyWithImpl<_BotRegistrationAttempt>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotRegistrationAttempt&&(identical(other.attemptId, attemptId) || other.attemptId == attemptId)&&(identical(other.name, name) || other.name == name)&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.status, status) || other.status == status)&&(identical(other.completedBotId, completedBotId) || other.completedBotId == completedBotId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attemptId,name,projectId,status,completedBotId);
}



}

/// @nodoc
abstract mixin class _$BotRegistrationAttemptCopyWith<$Res> implements $BotRegistrationAttemptCopyWith<$Res> {
  factory _$BotRegistrationAttemptCopyWith(_BotRegistrationAttempt value, $Res Function(_BotRegistrationAttempt) _then) = __$BotRegistrationAttemptCopyWithImpl;
@override @useResult
$Res call({
 String attemptId, String name, String projectId, BotRegistrationStatus status, String? completedBotId
});


@override $BotRegistrationStatusCopyWith<$Res> get status;

}
/// @nodoc
class __$BotRegistrationAttemptCopyWithImpl<$Res>
    implements _$BotRegistrationAttemptCopyWith<$Res> {
  __$BotRegistrationAttemptCopyWithImpl(this._self, this._then);

  final _BotRegistrationAttempt _self;
  final $Res Function(_BotRegistrationAttempt) _then;

/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? attemptId = null,Object? name = null,Object? projectId = null,Object? status = null,Object? completedBotId = freezed,}) {
  return _then(_BotRegistrationAttempt(
attemptId: null == attemptId ? _self.attemptId : attemptId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BotRegistrationStatus,completedBotId: freezed == completedBotId ? _self.completedBotId : completedBotId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of BotRegistrationAttempt
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotRegistrationStatusCopyWith<$Res> get status {

  return $BotRegistrationStatusCopyWith<$Res>(_self.status, (value) {
    return _then(_self.copyWith(status: value));
  });
}
}

/// @nodoc
mixin _$BotsStateSnapshot {


/// Create a copy of BotsStateSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsStateSnapshotCopyWith<BotsStateSnapshot> get copyWith => _$BotsStateSnapshotCopyWithImpl<BotsStateSnapshot>(this as BotsStateSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsStateSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsStateSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&const DeepCollectionEquality().equals(other.bots, _this.bots)&&(identical(other.registration, _this.registration) || other.registration == _this.registration)&&const DeepCollectionEquality().equals(other.pendingCredentialOperations, _this.pendingCredentialOperations));
}


@override
int get hashCode {
  final _this = this as BotsStateSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,const DeepCollectionEquality().hash(_this.bots),_this.registration,const DeepCollectionEquality().hash(_this.pendingCredentialOperations));
}



}

/// @nodoc
abstract mixin class $BotsStateSnapshotCopyWith<$Res>  {
  factory $BotsStateSnapshotCopyWith(BotsStateSnapshot value, $Res Function(BotsStateSnapshot) _then) = _$BotsStateSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, List<BotSnapshot> bots, BotRegistrationAttempt? registration, List<BotPendingCredentialOperation> pendingCredentialOperations
});


$BotRegistrationAttemptCopyWith<$Res>? get registration;

}
/// @nodoc
class _$BotsStateSnapshotCopyWithImpl<$Res>
    implements $BotsStateSnapshotCopyWith<$Res> {
  _$BotsStateSnapshotCopyWithImpl(this._self, this._then);

  final BotsStateSnapshot _self;
  final $Res Function(BotsStateSnapshot) _then;

/// Create a copy of BotsStateSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? bots = null,Object? registration = freezed,Object? pendingCredentialOperations = null,}) {
  return _then(BotsStateSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,bots: null == bots ? _self.bots : bots // ignore: cast_nullable_to_non_nullable
as List<BotSnapshot>,registration: freezed == registration ? _self.registration : registration // ignore: cast_nullable_to_non_nullable
as BotRegistrationAttempt?,pendingCredentialOperations: null == pendingCredentialOperations ? _self.pendingCredentialOperations : pendingCredentialOperations // ignore: cast_nullable_to_non_nullable
as List<BotPendingCredentialOperation>,
  ));
}
/// Create a copy of BotsStateSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotRegistrationAttemptCopyWith<$Res>? get registration {
    if (_self.registration == null) {
    return null;
  }

  return $BotRegistrationAttemptCopyWith<$Res>(_self.registration!, (value) {
    return _then(_self.copyWith(registration: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsStateSnapshot].
extension BotsStateSnapshotPatterns on BotsStateSnapshot {
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

// dart format on
