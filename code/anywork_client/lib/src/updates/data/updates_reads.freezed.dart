// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'updates_reads.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$UpdateSummaryRead {

 ReadText get version; int get publishedAt; ReadText get notesUrl;
/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateSummaryReadCopyWith<UpdateSummaryRead> get copyWith => _$UpdateSummaryReadCopyWithImpl<UpdateSummaryRead>(this as UpdateSummaryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateSummaryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateSummaryRead&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.publishedAt, _this.publishedAt) || other.publishedAt == _this.publishedAt)&&(identical(other.notesUrl, _this.notesUrl) || other.notesUrl == _this.notesUrl));
}


@override
int get hashCode {
  final _this = this as UpdateSummaryRead;
  return Object.hash(runtimeType,_this.version,_this.publishedAt,_this.notesUrl);
}



}

/// @nodoc
abstract mixin class $UpdateSummaryReadCopyWith<$Res>  {
  factory $UpdateSummaryReadCopyWith(UpdateSummaryRead value, $Res Function(UpdateSummaryRead) _then) = _$UpdateSummaryReadCopyWithImpl;
@useResult
$Res call({
 ReadText version, int publishedAt, ReadText notesUrl
});


$ReadTextCopyWith<$Res> get version;$ReadTextCopyWith<$Res> get notesUrl;

}
/// @nodoc
class _$UpdateSummaryReadCopyWithImpl<$Res>
    implements $UpdateSummaryReadCopyWith<$Res> {
  _$UpdateSummaryReadCopyWithImpl(this._self, this._then);

  final UpdateSummaryRead _self;
  final $Res Function(UpdateSummaryRead) _then;

/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? version = null,Object? publishedAt = null,Object? notesUrl = null,}) {
  return _then(UpdateSummaryRead(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as ReadText,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as int,notesUrl: null == notesUrl ? _self.notesUrl : notesUrl // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get version {

  return $ReadTextCopyWith<$Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get notesUrl {

  return $ReadTextCopyWith<$Res>(_self.notesUrl, (value) {
    return _then(_self.copyWith(notesUrl: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateSummaryRead].
extension UpdateSummaryReadPatterns on UpdateSummaryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateSummaryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateSummaryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateSummaryRead value)  $default,){
final _that = this;
switch (_that) {
case _UpdateSummaryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateSummaryRead value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateSummaryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText version,  int publishedAt,  ReadText notesUrl)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateSummaryRead() when $default != null:
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText version,  int publishedAt,  ReadText notesUrl)  $default,) {final _that = this;
switch (_that) {
case _UpdateSummaryRead():
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText version,  int publishedAt,  ReadText notesUrl)?  $default,) {final _that = this;
switch (_that) {
case _UpdateSummaryRead() when $default != null:
return $default(_that.version,_that.publishedAt,_that.notesUrl);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateSummaryRead implements UpdateSummaryRead {
  const _UpdateSummaryRead({required this.version, required this.publishedAt, required this.notesUrl});


@override final  ReadText version;
@override final  int publishedAt;
@override final  ReadText notesUrl;

/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateSummaryReadCopyWith<_UpdateSummaryRead> get copyWith => __$UpdateSummaryReadCopyWithImpl<_UpdateSummaryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateSummaryRead&&(identical(other.version, version) || other.version == version)&&(identical(other.publishedAt, publishedAt) || other.publishedAt == publishedAt)&&(identical(other.notesUrl, notesUrl) || other.notesUrl == notesUrl));
}


@override
int get hashCode {
    return Object.hash(runtimeType,version,publishedAt,notesUrl);
}



}

/// @nodoc
abstract mixin class _$UpdateSummaryReadCopyWith<$Res> implements $UpdateSummaryReadCopyWith<$Res> {
  factory _$UpdateSummaryReadCopyWith(_UpdateSummaryRead value, $Res Function(_UpdateSummaryRead) _then) = __$UpdateSummaryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText version, int publishedAt, ReadText notesUrl
});


@override $ReadTextCopyWith<$Res> get version;@override $ReadTextCopyWith<$Res> get notesUrl;

}
/// @nodoc
class __$UpdateSummaryReadCopyWithImpl<$Res>
    implements _$UpdateSummaryReadCopyWith<$Res> {
  __$UpdateSummaryReadCopyWithImpl(this._self, this._then);

  final _UpdateSummaryRead _self;
  final $Res Function(_UpdateSummaryRead) _then;

/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? version = null,Object? publishedAt = null,Object? notesUrl = null,}) {
  return _then(_UpdateSummaryRead(
version: null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as ReadText,publishedAt: null == publishedAt ? _self.publishedAt : publishedAt // ignore: cast_nullable_to_non_nullable
as int,notesUrl: null == notesUrl ? _self.notesUrl : notesUrl // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get version {

  return $ReadTextCopyWith<$Res>(_self.version, (value) {
    return _then(_self.copyWith(version: value));
  });
}/// Create a copy of UpdateSummaryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get notesUrl {

  return $ReadTextCopyWith<$Res>(_self.notesUrl, (value) {
    return _then(_self.copyWith(notesUrl: value));
  });
}
}

/// @nodoc
mixin _$UpdateAssetRead {

 ReadText get url; int get size; ReadText get sha256; ReadText get signature;
/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateAssetReadCopyWith<UpdateAssetRead> get copyWith => _$UpdateAssetReadCopyWithImpl<UpdateAssetRead>(this as UpdateAssetRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateAssetRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateAssetRead&&(identical(other.url, _this.url) || other.url == _this.url)&&(identical(other.size, _this.size) || other.size == _this.size)&&(identical(other.sha256, _this.sha256) || other.sha256 == _this.sha256)&&(identical(other.signature, _this.signature) || other.signature == _this.signature));
}


@override
int get hashCode {
  final _this = this as UpdateAssetRead;
  return Object.hash(runtimeType,_this.url,_this.size,_this.sha256,_this.signature);
}



}

