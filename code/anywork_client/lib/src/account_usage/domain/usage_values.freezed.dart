// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'usage_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountUsageQueryIdentity {

 String get accountId; int get usageQueryRevision; String get ownerEpoch;
/// Create a copy of AccountUsageQueryIdentity
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageQueryIdentityCopyWith<AccountUsageQueryIdentity> get copyWith => _$AccountUsageQueryIdentityCopyWithImpl<AccountUsageQueryIdentity>(this as AccountUsageQueryIdentity, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageQueryIdentity;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageQueryIdentity&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.usageQueryRevision, _this.usageQueryRevision) || other.usageQueryRevision == _this.usageQueryRevision)&&(identical(other.ownerEpoch, _this.ownerEpoch) || other.ownerEpoch == _this.ownerEpoch));
}


@override
int get hashCode {
  final _this = this as AccountUsageQueryIdentity;
  return Object.hash(runtimeType,_this.accountId,_this.usageQueryRevision,_this.ownerEpoch);
}

@override
String toString() {
  final _this = this as AccountUsageQueryIdentity;
  return 'AccountUsageQueryIdentity(accountId: ${_this.accountId}, usageQueryRevision: ${_this.usageQueryRevision}, ownerEpoch: ${_this.ownerEpoch})';
}


}

/// @nodoc
abstract mixin class $AccountUsageQueryIdentityCopyWith<$Res>  {
  factory $AccountUsageQueryIdentityCopyWith(AccountUsageQueryIdentity value, $Res Function(AccountUsageQueryIdentity) _then) = _$AccountUsageQueryIdentityCopyWithImpl;
@useResult
$Res call({
 String accountId, int usageQueryRevision, String ownerEpoch
});




}
/// @nodoc
class _$AccountUsageQueryIdentityCopyWithImpl<$Res>
    implements $AccountUsageQueryIdentityCopyWith<$Res> {
  _$AccountUsageQueryIdentityCopyWithImpl(this._self, this._then);

  final AccountUsageQueryIdentity _self;
  final $Res Function(AccountUsageQueryIdentity) _then;

/// Create a copy of AccountUsageQueryIdentity
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? usageQueryRevision = null,Object? ownerEpoch = null,}) {
  return _then(AccountUsageQueryIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountUsageQueryIdentity].
extension AccountUsageQueryIdentityPatterns on AccountUsageQueryIdentity {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageQueryIdentity value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageQueryIdentity value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageQueryIdentity value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  int usageQueryRevision,  String ownerEpoch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity() when $default != null:
return $default(_that.accountId,_that.usageQueryRevision,_that.ownerEpoch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  int usageQueryRevision,  String ownerEpoch)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity():
return $default(_that.accountId,_that.usageQueryRevision,_that.ownerEpoch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  int usageQueryRevision,  String ownerEpoch)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageQueryIdentity() when $default != null:
return $default(_that.accountId,_that.usageQueryRevision,_that.ownerEpoch);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageQueryIdentity implements AccountUsageQueryIdentity {
  const _AccountUsageQueryIdentity({required this.accountId, required this.usageQueryRevision, required this.ownerEpoch});


@override final  String accountId;
@override final  int usageQueryRevision;
@override final  String ownerEpoch;

/// Create a copy of AccountUsageQueryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageQueryIdentityCopyWith<_AccountUsageQueryIdentity> get copyWith => __$AccountUsageQueryIdentityCopyWithImpl<_AccountUsageQueryIdentity>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageQueryIdentity&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.usageQueryRevision, usageQueryRevision) || other.usageQueryRevision == usageQueryRevision)&&(identical(other.ownerEpoch, ownerEpoch) || other.ownerEpoch == ownerEpoch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,usageQueryRevision,ownerEpoch);
}

@override
String toString() {
    return 'AccountUsageQueryIdentity(accountId: $accountId, usageQueryRevision: $usageQueryRevision, ownerEpoch: $ownerEpoch)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageQueryIdentityCopyWith<$Res> implements $AccountUsageQueryIdentityCopyWith<$Res> {
  factory _$AccountUsageQueryIdentityCopyWith(_AccountUsageQueryIdentity value, $Res Function(_AccountUsageQueryIdentity) _then) = __$AccountUsageQueryIdentityCopyWithImpl;
@override @useResult
$Res call({
 String accountId, int usageQueryRevision, String ownerEpoch
});




}
/// @nodoc
class __$AccountUsageQueryIdentityCopyWithImpl<$Res>
    implements _$AccountUsageQueryIdentityCopyWith<$Res> {
  __$AccountUsageQueryIdentityCopyWithImpl(this._self, this._then);

  final _AccountUsageQueryIdentity _self;
  final $Res Function(_AccountUsageQueryIdentity) _then;

/// Create a copy of AccountUsageQueryIdentity
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? usageQueryRevision = null,Object? ownerEpoch = null,}) {
  return _then(_AccountUsageQueryIdentity(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,usageQueryRevision: null == usageQueryRevision ? _self.usageQueryRevision : usageQueryRevision // ignore: cast_nullable_to_non_nullable
as int,ownerEpoch: null == ownerEpoch ? _self.ownerEpoch : ownerEpoch // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AccountUsageValue {

 String get configFingerprint; List<AccountUsageRecord> get usages;
/// Create a copy of AccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageValueCopyWith<AccountUsageValue> get copyWith => _$AccountUsageValueCopyWithImpl<AccountUsageValue>(this as AccountUsageValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageValue&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint)&&const DeepCollectionEquality().equals(other.usages, _this.usages));
}


@override
int get hashCode {
  final _this = this as AccountUsageValue;
  return Object.hash(runtimeType,_this.configFingerprint,const DeepCollectionEquality().hash(_this.usages));
}

@override
String toString() {
  final _this = this as AccountUsageValue;
  return 'AccountUsageValue(configFingerprint: ${_this.configFingerprint}, usages: ${_this.usages})';
}


}

/// @nodoc
abstract mixin class $AccountUsageValueCopyWith<$Res>  {
  factory $AccountUsageValueCopyWith(AccountUsageValue value, $Res Function(AccountUsageValue) _then) = _$AccountUsageValueCopyWithImpl;
@useResult
$Res call({
 String configFingerprint, List<AccountUsageRecord> usages
});




}
/// @nodoc
class _$AccountUsageValueCopyWithImpl<$Res>
    implements $AccountUsageValueCopyWith<$Res> {
  _$AccountUsageValueCopyWithImpl(this._self, this._then);

  final AccountUsageValue _self;
  final $Res Function(AccountUsageValue) _then;

/// Create a copy of AccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? configFingerprint = null,Object? usages = null,}) {
  return _then(AccountUsageValue(
configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as String,usages: null == usages ? _self.usages : usages // ignore: cast_nullable_to_non_nullable
as List<AccountUsageRecord>,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountUsageValue].
extension AccountUsageValuePatterns on AccountUsageValue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageValue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageValue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageValue value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageValue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageValue value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageValue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String configFingerprint,  List<AccountUsageRecord> usages)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageValue() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String configFingerprint,  List<AccountUsageRecord> usages)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageValue():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String configFingerprint,  List<AccountUsageRecord> usages)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageValue() when $default != null:
return $default(_that.configFingerprint,_that.usages);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageValue implements AccountUsageValue {
  const _AccountUsageValue({required this.configFingerprint, required  List<AccountUsageRecord> usages}): _usages = usages;


@override final  String configFingerprint;
 final  List<AccountUsageRecord> _usages;
@override List<AccountUsageRecord> get usages {
  if (_usages is EqualUnmodifiableListView) return _usages;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_usages);
}


/// Create a copy of AccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageValueCopyWith<_AccountUsageValue> get copyWith => __$AccountUsageValueCopyWithImpl<_AccountUsageValue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageValue&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint)&&const DeepCollectionEquality().equals(other.usages, _usages));
}


