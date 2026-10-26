// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'template_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AccountTemplatesValue {


/// Create a copy of AccountTemplatesValue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplatesValueCopyWith<AccountTemplatesValue> get copyWith => _$AccountTemplatesValueCopyWithImpl<AccountTemplatesValue>(this as AccountTemplatesValue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplatesValue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplatesValue&&(identical(other.schemaVersion, _this.schemaVersion) || other.schemaVersion == _this.schemaVersion)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&const DeepCollectionEquality().equals(other.templates, _this.templates)&&const DeepCollectionEquality().equals(other.modelCatalogs, _this.modelCatalogs));
}


@override
int get hashCode {
  final _this = this as AccountTemplatesValue;
  return Object.hash(runtimeType,_this.schemaVersion,_this.revision,const DeepCollectionEquality().hash(_this.templates),const DeepCollectionEquality().hash(_this.modelCatalogs));
}

@override
String toString() {
  final _this = this as AccountTemplatesValue;
  return 'AccountTemplatesValue(schemaVersion: ${_this.schemaVersion}, revision: ${_this.revision}, templates: ${_this.templates}, modelCatalogs: ${_this.modelCatalogs})';
}


}

/// @nodoc
abstract mixin class $AccountTemplatesValueCopyWith<$Res>  {
  factory $AccountTemplatesValueCopyWith(AccountTemplatesValue value, $Res Function(AccountTemplatesValue) _then) = _$AccountTemplatesValueCopyWithImpl;
@useResult
$Res call({
 int schemaVersion, String revision, List<AccountTemplate> templates, Map<String, NamedModelCatalog> modelCatalogs
});




}
/// @nodoc
class _$AccountTemplatesValueCopyWithImpl<$Res>
    implements $AccountTemplatesValueCopyWith<$Res> {
  _$AccountTemplatesValueCopyWithImpl(this._self, this._then);

  final AccountTemplatesValue _self;
  final $Res Function(AccountTemplatesValue) _then;

/// Create a copy of AccountTemplatesValue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? schemaVersion = null,Object? revision = null,Object? templates = null,Object? modelCatalogs = null,}) {
  return _then(AccountTemplatesValue(
schemaVersion: null == schemaVersion ? _self.schemaVersion : schemaVersion // ignore: cast_nullable_to_non_nullable
as int,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as String,templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as List<AccountTemplate>,modelCatalogs: null == modelCatalogs ? _self.modelCatalogs : modelCatalogs // ignore: cast_nullable_to_non_nullable
as Map<String, NamedModelCatalog>,
  ));
}

}


/// Adds pattern-matching-related methods to [AccountTemplatesValue].
extension AccountTemplatesValuePatterns on AccountTemplatesValue {
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
mixin _$AccountTemplate {

 String get id; String get displayName; String? get description; String get baseUrl; CredentialDescriptor get credential; String get modelCatalogId; String get protocol; String get suggestedModelId; String? get iconKey; AccountServiceCapabilities get serviceCapabilities;
/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountTemplateCopyWith<AccountTemplate> get copyWith => _$AccountTemplateCopyWithImpl<AccountTemplate>(this as AccountTemplate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountTemplate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountTemplate&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.baseUrl, _this.baseUrl) || other.baseUrl == _this.baseUrl)&&(identical(other.credential, _this.credential) || other.credential == _this.credential)&&(identical(other.modelCatalogId, _this.modelCatalogId) || other.modelCatalogId == _this.modelCatalogId)&&(identical(other.protocol, _this.protocol) || other.protocol == _this.protocol)&&(identical(other.suggestedModelId, _this.suggestedModelId) || other.suggestedModelId == _this.suggestedModelId)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.serviceCapabilities, _this.serviceCapabilities) || other.serviceCapabilities == _this.serviceCapabilities));
}


