// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'account_presentations.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountDisplayKey {

 AccountKind get kind; String get id;
/// Create a copy of AccountDisplayKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<AccountDisplayKey> get copyWith => _$AccountDisplayKeyCopyWithImpl<AccountDisplayKey>(this as AccountDisplayKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountDisplayKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDisplayKey&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as AccountDisplayKey;
  return Object.hash(runtimeType,_this.kind,_this.id);
}

@override
String toString() {
  final _this = this as AccountDisplayKey;
  return 'AccountDisplayKey(kind: ${_this.kind}, id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $AccountDisplayKeyCopyWith<$Res>  {
  factory $AccountDisplayKeyCopyWith(AccountDisplayKey value, $Res Function(AccountDisplayKey) _then) = _$AccountDisplayKeyCopyWithImpl;
@useResult
$Res call({
 AccountKind kind, String id
});




}
/// @nodoc
class _$AccountDisplayKeyCopyWithImpl<$Res>
    implements $AccountDisplayKeyCopyWith<$Res> {
  _$AccountDisplayKeyCopyWithImpl(this._self, this._then);

  final AccountDisplayKey _self;
  final $Res Function(AccountDisplayKey) _then;

/// Create a copy of AccountDisplayKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? id = null,}) {
  return _then(AccountDisplayKey(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AccountKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountDisplayKey].
extension AccountDisplayKeyPatterns on AccountDisplayKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountDisplayKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountDisplayKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountDisplayKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountDisplayKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountDisplayKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountDisplayKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountKind kind,  String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountDisplayKey() when $default != null:
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountKind kind,  String id)  $default,) {final _that = this;
switch (_that) {
case _AccountDisplayKey():
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountKind kind,  String id)?  $default,) {final _that = this;
switch (_that) {
case _AccountDisplayKey() when $default != null:
return $default(_that.kind,_that.id);case _:
  return null;

}
}

}

/// @nodoc


class _AccountDisplayKey implements AccountDisplayKey {
  const _AccountDisplayKey({required this.kind, required this.id});


@override final  AccountKind kind;
@override final  String id;

/// Create a copy of AccountDisplayKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountDisplayKeyCopyWith<_AccountDisplayKey> get copyWith => __$AccountDisplayKeyCopyWithImpl<_AccountDisplayKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountDisplayKey&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,id);
}

@override
String toString() {
    return 'AccountDisplayKey(kind: $kind, id: $id)';
}


}

/// @nodoc
abstract mixin class _$AccountDisplayKeyCopyWith<$Res> implements $AccountDisplayKeyCopyWith<$Res> {
  factory _$AccountDisplayKeyCopyWith(_AccountDisplayKey value, $Res Function(_AccountDisplayKey) _then) = __$AccountDisplayKeyCopyWithImpl;
@override @useResult
$Res call({
 AccountKind kind, String id
});




}
/// @nodoc
class __$AccountDisplayKeyCopyWithImpl<$Res>
    implements _$AccountDisplayKeyCopyWith<$Res> {
  __$AccountDisplayKeyCopyWithImpl(this._self, this._then);

  final _AccountDisplayKey _self;
  final $Res Function(_AccountDisplayKey) _then;

/// Create a copy of AccountDisplayKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? id = null,}) {
  return _then(_AccountDisplayKey(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AccountKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountModelKey {

 AccountDisplayKey get account; String get modelId;
/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<AccountModelKey> get copyWith => _$AccountModelKeyCopyWithImpl<AccountModelKey>(this as AccountModelKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelKey&&(identical(other.account, _this.account) || other.account == _this.account)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as AccountModelKey;
  return Object.hash(runtimeType,_this.account,_this.modelId);
}

@override
String toString() {
  final _this = this as AccountModelKey;
  return 'AccountModelKey(account: ${_this.account}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $AccountModelKeyCopyWith<$Res>  {
  factory $AccountModelKeyCopyWith(AccountModelKey value, $Res Function(AccountModelKey) _then) = _$AccountModelKeyCopyWithImpl;
@useResult
$Res call({
 AccountDisplayKey account, String modelId
});


$AccountDisplayKeyCopyWith<$Res> get account;

}
/// @nodoc
class _$AccountModelKeyCopyWithImpl<$Res>
    implements $AccountModelKeyCopyWith<$Res> {
  _$AccountModelKeyCopyWithImpl(this._self, this._then);

  final AccountModelKey _self;
  final $Res Function(AccountModelKey) _then;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? account = null,Object? modelId = null,}) {
  return _then(AccountModelKey(
account: null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}
/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get account {

  return $AccountDisplayKeyCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelKey].
extension AccountModelKeyPatterns on AccountModelKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountDisplayKey account,  String modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
return $default(_that.account,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountDisplayKey account,  String modelId)  $default,) {final _that = this;
switch (_that) {
case _AccountModelKey():
return $default(_that.account,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountDisplayKey account,  String modelId)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelKey() when $default != null:
return $default(_that.account,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelKey implements AccountModelKey {
  const _AccountModelKey({required this.account, required this.modelId});


@override final  AccountDisplayKey account;
@override final  String modelId;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelKeyCopyWith<_AccountModelKey> get copyWith => __$AccountModelKeyCopyWithImpl<_AccountModelKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelKey&&(identical(other.account, account) || other.account == account)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,account,modelId);
}

@override
String toString() {
    return 'AccountModelKey(account: $account, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$AccountModelKeyCopyWith<$Res> implements $AccountModelKeyCopyWith<$Res> {
  factory _$AccountModelKeyCopyWith(_AccountModelKey value, $Res Function(_AccountModelKey) _then) = __$AccountModelKeyCopyWithImpl;
@override @useResult
$Res call({
 AccountDisplayKey account, String modelId
});


@override $AccountDisplayKeyCopyWith<$Res> get account;

}
/// @nodoc
class __$AccountModelKeyCopyWithImpl<$Res>
    implements _$AccountModelKeyCopyWith<$Res> {
  __$AccountModelKeyCopyWithImpl(this._self, this._then);

  final _AccountModelKey _self;
  final $Res Function(_AccountModelKey) _then;

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? account = null,Object? modelId = null,}) {
  return _then(_AccountModelKey(
account: null == account ? _self.account : account // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of AccountModelKey
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get account {

  return $AccountDisplayKeyCopyWith<$Res>(_self.account, (value) {
    return _then(_self.copyWith(account: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplateKey {

 AccountKind get kind; String get id;
/// Create a copy of AccountTemplateKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<AccountTemplateKey> get copyWith => _$AccountTemplateKeyCopyWithImpl<AccountTemplateKey>(this as AccountTemplateKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplateKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplateKey&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as AccountTemplateKey;
  return Object.hash(runtimeType,_this.kind,_this.id);
}

@override
String toString() {
  final _this = this as AccountTemplateKey;
  return 'AccountTemplateKey(kind: ${_this.kind}, id: ${_this.id})';
}


}

/// @nodoc
abstract mixin class $AccountTemplateKeyCopyWith<$Res>  {
  factory $AccountTemplateKeyCopyWith(AccountTemplateKey value, $Res Function(AccountTemplateKey) _then) = _$AccountTemplateKeyCopyWithImpl;
@useResult
$Res call({
 AccountKind kind, String id
});




}
/// @nodoc
class _$AccountTemplateKeyCopyWithImpl<$Res>
    implements $AccountTemplateKeyCopyWith<$Res> {
  _$AccountTemplateKeyCopyWithImpl(this._self, this._then);

  final AccountTemplateKey _self;
  final $Res Function(AccountTemplateKey) _then;

/// Create a copy of AccountTemplateKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? id = null,}) {
  return _then(AccountTemplateKey(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AccountKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountTemplateKey].
extension AccountTemplateKeyPatterns on AccountTemplateKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplateKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplateKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplateKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplateKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplateKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplateKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountKind kind,  String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplateKey() when $default != null:
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountKind kind,  String id)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplateKey():
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountKind kind,  String id)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplateKey() when $default != null:
return $default(_that.kind,_that.id);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplateKey implements AccountTemplateKey {
  const _AccountTemplateKey({required this.kind, required this.id});


@override final  AccountKind kind;
@override final  String id;

/// Create a copy of AccountTemplateKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplateKeyCopyWith<_AccountTemplateKey> get copyWith => __$AccountTemplateKeyCopyWithImpl<_AccountTemplateKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplateKey&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,id);
}

@override
String toString() {
    return 'AccountTemplateKey(kind: $kind, id: $id)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplateKeyCopyWith<$Res> implements $AccountTemplateKeyCopyWith<$Res> {
  factory _$AccountTemplateKeyCopyWith(_AccountTemplateKey value, $Res Function(_AccountTemplateKey) _then) = __$AccountTemplateKeyCopyWithImpl;
@override @useResult
$Res call({
 AccountKind kind, String id
});




}
/// @nodoc
class __$AccountTemplateKeyCopyWithImpl<$Res>
    implements _$AccountTemplateKeyCopyWith<$Res> {
  __$AccountTemplateKeyCopyWithImpl(this._self, this._then);

  final _AccountTemplateKey _self;
  final $Res Function(_AccountTemplateKey) _then;

/// Create a copy of AccountTemplateKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? id = null,}) {
  return _then(_AccountTemplateKey(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AccountKind,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountTemplateContent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplateContent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountTemplateContent()';
}


}

/// @nodoc
class $AccountTemplateContentCopyWith<$Res>  {
$AccountTemplateContentCopyWith(AccountTemplateContent _, $Res Function(AccountTemplateContent) __);
}


/// Adds pattern-matching-related methods to [AccountTemplateContent].
extension AccountTemplateContentPatterns on AccountTemplateContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeAccountTemplateContent value)?  native,TResult Function( AcpAccountTemplateContent value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeAccountTemplateContent() when native != null:
return native(_that);case AcpAccountTemplateContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeAccountTemplateContent value)  native,required TResult Function( AcpAccountTemplateContent value)  acp,}){
final _that = this;
switch (_that) {
case NativeAccountTemplateContent():
return native(_that);case AcpAccountTemplateContent():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeAccountTemplateContent value)?  native,TResult? Function( AcpAccountTemplateContent value)?  acp,}){
final _that = this;
switch (_that) {
case NativeAccountTemplateContent() when native != null:
return native(_that);case AcpAccountTemplateContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AccountBilling defaultBilling,  String protocolLabel,  String defaultEndpoint,  bool supportsModelDiscovery,  bool? supportsUsageQuery)?  native,TResult Function()?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeAccountTemplateContent() when native != null:
return native(_that.defaultBilling,_that.protocolLabel,_that.defaultEndpoint,_that.supportsModelDiscovery,_that.supportsUsageQuery);case AcpAccountTemplateContent() when acp != null:
return acp();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AccountBilling defaultBilling,  String protocolLabel,  String defaultEndpoint,  bool supportsModelDiscovery,  bool? supportsUsageQuery)  native,required TResult Function()  acp,}) {final _that = this;
switch (_that) {
case NativeAccountTemplateContent():
return native(_that.defaultBilling,_that.protocolLabel,_that.defaultEndpoint,_that.supportsModelDiscovery,_that.supportsUsageQuery);case AcpAccountTemplateContent():
return acp();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AccountBilling defaultBilling,  String protocolLabel,  String defaultEndpoint,  bool supportsModelDiscovery,  bool? supportsUsageQuery)?  native,TResult? Function()?  acp,}) {final _that = this;
switch (_that) {
case NativeAccountTemplateContent() when native != null:
return native(_that.defaultBilling,_that.protocolLabel,_that.defaultEndpoint,_that.supportsModelDiscovery,_that.supportsUsageQuery);case AcpAccountTemplateContent() when acp != null:
return acp();case _:
  return null;

}
}

}

/// @nodoc


class NativeAccountTemplateContent implements AccountTemplateContent {
  const NativeAccountTemplateContent({required this.defaultBilling, required this.protocolLabel, required this.defaultEndpoint, required this.supportsModelDiscovery, required this.supportsUsageQuery});


 final  AccountBilling defaultBilling;
 final  String protocolLabel;
 final  String defaultEndpoint;
 final  bool supportsModelDiscovery;
 final  bool? supportsUsageQuery;

/// Create a copy of AccountTemplateContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountTemplateContentCopyWith<NativeAccountTemplateContent> get copyWith => _$NativeAccountTemplateContentCopyWithImpl<NativeAccountTemplateContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountTemplateContent&&(identical(other.defaultBilling, defaultBilling) || other.defaultBilling == defaultBilling)&&(identical(other.protocolLabel, protocolLabel) || other.protocolLabel == protocolLabel)&&(identical(other.defaultEndpoint, defaultEndpoint) || other.defaultEndpoint == defaultEndpoint)&&(identical(other.supportsModelDiscovery, supportsModelDiscovery) || other.supportsModelDiscovery == supportsModelDiscovery)&&(identical(other.supportsUsageQuery, supportsUsageQuery) || other.supportsUsageQuery == supportsUsageQuery));
}


@override
int get hashCode {
    return Object.hash(runtimeType,defaultBilling,protocolLabel,defaultEndpoint,supportsModelDiscovery,supportsUsageQuery);
}

@override
String toString() {
    return 'AccountTemplateContent.native(defaultBilling: $defaultBilling, protocolLabel: $protocolLabel, defaultEndpoint: $defaultEndpoint, supportsModelDiscovery: $supportsModelDiscovery, supportsUsageQuery: $supportsUsageQuery)';
}


}

/// @nodoc
abstract mixin class $NativeAccountTemplateContentCopyWith<$Res> implements $AccountTemplateContentCopyWith<$Res> {
  factory $NativeAccountTemplateContentCopyWith(NativeAccountTemplateContent value, $Res Function(NativeAccountTemplateContent) _then) = _$NativeAccountTemplateContentCopyWithImpl;
@useResult
$Res call({
 AccountBilling defaultBilling, String protocolLabel, String defaultEndpoint, bool supportsModelDiscovery, bool? supportsUsageQuery
});




}
/// @nodoc
class _$NativeAccountTemplateContentCopyWithImpl<$Res>
    implements $NativeAccountTemplateContentCopyWith<$Res> {
  _$NativeAccountTemplateContentCopyWithImpl(this._self, this._then);

  final NativeAccountTemplateContent _self;
  final $Res Function(NativeAccountTemplateContent) _then;

/// Create a copy of AccountTemplateContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? defaultBilling = null,Object? protocolLabel = null,Object? defaultEndpoint = null,Object? supportsModelDiscovery = null,Object? supportsUsageQuery = freezed,}) {
  return _then(NativeAccountTemplateContent(
defaultBilling: null == defaultBilling ? _self.defaultBilling : defaultBilling // ignore: cast_nullable_to_non_nullable
as AccountBilling,protocolLabel: null == protocolLabel ? _self.protocolLabel : protocolLabel // ignore: cast_nullable_to_non_nullable
as String,defaultEndpoint: null == defaultEndpoint ? _self.defaultEndpoint : defaultEndpoint // ignore: cast_nullable_to_non_nullable
as String,supportsModelDiscovery: null == supportsModelDiscovery ? _self.supportsModelDiscovery : supportsModelDiscovery // ignore: cast_nullable_to_non_nullable
as bool,supportsUsageQuery: freezed == supportsUsageQuery ? _self.supportsUsageQuery : supportsUsageQuery // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}


}

/// @nodoc


class AcpAccountTemplateContent implements AccountTemplateContent {
  const AcpAccountTemplateContent();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountTemplateContent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountTemplateContent.acp()';
}


}




/// @nodoc
mixin _$AccountTemplatePresentation {

 AccountTemplateKey get key; String get name; AccountTemplateContent get content; String? get iconKey; String? get description;
/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatePresentationCopyWith<AccountTemplatePresentation> get copyWith => _$AccountTemplatePresentationCopyWithImpl<AccountTemplatePresentation>(this as AccountTemplatePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatePresentation&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.description, _this.description) || other.description == _this.description));
}


@override
int get hashCode {
  final _this = this as AccountTemplatePresentation;
  return Object.hash(runtimeType,_this.key,_this.name,_this.content,_this.iconKey,_this.description);
}

@override
String toString() {
  final _this = this as AccountTemplatePresentation;
  return 'AccountTemplatePresentation(key: ${_this.key}, name: ${_this.name}, content: ${_this.content}, iconKey: ${_this.iconKey}, description: ${_this.description})';
}


}

/// @nodoc
abstract mixin class $AccountTemplatePresentationCopyWith<$Res>  {
  factory $AccountTemplatePresentationCopyWith(AccountTemplatePresentation value, $Res Function(AccountTemplatePresentation) _then) = _$AccountTemplatePresentationCopyWithImpl;
@useResult
$Res call({
 AccountTemplateKey key, String name, AccountTemplateContent content, String? iconKey, String? description
});


$AccountTemplateKeyCopyWith<$Res> get key;$AccountTemplateContentCopyWith<$Res> get content;

}
/// @nodoc
class _$AccountTemplatePresentationCopyWithImpl<$Res>
    implements $AccountTemplatePresentationCopyWith<$Res> {
  _$AccountTemplatePresentationCopyWithImpl(this._self, this._then);

  final AccountTemplatePresentation _self;
  final $Res Function(AccountTemplatePresentation) _then;

/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? description = freezed,}) {
  return _then(AccountTemplatePresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountTemplateContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res> get key {

  return $AccountTemplateKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateContentCopyWith<$Res> get content {

  return $AccountTemplateContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplatePresentation].
extension AccountTemplatePresentationPatterns on AccountTemplatePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountTemplateKey key,  String name,  AccountTemplateContent content,  String? iconKey,  String? description)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplatePresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountTemplateKey key,  String name,  AccountTemplateContent content,  String? iconKey,  String? description)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatePresentation():
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.description);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountTemplateKey key,  String name,  AccountTemplateContent content,  String? iconKey,  String? description)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatePresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.description);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatePresentation implements AccountTemplatePresentation {
  const _AccountTemplatePresentation({required this.key, required this.name, required this.content, this.iconKey, this.description});


@override final  AccountTemplateKey key;
@override final  String name;
@override final  AccountTemplateContent content;
@override final  String? iconKey;
@override final  String? description;

/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatePresentationCopyWith<_AccountTemplatePresentation> get copyWith => __$AccountTemplatePresentationCopyWithImpl<_AccountTemplatePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatePresentation&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.content, content) || other.content == content)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,name,content,iconKey,description);
}

@override
String toString() {
    return 'AccountTemplatePresentation(key: $key, name: $name, content: $content, iconKey: $iconKey, description: $description)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplatePresentationCopyWith<$Res> implements $AccountTemplatePresentationCopyWith<$Res> {
  factory _$AccountTemplatePresentationCopyWith(_AccountTemplatePresentation value, $Res Function(_AccountTemplatePresentation) _then) = __$AccountTemplatePresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountTemplateKey key, String name, AccountTemplateContent content, String? iconKey, String? description
});


@override $AccountTemplateKeyCopyWith<$Res> get key;@override $AccountTemplateContentCopyWith<$Res> get content;

}
/// @nodoc
class __$AccountTemplatePresentationCopyWithImpl<$Res>
    implements _$AccountTemplatePresentationCopyWith<$Res> {
  __$AccountTemplatePresentationCopyWithImpl(this._self, this._then);

  final _AccountTemplatePresentation _self;
  final $Res Function(_AccountTemplatePresentation) _then;

/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? description = freezed,}) {
  return _then(_AccountTemplatePresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountTemplateContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res> get key {

  return $AccountTemplateKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountTemplatePresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateContentCopyWith<$Res> get content {

  return $AccountTemplateContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}

/// @nodoc
mixin _$AccountCurrencyBalance {

 String get currency; String? get total; String? get granted; String? get toppedUp;
/// Create a copy of AccountCurrencyBalance
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCurrencyBalanceCopyWith<AccountCurrencyBalance> get copyWith => _$AccountCurrencyBalanceCopyWithImpl<AccountCurrencyBalance>(this as AccountCurrencyBalance, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountCurrencyBalance;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountCurrencyBalance&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.granted, _this.granted) || other.granted == _this.granted)&&(identical(other.toppedUp, _this.toppedUp) || other.toppedUp == _this.toppedUp));
}


@override
int get hashCode {
  final _this = this as AccountCurrencyBalance;
  return Object.hash(runtimeType,_this.currency,_this.total,_this.granted,_this.toppedUp);
}

@override
String toString() {
  final _this = this as AccountCurrencyBalance;
  return 'AccountCurrencyBalance(currency: ${_this.currency}, total: ${_this.total}, granted: ${_this.granted}, toppedUp: ${_this.toppedUp})';
}


}

/// @nodoc
abstract mixin class $AccountCurrencyBalanceCopyWith<$Res>  {
  factory $AccountCurrencyBalanceCopyWith(AccountCurrencyBalance value, $Res Function(AccountCurrencyBalance) _then) = _$AccountCurrencyBalanceCopyWithImpl;
@useResult
$Res call({
 String currency, String? total, String? granted, String? toppedUp
});




}
/// @nodoc
class _$AccountCurrencyBalanceCopyWithImpl<$Res>
    implements $AccountCurrencyBalanceCopyWith<$Res> {
  _$AccountCurrencyBalanceCopyWithImpl(this._self, this._then);

  final AccountCurrencyBalance _self;
  final $Res Function(AccountCurrencyBalance) _then;

/// Create a copy of AccountCurrencyBalance
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? total = freezed,Object? granted = freezed,Object? toppedUp = freezed,}) {
  return _then(AccountCurrencyBalance(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as String?,granted: freezed == granted ? _self.granted : granted // ignore: cast_nullable_to_non_nullable
as String?,toppedUp: freezed == toppedUp ? _self.toppedUp : toppedUp // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountCurrencyBalance].
extension AccountCurrencyBalancePatterns on AccountCurrencyBalance {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountCurrencyBalance value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountCurrencyBalance() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountCurrencyBalance value)  $default,){
final _that = this;
switch (_that) {
case _AccountCurrencyBalance():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountCurrencyBalance value)?  $default,){
final _that = this;
switch (_that) {
case _AccountCurrencyBalance() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String currency,  String? total,  String? granted,  String? toppedUp)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountCurrencyBalance() when $default != null:
return $default(_that.currency,_that.total,_that.granted,_that.toppedUp);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String currency,  String? total,  String? granted,  String? toppedUp)  $default,) {final _that = this;
switch (_that) {
case _AccountCurrencyBalance():
return $default(_that.currency,_that.total,_that.granted,_that.toppedUp);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String currency,  String? total,  String? granted,  String? toppedUp)?  $default,) {final _that = this;
switch (_that) {
case _AccountCurrencyBalance() when $default != null:
return $default(_that.currency,_that.total,_that.granted,_that.toppedUp);case _:
  return null;

}
}

}

/// @nodoc


class _AccountCurrencyBalance implements AccountCurrencyBalance {
  const _AccountCurrencyBalance({required this.currency, this.total, this.granted, this.toppedUp});


@override final  String currency;
@override final  String? total;
@override final  String? granted;
@override final  String? toppedUp;

/// Create a copy of AccountCurrencyBalance
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCurrencyBalanceCopyWith<_AccountCurrencyBalance> get copyWith => __$AccountCurrencyBalanceCopyWithImpl<_AccountCurrencyBalance>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountCurrencyBalance&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.total, total) || other.total == total)&&(identical(other.granted, granted) || other.granted == granted)&&(identical(other.toppedUp, toppedUp) || other.toppedUp == toppedUp));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,total,granted,toppedUp);
}

@override
String toString() {
    return 'AccountCurrencyBalance(currency: $currency, total: $total, granted: $granted, toppedUp: $toppedUp)';
}


}

/// @nodoc
abstract mixin class _$AccountCurrencyBalanceCopyWith<$Res> implements $AccountCurrencyBalanceCopyWith<$Res> {
  factory _$AccountCurrencyBalanceCopyWith(_AccountCurrencyBalance value, $Res Function(_AccountCurrencyBalance) _then) = __$AccountCurrencyBalanceCopyWithImpl;
@override @useResult
$Res call({
 String currency, String? total, String? granted, String? toppedUp
});




}
/// @nodoc
class __$AccountCurrencyBalanceCopyWithImpl<$Res>
    implements _$AccountCurrencyBalanceCopyWith<$Res> {
  __$AccountCurrencyBalanceCopyWithImpl(this._self, this._then);

  final _AccountCurrencyBalance _self;
  final $Res Function(_AccountCurrencyBalance) _then;

/// Create a copy of AccountCurrencyBalance
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? total = freezed,Object? granted = freezed,Object? toppedUp = freezed,}) {
  return _then(_AccountCurrencyBalance(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as String?,granted: freezed == granted ? _self.granted : granted // ignore: cast_nullable_to_non_nullable
as String?,toppedUp: freezed == toppedUp ? _self.toppedUp : toppedUp // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountQuotaPresentation {

 String get label; String get remaining; double? get remainingFraction; String? get resetLabel; bool get low;
/// Create a copy of AccountQuotaPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountQuotaPresentationCopyWith<AccountQuotaPresentation> get copyWith => _$AccountQuotaPresentationCopyWithImpl<AccountQuotaPresentation>(this as AccountQuotaPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountQuotaPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountQuotaPresentation&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.remaining, _this.remaining) || other.remaining == _this.remaining)&&(identical(other.remainingFraction, _this.remainingFraction) || other.remainingFraction == _this.remainingFraction)&&(identical(other.resetLabel, _this.resetLabel) || other.resetLabel == _this.resetLabel)&&(identical(other.low, _this.low) || other.low == _this.low));
}


@override
int get hashCode {
  final _this = this as AccountQuotaPresentation;
  return Object.hash(runtimeType,_this.label,_this.remaining,_this.remainingFraction,_this.resetLabel,_this.low);
}

@override
String toString() {
  final _this = this as AccountQuotaPresentation;
  return 'AccountQuotaPresentation(label: ${_this.label}, remaining: ${_this.remaining}, remainingFraction: ${_this.remainingFraction}, resetLabel: ${_this.resetLabel}, low: ${_this.low})';
}


}

/// @nodoc
abstract mixin class $AccountQuotaPresentationCopyWith<$Res>  {
  factory $AccountQuotaPresentationCopyWith(AccountQuotaPresentation value, $Res Function(AccountQuotaPresentation) _then) = _$AccountQuotaPresentationCopyWithImpl;
@useResult
$Res call({
 String label, String remaining, double? remainingFraction, String? resetLabel, bool low
});




}
/// @nodoc
class _$AccountQuotaPresentationCopyWithImpl<$Res>
    implements $AccountQuotaPresentationCopyWith<$Res> {
  _$AccountQuotaPresentationCopyWithImpl(this._self, this._then);

  final AccountQuotaPresentation _self;
  final $Res Function(AccountQuotaPresentation) _then;

/// Create a copy of AccountQuotaPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? remaining = null,Object? remainingFraction = freezed,Object? resetLabel = freezed,Object? low = null,}) {
  return _then(AccountQuotaPresentation(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,remaining: null == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as String,remainingFraction: freezed == remainingFraction ? _self.remainingFraction : remainingFraction // ignore: cast_nullable_to_non_nullable
as double?,resetLabel: freezed == resetLabel ? _self.resetLabel : resetLabel // ignore: cast_nullable_to_non_nullable
as String?,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountQuotaPresentation].
extension AccountQuotaPresentationPatterns on AccountQuotaPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountQuotaPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountQuotaPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountQuotaPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountQuotaPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountQuotaPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountQuotaPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  String remaining,  double? remainingFraction,  String? resetLabel,  bool low)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountQuotaPresentation() when $default != null:
return $default(_that.label,_that.remaining,_that.remainingFraction,_that.resetLabel,_that.low);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  String remaining,  double? remainingFraction,  String? resetLabel,  bool low)  $default,) {final _that = this;
switch (_that) {
case _AccountQuotaPresentation():
return $default(_that.label,_that.remaining,_that.remainingFraction,_that.resetLabel,_that.low);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  String remaining,  double? remainingFraction,  String? resetLabel,  bool low)?  $default,) {final _that = this;
switch (_that) {
case _AccountQuotaPresentation() when $default != null:
return $default(_that.label,_that.remaining,_that.remainingFraction,_that.resetLabel,_that.low);case _:
  return null;

}
}

}

/// @nodoc


class _AccountQuotaPresentation implements AccountQuotaPresentation {
  const _AccountQuotaPresentation({required this.label, required this.remaining, this.remainingFraction, this.resetLabel, this.low = false});


@override final  String label;
@override final  String remaining;
@override final  double? remainingFraction;
@override final  String? resetLabel;
@override@JsonKey() final  bool low;

/// Create a copy of AccountQuotaPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountQuotaPresentationCopyWith<_AccountQuotaPresentation> get copyWith => __$AccountQuotaPresentationCopyWithImpl<_AccountQuotaPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountQuotaPresentation&&(identical(other.label, label) || other.label == label)&&(identical(other.remaining, remaining) || other.remaining == remaining)&&(identical(other.remainingFraction, remainingFraction) || other.remainingFraction == remainingFraction)&&(identical(other.resetLabel, resetLabel) || other.resetLabel == resetLabel)&&(identical(other.low, low) || other.low == low));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,remaining,remainingFraction,resetLabel,low);
}

@override
String toString() {
    return 'AccountQuotaPresentation(label: $label, remaining: $remaining, remainingFraction: $remainingFraction, resetLabel: $resetLabel, low: $low)';
}


}

