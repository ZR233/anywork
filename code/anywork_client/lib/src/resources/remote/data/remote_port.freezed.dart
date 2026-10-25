// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'remote_port.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RemoteDirectoryReadHeader {

 String get scopeId; ReadText get path; ReadText? get parent; ReadText? get nextCursor; int get pageEntryCount;
/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryReadHeaderCopyWith<RemoteDirectoryReadHeader> get copyWith => _$RemoteDirectoryReadHeaderCopyWithImpl<RemoteDirectoryReadHeader>(this as RemoteDirectoryReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryReadHeader&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parent, _this.parent) || other.parent == _this.parent)&&(identical(other.nextCursor, _this.nextCursor) || other.nextCursor == _this.nextCursor)&&(identical(other.pageEntryCount, _this.pageEntryCount) || other.pageEntryCount == _this.pageEntryCount));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryReadHeader;
  return Object.hash(runtimeType,_this.scopeId,_this.path,_this.parent,_this.nextCursor,_this.pageEntryCount);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryReadHeaderCopyWith<$Res>  {
  factory $RemoteDirectoryReadHeaderCopyWith(RemoteDirectoryReadHeader value, $Res Function(RemoteDirectoryReadHeader) _then) = _$RemoteDirectoryReadHeaderCopyWithImpl;
@useResult
$Res call({
 String scopeId, ReadText path, ReadText? parent, ReadText? nextCursor, int pageEntryCount
});


$ReadTextCopyWith<$Res> get path;$ReadTextCopyWith<$Res>? get parent;$ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class _$RemoteDirectoryReadHeaderCopyWithImpl<$Res>
    implements $RemoteDirectoryReadHeaderCopyWith<$Res> {
  _$RemoteDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final RemoteDirectoryReadHeader _self;
  final $Res Function(RemoteDirectoryReadHeader) _then;

/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? path = null,Object? parent = freezed,Object? nextCursor = freezed,Object? pageEntryCount = null,}) {
  return _then(RemoteDirectoryReadHeader(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as ReadText?,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,pageEntryCount: null == pageEntryCount ? _self.pageEntryCount : pageEntryCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parent {
    if (_self.parent == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parent!, (value) {
    return _then(_self.copyWith(parent: value));
  });
}/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoteDirectoryReadHeader].
extension RemoteDirectoryReadHeaderPatterns on RemoteDirectoryReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryReadHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryReadHeader value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryReadHeader value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  ReadText path,  ReadText? parent,  ReadText? nextCursor,  int pageEntryCount)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader() when $default != null:
return $default(_that.scopeId,_that.path,_that.parent,_that.nextCursor,_that.pageEntryCount);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  ReadText path,  ReadText? parent,  ReadText? nextCursor,  int pageEntryCount)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader():
return $default(_that.scopeId,_that.path,_that.parent,_that.nextCursor,_that.pageEntryCount);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  ReadText path,  ReadText? parent,  ReadText? nextCursor,  int pageEntryCount)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryReadHeader() when $default != null:
return $default(_that.scopeId,_that.path,_that.parent,_that.nextCursor,_that.pageEntryCount);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryReadHeader implements RemoteDirectoryReadHeader {
  const _RemoteDirectoryReadHeader({required this.scopeId, required this.path, required this.parent, required this.nextCursor, required this.pageEntryCount});


@override final  String scopeId;
@override final  ReadText path;
@override final  ReadText? parent;
@override final  ReadText? nextCursor;
@override final  int pageEntryCount;

/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryReadHeaderCopyWith<_RemoteDirectoryReadHeader> get copyWith => __$RemoteDirectoryReadHeaderCopyWithImpl<_RemoteDirectoryReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryReadHeader&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.path, path) || other.path == path)&&(identical(other.parent, parent) || other.parent == parent)&&(identical(other.nextCursor, nextCursor) || other.nextCursor == nextCursor)&&(identical(other.pageEntryCount, pageEntryCount) || other.pageEntryCount == pageEntryCount));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,path,parent,nextCursor,pageEntryCount);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryReadHeaderCopyWith<$Res> implements $RemoteDirectoryReadHeaderCopyWith<$Res> {
  factory _$RemoteDirectoryReadHeaderCopyWith(_RemoteDirectoryReadHeader value, $Res Function(_RemoteDirectoryReadHeader) _then) = __$RemoteDirectoryReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, ReadText path, ReadText? parent, ReadText? nextCursor, int pageEntryCount
});


