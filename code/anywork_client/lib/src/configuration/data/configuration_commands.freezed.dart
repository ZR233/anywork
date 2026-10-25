// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'configuration_commands.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountSettingsUpdate {


/// Create a copy of AccountSettingsUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountSettingsUpdateCopyWith<AccountSettingsUpdate> get copyWith => _$AccountSettingsUpdateCopyWithImpl<AccountSettingsUpdate>(this as AccountSettingsUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountSettingsUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountSettingsUpdate&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.templateId, _this.templateId) || other.templateId == _this.templateId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.secret, _this.secret) || other.secret == _this.secret)&&(identical(other.pricingEnabled, _this.pricingEnabled) || other.pricingEnabled == _this.pricingEnabled)&&const DeepCollectionEquality().equals(other.customModels, _this.customModels)&&const DeepCollectionEquality().equals(other.modelConnectionModes, _this.modelConnectionModes)&&const DeepCollectionEquality().equals(other.modelAutoCompactLimits, _this.modelAutoCompactLimits));
}


@override
int get hashCode {
  final _this = this as AccountSettingsUpdate;
  return Object.hash(runtimeType,_this.accountId,_this.templateId,_this.protocol,_this.name,_this.baseUrl,_this.secret,_this.pricingEnabled,const DeepCollectionEquality().hash(_this.customModels),const DeepCollectionEquality().hash(_this.modelConnectionModes),const DeepCollectionEquality().hash(_this.modelAutoCompactLimits));
}



}

/// @nodoc
abstract mixin class $AccountSettingsUpdateCopyWith<$Res>  {
  factory $AccountSettingsUpdateCopyWith(AccountSettingsUpdate value, $Res Function(AccountSettingsUpdate) _then) = _$AccountSettingsUpdateCopyWithImpl;
@useResult
$Res call({
 String accountId, String? templateId, String protocol, String name, String baseUrl, AccountSecretUpdate secret, bool pricingEnabled, List<AccountModelUpdate> customModels, List<AccountModelConnectionUpdate> modelConnectionModes, List<AccountModelAutoCompactUpdate> modelAutoCompactLimits
});


$AccountSecretUpdateCopyWith<$Res> get secret;

}
/// @nodoc
class _$AccountSettingsUpdateCopyWithImpl<$Res>
    implements $AccountSettingsUpdateCopyWith<$Res> {
  _$AccountSettingsUpdateCopyWithImpl(this._self, this._then);

  final AccountSettingsUpdate _self;
  final $Res Function(AccountSettingsUpdate) _then;

/// Create a copy of AccountSettingsUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? templateId = freezed,Object? protocol = null,Object? name = null,Object? baseUrl = null,Object? secret = null,Object? pricingEnabled = null,Object? customModels = null,Object? modelConnectionModes = null,Object? modelAutoCompactLimits = null,}) {
  return _then(AccountSettingsUpdate(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,templateId: freezed == templateId ? _self.templateId : templateId // ignore: cast_nullable_to_non_nullable
as String?,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,secret: null == secret ? _self.secret : secret // ignore: cast_nullable_to_non_nullable
as AccountSecretUpdate,pricingEnabled: null == pricingEnabled ? _self.pricingEnabled : pricingEnabled // ignore: cast_nullable_to_non_nullable
as bool,customModels: null == customModels ? _self.customModels : customModels // ignore: cast_nullable_to_non_nullable
as List<AccountModelUpdate>,modelConnectionModes: null == modelConnectionModes ? _self.modelConnectionModes : modelConnectionModes // ignore: cast_nullable_to_non_nullable
as List<AccountModelConnectionUpdate>,modelAutoCompactLimits: null == modelAutoCompactLimits ? _self.modelAutoCompactLimits : modelAutoCompactLimits // ignore: cast_nullable_to_non_nullable
as List<AccountModelAutoCompactUpdate>,
  ));
}
/// Create a copy of AccountSettingsUpdate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountSecretUpdateCopyWith<$Res> get secret {

  return $AccountSecretUpdateCopyWith<$Res>(_self.secret, (value) {
    return _then(_self.copyWith(secret: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountSettingsUpdate].
extension AccountSettingsUpdatePatterns on AccountSettingsUpdate {
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
mixin _$AccountModelConnectionUpdate {

 String get modelId; String get connectionMode;
/// Create a copy of AccountModelConnectionUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelConnectionUpdateCopyWith<AccountModelConnectionUpdate> get copyWith => _$AccountModelConnectionUpdateCopyWithImpl<AccountModelConnectionUpdate>(this as AccountModelConnectionUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelConnectionUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelConnectionUpdate&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.connectionMode, _this.connectionMode) || other.connectionMode == _this.connectionMode));
}


@override
int get hashCode {
  final _this = this as AccountModelConnectionUpdate;
  return Object.hash(runtimeType,_this.modelId,_this.connectionMode);
}

@override
String toString() {
  final _this = this as AccountModelConnectionUpdate;
  return 'AccountModelConnectionUpdate(modelId: ${_this.modelId}, connectionMode: ${_this.connectionMode})';
}


}

/// @nodoc
abstract mixin class $AccountModelConnectionUpdateCopyWith<$Res>  {
  factory $AccountModelConnectionUpdateCopyWith(AccountModelConnectionUpdate value, $Res Function(AccountModelConnectionUpdate) _then) = _$AccountModelConnectionUpdateCopyWithImpl;
@useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class _$AccountModelConnectionUpdateCopyWithImpl<$Res>
    implements $AccountModelConnectionUpdateCopyWith<$Res> {
  _$AccountModelConnectionUpdateCopyWithImpl(this._self, this._then);

  final AccountModelConnectionUpdate _self;
  final $Res Function(AccountModelConnectionUpdate) _then;

/// Create a copy of AccountModelConnectionUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(AccountModelConnectionUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelConnectionUpdate].
extension AccountModelConnectionUpdatePatterns on AccountModelConnectionUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelConnectionUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelConnectionUpdate value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelConnectionUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  String connectionMode)  $default,) {final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate():
return $default(_that.modelId,_that.connectionMode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  String connectionMode)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelConnectionUpdate() when $default != null:
return $default(_that.modelId,_that.connectionMode);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelConnectionUpdate implements AccountModelConnectionUpdate {
  const _AccountModelConnectionUpdate({required this.modelId, required this.connectionMode});


@override final  String modelId;
@override final  String connectionMode;

/// Create a copy of AccountModelConnectionUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelConnectionUpdateCopyWith<_AccountModelConnectionUpdate> get copyWith => __$AccountModelConnectionUpdateCopyWithImpl<_AccountModelConnectionUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelConnectionUpdate&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.connectionMode, connectionMode) || other.connectionMode == connectionMode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,connectionMode);
}

@override
String toString() {
    return 'AccountModelConnectionUpdate(modelId: $modelId, connectionMode: $connectionMode)';
}


}

/// @nodoc
abstract mixin class _$AccountModelConnectionUpdateCopyWith<$Res> implements $AccountModelConnectionUpdateCopyWith<$Res> {
  factory _$AccountModelConnectionUpdateCopyWith(_AccountModelConnectionUpdate value, $Res Function(_AccountModelConnectionUpdate) _then) = __$AccountModelConnectionUpdateCopyWithImpl;
@override @useResult
$Res call({
 String modelId, String connectionMode
});




}
/// @nodoc
class __$AccountModelConnectionUpdateCopyWithImpl<$Res>
    implements _$AccountModelConnectionUpdateCopyWith<$Res> {
  __$AccountModelConnectionUpdateCopyWithImpl(this._self, this._then);

  final _AccountModelConnectionUpdate _self;
  final $Res Function(_AccountModelConnectionUpdate) _then;

/// Create a copy of AccountModelConnectionUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? connectionMode = null,}) {
  return _then(_AccountModelConnectionUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,connectionMode: null == connectionMode ? _self.connectionMode : connectionMode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountModelAutoCompactUpdate {

 String get modelId; int get limit;
/// Create a copy of AccountModelAutoCompactUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelAutoCompactUpdateCopyWith<AccountModelAutoCompactUpdate> get copyWith => _$AccountModelAutoCompactUpdateCopyWithImpl<AccountModelAutoCompactUpdate>(this as AccountModelAutoCompactUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelAutoCompactUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelAutoCompactUpdate&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.limit, _this.limit) || other.limit == _this.limit));
}


@override
int get hashCode {
  final _this = this as AccountModelAutoCompactUpdate;
  return Object.hash(runtimeType,_this.modelId,_this.limit);
}

@override
String toString() {
  final _this = this as AccountModelAutoCompactUpdate;
  return 'AccountModelAutoCompactUpdate(modelId: ${_this.modelId}, limit: ${_this.limit})';
}


}

/// @nodoc
abstract mixin class $AccountModelAutoCompactUpdateCopyWith<$Res>  {
  factory $AccountModelAutoCompactUpdateCopyWith(AccountModelAutoCompactUpdate value, $Res Function(AccountModelAutoCompactUpdate) _then) = _$AccountModelAutoCompactUpdateCopyWithImpl;
@useResult
$Res call({
 String modelId, int limit
});




}
/// @nodoc
class _$AccountModelAutoCompactUpdateCopyWithImpl<$Res>
    implements $AccountModelAutoCompactUpdateCopyWith<$Res> {
  _$AccountModelAutoCompactUpdateCopyWithImpl(this._self, this._then);

  final AccountModelAutoCompactUpdate _self;
  final $Res Function(AccountModelAutoCompactUpdate) _then;

/// Create a copy of AccountModelAutoCompactUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelId = null,Object? limit = null,}) {
  return _then(AccountModelAutoCompactUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelAutoCompactUpdate].
extension AccountModelAutoCompactUpdatePatterns on AccountModelAutoCompactUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelAutoCompactUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelAutoCompactUpdate value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelAutoCompactUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String modelId,  int limit)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate() when $default != null:
return $default(_that.modelId,_that.limit);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String modelId,  int limit)  $default,) {final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate():
return $default(_that.modelId,_that.limit);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String modelId,  int limit)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelAutoCompactUpdate() when $default != null:
return $default(_that.modelId,_that.limit);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelAutoCompactUpdate implements AccountModelAutoCompactUpdate {
  const _AccountModelAutoCompactUpdate({required this.modelId, required this.limit});


@override final  String modelId;
@override final  int limit;

/// Create a copy of AccountModelAutoCompactUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelAutoCompactUpdateCopyWith<_AccountModelAutoCompactUpdate> get copyWith => __$AccountModelAutoCompactUpdateCopyWithImpl<_AccountModelAutoCompactUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelAutoCompactUpdate&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.limit, limit) || other.limit == limit));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelId,limit);
}

@override
String toString() {
    return 'AccountModelAutoCompactUpdate(modelId: $modelId, limit: $limit)';
}


}

/// @nodoc
abstract mixin class _$AccountModelAutoCompactUpdateCopyWith<$Res> implements $AccountModelAutoCompactUpdateCopyWith<$Res> {
  factory _$AccountModelAutoCompactUpdateCopyWith(_AccountModelAutoCompactUpdate value, $Res Function(_AccountModelAutoCompactUpdate) _then) = __$AccountModelAutoCompactUpdateCopyWithImpl;
@override @useResult
$Res call({
 String modelId, int limit
});




}
/// @nodoc
class __$AccountModelAutoCompactUpdateCopyWithImpl<$Res>
    implements _$AccountModelAutoCompactUpdateCopyWith<$Res> {
  __$AccountModelAutoCompactUpdateCopyWithImpl(this._self, this._then);

  final _AccountModelAutoCompactUpdate _self;
  final $Res Function(_AccountModelAutoCompactUpdate) _then;

/// Create a copy of AccountModelAutoCompactUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelId = null,Object? limit = null,}) {
  return _then(_AccountModelAutoCompactUpdate(
modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,limit: null == limit ? _self.limit : limit // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$UpdateAccountRequest {

 OperationId get operationId; int get expectedRevision; AccountSettingsUpdate get account;
/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateAccountRequestCopyWith<UpdateAccountRequest> get copyWith => _$UpdateAccountRequestCopyWithImpl<UpdateAccountRequest>(this as UpdateAccountRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateAccountRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateAccountRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.account, _this.account) || other.account == _this.account));
}


@override
int get hashCode {
  final _this = this as UpdateAccountRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.account);
}



}