@override
int get hashCode {
    return Object.hash(runtimeType,configFingerprint,const DeepCollectionEquality().hash(_usages));
}

@override
String toString() {
    return 'AccountUsageValue(configFingerprint: $configFingerprint, usages: $usages)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageValueCopyWith<$Res> implements $AccountUsageValueCopyWith<$Res> {
  factory _$AccountUsageValueCopyWith(_AccountUsageValue value, $Res Function(_AccountUsageValue) _then) = __$AccountUsageValueCopyWithImpl;
@override @useResult
$Res call({
 String configFingerprint, List<AccountUsageRecord> usages
});




}
/// @nodoc
class __$AccountUsageValueCopyWithImpl<$Res>
    implements _$AccountUsageValueCopyWith<$Res> {
  __$AccountUsageValueCopyWithImpl(this._self, this._then);

  final _AccountUsageValue _self;
  final $Res Function(_AccountUsageValue) _then;

/// Create a copy of AccountUsageValue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? configFingerprint = null,Object? usages = null,}) {
  return _then(_AccountUsageValue(
configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as String,usages: null == usages ? _self._usages : usages // ignore: cast_nullable_to_non_nullable
as List<AccountUsageRecord>,
  ));
}


}

/// @nodoc
mixin _$AccountUsageRecord {

 String get accountId; int get revision; int get updatedAt; String get lastOperationId; AccountUsageResult get state;
/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountUsageRecordCopyWith<AccountUsageRecord> get copyWith => _$AccountUsageRecordCopyWithImpl<AccountUsageRecord>(this as AccountUsageRecord, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountUsageRecord;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageRecord&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt)&&(identical(other.lastOperationId, _this.lastOperationId) || other.lastOperationId == _this.lastOperationId)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as AccountUsageRecord;
  return Object.hash(runtimeType,_this.accountId,_this.revision,_this.updatedAt,_this.lastOperationId,_this.state);
}

@override
String toString() {
  final _this = this as AccountUsageRecord;
  return 'AccountUsageRecord(accountId: ${_this.accountId}, revision: ${_this.revision}, updatedAt: ${_this.updatedAt}, lastOperationId: ${_this.lastOperationId}, state: ${_this.state})';
}


}

/// @nodoc
abstract mixin class $AccountUsageRecordCopyWith<$Res>  {
  factory $AccountUsageRecordCopyWith(AccountUsageRecord value, $Res Function(AccountUsageRecord) _then) = _$AccountUsageRecordCopyWithImpl;
@useResult
$Res call({
 String accountId, int revision, int updatedAt, String lastOperationId, AccountUsageResult state
});


$AccountUsageResultCopyWith<$Res> get state;

}
/// @nodoc
class _$AccountUsageRecordCopyWithImpl<$Res>
    implements $AccountUsageRecordCopyWith<$Res> {
  _$AccountUsageRecordCopyWithImpl(this._self, this._then);

  final AccountUsageRecord _self;
  final $Res Function(AccountUsageRecord) _then;

/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? revision = null,Object? updatedAt = null,Object? lastOperationId = null,Object? state = null,}) {
  return _then(AccountUsageRecord(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOperationId: null == lastOperationId ? _self.lastOperationId : lastOperationId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AccountUsageResult,
  ));
}
/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageResultCopyWith<$Res> get state {

  return $AccountUsageResultCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountUsageRecord].
extension AccountUsageRecordPatterns on AccountUsageRecord {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountUsageRecord value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountUsageRecord() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountUsageRecord value)  $default,){
final _that = this;
switch (_that) {
case _AccountUsageRecord():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountUsageRecord value)?  $default,){
final _that = this;
switch (_that) {
case _AccountUsageRecord() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  int revision,  int updatedAt,  String lastOperationId,  AccountUsageResult state)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountUsageRecord() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  int revision,  int updatedAt,  String lastOperationId,  AccountUsageResult state)  $default,) {final _that = this;
switch (_that) {
case _AccountUsageRecord():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  int revision,  int updatedAt,  String lastOperationId,  AccountUsageResult state)?  $default,) {final _that = this;
switch (_that) {
case _AccountUsageRecord() when $default != null:
return $default(_that.accountId,_that.revision,_that.updatedAt,_that.lastOperationId,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class _AccountUsageRecord implements AccountUsageRecord {
  const _AccountUsageRecord({required this.accountId, required this.revision, required this.updatedAt, required this.lastOperationId, required this.state});


@override final  String accountId;
@override final  int revision;
@override final  int updatedAt;
@override final  String lastOperationId;
@override final  AccountUsageResult state;

/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountUsageRecordCopyWith<_AccountUsageRecord> get copyWith => __$AccountUsageRecordCopyWithImpl<_AccountUsageRecord>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountUsageRecord&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastOperationId, lastOperationId) || other.lastOperationId == lastOperationId)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,revision,updatedAt,lastOperationId,state);
}