@override
int get hashCode {
  final _this = this as AccountTemplate;
  return Object.hash(runtimeType,_this.id,_this.displayName,_this.description,_this.baseUrl,_this.credential,_this.modelCatalogId,_this.protocol,_this.suggestedModelId,_this.iconKey,_this.serviceCapabilities);
}

@override
String toString() {
  final _this = this as AccountTemplate;
  return 'AccountTemplate(id: ${_this.id}, displayName: ${_this.displayName}, description: ${_this.description}, baseUrl: ${_this.baseUrl}, credential: ${_this.credential}, modelCatalogId: ${_this.modelCatalogId}, protocol: ${_this.protocol}, suggestedModelId: ${_this.suggestedModelId}, iconKey: ${_this.iconKey}, serviceCapabilities: ${_this.serviceCapabilities})';
}


}

/// @nodoc
abstract mixin class $AccountTemplateCopyWith<$Res>  {
  factory $AccountTemplateCopyWith(AccountTemplate value, $Res Function(AccountTemplate) _then) = _$AccountTemplateCopyWithImpl;
@useResult
$Res call({
 String id, String displayName, String? description, String baseUrl, CredentialDescriptor credential, String modelCatalogId, String protocol, String suggestedModelId, String? iconKey, AccountServiceCapabilities serviceCapabilities
});


$CredentialDescriptorCopyWith<$Res> get credential;$AccountServiceCapabilitiesCopyWith<$Res> get serviceCapabilities;

}
/// @nodoc
class _$AccountTemplateCopyWithImpl<$Res>
    implements $AccountTemplateCopyWith<$Res> {
  _$AccountTemplateCopyWithImpl(this._self, this._then);

  final AccountTemplate _self;
  final $Res Function(AccountTemplate) _then;

/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? displayName = null,Object? description = freezed,Object? baseUrl = null,Object? credential = null,Object? modelCatalogId = null,Object? protocol = null,Object? suggestedModelId = null,Object? iconKey = freezed,Object? serviceCapabilities = null,}) {
  return _then(AccountTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as CredentialDescriptor,modelCatalogId: null == modelCatalogId ? _self.modelCatalogId : modelCatalogId // ignore: cast_nullable_to_non_nullable
as String,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,suggestedModelId: null == suggestedModelId ? _self.suggestedModelId : suggestedModelId // ignore: cast_nullable_to_non_nullable
as String,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,serviceCapabilities: null == serviceCapabilities ? _self.serviceCapabilities : serviceCapabilities // ignore: cast_nullable_to_non_nullable
as AccountServiceCapabilities,
  ));
}
/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CredentialDescriptorCopyWith<$Res> get credential {

  return $CredentialDescriptorCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesCopyWith<$Res> get serviceCapabilities {

  return $AccountServiceCapabilitiesCopyWith<$Res>(_self.serviceCapabilities, (value) {
    return _then(_self.copyWith(serviceCapabilities: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountTemplate].
extension AccountTemplatePatterns on AccountTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountTemplate value)  $default,){
final _that = this;
switch (_that) {
case _AccountTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _AccountTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String displayName,  String? description,  String baseUrl,  CredentialDescriptor credential,  String modelCatalogId,  String protocol,  String suggestedModelId,  String? iconKey,  AccountServiceCapabilities serviceCapabilities)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountTemplate() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String displayName,  String? description,  String baseUrl,  CredentialDescriptor credential,  String modelCatalogId,  String protocol,  String suggestedModelId,  String? iconKey,  AccountServiceCapabilities serviceCapabilities)  $default,) {final _that = this;
switch (_that) {
case _AccountTemplate():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String displayName,  String? description,  String baseUrl,  CredentialDescriptor credential,  String modelCatalogId,  String protocol,  String suggestedModelId,  String? iconKey,  AccountServiceCapabilities serviceCapabilities)?  $default,) {final _that = this;
switch (_that) {
case _AccountTemplate() when $default != null:
return $default(_that.id,_that.displayName,_that.description,_that.baseUrl,_that.credential,_that.modelCatalogId,_that.protocol,_that.suggestedModelId,_that.iconKey,_that.serviceCapabilities);case _:
  return null;

}
}

}

/// @nodoc


class _AccountTemplate implements AccountTemplate {
  const _AccountTemplate({required this.id, required this.displayName, required this.description, required this.baseUrl, required this.credential, required this.modelCatalogId, required this.protocol, required this.suggestedModelId, required this.iconKey, required this.serviceCapabilities});


@override final  String id;
@override final  String displayName;
@override final  String? description;
@override final  String baseUrl;
@override final  CredentialDescriptor credential;
@override final  String modelCatalogId;
@override final  String protocol;
@override final  String suggestedModelId;
@override final  String? iconKey;
@override final  AccountServiceCapabilities serviceCapabilities;

/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountTemplateCopyWith<_AccountTemplate> get copyWith => __$AccountTemplateCopyWithImpl<_AccountTemplate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountTemplate&&(identical(other.id, id) || other.id == id)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.baseUrl, baseUrl) || other.baseUrl == baseUrl)&&(identical(other.credential, credential) || other.credential == credential)&&(identical(other.modelCatalogId, modelCatalogId) || other.modelCatalogId == modelCatalogId)&&(identical(other.protocol, protocol) || other.protocol == protocol)&&(identical(other.suggestedModelId, suggestedModelId) || other.suggestedModelId == suggestedModelId)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.serviceCapabilities, serviceCapabilities) || other.serviceCapabilities == serviceCapabilities));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,displayName,description,baseUrl,credential,modelCatalogId,protocol,suggestedModelId,iconKey,serviceCapabilities);
}