/// @nodoc
abstract mixin class $UpdateAccountRequestCopyWith<$Res>  {
  factory $UpdateAccountRequestCopyWith(UpdateAccountRequest value, $Res Function(UpdateAccountRequest) _then) = _$UpdateAccountRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, AccountSettingsUpdate account
});


$OperationIdCopyWith<$Res> get operationId;$AccountSettingsUpdateCopyWith<$Res> get account;

}
/// @nodoc
class _$UpdateAccountRequestCopyWithImpl<$Res>
    implements $UpdateAccountRequestCopyWith<$Res> {
  _$UpdateAccountRequestCopyWithImpl(this._self, this._then);

  final UpdateAccountRequest _self;
  final $Res Function(UpdateAccountRequest) _then;

/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? account = null,}) {
  return _then(UpdateAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,account: null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AccountSettingsUpdate,
  ));
}
/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountSettingsUpdateCopyWith<$Res> get account {

  return $AccountSettingsUpdateCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateAccountRequest].
extension UpdateAccountRequestPatterns on UpdateAccountRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateAccountRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateAccountRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateAccountRequest value)  $default,){
final _that = this;
switch (_that) {
case _UpdateAccountRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateAccountRequest value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateAccountRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  AccountSettingsUpdate account)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.account);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  AccountSettingsUpdate account)  $default,) {final _that = this;
switch (_that) {
case _UpdateAccountRequest():
return $default(_that.operationId,_that.expectedRevision,_that.account);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  AccountSettingsUpdate account)?  $default,) {final _that = this;
switch (_that) {
case _UpdateAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.account);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateAccountRequest implements UpdateAccountRequest {
  const _UpdateAccountRequest({required this.operationId, required this.expectedRevision, required this.account});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  AccountSettingsUpdate account;

/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateAccountRequestCopyWith<_UpdateAccountRequest> get copyWith => __$UpdateAccountRequestCopyWithImpl<_UpdateAccountRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateAccountRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.account, account) || other.account == account));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,account);
}



}

/// @nodoc
abstract mixin class _$UpdateAccountRequestCopyWith<$Res> implements $UpdateAccountRequestCopyWith<$Res> {
  factory _$UpdateAccountRequestCopyWith(_UpdateAccountRequest value, $Res Function(_UpdateAccountRequest) _then) = __$UpdateAccountRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, AccountSettingsUpdate account
});


@override $OperationIdCopyWith<$Res> get operationId;@override $AccountSettingsUpdateCopyWith<$Res> get account;

}
/// @nodoc
class __$UpdateAccountRequestCopyWithImpl<$Res>
    implements _$UpdateAccountRequestCopyWith<$Res> {
  __$UpdateAccountRequestCopyWithImpl(this._self, this._then);

  final _UpdateAccountRequest _self;
  final $Res Function(_UpdateAccountRequest) _then;

/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? account = null,}) {
  return _then(_UpdateAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,account: null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AccountSettingsUpdate,
  ));
}

/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of UpdateAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountSettingsUpdateCopyWith<$Res> get account {

  return $AccountSettingsUpdateCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}

/// @nodoc
mixin _$SetDefaultAccountRequest {

 OperationId get operationId; int get expectedRevision; String get accountId;
/// Create a copy of SetDefaultAccountRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetDefaultAccountRequestCopyWith<SetDefaultAccountRequest> get copyWith => _$SetDefaultAccountRequestCopyWithImpl<SetDefaultAccountRequest>(this as SetDefaultAccountRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetDefaultAccountRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetDefaultAccountRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId));
}


@override
int get hashCode {
  final _this = this as SetDefaultAccountRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.accountId);
}

@override
String toString() {
  final _this = this as SetDefaultAccountRequest;
  return 'SetDefaultAccountRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, accountId: ${_this.accountId})';
}


}

/// @nodoc
abstract mixin class $SetDefaultAccountRequestCopyWith<$Res>  {
  factory $SetDefaultAccountRequestCopyWith(SetDefaultAccountRequest value, $Res Function(SetDefaultAccountRequest) _then) = _$SetDefaultAccountRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetDefaultAccountRequestCopyWithImpl<$Res>
    implements $SetDefaultAccountRequestCopyWith<$Res> {
  _$SetDefaultAccountRequestCopyWithImpl(this._self, this._then);

  final SetDefaultAccountRequest _self;
  final $Res Function(SetDefaultAccountRequest) _then;

/// Create a copy of SetDefaultAccountRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,}) {
  return _then(SetDefaultAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of SetDefaultAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetDefaultAccountRequest].
extension SetDefaultAccountRequestPatterns on SetDefaultAccountRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetDefaultAccountRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetDefaultAccountRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetDefaultAccountRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetDefaultAccountRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetDefaultAccountRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetDefaultAccountRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetDefaultAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId)  $default,) {final _that = this;
switch (_that) {
case _SetDefaultAccountRequest():
return $default(_that.operationId,_that.expectedRevision,_that.accountId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String accountId)?  $default,) {final _that = this;
switch (_that) {
case _SetDefaultAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId);case _:
  return null;

}
}

}

/// @nodoc


class _SetDefaultAccountRequest implements SetDefaultAccountRequest {
  const _SetDefaultAccountRequest({required this.operationId, required this.expectedRevision, required this.accountId});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String accountId;

/// Create a copy of SetDefaultAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetDefaultAccountRequestCopyWith<_SetDefaultAccountRequest> get copyWith => __$SetDefaultAccountRequestCopyWithImpl<_SetDefaultAccountRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetDefaultAccountRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.accountId, accountId) || other.accountId == accountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,accountId);
}

@override
String toString() {
    return 'SetDefaultAccountRequest(operationId: $operationId, expectedRevision: $expectedRevision, accountId: $accountId)';
}


}