@override
String toString() {
    return 'AccountUsageRecord(accountId: $accountId, revision: $revision, updatedAt: $updatedAt, lastOperationId: $lastOperationId, state: $state)';
}


}

/// @nodoc
abstract mixin class _$AccountUsageRecordCopyWith<$Res> implements $AccountUsageRecordCopyWith<$Res> {
  factory _$AccountUsageRecordCopyWith(_AccountUsageRecord value, $Res Function(_AccountUsageRecord) _then) = __$AccountUsageRecordCopyWithImpl;
@override @useResult
$Res call({
 String accountId, int revision, int updatedAt, String lastOperationId, AccountUsageResult state
});


@override $AccountUsageResultCopyWith<$Res> get state;

}
/// @nodoc
class __$AccountUsageRecordCopyWithImpl<$Res>
    implements _$AccountUsageRecordCopyWith<$Res> {
  __$AccountUsageRecordCopyWithImpl(this._self, this._then);

  final _AccountUsageRecord _self;
  final $Res Function(_AccountUsageRecord) _then;

/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? revision = null,Object? updatedAt = null,Object? lastOperationId = null,Object? state = null,}) {
  return _then(_AccountUsageRecord(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastOperationId: null == lastOperationId ? _self.lastOperationId : lastOperationId // ignore: cast_nullable_to_non_nullable
as String,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as AccountUsageResult,
  ));
}

/// Create a copy of AccountUsageRecord
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageResultCopyWith<$Res> get state {

  return $AccountUsageResultCopyWith<$Res>(_self.state, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageResult {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageResult);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountUsageResult()';
}


}

/// @nodoc
class $AccountUsageResultCopyWith<$Res>  {
$AccountUsageResultCopyWith(AccountUsageResult _, $Res Function(AccountUsageResult) __);
}


/// Adds pattern-matching-related methods to [AccountUsageResult].
extension AccountUsageResultPatterns on AccountUsageResult {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UsageUnsupported value)?  unsupported,TResult Function( UsageMissingCredential value)?  missingCredential,TResult Function( UsageReady value)?  ready,TResult Function( UsageFailed value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UsageUnsupported() when unsupported != null:
return unsupported(_that);case UsageMissingCredential() when missingCredential != null:
return missingCredential(_that);case UsageReady() when ready != null:
return ready(_that);case UsageFailed() when failed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UsageUnsupported value)  unsupported,required TResult Function( UsageMissingCredential value)  missingCredential,required TResult Function( UsageReady value)  ready,required TResult Function( UsageFailed value)  failed,}){
final _that = this;
switch (_that) {
case UsageUnsupported():
return unsupported(_that);case UsageMissingCredential():
return missingCredential(_that);case UsageReady():
return ready(_that);case UsageFailed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UsageUnsupported value)?  unsupported,TResult? Function( UsageMissingCredential value)?  missingCredential,TResult? Function( UsageReady value)?  ready,TResult? Function( UsageFailed value)?  failed,}){
final _that = this;
switch (_that) {
case UsageUnsupported() when unsupported != null:
return unsupported(_that);case UsageMissingCredential() when missingCredential != null:
return missingCredential(_that);case UsageReady() when ready != null:
return ready(_that);case UsageFailed() when failed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  unsupported,TResult Function( String message)?  missingCredential,TResult Function( AccountUsageData data)?  ready,TResult Function( SourceStateError error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UsageUnsupported() when unsupported != null:
return unsupported();case UsageMissingCredential() when missingCredential != null:
return missingCredential(_that.message);case UsageReady() when ready != null:
return ready(_that.data);case UsageFailed() when failed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  unsupported,required TResult Function( String message)  missingCredential,required TResult Function( AccountUsageData data)  ready,required TResult Function( SourceStateError error)  failed,}) {final _that = this;
switch (_that) {
case UsageUnsupported():
return unsupported();case UsageMissingCredential():
return missingCredential(_that.message);case UsageReady():
return ready(_that.data);case UsageFailed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  unsupported,TResult? Function( String message)?  missingCredential,TResult? Function( AccountUsageData data)?  ready,TResult? Function( SourceStateError error)?  failed,}) {final _that = this;
switch (_that) {
case UsageUnsupported() when unsupported != null:
return unsupported();case UsageMissingCredential() when missingCredential != null:
return missingCredential(_that.message);case UsageReady() when ready != null:
return ready(_that.data);case UsageFailed() when failed != null:
return failed(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class UsageUnsupported implements AccountUsageResult {
  const UsageUnsupported();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageUnsupported);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountUsageResult.unsupported()';
}


}




/// @nodoc


class UsageMissingCredential implements AccountUsageResult {
  const UsageMissingCredential({required this.message});


 final  String message;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageMissingCredentialCopyWith<UsageMissingCredential> get copyWith => _$UsageMissingCredentialCopyWithImpl<UsageMissingCredential>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageMissingCredential&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,message);
}

@override
String toString() {
    return 'AccountUsageResult.missingCredential(message: $message)';
}


}

