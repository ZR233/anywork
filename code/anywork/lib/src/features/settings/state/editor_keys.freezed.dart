// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'editor_keys.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountEditorKey {

 int get editorId; String? get accountId; String? get initialTemplateId;
/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountEditorKeyCopyWith<AccountEditorKey> get copyWith => _$AccountEditorKeyCopyWithImpl<AccountEditorKey>(this as AccountEditorKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountEditorKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountEditorKey&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.initialTemplateId, _this.initialTemplateId) || other.initialTemplateId == _this.initialTemplateId));
}


@override
int get hashCode {
  final _this = this as AccountEditorKey;
  return Object.hash(runtimeType,_this.editorId,_this.accountId,_this.initialTemplateId);
}

@override
String toString() {
  final _this = this as AccountEditorKey;
  return 'AccountEditorKey(editorId: ${_this.editorId}, accountId: ${_this.accountId}, initialTemplateId: ${_this.initialTemplateId})';
}


}

/// @nodoc
abstract mixin class $AccountEditorKeyCopyWith<$Res>  {
  factory $AccountEditorKeyCopyWith(AccountEditorKey value, $Res Function(AccountEditorKey) _then) = _$AccountEditorKeyCopyWithImpl;
@useResult
$Res call({
 int editorId, String? accountId, String? initialTemplateId
});




}
/// @nodoc
class _$AccountEditorKeyCopyWithImpl<$Res>
    implements $AccountEditorKeyCopyWith<$Res> {
  _$AccountEditorKeyCopyWithImpl(this._self, this._then);

  final AccountEditorKey _self;
  final $Res Function(AccountEditorKey) _then;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? accountId = freezed,Object? initialTemplateId = freezed,}) {
  return _then(AccountEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,initialTemplateId: freezed == initialTemplateId ? _self.initialTemplateId : initialTemplateId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountEditorKey].
extension AccountEditorKeyPatterns on AccountEditorKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountEditorKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountEditorKey value)  $default,){
final _that = this;
switch (_that) {
case _AccountEditorKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountEditorKey value)?  $default,){
final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int editorId,  String? accountId,  String? initialTemplateId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
return $default(_that.editorId,_that.accountId,_that.initialTemplateId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int editorId,  String? accountId,  String? initialTemplateId)  $default,) {final _that = this;
switch (_that) {
case _AccountEditorKey():
return $default(_that.editorId,_that.accountId,_that.initialTemplateId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int editorId,  String? accountId,  String? initialTemplateId)?  $default,) {final _that = this;
switch (_that) {
case _AccountEditorKey() when $default != null:
return $default(_that.editorId,_that.accountId,_that.initialTemplateId);case _:
  return null;

}
}

}

/// @nodoc


class _AccountEditorKey implements AccountEditorKey {
  const _AccountEditorKey({required this.editorId, this.accountId, this.initialTemplateId});


@override final  int editorId;
@override final  String? accountId;
@override final  String? initialTemplateId;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountEditorKeyCopyWith<_AccountEditorKey> get copyWith => __$AccountEditorKeyCopyWithImpl<_AccountEditorKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountEditorKey&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.initialTemplateId, initialTemplateId) || other.initialTemplateId == initialTemplateId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,accountId,initialTemplateId);
}

@override
String toString() {
    return 'AccountEditorKey(editorId: $editorId, accountId: $accountId, initialTemplateId: $initialTemplateId)';
}


}