/// @nodoc
abstract mixin class _$AccountQuotaPresentationCopyWith<$Res> implements $AccountQuotaPresentationCopyWith<$Res> {
  factory _$AccountQuotaPresentationCopyWith(_AccountQuotaPresentation value, $Res Function(_AccountQuotaPresentation) _then) = __$AccountQuotaPresentationCopyWithImpl;
@override @useResult
$Res call({
 String label, String remaining, double? remainingFraction, String? resetLabel, bool low
});




}
/// @nodoc
class __$AccountQuotaPresentationCopyWithImpl<$Res>
    implements _$AccountQuotaPresentationCopyWith<$Res> {
  __$AccountQuotaPresentationCopyWithImpl(this._self, this._then);

  final _AccountQuotaPresentation _self;
  final $Res Function(_AccountQuotaPresentation) _then;

/// Create a copy of AccountQuotaPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? remaining = null,Object? remainingFraction = freezed,Object? resetLabel = freezed,Object? low = null,}) {
  return _then(_AccountQuotaPresentation(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,remaining: null == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as String,remainingFraction: freezed == remainingFraction ? _self.remainingFraction : remainingFraction // ignore: cast_nullable_to_non_nullable
as double?,resetLabel: freezed == resetLabel ? _self.resetLabel : resetLabel // ignore: cast_nullable_to_non_nullable
as String?,low: null == low ? _self.low : low // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AccountUsagePresentation {

 AccountQueryPhase get phase; AccountBalanceHealth get balanceHealth; List<AccountCurrencyBalance> get balances; List<AccountQuotaPresentation> get quotas; String? get updatedLabel; String? get error;/// The owner confirms that retained values belong to a successful query.
 bool get hasLastGood; bool get canRefresh; bool get canRetry;
/// Create a copy of AccountUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsagePresentationCopyWith<AccountUsagePresentation> get copyWith => _$AccountUsagePresentationCopyWithImpl<AccountUsagePresentation>(this as AccountUsagePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsagePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsagePresentation&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.balanceHealth, _this.balanceHealth) || other.balanceHealth == _this.balanceHealth)&&const DeepCollectionEquality().equals(other.balances, _this.balances)&&const DeepCollectionEquality().equals(other.quotas, _this.quotas)&&(identical(other.updatedLabel, _this.updatedLabel) || other.updatedLabel == _this.updatedLabel)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.hasLastGood, _this.hasLastGood) || other.hasLastGood == _this.hasLastGood)&&(identical(other.canRefresh, _this.canRefresh) || other.canRefresh == _this.canRefresh)&&(identical(other.canRetry, _this.canRetry) || other.canRetry == _this.canRetry));
}


@override
int get hashCode {
  final _this = this as AccountUsagePresentation;
  return Object.hash(runtimeType,_this.phase,_this.balanceHealth,const DeepCollectionEquality().hash(_this.balances),const DeepCollectionEquality().hash(_this.quotas),_this.updatedLabel,_this.error,_this.hasLastGood,_this.canRefresh,_this.canRetry);
}

@override
String toString() {
  final _this = this as AccountUsagePresentation;
  return 'AccountUsagePresentation(phase: ${_this.phase}, balanceHealth: ${_this.balanceHealth}, balances: ${_this.balances}, quotas: ${_this.quotas}, updatedLabel: ${_this.updatedLabel}, error: ${_this.error}, hasLastGood: ${_this.hasLastGood}, canRefresh: ${_this.canRefresh}, canRetry: ${_this.canRetry})';
}


}

/// @nodoc
abstract mixin class $AccountUsagePresentationCopyWith<$Res>  {
  factory $AccountUsagePresentationCopyWith(AccountUsagePresentation value, $Res Function(AccountUsagePresentation) _then) = _$AccountUsagePresentationCopyWithImpl;
@useResult
$Res call({
 AccountQueryPhase phase, AccountBalanceHealth balanceHealth, List<AccountCurrencyBalance> balances, List<AccountQuotaPresentation> quotas, String? updatedLabel, String? error, bool hasLastGood, bool canRefresh, bool canRetry
});




}
/// @nodoc
class _$AccountUsagePresentationCopyWithImpl<$Res>
    implements $AccountUsagePresentationCopyWith<$Res> {
  _$AccountUsagePresentationCopyWithImpl(this._self, this._then);

  final AccountUsagePresentation _self;
  final $Res Function(AccountUsagePresentation) _then;

/// Create a copy of AccountUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? balanceHealth = null,Object? balances = null,Object? quotas = null,Object? updatedLabel = freezed,Object? error = freezed,Object? hasLastGood = null,Object? canRefresh = null,Object? canRetry = null,}) {
  return _then(AccountUsagePresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountQueryPhase,balanceHealth: null == balanceHealth ? _self.balanceHealth : balanceHealth // ignore: cast_nullable_to_non_nullable
as AccountBalanceHealth,balances: null == balances ? _self.balances : balances // ignore: cast_nullable_to_non_nullable
as List<AccountCurrencyBalance>,quotas: null == quotas ? _self.quotas : quotas // ignore: cast_nullable_to_non_nullable
as List<AccountQuotaPresentation>,updatedLabel: freezed == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,hasLastGood: null == hasLastGood ? _self.hasLastGood : hasLastGood // ignore: cast_nullable_to_non_nullable
as bool,canRefresh: null == canRefresh ? _self.canRefresh : canRefresh // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountUsagePresentation].
extension AccountUsagePresentationPatterns on AccountUsagePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsagePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsagePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsagePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsagePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsagePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsagePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountQueryPhase phase,  AccountBalanceHealth balanceHealth,  List<AccountCurrencyBalance> balances,  List<AccountQuotaPresentation> quotas,  String? updatedLabel,  String? error,  bool hasLastGood,  bool canRefresh,  bool canRetry)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsagePresentation() when $default != null:
return $default(_that.phase,_that.balanceHealth,_that.balances,_that.quotas,_that.updatedLabel,_that.error,_that.hasLastGood,_that.canRefresh,_that.canRetry);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountQueryPhase phase,  AccountBalanceHealth balanceHealth,  List<AccountCurrencyBalance> balances,  List<AccountQuotaPresentation> quotas,  String? updatedLabel,  String? error,  bool hasLastGood,  bool canRefresh,  bool canRetry)  $default,) {final _that = this;
switch (_that) {
case _AccountUsagePresentation():
return $default(_that.phase,_that.balanceHealth,_that.balances,_that.quotas,_that.updatedLabel,_that.error,_that.hasLastGood,_that.canRefresh,_that.canRetry);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountQueryPhase phase,  AccountBalanceHealth balanceHealth,  List<AccountCurrencyBalance> balances,  List<AccountQuotaPresentation> quotas,  String? updatedLabel,  String? error,  bool hasLastGood,  bool canRefresh,  bool canRetry)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsagePresentation() when $default != null:
return $default(_that.phase,_that.balanceHealth,_that.balances,_that.quotas,_that.updatedLabel,_that.error,_that.hasLastGood,_that.canRefresh,_that.canRetry);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsagePresentation implements AccountUsagePresentation {
  const _AccountUsagePresentation({this.phase = AccountQueryPhase.idle, this.balanceHealth = AccountBalanceHealth.unknown,  List<AccountCurrencyBalance> balances = const <AccountCurrencyBalance>[],  List<AccountQuotaPresentation> quotas = const <AccountQuotaPresentation>[], this.updatedLabel, this.error, this.hasLastGood = false, this.canRefresh = false, this.canRetry = false}): _balances = balances,_quotas = quotas;


@override@JsonKey() final  AccountQueryPhase phase;
@override@JsonKey() final  AccountBalanceHealth balanceHealth;
 final  List<AccountCurrencyBalance> _balances;
@override@JsonKey() List<AccountCurrencyBalance> get balances {
  if (_balances is EqualUnmodifiableListView) return _balances;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_balances);
}

 final  List<AccountQuotaPresentation> _quotas;
@override@JsonKey() List<AccountQuotaPresentation> get quotas {
  if (_quotas is EqualUnmodifiableListView) return _quotas;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_quotas);
}

@override final  String? updatedLabel;
@override final  String? error;
/// The owner confirms that retained values belong to a successful query.
@override@JsonKey() final  bool hasLastGood;
@override@JsonKey() final  bool canRefresh;
@override@JsonKey() final  bool canRetry;

/// Create a copy of AccountUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsagePresentationCopyWith<_AccountUsagePresentation> get copyWith => __$AccountUsagePresentationCopyWithImpl<_AccountUsagePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsagePresentation&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.balanceHealth, balanceHealth) || other.balanceHealth == balanceHealth)&&const DeepCollectionEquality().equals(other.balances, _balances)&&const DeepCollectionEquality().equals(other.quotas, _quotas)&&(identical(other.updatedLabel, updatedLabel) || other.updatedLabel == updatedLabel)&&(identical(other.error, error) || other.error == error)&&(identical(other.hasLastGood, hasLastGood) || other.hasLastGood == hasLastGood)&&(identical(other.canRefresh, canRefresh) || other.canRefresh == canRefresh)&&(identical(other.canRetry, canRetry) || other.canRetry == canRetry));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,balanceHealth,const DeepCollectionEquality().hash(_balances),const DeepCollectionEquality().hash(_quotas),updatedLabel,error,hasLastGood,canRefresh,canRetry);
}

@override
String toString() {
    return 'AccountUsagePresentation(phase: $phase, balanceHealth: $balanceHealth, balances: $balances, quotas: $quotas, updatedLabel: $updatedLabel, error: $error, hasLastGood: $hasLastGood, canRefresh: $canRefresh, canRetry: $canRetry)';
}


}

/// @nodoc
abstract mixin class _$AccountUsagePresentationCopyWith<$Res> implements $AccountUsagePresentationCopyWith<$Res> {
  factory _$AccountUsagePresentationCopyWith(_AccountUsagePresentation value, $Res Function(_AccountUsagePresentation) _then) = __$AccountUsagePresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountQueryPhase phase, AccountBalanceHealth balanceHealth, List<AccountCurrencyBalance> balances, List<AccountQuotaPresentation> quotas, String? updatedLabel, String? error, bool hasLastGood, bool canRefresh, bool canRetry
});




}
/// @nodoc
class __$AccountUsagePresentationCopyWithImpl<$Res>
    implements _$AccountUsagePresentationCopyWith<$Res> {
  __$AccountUsagePresentationCopyWithImpl(this._self, this._then);

  final _AccountUsagePresentation _self;
  final $Res Function(_AccountUsagePresentation) _then;

/// Create a copy of AccountUsagePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? balanceHealth = null,Object? balances = null,Object? quotas = null,Object? updatedLabel = freezed,Object? error = freezed,Object? hasLastGood = null,Object? canRefresh = null,Object? canRetry = null,}) {
  return _then(_AccountUsagePresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountQueryPhase,balanceHealth: null == balanceHealth ? _self.balanceHealth : balanceHealth // ignore: cast_nullable_to_non_nullable
as AccountBalanceHealth,balances: null == balances ? _self._balances : balances // ignore: cast_nullable_to_non_nullable
as List<AccountCurrencyBalance>,quotas: null == quotas ? _self._quotas : quotas // ignore: cast_nullable_to_non_nullable
as List<AccountQuotaPresentation>,updatedLabel: freezed == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,hasLastGood: null == hasLastGood ? _self.hasLastGood : hasLastGood // ignore: cast_nullable_to_non_nullable
as bool,canRefresh: null == canRefresh ? _self.canRefresh : canRefresh // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AccountRowContent {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountRowContent);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountRowContent()';
}


}

/// @nodoc
class $AccountRowContentCopyWith<$Res>  {
$AccountRowContentCopyWith(AccountRowContent _, $Res Function(AccountRowContent) __);
}


/// Adds pattern-matching-related methods to [AccountRowContent].
extension AccountRowContentPatterns on AccountRowContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeAccountRowContent value)?  native,TResult Function( AcpAccountRowContent value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeAccountRowContent() when native != null:
return native(_that);case AcpAccountRowContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeAccountRowContent value)  native,required TResult Function( AcpAccountRowContent value)  acp,}){
final _that = this;
switch (_that) {
case NativeAccountRowContent():
return native(_that);case AcpAccountRowContent():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeAccountRowContent value)?  native,TResult? Function( AcpAccountRowContent value)?  acp,}){
final _that = this;
switch (_that) {
case NativeAccountRowContent() when native != null:
return native(_that);case AcpAccountRowContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( AccountBilling billing,  AccountUsagePresentation usage,  String? displayEndpoint)?  native,TResult Function( String status)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeAccountRowContent() when native != null:
return native(_that.billing,_that.usage,_that.displayEndpoint);case AcpAccountRowContent() when acp != null:
return acp(_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( AccountBilling billing,  AccountUsagePresentation usage,  String? displayEndpoint)  native,required TResult Function( String status)  acp,}) {final _that = this;
switch (_that) {
case NativeAccountRowContent():
return native(_that.billing,_that.usage,_that.displayEndpoint);case AcpAccountRowContent():
return acp(_that.status);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( AccountBilling billing,  AccountUsagePresentation usage,  String? displayEndpoint)?  native,TResult? Function( String status)?  acp,}) {final _that = this;
switch (_that) {
case NativeAccountRowContent() when native != null:
return native(_that.billing,_that.usage,_that.displayEndpoint);case AcpAccountRowContent() when acp != null:
return acp(_that.status);case _:
  return null;

}
}

}

/// @nodoc


class NativeAccountRowContent implements AccountRowContent {
  const NativeAccountRowContent({required this.billing, required this.usage, this.displayEndpoint});


 final  AccountBilling billing;
 final  AccountUsagePresentation usage;
 final  String? displayEndpoint;

/// Create a copy of AccountRowContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountRowContentCopyWith<NativeAccountRowContent> get copyWith => _$NativeAccountRowContentCopyWithImpl<NativeAccountRowContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountRowContent&&(identical(other.billing, billing) || other.billing == billing)&&(identical(other.usage, usage) || other.usage == usage)&&(identical(other.displayEndpoint, displayEndpoint) || other.displayEndpoint == displayEndpoint));
}


@override
int get hashCode {
    return Object.hash(runtimeType,billing,usage,displayEndpoint);
}

@override
String toString() {
    return 'AccountRowContent.native(billing: $billing, usage: $usage, displayEndpoint: $displayEndpoint)';
}


}

/// @nodoc
abstract mixin class $NativeAccountRowContentCopyWith<$Res> implements $AccountRowContentCopyWith<$Res> {
  factory $NativeAccountRowContentCopyWith(NativeAccountRowContent value, $Res Function(NativeAccountRowContent) _then) = _$NativeAccountRowContentCopyWithImpl;
@useResult
$Res call({
 AccountBilling billing, AccountUsagePresentation usage, String? displayEndpoint
});


$AccountUsagePresentationCopyWith<$Res> get usage;

}
/// @nodoc
class _$NativeAccountRowContentCopyWithImpl<$Res>
    implements $NativeAccountRowContentCopyWith<$Res> {
  _$NativeAccountRowContentCopyWithImpl(this._self, this._then);

  final NativeAccountRowContent _self;
  final $Res Function(NativeAccountRowContent) _then;

/// Create a copy of AccountRowContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? billing = null,Object? usage = null,Object? displayEndpoint = freezed,}) {
  return _then(NativeAccountRowContent(
billing: null == billing ? _self.billing : billing // ignore: cast_nullable_to_non_nullable
as AccountBilling,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as AccountUsagePresentation,displayEndpoint: freezed == displayEndpoint ? _self.displayEndpoint : displayEndpoint // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AccountRowContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsagePresentationCopyWith<$Res> get usage {

  return $AccountUsagePresentationCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}

/// @nodoc


class AcpAccountRowContent implements AccountRowContent {
  const AcpAccountRowContent({required this.status});


 final  String status;

/// Create a copy of AccountRowContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountRowContentCopyWith<AcpAccountRowContent> get copyWith => _$AcpAccountRowContentCopyWithImpl<AcpAccountRowContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountRowContent&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,status);
}

@override
String toString() {
    return 'AccountRowContent.acp(status: $status)';
}


}

/// @nodoc
abstract mixin class $AcpAccountRowContentCopyWith<$Res> implements $AccountRowContentCopyWith<$Res> {
  factory $AcpAccountRowContentCopyWith(AcpAccountRowContent value, $Res Function(AcpAccountRowContent) _then) = _$AcpAccountRowContentCopyWithImpl;
@useResult
$Res call({
 String status
});




}
/// @nodoc
class _$AcpAccountRowContentCopyWithImpl<$Res>
    implements $AcpAccountRowContentCopyWith<$Res> {
  _$AcpAccountRowContentCopyWithImpl(this._self, this._then);

  final AcpAccountRowContent _self;
  final $Res Function(AcpAccountRowContent) _then;

/// Create a copy of AccountRowContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? status = null,}) {
  return _then(AcpAccountRowContent(
status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountRowPresentation {

 AccountDisplayKey get key; String get name; AccountRowContent get content; String? get iconKey; bool get isDefault; String? get operationError; List<AccountRowAction> get actions;
/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountRowPresentationCopyWith<AccountRowPresentation> get copyWith => _$AccountRowPresentationCopyWithImpl<AccountRowPresentation>(this as AccountRowPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountRowPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountRowPresentation&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.isDefault, _this.isDefault) || other.isDefault == _this.isDefault)&&(identical(other.operationError, _this.operationError) || other.operationError == _this.operationError)&&const DeepCollectionEquality().equals(other.actions, _this.actions));
}


@override
int get hashCode {
  final _this = this as AccountRowPresentation;
  return Object.hash(runtimeType,_this.key,_this.name,_this.content,_this.iconKey,_this.isDefault,_this.operationError,const DeepCollectionEquality().hash(_this.actions));
}

@override
String toString() {
  final _this = this as AccountRowPresentation;
  return 'AccountRowPresentation(key: ${_this.key}, name: ${_this.name}, content: ${_this.content}, iconKey: ${_this.iconKey}, isDefault: ${_this.isDefault}, operationError: ${_this.operationError}, actions: ${_this.actions})';
}


}

/// @nodoc
abstract mixin class $AccountRowPresentationCopyWith<$Res>  {
  factory $AccountRowPresentationCopyWith(AccountRowPresentation value, $Res Function(AccountRowPresentation) _then) = _$AccountRowPresentationCopyWithImpl;
@useResult
$Res call({
 AccountDisplayKey key, String name, AccountRowContent content, String? iconKey, bool isDefault, String? operationError, List<AccountRowAction> actions
});


$AccountDisplayKeyCopyWith<$Res> get key;$AccountRowContentCopyWith<$Res> get content;

}
/// @nodoc
class _$AccountRowPresentationCopyWithImpl<$Res>
    implements $AccountRowPresentationCopyWith<$Res> {
  _$AccountRowPresentationCopyWithImpl(this._self, this._then);

  final AccountRowPresentation _self;
  final $Res Function(AccountRowPresentation) _then;

/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? isDefault = null,Object? operationError = freezed,Object? actions = null,}) {
  return _then(AccountRowPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountRowContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,operationError: freezed == operationError ? _self.operationError : operationError // ignore: cast_nullable_to_non_nullable
as String?,actions: null == actions ? _self.actions : actions // ignore: cast_nullable_to_non_nullable
as List<AccountRowAction>,
  ));
}
/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get key {

  return $AccountDisplayKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountRowContentCopyWith<$Res> get content {

  return $AccountRowContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountRowPresentation].
extension AccountRowPresentationPatterns on AccountRowPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountRowPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountRowPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountRowPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountRowPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountRowPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountRowPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountDisplayKey key,  String name,  AccountRowContent content,  String? iconKey,  bool isDefault,  String? operationError,  List<AccountRowAction> actions)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountRowPresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.isDefault,_that.operationError,_that.actions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountDisplayKey key,  String name,  AccountRowContent content,  String? iconKey,  bool isDefault,  String? operationError,  List<AccountRowAction> actions)  $default,) {final _that = this;
switch (_that) {
case _AccountRowPresentation():
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.isDefault,_that.operationError,_that.actions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountDisplayKey key,  String name,  AccountRowContent content,  String? iconKey,  bool isDefault,  String? operationError,  List<AccountRowAction> actions)?  $default,) {final _that = this;
switch (_that) {
case _AccountRowPresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.isDefault,_that.operationError,_that.actions);case _:
  return null;

}
}

}

/// @nodoc


class _AccountRowPresentation implements AccountRowPresentation {
  const _AccountRowPresentation({required this.key, required this.name, required this.content, this.iconKey, this.isDefault = false, this.operationError,  List<AccountRowAction> actions = const <AccountRowAction>[]}): _actions = actions;


@override final  AccountDisplayKey key;
@override final  String name;
@override final  AccountRowContent content;
@override final  String? iconKey;
@override@JsonKey() final  bool isDefault;
@override final  String? operationError;
 final  List<AccountRowAction> _actions;
@override@JsonKey() List<AccountRowAction> get actions {
  if (_actions is EqualUnmodifiableListView) return _actions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_actions);
}


/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountRowPresentationCopyWith<_AccountRowPresentation> get copyWith => __$AccountRowPresentationCopyWithImpl<_AccountRowPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountRowPresentation&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.content, content) || other.content == content)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.isDefault, isDefault) || other.isDefault == isDefault)&&(identical(other.operationError, operationError) || other.operationError == operationError)&&const DeepCollectionEquality().equals(other.actions, _actions));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,name,content,iconKey,isDefault,operationError,const DeepCollectionEquality().hash(_actions));
}

@override
String toString() {
    return 'AccountRowPresentation(key: $key, name: $name, content: $content, iconKey: $iconKey, isDefault: $isDefault, operationError: $operationError, actions: $actions)';
}


}

/// @nodoc
abstract mixin class _$AccountRowPresentationCopyWith<$Res> implements $AccountRowPresentationCopyWith<$Res> {
  factory _$AccountRowPresentationCopyWith(_AccountRowPresentation value, $Res Function(_AccountRowPresentation) _then) = __$AccountRowPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountDisplayKey key, String name, AccountRowContent content, String? iconKey, bool isDefault, String? operationError, List<AccountRowAction> actions
});


@override $AccountDisplayKeyCopyWith<$Res> get key;@override $AccountRowContentCopyWith<$Res> get content;

}
/// @nodoc
class __$AccountRowPresentationCopyWithImpl<$Res>
    implements _$AccountRowPresentationCopyWith<$Res> {
  __$AccountRowPresentationCopyWithImpl(this._self, this._then);

  final _AccountRowPresentation _self;
  final $Res Function(_AccountRowPresentation) _then;

/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? isDefault = null,Object? operationError = freezed,Object? actions = null,}) {
  return _then(_AccountRowPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountRowContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,isDefault: null == isDefault ? _self.isDefault : isDefault // ignore: cast_nullable_to_non_nullable
as bool,operationError: freezed == operationError ? _self.operationError : operationError // ignore: cast_nullable_to_non_nullable
as String?,actions: null == actions ? _self._actions : actions // ignore: cast_nullable_to_non_nullable
as List<AccountRowAction>,
  ));
}