/// @nodoc
abstract mixin class $UsageMissingCredentialCopyWith<$Res> implements $AccountUsageResultCopyWith<$Res> {
  factory $UsageMissingCredentialCopyWith(UsageMissingCredential value, $Res Function(UsageMissingCredential) _then) = _$UsageMissingCredentialCopyWithImpl;
@useResult
$Res call({
 String message
});




}
/// @nodoc
class _$UsageMissingCredentialCopyWithImpl<$Res>
    implements $UsageMissingCredentialCopyWith<$Res> {
  _$UsageMissingCredentialCopyWithImpl(this._self, this._then);

  final UsageMissingCredential _self;
  final $Res Function(UsageMissingCredential) _then;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? message = null,}) {
  return _then(UsageMissingCredential(
message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class UsageReady implements AccountUsageResult {
  const UsageReady({required this.data});


 final  AccountUsageData data;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageReadyCopyWith<UsageReady> get copyWith => _$UsageReadyCopyWithImpl<UsageReady>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageReady&&(identical(other.data, data) || other.data == data));
}


@override
int get hashCode {
    return Object.hash(runtimeType,data);
}

@override
String toString() {
    return 'AccountUsageResult.ready(data: $data)';
}


}

/// @nodoc
abstract mixin class $UsageReadyCopyWith<$Res> implements $AccountUsageResultCopyWith<$Res> {
  factory $UsageReadyCopyWith(UsageReady value, $Res Function(UsageReady) _then) = _$UsageReadyCopyWithImpl;
@useResult
$Res call({
 AccountUsageData data
});


$AccountUsageDataCopyWith<$Res> get data;

}
/// @nodoc
class _$UsageReadyCopyWithImpl<$Res>
    implements $UsageReadyCopyWith<$Res> {
  _$UsageReadyCopyWithImpl(this._self, this._then);

  final UsageReady _self;
  final $Res Function(UsageReady) _then;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? data = null,}) {
  return _then(UsageReady(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as AccountUsageData,
  ));
}

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountUsageDataCopyWith<$Res> get data {

  return $AccountUsageDataCopyWith<$Res>(_self.data, (value) {
    return _then(_self.copyWith(data: value));
  });
}
}

/// @nodoc


class UsageFailed implements AccountUsageResult {
  const UsageFailed({required this.error});


 final  SourceStateError error;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UsageFailedCopyWith<UsageFailed> get copyWith => _$UsageFailedCopyWithImpl<UsageFailed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UsageFailed&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}

@override
String toString() {
    return 'AccountUsageResult.failed(error: $error)';
}


}

/// @nodoc
abstract mixin class $UsageFailedCopyWith<$Res> implements $AccountUsageResultCopyWith<$Res> {
  factory $UsageFailedCopyWith(UsageFailed value, $Res Function(UsageFailed) _then) = _$UsageFailedCopyWithImpl;
@useResult
$Res call({
 SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$UsageFailedCopyWithImpl<$Res>
    implements $UsageFailedCopyWith<$Res> {
  _$UsageFailedCopyWithImpl(this._self, this._then);

  final UsageFailed _self;
  final $Res Function(UsageFailed) _then;

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(UsageFailed(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of AccountUsageResult
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AccountUsageData {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountUsageData);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'AccountUsageData()';
}


}

/// @nodoc
class $AccountUsageDataCopyWith<$Res>  {
$AccountUsageDataCopyWith(AccountUsageData _, $Res Function(AccountUsageData) __);
}


/// Adds pattern-matching-related methods to [AccountUsageData].
extension AccountUsageDataPatterns on AccountUsageData {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DeepSeekBalance value)?  deepSeekBalance,TResult Function( ZhipuCodingPlan value)?  zhipuCodingPlan,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DeepSeekBalance() when deepSeekBalance != null:
return deepSeekBalance(_that);case ZhipuCodingPlan() when zhipuCodingPlan != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DeepSeekBalance value)  deepSeekBalance,required TResult Function( ZhipuCodingPlan value)  zhipuCodingPlan,}){
final _that = this;
switch (_that) {
case DeepSeekBalance():
return deepSeekBalance(_that);case ZhipuCodingPlan():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DeepSeekBalance value)?  deepSeekBalance,TResult? Function( ZhipuCodingPlan value)?  zhipuCodingPlan,}){
final _that = this;
switch (_that) {
case DeepSeekBalance() when deepSeekBalance != null:
return deepSeekBalance(_that);case ZhipuCodingPlan() when zhipuCodingPlan != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( bool isAvailable,  List<Balance> balances)?  deepSeekBalance,TResult Function( String? level,  List<QuotaLimit> limits)?  zhipuCodingPlan,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DeepSeekBalance() when deepSeekBalance != null:
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlan() when zhipuCodingPlan != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( bool isAvailable,  List<Balance> balances)  deepSeekBalance,required TResult Function( String? level,  List<QuotaLimit> limits)  zhipuCodingPlan,}) {final _that = this;
switch (_that) {
case DeepSeekBalance():
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlan():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( bool isAvailable,  List<Balance> balances)?  deepSeekBalance,TResult? Function( String? level,  List<QuotaLimit> limits)?  zhipuCodingPlan,}) {final _that = this;
switch (_that) {
case DeepSeekBalance() when deepSeekBalance != null:
return deepSeekBalance(_that.isAvailable,_that.balances);case ZhipuCodingPlan() when zhipuCodingPlan != null:
return zhipuCodingPlan(_that.level,_that.limits);case _:
  return null;

}
}

}

/// @nodoc


class DeepSeekBalance implements AccountUsageData {
  const DeepSeekBalance({required this.isAvailable, required  List<Balance> balances}): _balances = balances;


 final  bool isAvailable;
 final  List<Balance> _balances;
 List<Balance> get balances {
  if (_balances is EqualUnmodifiableListView) return _balances;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_balances);
}


/// Create a copy of AccountUsageData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeepSeekBalanceCopyWith<DeepSeekBalance> get copyWith => _$DeepSeekBalanceCopyWithImpl<DeepSeekBalance>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeepSeekBalance&&(identical(other.isAvailable, isAvailable) || other.isAvailable == isAvailable)&&const DeepCollectionEquality().equals(other.balances, _balances));
}


@override
int get hashCode {
    return Object.hash(runtimeType,isAvailable,const DeepCollectionEquality().hash(_balances));
}

@override
String toString() {
    return 'AccountUsageData.deepSeekBalance(isAvailable: $isAvailable, balances: $balances)';
}


}

/// @nodoc
abstract mixin class $DeepSeekBalanceCopyWith<$Res> implements $AccountUsageDataCopyWith<$Res> {
  factory $DeepSeekBalanceCopyWith(DeepSeekBalance value, $Res Function(DeepSeekBalance) _then) = _$DeepSeekBalanceCopyWithImpl;
@useResult
$Res call({
 bool isAvailable, List<Balance> balances
});




}
/// @nodoc
class _$DeepSeekBalanceCopyWithImpl<$Res>
    implements $DeepSeekBalanceCopyWith<$Res> {
  _$DeepSeekBalanceCopyWithImpl(this._self, this._then);

  final DeepSeekBalance _self;
  final $Res Function(DeepSeekBalance) _then;

/// Create a copy of AccountUsageData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? isAvailable = null,Object? balances = null,}) {
  return _then(DeepSeekBalance(
isAvailable: null == isAvailable ? _self.isAvailable : isAvailable // ignore: cast_nullable_to_non_nullable
as bool,balances: null == balances ? _self._balances : balances // ignore: cast_nullable_to_non_nullable
as List<Balance>,
  ));
}


}

