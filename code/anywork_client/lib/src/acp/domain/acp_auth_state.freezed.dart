// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_auth_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAuthState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AcpAuthStateCopyWith<$Res>  {
$AcpAuthStateCopyWith(AcpAuthState _, $Res Function(AcpAuthState) __);
}


/// Adds pattern-matching-related methods to [AcpAuthState].
extension AcpAuthStatePatterns on AcpAuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpAuthUnchecked value)?  unchecked,TResult Function( AcpAuthChecking value)?  checking,TResult Function( AcpAuthRequired value)?  required,TResult Function( AcpAuthAuthenticating value)?  authenticating,TResult Function( AcpAuthVerifying value)?  verifying,TResult Function( AcpAuthClosing value)?  closing,TResult Function( AcpAuthVerified value)?  verified,TResult Function( AcpAuthCancelling value)?  cancelling,TResult Function( AcpAuthCancelled value)?  cancelled,TResult Function( AcpAuthFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpAuthUnchecked() when unchecked != null:
return unchecked(_that);case AcpAuthChecking() when checking != null:
return checking(_that);case AcpAuthRequired() when required != null:
return required(_that);case AcpAuthAuthenticating() when authenticating != null:
return authenticating(_that);case AcpAuthVerifying() when verifying != null:
return verifying(_that);case AcpAuthClosing() when closing != null:
return closing(_that);case AcpAuthVerified() when verified != null:
return verified(_that);case AcpAuthCancelling() when cancelling != null:
return cancelling(_that);case AcpAuthCancelled() when cancelled != null:
return cancelled(_that);case AcpAuthFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpAuthUnchecked value)  unchecked,required TResult Function( AcpAuthChecking value)  checking,required TResult Function( AcpAuthRequired value)  required,required TResult Function( AcpAuthAuthenticating value)  authenticating,required TResult Function( AcpAuthVerifying value)  verifying,required TResult Function( AcpAuthClosing value)  closing,required TResult Function( AcpAuthVerified value)  verified,required TResult Function( AcpAuthCancelling value)  cancelling,required TResult Function( AcpAuthCancelled value)  cancelled,required TResult Function( AcpAuthFailed value)  failed,}){
final _that = this;
switch (_that) {
case AcpAuthUnchecked():
return unchecked(_that);case AcpAuthChecking():
return checking(_that);case AcpAuthRequired():
return required(_that);case AcpAuthAuthenticating():
return authenticating(_that);case AcpAuthVerifying():
return verifying(_that);case AcpAuthClosing():
return closing(_that);case AcpAuthVerified():
return verified(_that);case AcpAuthCancelling():
return cancelling(_that);case AcpAuthCancelled():
return cancelled(_that);case AcpAuthFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpAuthUnchecked value)?  unchecked,TResult? Function( AcpAuthChecking value)?  checking,TResult? Function( AcpAuthRequired value)?  required,TResult? Function( AcpAuthAuthenticating value)?  authenticating,TResult? Function( AcpAuthVerifying value)?  verifying,TResult? Function( AcpAuthClosing value)?  closing,TResult? Function( AcpAuthVerified value)?  verified,TResult? Function( AcpAuthCancelling value)?  cancelling,TResult? Function( AcpAuthCancelled value)?  cancelled,TResult? Function( AcpAuthFailed value)?  failed,}){
final _that = this;
switch (_that) {
case AcpAuthUnchecked() when unchecked != null:
return unchecked(_that);case AcpAuthChecking() when checking != null:
return checking(_that);case AcpAuthRequired() when required != null:
return required(_that);case AcpAuthAuthenticating() when authenticating != null:
return authenticating(_that);case AcpAuthVerifying() when verifying != null:
return verifying(_that);case AcpAuthClosing() when closing != null:
return closing(_that);case AcpAuthVerified() when verified != null:
return verified(_that);case AcpAuthCancelling() when cancelling != null:
return cancelling(_that);case AcpAuthCancelled() when cancelled != null:
return cancelled(_that);case AcpAuthFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchecked,TResult Function( String operationId)?  checking,TResult Function( AcpServerInfo? server,  List<AcpAuthMethod> methods)?  required,TResult Function( String operationId,  String methodId)?  authenticating,TResult Function( String operationId)?  verifying,TResult Function( String operationId,  AcpAuthFailure? failure)?  closing,TResult Function( int checkedAt,  AcpServerInfo? server)?  verified,TResult Function( String operationId)?  cancelling,TResult Function()?  cancelled,TResult Function( AcpAuthFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpAuthUnchecked() when unchecked != null:
return unchecked();case AcpAuthChecking() when checking != null:
return checking(_that.operationId);case AcpAuthRequired() when required != null:
return required(_that.server,_that.methods);case AcpAuthAuthenticating() when authenticating != null:
return authenticating(_that.operationId,_that.methodId);case AcpAuthVerifying() when verifying != null:
return verifying(_that.operationId);case AcpAuthClosing() when closing != null:
return closing(_that.operationId,_that.failure);case AcpAuthVerified() when verified != null:
return verified(_that.checkedAt,_that.server);case AcpAuthCancelling() when cancelling != null:
return cancelling(_that.operationId);case AcpAuthCancelled() when cancelled != null:
return cancelled();case AcpAuthFailed() when failed != null:
return failed(_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchecked,required TResult Function( String operationId)  checking,required TResult Function( AcpServerInfo? server,  List<AcpAuthMethod> methods)  required,required TResult Function( String operationId,  String methodId)  authenticating,required TResult Function( String operationId)  verifying,required TResult Function( String operationId,  AcpAuthFailure? failure)  closing,required TResult Function( int checkedAt,  AcpServerInfo? server)  verified,required TResult Function( String operationId)  cancelling,required TResult Function()  cancelled,required TResult Function( AcpAuthFailure failure)  failed,}) {final _that = this;
switch (_that) {
case AcpAuthUnchecked():
return unchecked();case AcpAuthChecking():
return checking(_that.operationId);case AcpAuthRequired():
return required(_that.server,_that.methods);case AcpAuthAuthenticating():
return authenticating(_that.operationId,_that.methodId);case AcpAuthVerifying():
return verifying(_that.operationId);case AcpAuthClosing():
return closing(_that.operationId,_that.failure);case AcpAuthVerified():
return verified(_that.checkedAt,_that.server);case AcpAuthCancelling():
return cancelling(_that.operationId);case AcpAuthCancelled():
return cancelled();case AcpAuthFailed():
return failed(_that.failure);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchecked,TResult? Function( String operationId)?  checking,TResult? Function( AcpServerInfo? server,  List<AcpAuthMethod> methods)?  required,TResult? Function( String operationId,  String methodId)?  authenticating,TResult? Function( String operationId)?  verifying,TResult? Function( String operationId,  AcpAuthFailure? failure)?  closing,TResult? Function( int checkedAt,  AcpServerInfo? server)?  verified,TResult? Function( String operationId)?  cancelling,TResult? Function()?  cancelled,TResult? Function( AcpAuthFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case AcpAuthUnchecked() when unchecked != null:
return unchecked();case AcpAuthChecking() when checking != null:
return checking(_that.operationId);case AcpAuthRequired() when required != null:
return required(_that.server,_that.methods);case AcpAuthAuthenticating() when authenticating != null:
return authenticating(_that.operationId,_that.methodId);case AcpAuthVerifying() when verifying != null:
return verifying(_that.operationId);case AcpAuthClosing() when closing != null:
return closing(_that.operationId,_that.failure);case AcpAuthVerified() when verified != null:
return verified(_that.checkedAt,_that.server);case AcpAuthCancelling() when cancelling != null:
return cancelling(_that.operationId);case AcpAuthCancelled() when cancelled != null:
return cancelled();case AcpAuthFailed() when failed != null:
return failed(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class AcpAuthUnchecked extends AcpAuthState {
  const AcpAuthUnchecked(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthUnchecked);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AcpAuthChecking extends AcpAuthState {
  const AcpAuthChecking({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthCheckingCopyWith<AcpAuthChecking> get copyWith => _$AcpAuthCheckingCopyWithImpl<AcpAuthChecking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthChecking&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $AcpAuthCheckingCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthCheckingCopyWith(AcpAuthChecking value, $Res Function(AcpAuthChecking) _then) = _$AcpAuthCheckingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$AcpAuthCheckingCopyWithImpl<$Res>
    implements $AcpAuthCheckingCopyWith<$Res> {
  _$AcpAuthCheckingCopyWithImpl(this._self, this._then);

  final AcpAuthChecking _self;
  final $Res Function(AcpAuthChecking) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(AcpAuthChecking(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpAuthRequired extends AcpAuthState {
  const AcpAuthRequired({required this.server, required  List<AcpAuthMethod> methods}): _methods = methods,super._();


 final  AcpServerInfo? server;
 final  List<AcpAuthMethod> _methods;
 List<AcpAuthMethod> get methods {
  if (_methods is EqualUnmodifiableListView) return _methods;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_methods);
}


/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthRequiredCopyWith<AcpAuthRequired> get copyWith => _$AcpAuthRequiredCopyWithImpl<AcpAuthRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthRequired&&(identical(other.server, server) || other.server == server)&&const DeepCollectionEquality().equals(other.methods, _methods));
}


@override
int get hashCode {
    return Object.hash(runtimeType,server,const DeepCollectionEquality().hash(_methods));
}



}

/// @nodoc
abstract mixin class $AcpAuthRequiredCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthRequiredCopyWith(AcpAuthRequired value, $Res Function(AcpAuthRequired) _then) = _$AcpAuthRequiredCopyWithImpl;
@useResult
$Res call({
 AcpServerInfo? server, List<AcpAuthMethod> methods
});


$AcpServerInfoCopyWith<$Res>? get server;

}
/// @nodoc
class _$AcpAuthRequiredCopyWithImpl<$Res>
    implements $AcpAuthRequiredCopyWith<$Res> {
  _$AcpAuthRequiredCopyWithImpl(this._self, this._then);

  final AcpAuthRequired _self;
  final $Res Function(AcpAuthRequired) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? server = freezed,Object? methods = null,}) {
  return _then(AcpAuthRequired(
server: freezed == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as AcpServerInfo?,methods: null == methods ? _self._methods : methods // ignore: cast_nullable_to_non_nullable
as List<AcpAuthMethod>,
  ));
}

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpServerInfoCopyWith<$Res>? get server {
    if (_self.server == null) {
    return null;
  }

  return $AcpServerInfoCopyWith<$Res>(_self.server!, (value) {
    return _then(_self.copyWith(server: value));
  });
}
}

/// @nodoc


class AcpAuthAuthenticating extends AcpAuthState {
  const AcpAuthAuthenticating({required this.operationId, required this.methodId}): super._();


 final  String operationId;
 final  String methodId;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthAuthenticatingCopyWith<AcpAuthAuthenticating> get copyWith => _$AcpAuthAuthenticatingCopyWithImpl<AcpAuthAuthenticating>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthAuthenticating&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.methodId, methodId) || other.methodId == methodId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,methodId);
}



}

/// @nodoc
abstract mixin class $AcpAuthAuthenticatingCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthAuthenticatingCopyWith(AcpAuthAuthenticating value, $Res Function(AcpAuthAuthenticating) _then) = _$AcpAuthAuthenticatingCopyWithImpl;
@useResult
$Res call({
 String operationId, String methodId
});




}
/// @nodoc
class _$AcpAuthAuthenticatingCopyWithImpl<$Res>
    implements $AcpAuthAuthenticatingCopyWith<$Res> {
  _$AcpAuthAuthenticatingCopyWithImpl(this._self, this._then);

  final AcpAuthAuthenticating _self;
  final $Res Function(AcpAuthAuthenticating) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? methodId = null,}) {
  return _then(AcpAuthAuthenticating(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,methodId: null == methodId ? _self.methodId : methodId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpAuthVerifying extends AcpAuthState {
  const AcpAuthVerifying({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthVerifyingCopyWith<AcpAuthVerifying> get copyWith => _$AcpAuthVerifyingCopyWithImpl<AcpAuthVerifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthVerifying&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $AcpAuthVerifyingCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthVerifyingCopyWith(AcpAuthVerifying value, $Res Function(AcpAuthVerifying) _then) = _$AcpAuthVerifyingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$AcpAuthVerifyingCopyWithImpl<$Res>
    implements $AcpAuthVerifyingCopyWith<$Res> {
  _$AcpAuthVerifyingCopyWithImpl(this._self, this._then);

  final AcpAuthVerifying _self;
  final $Res Function(AcpAuthVerifying) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(AcpAuthVerifying(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpAuthClosing extends AcpAuthState {
  const AcpAuthClosing({required this.operationId, required this.failure}): super._();


 final  String operationId;
 final  AcpAuthFailure? failure;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthClosingCopyWith<AcpAuthClosing> get copyWith => _$AcpAuthClosingCopyWithImpl<AcpAuthClosing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthClosing&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,failure);
}



}

/// @nodoc
abstract mixin class $AcpAuthClosingCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthClosingCopyWith(AcpAuthClosing value, $Res Function(AcpAuthClosing) _then) = _$AcpAuthClosingCopyWithImpl;
@useResult
$Res call({
 String operationId, AcpAuthFailure? failure
});


$AcpAuthFailureCopyWith<$Res>? get failure;

}
/// @nodoc
class _$AcpAuthClosingCopyWithImpl<$Res>
    implements $AcpAuthClosingCopyWith<$Res> {
  _$AcpAuthClosingCopyWithImpl(this._self, this._then);

  final AcpAuthClosing _self;
  final $Res Function(AcpAuthClosing) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? failure = freezed,}) {
  return _then(AcpAuthClosing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as AcpAuthFailure?,
  ));
}

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $AcpAuthFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc


class AcpAuthVerified extends AcpAuthState {
  const AcpAuthVerified({required this.checkedAt, required this.server}): super._();


/// 观察时间（Unix 秒）；不代表凭据长期有效。
 final  int checkedAt;
/// 服务端观察身份；对端未提供时为 null（不伪造）。
 final  AcpServerInfo? server;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthVerifiedCopyWith<AcpAuthVerified> get copyWith => _$AcpAuthVerifiedCopyWithImpl<AcpAuthVerified>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthVerified&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,server);
}



}

/// @nodoc
abstract mixin class $AcpAuthVerifiedCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthVerifiedCopyWith(AcpAuthVerified value, $Res Function(AcpAuthVerified) _then) = _$AcpAuthVerifiedCopyWithImpl;
@useResult
$Res call({
 int checkedAt, AcpServerInfo? server
});


$AcpServerInfoCopyWith<$Res>? get server;

}
/// @nodoc
class _$AcpAuthVerifiedCopyWithImpl<$Res>
    implements $AcpAuthVerifiedCopyWith<$Res> {
  _$AcpAuthVerifiedCopyWithImpl(this._self, this._then);

  final AcpAuthVerified _self;
  final $Res Function(AcpAuthVerified) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? server = freezed,}) {
  return _then(AcpAuthVerified(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,server: freezed == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as AcpServerInfo?,
  ));
}

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpServerInfoCopyWith<$Res>? get server {
    if (_self.server == null) {
    return null;
  }

  return $AcpServerInfoCopyWith<$Res>(_self.server!, (value) {
    return _then(_self.copyWith(server: value));
  });
}
}

/// @nodoc


class AcpAuthCancelling extends AcpAuthState {
  const AcpAuthCancelling({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthCancellingCopyWith<AcpAuthCancelling> get copyWith => _$AcpAuthCancellingCopyWithImpl<AcpAuthCancelling>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthCancelling&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class $AcpAuthCancellingCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthCancellingCopyWith(AcpAuthCancelling value, $Res Function(AcpAuthCancelling) _then) = _$AcpAuthCancellingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$AcpAuthCancellingCopyWithImpl<$Res>
    implements $AcpAuthCancellingCopyWith<$Res> {
  _$AcpAuthCancellingCopyWithImpl(this._self, this._then);

  final AcpAuthCancelling _self;
  final $Res Function(AcpAuthCancelling) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(AcpAuthCancelling(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpAuthCancelled extends AcpAuthState {
  const AcpAuthCancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthCancelled);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AcpAuthFailed extends AcpAuthState {
  const AcpAuthFailed({required this.failure}): super._();


 final  AcpAuthFailure failure;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthFailedCopyWith<AcpAuthFailed> get copyWith => _$AcpAuthFailedCopyWithImpl<AcpAuthFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthFailed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}



}

/// @nodoc
abstract mixin class $AcpAuthFailedCopyWith<$Res> implements $AcpAuthStateCopyWith<$Res> {
  factory $AcpAuthFailedCopyWith(AcpAuthFailed value, $Res Function(AcpAuthFailed) _then) = _$AcpAuthFailedCopyWithImpl;
@useResult
$Res call({
 AcpAuthFailure failure
});


$AcpAuthFailureCopyWith<$Res> get failure;

}
/// @nodoc
class _$AcpAuthFailedCopyWithImpl<$Res>
    implements $AcpAuthFailedCopyWith<$Res> {
  _$AcpAuthFailedCopyWithImpl(this._self, this._then);

  final AcpAuthFailed _self;
  final $Res Function(AcpAuthFailed) _then;

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(AcpAuthFailed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as AcpAuthFailure,
  ));
}

/// Create a copy of AcpAuthState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthFailureCopyWith<$Res> get failure {

  return $AcpAuthFailureCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

/// @nodoc
mixin _$AcpAuthAccount {

 String get accountId;/// 本次观察对应的连接身份；不等于 Settings revision。
 int get connectionRevision; AcpAuthState get state;
/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthAccountCopyWith<AcpAuthAccount> get copyWith => _$AcpAuthAccountCopyWithImpl<AcpAuthAccount>(this as AcpAuthAccount, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthAccount;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthAccount&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.connectionRevision, _this.connectionRevision) || other.connectionRevision == _this.connectionRevision)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as AcpAuthAccount;
  return Object.hash(runtimeType,_this.accountId,_this.connectionRevision,_this.state);
}

@override
String toString() {
  final _this = this as AcpAuthAccount;
  return 'AcpAuthAccount(accountId: ${_this.accountId}, connectionRevision: ${_this.connectionRevision}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $AcpAuthAccountCopyWith<$Res>  {
  factory $AcpAuthAccountCopyWith(AcpAuthAccount value, $Res Function(AcpAuthAccount) _then) = _$AcpAuthAccountCopyWithImpl;
@useResult
$Res call({
 String accountId, int connectionRevision, AcpAuthState state
});


$AcpAuthStateCopyWith<$Res> get state;

}
/// @nodoc
class _$AcpAuthAccountCopyWithImpl<$Res>
    implements $AcpAuthAccountCopyWith<$Res> {
  _$AcpAuthAccountCopyWithImpl(this._self, this._then);

  final AcpAuthAccount _self;
  final $Res Function(AcpAuthAccount) _then;

/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? connectionRevision = null,Object? state = null,}) {
  return _then(AcpAuthAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AcpAuthState,
  ));
}
/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthStateCopyWith<$Res> get state {

  return $AcpAuthStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthAccount].
extension AcpAuthAccountPatterns on AcpAuthAccount {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthAccount value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthAccount() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthAccount value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthAccount():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthAccount value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthAccount() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  int connectionRevision,  AcpAuthState state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthAccount() when $default != null:
return $default(_that.accountId,_that.connectionRevision,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  int connectionRevision,  AcpAuthState state)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthAccount():
return $default(_that.accountId,_that.connectionRevision,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  int connectionRevision,  AcpAuthState state)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthAccount() when $default != null:
return $default(_that.accountId,_that.connectionRevision,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthAccount implements AcpAuthAccount {
  const _AcpAuthAccount({required this.accountId, required this.connectionRevision, required this.state});


@override final  String accountId;
/// 本次观察对应的连接身份；不等于 Settings revision。
@override final  int connectionRevision;
@override final  AcpAuthState state;

/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthAccountCopyWith<_AcpAuthAccount> get copyWith => __$AcpAuthAccountCopyWithImpl<_AcpAuthAccount>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthAccount&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,connectionRevision,state);
}

@override
String toString() {
    return 'AcpAuthAccount(accountId: $accountId, connectionRevision: $connectionRevision, state: $state)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthAccountCopyWith<$Res> implements $AcpAuthAccountCopyWith<$Res> {
  factory _$AcpAuthAccountCopyWith(_AcpAuthAccount value, $Res Function(_AcpAuthAccount) _then) = __$AcpAuthAccountCopyWithImpl;
@override @useResult
$Res call({
 String accountId, int connectionRevision, AcpAuthState state
});


@override $AcpAuthStateCopyWith<$Res> get state;

}
/// @nodoc
class __$AcpAuthAccountCopyWithImpl<$Res>
    implements _$AcpAuthAccountCopyWith<$Res> {
  __$AcpAuthAccountCopyWithImpl(this._self, this._then);

  final _AcpAuthAccount _self;
  final $Res Function(_AcpAuthAccount) _then;

/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? connectionRevision = null,Object? state = null,}) {
  return _then(_AcpAuthAccount(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AcpAuthState,
  ));
}

/// Create a copy of AcpAuthAccount
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthStateCopyWith<$Res> get state {

  return $AcpAuthStateCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$AcpAuthSnapshot {

 int get revision; int get updatedAt; List<AcpAuthAccount> get accounts;
/// Create a copy of AcpAuthSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<AcpAuthSnapshot> get copyWith => _$AcpAuthSnapshotCopyWithImpl<AcpAuthSnapshot>(this as AcpAuthSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthSnapshot&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&const DeepCollectionEquality().equals(other.accounts, _this.accounts));
}


@override
int get hashCode {
  final _this = this as AcpAuthSnapshot;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt,const DeepCollectionEquality().hash(_this.accounts));
}



}

/// @nodoc
abstract mixin class $AcpAuthSnapshotCopyWith<$Res>  {
  factory $AcpAuthSnapshotCopyWith(AcpAuthSnapshot value, $Res Function(AcpAuthSnapshot) _then) = _$AcpAuthSnapshotCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt, List<AcpAuthAccount> accounts
});




}
/// @nodoc
class _$AcpAuthSnapshotCopyWithImpl<$Res>
    implements $AcpAuthSnapshotCopyWith<$Res> {
  _$AcpAuthSnapshotCopyWithImpl(this._self, this._then);

  final AcpAuthSnapshot _self;
  final $Res Function(AcpAuthSnapshot) _then;

/// Create a copy of AcpAuthSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,Object? accounts = null,}) {
  return _then(AcpAuthSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,accounts: null == accounts ? _self.accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AcpAuthAccount>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAuthSnapshot].
extension AcpAuthSnapshotPatterns on AcpAuthSnapshot {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthSnapshot value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthSnapshot() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthSnapshot value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthSnapshot():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthSnapshot value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthSnapshot() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  List<AcpAuthAccount> accounts)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthSnapshot() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.accounts);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt,  List<AcpAuthAccount> accounts)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthSnapshot():
return $default(_that.revision,_that.updatedAt,_that.accounts);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt,  List<AcpAuthAccount> accounts)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthSnapshot() when $default != null:
return $default(_that.revision,_that.updatedAt,_that.accounts);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthSnapshot extends AcpAuthSnapshot {
  const _AcpAuthSnapshot({required this.revision, required this.updatedAt, required  List<AcpAuthAccount> accounts}): _accounts = accounts,super._();


@override final  int revision;
@override final  int updatedAt;
 final  List<AcpAuthAccount> _accounts;
@override List<AcpAuthAccount> get accounts {
  if (_accounts is EqualUnmodifiableListView) return _accounts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_accounts);
}


