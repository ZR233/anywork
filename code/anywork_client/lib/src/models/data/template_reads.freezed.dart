// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'template_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountTemplatesReadHeader {

 int get schemaVersion; ReadText get revision; TypedListRef get templates; TypedListRef get modelCatalogs;
/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesReadHeaderCopyWith<AccountTemplatesReadHeader> get copyWith => _$AccountTemplatesReadHeaderCopyWithImpl<AccountTemplatesReadHeader>(this as AccountTemplatesReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesReadHeader&&(identical(other.schemaVersion, _this.schemaVersion) || other.schemaVersion == _this.schemaVersion)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.templates, _this.templates) || other.templates == _this.templates)&&(identical(other.modelCatalogs, _this.modelCatalogs) || other.modelCatalogs == _this.modelCatalogs));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesReadHeader;
  return Object.hash(runtimeType,_this.schemaVersion,_this.revision,_this.templates,_this.modelCatalogs);
}



}

/// @nodoc
abstract mixin class $AccountTemplatesReadHeaderCopyWith<$Res>  {
  factory $AccountTemplatesReadHeaderCopyWith(AccountTemplatesReadHeader value, $Res Function(AccountTemplatesReadHeader) _then) = _$AccountTemplatesReadHeaderCopyWithImpl;
@useResult
$Res call({
 int schemaVersion, ReadText revision, TypedListRef templates, TypedListRef modelCatalogs
});


$ReadTextCopyWith<$Res> get revision;$TypedListRefCopyWith<$Res> get templates;$TypedListRefCopyWith<$Res> get modelCatalogs;

}
/// @nodoc
class _$AccountTemplatesReadHeaderCopyWithImpl<$Res>
    implements $AccountTemplatesReadHeaderCopyWith<$Res> {
  _$AccountTemplatesReadHeaderCopyWithImpl(this._self, this._then);

  final AccountTemplatesReadHeader _self;
  final $Res Function(AccountTemplatesReadHeader) _then;

/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schemaVersion = null,Object? revision = null,Object? templates = null,Object? modelCatalogs = null,}) {
  return _then(AccountTemplatesReadHeader(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as ReadText,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelCatalogs: null == modelCatalogs ? _self.modelCatalogs : modelCatalogs // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get revision {

  return $ReadTextCopyWith<$Res>(_self.revision, (value) {
    return _then(_self.copyWith(revision: value));
  });
}/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get templates {

  return $TypedListRefCopyWith<$Res>(_self.templates, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelCatalogs {

  return $TypedListRefCopyWith<$Res>(_self.modelCatalogs, (value) {
    return _then(_self.copyWith(modelCatalogs: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplatesReadHeader].
extension AccountTemplatesReadHeaderPatterns on AccountTemplatesReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplatesReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplatesReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplatesReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int schemaVersion,  ReadText revision,  TypedListRef templates,  TypedListRef modelCatalogs)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader() when $default != null:
return $default(_that.schemaVersion,_that.revision,_that.templates,_that.modelCatalogs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int schemaVersion,  ReadText revision,  TypedListRef templates,  TypedListRef modelCatalogs)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader():
return $default(_that.schemaVersion,_that.revision,_that.templates,_that.modelCatalogs);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int schemaVersion,  ReadText revision,  TypedListRef templates,  TypedListRef modelCatalogs)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplatesReadHeader() when $default != null:
return $default(_that.schemaVersion,_that.revision,_that.templates,_that.modelCatalogs);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplatesReadHeader implements AccountTemplatesReadHeader {
  const _AccountTemplatesReadHeader({required this.schemaVersion, required this.revision, required this.templates, required this.modelCatalogs});


@override final  int schemaVersion;
@override final  ReadText revision;
@override final  TypedListRef templates;
@override final  TypedListRef modelCatalogs;

/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplatesReadHeaderCopyWith<_AccountTemplatesReadHeader> get copyWith => __$AccountTemplatesReadHeaderCopyWithImpl<_AccountTemplatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplatesReadHeader&&(identical(other.schemaVersion, schemaVersion) || other.schemaVersion == schemaVersion)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.templates, templates) || other.templates == templates)&&(identical(other.modelCatalogs, modelCatalogs) || other.modelCatalogs == modelCatalogs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,schemaVersion,revision,templates,modelCatalogs);
}



}

/// @nodoc
abstract mixin class _$AccountTemplatesReadHeaderCopyWith<$Res> implements $AccountTemplatesReadHeaderCopyWith<$Res> {
  factory _$AccountTemplatesReadHeaderCopyWith(_AccountTemplatesReadHeader value, $Res Function(_AccountTemplatesReadHeader) _then) = __$AccountTemplatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int schemaVersion, ReadText revision, TypedListRef templates, TypedListRef modelCatalogs
});


@override $ReadTextCopyWith<$Res> get revision;@override $TypedListRefCopyWith<$Res> get templates;@override $TypedListRefCopyWith<$Res> get modelCatalogs;

}
/// @nodoc
class __$AccountTemplatesReadHeaderCopyWithImpl<$Res>
    implements _$AccountTemplatesReadHeaderCopyWith<$Res> {
  __$AccountTemplatesReadHeaderCopyWithImpl(this._self, this._then);

  final _AccountTemplatesReadHeader _self;
  final $Res Function(_AccountTemplatesReadHeader) _then;

/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? schemaVersion = null,Object? revision = null,Object? templates = null,Object? modelCatalogs = null,}) {
  return _then(_AccountTemplatesReadHeader(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as ReadText,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as TypedListRef,modelCatalogs: null == modelCatalogs ? _self.modelCatalogs : modelCatalogs // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get revision {

  return $ReadTextCopyWith<$Res>(_self.revision, (value) {
    return _then(_self.copyWith(revision: value));
  });
}/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get templates {

  return $TypedListRefCopyWith<$Res>(_self.templates, (value) {
    return _then(_self.copyWith(templates: value));
  });
}/// Create a copy of AccountTemplatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get modelCatalogs {

  return $TypedListRefCopyWith<$Res>(_self.modelCatalogs, (value) {
    return _then(_self.copyWith(modelCatalogs: value));
  });
}
}