/// @nodoc
abstract mixin class $UpdateAssetReadCopyWith<$Res>  {
  factory $UpdateAssetReadCopyWith(UpdateAssetRead value, $Res Function(UpdateAssetRead) _then) = _$UpdateAssetReadCopyWithImpl;
@useResult
$Res call({
 ReadText url, int size, ReadText sha256, ReadText signature
});


$ReadTextCopyWith<$Res> get url;$ReadTextCopyWith<$Res> get sha256;$ReadTextCopyWith<$Res> get signature;

}
/// @nodoc
class _$UpdateAssetReadCopyWithImpl<$Res>
    implements $UpdateAssetReadCopyWith<$Res> {
  _$UpdateAssetReadCopyWithImpl(this._self, this._then);

  final UpdateAssetRead _self;
  final $Res Function(UpdateAssetRead) _then;

/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? url = null,Object? size = null,Object? sha256 = null,Object? signature = null,}) {
  return _then(UpdateAssetRead(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as ReadText,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as ReadText,signature: null == signature ? _self.signature : signature // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get url {

  return $ReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sha256 {

  return $ReadTextCopyWith<$Res>(_self.sha256, (value) {
    return _then(_self.copyWith(sha256: value));
  });
}/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get signature {

  return $ReadTextCopyWith<$Res>(_self.signature, (value) {
    return _then(_self.copyWith(signature: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateAssetRead].
extension UpdateAssetReadPatterns on UpdateAssetRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateAssetRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateAssetRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateAssetRead value)  $default,){
final _that = this;
switch (_that) {
case _UpdateAssetRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateAssetRead value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateAssetRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText url,  int size,  ReadText sha256,  ReadText signature)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateAssetRead() when $default != null:
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText url,  int size,  ReadText sha256,  ReadText signature)  $default,) {final _that = this;
switch (_that) {
case _UpdateAssetRead():
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText url,  int size,  ReadText sha256,  ReadText signature)?  $default,) {final _that = this;
switch (_that) {
case _UpdateAssetRead() when $default != null:
return $default(_that.url,_that.size,_that.sha256,_that.signature);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateAssetRead implements UpdateAssetRead {
  const _UpdateAssetRead({required this.url, required this.size, required this.sha256, required this.signature});


@override final  ReadText url;
@override final  int size;
@override final  ReadText sha256;
@override final  ReadText signature;

/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateAssetReadCopyWith<_UpdateAssetRead> get copyWith => __$UpdateAssetReadCopyWithImpl<_UpdateAssetRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateAssetRead&&(identical(other.url, url) || other.url == url)&&(identical(other.size, size) || other.size == size)&&(identical(other.sha256, sha256) || other.sha256 == sha256)&&(identical(other.signature, signature) || other.signature == signature));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url,size,sha256,signature);
}



}

/// @nodoc
abstract mixin class _$UpdateAssetReadCopyWith<$Res> implements $UpdateAssetReadCopyWith<$Res> {
  factory _$UpdateAssetReadCopyWith(_UpdateAssetRead value, $Res Function(_UpdateAssetRead) _then) = __$UpdateAssetReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText url, int size, ReadText sha256, ReadText signature
});


@override $ReadTextCopyWith<$Res> get url;@override $ReadTextCopyWith<$Res> get sha256;@override $ReadTextCopyWith<$Res> get signature;

}
/// @nodoc
class __$UpdateAssetReadCopyWithImpl<$Res>
    implements _$UpdateAssetReadCopyWith<$Res> {
  __$UpdateAssetReadCopyWithImpl(this._self, this._then);

  final _UpdateAssetRead _self;
  final $Res Function(_UpdateAssetRead) _then;

/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? url = null,Object? size = null,Object? sha256 = null,Object? signature = null,}) {
  return _then(_UpdateAssetRead(
url: null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as ReadText,size: null == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as int,sha256: null == sha256 ? _self.sha256 : sha256 // ignore: cast_nullable_to_non_nullable
as ReadText,signature: null == signature ? _self.signature : signature // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get url {

  return $ReadTextCopyWith<$Res>(_self.url, (value) {
    return _then(_self.copyWith(url: value));
  });
}/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get sha256 {

  return $ReadTextCopyWith<$Res>(_self.sha256, (value) {
    return _then(_self.copyWith(sha256: value));
  });
}/// Create a copy of UpdateAssetRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get signature {

  return $ReadTextCopyWith<$Res>(_self.signature, (value) {
    return _then(_self.copyWith(signature: value));
  });
}
}

