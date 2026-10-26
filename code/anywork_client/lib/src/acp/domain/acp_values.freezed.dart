// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAccountTemplate {

 AcpProvider get provider; String get displayName;/// 一句话说明；界面不用它推断协议或凭据语义。
 String get description;/// 品牌图标键；空字符串表示模板没有提供，展示层回退到首字母。
 String get iconKey;/// 产品固定的受管服务器版本；客户端不硬编码版本，也不允许用户选择。
 String get supportedVersion;/// 官方安装说明地址；空字符串表示不展示入口，也不从进程输出推导。
 String get installUrl;/// 官方条款地址；空字符串表示后端未提供。
 String get termsUrl;/// 后端声明的自动准备资格与目标平台；缺省是不支持。
 AcpInstallAvailability get automaticInstall;
/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountTemplateCopyWith<AcpAccountTemplate> get copyWith => _$AcpAccountTemplateCopyWithImpl<AcpAccountTemplate>(this as AcpAccountTemplate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountTemplate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountTemplate&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.displayName, _this.displayName) || other.displayName == _this.displayName)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.iconKey, _this.iconKey) || other.iconKey == _this.iconKey)&&(identical(other.supportedVersion, _this.supportedVersion) || other.supportedVersion == _this.supportedVersion)&&(identical(other.installUrl, _this.installUrl) || other.installUrl == _this.installUrl)&&(identical(other.termsUrl, _this.termsUrl) || other.termsUrl == _this.termsUrl)&&(identical(other.automaticInstall, _this.automaticInstall) || other.automaticInstall == _this.automaticInstall));
}


@override
int get hashCode {
  final _this = this as AcpAccountTemplate;
  return Object.hash(runtimeType,_this.provider,_this.displayName,_this.description,_this.iconKey,_this.supportedVersion,_this.installUrl,_this.termsUrl,_this.automaticInstall);
}



}

/// @nodoc
abstract mixin class $AcpAccountTemplateCopyWith<$Res>  {
  factory $AcpAccountTemplateCopyWith(AcpAccountTemplate value, $Res Function(AcpAccountTemplate) _then) = _$AcpAccountTemplateCopyWithImpl;
@useResult
$Res call({
 AcpProvider provider, String displayName, String description, String iconKey, String supportedVersion, String installUrl, String termsUrl, AcpInstallAvailability automaticInstall
});


$AcpInstallAvailabilityCopyWith<$Res> get automaticInstall;

}
/// @nodoc
class _$AcpAccountTemplateCopyWithImpl<$Res>
    implements $AcpAccountTemplateCopyWith<$Res> {
  _$AcpAccountTemplateCopyWithImpl(this._self, this._then);

  final AcpAccountTemplate _self;
  final $Res Function(AcpAccountTemplate) _then;

/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? provider = null,Object? displayName = null,Object? description = null,Object? iconKey = null,Object? supportedVersion = null,Object? installUrl = null,Object? termsUrl = null,Object? automaticInstall = null,}) {
  return _then(AcpAccountTemplate(
provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,iconKey: null == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String,supportedVersion: null == supportedVersion ? _self.supportedVersion : supportedVersion // ignore: cast_nullable_to_non_nullable
as String,installUrl: null == installUrl ? _self.installUrl : installUrl // ignore: cast_nullable_to_non_nullable
as String,termsUrl: null == termsUrl ? _self.termsUrl : termsUrl // ignore: cast_nullable_to_non_nullable
as String,automaticInstall: null == automaticInstall ? _self.automaticInstall : automaticInstall // ignore: cast_nullable_to_non_nullable
as AcpInstallAvailability,
  ));
}
/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallAvailabilityCopyWith<$Res> get automaticInstall {

  return $AcpInstallAvailabilityCopyWith<$Res>(_self.automaticInstall, (value) {
    return _then(_self.copyWith(automaticInstall: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAccountTemplate].
extension AcpAccountTemplatePatterns on AcpAccountTemplate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountTemplate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountTemplate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountTemplate value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountTemplate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountTemplate value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountTemplate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpProvider provider,  String displayName,  String description,  String iconKey,  String supportedVersion,  String installUrl,  String termsUrl,  AcpInstallAvailability automaticInstall)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountTemplate() when $default != null:
return $default(_that.provider,_that.displayName,_that.description,_that.iconKey,_that.supportedVersion,_that.installUrl,_that.termsUrl,_that.automaticInstall);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpProvider provider,  String displayName,  String description,  String iconKey,  String supportedVersion,  String installUrl,  String termsUrl,  AcpInstallAvailability automaticInstall)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountTemplate():
return $default(_that.provider,_that.displayName,_that.description,_that.iconKey,_that.supportedVersion,_that.installUrl,_that.termsUrl,_that.automaticInstall);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpProvider provider,  String displayName,  String description,  String iconKey,  String supportedVersion,  String installUrl,  String termsUrl,  AcpInstallAvailability automaticInstall)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountTemplate() when $default != null:
return $default(_that.provider,_that.displayName,_that.description,_that.iconKey,_that.supportedVersion,_that.installUrl,_that.termsUrl,_that.automaticInstall);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountTemplate extends AcpAccountTemplate {
  const _AcpAccountTemplate({required this.provider, required this.displayName, required this.description, required this.iconKey, required this.supportedVersion, required this.installUrl, required this.termsUrl, required this.automaticInstall}): super._();


@override final  AcpProvider provider;
@override final  String displayName;
/// 一句话说明；界面不用它推断协议或凭据语义。
@override final  String description;
/// 品牌图标键；空字符串表示模板没有提供，展示层回退到首字母。
@override final  String iconKey;
/// 产品固定的受管服务器版本；客户端不硬编码版本，也不允许用户选择。
@override final  String supportedVersion;
/// 官方安装说明地址；空字符串表示不展示入口，也不从进程输出推导。
@override final  String installUrl;
/// 官方条款地址；空字符串表示后端未提供。
@override final  String termsUrl;
/// 后端声明的自动准备资格与目标平台；缺省是不支持。
@override final  AcpInstallAvailability automaticInstall;

/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountTemplateCopyWith<_AcpAccountTemplate> get copyWith => __$AcpAccountTemplateCopyWithImpl<_AcpAccountTemplate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountTemplate&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.displayName, displayName) || other.displayName == displayName)&&(identical(other.description, description) || other.description == description)&&(identical(other.iconKey, iconKey) || other.iconKey == iconKey)&&(identical(other.supportedVersion, supportedVersion) || other.supportedVersion == supportedVersion)&&(identical(other.installUrl, installUrl) || other.installUrl == installUrl)&&(identical(other.termsUrl, termsUrl) || other.termsUrl == termsUrl)&&(identical(other.automaticInstall, automaticInstall) || other.automaticInstall == automaticInstall));
}


@override
int get hashCode {
    return Object.hash(runtimeType,provider,displayName,description,iconKey,supportedVersion,installUrl,termsUrl,automaticInstall);
}



}