/// @nodoc
mixin _$AccountTemplateRead {

 ReadText get id; ReadText get displayName; ReadText? get description; ReadText get baseUrl; CredentialDescriptorRead get credential; ReadText get modelCatalogId; ReadText get protocol; ReadText get suggestedModelId; ReadText? get iconKey; AccountServiceCapabilitiesRead get serviceCapabilities;
/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplateReadCopyWith<AccountTemplateRead> get copyWith => _$AccountTemplateReadCopyWithImpl<AccountTemplateRead>(this as AccountTemplateRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplateRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplateRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.credential, _this.credential) || other.credential == _this.credential)&&(identical(other.modelCatalogId, _this.modelCatalogId) || other.modelCatalogId == _this.modelCatalogId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.suggestedModelId, _this.suggestedModelId) || other.suggestedModelId == _this.suggestedModelId)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.serviceCapabilities, _this.serviceCapabilities) || other.serviceCapabilities == _this.serviceCapabilities));
}


@override
int get hashCode {
  final _this = this as AccountTemplateRead;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.description,_this.baseUrl,_this.credential,_this.modelCatalogId,_this.protocol,_this.suggestedModelId,_this.iconKey,_this.serviceCapabilities);
}



}

/// @nodoc
abstract mixin class $AccountTemplateReadCopyWith<$Res>  {
  factory $AccountTemplateReadCopyWith(AccountTemplateRead value, $Res Function(AccountTemplateRead) _then) = _$AccountTemplateReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, ReadText displayName, ReadText? description, ReadText baseUrl, CredentialDescriptorRead credential, ReadText modelCatalogId, ReadText protocol, ReadText suggestedModelId, ReadText? iconKey, AccountServiceCapabilitiesRead serviceCapabilities
});