/// @nodoc
mixin _$UpdateDetailsRead {

 UpdateSummaryRead get summary; UpdateAssetRead get installer;
/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<UpdateDetailsRead> get copyWith => _$UpdateDetailsReadCopyWithImpl<UpdateDetailsRead>(this as UpdateDetailsRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateDetailsRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateDetailsRead&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.installer, _this.installer) || other.installer == _this.installer));
}


@override
int get hashCode {
  final _this = this as UpdateDetailsRead;
  return Object.hash(runtimeType,_this.summary,_this.installer);
}



}

/// @nodoc
abstract mixin class $UpdateDetailsReadCopyWith<$Res>  {
  factory $UpdateDetailsReadCopyWith(UpdateDetailsRead value, $Res Function(UpdateDetailsRead) _then) = _$UpdateDetailsReadCopyWithImpl;
@useResult
$Res call({
 UpdateSummaryRead summary, UpdateAssetRead installer
});


$UpdateSummaryReadCopyWith<$Res> get summary;$UpdateAssetReadCopyWith<$Res> get installer;

}
/// @nodoc
class _$UpdateDetailsReadCopyWithImpl<$Res>
    implements $UpdateDetailsReadCopyWith<$Res> {
  _$UpdateDetailsReadCopyWithImpl(this._self, this._then);

  final UpdateDetailsRead _self;
  final $Res Function(UpdateDetailsRead) _then;

/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? summary = null,Object? installer = null,}) {
  return _then(UpdateDetailsRead(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummaryRead,installer: null == installer ? _self.installer : installer // ignore: cast_nullable_to_non_nullable
as UpdateAssetRead,
  ));
}
/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadCopyWith<$Res> get summary {

  return $UpdateSummaryReadCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateAssetReadCopyWith<$Res> get installer {

  return $UpdateAssetReadCopyWith<$Res>(_self.installer, (value) {
    return _then(_self.copyWith(installer: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateDetailsRead].
extension UpdateDetailsReadPatterns on UpdateDetailsRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateDetailsRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateDetailsRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateDetailsRead value)  $default,){
final _that = this;
switch (_that) {
case _UpdateDetailsRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateDetailsRead value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateDetailsRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( UpdateSummaryRead summary,  UpdateAssetRead installer)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateDetailsRead() when $default != null:
return $default(_that.summary,_that.installer);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( UpdateSummaryRead summary,  UpdateAssetRead installer)  $default,) {final _that = this;
switch (_that) {
case _UpdateDetailsRead():
return $default(_that.summary,_that.installer);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( UpdateSummaryRead summary,  UpdateAssetRead installer)?  $default,) {final _that = this;
switch (_that) {
case _UpdateDetailsRead() when $default != null:
return $default(_that.summary,_that.installer);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateDetailsRead implements UpdateDetailsRead {
  const _UpdateDetailsRead({required this.summary, required this.installer});


@override final  UpdateSummaryRead summary;
@override final  UpdateAssetRead installer;

/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateDetailsReadCopyWith<_UpdateDetailsRead> get copyWith => __$UpdateDetailsReadCopyWithImpl<_UpdateDetailsRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateDetailsRead&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.installer, installer) || other.installer == installer));
}


@override
int get hashCode {
    return Object.hash(runtimeType,summary,installer);
}



}

/// @nodoc
abstract mixin class _$UpdateDetailsReadCopyWith<$Res> implements $UpdateDetailsReadCopyWith<$Res> {
  factory _$UpdateDetailsReadCopyWith(_UpdateDetailsRead value, $Res Function(_UpdateDetailsRead) _then) = __$UpdateDetailsReadCopyWithImpl;
@override @useResult
$Res call({
 UpdateSummaryRead summary, UpdateAssetRead installer
});


@override $UpdateSummaryReadCopyWith<$Res> get summary;@override $UpdateAssetReadCopyWith<$Res> get installer;

}
/// @nodoc
class __$UpdateDetailsReadCopyWithImpl<$Res>
    implements _$UpdateDetailsReadCopyWith<$Res> {
  __$UpdateDetailsReadCopyWithImpl(this._self, this._then);

  final _UpdateDetailsRead _self;
  final $Res Function(_UpdateDetailsRead) _then;

/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? summary = null,Object? installer = null,}) {
  return _then(_UpdateDetailsRead(
summary: null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as UpdateSummaryRead,installer: null == installer ? _self.installer : installer // ignore: cast_nullable_to_non_nullable
as UpdateAssetRead,
  ));
}

/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateSummaryReadCopyWith<$Res> get summary {

  return $UpdateSummaryReadCopyWith<$Res>(_self.summary, (value) {
    return _then(_self.copyWith(summary: value));
  });
}/// Create a copy of UpdateDetailsRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateAssetReadCopyWith<$Res> get installer {

  return $UpdateAssetReadCopyWith<$Res>(_self.installer, (value) {
    return _then(_self.copyWith(installer: value));
  });
}
}

/// @nodoc
mixin _$UpdateOperationReadHeader {

 ReadText get operationId;
/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdateOperationReadHeaderCopyWith<UpdateOperationReadHeader> get copyWith => _$UpdateOperationReadHeaderCopyWithImpl<UpdateOperationReadHeader>(this as UpdateOperationReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdateOperationReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdateOperationReadHeader&&(identical(other.operationId, _this.operationId) || other.operationId == _this.operationId));
}


