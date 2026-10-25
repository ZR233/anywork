// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usage_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageReadHeader {

 ReadText get configFingerprint; TypedListRef get usages;
/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageReadHeaderCopyWith<AccountUsageReadHeader> get copyWith => _$AccountUsageReadHeaderCopyWithImpl<AccountUsageReadHeader>(this as AccountUsageReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageReadHeader&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint)&&(identical(other.usages, _this.usages) || other.usages == _this.usages));
}


@override
int get hashCode {
  final _this = this as AccountUsageReadHeader;
  return Object.hash(runtimeType,_this.configFingerprint,_this.usages);
}



}

/// @nodoc
abstract mixin class $AccountUsageReadHeaderCopyWith<$Res>  {
  factory $AccountUsageReadHeaderCopyWith(AccountUsageReadHeader value, $Res Function(AccountUsageReadHeader) _then) = _$AccountUsageReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadText configFingerprint, TypedListRef usages
});


$ReadTextCopyWith<$Res> get configFingerprint;$TypedListRefCopyWith<$Res> get usages;

}
/// @nodoc
class _$AccountUsageReadHeaderCopyWithImpl<$Res>
    implements $AccountUsageReadHeaderCopyWith<$Res> {
  _$AccountUsageReadHeaderCopyWithImpl(this._self, this._then);

  final AccountUsageReadHeader _self;
  final $Res Function(AccountUsageReadHeader) _then;

/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configFingerprint = null,Object? usages = null,}) {
  return _then(AccountUsageReadHeader(
configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,usages: null == usages ? _self.usages : usages // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configFingerprint {

  return $ReadTextCopyWith<$Res>(_self.configFingerprint, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get usages {

  return $TypedListRefCopyWith<$Res>(_self.usages, (value) {
    return _then(_self.copyWith(usages: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageReadHeader].
extension AccountUsageReadHeaderPatterns on AccountUsageReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText configFingerprint,  TypedListRef usages)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageReadHeader() when $default != null:
return $default(_that.configFingerprint,_that.usages);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText configFingerprint,  TypedListRef usages)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadHeader():
return $default(_that.configFingerprint,_that.usages);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText configFingerprint,  TypedListRef usages)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadHeader() when $default != null:
return $default(_that.configFingerprint,_that.usages);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageReadHeader implements AccountUsageReadHeader {
  const _AccountUsageReadHeader({required this.configFingerprint, required this.usages});


@override final  ReadText configFingerprint;
@override final  TypedListRef usages;

/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageReadHeaderCopyWith<_AccountUsageReadHeader> get copyWith => __$AccountUsageReadHeaderCopyWithImpl<_AccountUsageReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageReadHeader&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint)&&(identical(other.usages, usages) || other.usages == usages));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configFingerprint,usages);
}



}

/// @nodoc
abstract mixin class _$AccountUsageReadHeaderCopyWith<$Res> implements $AccountUsageReadHeaderCopyWith<$Res> {
  factory _$AccountUsageReadHeaderCopyWith(_AccountUsageReadHeader value, $Res Function(_AccountUsageReadHeader) _then) = __$AccountUsageReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadText configFingerprint, TypedListRef usages
});


@override $ReadTextCopyWith<$Res> get configFingerprint;@override $TypedListRefCopyWith<$Res> get usages;

}
/// @nodoc
class __$AccountUsageReadHeaderCopyWithImpl<$Res>
    implements _$AccountUsageReadHeaderCopyWith<$Res> {
  __$AccountUsageReadHeaderCopyWithImpl(this._self, this._then);

  final _AccountUsageReadHeader _self;
  final $Res Function(_AccountUsageReadHeader) _then;

/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configFingerprint = null,Object? usages = null,}) {
  return _then(_AccountUsageReadHeader(
configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,usages: null == usages ? _self.usages : usages // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configFingerprint {

  return $ReadTextCopyWith<$Res>(_self.configFingerprint, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}/// Create a copy of AccountUsageReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get usages {

  return $TypedListRefCopyWith<$Res>(_self.usages, (value) {
    return _then(_self.copyWith(usages: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageRead {

 ReadText get accountId; int get revision; int get updatedAt; ReadText get lastOperationId; AccountUsageResultRead get state;
/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageReadCopyWith<AccountUsageRead> get copyWith => _$AccountUsageReadCopyWithImpl<AccountUsageRead>(this as AccountUsageRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageRead&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.lastOperationId, _this.lastOperationId) || other.lastOperationId == _this.lastOperationId)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as AccountUsageRead;
  return Object.hash(runtimeType,_this.accountId,_this.revision,_this.updatedAt,_this.lastOperationId,_this.state);
}



}

/// @nodoc
abstract mixin class $AccountUsageReadCopyWith<$Res>  {
  factory $AccountUsageReadCopyWith(AccountUsageRead value, $Res Function(AccountUsageRead) _then) = _$AccountUsageReadCopyWithImpl;
@useResult
$Res call({
 ReadText accountId, int revision, int updatedAt, ReadText lastOperationId, AccountUsageResultRead state
});


$ReadTextCopyWith<$Res> get accountId;$ReadTextCopyWith<$Res> get lastOperationId;$AccountUsageResultReadCopyWith<$Res> get state;

}
/// @nodoc
class _$AccountUsageReadCopyWithImpl<$Res>
    implements $AccountUsageReadCopyWith<$Res> {
  _$AccountUsageReadCopyWithImpl(this._self, this._then);

  final AccountUsageRead _self;
  final $Res Function(AccountUsageRead) _then;

/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? revision = null,Object? updatedAt = null,Object? lastOperationId = null,Object? state = null,}) {
  return _then(AccountUsageRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOperationId: null == lastOperationId ? _self.lastOperationId : lastOperationId // ignore: cast_nullable_to_non_nullable
as ReadText,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AccountUsageResultRead,
  ));
}
/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get lastOperationId {

  return $ReadTextCopyWith<$Res>(_self.lastOperationId, (value) {
    return _then(_self.copyWith(lastOperationId: value));
  });
}/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageResultReadCopyWith<$Res> get state {

  return $AccountUsageResultReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageRead].
extension AccountUsageReadPatterns on AccountUsageRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText accountId,  int revision,  int updatedAt,  ReadText lastOperationId,  AccountUsageResultRead state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageRead() when $default != null:
return $default(_that.accountId,_that.revision,_that.updatedAt,_that.lastOperationId,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText accountId,  int revision,  int updatedAt,  ReadText lastOperationId,  AccountUsageResultRead state)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageRead():
return $default(_that.accountId,_that.revision,_that.updatedAt,_that.lastOperationId,_that.state);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText accountId,  int revision,  int updatedAt,  ReadText lastOperationId,  AccountUsageResultRead state)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageRead() when $default != null:
return $default(_that.accountId,_that.revision,_that.updatedAt,_that.lastOperationId,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageRead implements AccountUsageRead {
  const _AccountUsageRead({required this.accountId, required this.revision, required this.updatedAt, required this.lastOperationId, required this.state});


@override final  ReadText accountId;
@override final  int revision;
@override final  int updatedAt;
@override final  ReadText lastOperationId;
@override final  AccountUsageResultRead state;

/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageReadCopyWith<_AccountUsageRead> get copyWith => __$AccountUsageReadCopyWithImpl<_AccountUsageRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageRead&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastOperationId, lastOperationId) || other.lastOperationId == lastOperationId)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,revision,updatedAt,lastOperationId,state);
}



}