/// @nodoc


class ZhipuCodingPlan implements AccountUsageData {
  const ZhipuCodingPlan({required this.level, required  List<QuotaLimit> limits}): _limits = limits;


 final  String? level;
 final  List<QuotaLimit> _limits;
 List<QuotaLimit> get limits {
  if (_limits is EqualUnmodifiableListView) return _limits;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_limits);
}


/// Create a copy of AccountUsageData
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ZhipuCodingPlanCopyWith<ZhipuCodingPlan> get copyWith => _$ZhipuCodingPlanCopyWithImpl<ZhipuCodingPlan>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ZhipuCodingPlan&&(identical(other.level, level) || other.level == level)&&const DeepCollectionEquality().equals(other.limits, _limits));
}


@override
int get hashCode {
    return Object.hash(runtimeType,level,const DeepCollectionEquality().hash(_limits));
}

@override
String toString() {
    return 'AccountUsageData.zhipuCodingPlan(level: $level, limits: $limits)';
}


}

/// @nodoc
abstract mixin class $ZhipuCodingPlanCopyWith<$Res> implements $AccountUsageDataCopyWith<$Res> {
  factory $ZhipuCodingPlanCopyWith(ZhipuCodingPlan value, $Res Function(ZhipuCodingPlan) _then) = _$ZhipuCodingPlanCopyWithImpl;
@useResult
$Res call({
 String? level, List<QuotaLimit> limits
});




}
/// @nodoc
class _$ZhipuCodingPlanCopyWithImpl<$Res>
    implements $ZhipuCodingPlanCopyWith<$Res> {
  _$ZhipuCodingPlanCopyWithImpl(this._self, this._then);

  final ZhipuCodingPlan _self;
  final $Res Function(ZhipuCodingPlan) _then;

/// Create a copy of AccountUsageData
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? level = freezed,Object? limits = null,}) {
  return _then(ZhipuCodingPlan(
level: freezed == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as String?,limits: null == limits ? _self._limits : limits // ignore: cast_nullable_to_non_nullable
as List<QuotaLimit>,
  ));
}


}

/// @nodoc
mixin _$Balance {

 String get currency; String get totalBalance; String get grantedBalance; String get toppedUpBalance;
/// Create a copy of Balance
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BalanceCopyWith<Balance> get copyWith => _$BalanceCopyWithImpl<Balance>(this as Balance, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as Balance;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is Balance&&(identical(other.currency, _this.currency) || other.currency == _this.currency)&&(identical(other.totalBalance, _this.totalBalance) || other.totalBalance == _this.totalBalance)&&(identical(other.grantedBalance, _this.grantedBalance) || other.grantedBalance == _this.grantedBalance)&&(identical(other.toppedUpBalance, _this.toppedUpBalance) || other.toppedUpBalance == _this.toppedUpBalance));
}


@override
int get hashCode {
  final _this = this as Balance;
  return Object.hash(runtimeType,_this.currency,_this.totalBalance,_this.grantedBalance,_this.toppedUpBalance);
}

@override
String toString() {
  final _this = this as Balance;
  return 'Balance(currency: ${_this.currency}, totalBalance: ${_this.totalBalance}, grantedBalance: ${_this.grantedBalance}, toppedUpBalance: ${_this.toppedUpBalance})';
}


}

/// @nodoc
abstract mixin class $BalanceCopyWith<$Res>  {
  factory $BalanceCopyWith(Balance value, $Res Function(Balance) _then) = _$BalanceCopyWithImpl;
@useResult
$Res call({
 String currency, String totalBalance, String grantedBalance, String toppedUpBalance
});




}
/// @nodoc
class _$BalanceCopyWithImpl<$Res>
    implements $BalanceCopyWith<$Res> {
  _$BalanceCopyWithImpl(this._self, this._then);

  final Balance _self;
  final $Res Function(Balance) _then;

/// Create a copy of Balance
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? currency = null,Object? totalBalance = null,Object? grantedBalance = null,Object? toppedUpBalance = null,}) {
  return _then(Balance(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,totalBalance: null == totalBalance ? _self.totalBalance : totalBalance // ignore: cast_nullable_to_non_nullable
as String,grantedBalance: null == grantedBalance ? _self.grantedBalance : grantedBalance // ignore: cast_nullable_to_non_nullable
as String,toppedUpBalance: null == toppedUpBalance ? _self.toppedUpBalance : toppedUpBalance // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [Balance].
extension BalancePatterns on Balance {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _Balance value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Balance() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _Balance value)  $default,){
final _that = this;
switch (_that) {
case _Balance():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _Balance value)?  $default,){
final _that = this;
switch (_that) {
case _Balance() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String currency,  String totalBalance,  String grantedBalance,  String toppedUpBalance)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Balance() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String currency,  String totalBalance,  String grantedBalance,  String toppedUpBalance)  $default,) {final _that = this;
switch (_that) {
case _Balance():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String currency,  String totalBalance,  String grantedBalance,  String toppedUpBalance)?  $default,) {final _that = this;
switch (_that) {
case _Balance() when $default != null:
return $default(_that.currency,_that.totalBalance,_that.grantedBalance,_that.toppedUpBalance);case _:
  return null;

}
}

}

/// @nodoc


class _Balance implements Balance {
  const _Balance({required this.currency, required this.totalBalance, required this.grantedBalance, required this.toppedUpBalance});


@override final  String currency;
@override final  String totalBalance;
@override final  String grantedBalance;
@override final  String toppedUpBalance;

/// Create a copy of Balance
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BalanceCopyWith<_Balance> get copyWith => __$BalanceCopyWithImpl<_Balance>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _Balance&&(identical(other.currency, currency) || other.currency == currency)&&(identical(other.totalBalance, totalBalance) || other.totalBalance == totalBalance)&&(identical(other.grantedBalance, grantedBalance) || other.grantedBalance == grantedBalance)&&(identical(other.toppedUpBalance, toppedUpBalance) || other.toppedUpBalance == toppedUpBalance));
}