/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get key {

  return $AccountDisplayKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountRowPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountRowContentCopyWith<$Res> get content {

  return $AccountRowContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}

/// @nodoc
mixin _$AccountsListPresentation {

 AccountListPhase get phase; List<AccountRowPresentation> get rows; String get search; bool get searchHasNoResults; bool get refreshing; bool get canAdd; bool get canRefresh; String? get error;
/// Create a copy of AccountsListPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountsListPresentationCopyWith<AccountsListPresentation> get copyWith => _$AccountsListPresentationCopyWithImpl<AccountsListPresentation>(this as AccountsListPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountsListPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountsListPresentation&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&const DeepCollectionEquality().equals(other.rows, _this.rows)&&(identical(other.search, _this.search) || other.search == _this.search)&&(identical(other.searchHasNoResults, _this.searchHasNoResults) || other.searchHasNoResults == _this.searchHasNoResults)&&(identical(other.refreshing, _this.refreshing) || other.refreshing == _this.refreshing)&&(identical(other.canAdd, _this.canAdd) || other.canAdd == _this.canAdd)&&(identical(other.canRefresh, _this.canRefresh) || other.canRefresh == _this.canRefresh)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountsListPresentation;
  return Object.hash(runtimeType,_this.phase,const DeepCollectionEquality().hash(_this.rows),_this.search,_this.searchHasNoResults,_this.refreshing,_this.canAdd,_this.canRefresh,_this.error);
}

@override
String toString() {
  final _this = this as AccountsListPresentation;
  return 'AccountsListPresentation(phase: ${_this.phase}, rows: ${_this.rows}, search: ${_this.search}, searchHasNoResults: ${_this.searchHasNoResults}, refreshing: ${_this.refreshing}, canAdd: ${_this.canAdd}, canRefresh: ${_this.canRefresh}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountsListPresentationCopyWith<$Res>  {
  factory $AccountsListPresentationCopyWith(AccountsListPresentation value, $Res Function(AccountsListPresentation) _then) = _$AccountsListPresentationCopyWithImpl;
@useResult
$Res call({
 AccountListPhase phase, List<AccountRowPresentation> rows, String search, bool searchHasNoResults, bool refreshing, bool canAdd, bool canRefresh, String? error
});




}
/// @nodoc
class _$AccountsListPresentationCopyWithImpl<$Res>
    implements $AccountsListPresentationCopyWith<$Res> {
  _$AccountsListPresentationCopyWithImpl(this._self, this._then);

  final AccountsListPresentation _self;
  final $Res Function(AccountsListPresentation) _then;

/// Create a copy of AccountsListPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? rows = null,Object? search = null,Object? searchHasNoResults = null,Object? refreshing = null,Object? canAdd = null,Object? canRefresh = null,Object? error = freezed,}) {
  return _then(AccountsListPresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountListPhase,rows: null == rows ? _self.rows : rows // ignore: cast_nullable_to_non_nullable
as List<AccountRowPresentation>,search: null == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as String,searchHasNoResults: null == searchHasNoResults ? _self.searchHasNoResults : searchHasNoResults // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,canAdd: null == canAdd ? _self.canAdd : canAdd // ignore: cast_nullable_to_non_nullable
as bool,canRefresh: null == canRefresh ? _self.canRefresh : canRefresh // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountsListPresentation].
extension AccountsListPresentationPatterns on AccountsListPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountsListPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountsListPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountsListPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountsListPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountsListPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountsListPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountListPhase phase,  List<AccountRowPresentation> rows,  String search,  bool searchHasNoResults,  bool refreshing,  bool canAdd,  bool canRefresh,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountsListPresentation() when $default != null:
return $default(_that.phase,_that.rows,_that.search,_that.searchHasNoResults,_that.refreshing,_that.canAdd,_that.canRefresh,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountListPhase phase,  List<AccountRowPresentation> rows,  String search,  bool searchHasNoResults,  bool refreshing,  bool canAdd,  bool canRefresh,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountsListPresentation():
return $default(_that.phase,_that.rows,_that.search,_that.searchHasNoResults,_that.refreshing,_that.canAdd,_that.canRefresh,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountListPhase phase,  List<AccountRowPresentation> rows,  String search,  bool searchHasNoResults,  bool refreshing,  bool canAdd,  bool canRefresh,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountsListPresentation() when $default != null:
return $default(_that.phase,_that.rows,_that.search,_that.searchHasNoResults,_that.refreshing,_that.canAdd,_that.canRefresh,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountsListPresentation implements AccountsListPresentation {
  const _AccountsListPresentation({this.phase = AccountListPhase.ready,  List<AccountRowPresentation> rows = const <AccountRowPresentation>[], this.search = '', this.searchHasNoResults = false, this.refreshing = false, this.canAdd = true, this.canRefresh = false, this.error}): _rows = rows;


@override@JsonKey() final  AccountListPhase phase;
 final  List<AccountRowPresentation> _rows;
@override@JsonKey() List<AccountRowPresentation> get rows {
  if (_rows is EqualUnmodifiableListView) return _rows;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_rows);
}

@override@JsonKey() final  String search;
@override@JsonKey() final  bool searchHasNoResults;
@override@JsonKey() final  bool refreshing;
@override@JsonKey() final  bool canAdd;
@override@JsonKey() final  bool canRefresh;
@override final  String? error;

/// Create a copy of AccountsListPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountsListPresentationCopyWith<_AccountsListPresentation> get copyWith => __$AccountsListPresentationCopyWithImpl<_AccountsListPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountsListPresentation&&(identical(other.phase, phase) || other.phase == phase)&&const DeepCollectionEquality().equals(other.rows, _rows)&&(identical(other.search, search) || other.search == search)&&(identical(other.searchHasNoResults, searchHasNoResults) || other.searchHasNoResults == searchHasNoResults)&&(identical(other.refreshing, refreshing) || other.refreshing == refreshing)&&(identical(other.canAdd, canAdd) || other.canAdd == canAdd)&&(identical(other.canRefresh, canRefresh) || other.canRefresh == canRefresh)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,const DeepCollectionEquality().hash(_rows),search,searchHasNoResults,refreshing,canAdd,canRefresh,error);
}

@override
String toString() {
    return 'AccountsListPresentation(phase: $phase, rows: $rows, search: $search, searchHasNoResults: $searchHasNoResults, refreshing: $refreshing, canAdd: $canAdd, canRefresh: $canRefresh, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountsListPresentationCopyWith<$Res> implements $AccountsListPresentationCopyWith<$Res> {
  factory _$AccountsListPresentationCopyWith(_AccountsListPresentation value, $Res Function(_AccountsListPresentation) _then) = __$AccountsListPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountListPhase phase, List<AccountRowPresentation> rows, String search, bool searchHasNoResults, bool refreshing, bool canAdd, bool canRefresh, String? error
});




}
/// @nodoc
class __$AccountsListPresentationCopyWithImpl<$Res>
    implements _$AccountsListPresentationCopyWith<$Res> {
  __$AccountsListPresentationCopyWithImpl(this._self, this._then);

  final _AccountsListPresentation _self;
  final $Res Function(_AccountsListPresentation) _then;

/// Create a copy of AccountsListPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? rows = null,Object? search = null,Object? searchHasNoResults = null,Object? refreshing = null,Object? canAdd = null,Object? canRefresh = null,Object? error = freezed,}) {
  return _then(_AccountsListPresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AccountListPhase,rows: null == rows ? _self._rows : rows // ignore: cast_nullable_to_non_nullable
as List<AccountRowPresentation>,search: null == search ? _self.search : search // ignore: cast_nullable_to_non_nullable
as String,searchHasNoResults: null == searchHasNoResults ? _self.searchHasNoResults : searchHasNoResults // ignore: cast_nullable_to_non_nullable
as bool,refreshing: null == refreshing ? _self.refreshing : refreshing // ignore: cast_nullable_to_non_nullable
as bool,canAdd: null == canAdd ? _self.canAdd : canAdd // ignore: cast_nullable_to_non_nullable
as bool,canRefresh: null == canRefresh ? _self.canRefresh : canRefresh // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountDisplayFact {

 String get label; String get value;
/// Create a copy of AccountDisplayFact
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountDisplayFactCopyWith<AccountDisplayFact> get copyWith => _$AccountDisplayFactCopyWithImpl<AccountDisplayFact>(this as AccountDisplayFact, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountDisplayFact;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDisplayFact&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as AccountDisplayFact;
  return Object.hash(runtimeType,_this.label,_this.value);
}

@override
String toString() {
  final _this = this as AccountDisplayFact;
  return 'AccountDisplayFact(label: ${_this.label}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $AccountDisplayFactCopyWith<$Res>  {
  factory $AccountDisplayFactCopyWith(AccountDisplayFact value, $Res Function(AccountDisplayFact) _then) = _$AccountDisplayFactCopyWithImpl;
@useResult
$Res call({
 String label, String value
});




}
/// @nodoc
class _$AccountDisplayFactCopyWithImpl<$Res>
    implements $AccountDisplayFactCopyWith<$Res> {
  _$AccountDisplayFactCopyWithImpl(this._self, this._then);

  final AccountDisplayFact _self;
  final $Res Function(AccountDisplayFact) _then;

/// Create a copy of AccountDisplayFact
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? value = null,}) {
  return _then(AccountDisplayFact(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountDisplayFact].
extension AccountDisplayFactPatterns on AccountDisplayFact {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountDisplayFact value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountDisplayFact() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountDisplayFact value)  $default,){
final _that = this;
switch (_that) {
case _AccountDisplayFact():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountDisplayFact value)?  $default,){
final _that = this;
switch (_that) {
case _AccountDisplayFact() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountDisplayFact() when $default != null:
return $default(_that.label,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  String value)  $default,) {final _that = this;
switch (_that) {
case _AccountDisplayFact():
return $default(_that.label,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  String value)?  $default,) {final _that = this;
switch (_that) {
case _AccountDisplayFact() when $default != null:
return $default(_that.label,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _AccountDisplayFact implements AccountDisplayFact {
  const _AccountDisplayFact({required this.label, required this.value});


@override final  String label;
@override final  String value;

/// Create a copy of AccountDisplayFact
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountDisplayFactCopyWith<_AccountDisplayFact> get copyWith => __$AccountDisplayFactCopyWithImpl<_AccountDisplayFact>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountDisplayFact&&(identical(other.label, label) || other.label == label)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,value);
}

@override
String toString() {
    return 'AccountDisplayFact(label: $label, value: $value)';
}


}

/// @nodoc
abstract mixin class _$AccountDisplayFactCopyWith<$Res> implements $AccountDisplayFactCopyWith<$Res> {
  factory _$AccountDisplayFactCopyWith(_AccountDisplayFact value, $Res Function(_AccountDisplayFact) _then) = __$AccountDisplayFactCopyWithImpl;
@override @useResult
$Res call({
 String label, String value
});




}
/// @nodoc
class __$AccountDisplayFactCopyWithImpl<$Res>
    implements _$AccountDisplayFactCopyWith<$Res> {
  __$AccountDisplayFactCopyWithImpl(this._self, this._then);

  final _AccountDisplayFact _self;
  final $Res Function(_AccountDisplayFact) _then;

/// Create a copy of AccountDisplayFact
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? value = null,}) {
  return _then(_AccountDisplayFact(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountModelSpecificationFacts {

 List<AccountDisplayFact> get modalityCapabilities; List<AccountDisplayFact> get context; List<AccountDisplayFact> get connection;
/// Create a copy of AccountModelSpecificationFacts
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelSpecificationFactsCopyWith<AccountModelSpecificationFacts> get copyWith => _$AccountModelSpecificationFactsCopyWithImpl<AccountModelSpecificationFacts>(this as AccountModelSpecificationFacts, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelSpecificationFacts;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelSpecificationFacts&&const DeepCollectionEquality().equals(other.modalityCapabilities, _this.modalityCapabilities)&&const DeepCollectionEquality().equals(other.context, _this.context)&&const DeepCollectionEquality().equals(other.connection, _this.connection));
}


@override
int get hashCode {
  final _this = this as AccountModelSpecificationFacts;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.modalityCapabilities),const DeepCollectionEquality().hash(_this.context),const DeepCollectionEquality().hash(_this.connection));
}

@override
String toString() {
  final _this = this as AccountModelSpecificationFacts;
  return 'AccountModelSpecificationFacts(modalityCapabilities: ${_this.modalityCapabilities}, context: ${_this.context}, connection: ${_this.connection})';
}


}

/// @nodoc
abstract mixin class $AccountModelSpecificationFactsCopyWith<$Res>  {
  factory $AccountModelSpecificationFactsCopyWith(AccountModelSpecificationFacts value, $Res Function(AccountModelSpecificationFacts) _then) = _$AccountModelSpecificationFactsCopyWithImpl;
@useResult
$Res call({
 List<AccountDisplayFact> modalityCapabilities, List<AccountDisplayFact> context, List<AccountDisplayFact> connection
});




}
/// @nodoc
class _$AccountModelSpecificationFactsCopyWithImpl<$Res>
    implements $AccountModelSpecificationFactsCopyWith<$Res> {
  _$AccountModelSpecificationFactsCopyWithImpl(this._self, this._then);

  final AccountModelSpecificationFacts _self;
  final $Res Function(AccountModelSpecificationFacts) _then;

/// Create a copy of AccountModelSpecificationFacts
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modalityCapabilities = null,Object? context = null,Object? connection = null,}) {
  return _then(AccountModelSpecificationFacts(
modalityCapabilities: null == modalityCapabilities ? _self.modalityCapabilities : modalityCapabilities // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,context: null == context ? _self.context : context // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelSpecificationFacts].
extension AccountModelSpecificationFactsPatterns on AccountModelSpecificationFacts {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelSpecificationFacts value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelSpecificationFacts value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelSpecificationFacts value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AccountDisplayFact> modalityCapabilities,  List<AccountDisplayFact> context,  List<AccountDisplayFact> connection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts() when $default != null:
return $default(_that.modalityCapabilities,_that.context,_that.connection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AccountDisplayFact> modalityCapabilities,  List<AccountDisplayFact> context,  List<AccountDisplayFact> connection)  $default,) {final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts():
return $default(_that.modalityCapabilities,_that.context,_that.connection);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AccountDisplayFact> modalityCapabilities,  List<AccountDisplayFact> context,  List<AccountDisplayFact> connection)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelSpecificationFacts() when $default != null:
return $default(_that.modalityCapabilities,_that.context,_that.connection);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelSpecificationFacts implements AccountModelSpecificationFacts {
  const _AccountModelSpecificationFacts({ List<AccountDisplayFact> modalityCapabilities = const <AccountDisplayFact>[],  List<AccountDisplayFact> context = const <AccountDisplayFact>[],  List<AccountDisplayFact> connection = const <AccountDisplayFact>[]}): _modalityCapabilities = modalityCapabilities,_context = context,_connection = connection;


 final  List<AccountDisplayFact> _modalityCapabilities;
@override@JsonKey() List<AccountDisplayFact> get modalityCapabilities {
  if (_modalityCapabilities is EqualUnmodifiableListView) return _modalityCapabilities;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_modalityCapabilities);
}

 final  List<AccountDisplayFact> _context;
@override@JsonKey() List<AccountDisplayFact> get context {
  if (_context is EqualUnmodifiableListView) return _context;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_context);
}

 final  List<AccountDisplayFact> _connection;
@override@JsonKey() List<AccountDisplayFact> get connection {
  if (_connection is EqualUnmodifiableListView) return _connection;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_connection);
}


/// Create a copy of AccountModelSpecificationFacts
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelSpecificationFactsCopyWith<_AccountModelSpecificationFacts> get copyWith => __$AccountModelSpecificationFactsCopyWithImpl<_AccountModelSpecificationFacts>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelSpecificationFacts&&const DeepCollectionEquality().equals(other.modalityCapabilities, _modalityCapabilities)&&const DeepCollectionEquality().equals(other.context, _context)&&const DeepCollectionEquality().equals(other.connection, _connection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_modalityCapabilities),const DeepCollectionEquality().hash(_context),const DeepCollectionEquality().hash(_connection));
}

@override
String toString() {
    return 'AccountModelSpecificationFacts(modalityCapabilities: $modalityCapabilities, context: $context, connection: $connection)';
}


}

/// @nodoc
abstract mixin class _$AccountModelSpecificationFactsCopyWith<$Res> implements $AccountModelSpecificationFactsCopyWith<$Res> {
  factory _$AccountModelSpecificationFactsCopyWith(_AccountModelSpecificationFacts value, $Res Function(_AccountModelSpecificationFacts) _then) = __$AccountModelSpecificationFactsCopyWithImpl;
@override @useResult
$Res call({
 List<AccountDisplayFact> modalityCapabilities, List<AccountDisplayFact> context, List<AccountDisplayFact> connection
});




}
/// @nodoc
class __$AccountModelSpecificationFactsCopyWithImpl<$Res>
    implements _$AccountModelSpecificationFactsCopyWith<$Res> {
  __$AccountModelSpecificationFactsCopyWithImpl(this._self, this._then);

  final _AccountModelSpecificationFacts _self;
  final $Res Function(_AccountModelSpecificationFacts) _then;

/// Create a copy of AccountModelSpecificationFacts
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modalityCapabilities = null,Object? context = null,Object? connection = null,}) {
  return _then(_AccountModelSpecificationFacts(
modalityCapabilities: null == modalityCapabilities ? _self._modalityCapabilities : modalityCapabilities // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,context: null == context ? _self._context : context // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,connection: null == connection ? _self._connection : connection // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,
  ));
}


}

/// @nodoc
mixin _$AccountBillingPresentation {

 AccountBilling get effective; AccountBilling? get billingKindOverride; List<AccountBilling> get allowedOverrides; bool get saving; String? get error;
/// Create a copy of AccountBillingPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountBillingPresentationCopyWith<AccountBillingPresentation> get copyWith => _$AccountBillingPresentationCopyWithImpl<AccountBillingPresentation>(this as AccountBillingPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountBillingPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountBillingPresentation&&(identical(other.effective, _this.effective) || other.effective == _this.effective)&&(identical(other.billingKindOverride, _this.billingKindOverride) || other.billingKindOverride == _this.billingKindOverride)&&const DeepCollectionEquality().equals(other.allowedOverrides, _this.allowedOverrides)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountBillingPresentation;
  return Object.hash(runtimeType,_this.effective,_this.billingKindOverride,const DeepCollectionEquality().hash(_this.allowedOverrides),_this.saving,_this.error);
}

@override
String toString() {
  final _this = this as AccountBillingPresentation;
  return 'AccountBillingPresentation(effective: ${_this.effective}, billingKindOverride: ${_this.billingKindOverride}, allowedOverrides: ${_this.allowedOverrides}, saving: ${_this.saving}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountBillingPresentationCopyWith<$Res>  {
  factory $AccountBillingPresentationCopyWith(AccountBillingPresentation value, $Res Function(AccountBillingPresentation) _then) = _$AccountBillingPresentationCopyWithImpl;
@useResult
$Res call({
 AccountBilling effective, AccountBilling? billingKindOverride, List<AccountBilling> allowedOverrides, bool saving, String? error
});




}
/// @nodoc
class _$AccountBillingPresentationCopyWithImpl<$Res>
    implements $AccountBillingPresentationCopyWith<$Res> {
  _$AccountBillingPresentationCopyWithImpl(this._self, this._then);

  final AccountBillingPresentation _self;
  final $Res Function(AccountBillingPresentation) _then;

/// Create a copy of AccountBillingPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? effective = null,Object? billingKindOverride = freezed,Object? allowedOverrides = null,Object? saving = null,Object? error = freezed,}) {
  return _then(AccountBillingPresentation(
effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as AccountBilling,billingKindOverride: freezed == billingKindOverride ? _self.billingKindOverride : billingKindOverride // ignore: cast_nullable_to_non_nullable
as AccountBilling?,allowedOverrides: null == allowedOverrides ? _self.allowedOverrides : allowedOverrides // ignore: cast_nullable_to_non_nullable
as List<AccountBilling>,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountBillingPresentation].
extension AccountBillingPresentationPatterns on AccountBillingPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountBillingPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountBillingPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountBillingPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountBillingPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountBillingPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountBillingPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountBilling effective,  AccountBilling? billingKindOverride,  List<AccountBilling> allowedOverrides,  bool saving,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountBillingPresentation() when $default != null:
return $default(_that.effective,_that.billingKindOverride,_that.allowedOverrides,_that.saving,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountBilling effective,  AccountBilling? billingKindOverride,  List<AccountBilling> allowedOverrides,  bool saving,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountBillingPresentation():
return $default(_that.effective,_that.billingKindOverride,_that.allowedOverrides,_that.saving,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountBilling effective,  AccountBilling? billingKindOverride,  List<AccountBilling> allowedOverrides,  bool saving,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountBillingPresentation() when $default != null:
return $default(_that.effective,_that.billingKindOverride,_that.allowedOverrides,_that.saving,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountBillingPresentation implements AccountBillingPresentation {
  const _AccountBillingPresentation({required this.effective, this.billingKindOverride,  List<AccountBilling> allowedOverrides = const <AccountBilling>[], this.saving = false, this.error}): _allowedOverrides = allowedOverrides;


@override final  AccountBilling effective;
@override final  AccountBilling? billingKindOverride;
 final  List<AccountBilling> _allowedOverrides;
@override@JsonKey() List<AccountBilling> get allowedOverrides {
  if (_allowedOverrides is EqualUnmodifiableListView) return _allowedOverrides;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_allowedOverrides);
}

@override@JsonKey() final  bool saving;
@override final  String? error;

/// Create a copy of AccountBillingPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountBillingPresentationCopyWith<_AccountBillingPresentation> get copyWith => __$AccountBillingPresentationCopyWithImpl<_AccountBillingPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountBillingPresentation&&(identical(other.effective, effective) || other.effective == effective)&&(identical(other.billingKindOverride, billingKindOverride) || other.billingKindOverride == billingKindOverride)&&const DeepCollectionEquality().equals(other.allowedOverrides, _allowedOverrides)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,effective,billingKindOverride,const DeepCollectionEquality().hash(_allowedOverrides),saving,error);
}

@override
String toString() {
    return 'AccountBillingPresentation(effective: $effective, billingKindOverride: $billingKindOverride, allowedOverrides: $allowedOverrides, saving: $saving, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountBillingPresentationCopyWith<$Res> implements $AccountBillingPresentationCopyWith<$Res> {
  factory _$AccountBillingPresentationCopyWith(_AccountBillingPresentation value, $Res Function(_AccountBillingPresentation) _then) = __$AccountBillingPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountBilling effective, AccountBilling? billingKindOverride, List<AccountBilling> allowedOverrides, bool saving, String? error
});




}
/// @nodoc
class __$AccountBillingPresentationCopyWithImpl<$Res>
    implements _$AccountBillingPresentationCopyWith<$Res> {
  __$AccountBillingPresentationCopyWithImpl(this._self, this._then);

  final _AccountBillingPresentation _self;
  final $Res Function(_AccountBillingPresentation) _then;

/// Create a copy of AccountBillingPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? effective = null,Object? billingKindOverride = freezed,Object? allowedOverrides = null,Object? saving = null,Object? error = freezed,}) {
  return _then(_AccountBillingPresentation(
effective: null == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as AccountBilling,billingKindOverride: freezed == billingKindOverride ? _self.billingKindOverride : billingKindOverride // ignore: cast_nullable_to_non_nullable
as AccountBilling?,allowedOverrides: null == allowedOverrides ? _self._allowedOverrides : allowedOverrides // ignore: cast_nullable_to_non_nullable
as List<AccountBilling>,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountCompactPresentation {

 String get raw; bool get overridden; String? get effective; String? get automatic; String? get error; bool get saving; bool get canEdit; bool get canReset; bool get canRetry; bool get dirty; bool get canSave; int? get contextWindow; bool get adjusted;
/// Create a copy of AccountCompactPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCompactPresentationCopyWith<AccountCompactPresentation> get copyWith => _$AccountCompactPresentationCopyWithImpl<AccountCompactPresentation>(this as AccountCompactPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountCompactPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountCompactPresentation&&(identical(other.raw, _this.raw) || other.raw == _this.raw)&&(identical(other.overridden, _this.overridden) || other.overridden == _this.overridden)&&(identical(other.effective, _this.effective) || other.effective == _this.effective)&&(identical(other.automatic, _this.automatic) || other.automatic == _this.automatic)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.canEdit, _this.canEdit) || other.canEdit == _this.canEdit)&&(identical(other.canReset, _this.canReset) || other.canReset == _this.canReset)&&(identical(other.canRetry, _this.canRetry) || other.canRetry == _this.canRetry)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.canSave, _this.canSave) || other.canSave == _this.canSave)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.adjusted, _this.adjusted) || other.adjusted == _this.adjusted));
}


@override
int get hashCode {
  final _this = this as AccountCompactPresentation;
  return Object.hash(runtimeType,_this.raw,_this.overridden,_this.effective,_this.automatic,_this.error,_this.saving,_this.canEdit,_this.canReset,_this.canRetry,_this.dirty,_this.canSave,_this.contextWindow,_this.adjusted);
}

@override
String toString() {
  final _this = this as AccountCompactPresentation;
  return 'AccountCompactPresentation(raw: ${_this.raw}, overridden: ${_this.overridden}, effective: ${_this.effective}, automatic: ${_this.automatic}, error: ${_this.error}, saving: ${_this.saving}, canEdit: ${_this.canEdit}, canReset: ${_this.canReset}, canRetry: ${_this.canRetry}, dirty: ${_this.dirty}, canSave: ${_this.canSave}, contextWindow: ${_this.contextWindow}, adjusted: ${_this.adjusted})';
}


}

/// @nodoc
abstract mixin class $AccountCompactPresentationCopyWith<$Res>  {
  factory $AccountCompactPresentationCopyWith(AccountCompactPresentation value, $Res Function(AccountCompactPresentation) _then) = _$AccountCompactPresentationCopyWithImpl;
@useResult
$Res call({
 String raw, bool overridden, String? effective, String? automatic, String? error, bool saving, bool canEdit, bool canReset, bool canRetry, bool dirty, bool canSave, int? contextWindow, bool adjusted
});




}
/// @nodoc
class _$AccountCompactPresentationCopyWithImpl<$Res>
    implements $AccountCompactPresentationCopyWith<$Res> {
  _$AccountCompactPresentationCopyWithImpl(this._self, this._then);

  final AccountCompactPresentation _self;
  final $Res Function(AccountCompactPresentation) _then;

/// Create a copy of AccountCompactPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,Object? overridden = null,Object? effective = freezed,Object? automatic = freezed,Object? error = freezed,Object? saving = null,Object? canEdit = null,Object? canReset = null,Object? canRetry = null,Object? dirty = null,Object? canSave = null,Object? contextWindow = freezed,Object? adjusted = null,}) {
  return _then(AccountCompactPresentation(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,overridden: null == overridden ? _self.overridden : overridden // ignore: cast_nullable_to_non_nullable
as bool,effective: freezed == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as String?,automatic: freezed == automatic ? _self.automatic : automatic // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canReset: null == canReset ? _self.canReset : canReset // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,adjusted: null == adjusted ? _self.adjusted : adjusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountCompactPresentation].
extension AccountCompactPresentationPatterns on AccountCompactPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountCompactPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountCompactPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountCompactPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountCompactPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountCompactPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountCompactPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String raw,  bool overridden,  String? effective,  String? automatic,  String? error,  bool saving,  bool canEdit,  bool canReset,  bool canRetry,  bool dirty,  bool canSave,  int? contextWindow,  bool adjusted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountCompactPresentation() when $default != null:
return $default(_that.raw,_that.overridden,_that.effective,_that.automatic,_that.error,_that.saving,_that.canEdit,_that.canReset,_that.canRetry,_that.dirty,_that.canSave,_that.contextWindow,_that.adjusted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String raw,  bool overridden,  String? effective,  String? automatic,  String? error,  bool saving,  bool canEdit,  bool canReset,  bool canRetry,  bool dirty,  bool canSave,  int? contextWindow,  bool adjusted)  $default,) {final _that = this;
switch (_that) {
case _AccountCompactPresentation():
return $default(_that.raw,_that.overridden,_that.effective,_that.automatic,_that.error,_that.saving,_that.canEdit,_that.canReset,_that.canRetry,_that.dirty,_that.canSave,_that.contextWindow,_that.adjusted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String raw,  bool overridden,  String? effective,  String? automatic,  String? error,  bool saving,  bool canEdit,  bool canReset,  bool canRetry,  bool dirty,  bool canSave,  int? contextWindow,  bool adjusted)?  $default,) {final _that = this;
switch (_that) {
case _AccountCompactPresentation() when $default != null:
return $default(_that.raw,_that.overridden,_that.effective,_that.automatic,_that.error,_that.saving,_that.canEdit,_that.canReset,_that.canRetry,_that.dirty,_that.canSave,_that.contextWindow,_that.adjusted);case _:
  return null;

}
}

}

/// @nodoc


class _AccountCompactPresentation implements AccountCompactPresentation {
  const _AccountCompactPresentation({this.raw = '', this.overridden = false, this.effective, this.automatic, this.error, this.saving = false, this.canEdit = false, this.canReset = false, this.canRetry = false, this.dirty = false, this.canSave = false, this.contextWindow, this.adjusted = false});


@override@JsonKey() final  String raw;
@override@JsonKey() final  bool overridden;
@override final  String? effective;
@override final  String? automatic;
@override final  String? error;
@override@JsonKey() final  bool saving;
@override@JsonKey() final  bool canEdit;
@override@JsonKey() final  bool canReset;
@override@JsonKey() final  bool canRetry;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool canSave;
@override final  int? contextWindow;
@override@JsonKey() final  bool adjusted;

/// Create a copy of AccountCompactPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCompactPresentationCopyWith<_AccountCompactPresentation> get copyWith => __$AccountCompactPresentationCopyWithImpl<_AccountCompactPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountCompactPresentation&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.overridden, overridden) || other.overridden == overridden)&&(identical(other.effective, effective) || other.effective == effective)&&(identical(other.automatic, automatic) || other.automatic == automatic)&&(identical(other.error, error) || other.error == error)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.canEdit, canEdit) || other.canEdit == canEdit)&&(identical(other.canReset, canReset) || other.canReset == canReset)&&(identical(other.canRetry, canRetry) || other.canRetry == canRetry)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.canSave, canSave) || other.canSave == canSave)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.adjusted, adjusted) || other.adjusted == adjusted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,raw,overridden,effective,automatic,error,saving,canEdit,canReset,canRetry,dirty,canSave,contextWindow,adjusted);
}

@override
String toString() {
    return 'AccountCompactPresentation(raw: $raw, overridden: $overridden, effective: $effective, automatic: $automatic, error: $error, saving: $saving, canEdit: $canEdit, canReset: $canReset, canRetry: $canRetry, dirty: $dirty, canSave: $canSave, contextWindow: $contextWindow, adjusted: $adjusted)';
}


}

/// @nodoc
abstract mixin class _$AccountCompactPresentationCopyWith<$Res> implements $AccountCompactPresentationCopyWith<$Res> {
  factory _$AccountCompactPresentationCopyWith(_AccountCompactPresentation value, $Res Function(_AccountCompactPresentation) _then) = __$AccountCompactPresentationCopyWithImpl;
@override @useResult
$Res call({
 String raw, bool overridden, String? effective, String? automatic, String? error, bool saving, bool canEdit, bool canReset, bool canRetry, bool dirty, bool canSave, int? contextWindow, bool adjusted
});




}
/// @nodoc
class __$AccountCompactPresentationCopyWithImpl<$Res>
    implements _$AccountCompactPresentationCopyWith<$Res> {
  __$AccountCompactPresentationCopyWithImpl(this._self, this._then);

  final _AccountCompactPresentation _self;
  final $Res Function(_AccountCompactPresentation) _then;

/// Create a copy of AccountCompactPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,Object? overridden = null,Object? effective = freezed,Object? automatic = freezed,Object? error = freezed,Object? saving = null,Object? canEdit = null,Object? canReset = null,Object? canRetry = null,Object? dirty = null,Object? canSave = null,Object? contextWindow = freezed,Object? adjusted = null,}) {
  return _then(_AccountCompactPresentation(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,overridden: null == overridden ? _self.overridden : overridden // ignore: cast_nullable_to_non_nullable
as bool,effective: freezed == effective ? _self.effective : effective // ignore: cast_nullable_to_non_nullable
as String?,automatic: freezed == automatic ? _self.automatic : automatic // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canReset: null == canReset ? _self.canReset : canReset // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,contextWindow: freezed == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as int?,adjusted: null == adjusted ? _self.adjusted : adjusted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AccountModelEvaluation {

 AccountEvaluationCategory get category; String get categoryLabel; AccountEvaluationOutcome get outcome; String get outcomeLabel; String get updatedLabel; int get updatedAt; String get comment; int? get quality; int? get instructionFollowing;
/// Create a copy of AccountModelEvaluation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelEvaluationCopyWith<AccountModelEvaluation> get copyWith => _$AccountModelEvaluationCopyWithImpl<AccountModelEvaluation>(this as AccountModelEvaluation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelEvaluation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelEvaluation&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.categoryLabel, _this.categoryLabel) || other.categoryLabel == _this.categoryLabel)&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.outcomeLabel, _this.outcomeLabel) || other.outcomeLabel == _this.outcomeLabel)&&(identical(other.updatedLabel, _this.updatedLabel) || other.updatedLabel == _this.updatedLabel)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.comment, _this.comment) || other.comment == _this.comment)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&(identical(other.instructionFollowing, _this.instructionFollowing) || other.instructionFollowing == _this.instructionFollowing));
}


@override
int get hashCode {
  final _this = this as AccountModelEvaluation;
  return Object.hash(runtimeType,_this.category,_this.categoryLabel,_this.outcome,_this.outcomeLabel,_this.updatedLabel,_this.updatedAt,_this.comment,_this.quality,_this.instructionFollowing);
}

@override
String toString() {
  final _this = this as AccountModelEvaluation;
  return 'AccountModelEvaluation(category: ${_this.category}, categoryLabel: ${_this.categoryLabel}, outcome: ${_this.outcome}, outcomeLabel: ${_this.outcomeLabel}, updatedLabel: ${_this.updatedLabel}, updatedAt: ${_this.updatedAt}, comment: ${_this.comment}, quality: ${_this.quality}, instructionFollowing: ${_this.instructionFollowing})';
}


}

/// @nodoc
abstract mixin class $AccountModelEvaluationCopyWith<$Res>  {
  factory $AccountModelEvaluationCopyWith(AccountModelEvaluation value, $Res Function(AccountModelEvaluation) _then) = _$AccountModelEvaluationCopyWithImpl;
@useResult
$Res call({
 AccountEvaluationCategory category, String categoryLabel, AccountEvaluationOutcome outcome, String outcomeLabel, String updatedLabel, int updatedAt, String comment, int? quality, int? instructionFollowing
});




}
/// @nodoc
class _$AccountModelEvaluationCopyWithImpl<$Res>
    implements $AccountModelEvaluationCopyWith<$Res> {
  _$AccountModelEvaluationCopyWithImpl(this._self, this._then);

  final AccountModelEvaluation _self;
  final $Res Function(AccountModelEvaluation) _then;

/// Create a copy of AccountModelEvaluation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? category = null,Object? categoryLabel = null,Object? outcome = null,Object? outcomeLabel = null,Object? updatedLabel = null,Object? updatedAt = null,Object? comment = null,Object? quality = freezed,Object? instructionFollowing = freezed,}) {
  return _then(AccountModelEvaluation(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountEvaluationCategory,categoryLabel: null == categoryLabel ? _self.categoryLabel : categoryLabel // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AccountEvaluationOutcome,outcomeLabel: null == outcomeLabel ? _self.outcomeLabel : outcomeLabel // ignore: cast_nullable_to_non_nullable
as String,updatedLabel: null == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelEvaluation].
extension AccountModelEvaluationPatterns on AccountModelEvaluation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelEvaluation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelEvaluation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelEvaluation value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelEvaluation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelEvaluation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelEvaluation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountEvaluationCategory category,  String categoryLabel,  AccountEvaluationOutcome outcome,  String outcomeLabel,  String updatedLabel,  int updatedAt,  String comment,  int? quality,  int? instructionFollowing)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelEvaluation() when $default != null:
return $default(_that.category,_that.categoryLabel,_that.outcome,_that.outcomeLabel,_that.updatedLabel,_that.updatedAt,_that.comment,_that.quality,_that.instructionFollowing);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountEvaluationCategory category,  String categoryLabel,  AccountEvaluationOutcome outcome,  String outcomeLabel,  String updatedLabel,  int updatedAt,  String comment,  int? quality,  int? instructionFollowing)  $default,) {final _that = this;
switch (_that) {
case _AccountModelEvaluation():
return $default(_that.category,_that.categoryLabel,_that.outcome,_that.outcomeLabel,_that.updatedLabel,_that.updatedAt,_that.comment,_that.quality,_that.instructionFollowing);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountEvaluationCategory category,  String categoryLabel,  AccountEvaluationOutcome outcome,  String outcomeLabel,  String updatedLabel,  int updatedAt,  String comment,  int? quality,  int? instructionFollowing)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelEvaluation() when $default != null:
return $default(_that.category,_that.categoryLabel,_that.outcome,_that.outcomeLabel,_that.updatedLabel,_that.updatedAt,_that.comment,_that.quality,_that.instructionFollowing);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelEvaluation implements AccountModelEvaluation {
  const _AccountModelEvaluation({required this.category, required this.categoryLabel, required this.outcome, required this.outcomeLabel, required this.updatedLabel, required this.updatedAt, required this.comment, this.quality, this.instructionFollowing});


@override final  AccountEvaluationCategory category;
@override final  String categoryLabel;
@override final  AccountEvaluationOutcome outcome;
@override final  String outcomeLabel;
@override final  String updatedLabel;
@override final  int updatedAt;
@override final  String comment;
@override final  int? quality;
@override final  int? instructionFollowing;

/// Create a copy of AccountModelEvaluation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelEvaluationCopyWith<_AccountModelEvaluation> get copyWith => __$AccountModelEvaluationCopyWithImpl<_AccountModelEvaluation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelEvaluation&&(identical(other.category, category) || other.category == category)&&(identical(other.categoryLabel, categoryLabel) || other.categoryLabel == categoryLabel)&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.outcomeLabel, outcomeLabel) || other.outcomeLabel == outcomeLabel)&&(identical(other.updatedLabel, updatedLabel) || other.updatedLabel == updatedLabel)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.comment, comment) || other.comment == comment)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.instructionFollowing, instructionFollowing) || other.instructionFollowing == instructionFollowing));
}


@override
int get hashCode {
    return Object.hash(runtimeType,category,categoryLabel,outcome,outcomeLabel,updatedLabel,updatedAt,comment,quality,instructionFollowing);
}

@override
String toString() {
    return 'AccountModelEvaluation(category: $category, categoryLabel: $categoryLabel, outcome: $outcome, outcomeLabel: $outcomeLabel, updatedLabel: $updatedLabel, updatedAt: $updatedAt, comment: $comment, quality: $quality, instructionFollowing: $instructionFollowing)';
}


}

/// @nodoc
abstract mixin class _$AccountModelEvaluationCopyWith<$Res> implements $AccountModelEvaluationCopyWith<$Res> {
  factory _$AccountModelEvaluationCopyWith(_AccountModelEvaluation value, $Res Function(_AccountModelEvaluation) _then) = __$AccountModelEvaluationCopyWithImpl;
@override @useResult
$Res call({
 AccountEvaluationCategory category, String categoryLabel, AccountEvaluationOutcome outcome, String outcomeLabel, String updatedLabel, int updatedAt, String comment, int? quality, int? instructionFollowing
});




}
/// @nodoc
class __$AccountModelEvaluationCopyWithImpl<$Res>
    implements _$AccountModelEvaluationCopyWith<$Res> {
  __$AccountModelEvaluationCopyWithImpl(this._self, this._then);

  final _AccountModelEvaluation _self;
  final $Res Function(_AccountModelEvaluation) _then;

/// Create a copy of AccountModelEvaluation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? category = null,Object? categoryLabel = null,Object? outcome = null,Object? outcomeLabel = null,Object? updatedLabel = null,Object? updatedAt = null,Object? comment = null,Object? quality = freezed,Object? instructionFollowing = freezed,}) {
  return _then(_AccountModelEvaluation(
category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountEvaluationCategory,categoryLabel: null == categoryLabel ? _self.categoryLabel : categoryLabel // ignore: cast_nullable_to_non_nullable
as String,outcome: null == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AccountEvaluationOutcome,outcomeLabel: null == outcomeLabel ? _self.outcomeLabel : outcomeLabel // ignore: cast_nullable_to_non_nullable
as String,updatedLabel: null == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,comment: null == comment ? _self.comment : comment // ignore: cast_nullable_to_non_nullable
as String,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as int?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$AccountModelPriceTier {

 String get label; double get input; double get output; double? get cacheRead; double? get cacheWrite;
/// Create a copy of AccountModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelPriceTierCopyWith<AccountModelPriceTier> get copyWith => _$AccountModelPriceTierCopyWithImpl<AccountModelPriceTier>(this as AccountModelPriceTier, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelPriceTier;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelPriceTier&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.input, _this.input) || other.input == _this.input)&&(identical(other.output, _this.output) || other.output == _this.output)&&(identical(other.cacheRead, _this.cacheRead) || other.cacheRead == _this.cacheRead)&&(identical(other.cacheWrite, _this.cacheWrite) || other.cacheWrite == _this.cacheWrite));
}


@override
int get hashCode {
  final _this = this as AccountModelPriceTier;
  return Object.hash(runtimeType,_this.label,_this.input,_this.output,_this.cacheRead,_this.cacheWrite);
}

@override
String toString() {
  final _this = this as AccountModelPriceTier;
  return 'AccountModelPriceTier(label: ${_this.label}, input: ${_this.input}, output: ${_this.output}, cacheRead: ${_this.cacheRead}, cacheWrite: ${_this.cacheWrite})';
}


}

/// @nodoc
abstract mixin class $AccountModelPriceTierCopyWith<$Res>  {
  factory $AccountModelPriceTierCopyWith(AccountModelPriceTier value, $Res Function(AccountModelPriceTier) _then) = _$AccountModelPriceTierCopyWithImpl;
@useResult
$Res call({
 String label, double input, double output, double? cacheRead, double? cacheWrite
});




}
/// @nodoc
class _$AccountModelPriceTierCopyWithImpl<$Res>
    implements $AccountModelPriceTierCopyWith<$Res> {
  _$AccountModelPriceTierCopyWithImpl(this._self, this._then);

  final AccountModelPriceTier _self;
  final $Res Function(AccountModelPriceTier) _then;

/// Create a copy of AccountModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? input = null,Object? output = null,Object? cacheRead = freezed,Object? cacheWrite = freezed,}) {
  return _then(AccountModelPriceTier(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as double,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as double,cacheRead: freezed == cacheRead ? _self.cacheRead : cacheRead // ignore: cast_nullable_to_non_nullable
as double?,cacheWrite: freezed == cacheWrite ? _self.cacheWrite : cacheWrite // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountModelPriceTier].
extension AccountModelPriceTierPatterns on AccountModelPriceTier {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelPriceTier value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelPriceTier() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelPriceTier value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelPriceTier():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelPriceTier value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelPriceTier() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  double input,  double output,  double? cacheRead,  double? cacheWrite)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelPriceTier() when $default != null:
return $default(_that.label,_that.input,_that.output,_that.cacheRead,_that.cacheWrite);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  double input,  double output,  double? cacheRead,  double? cacheWrite)  $default,) {final _that = this;
switch (_that) {
case _AccountModelPriceTier():
return $default(_that.label,_that.input,_that.output,_that.cacheRead,_that.cacheWrite);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  double input,  double output,  double? cacheRead,  double? cacheWrite)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelPriceTier() when $default != null:
return $default(_that.label,_that.input,_that.output,_that.cacheRead,_that.cacheWrite);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelPriceTier implements AccountModelPriceTier {
  const _AccountModelPriceTier({required this.label, required this.input, required this.output, this.cacheRead, this.cacheWrite});


@override final  String label;
@override final  double input;
@override final  double output;
@override final  double? cacheRead;
@override final  double? cacheWrite;

/// Create a copy of AccountModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelPriceTierCopyWith<_AccountModelPriceTier> get copyWith => __$AccountModelPriceTierCopyWithImpl<_AccountModelPriceTier>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelPriceTier&&(identical(other.label, label) || other.label == label)&&(identical(other.input, input) || other.input == input)&&(identical(other.output, output) || other.output == output)&&(identical(other.cacheRead, cacheRead) || other.cacheRead == cacheRead)&&(identical(other.cacheWrite, cacheWrite) || other.cacheWrite == cacheWrite));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,input,output,cacheRead,cacheWrite);
}

@override
String toString() {
    return 'AccountModelPriceTier(label: $label, input: $input, output: $output, cacheRead: $cacheRead, cacheWrite: $cacheWrite)';
}


}

/// @nodoc
abstract mixin class _$AccountModelPriceTierCopyWith<$Res> implements $AccountModelPriceTierCopyWith<$Res> {
  factory _$AccountModelPriceTierCopyWith(_AccountModelPriceTier value, $Res Function(_AccountModelPriceTier) _then) = __$AccountModelPriceTierCopyWithImpl;
@override @useResult
$Res call({
 String label, double input, double output, double? cacheRead, double? cacheWrite
});




}
/// @nodoc
class __$AccountModelPriceTierCopyWithImpl<$Res>
    implements _$AccountModelPriceTierCopyWith<$Res> {
  __$AccountModelPriceTierCopyWithImpl(this._self, this._then);

  final _AccountModelPriceTier _self;
  final $Res Function(_AccountModelPriceTier) _then;

/// Create a copy of AccountModelPriceTier
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? input = null,Object? output = null,Object? cacheRead = freezed,Object? cacheWrite = freezed,}) {
  return _then(_AccountModelPriceTier(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,input: null == input ? _self.input : input // ignore: cast_nullable_to_non_nullable
as double,output: null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as double,cacheRead: freezed == cacheRead ? _self.cacheRead : cacheRead // ignore: cast_nullable_to_non_nullable
as double?,cacheWrite: freezed == cacheWrite ? _self.cacheWrite : cacheWrite // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

/// @nodoc
mixin _$AccountEvaluationFilter {

 AccountEvaluationOutcome? get outcome; AccountEvaluationCategory? get category; int? get minimumQuality; AccountEvaluationSort get sort;
/// Create a copy of AccountEvaluationFilter
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEvaluationFilterCopyWith<AccountEvaluationFilter> get copyWith => _$AccountEvaluationFilterCopyWithImpl<AccountEvaluationFilter>(this as AccountEvaluationFilter, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEvaluationFilter;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEvaluationFilter&&(identical(other.outcome, _this.outcome) || other.outcome == _this.outcome)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.minimumQuality, _this.minimumQuality) || other.minimumQuality == _this.minimumQuality)&&(identical(other.sort, _this.sort) || other.sort == _this.sort));
}


@override
int get hashCode {
  final _this = this as AccountEvaluationFilter;
  return Object.hash(runtimeType,_this.outcome,_this.category,_this.minimumQuality,_this.sort);
}

@override
String toString() {
  final _this = this as AccountEvaluationFilter;
  return 'AccountEvaluationFilter(outcome: ${_this.outcome}, category: ${_this.category}, minimumQuality: ${_this.minimumQuality}, sort: ${_this.sort})';
}


}

/// @nodoc
abstract mixin class $AccountEvaluationFilterCopyWith<$Res>  {
  factory $AccountEvaluationFilterCopyWith(AccountEvaluationFilter value, $Res Function(AccountEvaluationFilter) _then) = _$AccountEvaluationFilterCopyWithImpl;
@useResult
$Res call({
 AccountEvaluationOutcome? outcome, AccountEvaluationCategory? category, int? minimumQuality, AccountEvaluationSort sort
});




}
/// @nodoc
class _$AccountEvaluationFilterCopyWithImpl<$Res>
    implements $AccountEvaluationFilterCopyWith<$Res> {
  _$AccountEvaluationFilterCopyWithImpl(this._self, this._then);

  final AccountEvaluationFilter _self;
  final $Res Function(AccountEvaluationFilter) _then;

/// Create a copy of AccountEvaluationFilter
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outcome = freezed,Object? category = freezed,Object? minimumQuality = freezed,Object? sort = null,}) {
  return _then(AccountEvaluationFilter(
outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AccountEvaluationOutcome?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountEvaluationCategory?,minimumQuality: freezed == minimumQuality ? _self.minimumQuality : minimumQuality // ignore: cast_nullable_to_non_nullable
as int?,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as AccountEvaluationSort,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountEvaluationFilter].
extension AccountEvaluationFilterPatterns on AccountEvaluationFilter {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEvaluationFilter value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEvaluationFilter() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEvaluationFilter value)  $default,){
final _that = this;
switch (_that) {
case _AccountEvaluationFilter():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEvaluationFilter value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEvaluationFilter() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountEvaluationOutcome? outcome,  AccountEvaluationCategory? category,  int? minimumQuality,  AccountEvaluationSort sort)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEvaluationFilter() when $default != null:
return $default(_that.outcome,_that.category,_that.minimumQuality,_that.sort);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountEvaluationOutcome? outcome,  AccountEvaluationCategory? category,  int? minimumQuality,  AccountEvaluationSort sort)  $default,) {final _that = this;
switch (_that) {
case _AccountEvaluationFilter():
return $default(_that.outcome,_that.category,_that.minimumQuality,_that.sort);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountEvaluationOutcome? outcome,  AccountEvaluationCategory? category,  int? minimumQuality,  AccountEvaluationSort sort)?  $default,) {final _that = this;
switch (_that) {
case _AccountEvaluationFilter() when $default != null:
return $default(_that.outcome,_that.category,_that.minimumQuality,_that.sort);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEvaluationFilter implements AccountEvaluationFilter {
  const _AccountEvaluationFilter({this.outcome, this.category, this.minimumQuality, this.sort = AccountEvaluationSort.newest});


@override final  AccountEvaluationOutcome? outcome;
@override final  AccountEvaluationCategory? category;
@override final  int? minimumQuality;
@override@JsonKey() final  AccountEvaluationSort sort;

/// Create a copy of AccountEvaluationFilter
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEvaluationFilterCopyWith<_AccountEvaluationFilter> get copyWith => __$AccountEvaluationFilterCopyWithImpl<_AccountEvaluationFilter>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEvaluationFilter&&(identical(other.outcome, outcome) || other.outcome == outcome)&&(identical(other.category, category) || other.category == category)&&(identical(other.minimumQuality, minimumQuality) || other.minimumQuality == minimumQuality)&&(identical(other.sort, sort) || other.sort == sort));
}


@override
int get hashCode {
    return Object.hash(runtimeType,outcome,category,minimumQuality,sort);
}

@override
String toString() {
    return 'AccountEvaluationFilter(outcome: $outcome, category: $category, minimumQuality: $minimumQuality, sort: $sort)';
}


}

/// @nodoc
abstract mixin class _$AccountEvaluationFilterCopyWith<$Res> implements $AccountEvaluationFilterCopyWith<$Res> {
  factory _$AccountEvaluationFilterCopyWith(_AccountEvaluationFilter value, $Res Function(_AccountEvaluationFilter) _then) = __$AccountEvaluationFilterCopyWithImpl;
@override @useResult
$Res call({
 AccountEvaluationOutcome? outcome, AccountEvaluationCategory? category, int? minimumQuality, AccountEvaluationSort sort
});




}
/// @nodoc
class __$AccountEvaluationFilterCopyWithImpl<$Res>
    implements _$AccountEvaluationFilterCopyWith<$Res> {
  __$AccountEvaluationFilterCopyWithImpl(this._self, this._then);

  final _AccountEvaluationFilter _self;
  final $Res Function(_AccountEvaluationFilter) _then;

/// Create a copy of AccountEvaluationFilter
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outcome = freezed,Object? category = freezed,Object? minimumQuality = freezed,Object? sort = null,}) {
  return _then(_AccountEvaluationFilter(
outcome: freezed == outcome ? _self.outcome : outcome // ignore: cast_nullable_to_non_nullable
as AccountEvaluationOutcome?,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as AccountEvaluationCategory?,minimumQuality: freezed == minimumQuality ? _self.minimumQuality : minimumQuality // ignore: cast_nullable_to_non_nullable
as int?,sort: null == sort ? _self.sort : sort // ignore: cast_nullable_to_non_nullable
as AccountEvaluationSort,
  ));
}


}

/// @nodoc
mixin _$AccountEvaluationSummary {

 int get count; double? get quality; double? get instructionFollowing; Map<int, int> get qualityDistribution; List<AccountModelEvaluation> get visible; AccountEvaluationFilter get filter;
/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEvaluationSummaryCopyWith<AccountEvaluationSummary> get copyWith => _$AccountEvaluationSummaryCopyWithImpl<AccountEvaluationSummary>(this as AccountEvaluationSummary, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEvaluationSummary;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEvaluationSummary&&(identical(other.count, _this.count) || other.count == _this.count)&&(identical(other.quality, _this.quality) || other.quality == _this.quality)&&(identical(other.instructionFollowing, _this.instructionFollowing) || other.instructionFollowing == _this.instructionFollowing)&&const DeepCollectionEquality().equals(other.qualityDistribution, _this.qualityDistribution)&&const DeepCollectionEquality().equals(other.visible, _this.visible)&&(identical(other.filter, _this.filter) || other.filter == _this.filter));
}


@override
int get hashCode {
  final _this = this as AccountEvaluationSummary;
  return Object.hash(runtimeType,_this.count,_this.quality,_this.instructionFollowing,const DeepCollectionEquality().hash(_this.qualityDistribution),const DeepCollectionEquality().hash(_this.visible),_this.filter);
}

@override
String toString() {
  final _this = this as AccountEvaluationSummary;
  return 'AccountEvaluationSummary(count: ${_this.count}, quality: ${_this.quality}, instructionFollowing: ${_this.instructionFollowing}, qualityDistribution: ${_this.qualityDistribution}, visible: ${_this.visible}, filter: ${_this.filter})';
}


}

/// @nodoc
abstract mixin class $AccountEvaluationSummaryCopyWith<$Res>  {
  factory $AccountEvaluationSummaryCopyWith(AccountEvaluationSummary value, $Res Function(AccountEvaluationSummary) _then) = _$AccountEvaluationSummaryCopyWithImpl;
@useResult
$Res call({
 int count, double? quality, double? instructionFollowing, Map<int, int> qualityDistribution, List<AccountModelEvaluation> visible, AccountEvaluationFilter filter
});


$AccountEvaluationFilterCopyWith<$Res> get filter;

}
/// @nodoc
class _$AccountEvaluationSummaryCopyWithImpl<$Res>
    implements $AccountEvaluationSummaryCopyWith<$Res> {
  _$AccountEvaluationSummaryCopyWithImpl(this._self, this._then);

  final AccountEvaluationSummary _self;
  final $Res Function(AccountEvaluationSummary) _then;

/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? count = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? qualityDistribution = null,Object? visible = null,Object? filter = null,}) {
  return _then(AccountEvaluationSummary(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as double?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as double?,qualityDistribution: null == qualityDistribution ? _self.qualityDistribution : qualityDistribution // ignore: cast_nullable_to_non_nullable
as Map<int, int>,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as AccountEvaluationFilter,
  ));
}
/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEvaluationFilterCopyWith<$Res> get filter {

  return $AccountEvaluationFilterCopyWith<$Res>(_self.filter, (value) {
    return _then(_self.copyWith(filter: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountEvaluationSummary].
extension AccountEvaluationSummaryPatterns on AccountEvaluationSummary {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEvaluationSummary value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEvaluationSummary() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEvaluationSummary value)  $default,){
final _that = this;
switch (_that) {
case _AccountEvaluationSummary():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEvaluationSummary value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEvaluationSummary() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int count,  double? quality,  double? instructionFollowing,  Map<int, int> qualityDistribution,  List<AccountModelEvaluation> visible,  AccountEvaluationFilter filter)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEvaluationSummary() when $default != null:
return $default(_that.count,_that.quality,_that.instructionFollowing,_that.qualityDistribution,_that.visible,_that.filter);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int count,  double? quality,  double? instructionFollowing,  Map<int, int> qualityDistribution,  List<AccountModelEvaluation> visible,  AccountEvaluationFilter filter)  $default,) {final _that = this;
switch (_that) {
case _AccountEvaluationSummary():
return $default(_that.count,_that.quality,_that.instructionFollowing,_that.qualityDistribution,_that.visible,_that.filter);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int count,  double? quality,  double? instructionFollowing,  Map<int, int> qualityDistribution,  List<AccountModelEvaluation> visible,  AccountEvaluationFilter filter)?  $default,) {final _that = this;
switch (_that) {
case _AccountEvaluationSummary() when $default != null:
return $default(_that.count,_that.quality,_that.instructionFollowing,_that.qualityDistribution,_that.visible,_that.filter);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEvaluationSummary implements AccountEvaluationSummary {
  const _AccountEvaluationSummary({this.count = 0, this.quality, this.instructionFollowing,  Map<int, int> qualityDistribution = const <int, int>{},  List<AccountModelEvaluation> visible = const <AccountModelEvaluation>[], this.filter = const AccountEvaluationFilter()}): _qualityDistribution = qualityDistribution,_visible = visible;


@override@JsonKey() final  int count;
@override final  double? quality;
@override final  double? instructionFollowing;
 final  Map<int, int> _qualityDistribution;
@override@JsonKey() Map<int, int> get qualityDistribution {
  if (_qualityDistribution is EqualUnmodifiableMapView) return _qualityDistribution;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_qualityDistribution);
}

 final  List<AccountModelEvaluation> _visible;
@override@JsonKey() List<AccountModelEvaluation> get visible {
  if (_visible is EqualUnmodifiableListView) return _visible;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_visible);
}

@override@JsonKey() final  AccountEvaluationFilter filter;

/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEvaluationSummaryCopyWith<_AccountEvaluationSummary> get copyWith => __$AccountEvaluationSummaryCopyWithImpl<_AccountEvaluationSummary>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEvaluationSummary&&(identical(other.count, count) || other.count == count)&&(identical(other.quality, quality) || other.quality == quality)&&(identical(other.instructionFollowing, instructionFollowing) || other.instructionFollowing == instructionFollowing)&&const DeepCollectionEquality().equals(other.qualityDistribution, _qualityDistribution)&&const DeepCollectionEquality().equals(other.visible, _visible)&&(identical(other.filter, filter) || other.filter == filter));
}


@override
int get hashCode {
    return Object.hash(runtimeType,count,quality,instructionFollowing,const DeepCollectionEquality().hash(_qualityDistribution),const DeepCollectionEquality().hash(_visible),filter);
}

@override
String toString() {
    return 'AccountEvaluationSummary(count: $count, quality: $quality, instructionFollowing: $instructionFollowing, qualityDistribution: $qualityDistribution, visible: $visible, filter: $filter)';
}


}

/// @nodoc
abstract mixin class _$AccountEvaluationSummaryCopyWith<$Res> implements $AccountEvaluationSummaryCopyWith<$Res> {
  factory _$AccountEvaluationSummaryCopyWith(_AccountEvaluationSummary value, $Res Function(_AccountEvaluationSummary) _then) = __$AccountEvaluationSummaryCopyWithImpl;
@override @useResult
$Res call({
 int count, double? quality, double? instructionFollowing, Map<int, int> qualityDistribution, List<AccountModelEvaluation> visible, AccountEvaluationFilter filter
});


@override $AccountEvaluationFilterCopyWith<$Res> get filter;

}
/// @nodoc
class __$AccountEvaluationSummaryCopyWithImpl<$Res>
    implements _$AccountEvaluationSummaryCopyWith<$Res> {
  __$AccountEvaluationSummaryCopyWithImpl(this._self, this._then);

  final _AccountEvaluationSummary _self;
  final $Res Function(_AccountEvaluationSummary) _then;

/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? count = null,Object? quality = freezed,Object? instructionFollowing = freezed,Object? qualityDistribution = null,Object? visible = null,Object? filter = null,}) {
  return _then(_AccountEvaluationSummary(
count: null == count ? _self.count : count // ignore: cast_nullable_to_non_nullable
as int,quality: freezed == quality ? _self.quality : quality // ignore: cast_nullable_to_non_nullable
as double?,instructionFollowing: freezed == instructionFollowing ? _self.instructionFollowing : instructionFollowing // ignore: cast_nullable_to_non_nullable
as double?,qualityDistribution: null == qualityDistribution ? _self._qualityDistribution : qualityDistribution // ignore: cast_nullable_to_non_nullable
as Map<int, int>,visible: null == visible ? _self._visible : visible // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,filter: null == filter ? _self.filter : filter // ignore: cast_nullable_to_non_nullable
as AccountEvaluationFilter,
  ));
}

/// Create a copy of AccountEvaluationSummary
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEvaluationFilterCopyWith<$Res> get filter {

  return $AccountEvaluationFilterCopyWith<$Res>(_self.filter, (value) {
    return _then(_self.copyWith(filter: value));
  });
}
}

/// @nodoc
mixin _$AccountPerformancePresentation {

 int get sampleCount; int get ttftSampleCount; double? get tokensPerSecond; double? get averageTtftMillis; String? get updatedLabel;
/// Create a copy of AccountPerformancePresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountPerformancePresentationCopyWith<AccountPerformancePresentation> get copyWith => _$AccountPerformancePresentationCopyWithImpl<AccountPerformancePresentation>(this as AccountPerformancePresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountPerformancePresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountPerformancePresentation&&(identical(other.sampleCount, _this.sampleCount) || other.sampleCount == _this.sampleCount)&&(identical(other.ttftSampleCount, _this.ttftSampleCount) || other.ttftSampleCount == _this.ttftSampleCount)&&(identical(other.tokensPerSecond, _this.tokensPerSecond) || other.tokensPerSecond == _this.tokensPerSecond)&&(identical(other.averageTtftMillis, _this.averageTtftMillis) || other.averageTtftMillis == _this.averageTtftMillis)&&(identical(other.updatedLabel, _this.updatedLabel) || other.updatedLabel == _this.updatedLabel));
}


@override
int get hashCode {
  final _this = this as AccountPerformancePresentation;
  return Object.hash(runtimeType,_this.sampleCount,_this.ttftSampleCount,_this.tokensPerSecond,_this.averageTtftMillis,_this.updatedLabel);
}

@override
String toString() {
  final _this = this as AccountPerformancePresentation;
  return 'AccountPerformancePresentation(sampleCount: ${_this.sampleCount}, ttftSampleCount: ${_this.ttftSampleCount}, tokensPerSecond: ${_this.tokensPerSecond}, averageTtftMillis: ${_this.averageTtftMillis}, updatedLabel: ${_this.updatedLabel})';
}


}

/// @nodoc
abstract mixin class $AccountPerformancePresentationCopyWith<$Res>  {
  factory $AccountPerformancePresentationCopyWith(AccountPerformancePresentation value, $Res Function(AccountPerformancePresentation) _then) = _$AccountPerformancePresentationCopyWithImpl;
@useResult
$Res call({
 int sampleCount, int ttftSampleCount, double? tokensPerSecond, double? averageTtftMillis, String? updatedLabel
});




}
/// @nodoc
class _$AccountPerformancePresentationCopyWithImpl<$Res>
    implements $AccountPerformancePresentationCopyWith<$Res> {
  _$AccountPerformancePresentationCopyWithImpl(this._self, this._then);

  final AccountPerformancePresentation _self;
  final $Res Function(AccountPerformancePresentation) _then;

/// Create a copy of AccountPerformancePresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? sampleCount = null,Object? ttftSampleCount = null,Object? tokensPerSecond = freezed,Object? averageTtftMillis = freezed,Object? updatedLabel = freezed,}) {
  return _then(AccountPerformancePresentation(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,updatedLabel: freezed == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountPerformancePresentation].
extension AccountPerformancePresentationPatterns on AccountPerformancePresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountPerformancePresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountPerformancePresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountPerformancePresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountPerformancePresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountPerformancePresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountPerformancePresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int sampleCount,  int ttftSampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  String? updatedLabel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountPerformancePresentation() when $default != null:
return $default(_that.sampleCount,_that.ttftSampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.updatedLabel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int sampleCount,  int ttftSampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  String? updatedLabel)  $default,) {final _that = this;
switch (_that) {
case _AccountPerformancePresentation():
return $default(_that.sampleCount,_that.ttftSampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.updatedLabel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int sampleCount,  int ttftSampleCount,  double? tokensPerSecond,  double? averageTtftMillis,  String? updatedLabel)?  $default,) {final _that = this;
switch (_that) {
case _AccountPerformancePresentation() when $default != null:
return $default(_that.sampleCount,_that.ttftSampleCount,_that.tokensPerSecond,_that.averageTtftMillis,_that.updatedLabel);case _:
  return null;

}
}

}

/// @nodoc


class _AccountPerformancePresentation implements AccountPerformancePresentation {
  const _AccountPerformancePresentation({required this.sampleCount, required this.ttftSampleCount, this.tokensPerSecond, this.averageTtftMillis, this.updatedLabel});


@override final  int sampleCount;
@override final  int ttftSampleCount;
@override final  double? tokensPerSecond;
@override final  double? averageTtftMillis;
@override final  String? updatedLabel;

/// Create a copy of AccountPerformancePresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountPerformancePresentationCopyWith<_AccountPerformancePresentation> get copyWith => __$AccountPerformancePresentationCopyWithImpl<_AccountPerformancePresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountPerformancePresentation&&(identical(other.sampleCount, sampleCount) || other.sampleCount == sampleCount)&&(identical(other.ttftSampleCount, ttftSampleCount) || other.ttftSampleCount == ttftSampleCount)&&(identical(other.tokensPerSecond, tokensPerSecond) || other.tokensPerSecond == tokensPerSecond)&&(identical(other.averageTtftMillis, averageTtftMillis) || other.averageTtftMillis == averageTtftMillis)&&(identical(other.updatedLabel, updatedLabel) || other.updatedLabel == updatedLabel));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sampleCount,ttftSampleCount,tokensPerSecond,averageTtftMillis,updatedLabel);
}

@override
String toString() {
    return 'AccountPerformancePresentation(sampleCount: $sampleCount, ttftSampleCount: $ttftSampleCount, tokensPerSecond: $tokensPerSecond, averageTtftMillis: $averageTtftMillis, updatedLabel: $updatedLabel)';
}


}

/// @nodoc
abstract mixin class _$AccountPerformancePresentationCopyWith<$Res> implements $AccountPerformancePresentationCopyWith<$Res> {
  factory _$AccountPerformancePresentationCopyWith(_AccountPerformancePresentation value, $Res Function(_AccountPerformancePresentation) _then) = __$AccountPerformancePresentationCopyWithImpl;
@override @useResult
$Res call({
 int sampleCount, int ttftSampleCount, double? tokensPerSecond, double? averageTtftMillis, String? updatedLabel
});




}
/// @nodoc
class __$AccountPerformancePresentationCopyWithImpl<$Res>
    implements _$AccountPerformancePresentationCopyWith<$Res> {
  __$AccountPerformancePresentationCopyWithImpl(this._self, this._then);

  final _AccountPerformancePresentation _self;
  final $Res Function(_AccountPerformancePresentation) _then;

/// Create a copy of AccountPerformancePresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? sampleCount = null,Object? ttftSampleCount = null,Object? tokensPerSecond = freezed,Object? averageTtftMillis = freezed,Object? updatedLabel = freezed,}) {
  return _then(_AccountPerformancePresentation(
sampleCount: null == sampleCount ? _self.sampleCount : sampleCount // ignore: cast_nullable_to_non_nullable
as int,ttftSampleCount: null == ttftSampleCount ? _self.ttftSampleCount : ttftSampleCount // ignore: cast_nullable_to_non_nullable
as int,tokensPerSecond: freezed == tokensPerSecond ? _self.tokensPerSecond : tokensPerSecond // ignore: cast_nullable_to_non_nullable
as double?,averageTtftMillis: freezed == averageTtftMillis ? _self.averageTtftMillis : averageTtftMillis // ignore: cast_nullable_to_non_nullable
as double?,updatedLabel: freezed == updatedLabel ? _self.updatedLabel : updatedLabel // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountModelPresentation {

 AccountModelKey get key; String get name; AccountModelOrigin get origin; bool get enabled; bool get canToggle; bool get saving; String? get error; String? get summary; AccountModelSpecificationFacts get specificationFacts; List<AccountModelPriceTier> get priceTiers; String? get currency; String? get priceSource; String? get priceVerifiedLabel; AccountPerformancePresentation? get performance; List<AccountDisplayFact> get guidance; List<AccountModelEvaluation> get evaluations; AccountEvaluationSummary get evaluationSummary; bool get readoutLoading; String? get readoutError; bool get canLoadReadout; AccountConnection? get connection; List<AccountConnection> get allowedConnections; AccountCompactPresentation? get compact; bool get canEdit; bool get canDelete;
/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountModelPresentationCopyWith<AccountModelPresentation> get copyWith => _$AccountModelPresentationCopyWithImpl<AccountModelPresentation>(this as AccountModelPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountModelPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountModelPresentation&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.enabled, _this.enabled) || other.enabled == _this.enabled)&&(identical(other.canToggle, _this.canToggle) || other.canToggle == _this.canToggle)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.specificationFacts, _this.specificationFacts) || other.specificationFacts == _this.specificationFacts)&&const DeepCollectionEquality().equals(other.priceTiers, _this.priceTiers)&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.priceSource, _this.priceSource) || other.priceSource == _this.priceSource)&&(identical(other.priceVerifiedLabel, _this.priceVerifiedLabel) || other.priceVerifiedLabel == _this.priceVerifiedLabel)&&(identical(other.performance, _this.performance) || other.performance == _this.performance)&&const DeepCollectionEquality().equals(other.guidance, _this.guidance)&&const DeepCollectionEquality().equals(other.evaluations, _this.evaluations)&&(identical(other.evaluationSummary, _this.evaluationSummary) || other.evaluationSummary == _this.evaluationSummary)&&(identical(other.readoutLoading, _this.readoutLoading) || other.readoutLoading == _this.readoutLoading)&&(identical(other.readoutError, _this.readoutError) || other.readoutError == _this.readoutError)&&(identical(other.canLoadReadout, _this.canLoadReadout) || other.canLoadReadout == _this.canLoadReadout)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&const DeepCollectionEquality().equals(other.allowedConnections, _this.allowedConnections)&&(identical(other.compact, _this.compact) || other.compact == _this.compact)&&(identical(other.canEdit, _this.canEdit) || other.canEdit == _this.canEdit)&&(identical(other.canDelete, _this.canDelete) || other.canDelete == _this.canDelete));
}


