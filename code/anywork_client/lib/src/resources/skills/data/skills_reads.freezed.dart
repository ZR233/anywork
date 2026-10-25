// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SkillCatalogRead {

 ReadText get projectDir; TypedListRef get skills; TypedListRef get warnings; bool get complete;
/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillCatalogReadCopyWith<SkillCatalogRead> get copyWith => _$SkillCatalogReadCopyWithImpl<SkillCatalogRead>(this as SkillCatalogRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillCatalogRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillCatalogRead&&(identical(other.projectDir, _this.projectDir) || other.projectDir == _this.projectDir)&&(identical(other.skills, _this.skills) || other.skills == _this.skills)&&(identical(other.warnings, _this.warnings) || other.warnings == _this.warnings)&&(identical(other.complete, _this.complete) || other.complete == _this.complete));
}


@override
int get hashCode {
  final _this = this as SkillCatalogRead;
  return Object.hash(runtimeType,_this.projectDir,_this.skills,_this.warnings,_this.complete);
}



}

/// @nodoc
abstract mixin class $SkillCatalogReadCopyWith<$Res>  {
  factory $SkillCatalogReadCopyWith(SkillCatalogRead value, $Res Function(SkillCatalogRead) _then) = _$SkillCatalogReadCopyWithImpl;
@useResult
$Res call({
 ReadText projectDir, TypedListRef skills, TypedListRef warnings, bool complete
});


$ReadTextCopyWith<$Res> get projectDir;$TypedListRefCopyWith<$Res> get skills;$TypedListRefCopyWith<$Res> get warnings;

}
/// @nodoc
class _$SkillCatalogReadCopyWithImpl<$Res>
    implements $SkillCatalogReadCopyWith<$Res> {
  _$SkillCatalogReadCopyWithImpl(this._self, this._then);

  final SkillCatalogRead _self;
  final $Res Function(SkillCatalogRead) _then;

/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectDir = null,Object? skills = null,Object? warnings = null,Object? complete = null,}) {
  return _then(SkillCatalogRead(
projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as ReadText,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as TypedListRef,warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as TypedListRef,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectDir {

  return $ReadTextCopyWith<$Res>(_self.projectDir, (value) {
    return _then(_self.copyWith(projectDir: value));
  });
}/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get skills {

  return $TypedListRefCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get warnings {

  return $TypedListRefCopyWith<$Res>(_self.warnings, (value) {
    return _then(_self.copyWith(warnings: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillCatalogRead].
extension SkillCatalogReadPatterns on SkillCatalogRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillCatalogRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillCatalogRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillCatalogRead value)  $default,){
final _that = this;
switch (_that) {
case _SkillCatalogRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillCatalogRead value)?  $default,){
final _that = this;
switch (_that) {
case _SkillCatalogRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText projectDir,  TypedListRef skills,  TypedListRef warnings,  bool complete)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillCatalogRead() when $default != null:
return $default(_that.projectDir,_that.skills,_that.warnings,_that.complete);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText projectDir,  TypedListRef skills,  TypedListRef warnings,  bool complete)  $default,) {final _that = this;
switch (_that) {
case _SkillCatalogRead():
return $default(_that.projectDir,_that.skills,_that.warnings,_that.complete);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText projectDir,  TypedListRef skills,  TypedListRef warnings,  bool complete)?  $default,) {final _that = this;
switch (_that) {
case _SkillCatalogRead() when $default != null:
return $default(_that.projectDir,_that.skills,_that.warnings,_that.complete);case _:
  return null;

}
}

}

/// @nodoc


class _SkillCatalogRead implements SkillCatalogRead {
  const _SkillCatalogRead({required this.projectDir, required this.skills, required this.warnings, required this.complete});


@override final  ReadText projectDir;
@override final  TypedListRef skills;
@override final  TypedListRef warnings;
@override final  bool complete;

/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillCatalogReadCopyWith<_SkillCatalogRead> get copyWith => __$SkillCatalogReadCopyWithImpl<_SkillCatalogRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillCatalogRead&&(identical(other.projectDir, projectDir) || other.projectDir == projectDir)&&(identical(other.skills, skills) || other.skills == skills)&&(identical(other.warnings, warnings) || other.warnings == warnings)&&(identical(other.complete, complete) || other.complete == complete));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectDir,skills,warnings,complete);
}



}

/// @nodoc
abstract mixin class _$SkillCatalogReadCopyWith<$Res> implements $SkillCatalogReadCopyWith<$Res> {
  factory _$SkillCatalogReadCopyWith(_SkillCatalogRead value, $Res Function(_SkillCatalogRead) _then) = __$SkillCatalogReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText projectDir, TypedListRef skills, TypedListRef warnings, bool complete
});