/// @nodoc
abstract mixin class _$AccountEditorKeyCopyWith<$Res> implements $AccountEditorKeyCopyWith<$Res> {
  factory _$AccountEditorKeyCopyWith(_AccountEditorKey value, $Res Function(_AccountEditorKey) _then) = __$AccountEditorKeyCopyWithImpl;
@override @useResult
$Res call({
 int editorId, String? accountId, String? initialTemplateId
});




}
/// @nodoc
class __$AccountEditorKeyCopyWithImpl<$Res>
    implements _$AccountEditorKeyCopyWith<$Res> {
  __$AccountEditorKeyCopyWithImpl(this._self, this._then);

  final _AccountEditorKey _self;
  final $Res Function(_AccountEditorKey) _then;

/// Create a copy of AccountEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? accountId = freezed,Object? initialTemplateId = freezed,}) {
  return _then(_AccountEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,accountId: freezed == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String?,initialTemplateId: freezed == initialTemplateId ? _self.initialTemplateId : initialTemplateId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ProfileEditorKey {

 int get editorId; String? get profileId;
/// Create a copy of ProfileEditorKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProfileEditorKeyCopyWith<ProfileEditorKey> get copyWith => _$ProfileEditorKeyCopyWithImpl<ProfileEditorKey>(this as ProfileEditorKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProfileEditorKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProfileEditorKey&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.profileId, _this.profileId) || other.profileId == _this.profileId));
}


@override
int get hashCode {
  final _this = this as ProfileEditorKey;
  return Object.hash(runtimeType,_this.editorId,_this.profileId);
}

@override
String toString() {
  final _this = this as ProfileEditorKey;
  return 'ProfileEditorKey(editorId: ${_this.editorId}, profileId: ${_this.profileId})';
}


}

/// @nodoc
abstract mixin class $ProfileEditorKeyCopyWith<$Res>  {
  factory $ProfileEditorKeyCopyWith(ProfileEditorKey value, $Res Function(ProfileEditorKey) _then) = _$ProfileEditorKeyCopyWithImpl;
@useResult
$Res call({
 int editorId, String? profileId
});




}
/// @nodoc
class _$ProfileEditorKeyCopyWithImpl<$Res>
    implements $ProfileEditorKeyCopyWith<$Res> {
  _$ProfileEditorKeyCopyWithImpl(this._self, this._then);

  final ProfileEditorKey _self;
  final $Res Function(ProfileEditorKey) _then;

/// Create a copy of ProfileEditorKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? profileId = freezed,}) {
  return _then(ProfileEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,profileId: freezed == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ProfileEditorKey].
extension ProfileEditorKeyPatterns on ProfileEditorKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProfileEditorKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProfileEditorKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProfileEditorKey value)  $default,){
final _that = this;
switch (_that) {
case _ProfileEditorKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProfileEditorKey value)?  $default,){
final _that = this;
switch (_that) {
case _ProfileEditorKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int editorId,  String? profileId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProfileEditorKey() when $default != null:
return $default(_that.editorId,_that.profileId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int editorId,  String? profileId)  $default,) {final _that = this;
switch (_that) {
case _ProfileEditorKey():
return $default(_that.editorId,_that.profileId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int editorId,  String? profileId)?  $default,) {final _that = this;
switch (_that) {
case _ProfileEditorKey() when $default != null:
return $default(_that.editorId,_that.profileId);case _:
  return null;

}
}

}

/// @nodoc


class _ProfileEditorKey implements ProfileEditorKey {
  const _ProfileEditorKey({required this.editorId, this.profileId});


@override final  int editorId;
@override final  String? profileId;

/// Create a copy of ProfileEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProfileEditorKeyCopyWith<_ProfileEditorKey> get copyWith => __$ProfileEditorKeyCopyWithImpl<_ProfileEditorKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProfileEditorKey&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.profileId, profileId) || other.profileId == profileId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,profileId);
}

@override
String toString() {
    return 'ProfileEditorKey(editorId: $editorId, profileId: $profileId)';
}


}