/// @nodoc
abstract mixin class _$SetDefaultAccountRequestCopyWith<$Res> implements $SetDefaultAccountRequestCopyWith<$Res> {
  factory _$SetDefaultAccountRequestCopyWith(_SetDefaultAccountRequest value, $Res Function(_SetDefaultAccountRequest) _then) = __$SetDefaultAccountRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetDefaultAccountRequestCopyWithImpl<$Res>
    implements _$SetDefaultAccountRequestCopyWith<$Res> {
  __$SetDefaultAccountRequestCopyWithImpl(this._self, this._then);

  final _SetDefaultAccountRequest _self;
  final $Res Function(_SetDefaultAccountRequest) _then;

/// Create a copy of SetDefaultAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,}) {
  return _then(_SetDefaultAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of SetDefaultAccountRequest
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
mixin _$RemoveAccountRequest {

 OperationId get operationId; int get expectedRevision; String get accountId; String? get replacementAccountId;
/// Create a copy of RemoveAccountRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveAccountRequestCopyWith<RemoveAccountRequest> get copyWith => _$RemoveAccountRequestCopyWithImpl<RemoveAccountRequest>(this as RemoveAccountRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoveAccountRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveAccountRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.replacementAccountId, _this.replacementAccountId) || other.replacementAccountId == _this.replacementAccountId));
}


@override
int get hashCode {
  final _this = this as RemoveAccountRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.accountId,_this.replacementAccountId);
}

@override
String toString() {
  final _this = this as RemoveAccountRequest;
  return 'RemoveAccountRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, accountId: ${_this.accountId}, replacementAccountId: ${_this.replacementAccountId})';
}


}

/// @nodoc
abstract mixin class $RemoveAccountRequestCopyWith<$Res>  {
  factory $RemoveAccountRequestCopyWith(RemoveAccountRequest value, $Res Function(RemoveAccountRequest) _then) = _$RemoveAccountRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String? replacementAccountId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$RemoveAccountRequestCopyWithImpl<$Res>
    implements $RemoveAccountRequestCopyWith<$Res> {
  _$RemoveAccountRequestCopyWithImpl(this._self, this._then);

  final RemoveAccountRequest _self;
  final $Res Function(RemoveAccountRequest) _then;

/// Create a copy of RemoveAccountRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? replacementAccountId = freezed,}) {
  return _then(RemoveAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,replacementAccountId: freezed == replacementAccountId ? _self.replacementAccountId : replacementAccountId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of RemoveAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoveAccountRequest].
extension RemoveAccountRequestPatterns on RemoveAccountRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoveAccountRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoveAccountRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoveAccountRequest value)  $default,){
final _that = this;
switch (_that) {
case _RemoveAccountRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoveAccountRequest value)?  $default,){
final _that = this;
switch (_that) {
case _RemoveAccountRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String? replacementAccountId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoveAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.replacementAccountId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String? replacementAccountId)  $default,) {final _that = this;
switch (_that) {
case _RemoveAccountRequest():
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.replacementAccountId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String accountId,  String? replacementAccountId)?  $default,) {final _that = this;
switch (_that) {
case _RemoveAccountRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.replacementAccountId);case _:
  return null;

}
}

}

/// @nodoc


class _RemoveAccountRequest implements RemoveAccountRequest {
  const _RemoveAccountRequest({required this.operationId, required this.expectedRevision, required this.accountId, required this.replacementAccountId});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String accountId;
@override final  String? replacementAccountId;

/// Create a copy of RemoveAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoveAccountRequestCopyWith<_RemoveAccountRequest> get copyWith => __$RemoveAccountRequestCopyWithImpl<_RemoveAccountRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoveAccountRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.replacementAccountId, replacementAccountId) || other.replacementAccountId == replacementAccountId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,accountId,replacementAccountId);
}

@override
String toString() {
    return 'RemoveAccountRequest(operationId: $operationId, expectedRevision: $expectedRevision, accountId: $accountId, replacementAccountId: $replacementAccountId)';
}


}