@override
String toString() {
    return 'AccountTemplate(id: $id, displayName: $displayName, description: $description, baseUrl: $baseUrl, credential: $credential, modelCatalogId: $modelCatalogId, protocol: $protocol, suggestedModelId: $suggestedModelId, iconKey: $iconKey, serviceCapabilities: $serviceCapabilities)';
}


}

/// @nodoc
abstract mixin class _$AccountTemplateCopyWith<$Res> implements $AccountTemplateCopyWith<$Res> {
  factory _$AccountTemplateCopyWith(_AccountTemplate value, $Res Function(_AccountTemplate) _then) = __$AccountTemplateCopyWithImpl;
@override @useResult
$Res call({
 String id, String displayName, String? description, String baseUrl, CredentialDescriptor credential, String modelCatalogId, String protocol, String suggestedModelId, String? iconKey, AccountServiceCapabilities serviceCapabilities
});


@override $CredentialDescriptorCopyWith<$Res> get credential;@override $AccountServiceCapabilitiesCopyWith<$Res> get serviceCapabilities;

}
/// @nodoc
class __$AccountTemplateCopyWithImpl<$Res>
    implements _$AccountTemplateCopyWith<$Res> {
  __$AccountTemplateCopyWithImpl(this._self, this._then);

  final _AccountTemplate _self;
  final $Res Function(_AccountTemplate) _then;

/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? displayName = null,Object? description = freezed,Object? baseUrl = null,Object? credential = null,Object? modelCatalogId = null,Object? protocol = null,Object? suggestedModelId = null,Object? iconKey = freezed,Object? serviceCapabilities = null,}) {
  return _then(_AccountTemplate(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,baseUrl: null == baseUrl ? _self.baseUrl : baseUrl // ignore: cast_nullable_to_non_nullable
as String,credential: null == credential ? _self.credential : credential // ignore: cast_nullable_to_non_nullable
as CredentialDescriptor,modelCatalogId: null == modelCatalogId ? _self.modelCatalogId : modelCatalogId // ignore: cast_nullable_to_non_nullable
as String,protocol: null == protocol ? _self.protocol : protocol // ignore: cast_nullable_to_non_nullable
as String,suggestedModelId: null == suggestedModelId ? _self.suggestedModelId : suggestedModelId // ignore: cast_nullable_to_non_nullable
as String,iconKey: freezed == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String?,serviceCapabilities: null == serviceCapabilities ? _self.serviceCapabilities : serviceCapabilities // ignore: cast_nullable_to_non_nullable
as AccountServiceCapabilities,
  ));
}