/// @nodoc
abstract mixin class _$ProfileEditorKeyCopyWith<$Res> implements $ProfileEditorKeyCopyWith<$Res> {
  factory _$ProfileEditorKeyCopyWith(_ProfileEditorKey value, $Res Function(_ProfileEditorKey) _then) = __$ProfileEditorKeyCopyWithImpl;
@override @useResult
$Res call({
 int editorId, String? profileId
});




}
/// @nodoc
class __$ProfileEditorKeyCopyWithImpl<$Res>
    implements _$ProfileEditorKeyCopyWith<$Res> {
  __$ProfileEditorKeyCopyWithImpl(this._self, this._then);

  final _ProfileEditorKey _self;
  final $Res Function(_ProfileEditorKey) _then;

/// Create a copy of ProfileEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? profileId = freezed,}) {
  return _then(_ProfileEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,profileId: freezed == profileId ? _self.profileId : profileId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$SshEditorKey {

 int get editorId; String? get alias;
/// Create a copy of SshEditorKey
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SshEditorKeyCopyWith<SshEditorKey> get copyWith => _$SshEditorKeyCopyWithImpl<SshEditorKey>(this as SshEditorKey, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SshEditorKey;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SshEditorKey&&(identical(other.editorId, _this.editorId) || other.editorId == _this.editorId)&&(identical(other.alias, _this.alias) || other.alias == _this.alias));
}


@override
int get hashCode {
  final _this = this as SshEditorKey;
  return Object.hash(runtimeType,_this.editorId,_this.alias);
}

@override
String toString() {
  final _this = this as SshEditorKey;
  return 'SshEditorKey(editorId: ${_this.editorId}, alias: ${_this.alias})';
}


}

/// @nodoc
abstract mixin class $SshEditorKeyCopyWith<$Res>  {
  factory $SshEditorKeyCopyWith(SshEditorKey value, $Res Function(SshEditorKey) _then) = _$SshEditorKeyCopyWithImpl;
@useResult
$Res call({
 int editorId, String? alias
});




}
/// @nodoc
class _$SshEditorKeyCopyWithImpl<$Res>
    implements $SshEditorKeyCopyWith<$Res> {
  _$SshEditorKeyCopyWithImpl(this._self, this._then);

  final SshEditorKey _self;
  final $Res Function(SshEditorKey) _then;

/// Create a copy of SshEditorKey
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? editorId = null,Object? alias = freezed,}) {
  return _then(SshEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,alias: freezed == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [SshEditorKey].
extension SshEditorKeyPatterns on SshEditorKey {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SshEditorKey value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SshEditorKey() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SshEditorKey value)  $default,){
final _that = this;
switch (_that) {
case _SshEditorKey():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SshEditorKey value)?  $default,){
final _that = this;
switch (_that) {
case _SshEditorKey() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int editorId,  String? alias)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SshEditorKey() when $default != null:
return $default(_that.editorId,_that.alias);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int editorId,  String? alias)  $default,) {final _that = this;
switch (_that) {
case _SshEditorKey():
return $default(_that.editorId,_that.alias);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int editorId,  String? alias)?  $default,) {final _that = this;
switch (_that) {
case _SshEditorKey() when $default != null:
return $default(_that.editorId,_that.alias);case _:
  return null;

}
}

}

/// @nodoc


class _SshEditorKey implements SshEditorKey {
  const _SshEditorKey({required this.editorId, this.alias});


@override final  int editorId;
@override final  String? alias;

/// Create a copy of SshEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SshEditorKeyCopyWith<_SshEditorKey> get copyWith => __$SshEditorKeyCopyWithImpl<_SshEditorKey>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SshEditorKey&&(identical(other.editorId, editorId) || other.editorId == editorId)&&(identical(other.alias, alias) || other.alias == alias));
}


@override
int get hashCode {
    return Object.hash(runtimeType,editorId,alias);
}

@override
String toString() {
    return 'SshEditorKey(editorId: $editorId, alias: $alias)';
}


}

/// @nodoc
abstract mixin class _$SshEditorKeyCopyWith<$Res> implements $SshEditorKeyCopyWith<$Res> {
  factory _$SshEditorKeyCopyWith(_SshEditorKey value, $Res Function(_SshEditorKey) _then) = __$SshEditorKeyCopyWithImpl;
@override @useResult
$Res call({
 int editorId, String? alias
});




}
/// @nodoc
class __$SshEditorKeyCopyWithImpl<$Res>
    implements _$SshEditorKeyCopyWith<$Res> {
  __$SshEditorKeyCopyWithImpl(this._self, this._then);

  final _SshEditorKey _self;
  final $Res Function(_SshEditorKey) _then;

/// Create a copy of SshEditorKey
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? editorId = null,Object? alias = freezed,}) {
  return _then(_SshEditorKey(
editorId: null == editorId ? _self.editorId : editorId // ignore: cast_nullable_to_non_nullable
as int,alias: freezed == alias ? _self.alias : alias // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