@override $ReadTextCopyWith<$Res> get projectDir;@override $TypedListRefCopyWith<$Res> get skills;@override $TypedListRefCopyWith<$Res> get warnings;

}
/// @nodoc
class __$SkillCatalogReadCopyWithImpl<$Res>
    implements _$SkillCatalogReadCopyWith<$Res> {
  __$SkillCatalogReadCopyWithImpl(this._self, this._then);

  final _SkillCatalogRead _self;
  final $Res Function(_SkillCatalogRead) _then;

/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectDir = null,Object? skills = null,Object? warnings = null,Object? complete = null,}) {
  return _then(_SkillCatalogRead(
projectDir: null == projectDir ? _self.projectDir : projectDir // ignore: cast_nullable_to_non_nullable
as ReadText,skills: null == skills ? _self.skills : skills // ignore: cast_nullable_to_non_nullable
as TypedListRef,warnings: null == warnings ? _self.warnings : warnings // ignore: cast_nullable_to_non_nullable
as TypedListRef,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectDir {

  return $ReadTextCopyWith<$Res>(_self.projectDir, (value) {
    return _then(_self.copyWith(projectDir: value));
  });
}/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get skills {

  return $TypedListRefCopyWith<$Res>(_self.skills, (value) {
    return _then(_self.copyWith(skills: value));
  });
}/// Create a copy of SkillCatalogRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get warnings {

  return $TypedListRefCopyWith<$Res>(_self.warnings, (value) {
    return _then(_self.copyWith(warnings: value));
  });
}
}

/// @nodoc
mixin _$SkillsReadHeader {

 ReadText get projectId; ReadText get configFingerprint; int get catalogRevision; SkillCatalogRead get catalog;
/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsReadHeaderCopyWith<SkillsReadHeader> get copyWith => _$SkillsReadHeaderCopyWithImpl<SkillsReadHeader>(this as SkillsReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsReadHeader&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.configFingerprint, _this.configFingerprint) || other.configFingerprint == _this.configFingerprint)&&(identical(other.catalogRevision, _this.catalogRevision) || other.catalogRevision == _this.catalogRevision)&&(identical(other.catalog, _this.catalog) || other.catalog == _this.catalog));
}


@override
int get hashCode {
  final _this = this as SkillsReadHeader;
  return Object.hash(runtimeType,_this.projectId,_this.configFingerprint,_this.catalogRevision,_this.catalog);
}



}

/// @nodoc
abstract mixin class $SkillsReadHeaderCopyWith<$Res>  {
  factory $SkillsReadHeaderCopyWith(SkillsReadHeader value, $Res Function(SkillsReadHeader) _then) = _$SkillsReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadText projectId, ReadText configFingerprint, int catalogRevision, SkillCatalogRead catalog
});


$ReadTextCopyWith<$Res> get projectId;$ReadTextCopyWith<$Res> get configFingerprint;$SkillCatalogReadCopyWith<$Res> get catalog;

}
/// @nodoc
class _$SkillsReadHeaderCopyWithImpl<$Res>
    implements $SkillsReadHeaderCopyWith<$Res> {
  _$SkillsReadHeaderCopyWithImpl(this._self, this._then);

  final SkillsReadHeader _self;
  final $Res Function(SkillsReadHeader) _then;

/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? configFingerprint = null,Object? catalogRevision = null,Object? catalog = null,}) {
  return _then(SkillsReadHeader(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText,configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as SkillCatalogRead,
  ));
}
/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectId {

  return $ReadTextCopyWith<$Res>(_self.projectId, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configFingerprint {

  return $ReadTextCopyWith<$Res>(_self.configFingerprint, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillCatalogReadCopyWith<$Res> get catalog {

  return $SkillCatalogReadCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsReadHeader].
extension SkillsReadHeaderPatterns on SkillsReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _SkillsReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText projectId,  ReadText configFingerprint,  int catalogRevision,  SkillCatalogRead catalog)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsReadHeader() when $default != null:
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText projectId,  ReadText configFingerprint,  int catalogRevision,  SkillCatalogRead catalog)  $default,) {final _that = this;
switch (_that) {
case _SkillsReadHeader():
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText projectId,  ReadText configFingerprint,  int catalogRevision,  SkillCatalogRead catalog)?  $default,) {final _that = this;
switch (_that) {
case _SkillsReadHeader() when $default != null:
return $default(_that.projectId,_that.configFingerprint,_that.catalogRevision,_that.catalog);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsReadHeader implements SkillsReadHeader {
  const _SkillsReadHeader({required this.projectId, required this.configFingerprint, required this.catalogRevision, required this.catalog});


@override final  ReadText projectId;
@override final  ReadText configFingerprint;
@override final  int catalogRevision;
@override final  SkillCatalogRead catalog;

/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsReadHeaderCopyWith<_SkillsReadHeader> get copyWith => __$SkillsReadHeaderCopyWithImpl<_SkillsReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsReadHeader&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.configFingerprint, configFingerprint) || other.configFingerprint == configFingerprint)&&(identical(other.catalogRevision, catalogRevision) || other.catalogRevision == catalogRevision)&&(identical(other.catalog, catalog) || other.catalog == catalog));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,configFingerprint,catalogRevision,catalog);
}



}