/// @nodoc
abstract mixin class _$AccountUsageReadCopyWith<$Res> implements $AccountUsageReadCopyWith<$Res> {
  factory _$AccountUsageReadCopyWith(_AccountUsageRead value, $Res Function(_AccountUsageRead) _then) = __$AccountUsageReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText accountId, int revision, int updatedAt, ReadText lastOperationId, AccountUsageResultRead state
});


@override $ReadTextCopyWith<$Res> get accountId;@override $ReadTextCopyWith<$Res> get lastOperationId;@override $AccountUsageResultReadCopyWith<$Res> get state;

}
/// @nodoc
class __$AccountUsageReadCopyWithImpl<$Res>
    implements _$AccountUsageReadCopyWith<$Res> {
  __$AccountUsageReadCopyWithImpl(this._self, this._then);

  final _AccountUsageRead _self;
  final $Res Function(_AccountUsageRead) _then;

/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? revision = null,Object? updatedAt = null,Object? lastOperationId = null,Object? state = null,}) {
  return _then(_AccountUsageRead(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as ReadText,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOperationId: null == lastOperationId ? _self.lastOperationId : lastOperationId // ignore: cast_nullable_to_non_nullable
as ReadText,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AccountUsageResultRead,
  ));
}

/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get accountId {

  return $ReadTextCopyWith<$Res>(_self.accountId, (value) {
    return _then(_self.copyWith(accountId: value));
  });
}/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get lastOperationId {

  return $ReadTextCopyWith<$Res>(_self.lastOperationId, (value) {
    return _then(_self.copyWith(lastOperationId: value));
  });
}/// Create a copy of AccountUsageRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageResultReadCopyWith<$Res> get state {

  return $AccountUsageResultReadCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageResultRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageResultRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AccountUsageResultReadCopyWith<$Res>  {
$AccountUsageResultReadCopyWith(AccountUsageResultRead _, $Res Function(AccountUsageResultRead) __);
}