/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CredentialDescriptorCopyWith<$Res> get credential {

  return $CredentialDescriptorCopyWith<$Res>(_self.credential, (value) {
    return _then(_self.copyWith(credential: value));
  });
}/// Create a copy of AccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesCopyWith<$Res> get serviceCapabilities {

  return $AccountServiceCapabilitiesCopyWith<$Res>(_self.serviceCapabilities, (value) {
    return _then(_self.copyWith(serviceCapabilities: value));
  });
}
}

/// @nodoc
mixin _$CredentialDescriptor {

 String get label; String? get envVar;
/// Create a copy of CredentialDescriptor
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CredentialDescriptorCopyWith<CredentialDescriptor> get copyWith => _$CredentialDescriptorCopyWithImpl<CredentialDescriptor>(this as CredentialDescriptor, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as CredentialDescriptor;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is CredentialDescriptor&&(identical(other.label, _this.label) || other.label == _this.label)&&(identical(other.envVar, _this.envVar) || other.envVar == _this.envVar));
}


@override
int get hashCode {
  final _this = this as CredentialDescriptor;
  return Object.hash(runtimeType,_this.label,_this.envVar);
}

@override
String toString() {
  final _this = this as CredentialDescriptor;
  return 'CredentialDescriptor(label: ${_this.label}, envVar: ${_this.envVar})';
}


}

/// @nodoc
abstract mixin class $CredentialDescriptorCopyWith<$Res>  {
  factory $CredentialDescriptorCopyWith(CredentialDescriptor value, $Res Function(CredentialDescriptor) _then) = _$CredentialDescriptorCopyWithImpl;
@useResult
$Res call({
 String label, String? envVar
});




}
/// @nodoc
class _$CredentialDescriptorCopyWithImpl<$Res>
    implements $CredentialDescriptorCopyWith<$Res> {
  _$CredentialDescriptorCopyWithImpl(this._self, this._then);

  final CredentialDescriptor _self;
  final $Res Function(CredentialDescriptor) _then;

/// Create a copy of CredentialDescriptor
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? label = null,Object? envVar = freezed,}) {
  return _then(CredentialDescriptor(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,envVar: freezed == envVar ? _self.envVar : envVar // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [CredentialDescriptor].
extension CredentialDescriptorPatterns on CredentialDescriptor {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _CredentialDescriptor value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _CredentialDescriptor() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _CredentialDescriptor value)  $default,){
final _that = this;
switch (_that) {
case _CredentialDescriptor():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _CredentialDescriptor value)?  $default,){
final _that = this;
switch (_that) {
case _CredentialDescriptor() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String label,  String? envVar)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _CredentialDescriptor() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String label,  String? envVar)  $default,) {final _that = this;
switch (_that) {
case _CredentialDescriptor():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String label,  String? envVar)?  $default,) {final _that = this;
switch (_that) {
case _CredentialDescriptor() when $default != null:
return $default(_that.label,_that.envVar);case _:
  return null;

}
}

}

/// @nodoc


class _CredentialDescriptor implements CredentialDescriptor {
  const _CredentialDescriptor({required this.label, required this.envVar});


@override final  String label;
@override final  String? envVar;

/// Create a copy of CredentialDescriptor
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$CredentialDescriptorCopyWith<_CredentialDescriptor> get copyWith => __$CredentialDescriptorCopyWithImpl<_CredentialDescriptor>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _CredentialDescriptor&&(identical(other.label, label) || other.label == label)&&(identical(other.envVar, envVar) || other.envVar == envVar));
}