$ReadTextCopyWith<$Res> get id;$ReadTextCopyWith<$Res> get displayName;$ReadTextCopyWith<$Res>? get description;$ReadTextCopyWith<$Res> get baseUrl;$CredentialDescriptorReadCopyWith<$Res> get credential;$ReadTextCopyWith<$Res> get modelCatalogId;$ReadTextCopyWith<$Res> get protocol;$ReadTextCopyWith<$Res> get suggestedModelId;$ReadTextCopyWith<$Res>? get iconKey;$AccountServiceCapabilitiesReadCopyWith<$Res> get serviceCapabilities;

}
/// @nodoc
class _$AccountTemplateReadCopyWithImpl<$Res>
    implements $AccountTemplateReadCopyWith<$Res> {
  _$AccountTemplateReadCopyWithImpl(this._self, this._then);

  final AccountTemplateRead _self;
  final $Res Function(AccountTemplateRead) _then;

/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? description = freezed,Object? baseUrl = null,Object? credential = null,Object? modelCatalogId = null,Object? protocol = null,Object? suggestedModelId = null,Object? iconKey = freezed,Object? serviceCapabilities = null,}) {
  return _then(AccountTemplateRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText?,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as ReadText,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as CredentialDescriptorRead,modelCatalogId: null == modelCatalogId ? _self.modelCatalogId : modelCatalogId // ignore: cast_nullable_to_non_nullable
as ReadText,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,suggestedModelId: null == suggestedModelId ? _self.suggestedModelId : suggestedModelId // ignore: cast_nullable_to_non_nullable
as ReadText,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as ReadText?,serviceCapabilities: null == serviceCapabilities ? _self.serviceCapabilities : serviceCapabilities // ignore: cast_nullable_to_non_nullable
as AccountServiceCapabilitiesRead,
  ));
}
/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get description {
    if (_self.description == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.description!, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseUrl {

  return $ReadTextCopyWith<$Res>(_self.baseUrl, (value) {
    return _then(_self.copyWith(baseUrl: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CredentialDescriptorReadCopyWith<$Res> get credential {

  return $CredentialDescriptorReadCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelCatalogId {

  return $ReadTextCopyWith<$Res>(_self.modelCatalogId, (value) {
    return _then(_self.copyWith(modelCatalogId: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get suggestedModelId {

  return $ReadTextCopyWith<$Res>(_self.suggestedModelId, (value) {
    return _then(_self.copyWith(suggestedModelId: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get iconKey {
    if (_self.iconKey == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.iconKey!, (value) {
    return _then(_self.copyWith(iconKey: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesReadCopyWith<$Res> get serviceCapabilities {

  return $AccountServiceCapabilitiesReadCopyWith<$Res>(_self.serviceCapabilities, (value) {
    return _then(_self.copyWith(serviceCapabilities: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplateRead].
extension AccountTemplateReadPatterns on AccountTemplateRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplateRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplateRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplateRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplateRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplateRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplateRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName,  ReadText? description,  ReadText baseUrl,  CredentialDescriptorRead credential,  ReadText modelCatalogId,  ReadText protocol,  ReadText suggestedModelId,  ReadText? iconKey,  AccountServiceCapabilitiesRead serviceCapabilities)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplateRead() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.baseUrl,_that.credential,_that.modelCatalogId,_that.protocol,_that.suggestedModelId,_that.iconKey,_that.serviceCapabilities);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  ReadText displayName,  ReadText? description,  ReadText baseUrl,  CredentialDescriptorRead credential,  ReadText modelCatalogId,  ReadText protocol,  ReadText suggestedModelId,  ReadText? iconKey,  AccountServiceCapabilitiesRead serviceCapabilities)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplateRead():
return $default(_that.id,_that.displayName,_that.description,_that.baseUrl,_that.credential,_that.modelCatalogId,_that.protocol,_that.suggestedModelId,_that.iconKey,_that.serviceCapabilities);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  ReadText displayName,  ReadText? description,  ReadText baseUrl,  CredentialDescriptorRead credential,  ReadText modelCatalogId,  ReadText protocol,  ReadText suggestedModelId,  ReadText? iconKey,  AccountServiceCapabilitiesRead serviceCapabilities)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplateRead() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.baseUrl,_that.credential,_that.modelCatalogId,_that.protocol,_that.suggestedModelId,_that.iconKey,_that.serviceCapabilities);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplateRead implements AccountTemplateRead {
  const _AccountTemplateRead({required this.id, required this.displayName, required this.description, required this.baseUrl, required this.credential, required this.modelCatalogId, required this.protocol, required this.suggestedModelId, required this.iconKey, required this.serviceCapabilities});


@override final  ReadText id;
@override final  ReadText displayName;
@override final  ReadText? description;
@override final  ReadText baseUrl;
@override final  CredentialDescriptorRead credential;
@override final  ReadText modelCatalogId;
@override final  ReadText protocol;
@override final  ReadText suggestedModelId;
@override final  ReadText? iconKey;
@override final  AccountServiceCapabilitiesRead serviceCapabilities;

/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplateReadCopyWith<_AccountTemplateRead> get copyWith => __$AccountTemplateReadCopyWithImpl<_AccountTemplateRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplateRead&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.credential, credential) || other.credential == credential)&&(identical(other.modelCatalogId, modelCatalogId) || other.modelCatalogId == modelCatalogId)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.suggestedModelId, suggestedModelId) || other.suggestedModelId == suggestedModelId)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.serviceCapabilities, serviceCapabilities) || other.serviceCapabilities == serviceCapabilities));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,description,baseUrl,credential,modelCatalogId,protocol,suggestedModelId,iconKey,serviceCapabilities);
}



}

/// @nodoc
abstract mixin class _$AccountTemplateReadCopyWith<$Res> implements $AccountTemplateReadCopyWith<$Res> {
  factory _$AccountTemplateReadCopyWith(_AccountTemplateRead value, $Res Function(_AccountTemplateRead) _then) = __$AccountTemplateReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, ReadText displayName, ReadText? description, ReadText baseUrl, CredentialDescriptorRead credential, ReadText modelCatalogId, ReadText protocol, ReadText suggestedModelId, ReadText? iconKey, AccountServiceCapabilitiesRead serviceCapabilities
});


@override $ReadTextCopyWith<$Res> get id;@override $ReadTextCopyWith<$Res> get displayName;@override $ReadTextCopyWith<$Res>? get description;@override $ReadTextCopyWith<$Res> get baseUrl;@override $CredentialDescriptorReadCopyWith<$Res> get credential;@override $ReadTextCopyWith<$Res> get modelCatalogId;@override $ReadTextCopyWith<$Res> get protocol;@override $ReadTextCopyWith<$Res> get suggestedModelId;@override $ReadTextCopyWith<$Res>? get iconKey;@override $AccountServiceCapabilitiesReadCopyWith<$Res> get serviceCapabilities;

}
/// @nodoc
class __$AccountTemplateReadCopyWithImpl<$Res>
    implements _$AccountTemplateReadCopyWith<$Res> {
  __$AccountTemplateReadCopyWithImpl(this._self, this._then);

  final _AccountTemplateRead _self;
  final $Res Function(_AccountTemplateRead) _then;

/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? description = freezed,Object? baseUrl = null,Object? credential = null,Object? modelCatalogId = null,Object? protocol = null,Object? suggestedModelId = null,Object? iconKey = freezed,Object? serviceCapabilities = null,}) {
  return _then(_AccountTemplateRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as ReadText,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText?,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as ReadText,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as CredentialDescriptorRead,modelCatalogId: null == modelCatalogId ? _self.modelCatalogId : modelCatalogId // ignore: cast_nullable_to_non_nullable
as ReadText,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as ReadText,suggestedModelId: null == suggestedModelId ? _self.suggestedModelId : suggestedModelId // ignore: cast_nullable_to_non_nullable
as ReadText,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as ReadText?,serviceCapabilities: null == serviceCapabilities ? _self.serviceCapabilities : serviceCapabilities // ignore: cast_nullable_to_non_nullable
as AccountServiceCapabilitiesRead,
  ));
}

/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get displayName {

  return $ReadTextCopyWith<$Res>(_self.displayName, (value) {
    return _then(_self.copyWith(displayName: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get description {
    if (_self.description == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.description!, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get baseUrl {

  return $ReadTextCopyWith<$Res>(_self.baseUrl, (value) {
    return _then(_self.copyWith(baseUrl: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CredentialDescriptorReadCopyWith<$Res> get credential {

  return $CredentialDescriptorReadCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get modelCatalogId {

  return $ReadTextCopyWith<$Res>(_self.modelCatalogId, (value) {
    return _then(_self.copyWith(modelCatalogId: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get protocol {

  return $ReadTextCopyWith<$Res>(_self.protocol, (value) {
    return _then(_self.copyWith(protocol: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get suggestedModelId {

  return $ReadTextCopyWith<$Res>(_self.suggestedModelId, (value) {
    return _then(_self.copyWith(suggestedModelId: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get iconKey {
    if (_self.iconKey == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.iconKey!, (value) {
    return _then(_self.copyWith(iconKey: value));
  });
}/// Create a copy of AccountTemplateRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesReadCopyWith<$Res> get serviceCapabilities {

  return $AccountServiceCapabilitiesReadCopyWith<$Res>(_self.serviceCapabilities, (value) {
    return _then(_self.copyWith(serviceCapabilities: value));
  });
}
}

/// @nodoc
mixin _$CredentialDescriptorRead {

 ReadText get label; ReadText? get envVar;
/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CredentialDescriptorReadCopyWith<CredentialDescriptorRead> get copyWith => _$CredentialDescriptorReadCopyWithImpl<CredentialDescriptorRead>(this as CredentialDescriptorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CredentialDescriptorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CredentialDescriptorRead&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.envVar, _this.envVar) || other.envVar == _this.envVar));
}


@override
int get hashCode {
  final _this = this as CredentialDescriptorRead;
  return Object.hash(runtimeType,_this.label,_this.envVar);
}



}

/// @nodoc
abstract mixin class $CredentialDescriptorReadCopyWith<$Res>  {
  factory $CredentialDescriptorReadCopyWith(CredentialDescriptorRead value, $Res Function(CredentialDescriptorRead) _then) = _$CredentialDescriptorReadCopyWithImpl;
@useResult
$Res call({
 ReadText label, ReadText? envVar
});


$ReadTextCopyWith<$Res> get label;$ReadTextCopyWith<$Res>? get envVar;

}
/// @nodoc
class _$CredentialDescriptorReadCopyWithImpl<$Res>
    implements $CredentialDescriptorReadCopyWith<$Res> {
  _$CredentialDescriptorReadCopyWithImpl(this._self, this._then);

  final CredentialDescriptorRead _self;
  final $Res Function(CredentialDescriptorRead) _then;

/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? envVar = freezed,}) {
  return _then(CredentialDescriptorRead(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,envVar: freezed == envVar ? _self.envVar : envVar // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get envVar {
    if (_self.envVar == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.envVar!, (value) {
    return _then(_self.copyWith(envVar: value));
  });
}
}


/// Adds pattern-matching-related methods to [CredentialDescriptorRead].
extension CredentialDescriptorReadPatterns on CredentialDescriptorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CredentialDescriptorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CredentialDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CredentialDescriptorRead value)  $default,){
final _that = this;
switch (_that) {
case _CredentialDescriptorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CredentialDescriptorRead value)?  $default,){
final _that = this;
switch (_that) {
case _CredentialDescriptorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText label,  ReadText? envVar)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CredentialDescriptorRead() when $default != null:
return $default(_that.label,_that.envVar);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText label,  ReadText? envVar)  $default,) {final _that = this;
switch (_that) {
case _CredentialDescriptorRead():
return $default(_that.label,_that.envVar);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText label,  ReadText? envVar)?  $default,) {final _that = this;
switch (_that) {
case _CredentialDescriptorRead() when $default != null:
return $default(_that.label,_that.envVar);case _:
  return null;

}
}

}

/// @nodoc


class _CredentialDescriptorRead implements CredentialDescriptorRead {
  const _CredentialDescriptorRead({required this.label, required this.envVar});


@override final  ReadText label;
@override final  ReadText? envVar;

/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CredentialDescriptorReadCopyWith<_CredentialDescriptorRead> get copyWith => __$CredentialDescriptorReadCopyWithImpl<_CredentialDescriptorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CredentialDescriptorRead&&(identical(other.label, label) || other.label == label)&&(identical(other.envVar, envVar) || other.envVar == envVar));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,envVar);
}



}

/// @nodoc
abstract mixin class _$CredentialDescriptorReadCopyWith<$Res> implements $CredentialDescriptorReadCopyWith<$Res> {
  factory _$CredentialDescriptorReadCopyWith(_CredentialDescriptorRead value, $Res Function(_CredentialDescriptorRead) _then) = __$CredentialDescriptorReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText label, ReadText? envVar
});


@override $ReadTextCopyWith<$Res> get label;@override $ReadTextCopyWith<$Res>? get envVar;

}
/// @nodoc
class __$CredentialDescriptorReadCopyWithImpl<$Res>
    implements _$CredentialDescriptorReadCopyWith<$Res> {
  __$CredentialDescriptorReadCopyWithImpl(this._self, this._then);

  final _CredentialDescriptorRead _self;
  final $Res Function(_CredentialDescriptorRead) _then;

/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? envVar = freezed,}) {
  return _then(_CredentialDescriptorRead(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as ReadText,envVar: freezed == envVar ? _self.envVar : envVar // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get label {

  return $ReadTextCopyWith<$Res>(_self.label, (value) {
    return _then(_self.copyWith(label: value));
  });
}/// Create a copy of CredentialDescriptorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get envVar {
    if (_self.envVar == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.envVar!, (value) {
    return _then(_self.copyWith(envVar: value));
  });
}
}

/// @nodoc
mixin _$AccountServiceCapabilitiesRead {

 WebSearchServiceCapabilitiesRead get webSearch; ReadText get promptCacheDialect; bool get responsesProgrammaticToolCalling;
/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesReadCopyWith<AccountServiceCapabilitiesRead> get copyWith => _$AccountServiceCapabilitiesReadCopyWithImpl<AccountServiceCapabilitiesRead>(this as AccountServiceCapabilitiesRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountServiceCapabilitiesRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountServiceCapabilitiesRead&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.promptCacheDialect, _this.promptCacheDialect) || other.promptCacheDialect == _this.promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, _this.responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == _this.responsesProgrammaticToolCalling));
}


@override
int get hashCode {
  final _this = this as AccountServiceCapabilitiesRead;
  return Object.hash(runtimeType,_this.webSearch,_this.promptCacheDialect,_this.responsesProgrammaticToolCalling);
}



}

/// @nodoc
abstract mixin class $AccountServiceCapabilitiesReadCopyWith<$Res>  {
  factory $AccountServiceCapabilitiesReadCopyWith(AccountServiceCapabilitiesRead value, $Res Function(AccountServiceCapabilitiesRead) _then) = _$AccountServiceCapabilitiesReadCopyWithImpl;
@useResult
$Res call({
 WebSearchServiceCapabilitiesRead webSearch, ReadText promptCacheDialect, bool responsesProgrammaticToolCalling
});


$WebSearchServiceCapabilitiesReadCopyWith<$Res> get webSearch;$ReadTextCopyWith<$Res> get promptCacheDialect;

}
/// @nodoc
class _$AccountServiceCapabilitiesReadCopyWithImpl<$Res>
    implements $AccountServiceCapabilitiesReadCopyWith<$Res> {
  _$AccountServiceCapabilitiesReadCopyWithImpl(this._self, this._then);

  final AccountServiceCapabilitiesRead _self;
  final $Res Function(AccountServiceCapabilitiesRead) _then;

/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? webSearch = null,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,}) {
  return _then(AccountServiceCapabilitiesRead(
webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchServiceCapabilitiesRead,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as ReadText,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesReadCopyWith<$Res> get webSearch {

  return $WebSearchServiceCapabilitiesReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get promptCacheDialect {

  return $ReadTextCopyWith<$Res>(_self.promptCacheDialect, (value) {
    return _then(_self.copyWith(promptCacheDialect: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountServiceCapabilitiesRead].
extension AccountServiceCapabilitiesReadPatterns on AccountServiceCapabilitiesRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountServiceCapabilitiesRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountServiceCapabilitiesRead value)  $default,){
final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountServiceCapabilitiesRead value)?  $default,){
final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WebSearchServiceCapabilitiesRead webSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead() when $default != null:
return $default(_that.webSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WebSearchServiceCapabilitiesRead webSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling)  $default,) {final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead():
return $default(_that.webSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WebSearchServiceCapabilitiesRead webSearch,  ReadText promptCacheDialect,  bool responsesProgrammaticToolCalling)?  $default,) {final _that = this;
switch (_that) {
case _AccountServiceCapabilitiesRead() when $default != null:
return $default(_that.webSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling);case _:
  return null;

}
}

}

/// @nodoc


class _AccountServiceCapabilitiesRead implements AccountServiceCapabilitiesRead {
  const _AccountServiceCapabilitiesRead({required this.webSearch, required this.promptCacheDialect, required this.responsesProgrammaticToolCalling});


@override final  WebSearchServiceCapabilitiesRead webSearch;
@override final  ReadText promptCacheDialect;
@override final  bool responsesProgrammaticToolCalling;

/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountServiceCapabilitiesReadCopyWith<_AccountServiceCapabilitiesRead> get copyWith => __$AccountServiceCapabilitiesReadCopyWithImpl<_AccountServiceCapabilitiesRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountServiceCapabilitiesRead&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.promptCacheDialect, promptCacheDialect) || other.promptCacheDialect == promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == responsesProgrammaticToolCalling));
}


@override
int get hashCode {
    return Object.hash(runtimeType,webSearch,promptCacheDialect,responsesProgrammaticToolCalling);
}



}

/// @nodoc
abstract mixin class _$AccountServiceCapabilitiesReadCopyWith<$Res> implements $AccountServiceCapabilitiesReadCopyWith<$Res> {
  factory _$AccountServiceCapabilitiesReadCopyWith(_AccountServiceCapabilitiesRead value, $Res Function(_AccountServiceCapabilitiesRead) _then) = __$AccountServiceCapabilitiesReadCopyWithImpl;
@override @useResult
$Res call({
 WebSearchServiceCapabilitiesRead webSearch, ReadText promptCacheDialect, bool responsesProgrammaticToolCalling
});


@override $WebSearchServiceCapabilitiesReadCopyWith<$Res> get webSearch;@override $ReadTextCopyWith<$Res> get promptCacheDialect;

}
/// @nodoc
class __$AccountServiceCapabilitiesReadCopyWithImpl<$Res>
    implements _$AccountServiceCapabilitiesReadCopyWith<$Res> {
  __$AccountServiceCapabilitiesReadCopyWithImpl(this._self, this._then);

  final _AccountServiceCapabilitiesRead _self;
  final $Res Function(_AccountServiceCapabilitiesRead) _then;

/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? webSearch = null,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,}) {
  return _then(_AccountServiceCapabilitiesRead(
webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchServiceCapabilitiesRead,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as ReadText,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesReadCopyWith<$Res> get webSearch {

  return $WebSearchServiceCapabilitiesReadCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}/// Create a copy of AccountServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get promptCacheDialect {

  return $ReadTextCopyWith<$Res>(_self.promptCacheDialect, (value) {
    return _then(_self.copyWith(promptCacheDialect: value));
  });
}
}

/// @nodoc
mixin _$WebSearchServiceCapabilitiesRead {

 bool get hostedResponses; ReadText get hostedDialect; ReadText? get standalone;
/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesReadCopyWith<WebSearchServiceCapabilitiesRead> get copyWith => _$WebSearchServiceCapabilitiesReadCopyWithImpl<WebSearchServiceCapabilitiesRead>(this as WebSearchServiceCapabilitiesRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WebSearchServiceCapabilitiesRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSearchServiceCapabilitiesRead&&(identical(other.hostedResponses, _this.hostedResponses) || other.hostedResponses == _this.hostedResponses)&&(identical(other.hostedDialect, _this.hostedDialect) || other.hostedDialect == _this.hostedDialect)&&(identical(other.standalone, _this.standalone) || other.standalone == _this.standalone));
}


@override
int get hashCode {
  final _this = this as WebSearchServiceCapabilitiesRead;
  return Object.hash(runtimeType,_this.hostedResponses,_this.hostedDialect,_this.standalone);
}



}

/// @nodoc
abstract mixin class $WebSearchServiceCapabilitiesReadCopyWith<$Res>  {
  factory $WebSearchServiceCapabilitiesReadCopyWith(WebSearchServiceCapabilitiesRead value, $Res Function(WebSearchServiceCapabilitiesRead) _then) = _$WebSearchServiceCapabilitiesReadCopyWithImpl;
@useResult
$Res call({
 bool hostedResponses, ReadText hostedDialect, ReadText? standalone
});


$ReadTextCopyWith<$Res> get hostedDialect;$ReadTextCopyWith<$Res>? get standalone;

}
/// @nodoc
class _$WebSearchServiceCapabilitiesReadCopyWithImpl<$Res>
    implements $WebSearchServiceCapabilitiesReadCopyWith<$Res> {
  _$WebSearchServiceCapabilitiesReadCopyWithImpl(this._self, this._then);

  final WebSearchServiceCapabilitiesRead _self;
  final $Res Function(WebSearchServiceCapabilitiesRead) _then;

/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hostedResponses = null,Object? hostedDialect = null,Object? standalone = freezed,}) {
  return _then(WebSearchServiceCapabilitiesRead(
hostedResponses: null == hostedResponses ? _self.hostedResponses : hostedResponses // ignore: cast_nullable_to_non_nullable
as bool,hostedDialect: null == hostedDialect ? _self.hostedDialect : hostedDialect // ignore: cast_nullable_to_non_nullable
as ReadText,standalone: freezed == standalone ? _self.standalone : standalone // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}
/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get hostedDialect {

  return $ReadTextCopyWith<$Res>(_self.hostedDialect, (value) {
    return _then(_self.copyWith(hostedDialect: value));
  });
}/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get standalone {
    if (_self.standalone == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.standalone!, (value) {
    return _then(_self.copyWith(standalone: value));
  });
}
}


/// Adds pattern-matching-related methods to [WebSearchServiceCapabilitiesRead].
extension WebSearchServiceCapabilitiesReadPatterns on WebSearchServiceCapabilitiesRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSearchServiceCapabilitiesRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSearchServiceCapabilitiesRead value)  $default,){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSearchServiceCapabilitiesRead value)?  $default,){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool hostedResponses,  ReadText hostedDialect,  ReadText? standalone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead() when $default != null:
return $default(_that.hostedResponses,_that.hostedDialect,_that.standalone);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool hostedResponses,  ReadText hostedDialect,  ReadText? standalone)  $default,) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead():
return $default(_that.hostedResponses,_that.hostedDialect,_that.standalone);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool hostedResponses,  ReadText hostedDialect,  ReadText? standalone)?  $default,) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilitiesRead() when $default != null:
return $default(_that.hostedResponses,_that.hostedDialect,_that.standalone);case _:
  return null;

}
}

}

/// @nodoc


class _WebSearchServiceCapabilitiesRead implements WebSearchServiceCapabilitiesRead {
  const _WebSearchServiceCapabilitiesRead({required this.hostedResponses, required this.hostedDialect, required this.standalone});


@override final  bool hostedResponses;
@override final  ReadText hostedDialect;
@override final  ReadText? standalone;

/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSearchServiceCapabilitiesReadCopyWith<_WebSearchServiceCapabilitiesRead> get copyWith => __$WebSearchServiceCapabilitiesReadCopyWithImpl<_WebSearchServiceCapabilitiesRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSearchServiceCapabilitiesRead&&(identical(other.hostedResponses, hostedResponses) || other.hostedResponses == hostedResponses)&&(identical(other.hostedDialect, hostedDialect) || other.hostedDialect == hostedDialect)&&(identical(other.standalone, standalone) || other.standalone == standalone));
}


@override
int get hashCode {
    return Object.hash(runtimeType,hostedResponses,hostedDialect,standalone);
}



}

/// @nodoc
abstract mixin class _$WebSearchServiceCapabilitiesReadCopyWith<$Res> implements $WebSearchServiceCapabilitiesReadCopyWith<$Res> {
  factory _$WebSearchServiceCapabilitiesReadCopyWith(_WebSearchServiceCapabilitiesRead value, $Res Function(_WebSearchServiceCapabilitiesRead) _then) = __$WebSearchServiceCapabilitiesReadCopyWithImpl;
@override @useResult
$Res call({
 bool hostedResponses, ReadText hostedDialect, ReadText? standalone
});


@override $ReadTextCopyWith<$Res> get hostedDialect;@override $ReadTextCopyWith<$Res>? get standalone;

}
/// @nodoc
class __$WebSearchServiceCapabilitiesReadCopyWithImpl<$Res>
    implements _$WebSearchServiceCapabilitiesReadCopyWith<$Res> {
  __$WebSearchServiceCapabilitiesReadCopyWithImpl(this._self, this._then);

  final _WebSearchServiceCapabilitiesRead _self;
  final $Res Function(_WebSearchServiceCapabilitiesRead) _then;

/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostedResponses = null,Object? hostedDialect = null,Object? standalone = freezed,}) {
  return _then(_WebSearchServiceCapabilitiesRead(
hostedResponses: null == hostedResponses ? _self.hostedResponses : hostedResponses // ignore: cast_nullable_to_non_nullable
as bool,hostedDialect: null == hostedDialect ? _self.hostedDialect : hostedDialect // ignore: cast_nullable_to_non_nullable
as ReadText,standalone: freezed == standalone ? _self.standalone : standalone // ignore: cast_nullable_to_non_nullable
as ReadText?,
  ));
}

/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get hostedDialect {

  return $ReadTextCopyWith<$Res>(_self.hostedDialect, (value) {
    return _then(_self.copyWith(hostedDialect: value));
  });
}/// Create a copy of WebSearchServiceCapabilitiesRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get standalone {
    if (_self.standalone == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.standalone!, (value) {
    return _then(_self.copyWith(standalone: value));
  });
}
}

/// @nodoc
mixin _$NamedModelCatalogRead {

 ReadText get id; TypedListRef get models;
/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NamedModelCatalogReadCopyWith<NamedModelCatalogRead> get copyWith => _$NamedModelCatalogReadCopyWithImpl<NamedModelCatalogRead>(this as NamedModelCatalogRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NamedModelCatalogRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NamedModelCatalogRead&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.models, _this.models) || other.models == _this.models));
}


@override
int get hashCode {
  final _this = this as NamedModelCatalogRead;
  return Object.hash(runtimeType,_this.id,_this.models);
}



}

/// @nodoc
abstract mixin class $NamedModelCatalogReadCopyWith<$Res>  {
  factory $NamedModelCatalogReadCopyWith(NamedModelCatalogRead value, $Res Function(NamedModelCatalogRead) _then) = _$NamedModelCatalogReadCopyWithImpl;
@useResult
$Res call({
 ReadText id, TypedListRef models
});


$ReadTextCopyWith<$Res> get id;$TypedListRefCopyWith<$Res> get models;

}
/// @nodoc
class _$NamedModelCatalogReadCopyWithImpl<$Res>
    implements $NamedModelCatalogReadCopyWith<$Res> {
  _$NamedModelCatalogReadCopyWithImpl(this._self, this._then);

  final NamedModelCatalogRead _self;
  final $Res Function(NamedModelCatalogRead) _then;

/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? models = null,}) {
  return _then(NamedModelCatalogRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}
/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get models {

  return $TypedListRefCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}
}