/// @nodoc
abstract mixin class _$RemoveAccountRequestCopyWith<$Res> implements $RemoveAccountRequestCopyWith<$Res> {
  factory _$RemoveAccountRequestCopyWith(_RemoveAccountRequest value, $Res Function(_RemoveAccountRequest) _then) = __$RemoveAccountRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String? replacementAccountId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$RemoveAccountRequestCopyWithImpl<$Res>
    implements _$RemoveAccountRequestCopyWith<$Res> {
  __$RemoveAccountRequestCopyWithImpl(this._self, this._then);

  final _RemoveAccountRequest _self;
  final $Res Function(_RemoveAccountRequest) _then;

/// Create a copy of RemoveAccountRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? replacementAccountId = freezed,}) {
  return _then(_RemoveAccountRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,replacementAccountId: freezed == replacementAccountId ? _self.replacementAccountId : replacementAccountId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of RemoveAccountRequest
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
mixin _$RemoveAccountModelRequest {

 OperationId get operationId; int get expectedRevision; String get accountId; String get modelId;
/// Create a copy of RemoveAccountModelRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoveAccountModelRequestCopyWith<RemoveAccountModelRequest> get copyWith => _$RemoveAccountModelRequestCopyWithImpl<RemoveAccountModelRequest>(this as RemoveAccountModelRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoveAccountModelRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoveAccountModelRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as RemoveAccountModelRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.accountId,_this.modelId);
}

@override
String toString() {
  final _this = this as RemoveAccountModelRequest;
  return 'RemoveAccountModelRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, accountId: ${_this.accountId}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $RemoveAccountModelRequestCopyWith<$Res>  {
  factory $RemoveAccountModelRequestCopyWith(RemoveAccountModelRequest value, $Res Function(RemoveAccountModelRequest) _then) = _$RemoveAccountModelRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String modelId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$RemoveAccountModelRequestCopyWithImpl<$Res>
    implements $RemoveAccountModelRequestCopyWith<$Res> {
  _$RemoveAccountModelRequestCopyWithImpl(this._self, this._then);

  final RemoveAccountModelRequest _self;
  final $Res Function(RemoveAccountModelRequest) _then;

/// Create a copy of RemoveAccountModelRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? modelId = null,}) {
  return _then(RemoveAccountModelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of RemoveAccountModelRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoveAccountModelRequest].
extension RemoveAccountModelRequestPatterns on RemoveAccountModelRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoveAccountModelRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoveAccountModelRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoveAccountModelRequest value)  $default,){
final _that = this;
switch (_that) {
case _RemoveAccountModelRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoveAccountModelRequest value)?  $default,){
final _that = this;
switch (_that) {
case _RemoveAccountModelRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoveAccountModelRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId)  $default,) {final _that = this;
switch (_that) {
case _RemoveAccountModelRequest():
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId)?  $default,) {final _that = this;
switch (_that) {
case _RemoveAccountModelRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _RemoveAccountModelRequest implements RemoveAccountModelRequest {
  const _RemoveAccountModelRequest({required this.operationId, required this.expectedRevision, required this.accountId, required this.modelId});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String accountId;
@override final  String modelId;

/// Create a copy of RemoveAccountModelRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoveAccountModelRequestCopyWith<_RemoveAccountModelRequest> get copyWith => __$RemoveAccountModelRequestCopyWithImpl<_RemoveAccountModelRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoveAccountModelRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,accountId,modelId);
}

@override
String toString() {
    return 'RemoveAccountModelRequest(operationId: $operationId, expectedRevision: $expectedRevision, accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$RemoveAccountModelRequestCopyWith<$Res> implements $RemoveAccountModelRequestCopyWith<$Res> {
  factory _$RemoveAccountModelRequestCopyWith(_RemoveAccountModelRequest value, $Res Function(_RemoveAccountModelRequest) _then) = __$RemoveAccountModelRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String modelId
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$RemoveAccountModelRequestCopyWithImpl<$Res>
    implements _$RemoveAccountModelRequestCopyWith<$Res> {
  __$RemoveAccountModelRequestCopyWithImpl(this._self, this._then);

  final _RemoveAccountModelRequest _self;
  final $Res Function(_RemoveAccountModelRequest) _then;

/// Create a copy of RemoveAccountModelRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? modelId = null,}) {
  return _then(_RemoveAccountModelRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of RemoveAccountModelRequest
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
mixin _$SetAccountModelEnabledRequest {

 OperationId get operationId; int get expectedRevision; String get accountId; String get modelId; bool get enabled;
/// Create a copy of SetAccountModelEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetAccountModelEnabledRequestCopyWith<SetAccountModelEnabledRequest> get copyWith => _$SetAccountModelEnabledRequestCopyWithImpl<SetAccountModelEnabledRequest>(this as SetAccountModelEnabledRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetAccountModelEnabledRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetAccountModelEnabledRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled));
}


@override
int get hashCode {
  final _this = this as SetAccountModelEnabledRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.accountId,_this.modelId,_this.enabled);
}

@override
String toString() {
  final _this = this as SetAccountModelEnabledRequest;
  return 'SetAccountModelEnabledRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, accountId: ${_this.accountId}, modelId: ${_this.modelId}, enabled: ${_this.enabled})';
}


}

/// @nodoc
abstract mixin class $SetAccountModelEnabledRequestCopyWith<$Res>  {
  factory $SetAccountModelEnabledRequestCopyWith(SetAccountModelEnabledRequest value, $Res Function(SetAccountModelEnabledRequest) _then) = _$SetAccountModelEnabledRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String modelId, bool enabled
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetAccountModelEnabledRequestCopyWithImpl<$Res>
    implements $SetAccountModelEnabledRequestCopyWith<$Res> {
  _$SetAccountModelEnabledRequestCopyWithImpl(this._self, this._then);

  final SetAccountModelEnabledRequest _self;
  final $Res Function(SetAccountModelEnabledRequest) _then;

/// Create a copy of SetAccountModelEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? modelId = null,Object? enabled = null,}) {
  return _then(SetAccountModelEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SetAccountModelEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetAccountModelEnabledRequest].
extension SetAccountModelEnabledRequestPatterns on SetAccountModelEnabledRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetAccountModelEnabledRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetAccountModelEnabledRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetAccountModelEnabledRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId,  bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId,_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId,  bool enabled)  $default,) {final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest():
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId,_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String accountId,  String modelId,  bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _SetAccountModelEnabledRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.modelId,_that.enabled);case _:
  return null;

}
}

}

/// @nodoc


class _SetAccountModelEnabledRequest implements SetAccountModelEnabledRequest {
  const _SetAccountModelEnabledRequest({required this.operationId, required this.expectedRevision, required this.accountId, required this.modelId, required this.enabled});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String accountId;
@override final  String modelId;
@override final  bool enabled;

/// Create a copy of SetAccountModelEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetAccountModelEnabledRequestCopyWith<_SetAccountModelEnabledRequest> get copyWith => __$SetAccountModelEnabledRequestCopyWithImpl<_SetAccountModelEnabledRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetAccountModelEnabledRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,accountId,modelId,enabled);
}

@override
String toString() {
    return 'SetAccountModelEnabledRequest(operationId: $operationId, expectedRevision: $expectedRevision, accountId: $accountId, modelId: $modelId, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$SetAccountModelEnabledRequestCopyWith<$Res> implements $SetAccountModelEnabledRequestCopyWith<$Res> {
  factory _$SetAccountModelEnabledRequestCopyWith(_SetAccountModelEnabledRequest value, $Res Function(_SetAccountModelEnabledRequest) _then) = __$SetAccountModelEnabledRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, String modelId, bool enabled
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetAccountModelEnabledRequestCopyWithImpl<$Res>
    implements _$SetAccountModelEnabledRequestCopyWith<$Res> {
  __$SetAccountModelEnabledRequestCopyWithImpl(this._self, this._then);

  final _SetAccountModelEnabledRequest _self;
  final $Res Function(_SetAccountModelEnabledRequest) _then;

/// Create a copy of SetAccountModelEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? modelId = null,Object? enabled = null,}) {
  return _then(_SetAccountModelEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SetAccountModelEnabledRequest
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
mixin _$SetAccountBillingKindRequest {

 OperationId get operationId; int get expectedRevision; String get accountId; BillingKind? get billingKind;
/// Create a copy of SetAccountBillingKindRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetAccountBillingKindRequestCopyWith<SetAccountBillingKindRequest> get copyWith => _$SetAccountBillingKindRequestCopyWithImpl<SetAccountBillingKindRequest>(this as SetAccountBillingKindRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetAccountBillingKindRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetAccountBillingKindRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.billingKind, _this.billingKind) || other.billingKind == _this.billingKind));
}


@override
int get hashCode {
  final _this = this as SetAccountBillingKindRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.accountId,_this.billingKind);
}

@override
String toString() {
  final _this = this as SetAccountBillingKindRequest;
  return 'SetAccountBillingKindRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, accountId: ${_this.accountId}, billingKind: ${_this.billingKind})';
}


}

/// @nodoc
abstract mixin class $SetAccountBillingKindRequestCopyWith<$Res>  {
  factory $SetAccountBillingKindRequestCopyWith(SetAccountBillingKindRequest value, $Res Function(SetAccountBillingKindRequest) _then) = _$SetAccountBillingKindRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, BillingKind? billingKind
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetAccountBillingKindRequestCopyWithImpl<$Res>
    implements $SetAccountBillingKindRequestCopyWith<$Res> {
  _$SetAccountBillingKindRequestCopyWithImpl(this._self, this._then);

  final SetAccountBillingKindRequest _self;
  final $Res Function(SetAccountBillingKindRequest) _then;

/// Create a copy of SetAccountBillingKindRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? billingKind = freezed,}) {
  return _then(SetAccountBillingKindRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,billingKind: freezed == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind?,
  ));
}
/// Create a copy of SetAccountBillingKindRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetAccountBillingKindRequest].
extension SetAccountBillingKindRequestPatterns on SetAccountBillingKindRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetAccountBillingKindRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetAccountBillingKindRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetAccountBillingKindRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  BillingKind? billingKind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.billingKind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String accountId,  BillingKind? billingKind)  $default,) {final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest():
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.billingKind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String accountId,  BillingKind? billingKind)?  $default,) {final _that = this;
switch (_that) {
case _SetAccountBillingKindRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.accountId,_that.billingKind);case _:
  return null;

}
}

}

/// @nodoc


class _SetAccountBillingKindRequest implements SetAccountBillingKindRequest {
  const _SetAccountBillingKindRequest({required this.operationId, required this.expectedRevision, required this.accountId, required this.billingKind});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String accountId;
@override final  BillingKind? billingKind;

/// Create a copy of SetAccountBillingKindRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetAccountBillingKindRequestCopyWith<_SetAccountBillingKindRequest> get copyWith => __$SetAccountBillingKindRequestCopyWithImpl<_SetAccountBillingKindRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetAccountBillingKindRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.billingKind, billingKind) || other.billingKind == billingKind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,accountId,billingKind);
}

@override
String toString() {
    return 'SetAccountBillingKindRequest(operationId: $operationId, expectedRevision: $expectedRevision, accountId: $accountId, billingKind: $billingKind)';
}


}

/// @nodoc
abstract mixin class _$SetAccountBillingKindRequestCopyWith<$Res> implements $SetAccountBillingKindRequestCopyWith<$Res> {
  factory _$SetAccountBillingKindRequestCopyWith(_SetAccountBillingKindRequest value, $Res Function(_SetAccountBillingKindRequest) _then) = __$SetAccountBillingKindRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String accountId, BillingKind? billingKind
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetAccountBillingKindRequestCopyWithImpl<$Res>
    implements _$SetAccountBillingKindRequestCopyWith<$Res> {
  __$SetAccountBillingKindRequestCopyWithImpl(this._self, this._then);

  final _SetAccountBillingKindRequest _self;
  final $Res Function(_SetAccountBillingKindRequest) _then;

/// Create a copy of SetAccountBillingKindRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? accountId = null,Object? billingKind = freezed,}) {
  return _then(_SetAccountBillingKindRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,billingKind: freezed == billingKind ? _self.billingKind : billingKind // ignore: cast_nullable_to_non_nullable
as BillingKind?,
  ));
}

/// Create a copy of SetAccountBillingKindRequest
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
mixin _$UpdateSettingsFieldRequest {

 OperationId get operationId; int get expectedRevision; SettingsFieldUpdate get update;
/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateSettingsFieldRequestCopyWith<UpdateSettingsFieldRequest> get copyWith => _$UpdateSettingsFieldRequestCopyWithImpl<UpdateSettingsFieldRequest>(this as UpdateSettingsFieldRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateSettingsFieldRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateSettingsFieldRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.update, _this.update) || other.update == _this.update));
}


@override
int get hashCode {
  final _this = this as UpdateSettingsFieldRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.update);
}



}

/// @nodoc
abstract mixin class $UpdateSettingsFieldRequestCopyWith<$Res>  {
  factory $UpdateSettingsFieldRequestCopyWith(UpdateSettingsFieldRequest value, $Res Function(UpdateSettingsFieldRequest) _then) = _$UpdateSettingsFieldRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, SettingsFieldUpdate update
});


$OperationIdCopyWith<$Res> get operationId;$SettingsFieldUpdateCopyWith<$Res> get update;

}
/// @nodoc
class _$UpdateSettingsFieldRequestCopyWithImpl<$Res>
    implements $UpdateSettingsFieldRequestCopyWith<$Res> {
  _$UpdateSettingsFieldRequestCopyWithImpl(this._self, this._then);

  final UpdateSettingsFieldRequest _self;
  final $Res Function(UpdateSettingsFieldRequest) _then;

/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? update = null,}) {
  return _then(UpdateSettingsFieldRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as SettingsFieldUpdate,
  ));
}
/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsFieldUpdateCopyWith<$Res> get update {

  return $SettingsFieldUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateSettingsFieldRequest].