/// @nodoc
abstract mixin class _$SkillsReadHeaderCopyWith<$Res> implements $SkillsReadHeaderCopyWith<$Res> {
  factory _$SkillsReadHeaderCopyWith(_SkillsReadHeader value, $Res Function(_SkillsReadHeader) _then) = __$SkillsReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadText projectId, ReadText configFingerprint, int catalogRevision, SkillCatalogRead catalog
});


@override $ReadTextCopyWith<$Res> get projectId;@override $ReadTextCopyWith<$Res> get configFingerprint;@override $SkillCatalogReadCopyWith<$Res> get catalog;

}
/// @nodoc
class __$SkillsReadHeaderCopyWithImpl<$Res>
    implements _$SkillsReadHeaderCopyWith<$Res> {
  __$SkillsReadHeaderCopyWithImpl(this._self, this._then);

  final _SkillsReadHeader _self;
  final $Res Function(_SkillsReadHeader) _then;

/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? configFingerprint = null,Object? catalogRevision = null,Object? catalog = null,}) {
  return _then(_SkillsReadHeader(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as ReadText,configFingerprint: null == configFingerprint ? _self.configFingerprint : configFingerprint // ignore: cast_nullable_to_non_nullable
as ReadText,catalogRevision: null == catalogRevision ? _self.catalogRevision : catalogRevision // ignore: cast_nullable_to_non_nullable
as int,catalog: null == catalog ? _self.catalog : catalog // ignore: cast_nullable_to_non_nullable
as SkillCatalogRead,
  ));
}

/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get projectId {

  return $ReadTextCopyWith<$Res>(_self.projectId, (value) {
    return _then(_self.copyWith(projectId: value));
  });
}/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get configFingerprint {

  return $ReadTextCopyWith<$Res>(_self.configFingerprint, (value) {
    return _then(_self.copyWith(configFingerprint: value));
  });
}/// Create a copy of SkillsReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillCatalogReadCopyWith<$Res> get catalog {

  return $SkillCatalogReadCopyWith<$Res>(_self.catalog, (value) {
    return _then(_self.copyWith(catalog: value));
  });
}
}

/// @nodoc
mixin _$SkillInvocationPolicyRead {

 bool get modelInvocable; bool get userInvocable;
/// Create a copy of SkillInvocationPolicyRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillInvocationPolicyReadCopyWith<SkillInvocationPolicyRead> get copyWith => _$SkillInvocationPolicyReadCopyWithImpl<SkillInvocationPolicyRead>(this as SkillInvocationPolicyRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillInvocationPolicyRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillInvocationPolicyRead&&(identical(other.modelInvocable, _this.modelInvocable) || other.modelInvocable == _this.modelInvocable)&&(identical(other.userInvocable, _this.userInvocable) || other.userInvocable == _this.userInvocable));
}


@override
int get hashCode {
  final _this = this as SkillInvocationPolicyRead;
  return Object.hash(runtimeType,_this.modelInvocable,_this.userInvocable);
}

@override
String toString() {
  final _this = this as SkillInvocationPolicyRead;
  return 'SkillInvocationPolicyRead(modelInvocable: ${_this.modelInvocable}, userInvocable: ${_this.userInvocable})';
}


}