/// @nodoc
abstract mixin class _$AcpAccountTemplateCopyWith<$Res> implements $AcpAccountTemplateCopyWith<$Res> {
  factory _$AcpAccountTemplateCopyWith(_AcpAccountTemplate value, $Res Function(_AcpAccountTemplate) _then) = __$AcpAccountTemplateCopyWithImpl;
@override @useResult
$Res call({
 AcpProvider provider, String displayName, String description, String iconKey, String supportedVersion, String installUrl, String termsUrl, AcpInstallAvailability automaticInstall
});


@override $AcpInstallAvailabilityCopyWith<$Res> get automaticInstall;

}
/// @nodoc
class __$AcpAccountTemplateCopyWithImpl<$Res>
    implements _$AcpAccountTemplateCopyWith<$Res> {
  __$AcpAccountTemplateCopyWithImpl(this._self, this._then);

  final _AcpAccountTemplate _self;
  final $Res Function(_AcpAccountTemplate) _then;

/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? provider = null,Object? displayName = null,Object? description = null,Object? iconKey = null,Object? supportedVersion = null,Object? installUrl = null,Object? termsUrl = null,Object? automaticInstall = null,}) {
  return _then(_AcpAccountTemplate(
provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,displayName: null == displayName ? _self.displayName : displayName // ignore: cast_nullable_to_non_nullable
as String,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,iconKey: null == iconKey ? _self.iconKey : iconKey // ignore: cast_nullable_to_non_nullable
as String,supportedVersion: null == supportedVersion ? _self.supportedVersion : supportedVersion // ignore: cast_nullable_to_non_nullable
as String,installUrl: null == installUrl ? _self.installUrl : installUrl // ignore: cast_nullable_to_non_nullable
as String,termsUrl: null == termsUrl ? _self.termsUrl : termsUrl // ignore: cast_nullable_to_non_nullable
as String,automaticInstall: null == automaticInstall ? _self.automaticInstall : automaticInstall // ignore: cast_nullable_to_non_nullable
as AcpInstallAvailability,
  ));
}

/// Create a copy of AcpAccountTemplate
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallAvailabilityCopyWith<$Res> get automaticInstall {

  return $AcpInstallAvailabilityCopyWith<$Res>(_self.automaticInstall, (value) {
    return _then(_self.copyWith(automaticInstall: value));
  });
}
}

/// @nodoc
mixin _$AcpAccountCatalog {

 List<AcpAccountTemplate> get templates;
/// Create a copy of AcpAccountCatalog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountCatalogCopyWith<AcpAccountCatalog> get copyWith => _$AcpAccountCatalogCopyWithImpl<AcpAccountCatalog>(this as AcpAccountCatalog, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountCatalog;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountCatalog&&const DeepCollectionEquality().equals(other.templates, _this.templates));
}


@override
int get hashCode {
  final _this = this as AcpAccountCatalog;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.templates));
}



}

/// @nodoc
abstract mixin class $AcpAccountCatalogCopyWith<$Res>  {
  factory $AcpAccountCatalogCopyWith(AcpAccountCatalog value, $Res Function(AcpAccountCatalog) _then) = _$AcpAccountCatalogCopyWithImpl;
@useResult
$Res call({
 List<AcpAccountTemplate> templates
});




}
/// @nodoc
class _$AcpAccountCatalogCopyWithImpl<$Res>
    implements $AcpAccountCatalogCopyWith<$Res> {
  _$AcpAccountCatalogCopyWithImpl(this._self, this._then);

  final AcpAccountCatalog _self;
  final $Res Function(AcpAccountCatalog) _then;

/// Create a copy of AcpAccountCatalog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? templates = null,}) {
  return _then(AcpAccountCatalog(
templates: null == templates ? _self.templates : templates // ignore: cast_nullable_to_non_nullable
as List<AcpAccountTemplate>,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAccountCatalog].
extension AcpAccountCatalogPatterns on AcpAccountCatalog {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountCatalog value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountCatalog() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountCatalog value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountCatalog():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountCatalog value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountCatalog() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( List<AcpAccountTemplate> templates)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountCatalog() when $default != null:
return $default(_that.templates);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( List<AcpAccountTemplate> templates)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountCatalog():
return $default(_that.templates);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( List<AcpAccountTemplate> templates)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountCatalog() when $default != null:
return $default(_that.templates);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountCatalog extends AcpAccountCatalog {
  const _AcpAccountCatalog({required  List<AcpAccountTemplate> templates}): _templates = templates,super._();


 final  List<AcpAccountTemplate> _templates;
@override List<AcpAccountTemplate> get templates {
  if (_templates is EqualUnmodifiableListView) return _templates;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_templates);
}


/// Create a copy of AcpAccountCatalog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountCatalogCopyWith<_AcpAccountCatalog> get copyWith => __$AcpAccountCatalogCopyWithImpl<_AcpAccountCatalog>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountCatalog&&const DeepCollectionEquality().equals(other.templates, _templates));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(_templates));
}



}

/// @nodoc
abstract mixin class _$AcpAccountCatalogCopyWith<$Res> implements $AcpAccountCatalogCopyWith<$Res> {
  factory _$AcpAccountCatalogCopyWith(_AcpAccountCatalog value, $Res Function(_AcpAccountCatalog) _then) = __$AcpAccountCatalogCopyWithImpl;
@override @useResult
$Res call({
 List<AcpAccountTemplate> templates
});




}
/// @nodoc
class __$AcpAccountCatalogCopyWithImpl<$Res>
    implements _$AcpAccountCatalogCopyWith<$Res> {
  __$AcpAccountCatalogCopyWithImpl(this._self, this._then);

  final _AcpAccountCatalog _self;
  final $Res Function(_AcpAccountCatalog) _then;

/// Create a copy of AcpAccountCatalog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? templates = null,}) {
  return _then(_AcpAccountCatalog(
templates: null == templates ? _self._templates : templates // ignore: cast_nullable_to_non_nullable
as List<AcpAccountTemplate>,
  ));
}


}

/// @nodoc
mixin _$AcpAccountSettings {

 String get accountId; String get name; AcpProvider get provider; int get connectionRevision;
/// Create a copy of AcpAccountSettings
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountSettingsCopyWith<AcpAccountSettings> get copyWith => _$AcpAccountSettingsCopyWithImpl<AcpAccountSettings>(this as AcpAccountSettings, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountSettings;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountSettings&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.provider, _this.provider) || other.provider == _this.provider)&&(identical(other.connectionRevision, _this.connectionRevision) || other.connectionRevision == _this.connectionRevision));
}


@override
int get hashCode {
  final _this = this as AcpAccountSettings;
  return Object.hash(runtimeType,_this.accountId,_this.name,_this.provider,_this.connectionRevision);
}



}