@override
int get hashCode {
    return Object.hash(runtimeType,label,envVar);
}

@override
String toString() {
    return 'CredentialDescriptor(label: $label, envVar: $envVar)';
}


}

/// @nodoc
abstract mixin class _$CredentialDescriptorCopyWith<$Res> implements $CredentialDescriptorCopyWith<$Res> {
  factory _$CredentialDescriptorCopyWith(_CredentialDescriptor value, $Res Function(_CredentialDescriptor) _then) = __$CredentialDescriptorCopyWithImpl;
@override @useResult
$Res call({
 String label, String? envVar
});




}
/// @nodoc
class __$CredentialDescriptorCopyWithImpl<$Res>
    implements _$CredentialDescriptorCopyWith<$Res> {
  __$CredentialDescriptorCopyWithImpl(this._self, this._then);

  final _CredentialDescriptor _self;
  final $Res Function(_CredentialDescriptor) _then;

/// Create a copy of CredentialDescriptor
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? label = null,Object? envVar = freezed,}) {
  return _then(_CredentialDescriptor(
label: null == label ? _self.label : label // ignore: cast_nullable_to_non_nullable
as String,envVar: freezed == envVar ? _self.envVar : envVar // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AccountServiceCapabilities {

 WebSearchServiceCapabilities get webSearch; String get promptCacheDialect; bool get responsesProgrammaticToolCalling;
/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AccountServiceCapabilitiesCopyWith<AccountServiceCapabilities> get copyWith => _$AccountServiceCapabilitiesCopyWithImpl<AccountServiceCapabilities>(this as AccountServiceCapabilities, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AccountServiceCapabilities;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AccountServiceCapabilities&&(identical(other.webSearch, _this.webSearch) || other.webSearch == _this.webSearch)&&(identical(other.promptCacheDialect, _this.promptCacheDialect) || other.promptCacheDialect == _this.promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, _this.responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == _this.responsesProgrammaticToolCalling));
}


@override
int get hashCode {
  final _this = this as AccountServiceCapabilities;
  return Object.hash(runtimeType,_this.webSearch,_this.promptCacheDialect,_this.responsesProgrammaticToolCalling);
}

@override
String toString() {
  final _this = this as AccountServiceCapabilities;
  return 'AccountServiceCapabilities(webSearch: ${_this.webSearch}, promptCacheDialect: ${_this.promptCacheDialect}, responsesProgrammaticToolCalling: ${_this.responsesProgrammaticToolCalling})';
}


}

/// @nodoc
abstract mixin class $AccountServiceCapabilitiesCopyWith<$Res>  {
  factory $AccountServiceCapabilitiesCopyWith(AccountServiceCapabilities value, $Res Function(AccountServiceCapabilities) _then) = _$AccountServiceCapabilitiesCopyWithImpl;
@useResult
$Res call({
 WebSearchServiceCapabilities webSearch, String promptCacheDialect, bool responsesProgrammaticToolCalling
});


$WebSearchServiceCapabilitiesCopyWith<$Res> get webSearch;

}
/// @nodoc
class _$AccountServiceCapabilitiesCopyWithImpl<$Res>
    implements $AccountServiceCapabilitiesCopyWith<$Res> {
  _$AccountServiceCapabilitiesCopyWithImpl(this._self, this._then);

  final AccountServiceCapabilities _self;
  final $Res Function(AccountServiceCapabilities) _then;

/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? webSearch = null,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,}) {
  return _then(AccountServiceCapabilities(
webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchServiceCapabilities,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as String,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesCopyWith<$Res> get webSearch {

  return $WebSearchServiceCapabilitiesCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}
}


/// Adds pattern-matching-related methods to [AccountServiceCapabilities].
extension AccountServiceCapabilitiesPatterns on AccountServiceCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AccountServiceCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AccountServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AccountServiceCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _AccountServiceCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AccountServiceCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _AccountServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( WebSearchServiceCapabilities webSearch,  String promptCacheDialect,  bool responsesProgrammaticToolCalling)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AccountServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( WebSearchServiceCapabilities webSearch,  String promptCacheDialect,  bool responsesProgrammaticToolCalling)  $default,) {final _that = this;
switch (_that) {
case _AccountServiceCapabilities():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( WebSearchServiceCapabilities webSearch,  String promptCacheDialect,  bool responsesProgrammaticToolCalling)?  $default,) {final _that = this;
switch (_that) {
case _AccountServiceCapabilities() when $default != null:
return $default(_that.webSearch,_that.promptCacheDialect,_that.responsesProgrammaticToolCalling);case _:
  return null;

}
}

}

/// @nodoc


class _AccountServiceCapabilities implements AccountServiceCapabilities {
  const _AccountServiceCapabilities({required this.webSearch, required this.promptCacheDialect, required this.responsesProgrammaticToolCalling});


@override final  WebSearchServiceCapabilities webSearch;
@override final  String promptCacheDialect;
@override final  bool responsesProgrammaticToolCalling;

/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AccountServiceCapabilitiesCopyWith<_AccountServiceCapabilities> get copyWith => __$AccountServiceCapabilitiesCopyWithImpl<_AccountServiceCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AccountServiceCapabilities&&(identical(other.webSearch, webSearch) || other.webSearch == webSearch)&&(identical(other.promptCacheDialect, promptCacheDialect) || other.promptCacheDialect == promptCacheDialect)&&(identical(other.responsesProgrammaticToolCalling, responsesProgrammaticToolCalling) || other.responsesProgrammaticToolCalling == responsesProgrammaticToolCalling));
}


