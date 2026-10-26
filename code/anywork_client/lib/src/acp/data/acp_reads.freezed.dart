// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAuthStartRequest {

 OperationId get operationId; String get accountId;/// 提交时冻结的连接代次；保存/删除/发行变化后旧值会被运行期拒绝。
 int get expectedConnectionRevision; AcpAuthAction get action;
/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthStartRequestCopyWith<AcpAuthStartRequest> get copyWith => _$AcpAuthStartRequestCopyWithImpl<AcpAuthStartRequest>(this as AcpAuthStartRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthStartRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthStartRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.expectedConnectionRevision, _this.expectedConnectionRevision) || other.expectedConnectionRevision == _this.expectedConnectionRevision)&&(identical(other.action, _this.action) || other.action == _this.action));
}


@override
int get hashCode {
  final _this = this as AcpAuthStartRequest;
  return Object.hash(runtimeType,_this.operationId,_this.accountId,_this.expectedConnectionRevision,_this.action);
}

@override
String toString() {
  final _this = this as AcpAuthStartRequest;
  return 'AcpAuthStartRequest(operationId: ${_this.operationId}, accountId: ${_this.accountId}, expectedConnectionRevision: ${_this.expectedConnectionRevision}, action: ${_this.action})';
}


}

/// @nodoc
abstract mixin class $AcpAuthStartRequestCopyWith<$Res>  {
  factory $AcpAuthStartRequestCopyWith(AcpAuthStartRequest value, $Res Function(AcpAuthStartRequest) _then) = _$AcpAuthStartRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String accountId, int expectedConnectionRevision, AcpAuthAction action
});


$OperationIdCopyWith<$Res> get operationId;$AcpAuthActionCopyWith<$Res> get action;

}
/// @nodoc
class _$AcpAuthStartRequestCopyWithImpl<$Res>
    implements $AcpAuthStartRequestCopyWith<$Res> {
  _$AcpAuthStartRequestCopyWithImpl(this._self, this._then);

  final AcpAuthStartRequest _self;
  final $Res Function(AcpAuthStartRequest) _then;

/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? accountId = null,Object? expectedConnectionRevision = null,Object? action = null,}) {
  return _then(AcpAuthStartRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,expectedConnectionRevision: null == expectedConnectionRevision ? _self.expectedConnectionRevision : expectedConnectionRevision // ignore: cast_nullable_to_non_nullable
as int,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as AcpAuthAction,
  ));
}
/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthActionCopyWith<$Res> get action {

  return $AcpAuthActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthStartRequest].
extension AcpAuthStartRequestPatterns on AcpAuthStartRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthStartRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthStartRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthStartRequest value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthStartRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthStartRequest value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthStartRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String accountId,  int expectedConnectionRevision,  AcpAuthAction action)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthStartRequest() when $default != null:
return $default(_that.operationId,_that.accountId,_that.expectedConnectionRevision,_that.action);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String accountId,  int expectedConnectionRevision,  AcpAuthAction action)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthStartRequest():
return $default(_that.operationId,_that.accountId,_that.expectedConnectionRevision,_that.action);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String accountId,  int expectedConnectionRevision,  AcpAuthAction action)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthStartRequest() when $default != null:
return $default(_that.operationId,_that.accountId,_that.expectedConnectionRevision,_that.action);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthStartRequest implements AcpAuthStartRequest {
  const _AcpAuthStartRequest({required this.operationId, required this.accountId, required this.expectedConnectionRevision, required this.action});


@override final  OperationId operationId;
@override final  String accountId;
/// 提交时冻结的连接代次；保存/删除/发行变化后旧值会被运行期拒绝。
@override final  int expectedConnectionRevision;
@override final  AcpAuthAction action;

/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthStartRequestCopyWith<_AcpAuthStartRequest> get copyWith => __$AcpAuthStartRequestCopyWithImpl<_AcpAuthStartRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthStartRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.expectedConnectionRevision, expectedConnectionRevision) || other.expectedConnectionRevision == expectedConnectionRevision)&&(identical(other.action, action) || other.action == action));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,accountId,expectedConnectionRevision,action);
}