/// @nodoc
abstract mixin class $AcpAccountSettingsCopyWith<$Res>  {
  factory $AcpAccountSettingsCopyWith(AcpAccountSettings value, $Res Function(AcpAccountSettings) _then) = _$AcpAccountSettingsCopyWithImpl;
@useResult
$Res call({
 String accountId, String name, AcpProvider provider, int connectionRevision
});




}
/// @nodoc
class _$AcpAccountSettingsCopyWithImpl<$Res>
    implements $AcpAccountSettingsCopyWith<$Res> {
  _$AcpAccountSettingsCopyWithImpl(this._self, this._then);

  final AcpAccountSettings _self;
  final $Res Function(AcpAccountSettings) _then;

/// Create a copy of AcpAccountSettings
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? name = null,Object? provider = null,Object? connectionRevision = null,}) {
  return _then(AcpAccountSettings(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAccountSettings].
extension AcpAccountSettingsPatterns on AcpAccountSettings {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountSettings value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountSettings() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountSettings value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountSettings():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountSettings value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountSettings() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String name,  AcpProvider provider,  int connectionRevision)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountSettings() when $default != null:
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String name,  AcpProvider provider,  int connectionRevision)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountSettings():
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String name,  AcpProvider provider,  int connectionRevision)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountSettings() when $default != null:
return $default(_that.accountId,_that.name,_that.provider,_that.connectionRevision);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountSettings extends AcpAccountSettings {
  const _AcpAccountSettings({required this.accountId, required this.name, required this.provider, required this.connectionRevision}): super._();


@override final  String accountId;
@override final  String name;
@override final  AcpProvider provider;
@override final  int connectionRevision;

/// Create a copy of AcpAccountSettings
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountSettingsCopyWith<_AcpAccountSettings> get copyWith => __$AcpAccountSettingsCopyWithImpl<_AcpAccountSettings>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountSettings&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.name, name) || other.name == name)&&(identical(other.provider, provider) || other.provider == provider)&&(identical(other.connectionRevision, connectionRevision) || other.connectionRevision == connectionRevision));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,name,provider,connectionRevision);
}



}

/// @nodoc
abstract mixin class _$AcpAccountSettingsCopyWith<$Res> implements $AcpAccountSettingsCopyWith<$Res> {
  factory _$AcpAccountSettingsCopyWith(_AcpAccountSettings value, $Res Function(_AcpAccountSettings) _then) = __$AcpAccountSettingsCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String name, AcpProvider provider, int connectionRevision
});




}
/// @nodoc
class __$AcpAccountSettingsCopyWithImpl<$Res>
    implements _$AcpAccountSettingsCopyWith<$Res> {
  __$AcpAccountSettingsCopyWithImpl(this._self, this._then);

  final _AcpAccountSettings _self;
  final $Res Function(_AcpAccountSettings) _then;

/// Create a copy of AcpAccountSettings
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? name = null,Object? provider = null,Object? connectionRevision = null,}) {
  return _then(_AcpAccountSettings(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,connectionRevision: null == connectionRevision ? _self.connectionRevision : connectionRevision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$AcpAccountUpdate {

 String get accountId; String get name; AcpProvider get provider;
/// Create a copy of AcpAccountUpdate
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAccountUpdateCopyWith<AcpAccountUpdate> get copyWith => _$AcpAccountUpdateCopyWithImpl<AcpAccountUpdate>(this as AcpAccountUpdate, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAccountUpdate;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAccountUpdate&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.provider, _this.provider) || other.provider == _this.provider));
}


@override
int get hashCode {
  final _this = this as AcpAccountUpdate;
  return Object.hash(runtimeType,_this.accountId,_this.name,_this.provider);
}

@override
String toString() {
  final _this = this as AcpAccountUpdate;
  return 'AcpAccountUpdate(accountId: ${_this.accountId}, name: ${_this.name}, provider: ${_this.provider})';
}


}

/// @nodoc
abstract mixin class $AcpAccountUpdateCopyWith<$Res>  {
  factory $AcpAccountUpdateCopyWith(AcpAccountUpdate value, $Res Function(AcpAccountUpdate) _then) = _$AcpAccountUpdateCopyWithImpl;
@useResult
$Res call({
 String accountId, String name, AcpProvider provider
});




}
/// @nodoc
class _$AcpAccountUpdateCopyWithImpl<$Res>
    implements $AcpAccountUpdateCopyWith<$Res> {
  _$AcpAccountUpdateCopyWithImpl(this._self, this._then);

  final AcpAccountUpdate _self;
  final $Res Function(AcpAccountUpdate) _then;

/// Create a copy of AcpAccountUpdate
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? name = null,Object? provider = null,}) {
  return _then(AcpAccountUpdate(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAccountUpdate].
extension AcpAccountUpdatePatterns on AcpAccountUpdate {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAccountUpdate value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAccountUpdate() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAccountUpdate value)  $default,){
final _that = this;
switch (_that) {
case _AcpAccountUpdate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAccountUpdate value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAccountUpdate() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String name,  AcpProvider provider)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAccountUpdate() when $default != null:
return $default(_that.accountId,_that.name,_that.provider);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String name,  AcpProvider provider)  $default,) {final _that = this;
switch (_that) {
case _AcpAccountUpdate():
return $default(_that.accountId,_that.name,_that.provider);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String name,  AcpProvider provider)?  $default,) {final _that = this;
switch (_that) {
case _AcpAccountUpdate() when $default != null:
return $default(_that.accountId,_that.name,_that.provider);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAccountUpdate implements AcpAccountUpdate {
  const _AcpAccountUpdate({required this.accountId, required this.name, required this.provider});


@override final  String accountId;
@override final  String name;
@override final  AcpProvider provider;

/// Create a copy of AcpAccountUpdate
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAccountUpdateCopyWith<_AcpAccountUpdate> get copyWith => __$AcpAccountUpdateCopyWithImpl<_AcpAccountUpdate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAccountUpdate&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.name, name) || other.name == name)&&(identical(other.provider, provider) || other.provider == provider));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,name,provider);
}

@override
String toString() {
    return 'AcpAccountUpdate(accountId: $accountId, name: $name, provider: $provider)';
}


}

/// @nodoc
abstract mixin class _$AcpAccountUpdateCopyWith<$Res> implements $AcpAccountUpdateCopyWith<$Res> {
  factory _$AcpAccountUpdateCopyWith(_AcpAccountUpdate value, $Res Function(_AcpAccountUpdate) _then) = __$AcpAccountUpdateCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String name, AcpProvider provider
});




}
/// @nodoc
class __$AcpAccountUpdateCopyWithImpl<$Res>
    implements _$AcpAccountUpdateCopyWith<$Res> {
  __$AcpAccountUpdateCopyWithImpl(this._self, this._then);

  final _AcpAccountUpdate _self;
  final $Res Function(_AcpAccountUpdate) _then;

/// Create a copy of AcpAccountUpdate
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? name = null,Object? provider = null,}) {
  return _then(_AcpAccountUpdate(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,provider: null == provider ? _self.provider : provider // ignore: cast_nullable_to_non_nullable
as AcpProvider,
  ));
}


}

/// @nodoc
mixin _$AcpAuthMethod {

 String get id; String get name;/// 服务端说明；null 表示对端未提供，UI 不合成文案。
 String? get description; AcpAuthMethodKind get kind;
/// Create a copy of AcpAuthMethod
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthMethodCopyWith<AcpAuthMethod> get copyWith => _$AcpAuthMethodCopyWithImpl<AcpAuthMethod>(this as AcpAuthMethod, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthMethod;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthMethod&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.kind, _this.kind) || other.kind == _this.kind));
}


@override
int get hashCode {
  final _this = this as AcpAuthMethod;
  return Object.hash(runtimeType,_this.id,_this.name,_this.description,_this.kind);
}



}