@override
int get hashCode {
  final _this = this as UpdateOperationReadHeader;
  return Object.hash(runtimeType,_this.operationId);
}



}

/// @nodoc
abstract mixin class $UpdateOperationReadHeaderCopyWith<$Res>  {
  factory $UpdateOperationReadHeaderCopyWith(UpdateOperationReadHeader value, $Res Function(UpdateOperationReadHeader) _then) = _$UpdateOperationReadHeaderCopyWithImpl;
@useResult
$Res call({
 ReadText operationId
});


$ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$UpdateOperationReadHeaderCopyWithImpl<$Res>
    implements $UpdateOperationReadHeaderCopyWith<$Res> {
  _$UpdateOperationReadHeaderCopyWithImpl(this._self, this._then);

  final UpdateOperationReadHeader _self;
  final $Res Function(UpdateOperationReadHeader) _then;

/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? operationId = null,}) {
  return _then(UpdateOperationReadHeader(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}


/// Adds pattern-matching-related methods to [UpdateOperationReadHeader].
extension UpdateOperationReadHeaderPatterns on UpdateOperationReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _UpdateOperationReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _UpdateOperationReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _UpdateOperationReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _UpdateOperationReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _UpdateOperationReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _UpdateOperationReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText operationId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _UpdateOperationReadHeader() when $default != null:
return $default(_that.operationId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText operationId)  $default,) {final _that = this;
switch (_that) {
case _UpdateOperationReadHeader():
return $default(_that.operationId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText operationId)?  $default,) {final _that = this;
switch (_that) {
case _UpdateOperationReadHeader() when $default != null:
return $default(_that.operationId);case _:
  return null;

}
}

}

/// @nodoc


class _UpdateOperationReadHeader implements UpdateOperationReadHeader {
  const _UpdateOperationReadHeader({required this.operationId});


@override final  ReadText operationId;

/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$UpdateOperationReadHeaderCopyWith<_UpdateOperationReadHeader> get copyWith => __$UpdateOperationReadHeaderCopyWithImpl<_UpdateOperationReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _UpdateOperationReadHeader&&(identical(other.operationId, operationId) || other.operationId == operationId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId);
}



}

/// @nodoc
abstract mixin class _$UpdateOperationReadHeaderCopyWith<$Res> implements $UpdateOperationReadHeaderCopyWith<$Res> {
  factory _$UpdateOperationReadHeaderCopyWith(_UpdateOperationReadHeader value, $Res Function(_UpdateOperationReadHeader) _then) = __$UpdateOperationReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 ReadText operationId
});