@override
int get hashCode {
  final _this = this as AccountModelPresentation;
  return Object.hashAll([runtimeType,_this.key,_this.name,_this.origin,_this.enabled,_this.canToggle,_this.saving,_this.error,_this.summary,_this.specificationFacts,const DeepCollectionEquality().hash(_this.priceTiers),_this.currency,_this.priceSource,_this.priceVerifiedLabel,_this.performance,const DeepCollectionEquality().hash(_this.guidance),const DeepCollectionEquality().hash(_this.evaluations),_this.evaluationSummary,_this.readoutLoading,_this.readoutError,_this.canLoadReadout,_this.connection,const DeepCollectionEquality().hash(_this.allowedConnections),_this.compact,_this.canEdit,_this.canDelete]);
}

@override
String toString() {
  final _this = this as AccountModelPresentation;
  return 'AccountModelPresentation(key: ${_this.key}, name: ${_this.name}, origin: ${_this.origin}, enabled: ${_this.enabled}, canToggle: ${_this.canToggle}, saving: ${_this.saving}, error: ${_this.error}, summary: ${_this.summary}, specificationFacts: ${_this.specificationFacts}, priceTiers: ${_this.priceTiers}, currency: ${_this.currency}, priceSource: ${_this.priceSource}, priceVerifiedLabel: ${_this.priceVerifiedLabel}, performance: ${_this.performance}, guidance: ${_this.guidance}, evaluations: ${_this.evaluations}, evaluationSummary: ${_this.evaluationSummary}, readoutLoading: ${_this.readoutLoading}, readoutError: ${_this.readoutError}, canLoadReadout: ${_this.canLoadReadout}, connection: ${_this.connection}, allowedConnections: ${_this.allowedConnections}, compact: ${_this.compact}, canEdit: ${_this.canEdit}, canDelete: ${_this.canDelete})';
}


}