/// @nodoc
abstract mixin class $AcpAuthMethodCopyWith<$Res>  {
  factory $AcpAuthMethodCopyWith(AcpAuthMethod value, $Res Function(AcpAuthMethod) _then) = _$AcpAuthMethodCopyWithImpl;
@useResult
$Res call({
 String id, String name, String? description, AcpAuthMethodKind kind
});




}
/// @nodoc
class _$AcpAuthMethodCopyWithImpl<$Res>
    implements $AcpAuthMethodCopyWith<$Res> {
  _$AcpAuthMethodCopyWithImpl(this._self, this._then);

  final AcpAuthMethod _self;
  final $Res Function(AcpAuthMethod) _then;

/// Create a copy of AcpAuthMethod
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? kind = null,}) {
  return _then(AcpAuthMethod(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AcpAuthMethodKind,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAuthMethod].
extension AcpAuthMethodPatterns on AcpAuthMethod {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthMethod value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthMethod() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthMethod value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthMethod():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthMethod value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthMethod() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  AcpAuthMethodKind kind)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthMethod() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.kind);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String name,  String? description,  AcpAuthMethodKind kind)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthMethod():
return $default(_that.id,_that.name,_that.description,_that.kind);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String name,  String? description,  AcpAuthMethodKind kind)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthMethod() when $default != null:
return $default(_that.id,_that.name,_that.description,_that.kind);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthMethod extends AcpAuthMethod {
  const _AcpAuthMethod({required this.id, required this.name, required this.description, required this.kind}): super._();


@override final  String id;
@override final  String name;
/// 服务端说明；null 表示对端未提供，UI 不合成文案。
@override final  String? description;
@override final  AcpAuthMethodKind kind;

/// Create a copy of AcpAuthMethod
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthMethodCopyWith<_AcpAuthMethod> get copyWith => __$AcpAuthMethodCopyWithImpl<_AcpAuthMethod>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthMethod&&(identical(other.id, id) || other.id == id)&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.kind, kind) || other.kind == kind));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,name,description,kind);
}



}

/// @nodoc
abstract mixin class _$AcpAuthMethodCopyWith<$Res> implements $AcpAuthMethodCopyWith<$Res> {
  factory _$AcpAuthMethodCopyWith(_AcpAuthMethod value, $Res Function(_AcpAuthMethod) _then) = __$AcpAuthMethodCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String? description, AcpAuthMethodKind kind
});




}
/// @nodoc
class __$AcpAuthMethodCopyWithImpl<$Res>
    implements _$AcpAuthMethodCopyWith<$Res> {
  __$AcpAuthMethodCopyWithImpl(this._self, this._then);

  final _AcpAuthMethod _self;
  final $Res Function(_AcpAuthMethod) _then;

/// Create a copy of AcpAuthMethod
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? description = freezed,Object? kind = null,}) {
  return _then(_AcpAuthMethod(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as AcpAuthMethodKind,
  ));
}


}

/// @nodoc
mixin _$AcpServerInfo {

 String get name;/// 服务端标题；null 表示对端未提供，不用本地账号名称补造。
 String? get title; String get version;
/// Create a copy of AcpServerInfo
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpServerInfoCopyWith<AcpServerInfo> get copyWith => _$AcpServerInfoCopyWithImpl<AcpServerInfo>(this as AcpServerInfo, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpServerInfo;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpServerInfo&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.title, _this.title) || other.title == _this.title)&&(identical(other.version, _this.version) || other.version == _this.version));
}


@override
int get hashCode {
  final _this = this as AcpServerInfo;
  return Object.hash(runtimeType,_this.name,_this.title,_this.version);
}



}

/// @nodoc
abstract mixin class $AcpServerInfoCopyWith<$Res>  {
  factory $AcpServerInfoCopyWith(AcpServerInfo value, $Res Function(AcpServerInfo) _then) = _$AcpServerInfoCopyWithImpl;
@useResult
$Res call({
 String name, String? title, String version
});




}
/// @nodoc
class _$AcpServerInfoCopyWithImpl<$Res>
    implements $AcpServerInfoCopyWith<$Res> {
  _$AcpServerInfoCopyWithImpl(this._self, this._then);

  final AcpServerInfo _self;
  final $Res Function(AcpServerInfo) _then;

/// Create a copy of AcpServerInfo
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? title = freezed,Object? version = null,}) {
  return _then(AcpServerInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpServerInfo].
extension AcpServerInfoPatterns on AcpServerInfo {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpServerInfo value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpServerInfo() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpServerInfo value)  $default,){
final _that = this;
switch (_that) {
case _AcpServerInfo():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpServerInfo value)?  $default,){
final _that = this;
switch (_that) {
case _AcpServerInfo() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String name,  String? title,  String version)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpServerInfo() when $default != null:
return $default(_that.name,_that.title,_that.version);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String name,  String? title,  String version)  $default,) {final _that = this;
switch (_that) {
case _AcpServerInfo():
return $default(_that.name,_that.title,_that.version);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String name,  String? title,  String version)?  $default,) {final _that = this;
switch (_that) {
case _AcpServerInfo() when $default != null:
return $default(_that.name,_that.title,_that.version);case _:
  return null;

}
}

}

/// @nodoc


class _AcpServerInfo extends AcpServerInfo {
  const _AcpServerInfo({required this.name, required this.title, required this.version}): super._();


@override final  String name;
/// 服务端标题；null 表示对端未提供，不用本地账号名称补造。
@override final  String? title;
@override final  String version;

/// Create a copy of AcpServerInfo
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpServerInfoCopyWith<_AcpServerInfo> get copyWith => __$AcpServerInfoCopyWithImpl<_AcpServerInfo>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpServerInfo&&(identical(other.name, name) || other.name == name)&&(identical(other.title, title) || other.title == title)&&(identical(other.version, version) || other.version == version));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,title,version);
}



}