/// @nodoc
abstract mixin class $SkillInvocationPolicyReadCopyWith<$Res>  {
  factory $SkillInvocationPolicyReadCopyWith(SkillInvocationPolicyRead value, $Res Function(SkillInvocationPolicyRead) _then) = _$SkillInvocationPolicyReadCopyWithImpl;
@useResult
$Res call({
 bool modelInvocable, bool userInvocable
});




}
/// @nodoc
class _$SkillInvocationPolicyReadCopyWithImpl<$Res>
    implements $SkillInvocationPolicyReadCopyWith<$Res> {
  _$SkillInvocationPolicyReadCopyWithImpl(this._self, this._then);

  final SkillInvocationPolicyRead _self;
  final $Res Function(SkillInvocationPolicyRead) _then;

/// Create a copy of SkillInvocationPolicyRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? modelInvocable = null,Object? userInvocable = null,}) {
  return _then(SkillInvocationPolicyRead(
modelInvocable: null == modelInvocable ? _self.modelInvocable : modelInvocable // ignore: cast_nullable_to_non_nullable
as bool,userInvocable: null == userInvocable ? _self.userInvocable : userInvocable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillInvocationPolicyRead].
extension SkillInvocationPolicyReadPatterns on SkillInvocationPolicyRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillInvocationPolicyRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillInvocationPolicyRead value)  $default,){
final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillInvocationPolicyRead value)?  $default,){
final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( bool modelInvocable,  bool userInvocable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead() when $default != null:
return $default(_that.modelInvocable,_that.userInvocable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( bool modelInvocable,  bool userInvocable)  $default,) {final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead():
return $default(_that.modelInvocable,_that.userInvocable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( bool modelInvocable,  bool userInvocable)?  $default,) {final _that = this;
switch (_that) {
case _SkillInvocationPolicyRead() when $default != null:
return $default(_that.modelInvocable,_that.userInvocable);case _:
  return null;

}
}

}

/// @nodoc


class _SkillInvocationPolicyRead implements SkillInvocationPolicyRead {
  const _SkillInvocationPolicyRead({required this.modelInvocable, required this.userInvocable});


@override final  bool modelInvocable;
@override final  bool userInvocable;

/// Create a copy of SkillInvocationPolicyRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillInvocationPolicyReadCopyWith<_SkillInvocationPolicyRead> get copyWith => __$SkillInvocationPolicyReadCopyWithImpl<_SkillInvocationPolicyRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillInvocationPolicyRead&&(identical(other.modelInvocable, modelInvocable) || other.modelInvocable == modelInvocable)&&(identical(other.userInvocable, userInvocable) || other.userInvocable == userInvocable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,modelInvocable,userInvocable);
}

@override
String toString() {
    return 'SkillInvocationPolicyRead(modelInvocable: $modelInvocable, userInvocable: $userInvocable)';
}


}

/// @nodoc
abstract mixin class _$SkillInvocationPolicyReadCopyWith<$Res> implements $SkillInvocationPolicyReadCopyWith<$Res> {
  factory _$SkillInvocationPolicyReadCopyWith(_SkillInvocationPolicyRead value, $Res Function(_SkillInvocationPolicyRead) _then) = __$SkillInvocationPolicyReadCopyWithImpl;
@override @useResult
$Res call({
 bool modelInvocable, bool userInvocable
});




}
/// @nodoc
class __$SkillInvocationPolicyReadCopyWithImpl<$Res>
    implements _$SkillInvocationPolicyReadCopyWith<$Res> {
  __$SkillInvocationPolicyReadCopyWithImpl(this._self, this._then);

  final _SkillInvocationPolicyRead _self;
  final $Res Function(_SkillInvocationPolicyRead) _then;

/// Create a copy of SkillInvocationPolicyRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? modelInvocable = null,Object? userInvocable = null,}) {
  return _then(_SkillInvocationPolicyRead(
modelInvocable: null == modelInvocable ? _self.modelInvocable : modelInvocable // ignore: cast_nullable_to_non_nullable
as bool,userInvocable: null == userInvocable ? _self.userInvocable : userInvocable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$SkillResourceBaseRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillResourceBaseRead);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SkillResourceBaseReadCopyWith<$Res>  {
$SkillResourceBaseReadCopyWith(SkillResourceBaseRead _, $Res Function(SkillResourceBaseRead) __);
}


/// Adds pattern-matching-related methods to [SkillResourceBaseRead].
extension SkillResourceBaseReadPatterns on SkillResourceBaseRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DirectorySkillResourceBaseRead value)?  directory,TResult Function( UrlSkillResourceBaseRead value)?  url,TResult Function( OpaqueSkillResourceBaseRead value)?  opaque,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead() when directory != null:
return directory(_that);case UrlSkillResourceBaseRead() when url != null:
return url(_that);case OpaqueSkillResourceBaseRead() when opaque != null:
return opaque(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DirectorySkillResourceBaseRead value)  directory,required TResult Function( UrlSkillResourceBaseRead value)  url,required TResult Function( OpaqueSkillResourceBaseRead value)  opaque,}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead():
return directory(_that);case UrlSkillResourceBaseRead():
return url(_that);case OpaqueSkillResourceBaseRead():
return opaque(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DirectorySkillResourceBaseRead value)?  directory,TResult? Function( UrlSkillResourceBaseRead value)?  url,TResult? Function( OpaqueSkillResourceBaseRead value)?  opaque,}){
final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead() when directory != null:
return directory(_that);case UrlSkillResourceBaseRead() when url != null:
return url(_that);case OpaqueSkillResourceBaseRead() when opaque != null:
return opaque(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ReadText path)?  directory,TResult Function( ReadText url)?  url,TResult Function( ReadText description)?  opaque,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead() when directory != null:
return directory(_that.path);case UrlSkillResourceBaseRead() when url != null:
return url(_that.url);case OpaqueSkillResourceBaseRead() when opaque != null:
return opaque(_that.description);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ReadText path)  directory,required TResult Function( ReadText url)  url,required TResult Function( ReadText description)  opaque,}) {final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead():
return directory(_that.path);case UrlSkillResourceBaseRead():
return url(_that.url);case OpaqueSkillResourceBaseRead():
return opaque(_that.description);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ReadText path)?  directory,TResult? Function( ReadText url)?  url,TResult? Function( ReadText description)?  opaque,}) {final _that = this;
switch (_that) {
case DirectorySkillResourceBaseRead() when directory != null:
return directory(_that.path);case UrlSkillResourceBaseRead() when url != null:
return url(_that.url);case OpaqueSkillResourceBaseRead() when opaque != null:
return opaque(_that.description);case _:
  return null;

}
}

}

/// @nodoc


class DirectorySkillResourceBaseRead implements SkillResourceBaseRead {
  const DirectorySkillResourceBaseRead({required this.path});