@override
String toString() {
    return 'AcpAuthStartRequest(operationId: $operationId, accountId: $accountId, expectedConnectionRevision: $expectedConnectionRevision, action: $action)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthStartRequestCopyWith<$Res> implements $AcpAuthStartRequestCopyWith<$Res> {
  factory _$AcpAuthStartRequestCopyWith(_AcpAuthStartRequest value, $Res Function(_AcpAuthStartRequest) _then) = __$AcpAuthStartRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String accountId, int expectedConnectionRevision, AcpAuthAction action
});


@override $OperationIdCopyWith<$Res> get operationId;@override $AcpAuthActionCopyWith<$Res> get action;

}
/// @nodoc
class __$AcpAuthStartRequestCopyWithImpl<$Res>
    implements _$AcpAuthStartRequestCopyWith<$Res> {
  __$AcpAuthStartRequestCopyWithImpl(this._self, this._then);

  final _AcpAuthStartRequest _self;
  final $Res Function(_AcpAuthStartRequest) _then;

/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? accountId = null,Object? expectedConnectionRevision = null,Object? action = null,}) {
  return _then(_AcpAuthStartRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,expectedConnectionRevision: null == expectedConnectionRevision ? _self.expectedConnectionRevision : expectedConnectionRevision // ignore: cast_nullable_to_non_nullable
as int,action: null == action ? _self.action : action // ignore: cast_nullable_to_non_nullable
as AcpAuthAction,
  ));
}

/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpAuthStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthActionCopyWith<$Res> get action {

  return $AcpAuthActionCopyWith<$Res>(_self.action, (value) {
    return _then(_self.copyWith(action: value));
  });
}
}

/// @nodoc
mixin _$AcpAuthCancelRequest {

 OperationId get operationId; String get accountId; OperationId get targetOperationId;
/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthCancelRequestCopyWith<AcpAuthCancelRequest> get copyWith => _$AcpAuthCancelRequestCopyWithImpl<AcpAuthCancelRequest>(this as AcpAuthCancelRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthCancelRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthCancelRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.targetOperationId, _this.targetOperationId) || other.targetOperationId == _this.targetOperationId));
}


@override
int get hashCode {
  final _this = this as AcpAuthCancelRequest;
  return Object.hash(runtimeType,_this.operationId,_this.accountId,_this.targetOperationId);
}

@override
String toString() {
  final _this = this as AcpAuthCancelRequest;
  return 'AcpAuthCancelRequest(operationId: ${_this.operationId}, accountId: ${_this.accountId}, targetOperationId: ${_this.targetOperationId})';
}


}

/// @nodoc
abstract mixin class $AcpAuthCancelRequestCopyWith<$Res>  {
  factory $AcpAuthCancelRequestCopyWith(AcpAuthCancelRequest value, $Res Function(AcpAuthCancelRequest) _then) = _$AcpAuthCancelRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String accountId, OperationId targetOperationId
});