extension UpdateSettingsFieldRequestPatterns on UpdateSettingsFieldRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateSettingsFieldRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateSettingsFieldRequest value)  $default,){
final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateSettingsFieldRequest value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  SettingsFieldUpdate update)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.update);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  SettingsFieldUpdate update)  $default,) {final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest():
return $default(_that.operationId,_that.expectedRevision,_that.update);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  SettingsFieldUpdate update)?  $default,) {final _that = this;
switch (_that) {
case _UpdateSettingsFieldRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.update);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateSettingsFieldRequest implements UpdateSettingsFieldRequest {
  const _UpdateSettingsFieldRequest({required this.operationId, required this.expectedRevision, required this.update});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  SettingsFieldUpdate update;

/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateSettingsFieldRequestCopyWith<_UpdateSettingsFieldRequest> get copyWith => __$UpdateSettingsFieldRequestCopyWithImpl<_UpdateSettingsFieldRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateSettingsFieldRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,update);
}



}

/// @nodoc
abstract mixin class _$UpdateSettingsFieldRequestCopyWith<$Res> implements $UpdateSettingsFieldRequestCopyWith<$Res> {
  factory _$UpdateSettingsFieldRequestCopyWith(_UpdateSettingsFieldRequest value, $Res Function(_UpdateSettingsFieldRequest) _then) = __$UpdateSettingsFieldRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, SettingsFieldUpdate update
});


@override $OperationIdCopyWith<$Res> get operationId;@override $SettingsFieldUpdateCopyWith<$Res> get update;

}
/// @nodoc
class __$UpdateSettingsFieldRequestCopyWithImpl<$Res>
    implements _$UpdateSettingsFieldRequestCopyWith<$Res> {
  __$UpdateSettingsFieldRequestCopyWithImpl(this._self, this._then);

  final _UpdateSettingsFieldRequest _self;
  final $Res Function(_UpdateSettingsFieldRequest) _then;

/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? update = null,}) {
  return _then(_UpdateSettingsFieldRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as SettingsFieldUpdate,
  ));
}

/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of UpdateSettingsFieldRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SettingsFieldUpdateCopyWith<$Res> get update {

  return $SettingsFieldUpdateCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc
mixin _$UpdatePermissionSettingsRequest {

 OperationId get operationId; int get expectedRevision; String get mode;
/// Create a copy of UpdatePermissionSettingsRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatePermissionSettingsRequestCopyWith<UpdatePermissionSettingsRequest> get copyWith => _$UpdatePermissionSettingsRequestCopyWithImpl<UpdatePermissionSettingsRequest>(this as UpdatePermissionSettingsRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatePermissionSettingsRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatePermissionSettingsRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision)&&(identical(other.mode, _this.mode) || other.mode == _this.mode));
}


@override
int get hashCode {
  final _this = this as UpdatePermissionSettingsRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision,_this.mode);
}

@override
String toString() {
  final _this = this as UpdatePermissionSettingsRequest;
  return 'UpdatePermissionSettingsRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision}, mode: ${_this.mode})';
}


}

/// @nodoc
abstract mixin class $UpdatePermissionSettingsRequestCopyWith<$Res>  {
  factory $UpdatePermissionSettingsRequestCopyWith(UpdatePermissionSettingsRequest value, $Res Function(UpdatePermissionSettingsRequest) _then) = _$UpdatePermissionSettingsRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision, String mode
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$UpdatePermissionSettingsRequestCopyWithImpl<$Res>
    implements $UpdatePermissionSettingsRequestCopyWith<$Res> {
  _$UpdatePermissionSettingsRequestCopyWithImpl(this._self, this._then);

  final UpdatePermissionSettingsRequest _self;
  final $Res Function(UpdatePermissionSettingsRequest) _then;

/// Create a copy of UpdatePermissionSettingsRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,Object? mode = null,}) {
  return _then(UpdatePermissionSettingsRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of UpdatePermissionSettingsRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdatePermissionSettingsRequest].
extension UpdatePermissionSettingsRequestPatterns on UpdatePermissionSettingsRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdatePermissionSettingsRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdatePermissionSettingsRequest value)  $default,){
final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdatePermissionSettingsRequest value)?  $default,){
final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String mode)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.mode);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision,  String mode)  $default,) {final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest():
return $default(_that.operationId,_that.expectedRevision,_that.mode);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision,  String mode)?  $default,) {final _that = this;
switch (_that) {
case _UpdatePermissionSettingsRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision,_that.mode);case _:
  return null;

}
}

}

/// @nodoc


class _UpdatePermissionSettingsRequest implements UpdatePermissionSettingsRequest {
  const _UpdatePermissionSettingsRequest({required this.operationId, required this.expectedRevision, required this.mode});


@override final  OperationId operationId;
@override final  int expectedRevision;
@override final  String mode;

/// Create a copy of UpdatePermissionSettingsRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdatePermissionSettingsRequestCopyWith<_UpdatePermissionSettingsRequest> get copyWith => __$UpdatePermissionSettingsRequestCopyWithImpl<_UpdatePermissionSettingsRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdatePermissionSettingsRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision)&&(identical(other.mode, mode) || other.mode == mode));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision,mode);
}

@override
String toString() {
    return 'UpdatePermissionSettingsRequest(operationId: $operationId, expectedRevision: $expectedRevision, mode: $mode)';
}


}

/// @nodoc
abstract mixin class _$UpdatePermissionSettingsRequestCopyWith<$Res> implements $UpdatePermissionSettingsRequestCopyWith<$Res> {
  factory _$UpdatePermissionSettingsRequestCopyWith(_UpdatePermissionSettingsRequest value, $Res Function(_UpdatePermissionSettingsRequest) _then) = __$UpdatePermissionSettingsRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision, String mode
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$UpdatePermissionSettingsRequestCopyWithImpl<$Res>
    implements _$UpdatePermissionSettingsRequestCopyWith<$Res> {
  __$UpdatePermissionSettingsRequestCopyWithImpl(this._self, this._then);

  final _UpdatePermissionSettingsRequest _self;
  final $Res Function(_UpdatePermissionSettingsRequest) _then;

/// Create a copy of UpdatePermissionSettingsRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,Object? mode = null,}) {
  return _then(_UpdatePermissionSettingsRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of UpdatePermissionSettingsRequest
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
mixin _$SaveProfileRequest {

 OperationId get operationId; int get expectedSettingsRevision; AgentProfileEdit get profile;
/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SaveProfileRequestCopyWith<SaveProfileRequest> get copyWith => _$SaveProfileRequestCopyWithImpl<SaveProfileRequest>(this as SaveProfileRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SaveProfileRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SaveProfileRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedSettingsRevision, _this.expectedSettingsRevision) || other.expectedSettingsRevision == _this.expectedSettingsRevision)&&(identical(other.profile, _this.profile) || other.profile == _this.profile));
}


@override
int get hashCode {
  final _this = this as SaveProfileRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedSettingsRevision,_this.profile);
}



}

/// @nodoc
abstract mixin class $SaveProfileRequestCopyWith<$Res>  {
  factory $SaveProfileRequestCopyWith(SaveProfileRequest value, $Res Function(SaveProfileRequest) _then) = _$SaveProfileRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedSettingsRevision, AgentProfileEdit profile
});


$OperationIdCopyWith<$Res> get operationId;$AgentProfileEditCopyWith<$Res> get profile;

}
/// @nodoc
class _$SaveProfileRequestCopyWithImpl<$Res>
    implements $SaveProfileRequestCopyWith<$Res> {
  _$SaveProfileRequestCopyWithImpl(this._self, this._then);

  final SaveProfileRequest _self;
  final $Res Function(SaveProfileRequest) _then;

/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedSettingsRevision = null,Object? profile = null,}) {
  return _then(SaveProfileRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedSettingsRevision: null == expectedSettingsRevision ? _self.expectedSettingsRevision : expectedSettingsRevision // ignore: cast_nullable_to_non_nullable
as int,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as AgentProfileEdit,
  ));
}
/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfileEditCopyWith<$Res> get profile {

  return $AgentProfileEditCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}


/// Adds pattern-matching-related methods to [SaveProfileRequest].
extension SaveProfileRequestPatterns on SaveProfileRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SaveProfileRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SaveProfileRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SaveProfileRequest value)  $default,){
final _that = this;
switch (_that) {
case _SaveProfileRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SaveProfileRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SaveProfileRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedSettingsRevision,  AgentProfileEdit profile)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SaveProfileRequest() when $default != null:
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profile);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedSettingsRevision,  AgentProfileEdit profile)  $default,) {final _that = this;
switch (_that) {
case _SaveProfileRequest():
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profile);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedSettingsRevision,  AgentProfileEdit profile)?  $default,) {final _that = this;
switch (_that) {
case _SaveProfileRequest() when $default != null:
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profile);case _:
  return null;

}
}

}

/// @nodoc


class _SaveProfileRequest implements SaveProfileRequest {
  const _SaveProfileRequest({required this.operationId, required this.expectedSettingsRevision, required this.profile});


@override final  OperationId operationId;
@override final  int expectedSettingsRevision;
@override final  AgentProfileEdit profile;

/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SaveProfileRequestCopyWith<_SaveProfileRequest> get copyWith => __$SaveProfileRequestCopyWithImpl<_SaveProfileRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SaveProfileRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedSettingsRevision, expectedSettingsRevision) || other.expectedSettingsRevision == expectedSettingsRevision)&&(identical(other.profile, profile) || other.profile == profile));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedSettingsRevision,profile);
}



}