 final  ReadText path;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DirectorySkillResourceBaseReadCopyWith<DirectorySkillResourceBaseRead> get copyWith => _$DirectorySkillResourceBaseReadCopyWithImpl<DirectorySkillResourceBaseRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DirectorySkillResourceBaseRead&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}



}

/// @nodoc
abstract mixin class $DirectorySkillResourceBaseReadCopyWith<$Res> implements $SkillResourceBaseReadCopyWith<$Res> {
  factory $DirectorySkillResourceBaseReadCopyWith(DirectorySkillResourceBaseRead value, $Res Function(DirectorySkillResourceBaseRead) _then) = _$DirectorySkillResourceBaseReadCopyWithImpl;
@useResult
$Res call({
 ReadText path
});


$ReadTextCopyWith<$Res> get path;

}
/// @nodoc
class _$DirectorySkillResourceBaseReadCopyWithImpl<$Res>
    implements $DirectorySkillResourceBaseReadCopyWith<$Res> {
  _$DirectorySkillResourceBaseReadCopyWithImpl(this._self, this._then);

  final DirectorySkillResourceBaseRead _self;
  final $Res Function(DirectorySkillResourceBaseRead) _then;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(DirectorySkillResourceBaseRead(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}
}

/// @nodoc


class UrlSkillResourceBaseRead implements SkillResourceBaseRead {
  const UrlSkillResourceBaseRead({required this.url});


 final  ReadText url;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UrlSkillResourceBaseReadCopyWith<UrlSkillResourceBaseRead> get copyWith => _$UrlSkillResourceBaseReadCopyWithImpl<UrlSkillResourceBaseRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UrlSkillResourceBaseRead&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url);
}



}

/// @nodoc
abstract mixin class $UrlSkillResourceBaseReadCopyWith<$Res> implements $SkillResourceBaseReadCopyWith<$Res> {
  factory $UrlSkillResourceBaseReadCopyWith(UrlSkillResourceBaseRead value, $Res Function(UrlSkillResourceBaseRead) _then) = _$UrlSkillResourceBaseReadCopyWithImpl;
@useResult
$Res call({
 ReadText url
});


$ReadTextCopyWith<$Res> get url;

}
/// @nodoc
class _$UrlSkillResourceBaseReadCopyWithImpl<$Res>
    implements $UrlSkillResourceBaseReadCopyWith<$Res> {
  _$UrlSkillResourceBaseReadCopyWithImpl(this._self, this._then);

  final UrlSkillResourceBaseRead _self;
  final $Res Function(UrlSkillResourceBaseRead) _then;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(UrlSkillResourceBaseRead(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get url {

  return $ReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}
}

/// @nodoc


class OpaqueSkillResourceBaseRead implements SkillResourceBaseRead {
  const OpaqueSkillResourceBaseRead({required this.description});


 final  ReadText description;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$OpaqueSkillResourceBaseReadCopyWith<OpaqueSkillResourceBaseRead> get copyWith => _$OpaqueSkillResourceBaseReadCopyWithImpl<OpaqueSkillResourceBaseRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is OpaqueSkillResourceBaseRead&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,description);
}



}

/// @nodoc
abstract mixin class $OpaqueSkillResourceBaseReadCopyWith<$Res> implements $SkillResourceBaseReadCopyWith<$Res> {
  factory $OpaqueSkillResourceBaseReadCopyWith(OpaqueSkillResourceBaseRead value, $Res Function(OpaqueSkillResourceBaseRead) _then) = _$OpaqueSkillResourceBaseReadCopyWithImpl;
@useResult
$Res call({
 ReadText description
});


$ReadTextCopyWith<$Res> get description;

}
/// @nodoc
class _$OpaqueSkillResourceBaseReadCopyWithImpl<$Res>
    implements $OpaqueSkillResourceBaseReadCopyWith<$Res> {
  _$OpaqueSkillResourceBaseReadCopyWithImpl(this._self, this._then);

  final OpaqueSkillResourceBaseRead _self;
  final $Res Function(OpaqueSkillResourceBaseRead) _then;

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? description = null,}) {
  return _then(OpaqueSkillResourceBaseRead(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of SkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}

/// @nodoc
mixin _$SkillSummaryRead {

 ReadText get name; ReadText get description; ReadText? get category; TypedListRef get platforms; SkillSource get source; ReadText get providerId; SkillInvocationPolicyRead get invocation; SkillResourceBaseRead get resourceBase;
/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillSummaryReadCopyWith<SkillSummaryRead> get copyWith => _$SkillSummaryReadCopyWithImpl<SkillSummaryRead>(this as SkillSummaryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillSummaryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillSummaryRead&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.description, _this.description) || other.description == _this.description)&&(identical(other.category, _this.category) || other.category == _this.category)&&(identical(other.platforms, _this.platforms) || other.platforms == _this.platforms)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.providerId, _this.providerId) || other.providerId == _this.providerId)&&(identical(other.invocation, _this.invocation) || other.invocation == _this.invocation)&&(identical(other.resourceBase, _this.resourceBase) || other.resourceBase == _this.resourceBase));
}