@override
int get hashCode {
    return Object.hash(runtimeType,webSearch,promptCacheDialect,responsesProgrammaticToolCalling);
}

@override
String toString() {
    return 'AccountServiceCapabilities(webSearch: $webSearch, promptCacheDialect: $promptCacheDialect, responsesProgrammaticToolCalling: $responsesProgrammaticToolCalling)';
}


}

/// @nodoc
abstract mixin class _$AccountServiceCapabilitiesCopyWith<$Res> implements $AccountServiceCapabilitiesCopyWith<$Res> {
  factory _$AccountServiceCapabilitiesCopyWith(_AccountServiceCapabilities value, $Res Function(_AccountServiceCapabilities) _then) = __$AccountServiceCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 WebSearchServiceCapabilities webSearch, String promptCacheDialect, bool responsesProgrammaticToolCalling
});


@override $WebSearchServiceCapabilitiesCopyWith<$Res> get webSearch;

}
/// @nodoc
class __$AccountServiceCapabilitiesCopyWithImpl<$Res>
    implements _$AccountServiceCapabilitiesCopyWith<$Res> {
  __$AccountServiceCapabilitiesCopyWithImpl(this._self, this._then);

  final _AccountServiceCapabilities _self;
  final $Res Function(_AccountServiceCapabilities) _then;

/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? webSearch = null,Object? promptCacheDialect = null,Object? responsesProgrammaticToolCalling = null,}) {
  return _then(_AccountServiceCapabilities(
webSearch: null == webSearch ? _self.webSearch : webSearch // ignore: cast_nullable_to_non_nullable
as WebSearchServiceCapabilities,promptCacheDialect: null == promptCacheDialect ? _self.promptCacheDialect : promptCacheDialect // ignore: cast_nullable_to_non_nullable
as String,responsesProgrammaticToolCalling: null == responsesProgrammaticToolCalling ? _self.responsesProgrammaticToolCalling : responsesProgrammaticToolCalling // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AccountServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesCopyWith<$Res> get webSearch {

  return $WebSearchServiceCapabilitiesCopyWith<$Res>(_self.webSearch, (value) {
    return _then(_self.copyWith(webSearch: value));
  });
}
}

/// @nodoc
mixin _$WebSearchServiceCapabilities {

 bool get hostedResponses; String get hostedDialect; String? get standalone;
/// Create a copy of WebSearchServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$WebSearchServiceCapabilitiesCopyWith<WebSearchServiceCapabilities> get copyWith => _$WebSearchServiceCapabilitiesCopyWithImpl<WebSearchServiceCapabilities>(this as WebSearchServiceCapabilities, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as WebSearchServiceCapabilities;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is WebSearchServiceCapabilities&&(identical(other.hostedResponses, _this.hostedResponses) || other.hostedResponses == _this.hostedResponses)&&(identical(other.hostedDialect, _this.hostedDialect) || other.hostedDialect == _this.hostedDialect)&&(identical(other.standalone, _this.standalone) || other.standalone == _this.standalone));
}


@override
int get hashCode {
  final _this = this as WebSearchServiceCapabilities;
  return Object.hash(runtimeType,_this.hostedResponses,_this.hostedDialect,_this.standalone);
}

@override
String toString() {
  final _this = this as WebSearchServiceCapabilities;
  return 'WebSearchServiceCapabilities(hostedResponses: ${_this.hostedResponses}, hostedDialect: ${_this.hostedDialect}, standalone: ${_this.standalone})';
}


}

