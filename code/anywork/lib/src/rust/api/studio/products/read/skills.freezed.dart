// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeSkillResourceBaseRead {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBaseRead);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSkillResourceBaseRead()';
}


}

/// @nodoc
class $BridgeSkillResourceBaseReadCopyWith<$Res>  {
$BridgeSkillResourceBaseReadCopyWith(BridgeSkillResourceBaseRead _, $Res Function(BridgeSkillResourceBaseRead) __);
}


/// Adds pattern-matching-related methods to [BridgeSkillResourceBaseRead].
extension BridgeSkillResourceBaseReadPatterns on BridgeSkillResourceBaseRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillResourceBaseRead_Directory value)?  directory,TResult Function( BridgeSkillResourceBaseRead_Url value)?  url,TResult Function( BridgeSkillResourceBaseRead_Opaque value)?  opaque,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory() when directory != null:
return directory(_that);case BridgeSkillResourceBaseRead_Url() when url != null:
return url(_that);case BridgeSkillResourceBaseRead_Opaque() when opaque != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillResourceBaseRead_Directory value)  directory,required TResult Function( BridgeSkillResourceBaseRead_Url value)  url,required TResult Function( BridgeSkillResourceBaseRead_Opaque value)  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory():
return directory(_that);case BridgeSkillResourceBaseRead_Url():
return url(_that);case BridgeSkillResourceBaseRead_Opaque():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillResourceBaseRead_Directory value)?  directory,TResult? Function( BridgeSkillResourceBaseRead_Url value)?  url,TResult? Function( BridgeSkillResourceBaseRead_Opaque value)?  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory() when directory != null:
return directory(_that);case BridgeSkillResourceBaseRead_Url() when url != null:
return url(_that);case BridgeSkillResourceBaseRead_Opaque() when opaque != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( BridgeReadText path)?  directory,TResult Function( BridgeReadText url)?  url,TResult Function( BridgeReadText description)?  opaque,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory() when directory != null:
return directory(_that.path);case BridgeSkillResourceBaseRead_Url() when url != null:
return url(_that.url);case BridgeSkillResourceBaseRead_Opaque() when opaque != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( BridgeReadText path)  directory,required TResult Function( BridgeReadText url)  url,required TResult Function( BridgeReadText description)  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory():
return directory(_that.path);case BridgeSkillResourceBaseRead_Url():
return url(_that.url);case BridgeSkillResourceBaseRead_Opaque():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( BridgeReadText path)?  directory,TResult? Function( BridgeReadText url)?  url,TResult? Function( BridgeReadText description)?  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillResourceBaseRead_Directory() when directory != null:
return directory(_that.path);case BridgeSkillResourceBaseRead_Url() when url != null:
return url(_that.url);case BridgeSkillResourceBaseRead_Opaque() when opaque != null:
return opaque(_that.description);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillResourceBaseRead_Directory extends BridgeSkillResourceBaseRead {
  const BridgeSkillResourceBaseRead_Directory({required this.path}): super._();


 final  BridgeReadText path;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBaseRead_DirectoryCopyWith<BridgeSkillResourceBaseRead_Directory> get copyWith => _$BridgeSkillResourceBaseRead_DirectoryCopyWithImpl<BridgeSkillResourceBaseRead_Directory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBaseRead_Directory&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}