/// @nodoc
abstract mixin class $AccountModelPresentationCopyWith<$Res>  {
  factory $AccountModelPresentationCopyWith(AccountModelPresentation value, $Res Function(AccountModelPresentation) _then) = _$AccountModelPresentationCopyWithImpl;
@useResult
$Res call({
 AccountModelKey key, String name, AccountModelOrigin origin, bool enabled, bool canToggle, bool saving, String? error, String? summary, AccountModelSpecificationFacts specificationFacts, List<AccountModelPriceTier> priceTiers, String? currency, String? priceSource, String? priceVerifiedLabel, AccountPerformancePresentation? performance, List<AccountDisplayFact> guidance, List<AccountModelEvaluation> evaluations, AccountEvaluationSummary evaluationSummary, bool readoutLoading, String? readoutError, bool canLoadReadout, AccountConnection? connection, List<AccountConnection> allowedConnections, AccountCompactPresentation? compact, bool canEdit, bool canDelete
});


$AccountModelKeyCopyWith<$Res> get key;$AccountModelSpecificationFactsCopyWith<$Res> get specificationFacts;$AccountPerformancePresentationCopyWith<$Res>? get performance;$AccountEvaluationSummaryCopyWith<$Res> get evaluationSummary;$AccountCompactPresentationCopyWith<$Res>? get compact;

}
/// @nodoc
class _$AccountModelPresentationCopyWithImpl<$Res>
    implements $AccountModelPresentationCopyWith<$Res> {
  _$AccountModelPresentationCopyWithImpl(this._self, this._then);

  final AccountModelPresentation _self;
  final $Res Function(AccountModelPresentation) _then;

/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,Object? origin = null,Object? enabled = null,Object? canToggle = null,Object? saving = null,Object? error = freezed,Object? summary = freezed,Object? specificationFacts = null,Object? priceTiers = null,Object? currency = freezed,Object? priceSource = freezed,Object? priceVerifiedLabel = freezed,Object? performance = freezed,Object? guidance = null,Object? evaluations = null,Object? evaluationSummary = null,Object? readoutLoading = null,Object? readoutError = freezed,Object? canLoadReadout = null,Object? connection = freezed,Object? allowedConnections = null,Object? compact = freezed,Object? canEdit = null,Object? canDelete = null,}) {
  return _then(AccountModelPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountModelKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as AccountModelOrigin,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,canToggle: null == canToggle ? _self.canToggle : canToggle // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,specificationFacts: null == specificationFacts ? _self.specificationFacts : specificationFacts // ignore: cast_nullable_to_non_nullable
as AccountModelSpecificationFacts,priceTiers: null == priceTiers ? _self.priceTiers : priceTiers // ignore: cast_nullable_to_non_nullable
as List<AccountModelPriceTier>,currency: freezed == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String?,priceSource: freezed == priceSource ? _self.priceSource : priceSource // ignore: cast_nullable_to_non_nullable
as String?,priceVerifiedLabel: freezed == priceVerifiedLabel ? _self.priceVerifiedLabel : priceVerifiedLabel // ignore: cast_nullable_to_non_nullable
as String?,performance: freezed == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as AccountPerformancePresentation?,guidance: null == guidance ? _self.guidance : guidance // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,evaluations: null == evaluations ? _self.evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,evaluationSummary: null == evaluationSummary ? _self.evaluationSummary : evaluationSummary // ignore: cast_nullable_to_non_nullable
as AccountEvaluationSummary,readoutLoading: null == readoutLoading ? _self.readoutLoading : readoutLoading // ignore: cast_nullable_to_non_nullable
as bool,readoutError: freezed == readoutError ? _self.readoutError : readoutError // ignore: cast_nullable_to_non_nullable
as String?,canLoadReadout: null == canLoadReadout ? _self.canLoadReadout : canLoadReadout // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as AccountConnection?,allowedConnections: null == allowedConnections ? _self.allowedConnections : allowedConnections // ignore: cast_nullable_to_non_nullable
as List<AccountConnection>,compact: freezed == compact ? _self.compact : compact // ignore: cast_nullable_to_non_nullable
as AccountCompactPresentation?,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canDelete: null == canDelete ? _self.canDelete : canDelete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get key {

  return $AccountModelKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelSpecificationFactsCopyWith<$Res> get specificationFacts {

  return $AccountModelSpecificationFactsCopyWith<$Res>(_self.specificationFacts, (value) {
    return _then(_self.copyWith(specificationFacts: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountPerformancePresentationCopyWith<$Res>? get performance {
    if (_self.performance == null) {
    return null;
  }

  return $AccountPerformancePresentationCopyWith<$Res>(_self.performance!, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEvaluationSummaryCopyWith<$Res> get evaluationSummary {

  return $AccountEvaluationSummaryCopyWith<$Res>(_self.evaluationSummary, (value) {
    return _then(_self.copyWith(evaluationSummary: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCompactPresentationCopyWith<$Res>? get compact {
    if (_self.compact == null) {
    return null;
  }

  return $AccountCompactPresentationCopyWith<$Res>(_self.compact!, (value) {
    return _then(_self.copyWith(compact: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountModelPresentation].
extension AccountModelPresentationPatterns on AccountModelPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountModelPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountModelPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountModelPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountModelPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountModelPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountModelPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountModelKey key,  String name,  AccountModelOrigin origin,  bool enabled,  bool canToggle,  bool saving,  String? error,  String? summary,  AccountModelSpecificationFacts specificationFacts,  List<AccountModelPriceTier> priceTiers,  String? currency,  String? priceSource,  String? priceVerifiedLabel,  AccountPerformancePresentation? performance,  List<AccountDisplayFact> guidance,  List<AccountModelEvaluation> evaluations,  AccountEvaluationSummary evaluationSummary,  bool readoutLoading,  String? readoutError,  bool canLoadReadout,  AccountConnection? connection,  List<AccountConnection> allowedConnections,  AccountCompactPresentation? compact,  bool canEdit,  bool canDelete)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountModelPresentation() when $default != null:
return $default(_that.key,_that.name,_that.origin,_that.enabled,_that.canToggle,_that.saving,_that.error,_that.summary,_that.specificationFacts,_that.priceTiers,_that.currency,_that.priceSource,_that.priceVerifiedLabel,_that.performance,_that.guidance,_that.evaluations,_that.evaluationSummary,_that.readoutLoading,_that.readoutError,_that.canLoadReadout,_that.connection,_that.allowedConnections,_that.compact,_that.canEdit,_that.canDelete);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountModelKey key,  String name,  AccountModelOrigin origin,  bool enabled,  bool canToggle,  bool saving,  String? error,  String? summary,  AccountModelSpecificationFacts specificationFacts,  List<AccountModelPriceTier> priceTiers,  String? currency,  String? priceSource,  String? priceVerifiedLabel,  AccountPerformancePresentation? performance,  List<AccountDisplayFact> guidance,  List<AccountModelEvaluation> evaluations,  AccountEvaluationSummary evaluationSummary,  bool readoutLoading,  String? readoutError,  bool canLoadReadout,  AccountConnection? connection,  List<AccountConnection> allowedConnections,  AccountCompactPresentation? compact,  bool canEdit,  bool canDelete)  $default,) {final _that = this;
switch (_that) {
case _AccountModelPresentation():
return $default(_that.key,_that.name,_that.origin,_that.enabled,_that.canToggle,_that.saving,_that.error,_that.summary,_that.specificationFacts,_that.priceTiers,_that.currency,_that.priceSource,_that.priceVerifiedLabel,_that.performance,_that.guidance,_that.evaluations,_that.evaluationSummary,_that.readoutLoading,_that.readoutError,_that.canLoadReadout,_that.connection,_that.allowedConnections,_that.compact,_that.canEdit,_that.canDelete);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountModelKey key,  String name,  AccountModelOrigin origin,  bool enabled,  bool canToggle,  bool saving,  String? error,  String? summary,  AccountModelSpecificationFacts specificationFacts,  List<AccountModelPriceTier> priceTiers,  String? currency,  String? priceSource,  String? priceVerifiedLabel,  AccountPerformancePresentation? performance,  List<AccountDisplayFact> guidance,  List<AccountModelEvaluation> evaluations,  AccountEvaluationSummary evaluationSummary,  bool readoutLoading,  String? readoutError,  bool canLoadReadout,  AccountConnection? connection,  List<AccountConnection> allowedConnections,  AccountCompactPresentation? compact,  bool canEdit,  bool canDelete)?  $default,) {final _that = this;
switch (_that) {
case _AccountModelPresentation() when $default != null:
return $default(_that.key,_that.name,_that.origin,_that.enabled,_that.canToggle,_that.saving,_that.error,_that.summary,_that.specificationFacts,_that.priceTiers,_that.currency,_that.priceSource,_that.priceVerifiedLabel,_that.performance,_that.guidance,_that.evaluations,_that.evaluationSummary,_that.readoutLoading,_that.readoutError,_that.canLoadReadout,_that.connection,_that.allowedConnections,_that.compact,_that.canEdit,_that.canDelete);case _:
  return null;

}
}

}

/// @nodoc


class _AccountModelPresentation implements AccountModelPresentation {
  const _AccountModelPresentation({required this.key, required this.name, required this.origin, this.enabled = true, this.canToggle = false, this.saving = false, this.error, this.summary, this.specificationFacts = const AccountModelSpecificationFacts(),  List<AccountModelPriceTier> priceTiers = const <AccountModelPriceTier>[], this.currency, this.priceSource, this.priceVerifiedLabel, this.performance,  List<AccountDisplayFact> guidance = const <AccountDisplayFact>[],  List<AccountModelEvaluation> evaluations = const <AccountModelEvaluation>[], this.evaluationSummary = const AccountEvaluationSummary(), this.readoutLoading = false, this.readoutError, this.canLoadReadout = false, this.connection,  List<AccountConnection> allowedConnections = const <AccountConnection>[], this.compact, this.canEdit = false, this.canDelete = false}): _priceTiers = priceTiers,_guidance = guidance,_evaluations = evaluations,_allowedConnections = allowedConnections;


@override final  AccountModelKey key;
@override final  String name;
@override final  AccountModelOrigin origin;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool canToggle;
@override@JsonKey() final  bool saving;
@override final  String? error;
@override final  String? summary;
@override@JsonKey() final  AccountModelSpecificationFacts specificationFacts;
 final  List<AccountModelPriceTier> _priceTiers;
@override@JsonKey() List<AccountModelPriceTier> get priceTiers {
  if (_priceTiers is EqualUnmodifiableListView) return _priceTiers;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_priceTiers);
}

@override final  String? currency;
@override final  String? priceSource;
@override final  String? priceVerifiedLabel;
@override final  AccountPerformancePresentation? performance;
 final  List<AccountDisplayFact> _guidance;
@override@JsonKey() List<AccountDisplayFact> get guidance {
  if (_guidance is EqualUnmodifiableListView) return _guidance;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_guidance);
}

 final  List<AccountModelEvaluation> _evaluations;
@override@JsonKey() List<AccountModelEvaluation> get evaluations {
  if (_evaluations is EqualUnmodifiableListView) return _evaluations;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_evaluations);
}

@override@JsonKey() final  AccountEvaluationSummary evaluationSummary;
@override@JsonKey() final  bool readoutLoading;
@override final  String? readoutError;
@override@JsonKey() final  bool canLoadReadout;
@override final  AccountConnection? connection;
 final  List<AccountConnection> _allowedConnections;
@override@JsonKey() List<AccountConnection> get allowedConnections {
  if (_allowedConnections is EqualUnmodifiableListView) return _allowedConnections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_allowedConnections);
}

@override final  AccountCompactPresentation? compact;
@override@JsonKey() final  bool canEdit;
@override@JsonKey() final  bool canDelete;

/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountModelPresentationCopyWith<_AccountModelPresentation> get copyWith => __$AccountModelPresentationCopyWithImpl<_AccountModelPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountModelPresentation&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.origin, origin) || other.origin == origin)&&(identical(other.enabled, enabled) || other.enabled == enabled)&&(identical(other.canToggle, canToggle) || other.canToggle == canToggle)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.error, error) || other.error == error)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.specificationFacts, specificationFacts) || other.specificationFacts == specificationFacts)&&const DeepCollectionEquality().equals(other.priceTiers, _priceTiers)&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.priceSource, priceSource) || other.priceSource == priceSource)&&(identical(other.priceVerifiedLabel, priceVerifiedLabel) || other.priceVerifiedLabel == priceVerifiedLabel)&&(identical(other.performance, performance) || other.performance == performance)&&const DeepCollectionEquality().equals(other.guidance, _guidance)&&const DeepCollectionEquality().equals(other.evaluations, _evaluations)&&(identical(other.evaluationSummary, evaluationSummary) || other.evaluationSummary == evaluationSummary)&&(identical(other.readoutLoading, readoutLoading) || other.readoutLoading == readoutLoading)&&(identical(other.readoutError, readoutError) || other.readoutError == readoutError)&&(identical(other.canLoadReadout, canLoadReadout) || other.canLoadReadout == canLoadReadout)&&(identical(other.connection, connection) || other.connection == connection)&&const DeepCollectionEquality().equals(other.allowedConnections, _allowedConnections)&&(identical(other.compact, compact) || other.compact == compact)&&(identical(other.canEdit, canEdit) || other.canEdit == canEdit)&&(identical(other.canDelete, canDelete) || other.canDelete == canDelete));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,key,name,origin,enabled,canToggle,saving,error,summary,specificationFacts,const DeepCollectionEquality().hash(_priceTiers),currency,priceSource,priceVerifiedLabel,performance,const DeepCollectionEquality().hash(_guidance),const DeepCollectionEquality().hash(_evaluations),evaluationSummary,readoutLoading,readoutError,canLoadReadout,connection,const DeepCollectionEquality().hash(_allowedConnections),compact,canEdit,canDelete]);
}

@override
String toString() {
    return 'AccountModelPresentation(key: $key, name: $name, origin: $origin, enabled: $enabled, canToggle: $canToggle, saving: $saving, error: $error, summary: $summary, specificationFacts: $specificationFacts, priceTiers: $priceTiers, currency: $currency, priceSource: $priceSource, priceVerifiedLabel: $priceVerifiedLabel, performance: $performance, guidance: $guidance, evaluations: $evaluations, evaluationSummary: $evaluationSummary, readoutLoading: $readoutLoading, readoutError: $readoutError, canLoadReadout: $canLoadReadout, connection: $connection, allowedConnections: $allowedConnections, compact: $compact, canEdit: $canEdit, canDelete: $canDelete)';
}


}

/// @nodoc
abstract mixin class _$AccountModelPresentationCopyWith<$Res> implements $AccountModelPresentationCopyWith<$Res> {
  factory _$AccountModelPresentationCopyWith(_AccountModelPresentation value, $Res Function(_AccountModelPresentation) _then) = __$AccountModelPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountModelKey key, String name, AccountModelOrigin origin, bool enabled, bool canToggle, bool saving, String? error, String? summary, AccountModelSpecificationFacts specificationFacts, List<AccountModelPriceTier> priceTiers, String? currency, String? priceSource, String? priceVerifiedLabel, AccountPerformancePresentation? performance, List<AccountDisplayFact> guidance, List<AccountModelEvaluation> evaluations, AccountEvaluationSummary evaluationSummary, bool readoutLoading, String? readoutError, bool canLoadReadout, AccountConnection? connection, List<AccountConnection> allowedConnections, AccountCompactPresentation? compact, bool canEdit, bool canDelete
});


@override $AccountModelKeyCopyWith<$Res> get key;@override $AccountModelSpecificationFactsCopyWith<$Res> get specificationFacts;@override $AccountPerformancePresentationCopyWith<$Res>? get performance;@override $AccountEvaluationSummaryCopyWith<$Res> get evaluationSummary;@override $AccountCompactPresentationCopyWith<$Res>? get compact;

}
/// @nodoc
class __$AccountModelPresentationCopyWithImpl<$Res>
    implements _$AccountModelPresentationCopyWith<$Res> {
  __$AccountModelPresentationCopyWithImpl(this._self, this._then);

  final _AccountModelPresentation _self;
  final $Res Function(_AccountModelPresentation) _then;

/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,Object? origin = null,Object? enabled = null,Object? canToggle = null,Object? saving = null,Object? error = freezed,Object? summary = freezed,Object? specificationFacts = null,Object? priceTiers = null,Object? currency = freezed,Object? priceSource = freezed,Object? priceVerifiedLabel = freezed,Object? performance = freezed,Object? guidance = null,Object? evaluations = null,Object? evaluationSummary = null,Object? readoutLoading = null,Object? readoutError = freezed,Object? canLoadReadout = null,Object? connection = freezed,Object? allowedConnections = null,Object? compact = freezed,Object? canEdit = null,Object? canDelete = null,}) {
  return _then(_AccountModelPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountModelKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as AccountModelOrigin,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,canToggle: null == canToggle ? _self.canToggle : canToggle // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,specificationFacts: null == specificationFacts ? _self.specificationFacts : specificationFacts // ignore: cast_nullable_to_non_nullable
as AccountModelSpecificationFacts,priceTiers: null == priceTiers ? _self._priceTiers : priceTiers // ignore: cast_nullable_to_non_nullable
as List<AccountModelPriceTier>,currency: freezed == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String?,priceSource: freezed == priceSource ? _self.priceSource : priceSource // ignore: cast_nullable_to_non_nullable
as String?,priceVerifiedLabel: freezed == priceVerifiedLabel ? _self.priceVerifiedLabel : priceVerifiedLabel // ignore: cast_nullable_to_non_nullable
as String?,performance: freezed == performance ? _self.performance : performance // ignore: cast_nullable_to_non_nullable
as AccountPerformancePresentation?,guidance: null == guidance ? _self._guidance : guidance // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,evaluations: null == evaluations ? _self._evaluations : evaluations // ignore: cast_nullable_to_non_nullable
as List<AccountModelEvaluation>,evaluationSummary: null == evaluationSummary ? _self.evaluationSummary : evaluationSummary // ignore: cast_nullable_to_non_nullable
as AccountEvaluationSummary,readoutLoading: null == readoutLoading ? _self.readoutLoading : readoutLoading // ignore: cast_nullable_to_non_nullable
as bool,readoutError: freezed == readoutError ? _self.readoutError : readoutError // ignore: cast_nullable_to_non_nullable
as String?,canLoadReadout: null == canLoadReadout ? _self.canLoadReadout : canLoadReadout // ignore: cast_nullable_to_non_nullable
as bool,connection: freezed == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as AccountConnection?,allowedConnections: null == allowedConnections ? _self._allowedConnections : allowedConnections // ignore: cast_nullable_to_non_nullable
as List<AccountConnection>,compact: freezed == compact ? _self.compact : compact // ignore: cast_nullable_to_non_nullable
as AccountCompactPresentation?,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canDelete: null == canDelete ? _self.canDelete : canDelete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelKeyCopyWith<$Res> get key {

  return $AccountModelKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountModelSpecificationFactsCopyWith<$Res> get specificationFacts {

  return $AccountModelSpecificationFactsCopyWith<$Res>(_self.specificationFacts, (value) {
    return _then(_self.copyWith(specificationFacts: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountPerformancePresentationCopyWith<$Res>? get performance {
    if (_self.performance == null) {
    return null;
  }

  return $AccountPerformancePresentationCopyWith<$Res>(_self.performance!, (value) {
    return _then(_self.copyWith(performance: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountEvaluationSummaryCopyWith<$Res> get evaluationSummary {

  return $AccountEvaluationSummaryCopyWith<$Res>(_self.evaluationSummary, (value) {
    return _then(_self.copyWith(evaluationSummary: value));
  });
}/// Create a copy of AccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCompactPresentationCopyWith<$Res>? get compact {
    if (_self.compact == null) {
    return null;
  }

  return $AccountCompactPresentationCopyWith<$Res>(_self.compact!, (value) {
    return _then(_self.copyWith(compact: value));
  });
}
}

/// @nodoc
mixin _$AccountCatalogPresentation {

 List<AccountModelPresentation> get models; bool get canSync; bool get syncing; bool get canRetry; String? get checkedLabel; String? get sourceLabel; String? get error;
/// Create a copy of AccountCatalogPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountCatalogPresentationCopyWith<AccountCatalogPresentation> get copyWith => _$AccountCatalogPresentationCopyWithImpl<AccountCatalogPresentation>(this as AccountCatalogPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountCatalogPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountCatalogPresentation&&const DeepCollectionEquality().equals(other.models, _this.models)&&(identical(other.canSync, _this.canSync) || other.canSync == _this.canSync)&&(identical(other.syncing, _this.syncing) || other.syncing == _this.syncing)&&(identical(other.canRetry, _this.canRetry) || other.canRetry == _this.canRetry)&&(identical(other.checkedLabel, _this.checkedLabel) || other.checkedLabel == _this.checkedLabel)&&(identical(other.sourceLabel, _this.sourceLabel) || other.sourceLabel == _this.sourceLabel)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountCatalogPresentation;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.models),_this.canSync,_this.syncing,_this.canRetry,_this.checkedLabel,_this.sourceLabel,_this.error);
}

@override
String toString() {
  final _this = this as AccountCatalogPresentation;
  return 'AccountCatalogPresentation(models: ${_this.models}, canSync: ${_this.canSync}, syncing: ${_this.syncing}, canRetry: ${_this.canRetry}, checkedLabel: ${_this.checkedLabel}, sourceLabel: ${_this.sourceLabel}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountCatalogPresentationCopyWith<$Res>  {
  factory $AccountCatalogPresentationCopyWith(AccountCatalogPresentation value, $Res Function(AccountCatalogPresentation) _then) = _$AccountCatalogPresentationCopyWithImpl;
@useResult
$Res call({
 List<AccountModelPresentation> models, bool canSync, bool syncing, bool canRetry, String? checkedLabel, String? sourceLabel, String? error
});




}
/// @nodoc
class _$AccountCatalogPresentationCopyWithImpl<$Res>
    implements $AccountCatalogPresentationCopyWith<$Res> {
  _$AccountCatalogPresentationCopyWithImpl(this._self, this._then);

  final AccountCatalogPresentation _self;
  final $Res Function(AccountCatalogPresentation) _then;

/// Create a copy of AccountCatalogPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? models = null,Object? canSync = null,Object? syncing = null,Object? canRetry = null,Object? checkedLabel = freezed,Object? sourceLabel = freezed,Object? error = freezed,}) {
  return _then(AccountCatalogPresentation(
models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<AccountModelPresentation>,canSync: null == canSync ? _self.canSync : canSync // ignore: cast_nullable_to_non_nullable
as bool,syncing: null == syncing ? _self.syncing : syncing // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,checkedLabel: freezed == checkedLabel ? _self.checkedLabel : checkedLabel // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountCatalogPresentation].
extension AccountCatalogPresentationPatterns on AccountCatalogPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountCatalogPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountCatalogPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountCatalogPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountCatalogPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountCatalogPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountCatalogPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AccountModelPresentation> models,  bool canSync,  bool syncing,  bool canRetry,  String? checkedLabel,  String? sourceLabel,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountCatalogPresentation() when $default != null:
return $default(_that.models,_that.canSync,_that.syncing,_that.canRetry,_that.checkedLabel,_that.sourceLabel,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AccountModelPresentation> models,  bool canSync,  bool syncing,  bool canRetry,  String? checkedLabel,  String? sourceLabel,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountCatalogPresentation():
return $default(_that.models,_that.canSync,_that.syncing,_that.canRetry,_that.checkedLabel,_that.sourceLabel,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AccountModelPresentation> models,  bool canSync,  bool syncing,  bool canRetry,  String? checkedLabel,  String? sourceLabel,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountCatalogPresentation() when $default != null:
return $default(_that.models,_that.canSync,_that.syncing,_that.canRetry,_that.checkedLabel,_that.sourceLabel,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountCatalogPresentation implements AccountCatalogPresentation {
  const _AccountCatalogPresentation({ List<AccountModelPresentation> models = const <AccountModelPresentation>[], this.canSync = false, this.syncing = false, this.canRetry = false, this.checkedLabel, this.sourceLabel, this.error}): _models = models;


 final  List<AccountModelPresentation> _models;
@override@JsonKey() List<AccountModelPresentation> get models {
  if (_models is EqualUnmodifiableListView) return _models;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_models);
}

@override@JsonKey() final  bool canSync;
@override@JsonKey() final  bool syncing;
@override@JsonKey() final  bool canRetry;
@override final  String? checkedLabel;
@override final  String? sourceLabel;
@override final  String? error;

/// Create a copy of AccountCatalogPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountCatalogPresentationCopyWith<_AccountCatalogPresentation> get copyWith => __$AccountCatalogPresentationCopyWithImpl<_AccountCatalogPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountCatalogPresentation&&const DeepCollectionEquality().equals(other.models, _models)&&(identical(other.canSync, canSync) || other.canSync == canSync)&&(identical(other.syncing, syncing) || other.syncing == syncing)&&(identical(other.canRetry, canRetry) || other.canRetry == canRetry)&&(identical(other.checkedLabel, checkedLabel) || other.checkedLabel == checkedLabel)&&(identical(other.sourceLabel, sourceLabel) || other.sourceLabel == sourceLabel)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_models),canSync,syncing,canRetry,checkedLabel,sourceLabel,error);
}

@override
String toString() {
    return 'AccountCatalogPresentation(models: $models, canSync: $canSync, syncing: $syncing, canRetry: $canRetry, checkedLabel: $checkedLabel, sourceLabel: $sourceLabel, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountCatalogPresentationCopyWith<$Res> implements $AccountCatalogPresentationCopyWith<$Res> {
  factory _$AccountCatalogPresentationCopyWith(_AccountCatalogPresentation value, $Res Function(_AccountCatalogPresentation) _then) = __$AccountCatalogPresentationCopyWithImpl;
@override @useResult
$Res call({
 List<AccountModelPresentation> models, bool canSync, bool syncing, bool canRetry, String? checkedLabel, String? sourceLabel, String? error
});




}
/// @nodoc
class __$AccountCatalogPresentationCopyWithImpl<$Res>
    implements _$AccountCatalogPresentationCopyWith<$Res> {
  __$AccountCatalogPresentationCopyWithImpl(this._self, this._then);

  final _AccountCatalogPresentation _self;
  final $Res Function(_AccountCatalogPresentation) _then;

/// Create a copy of AccountCatalogPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? models = null,Object? canSync = null,Object? syncing = null,Object? canRetry = null,Object? checkedLabel = freezed,Object? sourceLabel = freezed,Object? error = freezed,}) {
  return _then(_AccountCatalogPresentation(
models: null == models ? _self._models : models // ignore: cast_nullable_to_non_nullable
as List<AccountModelPresentation>,canSync: null == canSync ? _self.canSync : canSync // ignore: cast_nullable_to_non_nullable
as bool,syncing: null == syncing ? _self.syncing : syncing // ignore: cast_nullable_to_non_nullable
as bool,canRetry: null == canRetry ? _self.canRetry : canRetry // ignore: cast_nullable_to_non_nullable
as bool,checkedLabel: freezed == checkedLabel ? _self.checkedLabel : checkedLabel // ignore: cast_nullable_to_non_nullable
as String?,sourceLabel: freezed == sourceLabel ? _self.sourceLabel : sourceLabel // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$NativeAccountDetailsPresentation {

 AccountAuthenticationMethod get authentication; bool get credentialReady; AccountBillingPresentation get billing; AccountCatalogPresentation get catalog; AccountUsagePresentation get usage; List<AccountDisplayFact> get advanced;
/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountDetailsPresentationCopyWith<NativeAccountDetailsPresentation> get copyWith => _$NativeAccountDetailsPresentationCopyWithImpl<NativeAccountDetailsPresentation>(this as NativeAccountDetailsPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NativeAccountDetailsPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountDetailsPresentation&&(identical(other.authentication, _this.authentication) || other.authentication == _this.authentication)&&(identical(other.credentialReady, _this.credentialReady) || other.credentialReady == _this.credentialReady)&&(identical(other.billing, _this.billing) || other.billing == _this.billing)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog)&&(identical(other.usage, _this.usage) || other.usage == _this.usage)&&const DeepCollectionEquality().equals(other.advanced, _this.advanced));
}


@override
int get hashCode {
  final _this = this as NativeAccountDetailsPresentation;
  return Object.hash(runtimeType,_this.authentication,_this.credentialReady,_this.billing,_this.catalog,_this.usage,const DeepCollectionEquality().hash(_this.advanced));
}

@override
String toString() {
  final _this = this as NativeAccountDetailsPresentation;
  return 'NativeAccountDetailsPresentation(authentication: ${_this.authentication}, credentialReady: ${_this.credentialReady}, billing: ${_this.billing}, catalog: ${_this.catalog}, usage: ${_this.usage}, advanced: ${_this.advanced})';
}


}

/// @nodoc
abstract mixin class $NativeAccountDetailsPresentationCopyWith<$Res>  {
  factory $NativeAccountDetailsPresentationCopyWith(NativeAccountDetailsPresentation value, $Res Function(NativeAccountDetailsPresentation) _then) = _$NativeAccountDetailsPresentationCopyWithImpl;
@useResult
$Res call({
 AccountAuthenticationMethod authentication, bool credentialReady, AccountBillingPresentation billing, AccountCatalogPresentation catalog, AccountUsagePresentation usage, List<AccountDisplayFact> advanced
});


$AccountBillingPresentationCopyWith<$Res> get billing;$AccountCatalogPresentationCopyWith<$Res> get catalog;$AccountUsagePresentationCopyWith<$Res> get usage;

}
/// @nodoc
class _$NativeAccountDetailsPresentationCopyWithImpl<$Res>
    implements $NativeAccountDetailsPresentationCopyWith<$Res> {
  _$NativeAccountDetailsPresentationCopyWithImpl(this._self, this._then);

  final NativeAccountDetailsPresentation _self;
  final $Res Function(NativeAccountDetailsPresentation) _then;

/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? authentication = null,Object? credentialReady = null,Object? billing = null,Object? catalog = null,Object? usage = null,Object? advanced = null,}) {
  return _then(NativeAccountDetailsPresentation(
authentication: null == authentication ? _self.authentication : authentication // ignore: cast_nullable_to_non_nullable
as AccountAuthenticationMethod,credentialReady: null == credentialReady ? _self.credentialReady : credentialReady // ignore: cast_nullable_to_non_nullable
as bool,billing: null == billing ? _self.billing : billing // ignore: cast_nullable_to_non_nullable
as AccountBillingPresentation,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogPresentation,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as AccountUsagePresentation,advanced: null == advanced ? _self.advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,
  ));
}
/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingPresentationCopyWith<$Res> get billing {

  return $AccountBillingPresentationCopyWith<$Res>(_self.billing, (value) {
    return _then(_self.copyWith(billing: value));
  });
}/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogPresentationCopyWith<$Res> get catalog {

  return $AccountCatalogPresentationCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsagePresentationCopyWith<$Res> get usage {

  return $AccountUsagePresentationCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}


/// Adds pattern-matching-related methods to [NativeAccountDetailsPresentation].
extension NativeAccountDetailsPresentationPatterns on NativeAccountDetailsPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NativeAccountDetailsPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NativeAccountDetailsPresentation value)  $default,){
final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NativeAccountDetailsPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountAuthenticationMethod authentication,  bool credentialReady,  AccountBillingPresentation billing,  AccountCatalogPresentation catalog,  AccountUsagePresentation usage,  List<AccountDisplayFact> advanced)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation() when $default != null:
return $default(_that.authentication,_that.credentialReady,_that.billing,_that.catalog,_that.usage,_that.advanced);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountAuthenticationMethod authentication,  bool credentialReady,  AccountBillingPresentation billing,  AccountCatalogPresentation catalog,  AccountUsagePresentation usage,  List<AccountDisplayFact> advanced)  $default,) {final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation():
return $default(_that.authentication,_that.credentialReady,_that.billing,_that.catalog,_that.usage,_that.advanced);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountAuthenticationMethod authentication,  bool credentialReady,  AccountBillingPresentation billing,  AccountCatalogPresentation catalog,  AccountUsagePresentation usage,  List<AccountDisplayFact> advanced)?  $default,) {final _that = this;
switch (_that) {
case _NativeAccountDetailsPresentation() when $default != null:
return $default(_that.authentication,_that.credentialReady,_that.billing,_that.catalog,_that.usage,_that.advanced);case _:
  return null;

}
}

}

/// @nodoc


class _NativeAccountDetailsPresentation implements NativeAccountDetailsPresentation {
  const _NativeAccountDetailsPresentation({required this.authentication, required this.credentialReady, required this.billing, required this.catalog, required this.usage,  List<AccountDisplayFact> advanced = const <AccountDisplayFact>[]}): _advanced = advanced;


@override final  AccountAuthenticationMethod authentication;
@override final  bool credentialReady;
@override final  AccountBillingPresentation billing;
@override final  AccountCatalogPresentation catalog;
@override final  AccountUsagePresentation usage;
 final  List<AccountDisplayFact> _advanced;
@override@JsonKey() List<AccountDisplayFact> get advanced {
  if (_advanced is EqualUnmodifiableListView) return _advanced;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_advanced);
}


/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NativeAccountDetailsPresentationCopyWith<_NativeAccountDetailsPresentation> get copyWith => __$NativeAccountDetailsPresentationCopyWithImpl<_NativeAccountDetailsPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NativeAccountDetailsPresentation&&(identical(other.authentication, authentication) || other.authentication == authentication)&&(identical(other.credentialReady, credentialReady) || other.credentialReady == credentialReady)&&(identical(other.billing, billing) || other.billing == billing)&&(identical(other.catalog, catalog) || other.catalog == catalog)&&(identical(other.usage, usage) || other.usage == usage)&&const DeepCollectionEquality().equals(other.advanced, _advanced));
}


@override
int get hashCode {
    return Object.hash(runtimeType,authentication,credentialReady,billing,catalog,usage,const DeepCollectionEquality().hash(_advanced));
}

@override
String toString() {
    return 'NativeAccountDetailsPresentation(authentication: $authentication, credentialReady: $credentialReady, billing: $billing, catalog: $catalog, usage: $usage, advanced: $advanced)';
}


}

/// @nodoc
abstract mixin class _$NativeAccountDetailsPresentationCopyWith<$Res> implements $NativeAccountDetailsPresentationCopyWith<$Res> {
  factory _$NativeAccountDetailsPresentationCopyWith(_NativeAccountDetailsPresentation value, $Res Function(_NativeAccountDetailsPresentation) _then) = __$NativeAccountDetailsPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountAuthenticationMethod authentication, bool credentialReady, AccountBillingPresentation billing, AccountCatalogPresentation catalog, AccountUsagePresentation usage, List<AccountDisplayFact> advanced
});


@override $AccountBillingPresentationCopyWith<$Res> get billing;@override $AccountCatalogPresentationCopyWith<$Res> get catalog;@override $AccountUsagePresentationCopyWith<$Res> get usage;

}
/// @nodoc
class __$NativeAccountDetailsPresentationCopyWithImpl<$Res>
    implements _$NativeAccountDetailsPresentationCopyWith<$Res> {
  __$NativeAccountDetailsPresentationCopyWithImpl(this._self, this._then);

  final _NativeAccountDetailsPresentation _self;
  final $Res Function(_NativeAccountDetailsPresentation) _then;

/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? authentication = null,Object? credentialReady = null,Object? billing = null,Object? catalog = null,Object? usage = null,Object? advanced = null,}) {
  return _then(_NativeAccountDetailsPresentation(
authentication: null == authentication ? _self.authentication : authentication // ignore: cast_nullable_to_non_nullable
as AccountAuthenticationMethod,credentialReady: null == credentialReady ? _self.credentialReady : credentialReady // ignore: cast_nullable_to_non_nullable
as bool,billing: null == billing ? _self.billing : billing // ignore: cast_nullable_to_non_nullable
as AccountBillingPresentation,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as AccountCatalogPresentation,usage: null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as AccountUsagePresentation,advanced: null == advanced ? _self._advanced : advanced // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,
  ));
}

/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingPresentationCopyWith<$Res> get billing {

  return $AccountBillingPresentationCopyWith<$Res>(_self.billing, (value) {
    return _then(_self.copyWith(billing: value));
  });
}/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountCatalogPresentationCopyWith<$Res> get catalog {

  return $AccountCatalogPresentationCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}/// Create a copy of NativeAccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsagePresentationCopyWith<$Res> get usage {

  return $AccountUsagePresentationCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}

/// @nodoc
mixin _$AcpLoginMethodPresentation {

 String get id; String get label;
/// Create a copy of AcpLoginMethodPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpLoginMethodPresentationCopyWith<AcpLoginMethodPresentation> get copyWith => _$AcpLoginMethodPresentationCopyWithImpl<AcpLoginMethodPresentation>(this as AcpLoginMethodPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpLoginMethodPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpLoginMethodPresentation&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.label, _this.label) || other.label == _this.label));
}


@override
int get hashCode {
  final _this = this as AcpLoginMethodPresentation;
  return Object.hash(runtimeType,_this.id,_this.label);
}

@override
String toString() {
  final _this = this as AcpLoginMethodPresentation;
  return 'AcpLoginMethodPresentation(id: ${_this.id}, label: ${_this.label})';
}


}

/// @nodoc
abstract mixin class $AcpLoginMethodPresentationCopyWith<$Res>  {
  factory $AcpLoginMethodPresentationCopyWith(AcpLoginMethodPresentation value, $Res Function(AcpLoginMethodPresentation) _then) = _$AcpLoginMethodPresentationCopyWithImpl;
@useResult
$Res call({
 String id, String label
});




}
/// @nodoc
class _$AcpLoginMethodPresentationCopyWithImpl<$Res>
    implements $AcpLoginMethodPresentationCopyWith<$Res> {
  _$AcpLoginMethodPresentationCopyWithImpl(this._self, this._then);

  final AcpLoginMethodPresentation _self;
  final $Res Function(AcpLoginMethodPresentation) _then;

/// Create a copy of AcpLoginMethodPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? label = null,}) {
  return _then(AcpLoginMethodPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpLoginMethodPresentation].
extension AcpLoginMethodPresentationPatterns on AcpLoginMethodPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpLoginMethodPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpLoginMethodPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpLoginMethodPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String label)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation() when $default != null:
return $default(_that.id,_that.label);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String label)  $default,) {final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation():
return $default(_that.id,_that.label);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String label)?  $default,) {final _that = this;
switch (_that) {
case _AcpLoginMethodPresentation() when $default != null:
return $default(_that.id,_that.label);case _:
  return null;

}
}

}