/// Adds pattern-matching-related methods to [NamedModelCatalogRead].
extension NamedModelCatalogReadPatterns on NamedModelCatalogRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NamedModelCatalogRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NamedModelCatalogRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NamedModelCatalogRead value)  $default,){
final _that = this;
switch (_that) {
case _NamedModelCatalogRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NamedModelCatalogRead value)?  $default,){
final _that = this;
switch (_that) {
case _NamedModelCatalogRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText id,  TypedListRef models)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NamedModelCatalogRead() when $default != null:
return $default(_that.id,_that.models);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText id,  TypedListRef models)  $default,) {final _that = this;
switch (_that) {
case _NamedModelCatalogRead():
return $default(_that.id,_that.models);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText id,  TypedListRef models)?  $default,) {final _that = this;
switch (_that) {
case _NamedModelCatalogRead() when $default != null:
return $default(_that.id,_that.models);case _:
  return null;

}
}

}

/// @nodoc


class _NamedModelCatalogRead implements NamedModelCatalogRead {
  const _NamedModelCatalogRead({required this.id, required this.models});


@override final  ReadText id;
@override final  TypedListRef models;

/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NamedModelCatalogReadCopyWith<_NamedModelCatalogRead> get copyWith => __$NamedModelCatalogReadCopyWithImpl<_NamedModelCatalogRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NamedModelCatalogRead&&(identical(other.id, id) || other.id == id)&&(identical(other.models, models) || other.models == models));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,models);
}



}