/// Create a copy of AcpAuthSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthSnapshotCopyWith<_AcpAuthSnapshot> get copyWith => __$AcpAuthSnapshotCopyWithImpl<_AcpAuthSnapshot>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthSnapshot&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&const DeepCollectionEquality().equals(other.accounts, _accounts));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,const DeepCollectionEquality().hash(_accounts));
}



}

/// @nodoc
abstract mixin class _$AcpAuthSnapshotCopyWith<$Res> implements $AcpAuthSnapshotCopyWith<$Res> {
  factory _$AcpAuthSnapshotCopyWith(_AcpAuthSnapshot value, $Res Function(_AcpAuthSnapshot) _then) = __$AcpAuthSnapshotCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, List<AcpAuthAccount> accounts
});




}
/// @nodoc
class __$AcpAuthSnapshotCopyWithImpl<$Res>
    implements _$AcpAuthSnapshotCopyWith<$Res> {
  __$AcpAuthSnapshotCopyWithImpl(this._self, this._then);

  final _AcpAuthSnapshot _self;
  final $Res Function(_AcpAuthSnapshot) _then;

/// Create a copy of AcpAuthSnapshot
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? accounts = null,}) {
  return _then(_AcpAuthSnapshot(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,accounts: null == accounts ? _self._accounts : accounts // ignore: cast_nullable_to_non_nullable
as List<AcpAuthAccount>,
  ));
}


}