@override
int get hashCode {
  final _this = this as SkillSummaryRead;
  return Object.hash(runtimeType,_this.name,_this.description,_this.category,_this.platforms,_this.source,_this.providerId,_this.invocation,_this.resourceBase);
}



}

/// @nodoc
abstract mixin class $SkillSummaryReadCopyWith<$Res>  {
  factory $SkillSummaryReadCopyWith(SkillSummaryRead value, $Res Function(SkillSummaryRead) _then) = _$SkillSummaryReadCopyWithImpl;
@useResult
$Res call({
 ReadText name, ReadText description, ReadText? category, TypedListRef platforms, SkillSource source, ReadText providerId, SkillInvocationPolicyRead invocation, SkillResourceBaseRead resourceBase
});


$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get description;$ReadTextCopyWith<$Res>? get category;$TypedListRefCopyWith<$Res> get platforms;$ReadTextCopyWith<$Res> get providerId;$SkillInvocationPolicyReadCopyWith<$Res> get invocation;$SkillResourceBaseReadCopyWith<$Res> get resourceBase;

}
/// @nodoc
class _$SkillSummaryReadCopyWithImpl<$Res>
    implements $SkillSummaryReadCopyWith<$Res> {
  _$SkillSummaryReadCopyWithImpl(this._self, this._then);

  final SkillSummaryRead _self;
  final $Res Function(SkillSummaryRead) _then;

/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? description = null,Object? category = freezed,Object? platforms = null,Object? source = null,Object? providerId = null,Object? invocation = null,Object? resourceBase = null,}) {
  return _then(SkillSummaryRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ReadText?,platforms: null == platforms ? _self.platforms : platforms // ignore: cast_nullable_to_non_nullable
as TypedListRef,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SkillSource,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as ReadText,invocation: null == invocation ? _self.invocation : invocation // ignore: cast_nullable_to_non_nullable
as SkillInvocationPolicyRead,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as SkillResourceBaseRead,
  ));
}
/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get category {
    if (_self.category == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.category!, (value) {
    return _then(_self.copyWith(category: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get platforms {

  return $TypedListRefCopyWith<$Res>(_self.platforms, (value) {
    return _then(_self.copyWith(platforms: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get providerId {

  return $ReadTextCopyWith<$Res>(_self.providerId, (value) {
    return _then(_self.copyWith(providerId: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillInvocationPolicyReadCopyWith<$Res> get invocation {

  return $SkillInvocationPolicyReadCopyWith<$Res>(_self.invocation, (value) {
    return _then(_self.copyWith(invocation: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillResourceBaseReadCopyWith<$Res> get resourceBase {

  return $SkillResourceBaseReadCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillSummaryRead].
extension SkillSummaryReadPatterns on SkillSummaryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillSummaryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillSummaryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillSummaryRead value)  $default,){
final _that = this;
switch (_that) {
case _SkillSummaryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillSummaryRead value)?  $default,){
final _that = this;
switch (_that) {
case _SkillSummaryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText name,  ReadText description,  ReadText? category,  TypedListRef platforms,  SkillSource source,  ReadText providerId,  SkillInvocationPolicyRead invocation,  SkillResourceBaseRead resourceBase)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillSummaryRead() when $default != null:
return $default(_that.name,_that.description,_that.category,_that.platforms,_that.source,_that.providerId,_that.invocation,_that.resourceBase);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText name,  ReadText description,  ReadText? category,  TypedListRef platforms,  SkillSource source,  ReadText providerId,  SkillInvocationPolicyRead invocation,  SkillResourceBaseRead resourceBase)  $default,) {final _that = this;
switch (_that) {
case _SkillSummaryRead():
return $default(_that.name,_that.description,_that.category,_that.platforms,_that.source,_that.providerId,_that.invocation,_that.resourceBase);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText name,  ReadText description,  ReadText? category,  TypedListRef platforms,  SkillSource source,  ReadText providerId,  SkillInvocationPolicyRead invocation,  SkillResourceBaseRead resourceBase)?  $default,) {final _that = this;
switch (_that) {
case _SkillSummaryRead() when $default != null:
return $default(_that.name,_that.description,_that.category,_that.platforms,_that.source,_that.providerId,_that.invocation,_that.resourceBase);case _:
  return null;

}
}

}

/// @nodoc


class _SkillSummaryRead implements SkillSummaryRead {
  const _SkillSummaryRead({required this.name, required this.description, required this.category, required this.platforms, required this.source, required this.providerId, required this.invocation, required this.resourceBase});


@override final  ReadText name;
@override final  ReadText description;
@override final  ReadText? category;
@override final  TypedListRef platforms;
@override final  SkillSource source;
@override final  ReadText providerId;
@override final  SkillInvocationPolicyRead invocation;
@override final  SkillResourceBaseRead resourceBase;

/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillSummaryReadCopyWith<_SkillSummaryRead> get copyWith => __$SkillSummaryReadCopyWithImpl<_SkillSummaryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillSummaryRead&&(identical(other.name, name) || other.name == name)&&(identical(other.description, description) || other.description == description)&&(identical(other.category, category) || other.category == category)&&(identical(other.platforms, platforms) || other.platforms == platforms)&&(identical(other.source, source) || other.source == source)&&(identical(other.providerId, providerId) || other.providerId == providerId)&&(identical(other.invocation, invocation) || other.invocation == invocation)&&(identical(other.resourceBase, resourceBase) || other.resourceBase == resourceBase));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,description,category,platforms,source,providerId,invocation,resourceBase);
}



}

/// @nodoc
abstract mixin class _$SkillSummaryReadCopyWith<$Res> implements $SkillSummaryReadCopyWith<$Res> {
  factory _$SkillSummaryReadCopyWith(_SkillSummaryRead value, $Res Function(_SkillSummaryRead) _then) = __$SkillSummaryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText name, ReadText description, ReadText? category, TypedListRef platforms, SkillSource source, ReadText providerId, SkillInvocationPolicyRead invocation, SkillResourceBaseRead resourceBase
});


@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get description;@override $ReadTextCopyWith<$Res>? get category;@override $TypedListRefCopyWith<$Res> get platforms;@override $ReadTextCopyWith<$Res> get providerId;@override $SkillInvocationPolicyReadCopyWith<$Res> get invocation;@override $SkillResourceBaseReadCopyWith<$Res> get resourceBase;

}
/// @nodoc
class __$SkillSummaryReadCopyWithImpl<$Res>
    implements _$SkillSummaryReadCopyWith<$Res> {
  __$SkillSummaryReadCopyWithImpl(this._self, this._then);

  final _SkillSummaryRead _self;
  final $Res Function(_SkillSummaryRead) _then;

/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? description = null,Object? category = freezed,Object? platforms = null,Object? source = null,Object? providerId = null,Object? invocation = null,Object? resourceBase = null,}) {
  return _then(_SkillSummaryRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as ReadText,category: freezed == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as ReadText?,platforms: null == platforms ? _self.platforms : platforms // ignore: cast_nullable_to_non_nullable
as TypedListRef,source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as SkillSource,providerId: null == providerId ? _self.providerId : providerId // ignore: cast_nullable_to_non_nullable
as ReadText,invocation: null == invocation ? _self.invocation : invocation // ignore: cast_nullable_to_non_nullable
as SkillInvocationPolicyRead,resourceBase: null == resourceBase ? _self.resourceBase : resourceBase // ignore: cast_nullable_to_non_nullable
as SkillResourceBaseRead,
  ));
}

/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get description {

  return $ReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get category {
    if (_self.category == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.category!, (value) {
    return _then(_self.copyWith(category: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<$Res> get platforms {

  return $TypedListRefCopyWith<$Res>(_self.platforms, (value) {
    return _then(_self.copyWith(platforms: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get providerId {

  return $ReadTextCopyWith<$Res>(_self.providerId, (value) {
    return _then(_self.copyWith(providerId: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillInvocationPolicyReadCopyWith<$Res> get invocation {

  return $SkillInvocationPolicyReadCopyWith<$Res>(_self.invocation, (value) {
    return _then(_self.copyWith(invocation: value));
  });
}/// Create a copy of SkillSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillResourceBaseReadCopyWith<$Res> get resourceBase {

  return $SkillResourceBaseReadCopyWith<$Res>(_self.resourceBase, (value) {
    return _then(_self.copyWith(resourceBase: value));
  });
}
}

/// @nodoc
mixin _$SkillsEntityRead {

 ProductEntityRef get reference; SkillSummaryRead get value;
/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsEntityReadCopyWith<SkillsEntityRead> get copyWith => _$SkillsEntityReadCopyWithImpl<SkillsEntityRead>(this as SkillsEntityRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsEntityRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsEntityRead&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as SkillsEntityRead;
  return Object.hash(runtimeType,_this.reference,_this.value);
}



}

/// @nodoc
abstract mixin class $SkillsEntityReadCopyWith<$Res>  {
  factory $SkillsEntityReadCopyWith(SkillsEntityRead value, $Res Function(SkillsEntityRead) _then) = _$SkillsEntityReadCopyWithImpl;
@useResult
$Res call({
 ProductEntityRef reference, SkillSummaryRead value
});


$ProductEntityRefCopyWith<$Res> get reference;$SkillSummaryReadCopyWith<$Res> get value;

}
/// @nodoc
class _$SkillsEntityReadCopyWithImpl<$Res>
    implements $SkillsEntityReadCopyWith<$Res> {
  _$SkillsEntityReadCopyWithImpl(this._self, this._then);

  final SkillsEntityRead _self;
  final $Res Function(SkillsEntityRead) _then;

/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? value = null,}) {
  return _then(SkillsEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SkillSummaryRead,
  ));
}
/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillSummaryReadCopyWith<$Res> get value {

  return $SkillSummaryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsEntityRead].
extension SkillsEntityReadPatterns on SkillsEntityRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsEntityRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsEntityRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsEntityRead value)  $default,){
final _that = this;
switch (_that) {
case _SkillsEntityRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsEntityRead value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsEntityRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductEntityRef reference,  SkillSummaryRead value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsEntityRead() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductEntityRef reference,  SkillSummaryRead value)  $default,) {final _that = this;
switch (_that) {
case _SkillsEntityRead():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductEntityRef reference,  SkillSummaryRead value)?  $default,) {final _that = this;
switch (_that) {
case _SkillsEntityRead() when $default != null:
return $default(_that.reference,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsEntityRead implements SkillsEntityRead {
  const _SkillsEntityRead({required this.reference, required this.value});


@override final  ProductEntityRef reference;
@override final  SkillSummaryRead value;

/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsEntityReadCopyWith<_SkillsEntityRead> get copyWith => __$SkillsEntityReadCopyWithImpl<_SkillsEntityRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsEntityRead&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,value);
}



}

/// @nodoc
abstract mixin class _$SkillsEntityReadCopyWith<$Res> implements $SkillsEntityReadCopyWith<$Res> {
  factory _$SkillsEntityReadCopyWith(_SkillsEntityRead value, $Res Function(_SkillsEntityRead) _then) = __$SkillsEntityReadCopyWithImpl;
@override @useResult
$Res call({
 ProductEntityRef reference, SkillSummaryRead value
});


@override $ProductEntityRefCopyWith<$Res> get reference;@override $SkillSummaryReadCopyWith<$Res> get value;

}
/// @nodoc
class __$SkillsEntityReadCopyWithImpl<$Res>
    implements _$SkillsEntityReadCopyWith<$Res> {
  __$SkillsEntityReadCopyWithImpl(this._self, this._then);

  final _SkillsEntityRead _self;
  final $Res Function(_SkillsEntityRead) _then;

/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? value = null,}) {
  return _then(_SkillsEntityRead(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as ProductEntityRef,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SkillSummaryRead,
  ));
}

/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductEntityRefCopyWith<$Res> get reference {

  return $ProductEntityRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}/// Create a copy of SkillsEntityRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillSummaryReadCopyWith<$Res> get value {

  return $SkillSummaryReadCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$SkillsEntryPage {


/// Create a copy of SkillsEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsEntryPageCopyWith<SkillsEntryPage> get copyWith => _$SkillsEntryPageCopyWithImpl<SkillsEntryPage>(this as SkillsEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsEntryPage&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as SkillsEntryPage;
  return Object.hash(runtimeType,_this.collection,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}

@override
String toString() {
  final _this = this as SkillsEntryPage;
  return 'SkillsEntryPage(collection: ${_this.collection}, offset: ${_this.offset}, items: ${_this.items}, nextOffset: ${_this.nextOffset})';
}


}

/// @nodoc
abstract mixin class $SkillsEntryPageCopyWith<$Res>  {
  factory $SkillsEntryPageCopyWith(SkillsEntryPage value, $Res Function(SkillsEntryPage) _then) = _$SkillsEntryPageCopyWithImpl;
@useResult
$Res call({
 ProductCollectionRef collection, int offset, List<ProductEntityRef> items, int? nextOffset
});


$ProductCollectionRefCopyWith<$Res> get collection;

}
/// @nodoc
class _$SkillsEntryPageCopyWithImpl<$Res>
    implements $SkillsEntryPageCopyWith<$Res> {
  _$SkillsEntryPageCopyWithImpl(this._self, this._then);

  final SkillsEntryPage _self;
  final $Res Function(SkillsEntryPage) _then;

/// Create a copy of SkillsEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? collection = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(SkillsEntryPage(
collection: null == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of SkillsEntryPage
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res> get collection {

  return $ProductCollectionRefCopyWith<$Res>(_self.collection, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsEntryPage].
extension SkillsEntryPagePatterns on SkillsEntryPage {
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
mixin _$SkillSummaryReadPage {


/// Create a copy of SkillSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillSummaryReadPageCopyWith<SkillSummaryReadPage> get copyWith => _$SkillSummaryReadPageCopyWithImpl<SkillSummaryReadPage>(this as SkillSummaryReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillSummaryReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillSummaryReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as SkillSummaryReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $SkillSummaryReadPageCopyWith<$Res>  {
  factory $SkillSummaryReadPageCopyWith(SkillSummaryReadPage value, $Res Function(SkillSummaryReadPage) _then) = _$SkillSummaryReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<SkillSummaryRead> items, int? nextOffset
});




}
/// @nodoc
class _$SkillSummaryReadPageCopyWithImpl<$Res>
    implements $SkillSummaryReadPageCopyWith<$Res> {
  _$SkillSummaryReadPageCopyWithImpl(this._self, this._then);

  final SkillSummaryReadPage _self;
  final $Res Function(SkillSummaryReadPage) _then;

/// Create a copy of SkillSummaryReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(SkillSummaryReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<SkillSummaryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillSummaryReadPage].
extension SkillSummaryReadPagePatterns on SkillSummaryReadPage {
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