@override $ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class __$UpdateOperationReadHeaderCopyWithImpl<$Res>
    implements _$UpdateOperationReadHeaderCopyWith<$Res> {
  __$UpdateOperationReadHeaderCopyWithImpl(this._self, this._then);

  final _UpdateOperationReadHeader _self;
  final $Res Function(_UpdateOperationReadHeader) _then;

/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? operationId = null,}) {
  return _then(_UpdateOperationReadHeader(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of UpdateOperationReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc
mixin _$UpdatesReadHeader {

 int get revision;
/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpdatesReadHeaderCopyWith<UpdatesReadHeader> get copyWith => _$UpdatesReadHeaderCopyWithImpl<UpdatesReadHeader>(this as UpdatesReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as UpdatesReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is UpdatesReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as UpdatesReadHeader;
  return Object.hash(runtimeType,_this.revision);
}



}

/// @nodoc
abstract mixin class $UpdatesReadHeaderCopyWith<$Res>  {
  factory $UpdatesReadHeaderCopyWith(UpdatesReadHeader value, $Res Function(UpdatesReadHeader) _then) = _$UpdatesReadHeaderCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$UpdatesReadHeaderCopyWithImpl<$Res>
    implements $UpdatesReadHeaderCopyWith<$Res> {
  _$UpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final UpdatesReadHeader _self;
  final $Res Function(UpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [UpdatesReadHeader].
extension UpdatesReadHeaderPatterns on UpdatesReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( DisabledUpdatesReadHeader value)?  disabled,TResult Function( IdleUpdatesReadHeader value)?  idle,TResult Function( CheckingUpdatesReadHeader value)?  checking,TResult Function( UpToDateUpdatesReadHeader value)?  upToDate,TResult Function( AvailableUpdatesReadHeader value)?  available,TResult Function( DownloadingUpdatesReadHeader value)?  downloading,TResult Function( VerifyingUpdatesReadHeader value)?  verifying,TResult Function( ReadyUpdatesReadHeader value)?  ready,TResult Function( InstallerLaunchedUpdatesReadHeader value)?  installerLaunched,TResult Function( CheckFailedUpdatesReadHeader value)?  checkFailed,TResult Function( InstallFailedUpdatesReadHeader value)?  installFailed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader() when disabled != null:
return disabled(_that);case IdleUpdatesReadHeader() when idle != null:
return idle(_that);case CheckingUpdatesReadHeader() when checking != null:
return checking(_that);case UpToDateUpdatesReadHeader() when upToDate != null:
return upToDate(_that);case AvailableUpdatesReadHeader() when available != null:
return available(_that);case DownloadingUpdatesReadHeader() when downloading != null:
return downloading(_that);case VerifyingUpdatesReadHeader() when verifying != null:
return verifying(_that);case ReadyUpdatesReadHeader() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesReadHeader() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesReadHeader() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesReadHeader() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( DisabledUpdatesReadHeader value)  disabled,required TResult Function( IdleUpdatesReadHeader value)  idle,required TResult Function( CheckingUpdatesReadHeader value)  checking,required TResult Function( UpToDateUpdatesReadHeader value)  upToDate,required TResult Function( AvailableUpdatesReadHeader value)  available,required TResult Function( DownloadingUpdatesReadHeader value)  downloading,required TResult Function( VerifyingUpdatesReadHeader value)  verifying,required TResult Function( ReadyUpdatesReadHeader value)  ready,required TResult Function( InstallerLaunchedUpdatesReadHeader value)  installerLaunched,required TResult Function( CheckFailedUpdatesReadHeader value)  checkFailed,required TResult Function( InstallFailedUpdatesReadHeader value)  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader():
return disabled(_that);case IdleUpdatesReadHeader():
return idle(_that);case CheckingUpdatesReadHeader():
return checking(_that);case UpToDateUpdatesReadHeader():
return upToDate(_that);case AvailableUpdatesReadHeader():
return available(_that);case DownloadingUpdatesReadHeader():
return downloading(_that);case VerifyingUpdatesReadHeader():
return verifying(_that);case ReadyUpdatesReadHeader():
return ready(_that);case InstallerLaunchedUpdatesReadHeader():
return installerLaunched(_that);case CheckFailedUpdatesReadHeader():
return checkFailed(_that);case InstallFailedUpdatesReadHeader():
return installFailed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( DisabledUpdatesReadHeader value)?  disabled,TResult? Function( IdleUpdatesReadHeader value)?  idle,TResult? Function( CheckingUpdatesReadHeader value)?  checking,TResult? Function( UpToDateUpdatesReadHeader value)?  upToDate,TResult? Function( AvailableUpdatesReadHeader value)?  available,TResult? Function( DownloadingUpdatesReadHeader value)?  downloading,TResult? Function( VerifyingUpdatesReadHeader value)?  verifying,TResult? Function( ReadyUpdatesReadHeader value)?  ready,TResult? Function( InstallerLaunchedUpdatesReadHeader value)?  installerLaunched,TResult? Function( CheckFailedUpdatesReadHeader value)?  checkFailed,TResult? Function( InstallFailedUpdatesReadHeader value)?  installFailed,}){
final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader() when disabled != null:
return disabled(_that);case IdleUpdatesReadHeader() when idle != null:
return idle(_that);case CheckingUpdatesReadHeader() when checking != null:
return checking(_that);case UpToDateUpdatesReadHeader() when upToDate != null:
return upToDate(_that);case AvailableUpdatesReadHeader() when available != null:
return available(_that);case DownloadingUpdatesReadHeader() when downloading != null:
return downloading(_that);case VerifyingUpdatesReadHeader() when verifying != null:
return verifying(_that);case ReadyUpdatesReadHeader() when ready != null:
return ready(_that);case InstallerLaunchedUpdatesReadHeader() when installerLaunched != null:
return installerLaunched(_that);case CheckFailedUpdatesReadHeader() when checkFailed != null:
return checkFailed(_that);case InstallFailedUpdatesReadHeader() when installFailed != null:
return installFailed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  disabled,TResult Function( int revision,  int updatedAt)?  idle,TResult Function( int revision,  ReadText operationId,  int startedAt)?  checking,TResult Function( int revision,  int checkedAt)?  upToDate,TResult Function( int revision,  int checkedAt,  UpdateDetailsRead update)?  available,TResult Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)?  downloading,TResult Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)?  verifying,TResult Function( int revision,  int readyAt,  UpdateDetailsRead update)?  ready,TResult Function( int revision,  int launchedAt,  UpdateDetailsRead update)?  installerLaunched,TResult Function( int revision,  int failedAt,  SourceStateErrorRead error)?  checkFailed,TResult Function( int revision,  int failedAt,  UpdateDetailsRead update,  SourceStateErrorRead error)?  installFailed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesReadHeader() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesReadHeader() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesReadHeader() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesReadHeader() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesReadHeader() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesReadHeader() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesReadHeader() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesReadHeader() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesReadHeader() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesReadHeader() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  disabled,required TResult Function( int revision,  int updatedAt)  idle,required TResult Function( int revision,  ReadText operationId,  int startedAt)  checking,required TResult Function( int revision,  int checkedAt)  upToDate,required TResult Function( int revision,  int checkedAt,  UpdateDetailsRead update)  available,required TResult Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)  downloading,required TResult Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)  verifying,required TResult Function( int revision,  int readyAt,  UpdateDetailsRead update)  ready,required TResult Function( int revision,  int launchedAt,  UpdateDetailsRead update)  installerLaunched,required TResult Function( int revision,  int failedAt,  SourceStateErrorRead error)  checkFailed,required TResult Function( int revision,  int failedAt,  UpdateDetailsRead update,  SourceStateErrorRead error)  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader():
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesReadHeader():
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesReadHeader():
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesReadHeader():
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesReadHeader():
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesReadHeader():
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesReadHeader():
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesReadHeader():
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesReadHeader():
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesReadHeader():
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesReadHeader():
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  disabled,TResult? Function( int revision,  int updatedAt)?  idle,TResult? Function( int revision,  ReadText operationId,  int startedAt)?  checking,TResult? Function( int revision,  int checkedAt)?  upToDate,TResult? Function( int revision,  int checkedAt,  UpdateDetailsRead update)?  available,TResult? Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)?  downloading,TResult? Function( int revision,  int updatedAt,  UpdateDetailsRead update,  int downloaded,  int total)?  verifying,TResult? Function( int revision,  int readyAt,  UpdateDetailsRead update)?  ready,TResult? Function( int revision,  int launchedAt,  UpdateDetailsRead update)?  installerLaunched,TResult? Function( int revision,  int failedAt,  SourceStateErrorRead error)?  checkFailed,TResult? Function( int revision,  int failedAt,  UpdateDetailsRead update,  SourceStateErrorRead error)?  installFailed,}) {final _that = this;
switch (_that) {
case DisabledUpdatesReadHeader() when disabled != null:
return disabled(_that.revision,_that.updatedAt);case IdleUpdatesReadHeader() when idle != null:
return idle(_that.revision,_that.updatedAt);case CheckingUpdatesReadHeader() when checking != null:
return checking(_that.revision,_that.operationId,_that.startedAt);case UpToDateUpdatesReadHeader() when upToDate != null:
return upToDate(_that.revision,_that.checkedAt);case AvailableUpdatesReadHeader() when available != null:
return available(_that.revision,_that.checkedAt,_that.update);case DownloadingUpdatesReadHeader() when downloading != null:
return downloading(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case VerifyingUpdatesReadHeader() when verifying != null:
return verifying(_that.revision,_that.updatedAt,_that.update,_that.downloaded,_that.total);case ReadyUpdatesReadHeader() when ready != null:
return ready(_that.revision,_that.readyAt,_that.update);case InstallerLaunchedUpdatesReadHeader() when installerLaunched != null:
return installerLaunched(_that.revision,_that.launchedAt,_that.update);case CheckFailedUpdatesReadHeader() when checkFailed != null:
return checkFailed(_that.revision,_that.failedAt,_that.error);case InstallFailedUpdatesReadHeader() when installFailed != null:
return installFailed(_that.revision,_that.failedAt,_that.update,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class DisabledUpdatesReadHeader implements UpdatesReadHeader {
  const DisabledUpdatesReadHeader({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DisabledUpdatesReadHeaderCopyWith<DisabledUpdatesReadHeader> get copyWith => _$DisabledUpdatesReadHeaderCopyWithImpl<DisabledUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DisabledUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $DisabledUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $DisabledUpdatesReadHeaderCopyWith(DisabledUpdatesReadHeader value, $Res Function(DisabledUpdatesReadHeader) _then) = _$DisabledUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$DisabledUpdatesReadHeaderCopyWithImpl<$Res>
    implements $DisabledUpdatesReadHeaderCopyWith<$Res> {
  _$DisabledUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final DisabledUpdatesReadHeader _self;
  final $Res Function(DisabledUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(DisabledUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class IdleUpdatesReadHeader implements UpdatesReadHeader {
  const IdleUpdatesReadHeader({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$IdleUpdatesReadHeaderCopyWith<IdleUpdatesReadHeader> get copyWith => _$IdleUpdatesReadHeaderCopyWithImpl<IdleUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $IdleUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $IdleUpdatesReadHeaderCopyWith(IdleUpdatesReadHeader value, $Res Function(IdleUpdatesReadHeader) _then) = _$IdleUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$IdleUpdatesReadHeaderCopyWithImpl<$Res>
    implements $IdleUpdatesReadHeaderCopyWith<$Res> {
  _$IdleUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final IdleUpdatesReadHeader _self;
  final $Res Function(IdleUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(IdleUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class CheckingUpdatesReadHeader implements UpdatesReadHeader {
  const CheckingUpdatesReadHeader({required this.revision, required this.operationId, required this.startedAt});


@override final  int revision;
 final  ReadText operationId;
 final  int startedAt;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckingUpdatesReadHeaderCopyWith<CheckingUpdatesReadHeader> get copyWith => _$CheckingUpdatesReadHeaderCopyWithImpl<CheckingUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckingUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operationId,startedAt);
}



}

/// @nodoc
abstract mixin class $CheckingUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $CheckingUpdatesReadHeaderCopyWith(CheckingUpdatesReadHeader value, $Res Function(CheckingUpdatesReadHeader) _then) = _$CheckingUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, ReadText operationId, int startedAt
});


$ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$CheckingUpdatesReadHeaderCopyWithImpl<$Res>
    implements $CheckingUpdatesReadHeaderCopyWith<$Res> {
  _$CheckingUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final CheckingUpdatesReadHeader _self;
  final $Res Function(CheckingUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(CheckingUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class UpToDateUpdatesReadHeader implements UpdatesReadHeader {
  const UpToDateUpdatesReadHeader({required this.revision, required this.checkedAt});


@override final  int revision;
 final  int checkedAt;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UpToDateUpdatesReadHeaderCopyWith<UpToDateUpdatesReadHeader> get copyWith => _$UpToDateUpdatesReadHeaderCopyWithImpl<UpToDateUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UpToDateUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt);
}



}

/// @nodoc
abstract mixin class $UpToDateUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $UpToDateUpdatesReadHeaderCopyWith(UpToDateUpdatesReadHeader value, $Res Function(UpToDateUpdatesReadHeader) _then) = _$UpToDateUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt
});




}
/// @nodoc
class _$UpToDateUpdatesReadHeaderCopyWithImpl<$Res>
    implements $UpToDateUpdatesReadHeaderCopyWith<$Res> {
  _$UpToDateUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final UpToDateUpdatesReadHeader _self;
  final $Res Function(UpToDateUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,}) {
  return _then(UpToDateUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class AvailableUpdatesReadHeader implements UpdatesReadHeader {
  const AvailableUpdatesReadHeader({required this.revision, required this.checkedAt, required this.update});


@override final  int revision;
 final  int checkedAt;
 final  UpdateDetailsRead update;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AvailableUpdatesReadHeaderCopyWith<AvailableUpdatesReadHeader> get copyWith => _$AvailableUpdatesReadHeaderCopyWithImpl<AvailableUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AvailableUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.checkedAt, checkedAt) || other.checkedAt == checkedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,checkedAt,update);
}



}

/// @nodoc
abstract mixin class $AvailableUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $AvailableUpdatesReadHeaderCopyWith(AvailableUpdatesReadHeader value, $Res Function(AvailableUpdatesReadHeader) _then) = _$AvailableUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int checkedAt, UpdateDetailsRead update
});


$UpdateDetailsReadCopyWith<$Res> get update;

}
/// @nodoc
class _$AvailableUpdatesReadHeaderCopyWithImpl<$Res>
    implements $AvailableUpdatesReadHeaderCopyWith<$Res> {
  _$AvailableUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final AvailableUpdatesReadHeader _self;
  final $Res Function(AvailableUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? checkedAt = null,Object? update = null,}) {
  return _then(AvailableUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,checkedAt: null == checkedAt ? _self.checkedAt : checkedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class DownloadingUpdatesReadHeader implements UpdatesReadHeader {
  const DownloadingUpdatesReadHeader({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  UpdateDetailsRead update;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DownloadingUpdatesReadHeaderCopyWith<DownloadingUpdatesReadHeader> get copyWith => _$DownloadingUpdatesReadHeaderCopyWithImpl<DownloadingUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DownloadingUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}



}

/// @nodoc
abstract mixin class $DownloadingUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $DownloadingUpdatesReadHeaderCopyWith(DownloadingUpdatesReadHeader value, $Res Function(DownloadingUpdatesReadHeader) _then) = _$DownloadingUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, UpdateDetailsRead update, int downloaded, int total
});


$UpdateDetailsReadCopyWith<$Res> get update;

}
/// @nodoc
class _$DownloadingUpdatesReadHeaderCopyWithImpl<$Res>
    implements $DownloadingUpdatesReadHeaderCopyWith<$Res> {
  _$DownloadingUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final DownloadingUpdatesReadHeader _self;
  final $Res Function(DownloadingUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(DownloadingUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class VerifyingUpdatesReadHeader implements UpdatesReadHeader {
  const VerifyingUpdatesReadHeader({required this.revision, required this.updatedAt, required this.update, required this.downloaded, required this.total});


@override final  int revision;
 final  int updatedAt;
 final  UpdateDetailsRead update;
 final  int downloaded;
 final  int total;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$VerifyingUpdatesReadHeaderCopyWith<VerifyingUpdatesReadHeader> get copyWith => _$VerifyingUpdatesReadHeaderCopyWithImpl<VerifyingUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is VerifyingUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.downloaded, downloaded) || other.downloaded == downloaded)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,update,downloaded,total);
}



}

/// @nodoc
abstract mixin class $VerifyingUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $VerifyingUpdatesReadHeaderCopyWith(VerifyingUpdatesReadHeader value, $Res Function(VerifyingUpdatesReadHeader) _then) = _$VerifyingUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, UpdateDetailsRead update, int downloaded, int total
});


$UpdateDetailsReadCopyWith<$Res> get update;

}
/// @nodoc
class _$VerifyingUpdatesReadHeaderCopyWithImpl<$Res>
    implements $VerifyingUpdatesReadHeaderCopyWith<$Res> {
  _$VerifyingUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final VerifyingUpdatesReadHeader _self;
  final $Res Function(VerifyingUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? update = null,Object? downloaded = null,Object? total = null,}) {
  return _then(VerifyingUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,downloaded: null == downloaded ? _self.downloaded : downloaded // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class ReadyUpdatesReadHeader implements UpdatesReadHeader {
  const ReadyUpdatesReadHeader({required this.revision, required this.readyAt, required this.update});


@override final  int revision;
 final  int readyAt;
 final  UpdateDetailsRead update;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyUpdatesReadHeaderCopyWith<ReadyUpdatesReadHeader> get copyWith => _$ReadyUpdatesReadHeaderCopyWithImpl<ReadyUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.readyAt, readyAt) || other.readyAt == readyAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,readyAt,update);
}



}