/// @nodoc
abstract mixin class _$AcpServerInfoCopyWith<$Res> implements $AcpServerInfoCopyWith<$Res> {
  factory _$AcpServerInfoCopyWith(_AcpServerInfo value, $Res Function(_AcpServerInfo) _then) = __$AcpServerInfoCopyWithImpl;
@override @useResult
$Res call({
 String name, String? title, String version
});




}
/// @nodoc
class __$AcpServerInfoCopyWithImpl<$Res>
    implements _$AcpServerInfoCopyWith<$Res> {
  __$AcpServerInfoCopyWithImpl(this._self, this._then);

  final _AcpServerInfo _self;
  final $Res Function(_AcpServerInfo) _then;

/// Create a copy of AcpServerInfo
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? title = freezed,Object? version = null,}) {
  return _then(_AcpServerInfo(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AcpAuthFailure {

 AcpAuthFailureCode get code; AcpAuthStage get stage; String get message; bool get retryable;
/// Create a copy of AcpAuthFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthFailureCopyWith<AcpAuthFailure> get copyWith => _$AcpAuthFailureCopyWithImpl<AcpAuthFailure>(this as AcpAuthFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable));
}


@override
int get hashCode {
  final _this = this as AcpAuthFailure;
  return Object.hash(runtimeType,_this.code,_this.stage,_this.message,_this.retryable);
}

@override
String toString() {
  final _this = this as AcpAuthFailure;
  return 'AcpAuthFailure(code: ${_this.code}, stage: ${_this.stage}, message: ${_this.message}, retryable: ${_this.retryable})';
}


}

/// @nodoc
abstract mixin class $AcpAuthFailureCopyWith<$Res>  {
  factory $AcpAuthFailureCopyWith(AcpAuthFailure value, $Res Function(AcpAuthFailure) _then) = _$AcpAuthFailureCopyWithImpl;
@useResult
$Res call({
 AcpAuthFailureCode code, AcpAuthStage stage, String message, bool retryable
});




}
/// @nodoc
class _$AcpAuthFailureCopyWithImpl<$Res>
    implements $AcpAuthFailureCopyWith<$Res> {
  _$AcpAuthFailureCopyWithImpl(this._self, this._then);

  final AcpAuthFailure _self;
  final $Res Function(AcpAuthFailure) _then;

/// Create a copy of AcpAuthFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? stage = null,Object? message = null,Object? retryable = null,}) {
  return _then(AcpAuthFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as AcpAuthFailureCode,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AcpAuthStage,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpAuthFailure].
extension AcpAuthFailurePatterns on AcpAuthFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpAuthFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpAuthFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpAuthFailure value)  $default,){
final _that = this;
switch (_that) {
case _AcpAuthFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpAuthFailure value)?  $default,){
final _that = this;
switch (_that) {
case _AcpAuthFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpAuthFailureCode code,  AcpAuthStage stage,  String message,  bool retryable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpAuthFailure() when $default != null:
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpAuthFailureCode code,  AcpAuthStage stage,  String message,  bool retryable)  $default,) {final _that = this;
switch (_that) {
case _AcpAuthFailure():
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpAuthFailureCode code,  AcpAuthStage stage,  String message,  bool retryable)?  $default,) {final _that = this;
switch (_that) {
case _AcpAuthFailure() when $default != null:
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class _AcpAuthFailure implements AcpAuthFailure {
  const _AcpAuthFailure({required this.code, required this.stage, required this.message, required this.retryable});


@override final  AcpAuthFailureCode code;
@override final  AcpAuthStage stage;
@override final  String message;
@override final  bool retryable;

/// Create a copy of AcpAuthFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpAuthFailureCopyWith<_AcpAuthFailure> get copyWith => __$AcpAuthFailureCopyWithImpl<_AcpAuthFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpAuthFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,stage,message,retryable);
}

@override
String toString() {
    return 'AcpAuthFailure(code: $code, stage: $stage, message: $message, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class _$AcpAuthFailureCopyWith<$Res> implements $AcpAuthFailureCopyWith<$Res> {
  factory _$AcpAuthFailureCopyWith(_AcpAuthFailure value, $Res Function(_AcpAuthFailure) _then) = __$AcpAuthFailureCopyWithImpl;
@override @useResult
$Res call({
 AcpAuthFailureCode code, AcpAuthStage stage, String message, bool retryable
});




}
/// @nodoc
class __$AcpAuthFailureCopyWithImpl<$Res>
    implements _$AcpAuthFailureCopyWith<$Res> {
  __$AcpAuthFailureCopyWithImpl(this._self, this._then);

  final _AcpAuthFailure _self;
  final $Res Function(_AcpAuthFailure) _then;

/// Create a copy of AcpAuthFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? stage = null,Object? message = null,Object? retryable = null,}) {
  return _then(_AcpAuthFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as AcpAuthFailureCode,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AcpAuthStage,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$AcpAuthAction {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthAction);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AcpAuthActionCopyWith<$Res>  {
$AcpAuthActionCopyWith(AcpAuthAction _, $Res Function(AcpAuthAction) __);
}


/// Adds pattern-matching-related methods to [AcpAuthAction].
extension AcpAuthActionPatterns on AcpAuthAction {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpAuthCheck value)?  check,TResult Function( AcpAuthAuthenticate value)?  authenticate,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpAuthCheck() when check != null:
return check(_that);case AcpAuthAuthenticate() when authenticate != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpAuthCheck value)  check,required TResult Function( AcpAuthAuthenticate value)  authenticate,}){
final _that = this;
switch (_that) {
case AcpAuthCheck():
return check(_that);case AcpAuthAuthenticate():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpAuthCheck value)?  check,TResult? Function( AcpAuthAuthenticate value)?  authenticate,}){
final _that = this;
switch (_that) {
case AcpAuthCheck() when check != null:
return check(_that);case AcpAuthAuthenticate() when authenticate != null:
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
case AcpAuthCheck() when check != null:
return check();case AcpAuthAuthenticate() when authenticate != null:
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
case AcpAuthCheck():
return check();case AcpAuthAuthenticate():
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
case AcpAuthCheck() when check != null:
return check();case AcpAuthAuthenticate() when authenticate != null:
return authenticate(_that.methodId);case _:
  return null;

}
}

}

/// @nodoc


class AcpAuthCheck implements AcpAuthAction {
  const AcpAuthCheck();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthCheck);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AcpAuthAuthenticate implements AcpAuthAction {
  const AcpAuthAuthenticate({required this.methodId});


 final  String methodId;

/// Create a copy of AcpAuthAction
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthAuthenticateCopyWith<AcpAuthAuthenticate> get copyWith => _$AcpAuthAuthenticateCopyWithImpl<AcpAuthAuthenticate>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthAuthenticate&&(identical(other.methodId, methodId) || other.methodId == methodId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,methodId);
}



}

/// @nodoc
abstract mixin class $AcpAuthAuthenticateCopyWith<$Res> implements $AcpAuthActionCopyWith<$Res> {
  factory $AcpAuthAuthenticateCopyWith(AcpAuthAuthenticate value, $Res Function(AcpAuthAuthenticate) _then) = _$AcpAuthAuthenticateCopyWithImpl;
@useResult
$Res call({
 String methodId
});




}
/// @nodoc
class _$AcpAuthAuthenticateCopyWithImpl<$Res>
    implements $AcpAuthAuthenticateCopyWith<$Res> {
  _$AcpAuthAuthenticateCopyWithImpl(this._self, this._then);

  final AcpAuthAuthenticate _self;
  final $Res Function(AcpAuthAuthenticate) _then;

/// Create a copy of AcpAuthAction
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? methodId = null,}) {
  return _then(AcpAuthAuthenticate(
methodId: null == methodId ? _self.methodId : methodId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$AcpInstallAvailability {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallAvailability);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AcpInstallAvailabilityCopyWith<$Res>  {
$AcpInstallAvailabilityCopyWith(AcpInstallAvailability _, $Res Function(AcpInstallAvailability) __);
}


/// Adds pattern-matching-related methods to [AcpInstallAvailability].
extension AcpInstallAvailabilityPatterns on AcpInstallAvailability {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpInstallAvailable value)?  available,TResult Function( AcpInstallUnsupportedPlatform value)?  unsupportedPlatform,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpInstallAvailable() when available != null:
return available(_that);case AcpInstallUnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpInstallAvailable value)  available,required TResult Function( AcpInstallUnsupportedPlatform value)  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case AcpInstallAvailable():
return available(_that);case AcpInstallUnsupportedPlatform():
return unsupportedPlatform(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpInstallAvailable value)?  available,TResult? Function( AcpInstallUnsupportedPlatform value)?  unsupportedPlatform,}){
final _that = this;
switch (_that) {
case AcpInstallAvailable() when available != null:
return available(_that);case AcpInstallUnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String target)?  available,TResult Function()?  unsupportedPlatform,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpInstallAvailable() when available != null:
return available(_that.target);case AcpInstallUnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String target)  available,required TResult Function()  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case AcpInstallAvailable():
return available(_that.target);case AcpInstallUnsupportedPlatform():
return unsupportedPlatform();}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String target)?  available,TResult? Function()?  unsupportedPlatform,}) {final _that = this;
switch (_that) {
case AcpInstallAvailable() when available != null:
return available(_that.target);case AcpInstallUnsupportedPlatform() when unsupportedPlatform != null:
return unsupportedPlatform();case _:
  return null;

}
}

}