/// @nodoc
abstract mixin class _$SaveProfileRequestCopyWith<$Res> implements $SaveProfileRequestCopyWith<$Res> {
  factory _$SaveProfileRequestCopyWith(_SaveProfileRequest value, $Res Function(_SaveProfileRequest) _then) = __$SaveProfileRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedSettingsRevision, AgentProfileEdit profile
});


@override $OperationIdCopyWith<$Res> get operationId;@override $AgentProfileEditCopyWith<$Res> get profile;

}
/// @nodoc
class __$SaveProfileRequestCopyWithImpl<$Res>
    implements _$SaveProfileRequestCopyWith<$Res> {
  __$SaveProfileRequestCopyWithImpl(this._self, this._then);

  final _SaveProfileRequest _self;
  final $Res Function(_SaveProfileRequest) _then;

/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedSettingsRevision = null,Object? profile = null,}) {
  return _then(_SaveProfileRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedSettingsRevision: null == expectedSettingsRevision ? _self.expectedSettingsRevision : expectedSettingsRevision // ignore: cast_nullable_to_non_nullable
as int,profile: null == profile ? _self.profile : profile // ignore: cast_nullable_to_non_nullable
as AgentProfileEdit,
  ));
}

/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of SaveProfileRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfileEditCopyWith<$Res> get profile {

  return $AgentProfileEditCopyWith<$Res>(_self.profile, (value) {
    return _then(_self.copyWith(profile: value));
  });
}
}

/// @nodoc
mixin _$SetSystemProfileEnabledRequest {

 OperationId get operationId; int get expectedSettingsRevision; String get profileId; bool get enabled;
/// Create a copy of SetSystemProfileEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SetSystemProfileEnabledRequestCopyWith<SetSystemProfileEnabledRequest> get copyWith => _$SetSystemProfileEnabledRequestCopyWithImpl<SetSystemProfileEnabledRequest>(this as SetSystemProfileEnabledRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SetSystemProfileEnabledRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SetSystemProfileEnabledRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedSettingsRevision, _this.expectedSettingsRevision) || other.expectedSettingsRevision == _this.expectedSettingsRevision)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled));
}


@override
int get hashCode {
  final _this = this as SetSystemProfileEnabledRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedSettingsRevision,_this.profileId,_this.enabled);
}

@override
String toString() {
  final _this = this as SetSystemProfileEnabledRequest;
  return 'SetSystemProfileEnabledRequest(operationId: ${_this.operationId}, expectedSettingsRevision: ${_this.expectedSettingsRevision}, profileId: ${_this.profileId}, enabled: ${_this.enabled})';
}


}

/// @nodoc
abstract mixin class $SetSystemProfileEnabledRequestCopyWith<$Res>  {
  factory $SetSystemProfileEnabledRequestCopyWith(SetSystemProfileEnabledRequest value, $Res Function(SetSystemProfileEnabledRequest) _then) = _$SetSystemProfileEnabledRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedSettingsRevision, String profileId, bool enabled
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SetSystemProfileEnabledRequestCopyWithImpl<$Res>
    implements $SetSystemProfileEnabledRequestCopyWith<$Res> {
  _$SetSystemProfileEnabledRequestCopyWithImpl(this._self, this._then);

  final SetSystemProfileEnabledRequest _self;
  final $Res Function(SetSystemProfileEnabledRequest) _then;

/// Create a copy of SetSystemProfileEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedSettingsRevision = null,Object? profileId = null,Object? enabled = null,}) {
  return _then(SetSystemProfileEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedSettingsRevision: null == expectedSettingsRevision ? _self.expectedSettingsRevision : expectedSettingsRevision // ignore: cast_nullable_to_non_nullable
as int,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SetSystemProfileEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [SetSystemProfileEnabledRequest].
extension SetSystemProfileEnabledRequestPatterns on SetSystemProfileEnabledRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SetSystemProfileEnabledRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SetSystemProfileEnabledRequest value)  $default,){
final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SetSystemProfileEnabledRequest value)?  $default,){
final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedSettingsRevision,  String profileId,  bool enabled)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest() when $default != null:
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profileId,_that.enabled);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedSettingsRevision,  String profileId,  bool enabled)  $default,) {final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest():
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profileId,_that.enabled);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedSettingsRevision,  String profileId,  bool enabled)?  $default,) {final _that = this;
switch (_that) {
case _SetSystemProfileEnabledRequest() when $default != null:
return $default(_that.operationId,_that.expectedSettingsRevision,_that.profileId,_that.enabled);case _:
  return null;

}
}

}

/// @nodoc


class _SetSystemProfileEnabledRequest implements SetSystemProfileEnabledRequest {
  const _SetSystemProfileEnabledRequest({required this.operationId, required this.expectedSettingsRevision, required this.profileId, required this.enabled});


@override final  OperationId operationId;
@override final  int expectedSettingsRevision;
@override final  String profileId;
@override final  bool enabled;

/// Create a copy of SetSystemProfileEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SetSystemProfileEnabledRequestCopyWith<_SetSystemProfileEnabledRequest> get copyWith => __$SetSystemProfileEnabledRequestCopyWithImpl<_SetSystemProfileEnabledRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SetSystemProfileEnabledRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedSettingsRevision, expectedSettingsRevision) || other.expectedSettingsRevision == expectedSettingsRevision)&&(identical(other.profileId, profileId) || other.profileId == profileId)&&(identical(other.enabled, enabled) || other.enabled == enabled));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedSettingsRevision,profileId,enabled);
}

@override
String toString() {
    return 'SetSystemProfileEnabledRequest(operationId: $operationId, expectedSettingsRevision: $expectedSettingsRevision, profileId: $profileId, enabled: $enabled)';
}


}