/// @nodoc
abstract mixin class $ReadyUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $ReadyUpdatesReadHeaderCopyWith(ReadyUpdatesReadHeader value, $Res Function(ReadyUpdatesReadHeader) _then) = _$ReadyUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int readyAt, UpdateDetailsRead update
});


$UpdateDetailsReadCopyWith<$Res> get update;

}
/// @nodoc
class _$ReadyUpdatesReadHeaderCopyWithImpl<$Res>
    implements $ReadyUpdatesReadHeaderCopyWith<$Res> {
  _$ReadyUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final ReadyUpdatesReadHeader _self;
  final $Res Function(ReadyUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? readyAt = null,Object? update = null,}) {
  return _then(ReadyUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,readyAt: null == readyAt ? _self.readyAt : readyAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class InstallerLaunchedUpdatesReadHeader implements UpdatesReadHeader {
  const InstallerLaunchedUpdatesReadHeader({required this.revision, required this.launchedAt, required this.update});


@override final  int revision;
 final  int launchedAt;
 final  UpdateDetailsRead update;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallerLaunchedUpdatesReadHeaderCopyWith<InstallerLaunchedUpdatesReadHeader> get copyWith => _$InstallerLaunchedUpdatesReadHeaderCopyWithImpl<InstallerLaunchedUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallerLaunchedUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.launchedAt, launchedAt) || other.launchedAt == launchedAt)&&(identical(other.update, update) || other.update == update));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,launchedAt,update);
}



}