/// @nodoc


class _AcpLoginMethodPresentation implements AcpLoginMethodPresentation {
  const _AcpLoginMethodPresentation({required this.id, required this.label});


@override final  String id;
@override final  String label;

/// Create a copy of AcpLoginMethodPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpLoginMethodPresentationCopyWith<_AcpLoginMethodPresentation> get copyWith => __$AcpLoginMethodPresentationCopyWithImpl<_AcpLoginMethodPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpLoginMethodPresentation&&(identical(other.id, id) || other.id == id)&&(identical(other.label, label) || other.label == label));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,label);
}

@override
String toString() {
    return 'AcpLoginMethodPresentation(id: $id, label: $label)';
}


}

/// @nodoc
abstract mixin class _$AcpLoginMethodPresentationCopyWith<$Res> implements $AcpLoginMethodPresentationCopyWith<$Res> {
  factory _$AcpLoginMethodPresentationCopyWith(_AcpLoginMethodPresentation value, $Res Function(_AcpLoginMethodPresentation) _then) = __$AcpLoginMethodPresentationCopyWithImpl;
@override @useResult
$Res call({
 String id, String label
});




}
/// @nodoc
class __$AcpLoginMethodPresentationCopyWithImpl<$Res>
    implements _$AcpLoginMethodPresentationCopyWith<$Res> {
  __$AcpLoginMethodPresentationCopyWithImpl(this._self, this._then);

  final _AcpLoginMethodPresentation _self;
  final $Res Function(_AcpLoginMethodPresentation) _then;

/// Create a copy of AcpLoginMethodPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? label = null,}) {
  return _then(_AcpLoginMethodPresentation(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AcpAccountPresentation {

 AcpPresentationPhase get phase; String get status; String? get message; String? get error; double? get progress; String? get progressLabel; List<AccountDisplayFact> get facts; List<AcpAccountAction> get availableActions;/// Optional emphasis chosen by the VM, never inferred from [phase].
/// Must be an available operation, not cancellation or a documentation link.
 AcpAccountAction? get primaryAction; List<AcpLoginMethodPresentation> get loginMethods; String? get selectedLoginMethod; bool get canSelectLoginMethod;
/// Create a copy of AcpAccountPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<AcpAccountPresentation> get copyWith => _$AcpAccountPresentationCopyWithImpl<AcpAccountPresentation>(this as AcpAccountPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountPresentation&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.progressLabel, _this.progressLabel) || other.progressLabel == _this.progressLabel)&&const DeepCollectionEquality().equals(other.facts, _this.facts)&&const DeepCollectionEquality().equals(other.availableActions, _this.availableActions)&&(identical(other.primaryAction, _this.primaryAction) || other.primaryAction == _this.primaryAction)&&const DeepCollectionEquality().equals(other.loginMethods, _this.loginMethods)&&(identical(other.selectedLoginMethod, _this.selectedLoginMethod) || other.selectedLoginMethod == _this.selectedLoginMethod)&&(identical(other.canSelectLoginMethod, _this.canSelectLoginMethod) || other.canSelectLoginMethod == _this.canSelectLoginMethod));
}


@override
int get hashCode {
  final _this = this as AcpAccountPresentation;
  return Object.hash(runtimeType,_this.phase,_this.status,_this.message,_this.error,_this.progress,_this.progressLabel,const DeepCollectionEquality().hash(_this.facts),const DeepCollectionEquality().hash(_this.availableActions),_this.primaryAction,const DeepCollectionEquality().hash(_this.loginMethods),_this.selectedLoginMethod,_this.canSelectLoginMethod);
}

@override
String toString() {
  final _this = this as AcpAccountPresentation;
  return 'AcpAccountPresentation(phase: ${_this.phase}, status: ${_this.status}, message: ${_this.message}, error: ${_this.error}, progress: ${_this.progress}, progressLabel: ${_this.progressLabel}, facts: ${_this.facts}, availableActions: ${_this.availableActions}, primaryAction: ${_this.primaryAction}, loginMethods: ${_this.loginMethods}, selectedLoginMethod: ${_this.selectedLoginMethod}, canSelectLoginMethod: ${_this.canSelectLoginMethod})';
}


}

/// @nodoc
abstract mixin class $AcpAccountPresentationCopyWith<$Res>  {
  factory $AcpAccountPresentationCopyWith(AcpAccountPresentation value, $Res Function(AcpAccountPresentation) _then) = _$AcpAccountPresentationCopyWithImpl;
@useResult
$Res call({
 AcpPresentationPhase phase, String status, String? message, String? error, double? progress, String? progressLabel, List<AccountDisplayFact> facts, List<AcpAccountAction> availableActions, AcpAccountAction? primaryAction, List<AcpLoginMethodPresentation> loginMethods, String? selectedLoginMethod, bool canSelectLoginMethod
});




}
/// @nodoc
class _$AcpAccountPresentationCopyWithImpl<$Res>
    implements $AcpAccountPresentationCopyWith<$Res> {
  _$AcpAccountPresentationCopyWithImpl(this._self, this._then);

  final AcpAccountPresentation _self;
  final $Res Function(AcpAccountPresentation) _then;

/// Create a copy of AcpAccountPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? status = null,Object? message = freezed,Object? error = freezed,Object? progress = freezed,Object? progressLabel = freezed,Object? facts = null,Object? availableActions = null,Object? primaryAction = freezed,Object? loginMethods = null,Object? selectedLoginMethod = freezed,Object? canSelectLoginMethod = null,}) {
  return _then(AcpAccountPresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AcpPresentationPhase,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,progressLabel: freezed == progressLabel ? _self.progressLabel : progressLabel // ignore: cast_nullable_to_non_nullable
as String?,facts: null == facts ? _self.facts : facts // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,availableActions: null == availableActions ? _self.availableActions : availableActions // ignore: cast_nullable_to_non_nullable
as List<AcpAccountAction>,primaryAction: freezed == primaryAction ? _self.primaryAction : primaryAction // ignore: cast_nullable_to_non_nullable
as AcpAccountAction?,loginMethods: null == loginMethods ? _self.loginMethods : loginMethods // ignore: cast_nullable_to_non_nullable
as List<AcpLoginMethodPresentation>,selectedLoginMethod: freezed == selectedLoginMethod ? _self.selectedLoginMethod : selectedLoginMethod // ignore: cast_nullable_to_non_nullable
as String?,canSelectLoginMethod: null == canSelectLoginMethod ? _self.canSelectLoginMethod : canSelectLoginMethod // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAccountPresentation].
extension AcpAccountPresentationPatterns on AcpAccountPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpPresentationPhase phase,  String status,  String? message,  String? error,  double? progress,  String? progressLabel,  List<AccountDisplayFact> facts,  List<AcpAccountAction> availableActions,  AcpAccountAction? primaryAction,  List<AcpLoginMethodPresentation> loginMethods,  String? selectedLoginMethod,  bool canSelectLoginMethod)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountPresentation() when $default != null:
return $default(_that.phase,_that.status,_that.message,_that.error,_that.progress,_that.progressLabel,_that.facts,_that.availableActions,_that.primaryAction,_that.loginMethods,_that.selectedLoginMethod,_that.canSelectLoginMethod);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpPresentationPhase phase,  String status,  String? message,  String? error,  double? progress,  String? progressLabel,  List<AccountDisplayFact> facts,  List<AcpAccountAction> availableActions,  AcpAccountAction? primaryAction,  List<AcpLoginMethodPresentation> loginMethods,  String? selectedLoginMethod,  bool canSelectLoginMethod)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountPresentation():
return $default(_that.phase,_that.status,_that.message,_that.error,_that.progress,_that.progressLabel,_that.facts,_that.availableActions,_that.primaryAction,_that.loginMethods,_that.selectedLoginMethod,_that.canSelectLoginMethod);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpPresentationPhase phase,  String status,  String? message,  String? error,  double? progress,  String? progressLabel,  List<AccountDisplayFact> facts,  List<AcpAccountAction> availableActions,  AcpAccountAction? primaryAction,  List<AcpLoginMethodPresentation> loginMethods,  String? selectedLoginMethod,  bool canSelectLoginMethod)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountPresentation() when $default != null:
return $default(_that.phase,_that.status,_that.message,_that.error,_that.progress,_that.progressLabel,_that.facts,_that.availableActions,_that.primaryAction,_that.loginMethods,_that.selectedLoginMethod,_that.canSelectLoginMethod);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountPresentation extends AcpAccountPresentation {
  const _AcpAccountPresentation({required this.phase, required this.status, this.message, this.error, this.progress, this.progressLabel,  List<AccountDisplayFact> facts = const <AccountDisplayFact>[],  List<AcpAccountAction> availableActions = const <AcpAccountAction>[], this.primaryAction,  List<AcpLoginMethodPresentation> loginMethods = const <AcpLoginMethodPresentation>[], this.selectedLoginMethod, this.canSelectLoginMethod = false}): _facts = facts,_availableActions = availableActions,_loginMethods = loginMethods,super._();


@override final  AcpPresentationPhase phase;
@override final  String status;
@override final  String? message;
@override final  String? error;
@override final  double? progress;
@override final  String? progressLabel;
 final  List<AccountDisplayFact> _facts;
@override@JsonKey() List<AccountDisplayFact> get facts {
  if (_facts is EqualUnmodifiableListView) return _facts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_facts);
}

 final  List<AcpAccountAction> _availableActions;
@override@JsonKey() List<AcpAccountAction> get availableActions {
  if (_availableActions is EqualUnmodifiableListView) return _availableActions;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_availableActions);
}

/// Optional emphasis chosen by the VM, never inferred from [phase].
/// Must be an available operation, not cancellation or a documentation link.
@override final  AcpAccountAction? primaryAction;
 final  List<AcpLoginMethodPresentation> _loginMethods;
@override@JsonKey() List<AcpLoginMethodPresentation> get loginMethods {
  if (_loginMethods is EqualUnmodifiableListView) return _loginMethods;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_loginMethods);
}

@override final  String? selectedLoginMethod;
@override@JsonKey() final  bool canSelectLoginMethod;

/// Create a copy of AcpAccountPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountPresentationCopyWith<_AcpAccountPresentation> get copyWith => __$AcpAccountPresentationCopyWithImpl<_AcpAccountPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountPresentation&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.status, status) || other.status == status)&&(identical(other.message, message) || other.message == message)&&(identical(other.error, error) || other.error == error)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.progressLabel, progressLabel) || other.progressLabel == progressLabel)&&const DeepCollectionEquality().equals(other.facts, _facts)&&const DeepCollectionEquality().equals(other.availableActions, _availableActions)&&(identical(other.primaryAction, primaryAction) || other.primaryAction == primaryAction)&&const DeepCollectionEquality().equals(other.loginMethods, _loginMethods)&&(identical(other.selectedLoginMethod, selectedLoginMethod) || other.selectedLoginMethod == selectedLoginMethod)&&(identical(other.canSelectLoginMethod, canSelectLoginMethod) || other.canSelectLoginMethod == canSelectLoginMethod));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,status,message,error,progress,progressLabel,const DeepCollectionEquality().hash(_facts),const DeepCollectionEquality().hash(_availableActions),primaryAction,const DeepCollectionEquality().hash(_loginMethods),selectedLoginMethod,canSelectLoginMethod);
}

@override
String toString() {
    return 'AcpAccountPresentation(phase: $phase, status: $status, message: $message, error: $error, progress: $progress, progressLabel: $progressLabel, facts: $facts, availableActions: $availableActions, primaryAction: $primaryAction, loginMethods: $loginMethods, selectedLoginMethod: $selectedLoginMethod, canSelectLoginMethod: $canSelectLoginMethod)';
}


}