@override $ReadTextCopyWith<$Res> get path;@override $ReadTextCopyWith<$Res>? get parent;@override $ReadTextCopyWith<$Res>? get nextCursor;

}
/// @nodoc
class __$RemoteDirectoryReadHeaderCopyWithImpl<$Res>
    implements _$RemoteDirectoryReadHeaderCopyWith<$Res> {
  __$RemoteDirectoryReadHeaderCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryReadHeader _self;
  final $Res Function(_RemoteDirectoryReadHeader) _then;

/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? path = null,Object? parent = freezed,Object? nextCursor = freezed,Object? pageEntryCount = null,}) {
  return _then(_RemoteDirectoryReadHeader(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,parent: freezed == parent ? _self.parent : parent // ignore: cast_nullable_to_non_nullable
as ReadText?,nextCursor: freezed == nextCursor ? _self.nextCursor : nextCursor // ignore: cast_nullable_to_non_nullable
as ReadText?,pageEntryCount: null == pageEntryCount ? _self.pageEntryCount : pageEntryCount // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get parent {
    if (_self.parent == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.parent!, (value) {
    return _then(_self.copyWith(parent: value));
  });
}/// Create a copy of RemoteDirectoryReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res>? get nextCursor {
    if (_self.nextCursor == null) {
    return null;
  }

  return $ReadTextCopyWith<$Res>(_self.nextCursor!, (value) {
    return _then(_self.copyWith(nextCursor: value));
  });
}
}

/// @nodoc
mixin _$RemoteDirectoryEntryRead {

 ReadText get name; ReadText get path; bool get isDirectory; bool get isSymlink;
/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryEntryReadCopyWith<RemoteDirectoryEntryRead> get copyWith => _$RemoteDirectoryEntryReadCopyWithImpl<RemoteDirectoryEntryRead>(this as RemoteDirectoryEntryRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryEntryRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryEntryRead&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.isDirectory, _this.isDirectory) || other.isDirectory == _this.isDirectory)&&(identical(other.isSymlink, _this.isSymlink) || other.isSymlink == _this.isSymlink));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryEntryRead;
  return Object.hash(runtimeType,_this.name,_this.path,_this.isDirectory,_this.isSymlink);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryEntryReadCopyWith<$Res>  {
  factory $RemoteDirectoryEntryReadCopyWith(RemoteDirectoryEntryRead value, $Res Function(RemoteDirectoryEntryRead) _then) = _$RemoteDirectoryEntryReadCopyWithImpl;
@useResult
$Res call({
 ReadText name, ReadText path, bool isDirectory, bool isSymlink
});


$ReadTextCopyWith<$Res> get name;$ReadTextCopyWith<$Res> get path;

}
/// @nodoc
class _$RemoteDirectoryEntryReadCopyWithImpl<$Res>
    implements $RemoteDirectoryEntryReadCopyWith<$Res> {
  _$RemoteDirectoryEntryReadCopyWithImpl(this._self, this._then);

  final RemoteDirectoryEntryRead _self;
  final $Res Function(RemoteDirectoryEntryRead) _then;

/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? name = null,Object? path = null,Object? isDirectory = null,Object? isSymlink = null,}) {
  return _then(RemoteDirectoryEntryRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get path {

  return $ReadTextCopyWith<$Res>(_self.path, (value) {
    return _then(_self.copyWith(path: value));
  });
}
}


/// Adds pattern-matching-related methods to [RemoteDirectoryEntryRead].
extension RemoteDirectoryEntryReadPatterns on RemoteDirectoryEntryRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryEntryRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryEntryRead value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryEntryRead value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText name,  ReadText path,  bool isDirectory,  bool isSymlink)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead() when $default != null:
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText name,  ReadText path,  bool isDirectory,  bool isSymlink)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead():
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText name,  ReadText path,  bool isDirectory,  bool isSymlink)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryRead() when $default != null:
return $default(_that.name,_that.path,_that.isDirectory,_that.isSymlink);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryEntryRead implements RemoteDirectoryEntryRead {
  const _RemoteDirectoryEntryRead({required this.name, required this.path, required this.isDirectory, required this.isSymlink});


@override final  ReadText name;
@override final  ReadText path;
@override final  bool isDirectory;
@override final  bool isSymlink;

/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryEntryReadCopyWith<_RemoteDirectoryEntryRead> get copyWith => __$RemoteDirectoryEntryReadCopyWithImpl<_RemoteDirectoryEntryRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryEntryRead&&(identical(other.name, name) || other.name == name)&&(identical(other.path, path) || other.path == path)&&(identical(other.isDirectory, isDirectory) || other.isDirectory == isDirectory)&&(identical(other.isSymlink, isSymlink) || other.isSymlink == isSymlink));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,path,isDirectory,isSymlink);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryEntryReadCopyWith<$Res> implements $RemoteDirectoryEntryReadCopyWith<$Res> {
  factory _$RemoteDirectoryEntryReadCopyWith(_RemoteDirectoryEntryRead value, $Res Function(_RemoteDirectoryEntryRead) _then) = __$RemoteDirectoryEntryReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText name, ReadText path, bool isDirectory, bool isSymlink
});


