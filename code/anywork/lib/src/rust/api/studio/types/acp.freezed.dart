// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpAuthAction {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthAction);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthAction()';
}


}

/// @nodoc
class $BridgeAcpAuthActionCopyWith<$Res>  {
$BridgeAcpAuthActionCopyWith(BridgeAcpAuthAction _, $Res Function(BridgeAcpAuthAction) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpAuthAction].
extension BridgeAcpAuthActionPatterns on BridgeAcpAuthAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAuthAction_Check value)?  check,TResult Function( BridgeAcpAuthAction_Authenticate value)?  authenticate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check() when check != null:
return check(_that);case BridgeAcpAuthAction_Authenticate() when authenticate != null:
return authenticate(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAuthAction_Check value)  check,required TResult Function( BridgeAcpAuthAction_Authenticate value)  authenticate,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check():
return check(_that);case BridgeAcpAuthAction_Authenticate():
return authenticate(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAuthAction_Check value)?  check,TResult? Function( BridgeAcpAuthAction_Authenticate value)?  authenticate,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check() when check != null:
return check(_that);case BridgeAcpAuthAction_Authenticate() when authenticate != null:
return authenticate(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  check,TResult Function( String methodId)?  authenticate,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check() when check != null:
return check();case BridgeAcpAuthAction_Authenticate() when authenticate != null:
return authenticate(_that.methodId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  check,required TResult Function( String methodId)  authenticate,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check():
return check();case BridgeAcpAuthAction_Authenticate():
return authenticate(_that.methodId);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  check,TResult? Function( String methodId)?  authenticate,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthAction_Check() when check != null:
return check();case BridgeAcpAuthAction_Authenticate() when authenticate != null:
return authenticate(_that.methodId);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAuthAction_Check extends BridgeAcpAuthAction {
  const BridgeAcpAuthAction_Check(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthAction_Check);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthAction.check()';
}


}




/// @nodoc


class BridgeAcpAuthAction_Authenticate extends BridgeAcpAuthAction {
  const BridgeAcpAuthAction_Authenticate({required this.methodId}): super._();


 final  String methodId;

/// Create a copy of BridgeAcpAuthAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthAction_AuthenticateCopyWith<BridgeAcpAuthAction_Authenticate> get copyWith => _$BridgeAcpAuthAction_AuthenticateCopyWithImpl<BridgeAcpAuthAction_Authenticate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthAction_Authenticate&&(identical(other.methodId, methodId) || other.methodId == methodId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,methodId);
}

@override
String toString() {
    return 'BridgeAcpAuthAction.authenticate(methodId: $methodId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthAction_AuthenticateCopyWith<$Res> implements $BridgeAcpAuthActionCopyWith<$Res> {
  factory $BridgeAcpAuthAction_AuthenticateCopyWith(BridgeAcpAuthAction_Authenticate value, $Res Function(BridgeAcpAuthAction_Authenticate) _then) = _$BridgeAcpAuthAction_AuthenticateCopyWithImpl;
@useResult
$Res call({
 String methodId
});




}
/// @nodoc
class _$BridgeAcpAuthAction_AuthenticateCopyWithImpl<$Res>
    implements $BridgeAcpAuthAction_AuthenticateCopyWith<$Res> {
  _$BridgeAcpAuthAction_AuthenticateCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthAction_Authenticate _self;
  final $Res Function(BridgeAcpAuthAction_Authenticate) _then;

/// Create a copy of BridgeAcpAuthAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? methodId = null,}) {
  return _then(BridgeAcpAuthAction_Authenticate(
methodId: null == methodId ? _self.methodId : methodId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$BridgeAcpAuthState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthState()';
}


}

/// @nodoc
class $BridgeAcpAuthStateCopyWith<$Res>  {
$BridgeAcpAuthStateCopyWith(BridgeAcpAuthState _, $Res Function(BridgeAcpAuthState) __);
}


/// Adds pattern-matching-related methods to [BridgeAcpAuthState].
extension BridgeAcpAuthStatePatterns on BridgeAcpAuthState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpAuthState_Unchecked value)?  unchecked,TResult Function( BridgeAcpAuthState_Checking value)?  checking,TResult Function( BridgeAcpAuthState_Required value)?  required_,TResult Function( BridgeAcpAuthState_Authenticating value)?  authenticating,TResult Function( BridgeAcpAuthState_Verifying value)?  verifying,TResult Function( BridgeAcpAuthState_Closing value)?  closing,TResult Function( BridgeAcpAuthState_Verified value)?  verified,TResult Function( BridgeAcpAuthState_Cancelling value)?  cancelling,TResult Function( BridgeAcpAuthState_Cancelled value)?  cancelled,TResult Function( BridgeAcpAuthState_Failed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked() when unchecked != null:
return unchecked(_that);case BridgeAcpAuthState_Checking() when checking != null:
return checking(_that);case BridgeAcpAuthState_Required() when required_ != null:
return required_(_that);case BridgeAcpAuthState_Authenticating() when authenticating != null:
return authenticating(_that);case BridgeAcpAuthState_Verifying() when verifying != null:
return verifying(_that);case BridgeAcpAuthState_Closing() when closing != null:
return closing(_that);case BridgeAcpAuthState_Verified() when verified != null:
return verified(_that);case BridgeAcpAuthState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpAuthState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpAuthState_Failed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpAuthState_Unchecked value)  unchecked,required TResult Function( BridgeAcpAuthState_Checking value)  checking,required TResult Function( BridgeAcpAuthState_Required value)  required_,required TResult Function( BridgeAcpAuthState_Authenticating value)  authenticating,required TResult Function( BridgeAcpAuthState_Verifying value)  verifying,required TResult Function( BridgeAcpAuthState_Closing value)  closing,required TResult Function( BridgeAcpAuthState_Verified value)  verified,required TResult Function( BridgeAcpAuthState_Cancelling value)  cancelling,required TResult Function( BridgeAcpAuthState_Cancelled value)  cancelled,required TResult Function( BridgeAcpAuthState_Failed value)  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked():
return unchecked(_that);case BridgeAcpAuthState_Checking():
return checking(_that);case BridgeAcpAuthState_Required():
return required_(_that);case BridgeAcpAuthState_Authenticating():
return authenticating(_that);case BridgeAcpAuthState_Verifying():
return verifying(_that);case BridgeAcpAuthState_Closing():
return closing(_that);case BridgeAcpAuthState_Verified():
return verified(_that);case BridgeAcpAuthState_Cancelling():
return cancelling(_that);case BridgeAcpAuthState_Cancelled():
return cancelled(_that);case BridgeAcpAuthState_Failed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpAuthState_Unchecked value)?  unchecked,TResult? Function( BridgeAcpAuthState_Checking value)?  checking,TResult? Function( BridgeAcpAuthState_Required value)?  required_,TResult? Function( BridgeAcpAuthState_Authenticating value)?  authenticating,TResult? Function( BridgeAcpAuthState_Verifying value)?  verifying,TResult? Function( BridgeAcpAuthState_Closing value)?  closing,TResult? Function( BridgeAcpAuthState_Verified value)?  verified,TResult? Function( BridgeAcpAuthState_Cancelling value)?  cancelling,TResult? Function( BridgeAcpAuthState_Cancelled value)?  cancelled,TResult? Function( BridgeAcpAuthState_Failed value)?  failed,}){
final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked() when unchecked != null:
return unchecked(_that);case BridgeAcpAuthState_Checking() when checking != null:
return checking(_that);case BridgeAcpAuthState_Required() when required_ != null:
return required_(_that);case BridgeAcpAuthState_Authenticating() when authenticating != null:
return authenticating(_that);case BridgeAcpAuthState_Verifying() when verifying != null:
return verifying(_that);case BridgeAcpAuthState_Closing() when closing != null:
return closing(_that);case BridgeAcpAuthState_Verified() when verified != null:
return verified(_that);case BridgeAcpAuthState_Cancelling() when cancelling != null:
return cancelling(_that);case BridgeAcpAuthState_Cancelled() when cancelled != null:
return cancelled(_that);case BridgeAcpAuthState_Failed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unchecked,TResult Function( String operationId)?  checking,TResult Function( List<BridgeAcpAuthMethod> methods,  BridgeAcpServerInfo? server)?  required_,TResult Function( String operationId,  String methodId)?  authenticating,TResult Function( String operationId)?  verifying,TResult Function( String operationId,  BridgeAcpAuthFailure? failure)?  closing,TResult Function( PlatformInt64 checkedAt,  BridgeAcpServerInfo? server)?  verified,TResult Function( String operationId)?  cancelling,TResult Function()?  cancelled,TResult Function( BridgeAcpAuthFailure failure)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked() when unchecked != null:
return unchecked();case BridgeAcpAuthState_Checking() when checking != null:
return checking(_that.operationId);case BridgeAcpAuthState_Required() when required_ != null:
return required_(_that.methods,_that.server);case BridgeAcpAuthState_Authenticating() when authenticating != null:
return authenticating(_that.operationId,_that.methodId);case BridgeAcpAuthState_Verifying() when verifying != null:
return verifying(_that.operationId);case BridgeAcpAuthState_Closing() when closing != null:
return closing(_that.operationId,_that.failure);case BridgeAcpAuthState_Verified() when verified != null:
return verified(_that.checkedAt,_that.server);case BridgeAcpAuthState_Cancelling() when cancelling != null:
return cancelling(_that.operationId);case BridgeAcpAuthState_Cancelled() when cancelled != null:
return cancelled();case BridgeAcpAuthState_Failed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unchecked,required TResult Function( String operationId)  checking,required TResult Function( List<BridgeAcpAuthMethod> methods,  BridgeAcpServerInfo? server)  required_,required TResult Function( String operationId,  String methodId)  authenticating,required TResult Function( String operationId)  verifying,required TResult Function( String operationId,  BridgeAcpAuthFailure? failure)  closing,required TResult Function( PlatformInt64 checkedAt,  BridgeAcpServerInfo? server)  verified,required TResult Function( String operationId)  cancelling,required TResult Function()  cancelled,required TResult Function( BridgeAcpAuthFailure failure)  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked():
return unchecked();case BridgeAcpAuthState_Checking():
return checking(_that.operationId);case BridgeAcpAuthState_Required():
return required_(_that.methods,_that.server);case BridgeAcpAuthState_Authenticating():
return authenticating(_that.operationId,_that.methodId);case BridgeAcpAuthState_Verifying():
return verifying(_that.operationId);case BridgeAcpAuthState_Closing():
return closing(_that.operationId,_that.failure);case BridgeAcpAuthState_Verified():
return verified(_that.checkedAt,_that.server);case BridgeAcpAuthState_Cancelling():
return cancelling(_that.operationId);case BridgeAcpAuthState_Cancelled():
return cancelled();case BridgeAcpAuthState_Failed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unchecked,TResult? Function( String operationId)?  checking,TResult? Function( List<BridgeAcpAuthMethod> methods,  BridgeAcpServerInfo? server)?  required_,TResult? Function( String operationId,  String methodId)?  authenticating,TResult? Function( String operationId)?  verifying,TResult? Function( String operationId,  BridgeAcpAuthFailure? failure)?  closing,TResult? Function( PlatformInt64 checkedAt,  BridgeAcpServerInfo? server)?  verified,TResult? Function( String operationId)?  cancelling,TResult? Function()?  cancelled,TResult? Function( BridgeAcpAuthFailure failure)?  failed,}) {final _that = this;
switch (_that) {
case BridgeAcpAuthState_Unchecked() when unchecked != null:
return unchecked();case BridgeAcpAuthState_Checking() when checking != null:
return checking(_that.operationId);case BridgeAcpAuthState_Required() when required_ != null:
return required_(_that.methods,_that.server);case BridgeAcpAuthState_Authenticating() when authenticating != null:
return authenticating(_that.operationId,_that.methodId);case BridgeAcpAuthState_Verifying() when verifying != null:
return verifying(_that.operationId);case BridgeAcpAuthState_Closing() when closing != null:
return closing(_that.operationId,_that.failure);case BridgeAcpAuthState_Verified() when verified != null:
return verified(_that.checkedAt,_that.server);case BridgeAcpAuthState_Cancelling() when cancelling != null:
return cancelling(_that.operationId);case BridgeAcpAuthState_Cancelled() when cancelled != null:
return cancelled();case BridgeAcpAuthState_Failed() when failed != null:
return failed(_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpAuthState_Unchecked extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Unchecked(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Unchecked);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthState.unchecked()';
}


}




/// @nodoc


class BridgeAcpAuthState_Checking extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Checking({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_CheckingCopyWith<BridgeAcpAuthState_Checking> get copyWith => _$BridgeAcpAuthState_CheckingCopyWithImpl<BridgeAcpAuthState_Checking>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Checking&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpAuthState.checking(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_CheckingCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_CheckingCopyWith(BridgeAcpAuthState_Checking value, $Res Function(BridgeAcpAuthState_Checking) _then) = _$BridgeAcpAuthState_CheckingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpAuthState_CheckingCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_CheckingCopyWith<$Res> {
  _$BridgeAcpAuthState_CheckingCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Checking _self;
  final $Res Function(BridgeAcpAuthState_Checking) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpAuthState_Checking(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Required extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Required({required  List<BridgeAcpAuthMethod> methods, this.server}): _methods = methods,super._();


 final  List<BridgeAcpAuthMethod> _methods;
 List<BridgeAcpAuthMethod> get methods {
  if (_methods is EqualUnmodifiableListView) return _methods;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_methods);
}

/// 协议观察；对端未提供 `agentInfo` 时为 `None`（未知），不用本地账号名冒充。
 final  BridgeAcpServerInfo? server;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_RequiredCopyWith<BridgeAcpAuthState_Required> get copyWith => _$BridgeAcpAuthState_RequiredCopyWithImpl<BridgeAcpAuthState_Required>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Required&&const DeepCollectionEquality().equals(other.methods, _methods)&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_methods),server);
}

@override
String toString() {
    return 'BridgeAcpAuthState.required_(methods: $methods, server: $server)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_RequiredCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_RequiredCopyWith(BridgeAcpAuthState_Required value, $Res Function(BridgeAcpAuthState_Required) _then) = _$BridgeAcpAuthState_RequiredCopyWithImpl;
@useResult
$Res call({
 List<BridgeAcpAuthMethod> methods, BridgeAcpServerInfo? server
});




}
/// @nodoc
class _$BridgeAcpAuthState_RequiredCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_RequiredCopyWith<$Res> {
  _$BridgeAcpAuthState_RequiredCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Required _self;
  final $Res Function(BridgeAcpAuthState_Required) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? methods = null,Object? server = freezed,}) {
  return _then(BridgeAcpAuthState_Required(
methods: null == methods ? _self._methods : methods // ignore: cast_nullable_to_non_nullable
as List<BridgeAcpAuthMethod>,server: freezed == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as BridgeAcpServerInfo?,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Authenticating extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Authenticating({required this.operationId, required this.methodId}): super._();


 final  String operationId;
 final  String methodId;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_AuthenticatingCopyWith<BridgeAcpAuthState_Authenticating> get copyWith => _$BridgeAcpAuthState_AuthenticatingCopyWithImpl<BridgeAcpAuthState_Authenticating>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Authenticating&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.methodId, methodId) || other.methodId == methodId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,methodId);
}

@override
String toString() {
    return 'BridgeAcpAuthState.authenticating(operationId: $operationId, methodId: $methodId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_AuthenticatingCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_AuthenticatingCopyWith(BridgeAcpAuthState_Authenticating value, $Res Function(BridgeAcpAuthState_Authenticating) _then) = _$BridgeAcpAuthState_AuthenticatingCopyWithImpl;
@useResult
$Res call({
 String operationId, String methodId
});




}
/// @nodoc
class _$BridgeAcpAuthState_AuthenticatingCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_AuthenticatingCopyWith<$Res> {
  _$BridgeAcpAuthState_AuthenticatingCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Authenticating _self;
  final $Res Function(BridgeAcpAuthState_Authenticating) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? methodId = null,}) {
  return _then(BridgeAcpAuthState_Authenticating(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,methodId: null == methodId ? _self.methodId : methodId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Verifying extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Verifying({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_VerifyingCopyWith<BridgeAcpAuthState_Verifying> get copyWith => _$BridgeAcpAuthState_VerifyingCopyWithImpl<BridgeAcpAuthState_Verifying>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Verifying&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpAuthState.verifying(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_VerifyingCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_VerifyingCopyWith(BridgeAcpAuthState_Verifying value, $Res Function(BridgeAcpAuthState_Verifying) _then) = _$BridgeAcpAuthState_VerifyingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpAuthState_VerifyingCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_VerifyingCopyWith<$Res> {
  _$BridgeAcpAuthState_VerifyingCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Verifying _self;
  final $Res Function(BridgeAcpAuthState_Verifying) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpAuthState_Verifying(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Closing extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Closing({required this.operationId, this.failure}): super._();


 final  String operationId;
 final  BridgeAcpAuthFailure? failure;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_ClosingCopyWith<BridgeAcpAuthState_Closing> get copyWith => _$BridgeAcpAuthState_ClosingCopyWithImpl<BridgeAcpAuthState_Closing>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Closing&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,failure);
}

@override
String toString() {
    return 'BridgeAcpAuthState.closing(operationId: $operationId, failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_ClosingCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_ClosingCopyWith(BridgeAcpAuthState_Closing value, $Res Function(BridgeAcpAuthState_Closing) _then) = _$BridgeAcpAuthState_ClosingCopyWithImpl;
@useResult
$Res call({
 String operationId, BridgeAcpAuthFailure? failure
});




}
/// @nodoc
class _$BridgeAcpAuthState_ClosingCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_ClosingCopyWith<$Res> {
  _$BridgeAcpAuthState_ClosingCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Closing _self;
  final $Res Function(BridgeAcpAuthState_Closing) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? failure = freezed,}) {
  return _then(BridgeAcpAuthState_Closing(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthFailure?,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Verified extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Verified({required this.checkedAt, this.server}): super._();


 final  PlatformInt64 checkedAt;
 final  BridgeAcpServerInfo? server;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_VerifiedCopyWith<BridgeAcpAuthState_Verified> get copyWith => _$BridgeAcpAuthState_VerifiedCopyWithImpl<BridgeAcpAuthState_Verified>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Verified&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.server, server) || other.server == server));
}


@override
int get hashCode {
    return Object.hash(runtimeType,checkedAt,server);
}

@override
String toString() {
    return 'BridgeAcpAuthState.verified(checkedAt: $checkedAt, server: $server)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_VerifiedCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_VerifiedCopyWith(BridgeAcpAuthState_Verified value, $Res Function(BridgeAcpAuthState_Verified) _then) = _$BridgeAcpAuthState_VerifiedCopyWithImpl;
@useResult
$Res call({
 PlatformInt64 checkedAt, BridgeAcpServerInfo? server
});




}
/// @nodoc
class _$BridgeAcpAuthState_VerifiedCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_VerifiedCopyWith<$Res> {
  _$BridgeAcpAuthState_VerifiedCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Verified _self;
  final $Res Function(BridgeAcpAuthState_Verified) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? checkedAt = null,Object? server = freezed,}) {
  return _then(BridgeAcpAuthState_Verified(
checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as PlatformInt64,server: freezed == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as BridgeAcpServerInfo?,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Cancelling extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Cancelling({required this.operationId}): super._();


 final  String operationId;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_CancellingCopyWith<BridgeAcpAuthState_Cancelling> get copyWith => _$BridgeAcpAuthState_CancellingCopyWithImpl<BridgeAcpAuthState_Cancelling>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Cancelling&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}

@override
String toString() {
    return 'BridgeAcpAuthState.cancelling(operationId: $operationId)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_CancellingCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_CancellingCopyWith(BridgeAcpAuthState_Cancelling value, $Res Function(BridgeAcpAuthState_Cancelling) _then) = _$BridgeAcpAuthState_CancellingCopyWithImpl;
@useResult
$Res call({
 String operationId
});




}
/// @nodoc
class _$BridgeAcpAuthState_CancellingCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_CancellingCopyWith<$Res> {
  _$BridgeAcpAuthState_CancellingCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Cancelling _self;
  final $Res Function(BridgeAcpAuthState_Cancelling) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(BridgeAcpAuthState_Cancelling(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeAcpAuthState_Cancelled extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Cancelled(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Cancelled);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeAcpAuthState.cancelled()';
}


}




/// @nodoc


class BridgeAcpAuthState_Failed extends BridgeAcpAuthState {
  const BridgeAcpAuthState_Failed({required this.failure}): super._();


 final  BridgeAcpAuthFailure failure;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpAuthState_FailedCopyWith<BridgeAcpAuthState_Failed> get copyWith => _$BridgeAcpAuthState_FailedCopyWithImpl<BridgeAcpAuthState_Failed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpAuthState_Failed&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failure);
}

@override
String toString() {
    return 'BridgeAcpAuthState.failed(failure: $failure)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpAuthState_FailedCopyWith<$Res> implements $BridgeAcpAuthStateCopyWith<$Res> {
  factory $BridgeAcpAuthState_FailedCopyWith(BridgeAcpAuthState_Failed value, $Res Function(BridgeAcpAuthState_Failed) _then) = _$BridgeAcpAuthState_FailedCopyWithImpl;
@useResult
$Res call({
 BridgeAcpAuthFailure failure
});




}
/// @nodoc
class _$BridgeAcpAuthState_FailedCopyWithImpl<$Res>
    implements $BridgeAcpAuthState_FailedCopyWith<$Res> {
  _$BridgeAcpAuthState_FailedCopyWithImpl(this._self, this._then);

  final BridgeAcpAuthState_Failed _self;
  final $Res Function(BridgeAcpAuthState_Failed) _then;

/// Create a copy of BridgeAcpAuthState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failure = null,}) {
  return _then(BridgeAcpAuthState_Failed(
failure: null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as BridgeAcpAuthFailure,
  ));
}


}

// dart format on