/// @nodoc
abstract mixin class $WebSearchServiceCapabilitiesCopyWith<$Res>  {
  factory $WebSearchServiceCapabilitiesCopyWith(WebSearchServiceCapabilities value, $Res Function(WebSearchServiceCapabilities) _then) = _$WebSearchServiceCapabilitiesCopyWithImpl;
@useResult
$Res call({
 bool hostedResponses, String hostedDialect, String? standalone
});




}
/// @nodoc
class _$WebSearchServiceCapabilitiesCopyWithImpl<$Res>
    implements $WebSearchServiceCapabilitiesCopyWith<$Res> {
  _$WebSearchServiceCapabilitiesCopyWithImpl(this._self, this._then);

  final WebSearchServiceCapabilities _self;
  final $Res Function(WebSearchServiceCapabilities) _then;

/// Create a copy of WebSearchServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? hostedResponses = null,Object? hostedDialect = null,Object? standalone = freezed,}) {
  return _then(WebSearchServiceCapabilities(
hostedResponses: null == hostedResponses ? _self.hostedResponses : hostedResponses // ignore: cast_nullable_to_non_nullable
as bool,hostedDialect: null == hostedDialect ? _self.hostedDialect : hostedDialect // ignore: cast_nullable_to_non_nullable
as String,standalone: freezed == standalone ? _self.standalone : standalone // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [WebSearchServiceCapabilities].
extension WebSearchServiceCapabilitiesPatterns on WebSearchServiceCapabilities {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _WebSearchServiceCapabilities value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _WebSearchServiceCapabilities value)  $default,){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _WebSearchServiceCapabilities value)?  $default,){
final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool hostedResponses,  String hostedDialect,  String? standalone)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool hostedResponses,  String hostedDialect,  String? standalone)  $default,) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool hostedResponses,  String hostedDialect,  String? standalone)?  $default,) {final _that = this;
switch (_that) {
case _WebSearchServiceCapabilities() when $default != null:
return $default(_that.hostedResponses,_that.hostedDialect,_that.standalone);case _:
  return null;

}
}

}

/// @nodoc


class _WebSearchServiceCapabilities implements WebSearchServiceCapabilities {
  const _WebSearchServiceCapabilities({required this.hostedResponses, required this.hostedDialect, required this.standalone});


@override final  bool hostedResponses;
@override final  String hostedDialect;
@override final  String? standalone;

/// Create a copy of WebSearchServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$WebSearchServiceCapabilitiesCopyWith<_WebSearchServiceCapabilities> get copyWith => __$WebSearchServiceCapabilitiesCopyWithImpl<_WebSearchServiceCapabilities>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _WebSearchServiceCapabilities&&(identical(other.hostedResponses, hostedResponses) || other.hostedResponses == hostedResponses)&&(identical(other.hostedDialect, hostedDialect) || other.hostedDialect == hostedDialect)&&(identical(other.standalone, standalone) || other.standalone == standalone));
}