@override
String toString() {
    return 'BridgeSkillResourceBaseRead.directory(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBaseRead_DirectoryCopyWith<$Res> implements $BridgeSkillResourceBaseReadCopyWith<$Res> {
  factory $BridgeSkillResourceBaseRead_DirectoryCopyWith(BridgeSkillResourceBaseRead_Directory value, $Res Function(BridgeSkillResourceBaseRead_Directory) _then) = _$BridgeSkillResourceBaseRead_DirectoryCopyWithImpl;
@useResult
$Res call({
 BridgeReadText path
});


$BridgeReadTextCopyWith<$Res> get path;

}
/// @nodoc
class _$BridgeSkillResourceBaseRead_DirectoryCopyWithImpl<$Res>
    implements $BridgeSkillResourceBaseRead_DirectoryCopyWith<$Res> {
  _$BridgeSkillResourceBaseRead_DirectoryCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBaseRead_Directory _self;
  final $Res Function(BridgeSkillResourceBaseRead_Directory) _then;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeSkillResourceBaseRead_Directory(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get path {

  return $BridgeReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}
}

/// @nodoc


class BridgeSkillResourceBaseRead_Url extends BridgeSkillResourceBaseRead {
  const BridgeSkillResourceBaseRead_Url({required this.url}): super._();


 final  BridgeReadText url;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBaseRead_UrlCopyWith<BridgeSkillResourceBaseRead_Url> get copyWith => _$BridgeSkillResourceBaseRead_UrlCopyWithImpl<BridgeSkillResourceBaseRead_Url>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBaseRead_Url&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url);
}

@override
String toString() {
    return 'BridgeSkillResourceBaseRead.url(url: $url)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBaseRead_UrlCopyWith<$Res> implements $BridgeSkillResourceBaseReadCopyWith<$Res> {
  factory $BridgeSkillResourceBaseRead_UrlCopyWith(BridgeSkillResourceBaseRead_Url value, $Res Function(BridgeSkillResourceBaseRead_Url) _then) = _$BridgeSkillResourceBaseRead_UrlCopyWithImpl;
@useResult
$Res call({
 BridgeReadText url
});


$BridgeReadTextCopyWith<$Res> get url;

}
/// @nodoc
class _$BridgeSkillResourceBaseRead_UrlCopyWithImpl<$Res>
    implements $BridgeSkillResourceBaseRead_UrlCopyWith<$Res> {
  _$BridgeSkillResourceBaseRead_UrlCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBaseRead_Url _self;
  final $Res Function(BridgeSkillResourceBaseRead_Url) _then;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(BridgeSkillResourceBaseRead_Url(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get url {

  return $BridgeReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}
}

/// @nodoc


class BridgeSkillResourceBaseRead_Opaque extends BridgeSkillResourceBaseRead {
  const BridgeSkillResourceBaseRead_Opaque({required this.description}): super._();


 final  BridgeReadText description;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillResourceBaseRead_OpaqueCopyWith<BridgeSkillResourceBaseRead_Opaque> get copyWith => _$BridgeSkillResourceBaseRead_OpaqueCopyWithImpl<BridgeSkillResourceBaseRead_Opaque>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillResourceBaseRead_Opaque&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,description);
}

@override
String toString() {
    return 'BridgeSkillResourceBaseRead.opaque(description: $description)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillResourceBaseRead_OpaqueCopyWith<$Res> implements $BridgeSkillResourceBaseReadCopyWith<$Res> {
  factory $BridgeSkillResourceBaseRead_OpaqueCopyWith(BridgeSkillResourceBaseRead_Opaque value, $Res Function(BridgeSkillResourceBaseRead_Opaque) _then) = _$BridgeSkillResourceBaseRead_OpaqueCopyWithImpl;
@useResult
$Res call({
 BridgeReadText description
});


$BridgeReadTextCopyWith<$Res> get description;

}
/// @nodoc
class _$BridgeSkillResourceBaseRead_OpaqueCopyWithImpl<$Res>
    implements $BridgeSkillResourceBaseRead_OpaqueCopyWith<$Res> {
  _$BridgeSkillResourceBaseRead_OpaqueCopyWithImpl(this._self, this._then);

  final BridgeSkillResourceBaseRead_Opaque _self;
  final $Res Function(BridgeSkillResourceBaseRead_Opaque) _then;

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? description = null,}) {
  return _then(BridgeSkillResourceBaseRead_Opaque(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as BridgeReadText,
  ));
}

/// Create a copy of BridgeSkillResourceBaseRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeReadTextCopyWith<$Res> get description {

  return $BridgeReadTextCopyWith<$Res>(_self.description, (value) {
    return _then(_self.copyWith(description: value));
  });
}
}