/// @nodoc
abstract mixin class _$AcpAccountPresentationCopyWith<$Res> implements $AcpAccountPresentationCopyWith<$Res> {
  factory _$AcpAccountPresentationCopyWith(_AcpAccountPresentation value, $Res Function(_AcpAccountPresentation) _then) = __$AcpAccountPresentationCopyWithImpl;
@override @useResult
$Res call({
 AcpPresentationPhase phase, String status, String? message, String? error, double? progress, String? progressLabel, List<AccountDisplayFact> facts, List<AcpAccountAction> availableActions, AcpAccountAction? primaryAction, List<AcpLoginMethodPresentation> loginMethods, String? selectedLoginMethod, bool canSelectLoginMethod
});




}
/// @nodoc
class __$AcpAccountPresentationCopyWithImpl<$Res>
    implements _$AcpAccountPresentationCopyWith<$Res> {
  __$AcpAccountPresentationCopyWithImpl(this._self, this._then);

  final _AcpAccountPresentation _self;
  final $Res Function(_AcpAccountPresentation) _then;

/// Create a copy of AcpAccountPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? status = null,Object? message = freezed,Object? error = freezed,Object? progress = freezed,Object? progressLabel = freezed,Object? facts = null,Object? availableActions = null,Object? primaryAction = freezed,Object? loginMethods = null,Object? selectedLoginMethod = freezed,Object? canSelectLoginMethod = null,}) {
  return _then(_AcpAccountPresentation(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as AcpPresentationPhase,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as String,message: freezed == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String?,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as double?,progressLabel: freezed == progressLabel ? _self.progressLabel : progressLabel // ignore: cast_nullable_to_non_nullable
as String?,facts: null == facts ? _self._facts : facts // ignore: cast_nullable_to_non_nullable
as List<AccountDisplayFact>,availableActions: null == availableActions ? _self._availableActions : availableActions // ignore: cast_nullable_to_non_nullable
as List<AcpAccountAction>,primaryAction: freezed == primaryAction ? _self.primaryAction : primaryAction // ignore: cast_nullable_to_non_nullable
as AcpAccountAction?,loginMethods: null == loginMethods ? _self._loginMethods : loginMethods // ignore: cast_nullable_to_non_nullable
as List<AcpLoginMethodPresentation>,selectedLoginMethod: freezed == selectedLoginMethod ? _self.selectedLoginMethod : selectedLoginMethod // ignore: cast_nullable_to_non_nullable
as String?,canSelectLoginMethod: null == canSelectLoginMethod ? _self.canSelectLoginMethod : canSelectLoginMethod // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AccountDetailsContent {

 Object get value;



@override
bool operator ==(Object other) {
  final _this = this as AccountDetailsContent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDetailsContent&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as AccountDetailsContent;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as AccountDetailsContent;
  return 'AccountDetailsContent(value: ${_this.value})';
}


}

/// @nodoc
class $AccountDetailsContentCopyWith<$Res>  {
$AccountDetailsContentCopyWith(AccountDetailsContent _, $Res Function(AccountDetailsContent) __);
}


/// Adds pattern-matching-related methods to [AccountDetailsContent].
extension AccountDetailsContentPatterns on AccountDetailsContent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( NativeAccountDetailsContent value)?  native,TResult Function( AcpAccountDetailsContent value)?  acp,required TResult orElse(),}){
final _that = this;
switch (_that) {
case NativeAccountDetailsContent() when native != null:
return native(_that);case AcpAccountDetailsContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( NativeAccountDetailsContent value)  native,required TResult Function( AcpAccountDetailsContent value)  acp,}){
final _that = this;
switch (_that) {
case NativeAccountDetailsContent():
return native(_that);case AcpAccountDetailsContent():
return acp(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( NativeAccountDetailsContent value)?  native,TResult? Function( AcpAccountDetailsContent value)?  acp,}){
final _that = this;
switch (_that) {
case NativeAccountDetailsContent() when native != null:
return native(_that);case AcpAccountDetailsContent() when acp != null:
return acp(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( NativeAccountDetailsPresentation value)?  native,TResult Function( AcpAccountPresentation value)?  acp,required TResult orElse(),}) {final _that = this;
switch (_that) {
case NativeAccountDetailsContent() when native != null:
return native(_that.value);case AcpAccountDetailsContent() when acp != null:
return acp(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( NativeAccountDetailsPresentation value)  native,required TResult Function( AcpAccountPresentation value)  acp,}) {final _that = this;
switch (_that) {
case NativeAccountDetailsContent():
return native(_that.value);case AcpAccountDetailsContent():
return acp(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( NativeAccountDetailsPresentation value)?  native,TResult? Function( AcpAccountPresentation value)?  acp,}) {final _that = this;
switch (_that) {
case NativeAccountDetailsContent() when native != null:
return native(_that.value);case AcpAccountDetailsContent() when acp != null:
return acp(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class NativeAccountDetailsContent implements AccountDetailsContent {
  const NativeAccountDetailsContent(this.value);


@override final  NativeAccountDetailsPresentation value;

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountDetailsContentCopyWith<NativeAccountDetailsContent> get copyWith => _$NativeAccountDetailsContentCopyWithImpl<NativeAccountDetailsContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountDetailsContent&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'AccountDetailsContent.native(value: $value)';
}


}

/// @nodoc
abstract mixin class $NativeAccountDetailsContentCopyWith<$Res> implements $AccountDetailsContentCopyWith<$Res> {
  factory $NativeAccountDetailsContentCopyWith(NativeAccountDetailsContent value, $Res Function(NativeAccountDetailsContent) _then) = _$NativeAccountDetailsContentCopyWithImpl;
@useResult
$Res call({
 NativeAccountDetailsPresentation value
});


$NativeAccountDetailsPresentationCopyWith<$Res> get value;

}
/// @nodoc
class _$NativeAccountDetailsContentCopyWithImpl<$Res>
    implements $NativeAccountDetailsContentCopyWith<$Res> {
  _$NativeAccountDetailsContentCopyWithImpl(this._self, this._then);

  final NativeAccountDetailsContent _self;
  final $Res Function(NativeAccountDetailsContent) _then;

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(NativeAccountDetailsContent(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as NativeAccountDetailsPresentation,
  ));
}

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NativeAccountDetailsPresentationCopyWith<$Res> get value {

  return $NativeAccountDetailsPresentationCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class AcpAccountDetailsContent implements AccountDetailsContent {
  const AcpAccountDetailsContent(this.value);


@override final  AcpAccountPresentation value;

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountDetailsContentCopyWith<AcpAccountDetailsContent> get copyWith => _$AcpAccountDetailsContentCopyWithImpl<AcpAccountDetailsContent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountDetailsContent&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'AccountDetailsContent.acp(value: $value)';
}


}

/// @nodoc
abstract mixin class $AcpAccountDetailsContentCopyWith<$Res> implements $AccountDetailsContentCopyWith<$Res> {
  factory $AcpAccountDetailsContentCopyWith(AcpAccountDetailsContent value, $Res Function(AcpAccountDetailsContent) _then) = _$AcpAccountDetailsContentCopyWithImpl;
@useResult
$Res call({
 AcpAccountPresentation value
});


$AcpAccountPresentationCopyWith<$Res> get value;

}
/// @nodoc
class _$AcpAccountDetailsContentCopyWithImpl<$Res>
    implements $AcpAccountDetailsContentCopyWith<$Res> {
  _$AcpAccountDetailsContentCopyWithImpl(this._self, this._then);

  final AcpAccountDetailsContent _self;
  final $Res Function(AcpAccountDetailsContent) _then;

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(AcpAccountDetailsContent(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AcpAccountPresentation,
  ));
}

/// Create a copy of AccountDetailsContent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<$Res> get value {

  return $AcpAccountPresentationCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AccountDetailsPresentation {

 AccountDisplayKey get key; String get name; AccountDetailsContent get content; String? get iconKey; String? get endpoint; bool get canEdit; bool get canDelete; bool get canSetDefault; bool get loading; String? get error;
/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountDetailsPresentationCopyWith<AccountDetailsPresentation> get copyWith => _$AccountDetailsPresentationCopyWithImpl<AccountDetailsPresentation>(this as AccountDetailsPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountDetailsPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountDetailsPresentation&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.content, _this.content) || other.content == _this.content)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.canEdit, _this.canEdit) || other.canEdit == _this.canEdit)&&(identical(other.canDelete, _this.canDelete) || other.canDelete == _this.canDelete)&&(identical(other.canSetDefault, _this.canSetDefault) || other.canSetDefault == _this.canSetDefault)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AccountDetailsPresentation;
  return Object.hash(runtimeType,_this.key,_this.name,_this.content,_this.iconKey,_this.endpoint,_this.canEdit,_this.canDelete,_this.canSetDefault,_this.loading,_this.error);
}

@override
String toString() {
  final _this = this as AccountDetailsPresentation;
  return 'AccountDetailsPresentation(key: ${_this.key}, name: ${_this.name}, content: ${_this.content}, iconKey: ${_this.iconKey}, endpoint: ${_this.endpoint}, canEdit: ${_this.canEdit}, canDelete: ${_this.canDelete}, canSetDefault: ${_this.canSetDefault}, loading: ${_this.loading}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AccountDetailsPresentationCopyWith<$Res>  {
  factory $AccountDetailsPresentationCopyWith(AccountDetailsPresentation value, $Res Function(AccountDetailsPresentation) _then) = _$AccountDetailsPresentationCopyWithImpl;
@useResult
$Res call({
 AccountDisplayKey key, String name, AccountDetailsContent content, String? iconKey, String? endpoint, bool canEdit, bool canDelete, bool canSetDefault, bool loading, String? error
});


$AccountDisplayKeyCopyWith<$Res> get key;$AccountDetailsContentCopyWith<$Res> get content;

}
/// @nodoc
class _$AccountDetailsPresentationCopyWithImpl<$Res>
    implements $AccountDetailsPresentationCopyWith<$Res> {
  _$AccountDetailsPresentationCopyWithImpl(this._self, this._then);

  final AccountDetailsPresentation _self;
  final $Res Function(AccountDetailsPresentation) _then;

/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? endpoint = freezed,Object? canEdit = null,Object? canDelete = null,Object? canSetDefault = null,Object? loading = null,Object? error = freezed,}) {
  return _then(AccountDetailsPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountDetailsContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,endpoint: freezed == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String?,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canDelete: null == canDelete ? _self.canDelete : canDelete // ignore: cast_nullable_to_non_nullable
as bool,canSetDefault: null == canSetDefault ? _self.canSetDefault : canSetDefault // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get key {

  return $AccountDisplayKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDetailsContentCopyWith<$Res> get content {

  return $AccountDetailsContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountDetailsPresentation].
extension AccountDetailsPresentationPatterns on AccountDetailsPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountDetailsPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountDetailsPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountDetailsPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountDetailsPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountDetailsPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountDetailsPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AccountDisplayKey key,  String name,  AccountDetailsContent content,  String? iconKey,  String? endpoint,  bool canEdit,  bool canDelete,  bool canSetDefault,  bool loading,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountDetailsPresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.endpoint,_that.canEdit,_that.canDelete,_that.canSetDefault,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AccountDisplayKey key,  String name,  AccountDetailsContent content,  String? iconKey,  String? endpoint,  bool canEdit,  bool canDelete,  bool canSetDefault,  bool loading,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AccountDetailsPresentation():
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.endpoint,_that.canEdit,_that.canDelete,_that.canSetDefault,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AccountDisplayKey key,  String name,  AccountDetailsContent content,  String? iconKey,  String? endpoint,  bool canEdit,  bool canDelete,  bool canSetDefault,  bool loading,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AccountDetailsPresentation() when $default != null:
return $default(_that.key,_that.name,_that.content,_that.iconKey,_that.endpoint,_that.canEdit,_that.canDelete,_that.canSetDefault,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AccountDetailsPresentation implements AccountDetailsPresentation {
  const _AccountDetailsPresentation({required this.key, required this.name, required this.content, this.iconKey, this.endpoint, this.canEdit = false, this.canDelete = false, this.canSetDefault = false, this.loading = false, this.error});


@override final  AccountDisplayKey key;
@override final  String name;
@override final  AccountDetailsContent content;
@override final  String? iconKey;
@override final  String? endpoint;
@override@JsonKey() final  bool canEdit;
@override@JsonKey() final  bool canDelete;
@override@JsonKey() final  bool canSetDefault;
@override@JsonKey() final  bool loading;
@override final  String? error;

/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountDetailsPresentationCopyWith<_AccountDetailsPresentation> get copyWith => __$AccountDetailsPresentationCopyWithImpl<_AccountDetailsPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountDetailsPresentation&&(identical(other.key, key) || other.key == key)&&(identical(other.name, name) || other.name == name)&&(identical(other.content, content) || other.content == content)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.canEdit, canEdit) || other.canEdit == canEdit)&&(identical(other.canDelete, canDelete) || other.canDelete == canDelete)&&(identical(other.canSetDefault, canSetDefault) || other.canSetDefault == canSetDefault)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,name,content,iconKey,endpoint,canEdit,canDelete,canSetDefault,loading,error);
}

@override
String toString() {
    return 'AccountDetailsPresentation(key: $key, name: $name, content: $content, iconKey: $iconKey, endpoint: $endpoint, canEdit: $canEdit, canDelete: $canDelete, canSetDefault: $canSetDefault, loading: $loading, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AccountDetailsPresentationCopyWith<$Res> implements $AccountDetailsPresentationCopyWith<$Res> {
  factory _$AccountDetailsPresentationCopyWith(_AccountDetailsPresentation value, $Res Function(_AccountDetailsPresentation) _then) = __$AccountDetailsPresentationCopyWithImpl;
@override @useResult
$Res call({
 AccountDisplayKey key, String name, AccountDetailsContent content, String? iconKey, String? endpoint, bool canEdit, bool canDelete, bool canSetDefault, bool loading, String? error
});


@override $AccountDisplayKeyCopyWith<$Res> get key;@override $AccountDetailsContentCopyWith<$Res> get content;

}
/// @nodoc
class __$AccountDetailsPresentationCopyWithImpl<$Res>
    implements _$AccountDetailsPresentationCopyWith<$Res> {
  __$AccountDetailsPresentationCopyWithImpl(this._self, this._then);

  final _AccountDetailsPresentation _self;
  final $Res Function(_AccountDetailsPresentation) _then;

/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? name = null,Object? content = null,Object? iconKey = freezed,Object? endpoint = freezed,Object? canEdit = null,Object? canDelete = null,Object? canSetDefault = null,Object? loading = null,Object? error = freezed,}) {
  return _then(_AccountDetailsPresentation(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,content: null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as AccountDetailsContent,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,endpoint: freezed == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as String?,canEdit: null == canEdit ? _self.canEdit : canEdit // ignore: cast_nullable_to_non_nullable
as bool,canDelete: null == canDelete ? _self.canDelete : canDelete // ignore: cast_nullable_to_non_nullable
as bool,canSetDefault: null == canSetDefault ? _self.canSetDefault : canSetDefault // ignore: cast_nullable_to_non_nullable
as bool,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res> get key {

  return $AccountDisplayKeyCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of AccountDetailsPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDetailsContentCopyWith<$Res> get content {

  return $AccountDetailsContentCopyWith<$Res>(_self.content, (value) {
    return _then(_self.copyWith(content: value));
  });
}
}

/// @nodoc
mixin _$AccountTextPresentation {

 String get raw; String? get error; String? get helper;
/// Create a copy of AccountTextPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<AccountTextPresentation> get copyWith => _$AccountTextPresentationCopyWithImpl<AccountTextPresentation>(this as AccountTextPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTextPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTextPresentation&&(identical(other.raw, _this.raw) || other.raw == _this.raw)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.helper, _this.helper) || other.helper == _this.helper));
}


@override
int get hashCode {
  final _this = this as AccountTextPresentation;
  return Object.hash(runtimeType,_this.raw,_this.error,_this.helper);
}

@override
String toString() {
  final _this = this as AccountTextPresentation;
  return 'AccountTextPresentation(raw: ${_this.raw}, error: ${_this.error}, helper: ${_this.helper})';
}


}

/// @nodoc
abstract mixin class $AccountTextPresentationCopyWith<$Res>  {
  factory $AccountTextPresentationCopyWith(AccountTextPresentation value, $Res Function(AccountTextPresentation) _then) = _$AccountTextPresentationCopyWithImpl;
@useResult
$Res call({
 String raw, String? error, String? helper
});




}
/// @nodoc
class _$AccountTextPresentationCopyWithImpl<$Res>
    implements $AccountTextPresentationCopyWith<$Res> {
  _$AccountTextPresentationCopyWithImpl(this._self, this._then);

  final AccountTextPresentation _self;
  final $Res Function(AccountTextPresentation) _then;

/// Create a copy of AccountTextPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? raw = null,Object? error = freezed,Object? helper = freezed,}) {
  return _then(AccountTextPresentation(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,helper: freezed == helper ? _self.helper : helper // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountTextPresentation].
extension AccountTextPresentationPatterns on AccountTextPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTextPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTextPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTextPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AccountTextPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTextPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTextPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String raw,  String? error,  String? helper)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTextPresentation() when $default != null:
return $default(_that.raw,_that.error,_that.helper);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String raw,  String? error,  String? helper)  $default,) {final _that = this;
switch (_that) {
case _AccountTextPresentation():
return $default(_that.raw,_that.error,_that.helper);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String raw,  String? error,  String? helper)?  $default,) {final _that = this;
switch (_that) {
case _AccountTextPresentation() when $default != null:
return $default(_that.raw,_that.error,_that.helper);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTextPresentation implements AccountTextPresentation {
  const _AccountTextPresentation({this.raw = '', this.error, this.helper});


@override@JsonKey() final  String raw;
@override final  String? error;
@override final  String? helper;

/// Create a copy of AccountTextPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTextPresentationCopyWith<_AccountTextPresentation> get copyWith => __$AccountTextPresentationCopyWithImpl<_AccountTextPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTextPresentation&&(identical(other.raw, raw) || other.raw == raw)&&(identical(other.error, error) || other.error == error)&&(identical(other.helper, helper) || other.helper == helper));
}


@override
int get hashCode {
    return Object.hash(runtimeType,raw,error,helper);
}

@override
String toString() {
    return 'AccountTextPresentation(raw: $raw, error: $error, helper: $helper)';
}


}

/// @nodoc
abstract mixin class _$AccountTextPresentationCopyWith<$Res> implements $AccountTextPresentationCopyWith<$Res> {
  factory _$AccountTextPresentationCopyWith(_AccountTextPresentation value, $Res Function(_AccountTextPresentation) _then) = __$AccountTextPresentationCopyWithImpl;
@override @useResult
$Res call({
 String raw, String? error, String? helper
});




}
/// @nodoc
class __$AccountTextPresentationCopyWithImpl<$Res>
    implements _$AccountTextPresentationCopyWith<$Res> {
  __$AccountTextPresentationCopyWithImpl(this._self, this._then);

  final _AccountTextPresentation _self;
  final $Res Function(_AccountTextPresentation) _then;

/// Create a copy of AccountTextPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? raw = null,Object? error = freezed,Object? helper = freezed,}) {
  return _then(_AccountTextPresentation(
raw: null == raw ? _self.raw : raw // ignore: cast_nullable_to_non_nullable
as String,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,helper: freezed == helper ? _self.helper : helper // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ManualAccountModelPresentation {

 String get editorKey; AccountTextPresentation get id; AccountTextPresentation get name; AccountTextPresentation get contextWindow; AccountTextPresentation get maxOutputTokens; AccountWireApi get wireApi; List<AccountWireApi> get allowedWireApis; AccountConnection get connection; List<AccountConnection> get allowedConnections; bool get canRemove; bool get canEditId; String? get error;
/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ManualAccountModelPresentationCopyWith<ManualAccountModelPresentation> get copyWith => _$ManualAccountModelPresentationCopyWithImpl<ManualAccountModelPresentation>(this as ManualAccountModelPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ManualAccountModelPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ManualAccountModelPresentation&&(identical(other.editorKey, _this.editorKey) || other.editorKey == _this.editorKey)&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.contextWindow, _this.contextWindow) || other.contextWindow == _this.contextWindow)&&(identical(other.maxOutputTokens, _this.maxOutputTokens) || other.maxOutputTokens == _this.maxOutputTokens)&&(identical(other.wireApi, _this.wireApi) || other.wireApi == _this.wireApi)&&const DeepCollectionEquality().equals(other.allowedWireApis, _this.allowedWireApis)&&(identical(other.connection, _this.connection) || other.connection == _this.connection)&&const DeepCollectionEquality().equals(other.allowedConnections, _this.allowedConnections)&&(identical(other.canRemove, _this.canRemove) || other.canRemove == _this.canRemove)&&(identical(other.canEditId, _this.canEditId) || other.canEditId == _this.canEditId)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ManualAccountModelPresentation;
  return Object.hash(runtimeType,_this.editorKey,_this.id,_this.name,_this.contextWindow,_this.maxOutputTokens,_this.wireApi,const DeepCollectionEquality().hash(_this.allowedWireApis),_this.connection,const DeepCollectionEquality().hash(_this.allowedConnections),_this.canRemove,_this.canEditId,_this.error);
}

@override
String toString() {
  final _this = this as ManualAccountModelPresentation;
  return 'ManualAccountModelPresentation(editorKey: ${_this.editorKey}, id: ${_this.id}, name: ${_this.name}, contextWindow: ${_this.contextWindow}, maxOutputTokens: ${_this.maxOutputTokens}, wireApi: ${_this.wireApi}, allowedWireApis: ${_this.allowedWireApis}, connection: ${_this.connection}, allowedConnections: ${_this.allowedConnections}, canRemove: ${_this.canRemove}, canEditId: ${_this.canEditId}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $ManualAccountModelPresentationCopyWith<$Res>  {
  factory $ManualAccountModelPresentationCopyWith(ManualAccountModelPresentation value, $Res Function(ManualAccountModelPresentation) _then) = _$ManualAccountModelPresentationCopyWithImpl;
@useResult
$Res call({
 String editorKey, AccountTextPresentation id, AccountTextPresentation name, AccountTextPresentation contextWindow, AccountTextPresentation maxOutputTokens, AccountWireApi wireApi, List<AccountWireApi> allowedWireApis, AccountConnection connection, List<AccountConnection> allowedConnections, bool canRemove, bool canEditId, String? error
});


$AccountTextPresentationCopyWith<$Res> get id;$AccountTextPresentationCopyWith<$Res> get name;$AccountTextPresentationCopyWith<$Res> get contextWindow;$AccountTextPresentationCopyWith<$Res> get maxOutputTokens;

}
/// @nodoc
class _$ManualAccountModelPresentationCopyWithImpl<$Res>
    implements $ManualAccountModelPresentationCopyWith<$Res> {
  _$ManualAccountModelPresentationCopyWithImpl(this._self, this._then);

  final ManualAccountModelPresentation _self;
  final $Res Function(ManualAccountModelPresentation) _then;

/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorKey = null,Object? id = null,Object? name = null,Object? contextWindow = null,Object? maxOutputTokens = null,Object? wireApi = null,Object? allowedWireApis = null,Object? connection = null,Object? allowedConnections = null,Object? canRemove = null,Object? canEditId = null,Object? error = freezed,}) {
  return _then(ManualAccountModelPresentation(
editorKey: null == editorKey ? _self.editorKey : editorKey // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,contextWindow: null == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,maxOutputTokens: null == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as AccountWireApi,allowedWireApis: null == allowedWireApis ? _self.allowedWireApis : allowedWireApis // ignore: cast_nullable_to_non_nullable
as List<AccountWireApi>,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as AccountConnection,allowedConnections: null == allowedConnections ? _self.allowedConnections : allowedConnections // ignore: cast_nullable_to_non_nullable
as List<AccountConnection>,canRemove: null == canRemove ? _self.canRemove : canRemove // ignore: cast_nullable_to_non_nullable
as bool,canEditId: null == canEditId ? _self.canEditId : canEditId // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get id {

  return $AccountTextPresentationCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get contextWindow {

  return $AccountTextPresentationCopyWith<$Res>(_self.contextWindow, (value) {
    return _then(_self.copyWith(contextWindow: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get maxOutputTokens {

  return $AccountTextPresentationCopyWith<$Res>(_self.maxOutputTokens, (value) {
    return _then(_self.copyWith(maxOutputTokens: value));
  });
}
}


/// Adds pattern-matching-related methods to [ManualAccountModelPresentation].
extension ManualAccountModelPresentationPatterns on ManualAccountModelPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ManualAccountModelPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ManualAccountModelPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ManualAccountModelPresentation value)  $default,){
final _that = this;
switch (_that) {
case _ManualAccountModelPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ManualAccountModelPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _ManualAccountModelPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String editorKey,  AccountTextPresentation id,  AccountTextPresentation name,  AccountTextPresentation contextWindow,  AccountTextPresentation maxOutputTokens,  AccountWireApi wireApi,  List<AccountWireApi> allowedWireApis,  AccountConnection connection,  List<AccountConnection> allowedConnections,  bool canRemove,  bool canEditId,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ManualAccountModelPresentation() when $default != null:
return $default(_that.editorKey,_that.id,_that.name,_that.contextWindow,_that.maxOutputTokens,_that.wireApi,_that.allowedWireApis,_that.connection,_that.allowedConnections,_that.canRemove,_that.canEditId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String editorKey,  AccountTextPresentation id,  AccountTextPresentation name,  AccountTextPresentation contextWindow,  AccountTextPresentation maxOutputTokens,  AccountWireApi wireApi,  List<AccountWireApi> allowedWireApis,  AccountConnection connection,  List<AccountConnection> allowedConnections,  bool canRemove,  bool canEditId,  String? error)  $default,) {final _that = this;
switch (_that) {
case _ManualAccountModelPresentation():
return $default(_that.editorKey,_that.id,_that.name,_that.contextWindow,_that.maxOutputTokens,_that.wireApi,_that.allowedWireApis,_that.connection,_that.allowedConnections,_that.canRemove,_that.canEditId,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String editorKey,  AccountTextPresentation id,  AccountTextPresentation name,  AccountTextPresentation contextWindow,  AccountTextPresentation maxOutputTokens,  AccountWireApi wireApi,  List<AccountWireApi> allowedWireApis,  AccountConnection connection,  List<AccountConnection> allowedConnections,  bool canRemove,  bool canEditId,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _ManualAccountModelPresentation() when $default != null:
return $default(_that.editorKey,_that.id,_that.name,_that.contextWindow,_that.maxOutputTokens,_that.wireApi,_that.allowedWireApis,_that.connection,_that.allowedConnections,_that.canRemove,_that.canEditId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ManualAccountModelPresentation implements ManualAccountModelPresentation {
  const _ManualAccountModelPresentation({required this.editorKey, required this.id, required this.name, required this.contextWindow, required this.maxOutputTokens, required this.wireApi,  List<AccountWireApi> allowedWireApis = const <AccountWireApi>[], required this.connection,  List<AccountConnection> allowedConnections = const <AccountConnection>[], this.canRemove = false, this.canEditId = false, this.error}): _allowedWireApis = allowedWireApis,_allowedConnections = allowedConnections;


@override final  String editorKey;
@override final  AccountTextPresentation id;
@override final  AccountTextPresentation name;
@override final  AccountTextPresentation contextWindow;
@override final  AccountTextPresentation maxOutputTokens;
@override final  AccountWireApi wireApi;
 final  List<AccountWireApi> _allowedWireApis;
@override@JsonKey() List<AccountWireApi> get allowedWireApis {
  if (_allowedWireApis is EqualUnmodifiableListView) return _allowedWireApis;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_allowedWireApis);
}

@override final  AccountConnection connection;
 final  List<AccountConnection> _allowedConnections;
@override@JsonKey() List<AccountConnection> get allowedConnections {
  if (_allowedConnections is EqualUnmodifiableListView) return _allowedConnections;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_allowedConnections);
}

@override@JsonKey() final  bool canRemove;
@override@JsonKey() final  bool canEditId;
@override final  String? error;

/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ManualAccountModelPresentationCopyWith<_ManualAccountModelPresentation> get copyWith => __$ManualAccountModelPresentationCopyWithImpl<_ManualAccountModelPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ManualAccountModelPresentation&&(identical(other.editorKey, editorKey) || other.editorKey == editorKey)&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.contextWindow, contextWindow) || other.contextWindow == contextWindow)&&(identical(other.maxOutputTokens, maxOutputTokens) || other.maxOutputTokens == maxOutputTokens)&&(identical(other.wireApi, wireApi) || other.wireApi == wireApi)&&const DeepCollectionEquality().equals(other.allowedWireApis, _allowedWireApis)&&(identical(other.connection, connection) || other.connection == connection)&&const DeepCollectionEquality().equals(other.allowedConnections, _allowedConnections)&&(identical(other.canRemove, canRemove) || other.canRemove == canRemove)&&(identical(other.canEditId, canEditId) || other.canEditId == canEditId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorKey,id,name,contextWindow,maxOutputTokens,wireApi,const DeepCollectionEquality().hash(_allowedWireApis),connection,const DeepCollectionEquality().hash(_allowedConnections),canRemove,canEditId,error);
}

@override
String toString() {
    return 'ManualAccountModelPresentation(editorKey: $editorKey, id: $id, name: $name, contextWindow: $contextWindow, maxOutputTokens: $maxOutputTokens, wireApi: $wireApi, allowedWireApis: $allowedWireApis, connection: $connection, allowedConnections: $allowedConnections, canRemove: $canRemove, canEditId: $canEditId, error: $error)';
}


}

/// @nodoc
abstract mixin class _$ManualAccountModelPresentationCopyWith<$Res> implements $ManualAccountModelPresentationCopyWith<$Res> {
  factory _$ManualAccountModelPresentationCopyWith(_ManualAccountModelPresentation value, $Res Function(_ManualAccountModelPresentation) _then) = __$ManualAccountModelPresentationCopyWithImpl;
@override @useResult
$Res call({
 String editorKey, AccountTextPresentation id, AccountTextPresentation name, AccountTextPresentation contextWindow, AccountTextPresentation maxOutputTokens, AccountWireApi wireApi, List<AccountWireApi> allowedWireApis, AccountConnection connection, List<AccountConnection> allowedConnections, bool canRemove, bool canEditId, String? error
});


@override $AccountTextPresentationCopyWith<$Res> get id;@override $AccountTextPresentationCopyWith<$Res> get name;@override $AccountTextPresentationCopyWith<$Res> get contextWindow;@override $AccountTextPresentationCopyWith<$Res> get maxOutputTokens;

}
/// @nodoc
class __$ManualAccountModelPresentationCopyWithImpl<$Res>
    implements _$ManualAccountModelPresentationCopyWith<$Res> {
  __$ManualAccountModelPresentationCopyWithImpl(this._self, this._then);

  final _ManualAccountModelPresentation _self;
  final $Res Function(_ManualAccountModelPresentation) _then;

/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorKey = null,Object? id = null,Object? name = null,Object? contextWindow = null,Object? maxOutputTokens = null,Object? wireApi = null,Object? allowedWireApis = null,Object? connection = null,Object? allowedConnections = null,Object? canRemove = null,Object? canEditId = null,Object? error = freezed,}) {
  return _then(_ManualAccountModelPresentation(
editorKey: null == editorKey ? _self.editorKey : editorKey // ignore: cast_nullable_to_non_nullable
as String,id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,contextWindow: null == contextWindow ? _self.contextWindow : contextWindow // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,maxOutputTokens: null == maxOutputTokens ? _self.maxOutputTokens : maxOutputTokens // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,wireApi: null == wireApi ? _self.wireApi : wireApi // ignore: cast_nullable_to_non_nullable
as AccountWireApi,allowedWireApis: null == allowedWireApis ? _self._allowedWireApis : allowedWireApis // ignore: cast_nullable_to_non_nullable
as List<AccountWireApi>,connection: null == connection ? _self.connection : connection // ignore: cast_nullable_to_non_nullable
as AccountConnection,allowedConnections: null == allowedConnections ? _self._allowedConnections : allowedConnections // ignore: cast_nullable_to_non_nullable
as List<AccountConnection>,canRemove: null == canRemove ? _self.canRemove : canRemove // ignore: cast_nullable_to_non_nullable
as bool,canEditId: null == canEditId ? _self.canEditId : canEditId // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get id {

  return $AccountTextPresentationCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get contextWindow {

  return $AccountTextPresentationCopyWith<$Res>(_self.contextWindow, (value) {
    return _then(_self.copyWith(contextWindow: value));
  });
}/// Create a copy of ManualAccountModelPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get maxOutputTokens {

  return $AccountTextPresentationCopyWith<$Res>(_self.maxOutputTokens, (value) {
    return _then(_self.copyWith(maxOutputTokens: value));
  });
}
}

/// @nodoc
mixin _$NativeAccountEditorPresentation {

 String get editorId; AccountDisplayKey? get accountKey; AccountTemplateKey get templateKey; List<AccountTemplatePresentation> get templates; AccountTextPresentation get name; AccountTextPresentation get endpoint; AccountTextPresentation get credential; AccountAuthenticationMethod get authentication; bool get isOpenAiTemplate; ChatGptLoginSnapshot? get chatGptLogin; ChatGptAccountInfo? get savedChatGptAccount; String get protocolLabel; bool get canChangeTemplate; bool get hasStoredCredential; bool get credentialRequired; bool get dirty; bool get saving; bool get canSave; bool get canAddModel; bool get setDefaultOnCreate; bool get showSetDefaultOnCreate; List<ManualAccountModelPresentation> get manualModels; List<AccountModelPresentation> get declaredModels; AccountBillingPresentation get billing; String? get error;
/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NativeAccountEditorPresentationCopyWith<NativeAccountEditorPresentation> get copyWith => _$NativeAccountEditorPresentationCopyWithImpl<NativeAccountEditorPresentation>(this as NativeAccountEditorPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NativeAccountEditorPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NativeAccountEditorPresentation&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.accountKey, _this.accountKey) || other.accountKey == _this.accountKey)&&(identical(other.templateKey, _this.templateKey) || other.templateKey == _this.templateKey)&&const DeepCollectionEquality().equals(other.templates, _this.templates)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.endpoint, _this.endpoint) || other.endpoint == _this.endpoint)&&(identical(other.credential, _this.credential) || other.credential == _this.credential)&&(identical(other.authentication, _this.authentication) || other.authentication == _this.authentication)&&(identical(other.isOpenAiTemplate, _this.isOpenAiTemplate) || other.isOpenAiTemplate == _this.isOpenAiTemplate)&&(identical(other.chatGptLogin, _this.chatGptLogin) || other.chatGptLogin == _this.chatGptLogin)&&(identical(other.savedChatGptAccount, _this.savedChatGptAccount) || other.savedChatGptAccount == _this.savedChatGptAccount)&&(identical(other.protocolLabel, _this.protocolLabel) || other.protocolLabel == _this.protocolLabel)&&(identical(other.canChangeTemplate, _this.canChangeTemplate) || other.canChangeTemplate == _this.canChangeTemplate)&&(identical(other.hasStoredCredential, _this.hasStoredCredential) || other.hasStoredCredential == _this.hasStoredCredential)&&(identical(other.credentialRequired, _this.credentialRequired) || other.credentialRequired == _this.credentialRequired)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.canSave, _this.canSave) || other.canSave == _this.canSave)&&(identical(other.canAddModel, _this.canAddModel) || other.canAddModel == _this.canAddModel)&&(identical(other.setDefaultOnCreate, _this.setDefaultOnCreate) || other.setDefaultOnCreate == _this.setDefaultOnCreate)&&(identical(other.showSetDefaultOnCreate, _this.showSetDefaultOnCreate) || other.showSetDefaultOnCreate == _this.showSetDefaultOnCreate)&&const DeepCollectionEquality().equals(other.manualModels, _this.manualModels)&&const DeepCollectionEquality().equals(other.declaredModels, _this.declaredModels)&&(identical(other.billing, _this.billing) || other.billing == _this.billing)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as NativeAccountEditorPresentation;
  return Object.hashAll([runtimeType,_this.editorId,_this.accountKey,_this.templateKey,const DeepCollectionEquality().hash(_this.templates),_this.name,_this.endpoint,_this.credential,_this.authentication,_this.isOpenAiTemplate,_this.chatGptLogin,_this.savedChatGptAccount,_this.protocolLabel,_this.canChangeTemplate,_this.hasStoredCredential,_this.credentialRequired,_this.dirty,_this.saving,_this.canSave,_this.canAddModel,_this.setDefaultOnCreate,_this.showSetDefaultOnCreate,const DeepCollectionEquality().hash(_this.manualModels),const DeepCollectionEquality().hash(_this.declaredModels),_this.billing,_this.error]);
}

@override
String toString() {
  final _this = this as NativeAccountEditorPresentation;
  return 'NativeAccountEditorPresentation(editorId: ${_this.editorId}, accountKey: ${_this.accountKey}, templateKey: ${_this.templateKey}, templates: ${_this.templates}, name: ${_this.name}, endpoint: ${_this.endpoint}, credential: ${_this.credential}, authentication: ${_this.authentication}, isOpenAiTemplate: ${_this.isOpenAiTemplate}, chatGptLogin: ${_this.chatGptLogin}, savedChatGptAccount: ${_this.savedChatGptAccount}, protocolLabel: ${_this.protocolLabel}, canChangeTemplate: ${_this.canChangeTemplate}, hasStoredCredential: ${_this.hasStoredCredential}, credentialRequired: ${_this.credentialRequired}, dirty: ${_this.dirty}, saving: ${_this.saving}, canSave: ${_this.canSave}, canAddModel: ${_this.canAddModel}, setDefaultOnCreate: ${_this.setDefaultOnCreate}, showSetDefaultOnCreate: ${_this.showSetDefaultOnCreate}, manualModels: ${_this.manualModels}, declaredModels: ${_this.declaredModels}, billing: ${_this.billing}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $NativeAccountEditorPresentationCopyWith<$Res>  {
  factory $NativeAccountEditorPresentationCopyWith(NativeAccountEditorPresentation value, $Res Function(NativeAccountEditorPresentation) _then) = _$NativeAccountEditorPresentationCopyWithImpl;
@useResult
$Res call({
 String editorId, AccountDisplayKey? accountKey, AccountTemplateKey templateKey, List<AccountTemplatePresentation> templates, AccountTextPresentation name, AccountTextPresentation endpoint, AccountTextPresentation credential, AccountAuthenticationMethod authentication, bool isOpenAiTemplate, ChatGptLoginSnapshot? chatGptLogin, ChatGptAccountInfo? savedChatGptAccount, String protocolLabel, bool canChangeTemplate, bool hasStoredCredential, bool credentialRequired, bool dirty, bool saving, bool canSave, bool canAddModel, bool setDefaultOnCreate, bool showSetDefaultOnCreate, List<ManualAccountModelPresentation> manualModels, List<AccountModelPresentation> declaredModels, AccountBillingPresentation billing, String? error
});


$AccountDisplayKeyCopyWith<$Res>? get accountKey;$AccountTemplateKeyCopyWith<$Res> get templateKey;$AccountTextPresentationCopyWith<$Res> get name;$AccountTextPresentationCopyWith<$Res> get endpoint;$AccountTextPresentationCopyWith<$Res> get credential;$AccountBillingPresentationCopyWith<$Res> get billing;

}
/// @nodoc
class _$NativeAccountEditorPresentationCopyWithImpl<$Res>
    implements $NativeAccountEditorPresentationCopyWith<$Res> {
  _$NativeAccountEditorPresentationCopyWithImpl(this._self, this._then);

  final NativeAccountEditorPresentation _self;
  final $Res Function(NativeAccountEditorPresentation) _then;

/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? accountKey = freezed,Object? templateKey = null,Object? templates = null,Object? name = null,Object? endpoint = null,Object? credential = null,Object? authentication = null,Object? isOpenAiTemplate = null,Object? chatGptLogin = freezed,Object? savedChatGptAccount = freezed,Object? protocolLabel = null,Object? canChangeTemplate = null,Object? hasStoredCredential = null,Object? credentialRequired = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? canAddModel = null,Object? setDefaultOnCreate = null,Object? showSetDefaultOnCreate = null,Object? manualModels = null,Object? declaredModels = null,Object? billing = null,Object? error = freezed,}) {
  return _then(NativeAccountEditorPresentation(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,accountKey: freezed == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,templateKey: null == templateKey ? _self.templateKey : templateKey // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplatePresentation>,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,authentication: null == authentication ? _self.authentication : authentication // ignore: cast_nullable_to_non_nullable
as AccountAuthenticationMethod,isOpenAiTemplate: null == isOpenAiTemplate ? _self.isOpenAiTemplate : isOpenAiTemplate // ignore: cast_nullable_to_non_nullable
as bool,chatGptLogin: freezed == chatGptLogin ? _self.chatGptLogin : chatGptLogin // ignore: cast_nullable_to_non_nullable
as ChatGptLoginSnapshot?,savedChatGptAccount: freezed == savedChatGptAccount ? _self.savedChatGptAccount : savedChatGptAccount // ignore: cast_nullable_to_non_nullable
as ChatGptAccountInfo?,protocolLabel: null == protocolLabel ? _self.protocolLabel : protocolLabel // ignore: cast_nullable_to_non_nullable
as String,canChangeTemplate: null == canChangeTemplate ? _self.canChangeTemplate : canChangeTemplate // ignore: cast_nullable_to_non_nullable
as bool,hasStoredCredential: null == hasStoredCredential ? _self.hasStoredCredential : hasStoredCredential // ignore: cast_nullable_to_non_nullable
as bool,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,canAddModel: null == canAddModel ? _self.canAddModel : canAddModel // ignore: cast_nullable_to_non_nullable
as bool,setDefaultOnCreate: null == setDefaultOnCreate ? _self.setDefaultOnCreate : setDefaultOnCreate // ignore: cast_nullable_to_non_nullable
as bool,showSetDefaultOnCreate: null == showSetDefaultOnCreate ? _self.showSetDefaultOnCreate : showSetDefaultOnCreate // ignore: cast_nullable_to_non_nullable
as bool,manualModels: null == manualModels ? _self.manualModels : manualModels // ignore: cast_nullable_to_non_nullable
as List<ManualAccountModelPresentation>,declaredModels: null == declaredModels ? _self.declaredModels : declaredModels // ignore: cast_nullable_to_non_nullable
as List<AccountModelPresentation>,billing: null == billing ? _self.billing : billing // ignore: cast_nullable_to_non_nullable
as AccountBillingPresentation,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get accountKey {
    if (_self.accountKey == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.accountKey!, (value) {
    return _then(_self.copyWith(accountKey: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res> get templateKey {

  return $AccountTemplateKeyCopyWith<$Res>(_self.templateKey, (value) {
    return _then(_self.copyWith(templateKey: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get endpoint {

  return $AccountTextPresentationCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get credential {

  return $AccountTextPresentationCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingPresentationCopyWith<$Res> get billing {

  return $AccountBillingPresentationCopyWith<$Res>(_self.billing, (value) {
    return _then(_self.copyWith(billing: value));
  });
}
}


/// Adds pattern-matching-related methods to [NativeAccountEditorPresentation].
extension NativeAccountEditorPresentationPatterns on NativeAccountEditorPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NativeAccountEditorPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NativeAccountEditorPresentation value)  $default,){
final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NativeAccountEditorPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey? accountKey,  AccountTemplateKey templateKey,  List<AccountTemplatePresentation> templates,  AccountTextPresentation name,  AccountTextPresentation endpoint,  AccountTextPresentation credential,  AccountAuthenticationMethod authentication,  bool isOpenAiTemplate,  ChatGptLoginSnapshot? chatGptLogin,  ChatGptAccountInfo? savedChatGptAccount,  String protocolLabel,  bool canChangeTemplate,  bool hasStoredCredential,  bool credentialRequired,  bool dirty,  bool saving,  bool canSave,  bool canAddModel,  bool setDefaultOnCreate,  bool showSetDefaultOnCreate,  List<ManualAccountModelPresentation> manualModels,  List<AccountModelPresentation> declaredModels,  AccountBillingPresentation billing,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation() when $default != null:
return $default(_that.editorId,_that.accountKey,_that.templateKey,_that.templates,_that.name,_that.endpoint,_that.credential,_that.authentication,_that.isOpenAiTemplate,_that.chatGptLogin,_that.savedChatGptAccount,_that.protocolLabel,_that.canChangeTemplate,_that.hasStoredCredential,_that.credentialRequired,_that.dirty,_that.saving,_that.canSave,_that.canAddModel,_that.setDefaultOnCreate,_that.showSetDefaultOnCreate,_that.manualModels,_that.declaredModels,_that.billing,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey? accountKey,  AccountTemplateKey templateKey,  List<AccountTemplatePresentation> templates,  AccountTextPresentation name,  AccountTextPresentation endpoint,  AccountTextPresentation credential,  AccountAuthenticationMethod authentication,  bool isOpenAiTemplate,  ChatGptLoginSnapshot? chatGptLogin,  ChatGptAccountInfo? savedChatGptAccount,  String protocolLabel,  bool canChangeTemplate,  bool hasStoredCredential,  bool credentialRequired,  bool dirty,  bool saving,  bool canSave,  bool canAddModel,  bool setDefaultOnCreate,  bool showSetDefaultOnCreate,  List<ManualAccountModelPresentation> manualModels,  List<AccountModelPresentation> declaredModels,  AccountBillingPresentation billing,  String? error)  $default,) {final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation():
return $default(_that.editorId,_that.accountKey,_that.templateKey,_that.templates,_that.name,_that.endpoint,_that.credential,_that.authentication,_that.isOpenAiTemplate,_that.chatGptLogin,_that.savedChatGptAccount,_that.protocolLabel,_that.canChangeTemplate,_that.hasStoredCredential,_that.credentialRequired,_that.dirty,_that.saving,_that.canSave,_that.canAddModel,_that.setDefaultOnCreate,_that.showSetDefaultOnCreate,_that.manualModels,_that.declaredModels,_that.billing,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String editorId,  AccountDisplayKey? accountKey,  AccountTemplateKey templateKey,  List<AccountTemplatePresentation> templates,  AccountTextPresentation name,  AccountTextPresentation endpoint,  AccountTextPresentation credential,  AccountAuthenticationMethod authentication,  bool isOpenAiTemplate,  ChatGptLoginSnapshot? chatGptLogin,  ChatGptAccountInfo? savedChatGptAccount,  String protocolLabel,  bool canChangeTemplate,  bool hasStoredCredential,  bool credentialRequired,  bool dirty,  bool saving,  bool canSave,  bool canAddModel,  bool setDefaultOnCreate,  bool showSetDefaultOnCreate,  List<ManualAccountModelPresentation> manualModels,  List<AccountModelPresentation> declaredModels,  AccountBillingPresentation billing,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _NativeAccountEditorPresentation() when $default != null:
return $default(_that.editorId,_that.accountKey,_that.templateKey,_that.templates,_that.name,_that.endpoint,_that.credential,_that.authentication,_that.isOpenAiTemplate,_that.chatGptLogin,_that.savedChatGptAccount,_that.protocolLabel,_that.canChangeTemplate,_that.hasStoredCredential,_that.credentialRequired,_that.dirty,_that.saving,_that.canSave,_that.canAddModel,_that.setDefaultOnCreate,_that.showSetDefaultOnCreate,_that.manualModels,_that.declaredModels,_that.billing,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _NativeAccountEditorPresentation implements NativeAccountEditorPresentation {
  const _NativeAccountEditorPresentation({required this.editorId, this.accountKey, required this.templateKey,  List<AccountTemplatePresentation> templates = const <AccountTemplatePresentation>[], required this.name, required this.endpoint, required this.credential, this.authentication = AccountAuthenticationMethod.apiKey, this.isOpenAiTemplate = false, this.chatGptLogin, this.savedChatGptAccount, required this.protocolLabel, this.canChangeTemplate = false, this.hasStoredCredential = false, this.credentialRequired = true, this.dirty = false, this.saving = false, this.canSave = false, this.canAddModel = false, this.setDefaultOnCreate = false, this.showSetDefaultOnCreate = false,  List<ManualAccountModelPresentation> manualModels = const <ManualAccountModelPresentation>[],  List<AccountModelPresentation> declaredModels = const <AccountModelPresentation>[], required this.billing, this.error}): _templates = templates,_manualModels = manualModels,_declaredModels = declaredModels;


@override final  String editorId;
@override final  AccountDisplayKey? accountKey;
@override final  AccountTemplateKey templateKey;
 final  List<AccountTemplatePresentation> _templates;
@override@JsonKey() List<AccountTemplatePresentation> get templates {
  if (_templates is EqualUnmodifiableListView) return _templates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_templates);
}

@override final  AccountTextPresentation name;
@override final  AccountTextPresentation endpoint;
@override final  AccountTextPresentation credential;
@override@JsonKey() final  AccountAuthenticationMethod authentication;
@override@JsonKey() final  bool isOpenAiTemplate;
@override final  ChatGptLoginSnapshot? chatGptLogin;
@override final  ChatGptAccountInfo? savedChatGptAccount;
@override final  String protocolLabel;
@override@JsonKey() final  bool canChangeTemplate;
@override@JsonKey() final  bool hasStoredCredential;
@override@JsonKey() final  bool credentialRequired;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool saving;
@override@JsonKey() final  bool canSave;
@override@JsonKey() final  bool canAddModel;
@override@JsonKey() final  bool setDefaultOnCreate;
@override@JsonKey() final  bool showSetDefaultOnCreate;
 final  List<ManualAccountModelPresentation> _manualModels;
@override@JsonKey() List<ManualAccountModelPresentation> get manualModels {
  if (_manualModels is EqualUnmodifiableListView) return _manualModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_manualModels);
}

 final  List<AccountModelPresentation> _declaredModels;
@override@JsonKey() List<AccountModelPresentation> get declaredModels {
  if (_declaredModels is EqualUnmodifiableListView) return _declaredModels;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_declaredModels);
}

@override final  AccountBillingPresentation billing;
@override final  String? error;

/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NativeAccountEditorPresentationCopyWith<_NativeAccountEditorPresentation> get copyWith => __$NativeAccountEditorPresentationCopyWithImpl<_NativeAccountEditorPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NativeAccountEditorPresentation&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.accountKey, accountKey) || other.accountKey == accountKey)&&(identical(other.templateKey, templateKey) || other.templateKey == templateKey)&&const DeepCollectionEquality().equals(other.templates, _templates)&&(identical(other.name, name) || other.name == name)&&(identical(other.endpoint, endpoint) || other.endpoint == endpoint)&&(identical(other.credential, credential) || other.credential == credential)&&(identical(other.authentication, authentication) || other.authentication == authentication)&&(identical(other.isOpenAiTemplate, isOpenAiTemplate) || other.isOpenAiTemplate == isOpenAiTemplate)&&(identical(other.chatGptLogin, chatGptLogin) || other.chatGptLogin == chatGptLogin)&&(identical(other.savedChatGptAccount, savedChatGptAccount) || other.savedChatGptAccount == savedChatGptAccount)&&(identical(other.protocolLabel, protocolLabel) || other.protocolLabel == protocolLabel)&&(identical(other.canChangeTemplate, canChangeTemplate) || other.canChangeTemplate == canChangeTemplate)&&(identical(other.hasStoredCredential, hasStoredCredential) || other.hasStoredCredential == hasStoredCredential)&&(identical(other.credentialRequired, credentialRequired) || other.credentialRequired == credentialRequired)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.canSave, canSave) || other.canSave == canSave)&&(identical(other.canAddModel, canAddModel) || other.canAddModel == canAddModel)&&(identical(other.setDefaultOnCreate, setDefaultOnCreate) || other.setDefaultOnCreate == setDefaultOnCreate)&&(identical(other.showSetDefaultOnCreate, showSetDefaultOnCreate) || other.showSetDefaultOnCreate == showSetDefaultOnCreate)&&const DeepCollectionEquality().equals(other.manualModels, _manualModels)&&const DeepCollectionEquality().equals(other.declaredModels, _declaredModels)&&(identical(other.billing, billing) || other.billing == billing)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hashAll([runtimeType,editorId,accountKey,templateKey,const DeepCollectionEquality().hash(_templates),name,endpoint,credential,authentication,isOpenAiTemplate,chatGptLogin,savedChatGptAccount,protocolLabel,canChangeTemplate,hasStoredCredential,credentialRequired,dirty,saving,canSave,canAddModel,setDefaultOnCreate,showSetDefaultOnCreate,const DeepCollectionEquality().hash(_manualModels),const DeepCollectionEquality().hash(_declaredModels),billing,error]);
}

@override
String toString() {
    return 'NativeAccountEditorPresentation(editorId: $editorId, accountKey: $accountKey, templateKey: $templateKey, templates: $templates, name: $name, endpoint: $endpoint, credential: $credential, authentication: $authentication, isOpenAiTemplate: $isOpenAiTemplate, chatGptLogin: $chatGptLogin, savedChatGptAccount: $savedChatGptAccount, protocolLabel: $protocolLabel, canChangeTemplate: $canChangeTemplate, hasStoredCredential: $hasStoredCredential, credentialRequired: $credentialRequired, dirty: $dirty, saving: $saving, canSave: $canSave, canAddModel: $canAddModel, setDefaultOnCreate: $setDefaultOnCreate, showSetDefaultOnCreate: $showSetDefaultOnCreate, manualModels: $manualModels, declaredModels: $declaredModels, billing: $billing, error: $error)';
}


}

/// @nodoc
abstract mixin class _$NativeAccountEditorPresentationCopyWith<$Res> implements $NativeAccountEditorPresentationCopyWith<$Res> {
  factory _$NativeAccountEditorPresentationCopyWith(_NativeAccountEditorPresentation value, $Res Function(_NativeAccountEditorPresentation) _then) = __$NativeAccountEditorPresentationCopyWithImpl;
@override @useResult
$Res call({
 String editorId, AccountDisplayKey? accountKey, AccountTemplateKey templateKey, List<AccountTemplatePresentation> templates, AccountTextPresentation name, AccountTextPresentation endpoint, AccountTextPresentation credential, AccountAuthenticationMethod authentication, bool isOpenAiTemplate, ChatGptLoginSnapshot? chatGptLogin, ChatGptAccountInfo? savedChatGptAccount, String protocolLabel, bool canChangeTemplate, bool hasStoredCredential, bool credentialRequired, bool dirty, bool saving, bool canSave, bool canAddModel, bool setDefaultOnCreate, bool showSetDefaultOnCreate, List<ManualAccountModelPresentation> manualModels, List<AccountModelPresentation> declaredModels, AccountBillingPresentation billing, String? error
});


@override $AccountDisplayKeyCopyWith<$Res>? get accountKey;@override $AccountTemplateKeyCopyWith<$Res> get templateKey;@override $AccountTextPresentationCopyWith<$Res> get name;@override $AccountTextPresentationCopyWith<$Res> get endpoint;@override $AccountTextPresentationCopyWith<$Res> get credential;@override $AccountBillingPresentationCopyWith<$Res> get billing;

}
/// @nodoc
class __$NativeAccountEditorPresentationCopyWithImpl<$Res>
    implements _$NativeAccountEditorPresentationCopyWith<$Res> {
  __$NativeAccountEditorPresentationCopyWithImpl(this._self, this._then);

  final _NativeAccountEditorPresentation _self;
  final $Res Function(_NativeAccountEditorPresentation) _then;

/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? accountKey = freezed,Object? templateKey = null,Object? templates = null,Object? name = null,Object? endpoint = null,Object? credential = null,Object? authentication = null,Object? isOpenAiTemplate = null,Object? chatGptLogin = freezed,Object? savedChatGptAccount = freezed,Object? protocolLabel = null,Object? canChangeTemplate = null,Object? hasStoredCredential = null,Object? credentialRequired = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? canAddModel = null,Object? setDefaultOnCreate = null,Object? showSetDefaultOnCreate = null,Object? manualModels = null,Object? declaredModels = null,Object? billing = null,Object? error = freezed,}) {
  return _then(_NativeAccountEditorPresentation(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,accountKey: freezed == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,templateKey: null == templateKey ? _self.templateKey : templateKey // ignore: cast_nullable_to_non_nullable
as AccountTemplateKey,templates: null == templates ? _self._templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplatePresentation>,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,endpoint: null == endpoint ? _self.endpoint : endpoint // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,authentication: null == authentication ? _self.authentication : authentication // ignore: cast_nullable_to_non_nullable
as AccountAuthenticationMethod,isOpenAiTemplate: null == isOpenAiTemplate ? _self.isOpenAiTemplate : isOpenAiTemplate // ignore: cast_nullable_to_non_nullable
as bool,chatGptLogin: freezed == chatGptLogin ? _self.chatGptLogin : chatGptLogin // ignore: cast_nullable_to_non_nullable
as ChatGptLoginSnapshot?,savedChatGptAccount: freezed == savedChatGptAccount ? _self.savedChatGptAccount : savedChatGptAccount // ignore: cast_nullable_to_non_nullable
as ChatGptAccountInfo?,protocolLabel: null == protocolLabel ? _self.protocolLabel : protocolLabel // ignore: cast_nullable_to_non_nullable
as String,canChangeTemplate: null == canChangeTemplate ? _self.canChangeTemplate : canChangeTemplate // ignore: cast_nullable_to_non_nullable
as bool,hasStoredCredential: null == hasStoredCredential ? _self.hasStoredCredential : hasStoredCredential // ignore: cast_nullable_to_non_nullable
as bool,credentialRequired: null == credentialRequired ? _self.credentialRequired : credentialRequired // ignore: cast_nullable_to_non_nullable
as bool,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,canAddModel: null == canAddModel ? _self.canAddModel : canAddModel // ignore: cast_nullable_to_non_nullable
as bool,setDefaultOnCreate: null == setDefaultOnCreate ? _self.setDefaultOnCreate : setDefaultOnCreate // ignore: cast_nullable_to_non_nullable
as bool,showSetDefaultOnCreate: null == showSetDefaultOnCreate ? _self.showSetDefaultOnCreate : showSetDefaultOnCreate // ignore: cast_nullable_to_non_nullable
as bool,manualModels: null == manualModels ? _self._manualModels : manualModels // ignore: cast_nullable_to_non_nullable
as List<ManualAccountModelPresentation>,declaredModels: null == declaredModels ? _self._declaredModels : declaredModels // ignore: cast_nullable_to_non_nullable
as List<AccountModelPresentation>,billing: null == billing ? _self.billing : billing // ignore: cast_nullable_to_non_nullable
as AccountBillingPresentation,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get accountKey {
    if (_self.accountKey == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.accountKey!, (value) {
    return _then(_self.copyWith(accountKey: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTemplateKeyCopyWith<$Res> get templateKey {

  return $AccountTemplateKeyCopyWith<$Res>(_self.templateKey, (value) {
    return _then(_self.copyWith(templateKey: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get endpoint {

  return $AccountTextPresentationCopyWith<$Res>(_self.endpoint, (value) {
    return _then(_self.copyWith(endpoint: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get credential {

  return $AccountTextPresentationCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of NativeAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountBillingPresentationCopyWith<$Res> get billing {

  return $AccountBillingPresentationCopyWith<$Res>(_self.billing, (value) {
    return _then(_self.copyWith(billing: value));
  });
}
}

/// @nodoc
mixin _$AcpAccountEditorPresentation {

 String get editorId; AccountDisplayKey? get accountKey; String get templateName; String? get iconKey; AccountTextPresentation get name; AcpAccountPresentation get preparation; bool get dirty; bool get saving; bool get canSave; bool get saveAndConnect; String? get error;
/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountEditorPresentationCopyWith<AcpAccountEditorPresentation> get copyWith => _$AcpAccountEditorPresentationCopyWithImpl<AcpAccountEditorPresentation>(this as AcpAccountEditorPresentation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountEditorPresentation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountEditorPresentation&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.accountKey, _this.accountKey) || other.accountKey == _this.accountKey)&&(identical(other.templateName, _this.templateName) || other.templateName == _this.templateName)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.preparation, _this.preparation) || other.preparation == _this.preparation)&&(identical(other.dirty, _this.dirty) || other.dirty == _this.dirty)&&(identical(other.saving, _this.saving) || other.saving == _this.saving)&&(identical(other.canSave, _this.canSave) || other.canSave == _this.canSave)&&(identical(other.saveAndConnect, _this.saveAndConnect) || other.saveAndConnect == _this.saveAndConnect)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AcpAccountEditorPresentation;
  return Object.hash(runtimeType,_this.editorId,_this.accountKey,_this.templateName,_this.iconKey,_this.name,_this.preparation,_this.dirty,_this.saving,_this.canSave,_this.saveAndConnect,_this.error);
}

@override
String toString() {
  final _this = this as AcpAccountEditorPresentation;
  return 'AcpAccountEditorPresentation(editorId: ${_this.editorId}, accountKey: ${_this.accountKey}, templateName: ${_this.templateName}, iconKey: ${_this.iconKey}, name: ${_this.name}, preparation: ${_this.preparation}, dirty: ${_this.dirty}, saving: ${_this.saving}, canSave: ${_this.canSave}, saveAndConnect: ${_this.saveAndConnect}, error: ${_this.error})';
}


}

/// @nodoc
abstract mixin class $AcpAccountEditorPresentationCopyWith<$Res>  {
  factory $AcpAccountEditorPresentationCopyWith(AcpAccountEditorPresentation value, $Res Function(AcpAccountEditorPresentation) _then) = _$AcpAccountEditorPresentationCopyWithImpl;
@useResult
$Res call({
 String editorId, AccountDisplayKey? accountKey, String templateName, String? iconKey, AccountTextPresentation name, AcpAccountPresentation preparation, bool dirty, bool saving, bool canSave, bool saveAndConnect, String? error
});


$AccountDisplayKeyCopyWith<$Res>? get accountKey;$AccountTextPresentationCopyWith<$Res> get name;$AcpAccountPresentationCopyWith<$Res> get preparation;

}
/// @nodoc
class _$AcpAccountEditorPresentationCopyWithImpl<$Res>
    implements $AcpAccountEditorPresentationCopyWith<$Res> {
  _$AcpAccountEditorPresentationCopyWithImpl(this._self, this._then);

  final AcpAccountEditorPresentation _self;
  final $Res Function(AcpAccountEditorPresentation) _then;

/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? accountKey = freezed,Object? templateName = null,Object? iconKey = freezed,Object? name = null,Object? preparation = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? saveAndConnect = null,Object? error = freezed,}) {
  return _then(AcpAccountEditorPresentation(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,accountKey: freezed == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,templateName: null == templateName ? _self.templateName : templateName // ignore: cast_nullable_to_non_nullable
as String,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,preparation: null == preparation ? _self.preparation : preparation // ignore: cast_nullable_to_non_nullable
as AcpAccountPresentation,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,saveAndConnect: null == saveAndConnect ? _self.saveAndConnect : saveAndConnect // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}
/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get accountKey {
    if (_self.accountKey == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.accountKey!, (value) {
    return _then(_self.copyWith(accountKey: value));
  });
}/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<$Res> get preparation {

  return $AcpAccountPresentationCopyWith<$Res>(_self.preparation, (value) {
    return _then(_self.copyWith(preparation: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountEditorPresentation].
extension AcpAccountEditorPresentationPatterns on AcpAccountEditorPresentation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountEditorPresentation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountEditorPresentation value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountEditorPresentation value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey? accountKey,  String templateName,  String? iconKey,  AccountTextPresentation name,  AcpAccountPresentation preparation,  bool dirty,  bool saving,  bool canSave,  bool saveAndConnect,  String? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation() when $default != null:
return $default(_that.editorId,_that.accountKey,_that.templateName,_that.iconKey,_that.name,_that.preparation,_that.dirty,_that.saving,_that.canSave,_that.saveAndConnect,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String editorId,  AccountDisplayKey? accountKey,  String templateName,  String? iconKey,  AccountTextPresentation name,  AcpAccountPresentation preparation,  bool dirty,  bool saving,  bool canSave,  bool saveAndConnect,  String? error)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation():
return $default(_that.editorId,_that.accountKey,_that.templateName,_that.iconKey,_that.name,_that.preparation,_that.dirty,_that.saving,_that.canSave,_that.saveAndConnect,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String editorId,  AccountDisplayKey? accountKey,  String templateName,  String? iconKey,  AccountTextPresentation name,  AcpAccountPresentation preparation,  bool dirty,  bool saving,  bool canSave,  bool saveAndConnect,  String? error)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountEditorPresentation() when $default != null:
return $default(_that.editorId,_that.accountKey,_that.templateName,_that.iconKey,_that.name,_that.preparation,_that.dirty,_that.saving,_that.canSave,_that.saveAndConnect,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountEditorPresentation implements AcpAccountEditorPresentation {
  const _AcpAccountEditorPresentation({required this.editorId, this.accountKey, required this.templateName, this.iconKey, required this.name, required this.preparation, this.dirty = false, this.saving = false, this.canSave = false, this.saveAndConnect = false, this.error});


@override final  String editorId;
@override final  AccountDisplayKey? accountKey;
@override final  String templateName;
@override final  String? iconKey;
@override final  AccountTextPresentation name;
@override final  AcpAccountPresentation preparation;
@override@JsonKey() final  bool dirty;
@override@JsonKey() final  bool saving;
@override@JsonKey() final  bool canSave;
@override@JsonKey() final  bool saveAndConnect;
@override final  String? error;

/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountEditorPresentationCopyWith<_AcpAccountEditorPresentation> get copyWith => __$AcpAccountEditorPresentationCopyWithImpl<_AcpAccountEditorPresentation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountEditorPresentation&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.accountKey, accountKey) || other.accountKey == accountKey)&&(identical(other.templateName, templateName) || other.templateName == templateName)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.name, name) || other.name == name)&&(identical(other.preparation, preparation) || other.preparation == preparation)&&(identical(other.dirty, dirty) || other.dirty == dirty)&&(identical(other.saving, saving) || other.saving == saving)&&(identical(other.canSave, canSave) || other.canSave == canSave)&&(identical(other.saveAndConnect, saveAndConnect) || other.saveAndConnect == saveAndConnect)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,accountKey,templateName,iconKey,name,preparation,dirty,saving,canSave,saveAndConnect,error);
}

@override
String toString() {
    return 'AcpAccountEditorPresentation(editorId: $editorId, accountKey: $accountKey, templateName: $templateName, iconKey: $iconKey, name: $name, preparation: $preparation, dirty: $dirty, saving: $saving, canSave: $canSave, saveAndConnect: $saveAndConnect, error: $error)';
}


}

/// @nodoc
abstract mixin class _$AcpAccountEditorPresentationCopyWith<$Res> implements $AcpAccountEditorPresentationCopyWith<$Res> {
  factory _$AcpAccountEditorPresentationCopyWith(_AcpAccountEditorPresentation value, $Res Function(_AcpAccountEditorPresentation) _then) = __$AcpAccountEditorPresentationCopyWithImpl;
@override @useResult
$Res call({
 String editorId, AccountDisplayKey? accountKey, String templateName, String? iconKey, AccountTextPresentation name, AcpAccountPresentation preparation, bool dirty, bool saving, bool canSave, bool saveAndConnect, String? error
});


@override $AccountDisplayKeyCopyWith<$Res>? get accountKey;@override $AccountTextPresentationCopyWith<$Res> get name;@override $AcpAccountPresentationCopyWith<$Res> get preparation;

}
/// @nodoc
class __$AcpAccountEditorPresentationCopyWithImpl<$Res>
    implements _$AcpAccountEditorPresentationCopyWith<$Res> {
  __$AcpAccountEditorPresentationCopyWithImpl(this._self, this._then);

  final _AcpAccountEditorPresentation _self;
  final $Res Function(_AcpAccountEditorPresentation) _then;

/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? accountKey = freezed,Object? templateName = null,Object? iconKey = freezed,Object? name = null,Object? preparation = null,Object? dirty = null,Object? saving = null,Object? canSave = null,Object? saveAndConnect = null,Object? error = freezed,}) {
  return _then(_AcpAccountEditorPresentation(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as String,accountKey: freezed == accountKey ? _self.accountKey : accountKey // ignore: cast_nullable_to_non_nullable
as AccountDisplayKey?,templateName: null == templateName ? _self.templateName : templateName // ignore: cast_nullable_to_non_nullable
as String,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as AccountTextPresentation,preparation: null == preparation ? _self.preparation : preparation // ignore: cast_nullable_to_non_nullable
as AcpAccountPresentation,dirty: null == dirty ? _self.dirty : dirty // ignore: cast_nullable_to_non_nullable
as bool,saving: null == saving ? _self.saving : saving // ignore: cast_nullable_to_non_nullable
as bool,canSave: null == canSave ? _self.canSave : canSave // ignore: cast_nullable_to_non_nullable
as bool,saveAndConnect: null == saveAndConnect ? _self.saveAndConnect : saveAndConnect // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountDisplayKeyCopyWith<$Res>? get accountKey {
    if (_self.accountKey == null) {
    return null;
  }

  return $AccountDisplayKeyCopyWith<$Res>(_self.accountKey!, (value) {
    return _then(_self.copyWith(accountKey: value));
  });
}/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountTextPresentationCopyWith<$Res> get name {

  return $AccountTextPresentationCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of AcpAccountEditorPresentation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAccountPresentationCopyWith<$Res> get preparation {

  return $AcpAccountPresentationCopyWith<$Res>(_self.preparation, (value) {
    return _then(_self.copyWith(preparation: value));
  });
}
}

// dart format on