$OperationIdCopyWith<$Res> get operationId;$OperationIdCopyWith<$Res> get targetOperationId;

}
/// @nodoc
class _$AcpAuthCancelRequestCopyWithImpl<$Res>
    implements $AcpAuthCancelRequestCopyWith<$Res> {
  _$AcpAuthCancelRequestCopyWithImpl(this._self, this._then);

  final AcpAuthCancelRequest _self;
  final $Res Function(AcpAuthCancelRequest) _then;

/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? accountId = null,Object? targetOperationId = null,}) {
  return _then(AcpAuthCancelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,targetOperationId: null == targetOperationId ? _self.targetOperationId : targetOperationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}
/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get targetOperationId {

  return $OperationIdCopyWith<$Res>(_self.targetOperationId, (value) {
    return _then(_self.copyWith(targetOperationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthCancelRequest].
extension AcpAuthCancelRequestPatterns on AcpAuthCancelRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthCancelRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthCancelRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthCancelRequest value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthCancelRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthCancelRequest value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthCancelRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  String accountId,  OperationId targetOperationId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthCancelRequest() when $default != null:
return $default(_that.operationId,_that.accountId,_that.targetOperationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  String accountId,  OperationId targetOperationId)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthCancelRequest():
return $default(_that.operationId,_that.accountId,_that.targetOperationId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  String accountId,  OperationId targetOperationId)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthCancelRequest() when $default != null:
return $default(_that.operationId,_that.accountId,_that.targetOperationId);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthCancelRequest implements AcpAuthCancelRequest {
  const _AcpAuthCancelRequest({required this.operationId, required this.accountId, required this.targetOperationId});


@override final  OperationId operationId;
@override final  String accountId;
@override final  OperationId targetOperationId;

/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthCancelRequestCopyWith<_AcpAuthCancelRequest> get copyWith => __$AcpAuthCancelRequestCopyWithImpl<_AcpAuthCancelRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthCancelRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.targetOperationId, targetOperationId) || other.targetOperationId == targetOperationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,accountId,targetOperationId);
}

@override
String toString() {
    return 'AcpAuthCancelRequest(operationId: $operationId, accountId: $accountId, targetOperationId: $targetOperationId)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthCancelRequestCopyWith<$Res> implements $AcpAuthCancelRequestCopyWith<$Res> {
  factory _$AcpAuthCancelRequestCopyWith(_AcpAuthCancelRequest value, $Res Function(_AcpAuthCancelRequest) _then) = __$AcpAuthCancelRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, String accountId, OperationId targetOperationId
});


@override $OperationIdCopyWith<$Res> get operationId;@override $OperationIdCopyWith<$Res> get targetOperationId;

}
/// @nodoc
class __$AcpAuthCancelRequestCopyWithImpl<$Res>
    implements _$AcpAuthCancelRequestCopyWith<$Res> {
  __$AcpAuthCancelRequestCopyWithImpl(this._self, this._then);

  final _AcpAuthCancelRequest _self;
  final $Res Function(_AcpAuthCancelRequest) _then;

/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? accountId = null,Object? targetOperationId = null,}) {
  return _then(_AcpAuthCancelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,targetOperationId: null == targetOperationId ? _self.targetOperationId : targetOperationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}

/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpAuthCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get targetOperationId {

  return $OperationIdCopyWith<$Res>(_self.targetOperationId, (value) {
    return _then(_self.copyWith(targetOperationId: value));
  });
}
}

/// @nodoc
mixin _$AcpInstallStartRequest {

 OperationId get operationId; AcpProvider get provider;
/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallStartRequestCopyWith<AcpInstallStartRequest> get copyWith => _$AcpInstallStartRequestCopyWithImpl<AcpInstallStartRequest>(this as AcpInstallStartRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallStartRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallStartRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.provider, _this.provider) || other.provider == _this.provider));
}


@override
int get hashCode {
  final _this = this as AcpInstallStartRequest;
  return Object.hash(runtimeType,_this.operationId,_this.provider);
}

@override
String toString() {
  final _this = this as AcpInstallStartRequest;
  return 'AcpInstallStartRequest(operationId: ${_this.operationId}, provider: ${_this.provider})';
}


}

/// @nodoc
abstract mixin class $AcpInstallStartRequestCopyWith<$Res>  {
  factory $AcpInstallStartRequestCopyWith(AcpInstallStartRequest value, $Res Function(AcpInstallStartRequest) _then) = _$AcpInstallStartRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, AcpProvider provider
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$AcpInstallStartRequestCopyWithImpl<$Res>
    implements $AcpInstallStartRequestCopyWith<$Res> {
  _$AcpInstallStartRequestCopyWithImpl(this._self, this._then);

  final AcpInstallStartRequest _self;
  final $Res Function(AcpInstallStartRequest) _then;

/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? provider = null,}) {
  return _then(AcpInstallStartRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,
  ));
}
/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpInstallStartRequest].
extension AcpInstallStartRequestPatterns on AcpInstallStartRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallStartRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallStartRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallStartRequest value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallStartRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallStartRequest value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallStartRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  AcpProvider provider)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallStartRequest() when $default != null:
return $default(_that.operationId,_that.provider);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  AcpProvider provider)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallStartRequest():
return $default(_that.operationId,_that.provider);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  AcpProvider provider)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallStartRequest() when $default != null:
return $default(_that.operationId,_that.provider);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallStartRequest implements AcpInstallStartRequest {
  const _AcpInstallStartRequest({required this.operationId, required this.provider});


@override final  OperationId operationId;
@override final  AcpProvider provider;

/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallStartRequestCopyWith<_AcpInstallStartRequest> get copyWith => __$AcpInstallStartRequestCopyWithImpl<_AcpInstallStartRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallStartRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,provider);
}