@override $ReadTextCopyWith<$Res> get name;@override $ReadTextCopyWith<$Res> get path;

}
/// @nodoc
class __$RemoteDirectoryEntryReadCopyWithImpl<$Res>
    implements _$RemoteDirectoryEntryReadCopyWith<$Res> {
  __$RemoteDirectoryEntryReadCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryEntryRead _self;
  final $Res Function(_RemoteDirectoryEntryRead) _then;

/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? path = null,Object? isDirectory = null,Object? isSymlink = null,}) {
  return _then(_RemoteDirectoryEntryRead(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as ReadText,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as ReadText,isDirectory: null == isDirectory ? _self.isDirectory : isDirectory // ignore: cast_nullable_to_non_nullable
as bool,isSymlink: null == isSymlink ? _self.isSymlink : isSymlink // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of RemoteDirectoryEntryRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get name {

  return $ReadTextCopyWith<$Res>(_self.name, (value) {
    return _then(_self.copyWith(name: value));
  });
}/// Create a copy of RemoteDirectoryEntryRead
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
mixin _$RemoteDirectoryEntryPage {

 String get scopeId; int get offset; List<RemoteDirectoryEntryRead> get items; int? get nextOffset;
/// Create a copy of RemoteDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteDirectoryEntryPageCopyWith<RemoteDirectoryEntryPage> get copyWith => _$RemoteDirectoryEntryPageCopyWithImpl<RemoteDirectoryEntryPage>(this as RemoteDirectoryEntryPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RemoteDirectoryEntryPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteDirectoryEntryPage&&(identical(other.scopeId, _this.scopeId) || other.scopeId == _this.scopeId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as RemoteDirectoryEntryPage;
  return Object.hash(runtimeType,_this.scopeId,_this.offset,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $RemoteDirectoryEntryPageCopyWith<$Res>  {
  factory $RemoteDirectoryEntryPageCopyWith(RemoteDirectoryEntryPage value, $Res Function(RemoteDirectoryEntryPage) _then) = _$RemoteDirectoryEntryPageCopyWithImpl;
@useResult
$Res call({
 String scopeId, int offset, List<RemoteDirectoryEntryRead> items, int? nextOffset
});




}
/// @nodoc
class _$RemoteDirectoryEntryPageCopyWithImpl<$Res>
    implements $RemoteDirectoryEntryPageCopyWith<$Res> {
  _$RemoteDirectoryEntryPageCopyWithImpl(this._self, this._then);

  final RemoteDirectoryEntryPage _self;
  final $Res Function(RemoteDirectoryEntryPage) _then;

/// Create a copy of RemoteDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? scopeId = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(RemoteDirectoryEntryPage(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [RemoteDirectoryEntryPage].
extension RemoteDirectoryEntryPagePatterns on RemoteDirectoryEntryPage {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RemoteDirectoryEntryPage value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RemoteDirectoryEntryPage value)  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RemoteDirectoryEntryPage value)?  $default,){
final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String scopeId,  int offset,  List<RemoteDirectoryEntryRead> items,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage() when $default != null:
return $default(_that.scopeId,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String scopeId,  int offset,  List<RemoteDirectoryEntryRead> items,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage():
return $default(_that.scopeId,_that.offset,_that.items,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String scopeId,  int offset,  List<RemoteDirectoryEntryRead> items,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _RemoteDirectoryEntryPage() when $default != null:
return $default(_that.scopeId,_that.offset,_that.items,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _RemoteDirectoryEntryPage implements RemoteDirectoryEntryPage {
  const _RemoteDirectoryEntryPage({required this.scopeId, required this.offset, required  List<RemoteDirectoryEntryRead> items, required this.nextOffset}): _items = items;


@override final  String scopeId;
@override final  int offset;
 final  List<RemoteDirectoryEntryRead> _items;
@override List<RemoteDirectoryEntryRead> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

@override final  int? nextOffset;

/// Create a copy of RemoteDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RemoteDirectoryEntryPageCopyWith<_RemoteDirectoryEntryPage> get copyWith => __$RemoteDirectoryEntryPageCopyWithImpl<_RemoteDirectoryEntryPage>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RemoteDirectoryEntryPage&&(identical(other.scopeId, scopeId) || other.scopeId == scopeId)&&(identical(other.offset, offset) || other.offset == offset)&&const DeepCollectionEquality().equals(other.items, _items)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,scopeId,offset,const DeepCollectionEquality().hash(_items),nextOffset);
}



}

/// @nodoc
abstract mixin class _$RemoteDirectoryEntryPageCopyWith<$Res> implements $RemoteDirectoryEntryPageCopyWith<$Res> {
  factory _$RemoteDirectoryEntryPageCopyWith(_RemoteDirectoryEntryPage value, $Res Function(_RemoteDirectoryEntryPage) _then) = __$RemoteDirectoryEntryPageCopyWithImpl;
@override @useResult
$Res call({
 String scopeId, int offset, List<RemoteDirectoryEntryRead> items, int? nextOffset
});




}
/// @nodoc
class __$RemoteDirectoryEntryPageCopyWithImpl<$Res>
    implements _$RemoteDirectoryEntryPageCopyWith<$Res> {
  __$RemoteDirectoryEntryPageCopyWithImpl(this._self, this._then);

  final _RemoteDirectoryEntryPage _self;
  final $Res Function(_RemoteDirectoryEntryPage) _then;

/// Create a copy of RemoteDirectoryEntryPage
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? scopeId = null,Object? offset = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(_RemoteDirectoryEntryPage(
scopeId: null == scopeId ? _self.scopeId : scopeId // ignore: cast_nullable_to_non_nullable
as String,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<RemoteDirectoryEntryRead>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