/// @nodoc
abstract mixin class _$NamedModelCatalogReadCopyWith<$Res> implements $NamedModelCatalogReadCopyWith<$Res> {
  factory _$NamedModelCatalogReadCopyWith(_NamedModelCatalogRead value, $Res Function(_NamedModelCatalogRead) _then) = __$NamedModelCatalogReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText id, TypedListRef models
});


@override $ReadTextCopyWith<$Res> get id;@override $TypedListRefCopyWith<$Res> get models;

}
/// @nodoc
class __$NamedModelCatalogReadCopyWithImpl<$Res>
    implements _$NamedModelCatalogReadCopyWith<$Res> {
  __$NamedModelCatalogReadCopyWithImpl(this._self, this._then);

  final _NamedModelCatalogRead _self;
  final $Res Function(_NamedModelCatalogRead) _then;

/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? models = null,}) {
  return _then(_NamedModelCatalogRead(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as ReadText,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as TypedListRef,
  ));
}

/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get id {

  return $ReadTextCopyWith<$Res>(_self.id, (value) {
    return _then(_self.copyWith(id: value));
  });
}/// Create a copy of NamedModelCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get models {

  return $TypedListRefCopyWith<$Res>(_self.models, (value) {
    return _then(_self.copyWith(models: value));
  });
}
}