@override
String toString() {
    return 'AcpInstallStartRequest(operationId: $operationId, provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$AcpInstallStartRequestCopyWith<$Res> implements $AcpInstallStartRequestCopyWith<$Res> {
  factory _$AcpInstallStartRequestCopyWith(_AcpInstallStartRequest value, $Res Function(_AcpInstallStartRequest) _then) = __$AcpInstallStartRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, AcpProvider provider
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$AcpInstallStartRequestCopyWithImpl<$Res>
    implements _$AcpInstallStartRequestCopyWith<$Res> {
  __$AcpInstallStartRequestCopyWithImpl(this._self, this._then);

  final _AcpInstallStartRequest _self;
  final $Res Function(_AcpInstallStartRequest) _then;

/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? provider = null,}) {
  return _then(_AcpInstallStartRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,
  ));
}

/// Create a copy of AcpInstallStartRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$AcpInstallCancelRequest {

 OperationId get operationId; AcpProvider get provider; OperationId get targetOperationId;
/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallCancelRequestCopyWith<AcpInstallCancelRequest> get copyWith => _$AcpInstallCancelRequestCopyWithImpl<AcpInstallCancelRequest>(this as AcpInstallCancelRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallCancelRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallCancelRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.targetOperationId, _this.targetOperationId) || other.targetOperationId == _this.targetOperationId));
}


@override
int get hashCode {
  final _this = this as AcpInstallCancelRequest;
  return Object.hash(runtimeType,_this.operationId,_this.provider,_this.targetOperationId);
}

@override
String toString() {
  final _this = this as AcpInstallCancelRequest;
  return 'AcpInstallCancelRequest(operationId: ${_this.operationId}, provider: ${_this.provider}, targetOperationId: ${_this.targetOperationId})';
}


}

/// @nodoc
abstract mixin class $AcpInstallCancelRequestCopyWith<$Res>  {
  factory $AcpInstallCancelRequestCopyWith(AcpInstallCancelRequest value, $Res Function(AcpInstallCancelRequest) _then) = _$AcpInstallCancelRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, AcpProvider provider, OperationId targetOperationId
});


$OperationIdCopyWith<$Res> get operationId;$OperationIdCopyWith<$Res> get targetOperationId;

}
/// @nodoc
class _$AcpInstallCancelRequestCopyWithImpl<$Res>
    implements $AcpInstallCancelRequestCopyWith<$Res> {
  _$AcpInstallCancelRequestCopyWithImpl(this._self, this._then);

  final AcpInstallCancelRequest _self;
  final $Res Function(AcpInstallCancelRequest) _then;

/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? provider = null,Object? targetOperationId = null,}) {
  return _then(AcpInstallCancelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,targetOperationId: null == targetOperationId ? _self.targetOperationId : targetOperationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}
/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get targetOperationId {

  return $OperationIdCopyWith<$Res>(_self.targetOperationId, (value) {
    return _then(_self.copyWith(targetOperationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpInstallCancelRequest].
extension AcpInstallCancelRequestPatterns on AcpInstallCancelRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallCancelRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallCancelRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallCancelRequest value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallCancelRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallCancelRequest value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallCancelRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  AcpProvider provider,  OperationId targetOperationId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallCancelRequest() when $default != null:
return $default(_that.operationId,_that.provider,_that.targetOperationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  AcpProvider provider,  OperationId targetOperationId)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallCancelRequest():
return $default(_that.operationId,_that.provider,_that.targetOperationId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  AcpProvider provider,  OperationId targetOperationId)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallCancelRequest() when $default != null:
return $default(_that.operationId,_that.provider,_that.targetOperationId);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallCancelRequest implements AcpInstallCancelRequest {
  const _AcpInstallCancelRequest({required this.operationId, required this.provider, required this.targetOperationId});


@override final  OperationId operationId;
@override final  AcpProvider provider;
@override final  OperationId targetOperationId;

/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallCancelRequestCopyWith<_AcpInstallCancelRequest> get copyWith => __$AcpInstallCancelRequestCopyWithImpl<_AcpInstallCancelRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallCancelRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.targetOperationId, targetOperationId) || other.targetOperationId == targetOperationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,provider,targetOperationId);
}

@override
String toString() {
    return 'AcpInstallCancelRequest(operationId: $operationId, provider: $provider, targetOperationId: $targetOperationId)';
}


}

/// @nodoc
abstract mixin class _$AcpInstallCancelRequestCopyWith<$Res> implements $AcpInstallCancelRequestCopyWith<$Res> {
  factory _$AcpInstallCancelRequestCopyWith(_AcpInstallCancelRequest value, $Res Function(_AcpInstallCancelRequest) _then) = __$AcpInstallCancelRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, AcpProvider provider, OperationId targetOperationId
});


@override $OperationIdCopyWith<$Res> get operationId;@override $OperationIdCopyWith<$Res> get targetOperationId;

}
/// @nodoc
class __$AcpInstallCancelRequestCopyWithImpl<$Res>
    implements _$AcpInstallCancelRequestCopyWith<$Res> {
  __$AcpInstallCancelRequestCopyWithImpl(this._self, this._then);

  final _AcpInstallCancelRequest _self;
  final $Res Function(_AcpInstallCancelRequest) _then;

/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? provider = null,Object? targetOperationId = null,}) {
  return _then(_AcpInstallCancelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,targetOperationId: null == targetOperationId ? _self.targetOperationId : targetOperationId // ignore: cast_nullable_to_non_nullable
as OperationId,
  ));
}