@override
int get hashCode {
    return Object.hash(runtimeType,currency,totalBalance,grantedBalance,toppedUpBalance);
}

@override
String toString() {
    return 'Balance(currency: $currency, totalBalance: $totalBalance, grantedBalance: $grantedBalance, toppedUpBalance: $toppedUpBalance)';
}


}

/// @nodoc
abstract mixin class _$BalanceCopyWith<$Res> implements $BalanceCopyWith<$Res> {
  factory _$BalanceCopyWith(_Balance value, $Res Function(_Balance) _then) = __$BalanceCopyWithImpl;
@override @useResult
$Res call({
 String currency, String totalBalance, String grantedBalance, String toppedUpBalance
});




}
/// @nodoc
class __$BalanceCopyWithImpl<$Res>
    implements _$BalanceCopyWith<$Res> {
  __$BalanceCopyWithImpl(this._self, this._then);

  final _Balance _self;
  final $Res Function(_Balance) _then;

/// Create a copy of Balance
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? currency = null,Object? totalBalance = null,Object? grantedBalance = null,Object? toppedUpBalance = null,}) {
  return _then(_Balance(
currency: null == currency ? _self.currency : currency // ignore: cast_nullable_to_non_nullable
as String,totalBalance: null == totalBalance ? _self.totalBalance : totalBalance // ignore: cast_nullable_to_non_nullable
as String,grantedBalance: null == grantedBalance ? _self.grantedBalance : grantedBalance // ignore: cast_nullable_to_non_nullable
as String,toppedUpBalance: null == toppedUpBalance ? _self.toppedUpBalance : toppedUpBalance // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$QuotaLimit {

 QuotaWindow get window; double get percentage; double? get currentValue; double? get total; double? get remaining; int? get nextResetAt; List<QuotaDetail> get usageDetails;
/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaLimitCopyWith<QuotaLimit> get copyWith => _$QuotaLimitCopyWithImpl<QuotaLimit>(this as QuotaLimit, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaLimit;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaLimit&&(identical(other.window, _this.window) || other.window == _this.window)&&(identical(other.percentage, _this.percentage) || other.percentage == _this.percentage)&&(identical(other.currentValue, _this.currentValue) || other.currentValue == _this.currentValue)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.remaining, _this.remaining) || other.remaining == _this.remaining)&&(identical(other.nextResetAt, _this.nextResetAt) || other.nextResetAt == _this.nextResetAt)&&const DeepCollectionEquality().equals(other.usageDetails, _this.usageDetails));
}


@override
int get hashCode {
  final _this = this as QuotaLimit;
  return Object.hash(runtimeType,_this.window,_this.percentage,_this.currentValue,_this.total,_this.remaining,_this.nextResetAt,const DeepCollectionEquality().hash(_this.usageDetails));
}

@override
String toString() {
  final _this = this as QuotaLimit;
  return 'QuotaLimit(window: ${_this.window}, percentage: ${_this.percentage}, currentValue: ${_this.currentValue}, total: ${_this.total}, remaining: ${_this.remaining}, nextResetAt: ${_this.nextResetAt}, usageDetails: ${_this.usageDetails})';
}


}

/// @nodoc
abstract mixin class $QuotaLimitCopyWith<$Res>  {
  factory $QuotaLimitCopyWith(QuotaLimit value, $Res Function(QuotaLimit) _then) = _$QuotaLimitCopyWithImpl;
@useResult
$Res call({
 QuotaWindow window, double percentage, double? currentValue, double? total, double? remaining, int? nextResetAt, List<QuotaDetail> usageDetails
});


$QuotaWindowCopyWith<$Res> get window;

}
/// @nodoc
class _$QuotaLimitCopyWithImpl<$Res>
    implements $QuotaLimitCopyWith<$Res> {
  _$QuotaLimitCopyWithImpl(this._self, this._then);

  final QuotaLimit _self;
  final $Res Function(QuotaLimit) _then;

/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? window = null,Object? percentage = null,Object? currentValue = freezed,Object? total = freezed,Object? remaining = freezed,Object? nextResetAt = freezed,Object? usageDetails = null,}) {
  return _then(QuotaLimit(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as QuotaWindow,percentage: null == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,remaining: freezed == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as double?,nextResetAt: freezed == nextResetAt ? _self.nextResetAt : nextResetAt // ignore: cast_nullable_to_non_nullable
as int?,usageDetails: null == usageDetails ? _self.usageDetails : usageDetails // ignore: cast_nullable_to_non_nullable
as List<QuotaDetail>,
  ));
}
/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuotaWindowCopyWith<$Res> get window {

  return $QuotaWindowCopyWith<$Res>(_self.window, (value) {
    return _then(_self.copyWith(window: value));
  });
}
}


/// Adds pattern-matching-related methods to [QuotaLimit].
extension QuotaLimitPatterns on QuotaLimit {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaLimit value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaLimit() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaLimit value)  $default,){
final _that = this;
switch (_that) {
case _QuotaLimit():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaLimit value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaLimit() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( QuotaWindow window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  List<QuotaDetail> usageDetails)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaLimit() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( QuotaWindow window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  List<QuotaDetail> usageDetails)  $default,) {final _that = this;
switch (_that) {
case _QuotaLimit():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( QuotaWindow window,  double percentage,  double? currentValue,  double? total,  double? remaining,  int? nextResetAt,  List<QuotaDetail> usageDetails)?  $default,) {final _that = this;
switch (_that) {
case _QuotaLimit() when $default != null:
return $default(_that.window,_that.percentage,_that.currentValue,_that.total,_that.remaining,_that.nextResetAt,_that.usageDetails);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaLimit implements QuotaLimit {
  const _QuotaLimit({required this.window, required this.percentage, required this.currentValue, required this.total, required this.remaining, required this.nextResetAt, required  List<QuotaDetail> usageDetails}): _usageDetails = usageDetails;


@override final  QuotaWindow window;
@override final  double percentage;
@override final  double? currentValue;
@override final  double? total;
@override final  double? remaining;
@override final  int? nextResetAt;
 final  List<QuotaDetail> _usageDetails;
@override List<QuotaDetail> get usageDetails {
  if (_usageDetails is EqualUnmodifiableListView) return _usageDetails;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_usageDetails);
}


/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaLimitCopyWith<_QuotaLimit> get copyWith => __$QuotaLimitCopyWithImpl<_QuotaLimit>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaLimit&&(identical(other.window, window) || other.window == window)&&(identical(other.percentage, percentage) || other.percentage == percentage)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.total, total) || other.total == total)&&(identical(other.remaining, remaining) || other.remaining == remaining)&&(identical(other.nextResetAt, nextResetAt) || other.nextResetAt == nextResetAt)&&const DeepCollectionEquality().equals(other.usageDetails, _usageDetails));
}