/// @nodoc


class AcpInstallAvailable extends AcpInstallAvailability {
  const AcpInstallAvailable({required this.target}): super._();


 final  String target;

/// Create a copy of AcpInstallAvailability
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallAvailableCopyWith<AcpInstallAvailable> get copyWith => _$AcpInstallAvailableCopyWithImpl<AcpInstallAvailable>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallAvailable&&(identical(other.target, target) || other.target == target));
}


@override
int get hashCode {
    return Object.hash(runtimeType,target);
}



}

/// @nodoc
abstract mixin class $AcpInstallAvailableCopyWith<$Res> implements $AcpInstallAvailabilityCopyWith<$Res> {
  factory $AcpInstallAvailableCopyWith(AcpInstallAvailable value, $Res Function(AcpInstallAvailable) _then) = _$AcpInstallAvailableCopyWithImpl;
@useResult
$Res call({
 String target
});




}
/// @nodoc
class _$AcpInstallAvailableCopyWithImpl<$Res>
    implements $AcpInstallAvailableCopyWith<$Res> {
  _$AcpInstallAvailableCopyWithImpl(this._self, this._then);

  final AcpInstallAvailable _self;
  final $Res Function(AcpInstallAvailable) _then;

/// Create a copy of AcpInstallAvailability
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? target = null,}) {
  return _then(AcpInstallAvailable(
target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class AcpInstallUnsupportedPlatform extends AcpInstallAvailability {
  const AcpInstallUnsupportedPlatform(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallUnsupportedPlatform);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc
mixin _$AcpInstallRelease {

 String get version; String get target; String get archiveUrl;/// 发行方摘要；缺失时必须把信任边界表述为“官方 HTTPS 来源”，不能称作已签名。
 String? get sha256;
/// Create a copy of AcpInstallRelease
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallReleaseCopyWith<AcpInstallRelease> get copyWith => _$AcpInstallReleaseCopyWithImpl<AcpInstallRelease>(this as AcpInstallRelease, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallRelease;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallRelease&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.target, _this.target) || other.target == _this.target)&&(identical(other.archiveUrl, _this.archiveUrl) || other.archiveUrl == _this.archiveUrl)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256));
}


@override
int get hashCode {
  final _this = this as AcpInstallRelease;
  return Object.hash(runtimeType,_this.version,_this.target,_this.archiveUrl,_this.sha256);
}



}

/// @nodoc
abstract mixin class $AcpInstallReleaseCopyWith<$Res>  {
  factory $AcpInstallReleaseCopyWith(AcpInstallRelease value, $Res Function(AcpInstallRelease) _then) = _$AcpInstallReleaseCopyWithImpl;
@useResult
$Res call({
 String version, String target, String archiveUrl, String? sha256
});




}
/// @nodoc
class _$AcpInstallReleaseCopyWithImpl<$Res>
    implements $AcpInstallReleaseCopyWith<$Res> {
  _$AcpInstallReleaseCopyWithImpl(this._self, this._then);

  final AcpInstallRelease _self;
  final $Res Function(AcpInstallRelease) _then;

/// Create a copy of AcpInstallRelease
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? target = null,Object? archiveUrl = null,Object? sha256 = freezed,}) {
  return _then(AcpInstallRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,archiveUrl: null == archiveUrl ? _self.archiveUrl : archiveUrl // ignore: cast_nullable_to_non_nullable
as String,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpInstallRelease].
extension AcpInstallReleasePatterns on AcpInstallRelease {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallRelease value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallRelease() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallRelease value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallRelease():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallRelease value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallRelease() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String version,  String target,  String archiveUrl,  String? sha256)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallRelease() when $default != null:
return $default(_that.version,_that.target,_that.archiveUrl,_that.sha256);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String version,  String target,  String archiveUrl,  String? sha256)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallRelease():
return $default(_that.version,_that.target,_that.archiveUrl,_that.sha256);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String version,  String target,  String archiveUrl,  String? sha256)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallRelease() when $default != null:
return $default(_that.version,_that.target,_that.archiveUrl,_that.sha256);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallRelease extends AcpInstallRelease {
  const _AcpInstallRelease({required this.version, required this.target, required this.archiveUrl, required this.sha256}): super._();


@override final  String version;
@override final  String target;
@override final  String archiveUrl;
/// 发行方摘要；缺失时必须把信任边界表述为“官方 HTTPS 来源”，不能称作已签名。
@override final  String? sha256;

/// Create a copy of AcpInstallRelease
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallReleaseCopyWith<_AcpInstallRelease> get copyWith => __$AcpInstallReleaseCopyWithImpl<_AcpInstallRelease>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallRelease&&(identical(other.version, version) || other.version == version)&&(identical(other.target, target) || other.target == target)&&(identical(other.archiveUrl, archiveUrl) || other.archiveUrl == archiveUrl)&&(identical(other.sha256, sha256) || other.sha256 == sha256));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version,target,archiveUrl,sha256);
}



}