/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of AcpInstallCancelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get targetOperationId {

  return $OperationIdCopyWith<$Res>(_self.targetOperationId, (value) {
    return _then(_self.copyWith(targetOperationId: value));
  });
}
}

/// @nodoc
mixin _$AcpAuthCommandReply {

 CommitReceipt get receipt; AcpAuthSnapshot get snapshot;
/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthCommandReplyCopyWith<AcpAuthCommandReply> get copyWith => _$AcpAuthCommandReplyCopyWithImpl<AcpAuthCommandReply>(this as AcpAuthCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthCommandReply&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as AcpAuthCommandReply;
  return Object.hash(runtimeType,_this.receipt,_this.snapshot);
}

@override
String toString() {
  final _this = this as AcpAuthCommandReply;
  return 'AcpAuthCommandReply(receipt: ${_this.receipt}, snapshot: ${_this.snapshot})';
}


}

/// @nodoc
abstract mixin class $AcpAuthCommandReplyCopyWith<$Res>  {
  factory $AcpAuthCommandReplyCopyWith(AcpAuthCommandReply value, $Res Function(AcpAuthCommandReply) _then) = _$AcpAuthCommandReplyCopyWithImpl;
@useResult
$Res call({
 CommitReceipt receipt, AcpAuthSnapshot snapshot
});


$CommitReceiptCopyWith<$Res> get receipt;$AcpAuthSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpAuthCommandReplyCopyWithImpl<$Res>
    implements $AcpAuthCommandReplyCopyWith<$Res> {
  _$AcpAuthCommandReplyCopyWithImpl(this._self, this._then);

  final AcpAuthCommandReply _self;
  final $Res Function(AcpAuthCommandReply) _then;

/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? receipt = null,Object? snapshot = null,}) {
  return _then(AcpAuthCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot,
  ));
}
/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res> get snapshot {

  return $AcpAuthSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthCommandReply].
extension AcpAuthCommandReplyPatterns on AcpAuthCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CommitReceipt receipt,  AcpAuthSnapshot snapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthCommandReply() when $default != null:
return $default(_that.receipt,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CommitReceipt receipt,  AcpAuthSnapshot snapshot)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthCommandReply():
return $default(_that.receipt,_that.snapshot);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CommitReceipt receipt,  AcpAuthSnapshot snapshot)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthCommandReply() when $default != null:
return $default(_that.receipt,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthCommandReply implements AcpAuthCommandReply {
  const _AcpAuthCommandReply({required this.receipt, required this.snapshot});


@override final  CommitReceipt receipt;
@override final  AcpAuthSnapshot snapshot;

/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthCommandReplyCopyWith<_AcpAuthCommandReply> get copyWith => __$AcpAuthCommandReplyCopyWithImpl<_AcpAuthCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthCommandReply&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,snapshot);
}

@override
String toString() {
    return 'AcpAuthCommandReply(receipt: $receipt, snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthCommandReplyCopyWith<$Res> implements $AcpAuthCommandReplyCopyWith<$Res> {
  factory _$AcpAuthCommandReplyCopyWith(_AcpAuthCommandReply value, $Res Function(_AcpAuthCommandReply) _then) = __$AcpAuthCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, AcpAuthSnapshot snapshot
});