/// @nodoc
abstract mixin class $InstallerLaunchedUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $InstallerLaunchedUpdatesReadHeaderCopyWith(InstallerLaunchedUpdatesReadHeader value, $Res Function(InstallerLaunchedUpdatesReadHeader) _then) = _$InstallerLaunchedUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int launchedAt, UpdateDetailsRead update
});


$UpdateDetailsReadCopyWith<$Res> get update;

}
/// @nodoc
class _$InstallerLaunchedUpdatesReadHeaderCopyWithImpl<$Res>
    implements $InstallerLaunchedUpdatesReadHeaderCopyWith<$Res> {
  _$InstallerLaunchedUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final InstallerLaunchedUpdatesReadHeader _self;
  final $Res Function(InstallerLaunchedUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? launchedAt = null,Object? update = null,}) {
  return _then(InstallerLaunchedUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,launchedAt: null == launchedAt ? _self.launchedAt : launchedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}
}

/// @nodoc


class CheckFailedUpdatesReadHeader implements UpdatesReadHeader {
  const CheckFailedUpdatesReadHeader({required this.revision, required this.failedAt, required this.error});


@override final  int revision;
 final  int failedAt;
 final  SourceStateErrorRead error;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CheckFailedUpdatesReadHeaderCopyWith<CheckFailedUpdatesReadHeader> get copyWith => _$CheckFailedUpdatesReadHeaderCopyWithImpl<CheckFailedUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CheckFailedUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,error);
}



}