/// @nodoc
mixin _$BridgeSkillSearchResourceBase {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillSearchResourceBase);
}


@override
int get hashCode => runtimeType.hashCode;

@override
String toString() {
    return 'BridgeSkillSearchResourceBase()';
}


}

/// @nodoc
class $BridgeSkillSearchResourceBaseCopyWith<$Res>  {
$BridgeSkillSearchResourceBaseCopyWith(BridgeSkillSearchResourceBase _, $Res Function(BridgeSkillSearchResourceBase) __);
}


/// Adds pattern-matching-related methods to [BridgeSkillSearchResourceBase].
extension BridgeSkillSearchResourceBasePatterns on BridgeSkillSearchResourceBase {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeSkillSearchResourceBase_Directory value)?  directory,TResult Function( BridgeSkillSearchResourceBase_Url value)?  url,TResult Function( BridgeSkillSearchResourceBase_Opaque value)?  opaque,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory() when directory != null:
return directory(_that);case BridgeSkillSearchResourceBase_Url() when url != null:
return url(_that);case BridgeSkillSearchResourceBase_Opaque() when opaque != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeSkillSearchResourceBase_Directory value)  directory,required TResult Function( BridgeSkillSearchResourceBase_Url value)  url,required TResult Function( BridgeSkillSearchResourceBase_Opaque value)  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory():
return directory(_that);case BridgeSkillSearchResourceBase_Url():
return url(_that);case BridgeSkillSearchResourceBase_Opaque():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeSkillSearchResourceBase_Directory value)?  directory,TResult? Function( BridgeSkillSearchResourceBase_Url value)?  url,TResult? Function( BridgeSkillSearchResourceBase_Opaque value)?  opaque,}){
final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory() when directory != null:
return directory(_that);case BridgeSkillSearchResourceBase_Url() when url != null:
return url(_that);case BridgeSkillSearchResourceBase_Opaque() when opaque != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path)?  directory,TResult Function( String url)?  url,TResult Function( String description)?  opaque,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory() when directory != null:
return directory(_that.path);case BridgeSkillSearchResourceBase_Url() when url != null:
return url(_that.url);case BridgeSkillSearchResourceBase_Opaque() when opaque != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path)  directory,required TResult Function( String url)  url,required TResult Function( String description)  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory():
return directory(_that.path);case BridgeSkillSearchResourceBase_Url():
return url(_that.url);case BridgeSkillSearchResourceBase_Opaque():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path)?  directory,TResult? Function( String url)?  url,TResult? Function( String description)?  opaque,}) {final _that = this;
switch (_that) {
case BridgeSkillSearchResourceBase_Directory() when directory != null:
return directory(_that.path);case BridgeSkillSearchResourceBase_Url() when url != null:
return url(_that.url);case BridgeSkillSearchResourceBase_Opaque() when opaque != null:
return opaque(_that.description);case _:
  return null;

}
}

}

/// @nodoc


class BridgeSkillSearchResourceBase_Directory extends BridgeSkillSearchResourceBase {
  const BridgeSkillSearchResourceBase_Directory({required this.path}): super._();


 final  String path;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillSearchResourceBase_DirectoryCopyWith<BridgeSkillSearchResourceBase_Directory> get copyWith => _$BridgeSkillSearchResourceBase_DirectoryCopyWithImpl<BridgeSkillSearchResourceBase_Directory>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillSearchResourceBase_Directory&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}