@override $CommitReceiptCopyWith<$Res> get receipt;@override $AcpAuthSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class __$AcpAuthCommandReplyCopyWithImpl<$Res>
    implements _$AcpAuthCommandReplyCopyWith<$Res> {
  __$AcpAuthCommandReplyCopyWithImpl(this._self, this._then);

  final _AcpAuthCommandReply _self;
  final $Res Function(_AcpAuthCommandReply) _then;

/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? snapshot = null,}) {
  return _then(_AcpAuthCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot,
  ));
}

/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of AcpAuthCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res> get snapshot {

  return $AcpAuthSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

/// @nodoc
mixin _$AcpInstallCommandReply {

 CommitReceipt get receipt; AcpInstallSnapshot get snapshot;
/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallCommandReplyCopyWith<AcpInstallCommandReply> get copyWith => _$AcpInstallCommandReplyCopyWithImpl<AcpInstallCommandReply>(this as AcpInstallCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallCommandReply&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as AcpInstallCommandReply;
  return Object.hash(runtimeType,_this.receipt,_this.snapshot);
}

@override
String toString() {
  final _this = this as AcpInstallCommandReply;
  return 'AcpInstallCommandReply(receipt: ${_this.receipt}, snapshot: ${_this.snapshot})';
}


}

/// @nodoc
abstract mixin class $AcpInstallCommandReplyCopyWith<$Res>  {
  factory $AcpInstallCommandReplyCopyWith(AcpInstallCommandReply value, $Res Function(AcpInstallCommandReply) _then) = _$AcpInstallCommandReplyCopyWithImpl;
@useResult
$Res call({
 CommitReceipt receipt, AcpInstallSnapshot snapshot
});


$CommitReceiptCopyWith<$Res> get receipt;$AcpInstallSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpInstallCommandReplyCopyWithImpl<$Res>
    implements $AcpInstallCommandReplyCopyWith<$Res> {
  _$AcpInstallCommandReplyCopyWithImpl(this._self, this._then);

  final AcpInstallCommandReply _self;
  final $Res Function(AcpInstallCommandReply) _then;

/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? receipt = null,Object? snapshot = null,}) {
  return _then(AcpInstallCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpInstallSnapshot,
  ));
}
/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallSnapshotCopyWith<$Res> get snapshot {

  return $AcpInstallSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpInstallCommandReply].
extension AcpInstallCommandReplyPatterns on AcpInstallCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CommitReceipt receipt,  AcpInstallSnapshot snapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallCommandReply() when $default != null:
return $default(_that.receipt,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CommitReceipt receipt,  AcpInstallSnapshot snapshot)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallCommandReply():
return $default(_that.receipt,_that.snapshot);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CommitReceipt receipt,  AcpInstallSnapshot snapshot)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallCommandReply() when $default != null:
return $default(_that.receipt,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallCommandReply implements AcpInstallCommandReply {
  const _AcpInstallCommandReply({required this.receipt, required this.snapshot});


@override final  CommitReceipt receipt;
@override final  AcpInstallSnapshot snapshot;

/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallCommandReplyCopyWith<_AcpInstallCommandReply> get copyWith => __$AcpInstallCommandReplyCopyWithImpl<_AcpInstallCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallCommandReply&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,snapshot);
}

@override
String toString() {
    return 'AcpInstallCommandReply(receipt: $receipt, snapshot: $snapshot)';
}


}

/// @nodoc
abstract mixin class _$AcpInstallCommandReplyCopyWith<$Res> implements $AcpInstallCommandReplyCopyWith<$Res> {
  factory _$AcpInstallCommandReplyCopyWith(_AcpInstallCommandReply value, $Res Function(_AcpInstallCommandReply) _then) = __$AcpInstallCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, AcpInstallSnapshot snapshot
});


@override $CommitReceiptCopyWith<$Res> get receipt;@override $AcpInstallSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class __$AcpInstallCommandReplyCopyWithImpl<$Res>
    implements _$AcpInstallCommandReplyCopyWith<$Res> {
  __$AcpInstallCommandReplyCopyWithImpl(this._self, this._then);

  final _AcpInstallCommandReply _self;
  final $Res Function(_AcpInstallCommandReply) _then;

/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? snapshot = null,}) {
  return _then(_AcpInstallCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpInstallSnapshot,
  ));
}

/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of AcpInstallCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallSnapshotCopyWith<$Res> get snapshot {

  return $AcpInstallSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

// dart format on