@override
int get hashCode {
    return Object.hash(runtimeType,hostedResponses,hostedDialect,standalone);
}

@override
String toString() {
    return 'WebSearchServiceCapabilities(hostedResponses: $hostedResponses, hostedDialect: $hostedDialect, standalone: $standalone)';
}


}

/// @nodoc
abstract mixin class _$WebSearchServiceCapabilitiesCopyWith<$Res> implements $WebSearchServiceCapabilitiesCopyWith<$Res> {
  factory _$WebSearchServiceCapabilitiesCopyWith(_WebSearchServiceCapabilities value, $Res Function(_WebSearchServiceCapabilities) _then) = __$WebSearchServiceCapabilitiesCopyWithImpl;
@override @useResult
$Res call({
 bool hostedResponses, String hostedDialect, String? standalone
});




}
/// @nodoc
class __$WebSearchServiceCapabilitiesCopyWithImpl<$Res>
    implements _$WebSearchServiceCapabilitiesCopyWith<$Res> {
  __$WebSearchServiceCapabilitiesCopyWithImpl(this._self, this._then);

  final _WebSearchServiceCapabilities _self;
  final $Res Function(_WebSearchServiceCapabilities) _then;

/// Create a copy of WebSearchServiceCapabilities
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? hostedResponses = null,Object? hostedDialect = null,Object? standalone = freezed,}) {
  return _then(_WebSearchServiceCapabilities(
hostedResponses: null == hostedResponses ? _self.hostedResponses : hostedResponses // ignore: cast_nullable_to_non_nullable
as bool,hostedDialect: null == hostedDialect ? _self.hostedDialect : hostedDialect // ignore: cast_nullable_to_non_nullable
as String,standalone: freezed == standalone ? _self.standalone : standalone // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$NamedModelCatalog {


/// Create a copy of NamedModelCatalog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NamedModelCatalogCopyWith<NamedModelCatalog> get copyWith => _$NamedModelCatalogCopyWithImpl<NamedModelCatalog>(this as NamedModelCatalog, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NamedModelCatalog;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NamedModelCatalog&&(identical(other.id, _this.id) || other.id == _this.id)&&const DeepCollectionEquality().equals(other.models, _this.models));
}


@override
int get hashCode {
  final _this = this as NamedModelCatalog;
  return Object.hash(runtimeType,_this.id,const DeepCollectionEquality().hash(_this.models));
}

@override
String toString() {
  final _this = this as NamedModelCatalog;
  return 'NamedModelCatalog(id: ${_this.id}, models: ${_this.models})';
}


}

/// @nodoc
abstract mixin class $NamedModelCatalogCopyWith<$Res>  {
  factory $NamedModelCatalogCopyWith(NamedModelCatalog value, $Res Function(NamedModelCatalog) _then) = _$NamedModelCatalogCopyWithImpl;
@useResult
$Res call({
 String id, List<ModelDescriptor> models
});




}
/// @nodoc
class _$NamedModelCatalogCopyWithImpl<$Res>
    implements $NamedModelCatalogCopyWith<$Res> {
  _$NamedModelCatalogCopyWithImpl(this._self, this._then);

  final NamedModelCatalog _self;
  final $Res Function(NamedModelCatalog) _then;

/// Create a copy of NamedModelCatalog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? models = null,}) {
  return _then(NamedModelCatalog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as List<ModelDescriptor>,
  ));
}

}


/// Adds pattern-matching-related methods to [NamedModelCatalog].
extension NamedModelCatalogPatterns on NamedModelCatalog {
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