@override
String toString() {
    return 'BridgeSkillSearchResourceBase.directory(path: $path)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillSearchResourceBase_DirectoryCopyWith<$Res> implements $BridgeSkillSearchResourceBaseCopyWith<$Res> {
  factory $BridgeSkillSearchResourceBase_DirectoryCopyWith(BridgeSkillSearchResourceBase_Directory value, $Res Function(BridgeSkillSearchResourceBase_Directory) _then) = _$BridgeSkillSearchResourceBase_DirectoryCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$BridgeSkillSearchResourceBase_DirectoryCopyWithImpl<$Res>
    implements $BridgeSkillSearchResourceBase_DirectoryCopyWith<$Res> {
  _$BridgeSkillSearchResourceBase_DirectoryCopyWithImpl(this._self, this._then);

  final BridgeSkillSearchResourceBase_Directory _self;
  final $Res Function(BridgeSkillSearchResourceBase_Directory) _then;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(BridgeSkillSearchResourceBase_Directory(
path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSkillSearchResourceBase_Url extends BridgeSkillSearchResourceBase {
  const BridgeSkillSearchResourceBase_Url({required this.url}): super._();


 final  String url;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillSearchResourceBase_UrlCopyWith<BridgeSkillSearchResourceBase_Url> get copyWith => _$BridgeSkillSearchResourceBase_UrlCopyWithImpl<BridgeSkillSearchResourceBase_Url>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillSearchResourceBase_Url&&(identical(other.url, url) || other.url == url));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url);
}

@override
String toString() {
    return 'BridgeSkillSearchResourceBase.url(url: $url)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillSearchResourceBase_UrlCopyWith<$Res> implements $BridgeSkillSearchResourceBaseCopyWith<$Res> {
  factory $BridgeSkillSearchResourceBase_UrlCopyWith(BridgeSkillSearchResourceBase_Url value, $Res Function(BridgeSkillSearchResourceBase_Url) _then) = _$BridgeSkillSearchResourceBase_UrlCopyWithImpl;
@useResult
$Res call({
 String url
});




}
/// @nodoc
class _$BridgeSkillSearchResourceBase_UrlCopyWithImpl<$Res>
    implements $BridgeSkillSearchResourceBase_UrlCopyWith<$Res> {
  _$BridgeSkillSearchResourceBase_UrlCopyWithImpl(this._self, this._then);

  final BridgeSkillSearchResourceBase_Url _self;
  final $Res Function(BridgeSkillSearchResourceBase_Url) _then;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,}) {
  return _then(BridgeSkillSearchResourceBase_Url(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class BridgeSkillSearchResourceBase_Opaque extends BridgeSkillSearchResourceBase {
  const BridgeSkillSearchResourceBase_Opaque({required this.description}): super._();


 final  String description;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeSkillSearchResourceBase_OpaqueCopyWith<BridgeSkillSearchResourceBase_Opaque> get copyWith => _$BridgeSkillSearchResourceBase_OpaqueCopyWithImpl<BridgeSkillSearchResourceBase_Opaque>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeSkillSearchResourceBase_Opaque&&(identical(other.description, description) || other.description == description));
}


@override
int get hashCode {
    return Object.hash(runtimeType,description);
}

@override
String toString() {
    return 'BridgeSkillSearchResourceBase.opaque(description: $description)';
}


}

/// @nodoc
abstract mixin class $BridgeSkillSearchResourceBase_OpaqueCopyWith<$Res> implements $BridgeSkillSearchResourceBaseCopyWith<$Res> {
  factory $BridgeSkillSearchResourceBase_OpaqueCopyWith(BridgeSkillSearchResourceBase_Opaque value, $Res Function(BridgeSkillSearchResourceBase_Opaque) _then) = _$BridgeSkillSearchResourceBase_OpaqueCopyWithImpl;
@useResult
$Res call({
 String description
});




}
/// @nodoc
class _$BridgeSkillSearchResourceBase_OpaqueCopyWithImpl<$Res>
    implements $BridgeSkillSearchResourceBase_OpaqueCopyWith<$Res> {
  _$BridgeSkillSearchResourceBase_OpaqueCopyWithImpl(this._self, this._then);

  final BridgeSkillSearchResourceBase_Opaque _self;
  final $Res Function(BridgeSkillSearchResourceBase_Opaque) _then;

/// Create a copy of BridgeSkillSearchResourceBase
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? description = null,}) {
  return _then(BridgeSkillSearchResourceBase_Opaque(
description: null == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

// dart format on