@override
int get hashCode {
    return Object.hash(runtimeType,window,percentage,currentValue,total,remaining,nextResetAt,const DeepCollectionEquality().hash(_usageDetails));
}

@override
String toString() {
    return 'QuotaLimit(window: $window, percentage: $percentage, currentValue: $currentValue, total: $total, remaining: $remaining, nextResetAt: $nextResetAt, usageDetails: $usageDetails)';
}


}

/// @nodoc
abstract mixin class _$QuotaLimitCopyWith<$Res> implements $QuotaLimitCopyWith<$Res> {
  factory _$QuotaLimitCopyWith(_QuotaLimit value, $Res Function(_QuotaLimit) _then) = __$QuotaLimitCopyWithImpl;
@override @useResult
$Res call({
 QuotaWindow window, double percentage, double? currentValue, double? total, double? remaining, int? nextResetAt, List<QuotaDetail> usageDetails
});


@override $QuotaWindowCopyWith<$Res> get window;

}
/// @nodoc
class __$QuotaLimitCopyWithImpl<$Res>
    implements _$QuotaLimitCopyWith<$Res> {
  __$QuotaLimitCopyWithImpl(this._self, this._then);

  final _QuotaLimit _self;
  final $Res Function(_QuotaLimit) _then;

/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? window = null,Object? percentage = null,Object? currentValue = freezed,Object? total = freezed,Object? remaining = freezed,Object? nextResetAt = freezed,Object? usageDetails = null,}) {
  return _then(_QuotaLimit(
window: null == window ? _self.window : window // ignore: cast_nullable_to_non_nullable
as QuotaWindow,percentage: null == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,remaining: freezed == remaining ? _self.remaining : remaining // ignore: cast_nullable_to_non_nullable
as double?,nextResetAt: freezed == nextResetAt ? _self.nextResetAt : nextResetAt // ignore: cast_nullable_to_non_nullable
as int?,usageDetails: null == usageDetails ? _self._usageDetails : usageDetails // ignore: cast_nullable_to_non_nullable
as List<QuotaDetail>,
  ));
}

/// Create a copy of QuotaLimit
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$QuotaWindowCopyWith<$Res> get window {

  return $QuotaWindowCopyWith<$Res>(_self.window, (value) {
    return _then(_self.copyWith(window: value));
  });
}
}

/// @nodoc
mixin _$QuotaWindow {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaWindow);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QuotaWindow()';
}


}

/// @nodoc
class $QuotaWindowCopyWith<$Res>  {
$QuotaWindowCopyWith(QuotaWindow _, $Res Function(QuotaWindow) __);
}


/// Adds pattern-matching-related methods to [QuotaWindow].
extension QuotaWindowPatterns on QuotaWindow {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( FiveHourQuota value)?  fiveHour,TResult Function( WeeklyQuota value)?  weekly,TResult Function( McpMonthlyQuota value)?  mcpMonthly,TResult Function( OtherQuota value)?  other,required TResult orElse(),}){
final _that = this;
switch (_that) {
case FiveHourQuota() when fiveHour != null:
return fiveHour(_that);case WeeklyQuota() when weekly != null:
return weekly(_that);case McpMonthlyQuota() when mcpMonthly != null:
return mcpMonthly(_that);case OtherQuota() when other != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( FiveHourQuota value)  fiveHour,required TResult Function( WeeklyQuota value)  weekly,required TResult Function( McpMonthlyQuota value)  mcpMonthly,required TResult Function( OtherQuota value)  other,}){
final _that = this;
switch (_that) {
case FiveHourQuota():
return fiveHour(_that);case WeeklyQuota():
return weekly(_that);case McpMonthlyQuota():
return mcpMonthly(_that);case OtherQuota():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( FiveHourQuota value)?  fiveHour,TResult? Function( WeeklyQuota value)?  weekly,TResult? Function( McpMonthlyQuota value)?  mcpMonthly,TResult? Function( OtherQuota value)?  other,}){
final _that = this;
switch (_that) {
case FiveHourQuota() when fiveHour != null:
return fiveHour(_that);case WeeklyQuota() when weekly != null:
return weekly(_that);case McpMonthlyQuota() when mcpMonthly != null:
return mcpMonthly(_that);case OtherQuota() when other != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  fiveHour,TResult Function()?  weekly,TResult Function()?  mcpMonthly,TResult Function( String value)?  other,required TResult orElse(),}) {final _that = this;
switch (_that) {
case FiveHourQuota() when fiveHour != null:
return fiveHour();case WeeklyQuota() when weekly != null:
return weekly();case McpMonthlyQuota() when mcpMonthly != null:
return mcpMonthly();case OtherQuota() when other != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  fiveHour,required TResult Function()  weekly,required TResult Function()  mcpMonthly,required TResult Function( String value)  other,}) {final _that = this;
switch (_that) {
case FiveHourQuota():
return fiveHour();case WeeklyQuota():
return weekly();case McpMonthlyQuota():
return mcpMonthly();case OtherQuota():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  fiveHour,TResult? Function()?  weekly,TResult? Function()?  mcpMonthly,TResult? Function( String value)?  other,}) {final _that = this;
switch (_that) {
case FiveHourQuota() when fiveHour != null:
return fiveHour();case WeeklyQuota() when weekly != null:
return weekly();case McpMonthlyQuota() when mcpMonthly != null:
return mcpMonthly();case OtherQuota() when other != null:
return other(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class FiveHourQuota implements QuotaWindow {
  const FiveHourQuota();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FiveHourQuota);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QuotaWindow.fiveHour()';
}


}




/// @nodoc


class WeeklyQuota implements QuotaWindow {
  const WeeklyQuota();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is WeeklyQuota);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QuotaWindow.weekly()';
}


}