/// @nodoc
abstract mixin class $CheckFailedUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $CheckFailedUpdatesReadHeaderCopyWith(CheckFailedUpdatesReadHeader value, $Res Function(CheckFailedUpdatesReadHeader) _then) = _$CheckFailedUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$CheckFailedUpdatesReadHeaderCopyWithImpl<$Res>
    implements $CheckFailedUpdatesReadHeaderCopyWith<$Res> {
  _$CheckFailedUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final CheckFailedUpdatesReadHeader _self;
  final $Res Function(CheckFailedUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? error = null,}) {
  return _then(CheckFailedUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of UpdatesReadHeader
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


class InstallFailedUpdatesReadHeader implements UpdatesReadHeader {
  const InstallFailedUpdatesReadHeader({required this.revision, required this.failedAt, required this.update, required this.error});


@override final  int revision;
 final  int failedAt;
 final  UpdateDetailsRead update;
 final  SourceStateErrorRead error;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InstallFailedUpdatesReadHeaderCopyWith<InstallFailedUpdatesReadHeader> get copyWith => _$InstallFailedUpdatesReadHeaderCopyWithImpl<InstallFailedUpdatesReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InstallFailedUpdatesReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.update, update) || other.update == update)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,update,error);
}



}

/// @nodoc
abstract mixin class $InstallFailedUpdatesReadHeaderCopyWith<$Res> implements $UpdatesReadHeaderCopyWith<$Res> {
  factory $InstallFailedUpdatesReadHeaderCopyWith(InstallFailedUpdatesReadHeader value, $Res Function(InstallFailedUpdatesReadHeader) _then) = _$InstallFailedUpdatesReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, UpdateDetailsRead update, SourceStateErrorRead error
});


$UpdateDetailsReadCopyWith<$Res> get update;$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$InstallFailedUpdatesReadHeaderCopyWithImpl<$Res>
    implements $InstallFailedUpdatesReadHeaderCopyWith<$Res> {
  _$InstallFailedUpdatesReadHeaderCopyWithImpl(this._self, this._then);

  final InstallFailedUpdatesReadHeader _self;
  final $Res Function(InstallFailedUpdatesReadHeader) _then;

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? update = null,Object? error = null,}) {
  return _then(InstallFailedUpdatesReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,update: null == update ? _self.update : update // ignore: cast_nullable_to_non_nullable
as UpdateDetailsRead,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$UpdateDetailsReadCopyWith<$Res> get update {

  return $UpdateDetailsReadCopyWith<$Res>(_self.update, (value) {
    return _then(_self.copyWith(update: value));
  });
}/// Create a copy of UpdatesReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