/// @nodoc
mixin _$AcpAuthHeader {

 int get revision; int get updatedAt;
/// Create a copy of AcpAuthHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthHeaderCopyWith<AcpAuthHeader> get copyWith => _$AcpAuthHeaderCopyWithImpl<AcpAuthHeader>(this as AcpAuthHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as AcpAuthHeader;
  return Object.hash(runtimeType,_this.revision,_this.updatedAt);
}

@override
String toString() {
  final _this = this as AcpAuthHeader;
  return 'AcpAuthHeader(revision: ${_this.revision}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $AcpAuthHeaderCopyWith<$Res>  {
  factory $AcpAuthHeaderCopyWith(AcpAuthHeader value, $Res Function(AcpAuthHeader) _then) = _$AcpAuthHeaderCopyWithImpl;
@useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$AcpAuthHeaderCopyWithImpl<$Res>
    implements $AcpAuthHeaderCopyWith<$Res> {
  _$AcpAuthHeaderCopyWithImpl(this._self, this._then);

  final AcpAuthHeader _self;
  final $Res Function(AcpAuthHeader) _then;

/// Create a copy of AcpAuthHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(AcpAuthHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAuthHeader].
extension AcpAuthHeaderPatterns on AcpAuthHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthHeader value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int revision,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthHeader() when $default != null:
return $default(_that.revision,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int revision,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthHeader():
return $default(_that.revision,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int revision,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthHeader() when $default != null:
return $default(_that.revision,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthHeader implements AcpAuthHeader {
  const _AcpAuthHeader({required this.revision, required this.updatedAt});


@override final  int revision;
@override final  int updatedAt;

/// Create a copy of AcpAuthHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthHeaderCopyWith<_AcpAuthHeader> get copyWith => __$AcpAuthHeaderCopyWithImpl<_AcpAuthHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'AcpAuthHeader(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthHeaderCopyWith<$Res> implements $AcpAuthHeaderCopyWith<$Res> {
  factory _$AcpAuthHeaderCopyWith(_AcpAuthHeader value, $Res Function(_AcpAuthHeader) _then) = __$AcpAuthHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class __$AcpAuthHeaderCopyWithImpl<$Res>
    implements _$AcpAuthHeaderCopyWith<$Res> {
  __$AcpAuthHeaderCopyWithImpl(this._self, this._then);

  final _AcpAuthHeader _self;
  final $Res Function(_AcpAuthHeader) _then;

/// Create a copy of AcpAuthHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(_AcpAuthHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AcpAuthObservation {

 ProductProjection<AcpAuthHeader> get projection; Materialized<AcpAuthSnapshot, ResourceStamp>? get snapshot;
/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthObservationCopyWith<AcpAuthObservation> get copyWith => _$AcpAuthObservationCopyWithImpl<AcpAuthObservation>(this as AcpAuthObservation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthObservation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthObservation&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as AcpAuthObservation;
  return Object.hash(runtimeType,_this.projection,_this.snapshot);
}



}

/// @nodoc
abstract mixin class $AcpAuthObservationCopyWith<$Res>  {
  factory $AcpAuthObservationCopyWith(AcpAuthObservation value, $Res Function(AcpAuthObservation) _then) = _$AcpAuthObservationCopyWithImpl;
@useResult
$Res call({
 ProductProjection<AcpAuthHeader> projection, Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot
});


$ProductProjectionCopyWith<AcpAuthHeader, $Res> get projection;$MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>? get snapshot;

}
/// @nodoc
class _$AcpAuthObservationCopyWithImpl<$Res>
    implements $AcpAuthObservationCopyWith<$Res> {
  _$AcpAuthObservationCopyWithImpl(this._self, this._then);

  final AcpAuthObservation _self;
  final $Res Function(AcpAuthObservation) _then;

/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? snapshot = freezed,}) {
  return _then(AcpAuthObservation(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AcpAuthHeader>,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as Materialized<AcpAuthSnapshot, ResourceStamp>?,
  ));
}
/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AcpAuthHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AcpAuthHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthObservation].
extension AcpAuthObservationPatterns on AcpAuthObservation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthObservation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthObservation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthObservation value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthObservation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthObservation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthObservation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<AcpAuthHeader> projection,  Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthObservation() when $default != null:
return $default(_that.projection,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<AcpAuthHeader> projection,  Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthObservation():
return $default(_that.projection,_that.snapshot);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<AcpAuthHeader> projection,  Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthObservation() when $default != null:
return $default(_that.projection,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthObservation extends AcpAuthObservation {
  const _AcpAuthObservation({required this.projection, required this.snapshot}): super._();


@override final  ProductProjection<AcpAuthHeader> projection;
@override final  Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot;

/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthObservationCopyWith<_AcpAuthObservation> get copyWith => __$AcpAuthObservationCopyWithImpl<_AcpAuthObservation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthObservation&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,snapshot);
}



}

/// @nodoc
abstract mixin class _$AcpAuthObservationCopyWith<$Res> implements $AcpAuthObservationCopyWith<$Res> {
  factory _$AcpAuthObservationCopyWith(_AcpAuthObservation value, $Res Function(_AcpAuthObservation) _then) = __$AcpAuthObservationCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<AcpAuthHeader> projection, Materialized<AcpAuthSnapshot, ResourceStamp>? snapshot
});


@override $ProductProjectionCopyWith<AcpAuthHeader, $Res> get projection;@override $MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>? get snapshot;

}
/// @nodoc
class __$AcpAuthObservationCopyWithImpl<$Res>
    implements _$AcpAuthObservationCopyWith<$Res> {
  __$AcpAuthObservationCopyWithImpl(this._self, this._then);

  final _AcpAuthObservation _self;
  final $Res Function(_AcpAuthObservation) _then;

/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? snapshot = freezed,}) {
  return _then(_AcpAuthObservation(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<AcpAuthHeader>,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as Materialized<AcpAuthSnapshot, ResourceStamp>?,
  ));
}

/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<AcpAuthHeader, $Res> get projection {

  return $ProductProjectionCopyWith<AcpAuthHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of AcpAuthObservation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $MaterializedCopyWith<AcpAuthSnapshot, ResourceStamp, $Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

// dart format on