/// @nodoc
mixin _$NamedModelCatalogReadItem {

 ReadText get key; NamedModelCatalogRead get value;
/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NamedModelCatalogReadItemCopyWith<NamedModelCatalogReadItem> get copyWith => _$NamedModelCatalogReadItemCopyWithImpl<NamedModelCatalogReadItem>(this as NamedModelCatalogReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NamedModelCatalogReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NamedModelCatalogReadItem&&(identical(other.key, _this.key) || other.key == _this.key)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as NamedModelCatalogReadItem;
  return Object.hash(runtimeType,_this.key,_this.value);
}



}

/// @nodoc
abstract mixin class $NamedModelCatalogReadItemCopyWith<$Res>  {
  factory $NamedModelCatalogReadItemCopyWith(NamedModelCatalogReadItem value, $Res Function(NamedModelCatalogReadItem) _then) = _$NamedModelCatalogReadItemCopyWithImpl;
@useResult
$Res call({
 ReadText key, NamedModelCatalogRead value
});


$ReadTextCopyWith<$Res> get key;$NamedModelCatalogReadCopyWith<$Res> get value;

}
/// @nodoc
class _$NamedModelCatalogReadItemCopyWithImpl<$Res>
    implements $NamedModelCatalogReadItemCopyWith<$Res> {
  _$NamedModelCatalogReadItemCopyWithImpl(this._self, this._then);

  final NamedModelCatalogReadItem _self;
  final $Res Function(NamedModelCatalogReadItem) _then;

/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? key = null,Object? value = null,}) {
  return _then(NamedModelCatalogReadItem(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ReadText,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as NamedModelCatalogRead,
  ));
}
/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get key {

  return $ReadTextCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NamedModelCatalogReadCopyWith<$Res> get value {

  return $NamedModelCatalogReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [NamedModelCatalogReadItem].
extension NamedModelCatalogReadItemPatterns on NamedModelCatalogReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NamedModelCatalogReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NamedModelCatalogReadItem value)  $default,){
final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NamedModelCatalogReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText key,  NamedModelCatalogRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem() when $default != null:
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText key,  NamedModelCatalogRead value)  $default,) {final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem():
return $default(_that.key,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText key,  NamedModelCatalogRead value)?  $default,) {final _that = this;
switch (_that) {
case _NamedModelCatalogReadItem() when $default != null:
return $default(_that.key,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _NamedModelCatalogReadItem implements NamedModelCatalogReadItem {
  const _NamedModelCatalogReadItem({required this.key, required this.value});


@override final  ReadText key;
@override final  NamedModelCatalogRead value;

/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NamedModelCatalogReadItemCopyWith<_NamedModelCatalogReadItem> get copyWith => __$NamedModelCatalogReadItemCopyWithImpl<_NamedModelCatalogReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NamedModelCatalogReadItem&&(identical(other.key, key) || other.key == key)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,key,value);
}



}

/// @nodoc
abstract mixin class _$NamedModelCatalogReadItemCopyWith<$Res> implements $NamedModelCatalogReadItemCopyWith<$Res> {
  factory _$NamedModelCatalogReadItemCopyWith(_NamedModelCatalogReadItem value, $Res Function(_NamedModelCatalogReadItem) _then) = __$NamedModelCatalogReadItemCopyWithImpl;
@override @useResult
$Res call({
 ReadText key, NamedModelCatalogRead value
});


@override $ReadTextCopyWith<$Res> get key;@override $NamedModelCatalogReadCopyWith<$Res> get value;

}
/// @nodoc
class __$NamedModelCatalogReadItemCopyWithImpl<$Res>
    implements _$NamedModelCatalogReadItemCopyWith<$Res> {
  __$NamedModelCatalogReadItemCopyWithImpl(this._self, this._then);

  final _NamedModelCatalogReadItem _self;
  final $Res Function(_NamedModelCatalogReadItem) _then;

/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? key = null,Object? value = null,}) {
  return _then(_NamedModelCatalogReadItem(
key: null == key ? _self.key : key // ignore: cast_nullable_to_non_nullable
as ReadText,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as NamedModelCatalogRead,
  ));
}

/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get key {

  return $ReadTextCopyWith<$Res>(_self.key, (value) {
    return _then(_self.copyWith(key: value));
  });
}/// Create a copy of NamedModelCatalogReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NamedModelCatalogReadCopyWith<$Res> get value {

  return $NamedModelCatalogReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