/// Adds pattern-matching-related methods to [AccountUsageResultRead].
extension AccountUsageResultReadPatterns on AccountUsageResultRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UsageUnsupportedRead value)?  unsupported,TResult Function( UsageMissingCredentialRead value)?  missingCredential,TResult Function( UsageReadyRead value)?  ready,TResult Function( UsageFailedRead value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UsageUnsupportedRead() when unsupported != null:
return unsupported(_that);case UsageMissingCredentialRead() when missingCredential != null:
return missingCredential(_that);case UsageReadyRead() when ready != null:
return ready(_that);case UsageFailedRead() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UsageUnsupportedRead value)  unsupported,required TResult Function( UsageMissingCredentialRead value)  missingCredential,required TResult Function( UsageReadyRead value)  ready,required TResult Function( UsageFailedRead value)  failed,}){
final _that = this;
switch (_that) {
case UsageUnsupportedRead():
return unsupported(_that);case UsageMissingCredentialRead():
return missingCredential(_that);case UsageReadyRead():
return ready(_that);case UsageFailedRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UsageUnsupportedRead value)?  unsupported,TResult? Function( UsageMissingCredentialRead value)?  missingCredential,TResult? Function( UsageReadyRead value)?  ready,TResult? Function( UsageFailedRead value)?  failed,}){
final _that = this;
switch (_that) {
case UsageUnsupportedRead() when unsupported != null:
return unsupported(_that);case UsageMissingCredentialRead() when missingCredential != null:
return missingCredential(_that);case UsageReadyRead() when ready != null:
return ready(_that);case UsageFailedRead() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unsupported,TResult Function( ReadText message)?  missingCredential,TResult Function( AccountUsageDataRead data)?  ready,TResult Function( SourceStateErrorRead error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UsageUnsupportedRead() when unsupported != null:
return unsupported();case UsageMissingCredentialRead() when missingCredential != null:
return missingCredential(_that.message);case UsageReadyRead() when ready != null:
return ready(_that.data);case UsageFailedRead() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unsupported,required TResult Function( ReadText message)  missingCredential,required TResult Function( AccountUsageDataRead data)  ready,required TResult Function( SourceStateErrorRead error)  failed,}) {final _that = this;
switch (_that) {
case UsageUnsupportedRead():
return unsupported();case UsageMissingCredentialRead():
return missingCredential(_that.message);case UsageReadyRead():
return ready(_that.data);case UsageFailedRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unsupported,TResult? Function( ReadText message)?  missingCredential,TResult? Function( AccountUsageDataRead data)?  ready,TResult? Function( SourceStateErrorRead error)?  failed,}) {final _that = this;
switch (_that) {
case UsageUnsupportedRead() when unsupported != null:
return unsupported();case UsageMissingCredentialRead() when missingCredential != null:
return missingCredential(_that.message);case UsageReadyRead() when ready != null:
return ready(_that.data);case UsageFailedRead() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class UsageUnsupportedRead implements AccountUsageResultRead {
  const UsageUnsupportedRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageUnsupportedRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class UsageMissingCredentialRead implements AccountUsageResultRead {
  const UsageMissingCredentialRead({required this.message});


 final  ReadText message;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageMissingCredentialReadCopyWith<UsageMissingCredentialRead> get copyWith => _$UsageMissingCredentialReadCopyWithImpl<UsageMissingCredentialRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageMissingCredentialRead&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}



}

/// @nodoc
abstract mixin class $UsageMissingCredentialReadCopyWith<$Res> implements $AccountUsageResultReadCopyWith<$Res> {
  factory $UsageMissingCredentialReadCopyWith(UsageMissingCredentialRead value, $Res Function(UsageMissingCredentialRead) _then) = _$UsageMissingCredentialReadCopyWithImpl;
@useResult
$Res call({
 ReadText message
});


$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$UsageMissingCredentialReadCopyWithImpl<$Res>
    implements $UsageMissingCredentialReadCopyWith<$Res> {
  _$UsageMissingCredentialReadCopyWithImpl(this._self, this._then);

  final UsageMissingCredentialRead _self;
  final $Res Function(UsageMissingCredentialRead) _then;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(UsageMissingCredentialRead(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc


class UsageReadyRead implements AccountUsageResultRead {
  const UsageReadyRead({required this.data});


 final  AccountUsageDataRead data;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageReadyReadCopyWith<UsageReadyRead> get copyWith => _$UsageReadyReadCopyWithImpl<UsageReadyRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageReadyRead&&(identical(other.data, data) || other.data == data));
}


@override
int get hashCode {
    return Object.hash(runtimeType,data);
}



}

/// @nodoc
abstract mixin class $UsageReadyReadCopyWith<$Res> implements $AccountUsageResultReadCopyWith<$Res> {
  factory $UsageReadyReadCopyWith(UsageReadyRead value, $Res Function(UsageReadyRead) _then) = _$UsageReadyReadCopyWithImpl;
@useResult
$Res call({
 AccountUsageDataRead data
});


$AccountUsageDataReadCopyWith<$Res> get data;

}
/// @nodoc
class _$UsageReadyReadCopyWithImpl<$Res>
    implements $UsageReadyReadCopyWith<$Res> {
  _$UsageReadyReadCopyWithImpl(this._self, this._then);

  final UsageReadyRead _self;
  final $Res Function(UsageReadyRead) _then;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? data = null,}) {
  return _then(UsageReadyRead(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as AccountUsageDataRead,
  ));
}

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageDataReadCopyWith<$Res> get data {

  return $AccountUsageDataReadCopyWith<$Res>(_self.data, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}

/// @nodoc


class UsageFailedRead implements AccountUsageResultRead {
  const UsageFailedRead({required this.error});


 final  SourceStateErrorRead error;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageFailedReadCopyWith<UsageFailedRead> get copyWith => _$UsageFailedReadCopyWithImpl<UsageFailedRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageFailedRead&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $UsageFailedReadCopyWith<$Res> implements $AccountUsageResultReadCopyWith<$Res> {
  factory $UsageFailedReadCopyWith(UsageFailedRead value, $Res Function(UsageFailedRead) _then) = _$UsageFailedReadCopyWithImpl;
@useResult
$Res call({
 SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$UsageFailedReadCopyWithImpl<$Res>
    implements $UsageFailedReadCopyWith<$Res> {
  _$UsageFailedReadCopyWithImpl(this._self, this._then);

  final UsageFailedRead _self;
  final $Res Function(UsageFailedRead) _then;

/// Create a copy of AccountUsageResultRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(UsageFailedRead(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of AccountUsageResultRead
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
mixin _$AccountUsageDataRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageDataRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AccountUsageDataReadCopyWith<$Res>  {
$AccountUsageDataReadCopyWith(AccountUsageDataRead _, $Res Function(AccountUsageDataRead) __);
}


/// Adds pattern-matching-related methods to [AccountUsageDataRead].
extension AccountUsageDataReadPatterns on AccountUsageDataRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DeepSeekBalanceRead value)?  deepSeekBalance,TResult Function( ZhipuCodingPlanRead value)?  zhipuCodingPlan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DeepSeekBalanceRead() when deepSeekBalance != null:
return deepSeekBalance(_that);case ZhipuCodingPlanRead() when zhipuCodingPlan != null:
return zhipuCodingPlan(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DeepSeekBalanceRead value)  deepSeekBalance,required TResult Function( ZhipuCodingPlanRead value)  zhipuCodingPlan,}){
final _that = this;
switch (_that) {
case DeepSeekBalanceRead():
return deepSeekBalance(_that);case ZhipuCodingPlanRead():
return zhipuCodingPlan(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DeepSeekBalanceRead value)?  deepSeekBalance,TResult? Function( ZhipuCodingPlanRead value)?  zhipuCodingPlan,}){
final _that = this;
switch (_that) {
case DeepSeekBalanceRead() when deepSeekBalance != null:
return deepSeekBalance(_that);case ZhipuCodingPlanRead() when zhipuCodingPlan != null:
return zhipuCodingPlan(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool isAvailable,  TypedListRef balances)?  deepSeekBalance,TResult Function( ReadText? level,  TypedListRef limits)?  zhipuCodingPlan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DeepSeekBalanceRead() when deepSeekBalance != null:
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlanRead() when zhipuCodingPlan != null:
return zhipuCodingPlan(_that.level,_that.limits);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool isAvailable,  TypedListRef balances)  deepSeekBalance,required TResult Function( ReadText? level,  TypedListRef limits)  zhipuCodingPlan,}) {final _that = this;
switch (_that) {
case DeepSeekBalanceRead():
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlanRead():
return zhipuCodingPlan(_that.level,_that.limits);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool isAvailable,  TypedListRef balances)?  deepSeekBalance,TResult? Function( ReadText? level,  TypedListRef limits)?  zhipuCodingPlan,}) {final _that = this;
switch (_that) {
case DeepSeekBalanceRead() when deepSeekBalance != null:
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlanRead() when zhipuCodingPlan != null:
return zhipuCodingPlan(_that.level,_that.limits);case _:
  return null;

}
}

}

/// @nodoc


class DeepSeekBalanceRead implements AccountUsageDataRead {
  const DeepSeekBalanceRead({required this.isAvailable, required this.balances});


 final  bool isAvailable;
 final  TypedListRef balances;

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeepSeekBalanceReadCopyWith<DeepSeekBalanceRead> get copyWith => _$DeepSeekBalanceReadCopyWithImpl<DeepSeekBalanceRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeepSeekBalanceRead&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&(identical(other.balances, balances) || other.balances == balances));
}


@override
int get hashCode {
    return Object.hash(runtimeType,isAvailable,balances);
}



}

/// @nodoc
abstract mixin class $DeepSeekBalanceReadCopyWith<$Res> implements $AccountUsageDataReadCopyWith<$Res> {
  factory $DeepSeekBalanceReadCopyWith(DeepSeekBalanceRead value, $Res Function(DeepSeekBalanceRead) _then) = _$DeepSeekBalanceReadCopyWithImpl;
@useResult
$Res call({
 bool isAvailable, TypedListRef balances
});


$TypedListRefCopyWith<$Res> get balances;

}
/// @nodoc
class _$DeepSeekBalanceReadCopyWithImpl<$Res>
    implements $DeepSeekBalanceReadCopyWith<$Res> {
  _$DeepSeekBalanceReadCopyWithImpl(this._self, this._then);

  final DeepSeekBalanceRead _self;
  final $Res Function(DeepSeekBalanceRead) _then;

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? isAvailable = null,Object? balances = null,}) {
  return _then(DeepSeekBalanceRead(
isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,balances: null == balances ? _self.balances : balances // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get balances {

  return $TypedListRefCopyWith<$Res>(_self.balances, (value) {
    return _then(_self.copyWith(balances: value));
  });
}
}

/// @nodoc


class ZhipuCodingPlanRead implements AccountUsageDataRead {
  const ZhipuCodingPlanRead({required this.level, required this.limits});


 final  ReadText? level;
 final  TypedListRef limits;

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZhipuCodingPlanReadCopyWith<ZhipuCodingPlanRead> get copyWith => _$ZhipuCodingPlanReadCopyWithImpl<ZhipuCodingPlanRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ZhipuCodingPlanRead&&(identical(other.level, level) || other.level == level)&&(identical(other.limits, limits) || other.limits == limits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,limits);
}



}

/// @nodoc
abstract mixin class $ZhipuCodingPlanReadCopyWith<$Res> implements $AccountUsageDataReadCopyWith<$Res> {
  factory $ZhipuCodingPlanReadCopyWith(ZhipuCodingPlanRead value, $Res Function(ZhipuCodingPlanRead) _then) = _$ZhipuCodingPlanReadCopyWithImpl;
@useResult
$Res call({
 ReadText? level, TypedListRef limits
});


$ReadTextCopyWith<$Res>? get level;$TypedListRefCopyWith<$Res> get limits;

}
/// @nodoc
class _$ZhipuCodingPlanReadCopyWithImpl<$Res>
    implements $ZhipuCodingPlanReadCopyWith<$Res> {
  _$ZhipuCodingPlanReadCopyWithImpl(this._self, this._then);

  final ZhipuCodingPlanRead _self;
  final $Res Function(ZhipuCodingPlanRead) _then;

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = freezed,Object? limits = null,}) {
  return _then(ZhipuCodingPlanRead(
level: freezed == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as ReadText?,limits: null == limits ? _self.limits : limits // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get level {
    if (_self.level == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.level!, (value) {
    return _then(_self.copyWith(level: value));
  });
}/// Create a copy of AccountUsageDataRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get limits {

  return $TypedListRefCopyWith<$Res>(_self.limits, (value) {
    return _then(_self.copyWith(limits: value));
  });
}
}

/// @nodoc
mixin _$BalanceRead {

 ReadText get currency; ReadText get totalBalance; ReadText get grantedBalance; ReadText get toppedUpBalance;
/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BalanceReadCopyWith<BalanceRead> get copyWith => _$BalanceReadCopyWithImpl<BalanceRead>(this as BalanceRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BalanceRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BalanceRead&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.totalBalance, _this.totalBalance) || other.totalBalance == _this.totalBalance)&&(identical(other.grantedBalance, _this.grantedBalance) || other.grantedBalance == _this.grantedBalance)&&(identical(other.toppedUpBalance, _this.toppedUpBalance) || other.toppedUpBalance == _this.toppedUpBalance));
}