/// @nodoc


class McpMonthlyQuota implements QuotaWindow {
  const McpMonthlyQuota();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is McpMonthlyQuota);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'QuotaWindow.mcpMonthly()';
}


}




/// @nodoc


class OtherQuota implements QuotaWindow {
  const OtherQuota(this.value);


 final  String value;

/// Create a copy of QuotaWindow
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OtherQuotaCopyWith<OtherQuota> get copyWith => _$OtherQuotaCopyWithImpl<OtherQuota>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OtherQuota&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}

@override
String toString() {
    return 'QuotaWindow.other(value: $value)';
}


}

/// @nodoc
abstract mixin class $OtherQuotaCopyWith<$Res> implements $QuotaWindowCopyWith<$Res> {
  factory $OtherQuotaCopyWith(OtherQuota value, $Res Function(OtherQuota) _then) = _$OtherQuotaCopyWithImpl;
@useResult
$Res call({
 String value
});




}
/// @nodoc
class _$OtherQuotaCopyWithImpl<$Res>
    implements $OtherQuotaCopyWith<$Res> {
  _$OtherQuotaCopyWithImpl(this._self, this._then);

  final OtherQuota _self;
  final $Res Function(OtherQuota) _then;

/// Create a copy of QuotaWindow
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(OtherQuota(
null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$QuotaDetail {

 String get name; double? get currentValue; double? get total; double? get percentage;
/// Create a copy of QuotaDetail
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$QuotaDetailCopyWith<QuotaDetail> get copyWith => _$QuotaDetailCopyWithImpl<QuotaDetail>(this as QuotaDetail, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as QuotaDetail;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is QuotaDetail&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.currentValue, _this.currentValue) || other.currentValue == _this.currentValue)&&(identical(other.total, _this.total) || other.total == _this.total)&&(identical(other.percentage, _this.percentage) || other.percentage == _this.percentage));
}


@override
int get hashCode {
  final _this = this as QuotaDetail;
  return Object.hash(runtimeType,_this.name,_this.currentValue,_this.total,_this.percentage);
}

@override
String toString() {
  final _this = this as QuotaDetail;
  return 'QuotaDetail(name: ${_this.name}, currentValue: ${_this.currentValue}, total: ${_this.total}, percentage: ${_this.percentage})';
}


}

/// @nodoc
abstract mixin class $QuotaDetailCopyWith<$Res>  {
  factory $QuotaDetailCopyWith(QuotaDetail value, $Res Function(QuotaDetail) _then) = _$QuotaDetailCopyWithImpl;
@useResult
$Res call({
 String name, double? currentValue, double? total, double? percentage
});




}
/// @nodoc
class _$QuotaDetailCopyWithImpl<$Res>
    implements $QuotaDetailCopyWith<$Res> {
  _$QuotaDetailCopyWithImpl(this._self, this._then);

  final QuotaDetail _self;
  final $Res Function(QuotaDetail) _then;

/// Create a copy of QuotaDetail
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? currentValue = freezed,Object? total = freezed,Object? percentage = freezed,}) {
  return _then(QuotaDetail(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}

}


/// Adds pattern-matching-related methods to [QuotaDetail].
extension QuotaDetailPatterns on QuotaDetail {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _QuotaDetail value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _QuotaDetail() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _QuotaDetail value)  $default,){
final _that = this;
switch (_that) {
case _QuotaDetail():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _QuotaDetail value)?  $default,){
final _that = this;
switch (_that) {
case _QuotaDetail() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  double? currentValue,  double? total,  double? percentage)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _QuotaDetail() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  double? currentValue,  double? total,  double? percentage)  $default,) {final _that = this;
switch (_that) {
case _QuotaDetail():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  double? currentValue,  double? total,  double? percentage)?  $default,) {final _that = this;
switch (_that) {
case _QuotaDetail() when $default != null:
return $default(_that.name,_that.currentValue,_that.total,_that.percentage);case _:
  return null;

}
}

}

/// @nodoc


class _QuotaDetail implements QuotaDetail {
  const _QuotaDetail({required this.name, required this.currentValue, required this.total, required this.percentage});


@override final  String name;
@override final  double? currentValue;
@override final  double? total;
@override final  double? percentage;

/// Create a copy of QuotaDetail
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$QuotaDetailCopyWith<_QuotaDetail> get copyWith => __$QuotaDetailCopyWithImpl<_QuotaDetail>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _QuotaDetail&&(identical(other.name, name) || other.name == name)&&(identical(other.currentValue, currentValue) || other.currentValue == currentValue)&&(identical(other.total, total) || other.total == total)&&(identical(other.percentage, percentage) || other.percentage == percentage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,currentValue,total,percentage);
}

@override
String toString() {
    return 'QuotaDetail(name: $name, currentValue: $currentValue, total: $total, percentage: $percentage)';
}


}

/// @nodoc
abstract mixin class _$QuotaDetailCopyWith<$Res> implements $QuotaDetailCopyWith<$Res> {
  factory _$QuotaDetailCopyWith(_QuotaDetail value, $Res Function(_QuotaDetail) _then) = __$QuotaDetailCopyWithImpl;
@override @useResult
$Res call({
 String name, double? currentValue, double? total, double? percentage
});




}
/// @nodoc
class __$QuotaDetailCopyWithImpl<$Res>
    implements _$QuotaDetailCopyWith<$Res> {
  __$QuotaDetailCopyWithImpl(this._self, this._then);

  final _QuotaDetail _self;
  final $Res Function(_QuotaDetail) _then;

/// Create a copy of QuotaDetail
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? currentValue = freezed,Object? total = freezed,Object? percentage = freezed,}) {
  return _then(_QuotaDetail(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,currentValue: freezed == currentValue ? _self.currentValue : currentValue // ignore: cast_nullable_to_non_nullable
as double?,total: freezed == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as double?,percentage: freezed == percentage ? _self.percentage : percentage // ignore: cast_nullable_to_non_nullable
as double?,
  ));
}


}

// dart format on