/// @nodoc
abstract mixin class _$SetSystemProfileEnabledRequestCopyWith<$Res> implements $SetSystemProfileEnabledRequestCopyWith<$Res> {
  factory _$SetSystemProfileEnabledRequestCopyWith(_SetSystemProfileEnabledRequest value, $Res Function(_SetSystemProfileEnabledRequest) _then) = __$SetSystemProfileEnabledRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedSettingsRevision, String profileId, bool enabled
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$SetSystemProfileEnabledRequestCopyWithImpl<$Res>
    implements _$SetSystemProfileEnabledRequestCopyWith<$Res> {
  __$SetSystemProfileEnabledRequestCopyWithImpl(this._self, this._then);

  final _SetSystemProfileEnabledRequest _self;
  final $Res Function(_SetSystemProfileEnabledRequest) _then;

/// Create a copy of SetSystemProfileEnabledRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedSettingsRevision = null,Object? profileId = null,Object? enabled = null,}) {
  return _then(_SetSystemProfileEnabledRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedSettingsRevision: null == expectedSettingsRevision ? _self.expectedSettingsRevision : expectedSettingsRevision // ignore: cast_nullable_to_non_nullable
as int,profileId: null == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SetSystemProfileEnabledRequest
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
mixin _$ConfigurationReloadRequest {

 OperationId get operationId; int get expectedRevision;
/// Create a copy of ConfigurationReloadRequest
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationReloadRequestCopyWith<ConfigurationReloadRequest> get copyWith => _$ConfigurationReloadRequestCopyWithImpl<ConfigurationReloadRequest>(this as ConfigurationReloadRequest, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationReloadRequest;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationReloadRequest&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId)&&(identical(other.expectedRevision, _this.expectedRevision) || other.expectedRevision == _this.expectedRevision));
}


@override
int get hashCode {
  final _this = this as ConfigurationReloadRequest;
  return Object.hash(runtimeType,_this.operationId,_this.expectedRevision);
}

@override
String toString() {
  final _this = this as ConfigurationReloadRequest;
  return 'ConfigurationReloadRequest(operationId: ${_this.operationId}, expectedRevision: ${_this.expectedRevision})';
}


}

/// @nodoc
abstract mixin class $ConfigurationReloadRequestCopyWith<$Res>  {
  factory $ConfigurationReloadRequestCopyWith(ConfigurationReloadRequest value, $Res Function(ConfigurationReloadRequest) _then) = _$ConfigurationReloadRequestCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, int expectedRevision
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$ConfigurationReloadRequestCopyWithImpl<$Res>
    implements $ConfigurationReloadRequestCopyWith<$Res> {
  _$ConfigurationReloadRequestCopyWithImpl(this._self, this._then);

  final ConfigurationReloadRequest _self;
  final $Res Function(ConfigurationReloadRequest) _then;

/// Create a copy of ConfigurationReloadRequest
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,Object? expectedRevision = null,}) {
  return _then(ConfigurationReloadRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of ConfigurationReloadRequest
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationReloadRequest].
extension ConfigurationReloadRequestPatterns on ConfigurationReloadRequest {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationReloadRequest value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationReloadRequest() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationReloadRequest value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReloadRequest():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationReloadRequest value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReloadRequest() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationReloadRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( OperationId operationId,  int expectedRevision)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReloadRequest():
return $default(_that.operationId,_that.expectedRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( OperationId operationId,  int expectedRevision)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReloadRequest() when $default != null:
return $default(_that.operationId,_that.expectedRevision);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationReloadRequest implements ConfigurationReloadRequest {
  const _ConfigurationReloadRequest({required this.operationId, required this.expectedRevision});


@override final  OperationId operationId;
@override final  int expectedRevision;

/// Create a copy of ConfigurationReloadRequest
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationReloadRequestCopyWith<_ConfigurationReloadRequest> get copyWith => __$ConfigurationReloadRequestCopyWithImpl<_ConfigurationReloadRequest>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationReloadRequest&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.expectedRevision, expectedRevision) || other.expectedRevision == expectedRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,expectedRevision);
}

@override
String toString() {
    return 'ConfigurationReloadRequest(operationId: $operationId, expectedRevision: $expectedRevision)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationReloadRequestCopyWith<$Res> implements $ConfigurationReloadRequestCopyWith<$Res> {
  factory _$ConfigurationReloadRequestCopyWith(_ConfigurationReloadRequest value, $Res Function(_ConfigurationReloadRequest) _then) = __$ConfigurationReloadRequestCopyWithImpl;
@override @useResult
$Res call({
 OperationId operationId, int expectedRevision
});


@override $OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class __$ConfigurationReloadRequestCopyWithImpl<$Res>
    implements _$ConfigurationReloadRequestCopyWith<$Res> {
  __$ConfigurationReloadRequestCopyWithImpl(this._self, this._then);

  final _ConfigurationReloadRequest _self;
  final $Res Function(_ConfigurationReloadRequest) _then;

/// Create a copy of ConfigurationReloadRequest
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? expectedRevision = null,}) {
  return _then(_ConfigurationReloadRequest(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,expectedRevision: null == expectedRevision ? _self.expectedRevision : expectedRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ConfigurationReloadRequest
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
mixin _$ConfigurationCommandReply {

 CommitReceipt get receipt; ConfigurationReadTarget get configuration; ModelCatalogReadTarget get models;
/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationCommandReplyCopyWith<ConfigurationCommandReply> get copyWith => _$ConfigurationCommandReplyCopyWithImpl<ConfigurationCommandReply>(this as ConfigurationCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationCommandReply&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.models, _this.models) || other.models == _this.models));
}


@override
int get hashCode {
  final _this = this as ConfigurationCommandReply;
  return Object.hash(runtimeType,_this.receipt,_this.configuration,_this.models);
}

@override
String toString() {
  final _this = this as ConfigurationCommandReply;
  return 'ConfigurationCommandReply(receipt: ${_this.receipt}, configuration: ${_this.configuration}, models: ${_this.models})';
}


}

/// @nodoc
abstract mixin class $ConfigurationCommandReplyCopyWith<$Res>  {
  factory $ConfigurationCommandReplyCopyWith(ConfigurationCommandReply value, $Res Function(ConfigurationCommandReply) _then) = _$ConfigurationCommandReplyCopyWithImpl;
@useResult
$Res call({
 CommitReceipt receipt, ConfigurationReadTarget configuration, ModelCatalogReadTarget models
});


$CommitReceiptCopyWith<$Res> get receipt;$ConfigurationReadTargetCopyWith<$Res> get configuration;$ModelCatalogReadTargetCopyWith<$Res> get models;

}
/// @nodoc
class _$ConfigurationCommandReplyCopyWithImpl<$Res>
    implements $ConfigurationCommandReplyCopyWith<$Res> {
  _$ConfigurationCommandReplyCopyWithImpl(this._self, this._then);

  final ConfigurationCommandReply _self;
  final $Res Function(ConfigurationCommandReply) _then;

/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? receipt = null,Object? configuration = null,Object? models = null,}) {
  return _then(ConfigurationCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,
  ));
}
/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationCommandReply].
extension ConfigurationCommandReplyPatterns on ConfigurationCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationCommandReply() when $default != null:
return $default(_that.receipt,_that.configuration,_that.models);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationCommandReply():
return $default(_that.receipt,_that.configuration,_that.models);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationCommandReply() when $default != null:
return $default(_that.receipt,_that.configuration,_that.models);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationCommandReply implements ConfigurationCommandReply {
  const _ConfigurationCommandReply({required this.receipt, required this.configuration, required this.models});


@override final  CommitReceipt receipt;
@override final  ConfigurationReadTarget configuration;
@override final  ModelCatalogReadTarget models;

/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationCommandReplyCopyWith<_ConfigurationCommandReply> get copyWith => __$ConfigurationCommandReplyCopyWithImpl<_ConfigurationCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationCommandReply&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.models, models) || other.models == models));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,configuration,models);
}

@override
String toString() {
    return 'ConfigurationCommandReply(receipt: $receipt, configuration: $configuration, models: $models)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationCommandReplyCopyWith<$Res> implements $ConfigurationCommandReplyCopyWith<$Res> {
  factory _$ConfigurationCommandReplyCopyWith(_ConfigurationCommandReply value, $Res Function(_ConfigurationCommandReply) _then) = __$ConfigurationCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, ConfigurationReadTarget configuration, ModelCatalogReadTarget models
});


@override $CommitReceiptCopyWith<$Res> get receipt;@override $ConfigurationReadTargetCopyWith<$Res> get configuration;@override $ModelCatalogReadTargetCopyWith<$Res> get models;

}
/// @nodoc
class __$ConfigurationCommandReplyCopyWithImpl<$Res>
    implements _$ConfigurationCommandReplyCopyWith<$Res> {
  __$ConfigurationCommandReplyCopyWithImpl(this._self, this._then);

  final _ConfigurationCommandReply _self;
  final $Res Function(_ConfigurationCommandReply) _then;

/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? configuration = null,Object? models = null,}) {
  return _then(_ConfigurationCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,
  ));
}

/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}
}

/// @nodoc
mixin _$ProfileCommandReply {

 CommitReceipt get receipt; ConfigurationReadTarget get configuration; ModelCatalogReadTarget get models; AgentProfilesReadTarget get profiles;
/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileCommandReplyCopyWith<ProfileCommandReply> get copyWith => _$ProfileCommandReplyCopyWithImpl<ProfileCommandReply>(this as ProfileCommandReply, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileCommandReply;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileCommandReply&&(identical(other.receipt, _this.receipt) || other.receipt == _this.receipt)&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.models, _this.models) || other.models == _this.models)&&(identical(other.profiles, _this.profiles) || other.profiles == _this.profiles));
}


@override
int get hashCode {
  final _this = this as ProfileCommandReply;
  return Object.hash(runtimeType,_this.receipt,_this.configuration,_this.models,_this.profiles);
}

@override
String toString() {
  final _this = this as ProfileCommandReply;
  return 'ProfileCommandReply(receipt: ${_this.receipt}, configuration: ${_this.configuration}, models: ${_this.models}, profiles: ${_this.profiles})';
}


}

/// @nodoc
abstract mixin class $ProfileCommandReplyCopyWith<$Res>  {
  factory $ProfileCommandReplyCopyWith(ProfileCommandReply value, $Res Function(ProfileCommandReply) _then) = _$ProfileCommandReplyCopyWithImpl;
@useResult
$Res call({
 CommitReceipt receipt, ConfigurationReadTarget configuration, ModelCatalogReadTarget models, AgentProfilesReadTarget profiles
});


$CommitReceiptCopyWith<$Res> get receipt;$ConfigurationReadTargetCopyWith<$Res> get configuration;$ModelCatalogReadTargetCopyWith<$Res> get models;$AgentProfilesReadTargetCopyWith<$Res> get profiles;

}
/// @nodoc
class _$ProfileCommandReplyCopyWithImpl<$Res>
    implements $ProfileCommandReplyCopyWith<$Res> {
  _$ProfileCommandReplyCopyWithImpl(this._self, this._then);

  final ProfileCommandReply _self;
  final $Res Function(ProfileCommandReply) _then;

/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? receipt = null,Object? configuration = null,Object? models = null,Object? profiles = null,}) {
  return _then(ProfileCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadTarget,
  ));
}
/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadTargetCopyWith<$Res> get profiles {

  return $AgentProfilesReadTargetCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProfileCommandReply].