/// @nodoc
abstract mixin class _$AcpInstallReleaseCopyWith<$Res> implements $AcpInstallReleaseCopyWith<$Res> {
  factory _$AcpInstallReleaseCopyWith(_AcpInstallRelease value, $Res Function(_AcpInstallRelease) _then) = __$AcpInstallReleaseCopyWithImpl;
@override @useResult
$Res call({
 String version, String target, String archiveUrl, String? sha256
});




}
/// @nodoc
class __$AcpInstallReleaseCopyWithImpl<$Res>
    implements _$AcpInstallReleaseCopyWith<$Res> {
  __$AcpInstallReleaseCopyWithImpl(this._self, this._then);

  final _AcpInstallRelease _self;
  final $Res Function(_AcpInstallRelease) _then;

/// Create a copy of AcpInstallRelease
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? target = null,Object? archiveUrl = null,Object? sha256 = freezed,}) {
  return _then(_AcpInstallRelease(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as String,target: null == target ? _self.target : target // ignore: cast_nullable_to_non_nullable
as String,archiveUrl: null == archiveUrl ? _self.archiveUrl : archiveUrl // ignore: cast_nullable_to_non_nullable
as String,sha256: freezed == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$AcpInstallProgress {

 int get completedBytes; int? get totalBytes; int? get bytesPerSecond;
/// Create a copy of AcpInstallProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallProgressCopyWith<AcpInstallProgress> get copyWith => _$AcpInstallProgressCopyWithImpl<AcpInstallProgress>(this as AcpInstallProgress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallProgress&&(identical(other.completedBytes, _this.completedBytes) || other.completedBytes == _this.completedBytes)&&(identical(other.totalBytes, _this.totalBytes) || other.totalBytes == _this.totalBytes)&&(identical(other.bytesPerSecond, _this.bytesPerSecond) || other.bytesPerSecond == _this.bytesPerSecond));
}


@override
int get hashCode {
  final _this = this as AcpInstallProgress;
  return Object.hash(runtimeType,_this.completedBytes,_this.totalBytes,_this.bytesPerSecond);
}



}

/// @nodoc
abstract mixin class $AcpInstallProgressCopyWith<$Res>  {
  factory $AcpInstallProgressCopyWith(AcpInstallProgress value, $Res Function(AcpInstallProgress) _then) = _$AcpInstallProgressCopyWithImpl;
@useResult
$Res call({
 int completedBytes, int? totalBytes, int? bytesPerSecond
});




}
/// @nodoc
class _$AcpInstallProgressCopyWithImpl<$Res>
    implements $AcpInstallProgressCopyWith<$Res> {
  _$AcpInstallProgressCopyWithImpl(this._self, this._then);

  final AcpInstallProgress _self;
  final $Res Function(AcpInstallProgress) _then;

/// Create a copy of AcpInstallProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? completedBytes = null,Object? totalBytes = freezed,Object? bytesPerSecond = freezed,}) {
  return _then(AcpInstallProgress(
completedBytes: null == completedBytes ? _self.completedBytes : completedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,bytesPerSecond: freezed == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpInstallProgress].
extension AcpInstallProgressPatterns on AcpInstallProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallProgress value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallProgress value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int completedBytes,  int? totalBytes,  int? bytesPerSecond)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallProgress() when $default != null:
return $default(_that.completedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int completedBytes,  int? totalBytes,  int? bytesPerSecond)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallProgress():
return $default(_that.completedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int completedBytes,  int? totalBytes,  int? bytesPerSecond)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallProgress() when $default != null:
return $default(_that.completedBytes,_that.totalBytes,_that.bytesPerSecond);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallProgress extends AcpInstallProgress {
  const _AcpInstallProgress({required this.completedBytes, required this.totalBytes, required this.bytesPerSecond}): super._();


@override final  int completedBytes;
@override final  int? totalBytes;
@override final  int? bytesPerSecond;

/// Create a copy of AcpInstallProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallProgressCopyWith<_AcpInstallProgress> get copyWith => __$AcpInstallProgressCopyWithImpl<_AcpInstallProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallProgress&&(identical(other.completedBytes, completedBytes) || other.completedBytes == completedBytes)&&(identical(other.totalBytes, totalBytes) || other.totalBytes == totalBytes)&&(identical(other.bytesPerSecond, bytesPerSecond) || other.bytesPerSecond == bytesPerSecond));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedBytes,totalBytes,bytesPerSecond);
}



}

/// @nodoc
abstract mixin class _$AcpInstallProgressCopyWith<$Res> implements $AcpInstallProgressCopyWith<$Res> {
  factory _$AcpInstallProgressCopyWith(_AcpInstallProgress value, $Res Function(_AcpInstallProgress) _then) = __$AcpInstallProgressCopyWithImpl;
@override @useResult
$Res call({
 int completedBytes, int? totalBytes, int? bytesPerSecond
});




}
/// @nodoc
class __$AcpInstallProgressCopyWithImpl<$Res>
    implements _$AcpInstallProgressCopyWith<$Res> {
  __$AcpInstallProgressCopyWithImpl(this._self, this._then);

  final _AcpInstallProgress _self;
  final $Res Function(_AcpInstallProgress) _then;

/// Create a copy of AcpInstallProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? completedBytes = null,Object? totalBytes = freezed,Object? bytesPerSecond = freezed,}) {
  return _then(_AcpInstallProgress(
completedBytes: null == completedBytes ? _self.completedBytes : completedBytes // ignore: cast_nullable_to_non_nullable
as int,totalBytes: freezed == totalBytes ? _self.totalBytes : totalBytes // ignore: cast_nullable_to_non_nullable
as int?,bytesPerSecond: freezed == bytesPerSecond ? _self.bytesPerSecond : bytesPerSecond // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$AcpInstalledServer {

 String get installationId; AcpInstallRelease get release; String get program;/// 准备完成时间（Unix 秒）；只是历史事实。
 int get readyAt;/// 本次操作复用了既有完整安装，而不是重新下载。
 bool get reused;
/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstalledServerCopyWith<AcpInstalledServer> get copyWith => _$AcpInstalledServerCopyWithImpl<AcpInstalledServer>(this as AcpInstalledServer, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstalledServer;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstalledServer&&(identical(other.installationId, _this.installationId) || other.installationId == _this.installationId)&&(identical(other.release, _this.release) || other.release == _this.release)&&(identical(other.program, _this.program) || other.program == _this.program)&&(identical(other.readyAt, _this.readyAt) || other.readyAt == _this.readyAt)&&(identical(other.reused, _this.reused) || other.reused == _this.reused));
}


@override
int get hashCode {
  final _this = this as AcpInstalledServer;
  return Object.hash(runtimeType,_this.installationId,_this.release,_this.program,_this.readyAt,_this.reused);
}

@override
String toString() {
  final _this = this as AcpInstalledServer;
  return 'AcpInstalledServer(installationId: ${_this.installationId}, release: ${_this.release}, program: ${_this.program}, readyAt: ${_this.readyAt}, reused: ${_this.reused})';
}


}

/// @nodoc
abstract mixin class $AcpInstalledServerCopyWith<$Res>  {
  factory $AcpInstalledServerCopyWith(AcpInstalledServer value, $Res Function(AcpInstalledServer) _then) = _$AcpInstalledServerCopyWithImpl;
@useResult
$Res call({
 String installationId, AcpInstallRelease release, String program, int readyAt, bool reused
});


$AcpInstallReleaseCopyWith<$Res> get release;

}
/// @nodoc
class _$AcpInstalledServerCopyWithImpl<$Res>
    implements $AcpInstalledServerCopyWith<$Res> {
  _$AcpInstalledServerCopyWithImpl(this._self, this._then);

  final AcpInstalledServer _self;
  final $Res Function(AcpInstalledServer) _then;

/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? installationId = null,Object? release = null,Object? program = null,Object? readyAt = null,Object? reused = null,}) {
  return _then(AcpInstalledServer(
installationId: null == installationId ? _self.installationId : installationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as AcpInstallRelease,program: null == program ? _self.program : program // ignore: cast_nullable_to_non_nullable
as String,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,reused: null == reused ? _self.reused : reused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallReleaseCopyWith<$Res> get release {

  return $AcpInstallReleaseCopyWith<$Res>(_self.release, (value) {
    return _then(_self.copyWith(release: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpInstalledServer].
extension AcpInstalledServerPatterns on AcpInstalledServer {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstalledServer value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstalledServer() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstalledServer value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstalledServer():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstalledServer value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstalledServer() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String installationId,  AcpInstallRelease release,  String program,  int readyAt,  bool reused)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstalledServer() when $default != null:
return $default(_that.installationId,_that.release,_that.program,_that.readyAt,_that.reused);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String installationId,  AcpInstallRelease release,  String program,  int readyAt,  bool reused)  $default,) {final _that = this;
switch (_that) {
case _AcpInstalledServer():
return $default(_that.installationId,_that.release,_that.program,_that.readyAt,_that.reused);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String installationId,  AcpInstallRelease release,  String program,  int readyAt,  bool reused)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstalledServer() when $default != null:
return $default(_that.installationId,_that.release,_that.program,_that.readyAt,_that.reused);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstalledServer implements AcpInstalledServer {
  const _AcpInstalledServer({required this.installationId, required this.release, required this.program, required this.readyAt, required this.reused});


@override final  String installationId;
@override final  AcpInstallRelease release;
@override final  String program;
/// 准备完成时间（Unix 秒）；只是历史事实。
@override final  int readyAt;
/// 本次操作复用了既有完整安装，而不是重新下载。
@override final  bool reused;

/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstalledServerCopyWith<_AcpInstalledServer> get copyWith => __$AcpInstalledServerCopyWithImpl<_AcpInstalledServer>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstalledServer&&(identical(other.installationId, installationId) || other.installationId == installationId)&&(identical(other.release, release) || other.release == release)&&(identical(other.program, program) || other.program == program)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt)&&(identical(other.reused, reused) || other.reused == reused));
}


@override
int get hashCode {
    return Object.hash(runtimeType,installationId,release,program,readyAt,reused);
}

@override
String toString() {
    return 'AcpInstalledServer(installationId: $installationId, release: $release, program: $program, readyAt: $readyAt, reused: $reused)';
}


}

/// @nodoc
abstract mixin class _$AcpInstalledServerCopyWith<$Res> implements $AcpInstalledServerCopyWith<$Res> {
  factory _$AcpInstalledServerCopyWith(_AcpInstalledServer value, $Res Function(_AcpInstalledServer) _then) = __$AcpInstalledServerCopyWithImpl;
@override @useResult
$Res call({
 String installationId, AcpInstallRelease release, String program, int readyAt, bool reused
});


@override $AcpInstallReleaseCopyWith<$Res> get release;

}
/// @nodoc
class __$AcpInstalledServerCopyWithImpl<$Res>
    implements _$AcpInstalledServerCopyWith<$Res> {
  __$AcpInstalledServerCopyWithImpl(this._self, this._then);

  final _AcpInstalledServer _self;
  final $Res Function(_AcpInstalledServer) _then;

/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? installationId = null,Object? release = null,Object? program = null,Object? readyAt = null,Object? reused = null,}) {
  return _then(_AcpInstalledServer(
installationId: null == installationId ? _self.installationId : installationId // ignore: cast_nullable_to_non_nullable
as String,release: null == release ? _self.release : release // ignore: cast_nullable_to_non_nullable
as AcpInstallRelease,program: null == program ? _self.program : program // ignore: cast_nullable_to_non_nullable
as String,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,reused: null == reused ? _self.reused : reused // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of AcpInstalledServer
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallReleaseCopyWith<$Res> get release {

  return $AcpInstallReleaseCopyWith<$Res>(_self.release, (value) {
    return _then(_self.copyWith(release: value));
  });
}
}

/// @nodoc
mixin _$AcpInstallFailure {

 AcpInstallFailureCode get code; AcpInstallStage get stage; String get message; bool get retryable;
/// Create a copy of AcpInstallFailure
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallFailureCopyWith<AcpInstallFailure> get copyWith => _$AcpInstallFailureCopyWithImpl<AcpInstallFailure>(this as AcpInstallFailure, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallFailure;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallFailure&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable));
}


@override
int get hashCode {
  final _this = this as AcpInstallFailure;
  return Object.hash(runtimeType,_this.code,_this.stage,_this.message,_this.retryable);
}

@override
String toString() {
  final _this = this as AcpInstallFailure;
  return 'AcpInstallFailure(code: ${_this.code}, stage: ${_this.stage}, message: ${_this.message}, retryable: ${_this.retryable})';
}


}

/// @nodoc
abstract mixin class $AcpInstallFailureCopyWith<$Res>  {
  factory $AcpInstallFailureCopyWith(AcpInstallFailure value, $Res Function(AcpInstallFailure) _then) = _$AcpInstallFailureCopyWithImpl;
@useResult
$Res call({
 AcpInstallFailureCode code, AcpInstallStage stage, String message, bool retryable
});




}
/// @nodoc
class _$AcpInstallFailureCopyWithImpl<$Res>
    implements $AcpInstallFailureCopyWith<$Res> {
  _$AcpInstallFailureCopyWithImpl(this._self, this._then);

  final AcpInstallFailure _self;
  final $Res Function(AcpInstallFailure) _then;

/// Create a copy of AcpInstallFailure
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? stage = null,Object? message = null,Object? retryable = null,}) {
  return _then(AcpInstallFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as AcpInstallFailureCode,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AcpInstallStage,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [AcpInstallFailure].
extension AcpInstallFailurePatterns on AcpInstallFailure {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AcpInstallFailure value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AcpInstallFailure() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AcpInstallFailure value)  $default,){
final _that = this;
switch (_that) {
case _AcpInstallFailure():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AcpInstallFailure value)?  $default,){
final _that = this;
switch (_that) {
case _AcpInstallFailure() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AcpInstallFailureCode code,  AcpInstallStage stage,  String message,  bool retryable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AcpInstallFailure() when $default != null:
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AcpInstallFailureCode code,  AcpInstallStage stage,  String message,  bool retryable)  $default,) {final _that = this;
switch (_that) {
case _AcpInstallFailure():
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AcpInstallFailureCode code,  AcpInstallStage stage,  String message,  bool retryable)?  $default,) {final _that = this;
switch (_that) {
case _AcpInstallFailure() when $default != null:
return $default(_that.code,_that.stage,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class _AcpInstallFailure implements AcpInstallFailure {
  const _AcpInstallFailure({required this.code, required this.stage, required this.message, required this.retryable});


@override final  AcpInstallFailureCode code;
@override final  AcpInstallStage stage;
@override final  String message;
@override final  bool retryable;

/// Create a copy of AcpInstallFailure
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AcpInstallFailureCopyWith<_AcpInstallFailure> get copyWith => __$AcpInstallFailureCopyWithImpl<_AcpInstallFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AcpInstallFailure&&(identical(other.code, code) || other.code == code)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,stage,message,retryable);
}

@override
String toString() {
    return 'AcpInstallFailure(code: $code, stage: $stage, message: $message, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class _$AcpInstallFailureCopyWith<$Res> implements $AcpInstallFailureCopyWith<$Res> {
  factory _$AcpInstallFailureCopyWith(_AcpInstallFailure value, $Res Function(_AcpInstallFailure) _then) = __$AcpInstallFailureCopyWithImpl;
@override @useResult
$Res call({
 AcpInstallFailureCode code, AcpInstallStage stage, String message, bool retryable
});




}
/// @nodoc
class __$AcpInstallFailureCopyWithImpl<$Res>
    implements _$AcpInstallFailureCopyWith<$Res> {
  __$AcpInstallFailureCopyWithImpl(this._self, this._then);

  final _AcpInstallFailure _self;
  final $Res Function(_AcpInstallFailure) _then;

/// Create a copy of AcpInstallFailure
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? stage = null,Object? message = null,Object? retryable = null,}) {
  return _then(_AcpInstallFailure(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as AcpInstallFailureCode,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as AcpInstallStage,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

// dart format on