@override
int get hashCode {
  final _this = this as BalanceRead;
  return Object.hash(runtimeType,_this.currency,_this.totalBalance,_this.grantedBalance,_this.toppedUpBalance);
}



}

/// @nodoc
abstract mixin class $BalanceReadCopyWith<$Res>  {
  factory $BalanceReadCopyWith(BalanceRead value, $Res Function(BalanceRead) _then) = _$BalanceReadCopyWithImpl;
@useResult
$Res call({
 ReadText currency, ReadText totalBalance, ReadText grantedBalance, ReadText toppedUpBalance
});


$ReadTextCopyWith<$Res> get currency;$ReadTextCopyWith<$Res> get totalBalance;$ReadTextCopyWith<$Res> get grantedBalance;$ReadTextCopyWith<$Res> get toppedUpBalance;

}
/// @nodoc
class _$BalanceReadCopyWithImpl<$Res>
    implements $BalanceReadCopyWith<$Res> {
  _$BalanceReadCopyWithImpl(this._self, this._then);

  final BalanceRead _self;
  final $Res Function(BalanceRead) _then;

/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? totalBalance = null,Object? grantedBalance = null,Object? toppedUpBalance = null,}) {
  return _then(BalanceRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,totalBalance: null == totalBalance ? _self.totalBalance : totalBalance // ignore: cast_nullable_to_non_nullable
as ReadText,grantedBalance: null == grantedBalance ? _self.grantedBalance : grantedBalance // ignore: cast_nullable_to_non_nullable
as ReadText,toppedUpBalance: null == toppedUpBalance ? _self.toppedUpBalance : toppedUpBalance // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get totalBalance {

  return $ReadTextCopyWith<$Res>(_self.totalBalance, (value) {
    return _then(_self.copyWith(totalBalance: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get grantedBalance {

  return $ReadTextCopyWith<$Res>(_self.grantedBalance, (value) {
    return _then(_self.copyWith(grantedBalance: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get toppedUpBalance {

  return $ReadTextCopyWith<$Res>(_self.toppedUpBalance, (value) {
    return _then(_self.copyWith(toppedUpBalance: value));
  });
}
}


/// Adds pattern-matching-related methods to [BalanceRead].
extension BalanceReadPatterns on BalanceRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BalanceRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BalanceRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BalanceRead value)  $default,){
final _that = this;
switch (_that) {
case _BalanceRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BalanceRead value)?  $default,){
final _that = this;
switch (_that) {
case _BalanceRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText currency,  ReadText totalBalance,  ReadText grantedBalance,  ReadText toppedUpBalance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BalanceRead() when $default != null:
return $default(_that.currency,_that.totalBalance,_that.grantedBalance,_that.toppedUpBalance);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText currency,  ReadText totalBalance,  ReadText grantedBalance,  ReadText toppedUpBalance)  $default,) {final _that = this;
switch (_that) {
case _BalanceRead():
return $default(_that.currency,_that.totalBalance,_that.grantedBalance,_that.toppedUpBalance);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText currency,  ReadText totalBalance,  ReadText grantedBalance,  ReadText toppedUpBalance)?  $default,) {final _that = this;
switch (_that) {
case _BalanceRead() when $default != null:
return $default(_that.currency,_that.totalBalance,_that.grantedBalance,_that.toppedUpBalance);case _:
  return null;

}
}

}

/// @nodoc


class _BalanceRead implements BalanceRead {
  const _BalanceRead({required this.currency, required this.totalBalance, required this.grantedBalance, required this.toppedUpBalance});


@override final  ReadText currency;
@override final  ReadText totalBalance;
@override final  ReadText grantedBalance;
@override final  ReadText toppedUpBalance;

/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BalanceReadCopyWith<_BalanceRead> get copyWith => __$BalanceReadCopyWithImpl<_BalanceRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BalanceRead&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.totalBalance, totalBalance) || other.totalBalance == totalBalance)&&(identical(other.grantedBalance, grantedBalance) || other.grantedBalance == grantedBalance)&&(identical(other.toppedUpBalance, toppedUpBalance) || other.toppedUpBalance == toppedUpBalance));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,totalBalance,grantedBalance,toppedUpBalance);
}



}

/// @nodoc
abstract mixin class _$BalanceReadCopyWith<$Res> implements $BalanceReadCopyWith<$Res> {
  factory _$BalanceReadCopyWith(_BalanceRead value, $Res Function(_BalanceRead) _then) = __$BalanceReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText currency, ReadText totalBalance, ReadText grantedBalance, ReadText toppedUpBalance
});


@override $ReadTextCopyWith<$Res> get currency;@override $ReadTextCopyWith<$Res> get totalBalance;@override $ReadTextCopyWith<$Res> get grantedBalance;@override $ReadTextCopyWith<$Res> get toppedUpBalance;

}
/// @nodoc
class __$BalanceReadCopyWithImpl<$Res>
    implements _$BalanceReadCopyWith<$Res> {
  __$BalanceReadCopyWithImpl(this._self, this._then);

  final _BalanceRead _self;
  final $Res Function(_BalanceRead) _then;

/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? totalBalance = null,Object? grantedBalance = null,Object? toppedUpBalance = null,}) {
  return _then(_BalanceRead(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as ReadText,totalBalance: null == totalBalance ? _self.totalBalance : totalBalance // ignore: cast_nullable_to_non_nullable
as ReadText,grantedBalance: null == grantedBalance ? _self.grantedBalance : grantedBalance // ignore: cast_nullable_to_non_nullable
as ReadText,toppedUpBalance: null == toppedUpBalance ? _self.toppedUpBalance : toppedUpBalance // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get currency {

  return $ReadTextCopyWith<$Res>(_self.currency, (value) {
    return _then(_self.copyWith(currency: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get totalBalance {

  return $ReadTextCopyWith<$Res>(_self.totalBalance, (value) {
    return _then(_self.copyWith(totalBalance: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get grantedBalance {

  return $ReadTextCopyWith<$Res>(_self.grantedBalance, (value) {
    return _then(_self.copyWith(grantedBalance: value));
  });
}/// Create a copy of BalanceRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get toppedUpBalance {

  return $ReadTextCopyWith<$Res>(_self.toppedUpBalance, (value) {
    return _then(_self.copyWith(toppedUpBalance: value));
  });
}
}

/// @nodoc
mixin _$QuotaLimitRead {

 QuotaWindowRead get window; double get percentage; double? get currentValue; double? get total; double? get remaining; int? get nextResetAt; TypedListRef get usageDetails;
/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaLimitReadCopyWith<QuotaLimitRead> get copyWith => _$QuotaLimitReadCopyWithImpl<QuotaLimitRead>(this as QuotaLimitRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaLimitRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaLimitRead&&(identical(other.window, _this.window) || other.window == _this.window)&&(identical(other.percentage, _this.percentage) || other.percentage == _this.percentage)&&(identical(other.currentValue, _this.currentValue) || other.currentValue == _this.currentValue)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.remaining, _this.remaining) || other.remaining == _this.remaining)&&(identical(other.nextResetAt, _this.nextResetAt) || other.nextResetAt == _this.nextResetAt)&&(identical(other.usageDetails, _this.usageDetails) || other.usageDetails == _this.usageDetails));
}


@override
int get hashCode {
  final _this = this as QuotaLimitRead;
  return Object.hash(runtimeType,_this.window,_this.percentage,_this.currentValue,_this.total,_this.remaining,_this.nextResetAt,_this.usageDetails);
}



}

/// @nodoc
abstract mixin class $QuotaLimitReadCopyWith<$Res>  {
  factory $QuotaLimitReadCopyWith(QuotaLimitRead value, $Res Function(QuotaLimitRead) _then) = _$QuotaLimitReadCopyWithImpl;
@useResult
$Res call({
 QuotaWindowRead window, double percentage, double? currentValue, double? total, double? remaining, int? nextResetAt, TypedListRef usageDetails
});


$QuotaWindowReadCopyWith<$Res> get window;$TypedListRefCopyWith<$Res> get usageDetails;

}
/// @nodoc
class _$QuotaLimitReadCopyWithImpl<$Res>
    implements $QuotaLimitReadCopyWith<$Res> {
  _$QuotaLimitReadCopyWithImpl(this._self, this._then);

  final QuotaLimitRead _self;
  final $Res Function(QuotaLimitRead) _then;

/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? window = null,Object? percentage = null,Object? currentValue = freezed,Object? total = freezed,Object? remaining = freezed,Object? nextResetAt = freezed,Object? usageDetails = null,}) {
  return _then(QuotaLimitRead(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as QuotaWindowRead,percentage: null == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,remaining: freezed == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as double?,nextResetAt: freezed == nextResetAt ? _self.nextResetAt : nextResetAt // ignore: cast_nullable_to_non_nullable
as int?,usageDetails: null == usageDetails ? _self.usageDetails : usageDetails // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuotaWindowReadCopyWith<$Res> get window {

  return $QuotaWindowReadCopyWith<$Res>(_self.window, (value) {
    return _then(_self.copyWith(window: value));
  });
}/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get usageDetails {

  return $TypedListRefCopyWith<$Res>(_self.usageDetails, (value) {
    return _then(_self.copyWith(usageDetails: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuotaLimitRead].
extension QuotaLimitReadPatterns on QuotaLimitRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaLimitRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaLimitRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaLimitRead value)  $default,){
final _that = this;
switch (_that) {
case _QuotaLimitRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaLimitRead value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaLimitRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( QuotaWindowRead window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  TypedListRef usageDetails)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaLimitRead() when $default != null:
return $default(_that.window,_that.percentage,_that.currentValue,_that.total,_that.remaining,_that.nextResetAt,_that.usageDetails);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( QuotaWindowRead window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  TypedListRef usageDetails)  $default,) {final _that = this;
switch (_that) {
case _QuotaLimitRead():
return $default(_that.window,_that.percentage,_that.currentValue,_that.total,_that.remaining,_that.nextResetAt,_that.usageDetails);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( QuotaWindowRead window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  TypedListRef usageDetails)?  $default,) {final _that = this;
switch (_that) {
case _QuotaLimitRead() when $default != null:
return $default(_that.window,_that.percentage,_that.currentValue,_that.total,_that.remaining,_that.nextResetAt,_that.usageDetails);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaLimitRead implements QuotaLimitRead {
  const _QuotaLimitRead({required this.window, required this.percentage, required this.currentValue, required this.total, required this.remaining, required this.nextResetAt, required this.usageDetails});


@override final  QuotaWindowRead window;
@override final  double percentage;
@override final  double? currentValue;
@override final  double? total;
@override final  double? remaining;
@override final  int? nextResetAt;
@override final  TypedListRef usageDetails;

/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaLimitReadCopyWith<_QuotaLimitRead> get copyWith => __$QuotaLimitReadCopyWithImpl<_QuotaLimitRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaLimitRead&&(identical(other.window, window) || other.window == window)&&(identical(other.percentage, percentage) || other.percentage == percentage)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.total, total) || other.total == total)&&(identical(other.remaining, remaining) || other.remaining == remaining)&&(identical(other.nextResetAt, nextResetAt) || other.nextResetAt == nextResetAt)&&(identical(other.usageDetails, usageDetails) || other.usageDetails == usageDetails));
}


@override
int get hashCode {
    return Object.hash(runtimeType,window,percentage,currentValue,total,remaining,nextResetAt,usageDetails);
}



}

/// @nodoc
abstract mixin class _$QuotaLimitReadCopyWith<$Res> implements $QuotaLimitReadCopyWith<$Res> {
  factory _$QuotaLimitReadCopyWith(_QuotaLimitRead value, $Res Function(_QuotaLimitRead) _then) = __$QuotaLimitReadCopyWithImpl;
@override @useResult
$Res call({
 QuotaWindowRead window, double percentage, double? currentValue, double? total, double? remaining, int? nextResetAt, TypedListRef usageDetails
});


@override $QuotaWindowReadCopyWith<$Res> get window;@override $TypedListRefCopyWith<$Res> get usageDetails;

}
/// @nodoc
class __$QuotaLimitReadCopyWithImpl<$Res>
    implements _$QuotaLimitReadCopyWith<$Res> {
  __$QuotaLimitReadCopyWithImpl(this._self, this._then);

  final _QuotaLimitRead _self;
  final $Res Function(_QuotaLimitRead) _then;

/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? window = null,Object? percentage = null,Object? currentValue = freezed,Object? total = freezed,Object? remaining = freezed,Object? nextResetAt = freezed,Object? usageDetails = null,}) {
  return _then(_QuotaLimitRead(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as QuotaWindowRead,percentage: null == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,remaining: freezed == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as double?,nextResetAt: freezed == nextResetAt ? _self.nextResetAt : nextResetAt // ignore: cast_nullable_to_non_nullable
as int?,usageDetails: null == usageDetails ? _self.usageDetails : usageDetails // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuotaWindowReadCopyWith<$Res> get window {

  return $QuotaWindowReadCopyWith<$Res>(_self.window, (value) {
    return _then(_self.copyWith(window: value));
  });
}/// Create a copy of QuotaLimitRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get usageDetails {

  return $TypedListRefCopyWith<$Res>(_self.usageDetails, (value) {
    return _then(_self.copyWith(usageDetails: value));
  });
}
}

/// @nodoc
mixin _$QuotaWindowRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaWindowRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $QuotaWindowReadCopyWith<$Res>  {
$QuotaWindowReadCopyWith(QuotaWindowRead _, $Res Function(QuotaWindowRead) __);
}


/// Adds pattern-matching-related methods to [QuotaWindowRead].
extension QuotaWindowReadPatterns on QuotaWindowRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FiveHourQuotaRead value)?  fiveHour,TResult Function( WeeklyQuotaRead value)?  weekly,TResult Function( McpMonthlyQuotaRead value)?  mcpMonthly,TResult Function( OtherQuotaRead value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FiveHourQuotaRead() when fiveHour != null:
return fiveHour(_that);case WeeklyQuotaRead() when weekly != null:
return weekly(_that);case McpMonthlyQuotaRead() when mcpMonthly != null:
return mcpMonthly(_that);case OtherQuotaRead() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FiveHourQuotaRead value)  fiveHour,required TResult Function( WeeklyQuotaRead value)  weekly,required TResult Function( McpMonthlyQuotaRead value)  mcpMonthly,required TResult Function( OtherQuotaRead value)  other,}){
final _that = this;
switch (_that) {
case FiveHourQuotaRead():
return fiveHour(_that);case WeeklyQuotaRead():
return weekly(_that);case McpMonthlyQuotaRead():
return mcpMonthly(_that);case OtherQuotaRead():
return other(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FiveHourQuotaRead value)?  fiveHour,TResult? Function( WeeklyQuotaRead value)?  weekly,TResult? Function( McpMonthlyQuotaRead value)?  mcpMonthly,TResult? Function( OtherQuotaRead value)?  other,}){
final _that = this;
switch (_that) {
case FiveHourQuotaRead() when fiveHour != null:
return fiveHour(_that);case WeeklyQuotaRead() when weekly != null:
return weekly(_that);case McpMonthlyQuotaRead() when mcpMonthly != null:
return mcpMonthly(_that);case OtherQuotaRead() when other != null:
return other(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  fiveHour,TResult Function()?  weekly,TResult Function()?  mcpMonthly,TResult Function( ReadText value)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FiveHourQuotaRead() when fiveHour != null:
return fiveHour();case WeeklyQuotaRead() when weekly != null:
return weekly();case McpMonthlyQuotaRead() when mcpMonthly != null:
return mcpMonthly();case OtherQuotaRead() when other != null:
return other(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  fiveHour,required TResult Function()  weekly,required TResult Function()  mcpMonthly,required TResult Function( ReadText value)  other,}) {final _that = this;
switch (_that) {
case FiveHourQuotaRead():
return fiveHour();case WeeklyQuotaRead():
return weekly();case McpMonthlyQuotaRead():
return mcpMonthly();case OtherQuotaRead():
return other(_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  fiveHour,TResult? Function()?  weekly,TResult? Function()?  mcpMonthly,TResult? Function( ReadText value)?  other,}) {final _that = this;
switch (_that) {
case FiveHourQuotaRead() when fiveHour != null:
return fiveHour();case WeeklyQuotaRead() when weekly != null:
return weekly();case McpMonthlyQuotaRead() when mcpMonthly != null:
return mcpMonthly();case OtherQuotaRead() when other != null:
return other(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class FiveHourQuotaRead implements QuotaWindowRead {
  const FiveHourQuotaRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FiveHourQuotaRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class WeeklyQuotaRead implements QuotaWindowRead {
  const WeeklyQuotaRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WeeklyQuotaRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class McpMonthlyQuotaRead implements QuotaWindowRead {
  const McpMonthlyQuotaRead();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is McpMonthlyQuotaRead);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class OtherQuotaRead implements QuotaWindowRead {
  const OtherQuotaRead(this.value);


 final  ReadText value;

/// Create a copy of QuotaWindowRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OtherQuotaReadCopyWith<OtherQuotaRead> get copyWith => _$OtherQuotaReadCopyWithImpl<OtherQuotaRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OtherQuotaRead&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class $OtherQuotaReadCopyWith<$Res> implements $QuotaWindowReadCopyWith<$Res> {
  factory $OtherQuotaReadCopyWith(OtherQuotaRead value, $Res Function(OtherQuotaRead) _then) = _$OtherQuotaReadCopyWithImpl;
@useResult
$Res call({
 ReadText value
});


$ReadTextCopyWith<$Res> get value;

}
/// @nodoc
class _$OtherQuotaReadCopyWithImpl<$Res>
    implements $OtherQuotaReadCopyWith<$Res> {
  _$OtherQuotaReadCopyWithImpl(this._self, this._then);

  final OtherQuotaRead _self;
  final $Res Function(OtherQuotaRead) _then;

/// Create a copy of QuotaWindowRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(OtherQuotaRead(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of QuotaWindowRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get value {

  return $ReadTextCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$QuotaDetailRead {

 ReadText get name; double? get currentValue; double? get total; double? get percentage;
/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaDetailReadCopyWith<QuotaDetailRead> get copyWith => _$QuotaDetailReadCopyWithImpl<QuotaDetailRead>(this as QuotaDetailRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaDetailRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaDetailRead&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.currentValue, _this.currentValue) || other.currentValue == _this.currentValue)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.percentage, _this.percentage) || other.percentage == _this.percentage));
}


@override
int get hashCode {
  final _this = this as QuotaDetailRead;
  return Object.hash(runtimeType,_this.name,_this.currentValue,_this.total,_this.percentage);
}



}

/// @nodoc
abstract mixin class $QuotaDetailReadCopyWith<$Res>  {
  factory $QuotaDetailReadCopyWith(QuotaDetailRead value, $Res Function(QuotaDetailRead) _then) = _$QuotaDetailReadCopyWithImpl;
@useResult
$Res call({
 ReadText name, double? currentValue, double? total, double? percentage
});


$ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class _$QuotaDetailReadCopyWithImpl<$Res>
    implements $QuotaDetailReadCopyWith<$Res> {
  _$QuotaDetailReadCopyWithImpl(this._self, this._then);

  final QuotaDetailRead _self;
  final $Res Function(QuotaDetailRead) _then;

/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? currentValue = freezed,Object? total = freezed,Object? percentage = freezed,}) {
  return _then(QuotaDetailRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}
/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuotaDetailRead].
extension QuotaDetailReadPatterns on QuotaDetailRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaDetailRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaDetailRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaDetailRead value)  $default,){
final _that = this;
switch (_that) {
case _QuotaDetailRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaDetailRead value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaDetailRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText name,  double? currentValue,  double? total,  double? percentage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaDetailRead() when $default != null:
return $default(_that.name,_that.currentValue,_that.total,_that.percentage);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText name,  double? currentValue,  double? total,  double? percentage)  $default,) {final _that = this;
switch (_that) {
case _QuotaDetailRead():
return $default(_that.name,_that.currentValue,_that.total,_that.percentage);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText name,  double? currentValue,  double? total,  double? percentage)?  $default,) {final _that = this;
switch (_that) {
case _QuotaDetailRead() when $default != null:
return $default(_that.name,_that.currentValue,_that.total,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaDetailRead implements QuotaDetailRead {
  const _QuotaDetailRead({required this.name, required this.currentValue, required this.total, required this.percentage});


@override final  ReadText name;
@override final  double? currentValue;
@override final  double? total;
@override final  double? percentage;

/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaDetailReadCopyWith<_QuotaDetailRead> get copyWith => __$QuotaDetailReadCopyWithImpl<_QuotaDetailRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaDetailRead&&(identical(other.name, name) || other.name == name)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.total, total) || other.total == total)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,currentValue,total,percentage);
}



}

/// @nodoc
abstract mixin class _$QuotaDetailReadCopyWith<$Res> implements $QuotaDetailReadCopyWith<$Res> {
  factory _$QuotaDetailReadCopyWith(_QuotaDetailRead value, $Res Function(_QuotaDetailRead) _then) = __$QuotaDetailReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText name, double? currentValue, double? total, double? percentage
});


@override $ReadTextCopyWith<$Res> get name;

}
/// @nodoc
class __$QuotaDetailReadCopyWithImpl<$Res>
    implements _$QuotaDetailReadCopyWith<$Res> {
  __$QuotaDetailReadCopyWithImpl(this._self, this._then);

  final _QuotaDetailRead _self;
  final $Res Function(_QuotaDetailRead) _then;

/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? currentValue = freezed,Object? total = freezed,Object? percentage = freezed,}) {
  return _then(_QuotaDetailRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

/// Create a copy of QuotaDetailRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageEntryPage {

 ProductCollectionRef get collection; int get offset; List<ProductEntityRef> get items; int? get nextOffset;
/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageEntryPageCopyWith<AccountUsageEntryPage> get copyWith => _$AccountUsageEntryPageCopyWithImpl<AccountUsageEntryPage>(this as AccountUsageEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AccountUsageEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as AccountUsageEntryPage;
  return 'AccountUsageEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $AccountUsageEntryPageCopyWith<$Res>  {
  factory $AccountUsageEntryPageCopyWith(AccountUsageEntryPage value, $Res Function(AccountUsageEntryPage) _then) = _$AccountUsageEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$AccountUsageEntryPageCopyWithImpl<$Res>
    implements $AccountUsageEntryPageCopyWith<$Res> {
  _$AccountUsageEntryPageCopyWithImpl(this._self, this._then);

  final AccountUsageEntryPage _self;
  final $Res Function(AccountUsageEntryPage) _then;

/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AccountUsageEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageEntryPage].
extension AccountUsageEntryPagePatterns on AccountUsageEntryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageEntryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageEntryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageEntryPage value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageEntryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageEntryPage value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageEntryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageEntryPage():
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductCollectionRef collection,  int offset,  List<ProductEntityRef> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageEntryPage() when $default != null:
return $default(_that.collection,_that.offset,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageEntryPage implements AccountUsageEntryPage {
  const _AccountUsageEntryPage({required this.collection, required this.offset, required  List<ProductEntityRef> items, required this.nextOffset}): _items = items;


@override final  ProductCollectionRef collection;
@override final  int offset;
 final  List<ProductEntityRef> _items;
@override List<ProductEntityRef> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageEntryPageCopyWith<_AccountUsageEntryPage> get copyWith => __$AccountUsageEntryPageCopyWithImpl<_AccountUsageEntryPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageEntryPage&&(identical(other.collection, collection) || other.collection == collection)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,collection,offset,const DeepCollectionEquality().hash(_items),nextOffset);
}

@override
String toString() {
    return 'AccountUsageEntryPage(collection: $collection, offset: $offset, items: $items, nextOffset: $nextOffset)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageEntryPageCopyWith<$Res> implements $AccountUsageEntryPageCopyWith<$Res> {
  factory _$AccountUsageEntryPageCopyWith(_AccountUsageEntryPage value, $Res Function(_AccountUsageEntryPage) _then) = __$AccountUsageEntryPageCopyWithImpl;
@override @useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


@override $ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class __$AccountUsageEntryPageCopyWithImpl<$Res>
    implements _$AccountUsageEntryPageCopyWith<$Res> {
  __$AccountUsageEntryPageCopyWithImpl(this._self, this._then);

  final _AccountUsageEntryPage _self;
  final $Res Function(_AccountUsageEntryPage) _then;

/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_AccountUsageEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of AccountUsageEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageEntityRead {

 ProductEntityRef get reference; AccountUsageRead get value;
/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageEntityReadCopyWith<AccountUsageEntityRead> get copyWith => _$AccountUsageEntityReadCopyWithImpl<AccountUsageEntityRead>(this as AccountUsageEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as AccountUsageEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $AccountUsageEntityReadCopyWith<$Res>  {
  factory $AccountUsageEntityReadCopyWith(AccountUsageEntityRead value, $Res Function(AccountUsageEntityRead) _then) = _$AccountUsageEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, AccountUsageRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$AccountUsageReadCopyWith<$Res> get value;

}
/// @nodoc
class _$AccountUsageEntityReadCopyWithImpl<$Res>
    implements $AccountUsageEntityReadCopyWith<$Res> {
  _$AccountUsageEntityReadCopyWithImpl(this._self, this._then);

  final AccountUsageEntityRead _self;
  final $Res Function(AccountUsageEntityRead) _then;

/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(AccountUsageEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountUsageRead,
  ));
}
/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadCopyWith<$Res> get value {

  return $AccountUsageReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageEntityRead].
extension AccountUsageEntityReadPatterns on AccountUsageEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  AccountUsageRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  AccountUsageRead value)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageEntityRead():
return $default(_that.reference,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  AccountUsageRead value)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageEntityRead implements AccountUsageEntityRead {
  const _AccountUsageEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  AccountUsageRead value;

/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageEntityReadCopyWith<_AccountUsageEntityRead> get copyWith => __$AccountUsageEntityReadCopyWithImpl<_AccountUsageEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$AccountUsageEntityReadCopyWith<$Res> implements $AccountUsageEntityReadCopyWith<$Res> {
  factory _$AccountUsageEntityReadCopyWith(_AccountUsageEntityRead value, $Res Function(_AccountUsageEntityRead) _then) = __$AccountUsageEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, AccountUsageRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $AccountUsageReadCopyWith<$Res> get value;

}
/// @nodoc
class __$AccountUsageEntityReadCopyWithImpl<$Res>
    implements _$AccountUsageEntityReadCopyWith<$Res> {
  __$AccountUsageEntityReadCopyWithImpl(this._self, this._then);

  final _AccountUsageEntityRead _self;
  final $Res Function(_AccountUsageEntityRead) _then;

/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_AccountUsageEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AccountUsageRead,
  ));
}

/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of AccountUsageEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageReadCopyWith<$Res> get value {

  return $AccountUsageReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageReadPage {

 int get listId; int get offset; int get total; List<AccountUsageRead> get items; int? get nextOffset;
/// Create a copy of AccountUsageReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageReadPageCopyWith<AccountUsageReadPage> get copyWith => _$AccountUsageReadPageCopyWithImpl<AccountUsageReadPage>(this as AccountUsageReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as AccountUsageReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $AccountUsageReadPageCopyWith<$Res>  {
  factory $AccountUsageReadPageCopyWith(AccountUsageReadPage value, $Res Function(AccountUsageReadPage) _then) = _$AccountUsageReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<AccountUsageRead> items, int? nextOffset
});




}
/// @nodoc
class _$AccountUsageReadPageCopyWithImpl<$Res>
    implements $AccountUsageReadPageCopyWith<$Res> {
  _$AccountUsageReadPageCopyWithImpl(this._self, this._then);

  final AccountUsageReadPage _self;
  final $Res Function(AccountUsageReadPage) _then;

/// Create a copy of AccountUsageReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(AccountUsageReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<AccountUsageRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountUsageReadPage].
extension AccountUsageReadPagePatterns on AccountUsageReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageReadPage value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<AccountUsageRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<AccountUsageRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<AccountUsageRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageReadPage implements AccountUsageReadPage {
  const _AccountUsageReadPage({required this.listId, required this.offset, required this.total, required  List<AccountUsageRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<AccountUsageRead> _items;
@override List<AccountUsageRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of AccountUsageReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageReadPageCopyWith<_AccountUsageReadPage> get copyWith => __$AccountUsageReadPageCopyWithImpl<_AccountUsageReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$AccountUsageReadPageCopyWith<$Res> implements $AccountUsageReadPageCopyWith<$Res> {
  factory _$AccountUsageReadPageCopyWith(_AccountUsageReadPage value, $Res Function(_AccountUsageReadPage) _then) = __$AccountUsageReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<AccountUsageRead> items, int? nextOffset
});




}
/// @nodoc
class __$AccountUsageReadPageCopyWithImpl<$Res>
    implements _$AccountUsageReadPageCopyWith<$Res> {
  __$AccountUsageReadPageCopyWithImpl(this._self, this._then);

  final _AccountUsageReadPage _self;
  final $Res Function(_AccountUsageReadPage) _then;

/// Create a copy of AccountUsageReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_AccountUsageReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<AccountUsageRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$BalanceReadPage {

 int get listId; int get offset; int get total; List<BalanceRead> get items; int? get nextOffset;
/// Create a copy of BalanceReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BalanceReadPageCopyWith<BalanceReadPage> get copyWith => _$BalanceReadPageCopyWithImpl<BalanceReadPage>(this as BalanceReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BalanceReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BalanceReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as BalanceReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $BalanceReadPageCopyWith<$Res>  {
  factory $BalanceReadPageCopyWith(BalanceReadPage value, $Res Function(BalanceReadPage) _then) = _$BalanceReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<BalanceRead> items, int? nextOffset
});




}
/// @nodoc
class _$BalanceReadPageCopyWithImpl<$Res>
    implements $BalanceReadPageCopyWith<$Res> {
  _$BalanceReadPageCopyWithImpl(this._self, this._then);

  final BalanceReadPage _self;
  final $Res Function(BalanceReadPage) _then;

/// Create a copy of BalanceReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(BalanceReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<BalanceRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [BalanceReadPage].
extension BalanceReadPagePatterns on BalanceReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BalanceReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BalanceReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BalanceReadPage value)  $default,){
final _that = this;
switch (_that) {
case _BalanceReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BalanceReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _BalanceReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<BalanceRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BalanceReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<BalanceRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _BalanceReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<BalanceRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _BalanceReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _BalanceReadPage implements BalanceReadPage {
  const _BalanceReadPage({required this.listId, required this.offset, required this.total, required  List<BalanceRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<BalanceRead> _items;
@override List<BalanceRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of BalanceReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BalanceReadPageCopyWith<_BalanceReadPage> get copyWith => __$BalanceReadPageCopyWithImpl<_BalanceReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BalanceReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$BalanceReadPageCopyWith<$Res> implements $BalanceReadPageCopyWith<$Res> {
  factory _$BalanceReadPageCopyWith(_BalanceReadPage value, $Res Function(_BalanceReadPage) _then) = __$BalanceReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<BalanceRead> items, int? nextOffset
});




}
/// @nodoc
class __$BalanceReadPageCopyWithImpl<$Res>
    implements _$BalanceReadPageCopyWith<$Res> {
  __$BalanceReadPageCopyWithImpl(this._self, this._then);

  final _BalanceReadPage _self;
  final $Res Function(_BalanceReadPage) _then;

/// Create a copy of BalanceReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_BalanceReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<BalanceRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$QuotaLimitReadPage {

 int get listId; int get offset; int get total; List<QuotaLimitRead> get items; int? get nextOffset;
/// Create a copy of QuotaLimitReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaLimitReadPageCopyWith<QuotaLimitReadPage> get copyWith => _$QuotaLimitReadPageCopyWithImpl<QuotaLimitReadPage>(this as QuotaLimitReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaLimitReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaLimitReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as QuotaLimitReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $QuotaLimitReadPageCopyWith<$Res>  {
  factory $QuotaLimitReadPageCopyWith(QuotaLimitReadPage value, $Res Function(QuotaLimitReadPage) _then) = _$QuotaLimitReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<QuotaLimitRead> items, int? nextOffset
});




}
/// @nodoc
class _$QuotaLimitReadPageCopyWithImpl<$Res>
    implements $QuotaLimitReadPageCopyWith<$Res> {
  _$QuotaLimitReadPageCopyWithImpl(this._self, this._then);

  final QuotaLimitReadPage _self;
  final $Res Function(QuotaLimitReadPage) _then;

/// Create a copy of QuotaLimitReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(QuotaLimitReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<QuotaLimitRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuotaLimitReadPage].
extension QuotaLimitReadPagePatterns on QuotaLimitReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaLimitReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaLimitReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaLimitReadPage value)  $default,){
final _that = this;
switch (_that) {
case _QuotaLimitReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaLimitReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaLimitReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<QuotaLimitRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaLimitReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<QuotaLimitRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _QuotaLimitReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<QuotaLimitRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _QuotaLimitReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaLimitReadPage implements QuotaLimitReadPage {
  const _QuotaLimitReadPage({required this.listId, required this.offset, required this.total, required  List<QuotaLimitRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<QuotaLimitRead> _items;
@override List<QuotaLimitRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of QuotaLimitReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaLimitReadPageCopyWith<_QuotaLimitReadPage> get copyWith => __$QuotaLimitReadPageCopyWithImpl<_QuotaLimitReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaLimitReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$QuotaLimitReadPageCopyWith<$Res> implements $QuotaLimitReadPageCopyWith<$Res> {
  factory _$QuotaLimitReadPageCopyWith(_QuotaLimitReadPage value, $Res Function(_QuotaLimitReadPage) _then) = __$QuotaLimitReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<QuotaLimitRead> items, int? nextOffset
});




}
/// @nodoc
class __$QuotaLimitReadPageCopyWithImpl<$Res>
    implements _$QuotaLimitReadPageCopyWith<$Res> {
  __$QuotaLimitReadPageCopyWithImpl(this._self, this._then);

  final _QuotaLimitReadPage _self;
  final $Res Function(_QuotaLimitReadPage) _then;

/// Create a copy of QuotaLimitReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_QuotaLimitReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<QuotaLimitRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$QuotaDetailReadPage {

 int get listId; int get offset; int get total; List<QuotaDetailRead> get items; int? get nextOffset;
/// Create a copy of QuotaDetailReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaDetailReadPageCopyWith<QuotaDetailReadPage> get copyWith => _$QuotaDetailReadPageCopyWithImpl<QuotaDetailReadPage>(this as QuotaDetailReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaDetailReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaDetailReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as QuotaDetailReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $QuotaDetailReadPageCopyWith<$Res>  {
  factory $QuotaDetailReadPageCopyWith(QuotaDetailReadPage value, $Res Function(QuotaDetailReadPage) _then) = _$QuotaDetailReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<QuotaDetailRead> items, int? nextOffset
});




}
/// @nodoc
class _$QuotaDetailReadPageCopyWithImpl<$Res>
    implements $QuotaDetailReadPageCopyWith<$Res> {
  _$QuotaDetailReadPageCopyWithImpl(this._self, this._then);

  final QuotaDetailReadPage _self;
  final $Res Function(QuotaDetailReadPage) _then;

/// Create a copy of QuotaDetailReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(QuotaDetailReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<QuotaDetailRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuotaDetailReadPage].
extension QuotaDetailReadPagePatterns on QuotaDetailReadPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaDetailReadPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaDetailReadPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaDetailReadPage value)  $default,){
final _that = this;
switch (_that) {
case _QuotaDetailReadPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaDetailReadPage value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaDetailReadPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<QuotaDetailRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaDetailReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int offset,  int total,  List<QuotaDetailRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _QuotaDetailReadPage():
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int offset,  int total,  List<QuotaDetailRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _QuotaDetailReadPage() when $default != null:
return $default(_that.listId,_that.offset,_that.total,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaDetailReadPage implements QuotaDetailReadPage {
  const _QuotaDetailReadPage({required this.listId, required this.offset, required this.total, required  List<QuotaDetailRead> items, required this.nextOffset}): _items = items;


@override final  int listId;
@override final  int offset;
@override final  int total;
 final  List<QuotaDetailRead> _items;
@override List<QuotaDetailRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of QuotaDetailReadPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaDetailReadPageCopyWith<_QuotaDetailReadPage> get copyWith => __$QuotaDetailReadPageCopyWithImpl<_QuotaDetailReadPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaDetailReadPage&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.total, total) || other.total == total)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,offset,total,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$QuotaDetailReadPageCopyWith<$Res> implements $QuotaDetailReadPageCopyWith<$Res> {
  factory _$QuotaDetailReadPageCopyWith(_QuotaDetailReadPage value, $Res Function(_QuotaDetailReadPage) _then) = __$QuotaDetailReadPageCopyWithImpl;
@override @useResult
$Res call({
 int listId, int offset, int total, List<QuotaDetailRead> items, int? nextOffset
});




}
/// @nodoc
class __$QuotaDetailReadPageCopyWithImpl<$Res>
    implements _$QuotaDetailReadPageCopyWith<$Res> {
  __$QuotaDetailReadPageCopyWithImpl(this._self, this._then);

  final _QuotaDetailReadPage _self;
  final $Res Function(_QuotaDetailReadPage) _then;

/// Create a copy of QuotaDetailReadPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_QuotaDetailReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<QuotaDetailRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