extension ProfileCommandReplyPatterns on ProfileCommandReply {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileCommandReply value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileCommandReply() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileCommandReply value)  $default,){
final _that = this;
switch (_that) {
case _ProfileCommandReply():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileCommandReply value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileCommandReply() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileCommandReply() when $default != null:
return $default(_that.receipt,_that.configuration,_that.models,_that.profiles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)  $default,) {final _that = this;
switch (_that) {
case _ProfileCommandReply():
return $default(_that.receipt,_that.configuration,_that.models,_that.profiles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( CommitReceipt receipt,  ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)?  $default,) {final _that = this;
switch (_that) {
case _ProfileCommandReply() when $default != null:
return $default(_that.receipt,_that.configuration,_that.models,_that.profiles);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileCommandReply implements ProfileCommandReply {
  const _ProfileCommandReply({required this.receipt, required this.configuration, required this.models, required this.profiles});


@override final  CommitReceipt receipt;
@override final  ConfigurationReadTarget configuration;
@override final  ModelCatalogReadTarget models;
@override final  AgentProfilesReadTarget profiles;

/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileCommandReplyCopyWith<_ProfileCommandReply> get copyWith => __$ProfileCommandReplyCopyWithImpl<_ProfileCommandReply>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileCommandReply&&(identical(other.receipt, receipt) || other.receipt == receipt)&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.models, models) || other.models == models)&&(identical(other.profiles, profiles) || other.profiles == profiles));
}


@override
int get hashCode {
    return Object.hash(runtimeType,receipt,configuration,models,profiles);
}

@override
String toString() {
    return 'ProfileCommandReply(receipt: $receipt, configuration: $configuration, models: $models, profiles: $profiles)';
}


}

/// @nodoc
abstract mixin class _$ProfileCommandReplyCopyWith<$Res> implements $ProfileCommandReplyCopyWith<$Res> {
  factory _$ProfileCommandReplyCopyWith(_ProfileCommandReply value, $Res Function(_ProfileCommandReply) _then) = __$ProfileCommandReplyCopyWithImpl;
@override @useResult
$Res call({
 CommitReceipt receipt, ConfigurationReadTarget configuration, ModelCatalogReadTarget models, AgentProfilesReadTarget profiles
});


@override $CommitReceiptCopyWith<$Res> get receipt;@override $ConfigurationReadTargetCopyWith<$Res> get configuration;@override $ModelCatalogReadTargetCopyWith<$Res> get models;@override $AgentProfilesReadTargetCopyWith<$Res> get profiles;

}
/// @nodoc
class __$ProfileCommandReplyCopyWithImpl<$Res>
    implements _$ProfileCommandReplyCopyWith<$Res> {
  __$ProfileCommandReplyCopyWithImpl(this._self, this._then);

  final _ProfileCommandReply _self;
  final $Res Function(_ProfileCommandReply) _then;

/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? receipt = null,Object? configuration = null,Object? models = null,Object? profiles = null,}) {
  return _then(_ProfileCommandReply(
receipt: null == receipt ? _self.receipt : receipt // ignore: cast_nullable_to_non_nullable
as CommitReceipt,configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadTarget,
  ));
}

/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CommitReceiptCopyWith<$Res> get receipt {

  return $CommitReceiptCopyWith<$Res>(_self.receipt, (value) {
    return _then(_self.copyWith(receipt: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of ProfileCommandReply
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadTargetCopyWith<$Res> get profiles {

  return $AgentProfilesReadTargetCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}
}

/// @nodoc
mixin _$ConfigurationReloadResult {

 ConfigurationReadTarget get configuration; ModelCatalogReadTarget get models; AgentProfilesReadTarget get profiles;
/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ConfigurationReloadResultCopyWith<ConfigurationReloadResult> get copyWith => _$ConfigurationReloadResultCopyWithImpl<ConfigurationReloadResult>(this as ConfigurationReloadResult, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ConfigurationReloadResult;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ConfigurationReloadResult&&(identical(other.configuration, _this.configuration) || other.configuration == _this.configuration)&&(identical(other.models, _this.models) || other.models == _this.models)&&(identical(other.profiles, _this.profiles) || other.profiles == _this.profiles));
}


@override
int get hashCode {
  final _this = this as ConfigurationReloadResult;
  return Object.hash(runtimeType,_this.configuration,_this.models,_this.profiles);
}

@override
String toString() {
  final _this = this as ConfigurationReloadResult;
  return 'ConfigurationReloadResult(configuration: ${_this.configuration}, models: ${_this.models}, profiles: ${_this.profiles})';
}


}

/// @nodoc
abstract mixin class $ConfigurationReloadResultCopyWith<$Res>  {
  factory $ConfigurationReloadResultCopyWith(ConfigurationReloadResult value, $Res Function(ConfigurationReloadResult) _then) = _$ConfigurationReloadResultCopyWithImpl;
@useResult
$Res call({
 ConfigurationReadTarget configuration, ModelCatalogReadTarget models, AgentProfilesReadTarget profiles
});


$ConfigurationReadTargetCopyWith<$Res> get configuration;$ModelCatalogReadTargetCopyWith<$Res> get models;$AgentProfilesReadTargetCopyWith<$Res> get profiles;

}
/// @nodoc
class _$ConfigurationReloadResultCopyWithImpl<$Res>
    implements $ConfigurationReloadResultCopyWith<$Res> {
  _$ConfigurationReloadResultCopyWithImpl(this._self, this._then);

  final ConfigurationReloadResult _self;
  final $Res Function(ConfigurationReloadResult) _then;

/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configuration = null,Object? models = null,Object? profiles = null,}) {
  return _then(ConfigurationReloadResult(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadTarget,
  ));
}
/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadTargetCopyWith<$Res> get profiles {

  return $AgentProfilesReadTargetCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}
}


/// Adds pattern-matching-related methods to [ConfigurationReloadResult].
extension ConfigurationReloadResultPatterns on ConfigurationReloadResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ConfigurationReloadResult value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ConfigurationReloadResult() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ConfigurationReloadResult value)  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReloadResult():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ConfigurationReloadResult value)?  $default,){
final _that = this;
switch (_that) {
case _ConfigurationReloadResult() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ConfigurationReloadResult() when $default != null:
return $default(_that.configuration,_that.models,_that.profiles);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReloadResult():
return $default(_that.configuration,_that.models,_that.profiles);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ConfigurationReadTarget configuration,  ModelCatalogReadTarget models,  AgentProfilesReadTarget profiles)?  $default,) {final _that = this;
switch (_that) {
case _ConfigurationReloadResult() when $default != null:
return $default(_that.configuration,_that.models,_that.profiles);case _:
  return null;

}
}

}

/// @nodoc


class _ConfigurationReloadResult implements ConfigurationReloadResult {
  const _ConfigurationReloadResult({required this.configuration, required this.models, required this.profiles});


@override final  ConfigurationReadTarget configuration;
@override final  ModelCatalogReadTarget models;
@override final  AgentProfilesReadTarget profiles;

/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ConfigurationReloadResultCopyWith<_ConfigurationReloadResult> get copyWith => __$ConfigurationReloadResultCopyWithImpl<_ConfigurationReloadResult>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ConfigurationReloadResult&&(identical(other.configuration, configuration) || other.configuration == configuration)&&(identical(other.models, models) || other.models == models)&&(identical(other.profiles, profiles) || other.profiles == profiles));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configuration,models,profiles);
}

@override
String toString() {
    return 'ConfigurationReloadResult(configuration: $configuration, models: $models, profiles: $profiles)';
}


}

/// @nodoc
abstract mixin class _$ConfigurationReloadResultCopyWith<$Res> implements $ConfigurationReloadResultCopyWith<$Res> {
  factory _$ConfigurationReloadResultCopyWith(_ConfigurationReloadResult value, $Res Function(_ConfigurationReloadResult) _then) = __$ConfigurationReloadResultCopyWithImpl;
@override @useResult
$Res call({
 ConfigurationReadTarget configuration, ModelCatalogReadTarget models, AgentProfilesReadTarget profiles
});


@override $ConfigurationReadTargetCopyWith<$Res> get configuration;@override $ModelCatalogReadTargetCopyWith<$Res> get models;@override $AgentProfilesReadTargetCopyWith<$Res> get profiles;

}
/// @nodoc
class __$ConfigurationReloadResultCopyWithImpl<$Res>
    implements _$ConfigurationReloadResultCopyWith<$Res> {
  __$ConfigurationReloadResultCopyWithImpl(this._self, this._then);

  final _ConfigurationReloadResult _self;
  final $Res Function(_ConfigurationReloadResult) _then;

/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configuration = null,Object? models = null,Object? profiles = null,}) {
  return _then(_ConfigurationReloadResult(
configuration: null == configuration ? _self.configuration : configuration // ignore: cast_nullable_to_non_nullable
as ConfigurationReadTarget,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as ModelCatalogReadTarget,profiles: null == profiles ? _self.profiles : profiles // ignore: cast_nullable_to_non_nullable
as AgentProfilesReadTarget,
  ));
}

/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationReadTargetCopyWith<$Res> get configuration {

  return $ConfigurationReadTargetCopyWith<$Res>(_self.configuration, (value) {
    return _then(_self.copyWith(configuration: value));
  });
}/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelCatalogReadTargetCopyWith<$Res> get models {

  return $ModelCatalogReadTargetCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}/// Create a copy of ConfigurationReloadResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentProfilesReadTargetCopyWith<$Res> get profiles {

  return $AgentProfilesReadTargetCopyWith<$Res>(_self.profiles, (value) {
    return _then(_self.copyWith(profiles: value));
  });
}
}

// dart format on
