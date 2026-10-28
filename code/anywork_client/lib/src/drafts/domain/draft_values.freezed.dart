// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'draft_values.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AttachmentMetadata {

 String get id; AttachmentModality get modality; String get mediaType; String get filename; int get byteSize; int? get width; int? get height;
/// Create a copy of AttachmentMetadata
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttachmentMetadataCopyWith<AttachmentMetadata> get copyWith => _$AttachmentMetadataCopyWithImpl<AttachmentMetadata>(this as AttachmentMetadata, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttachmentMetadata;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentMetadata&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.modality, _this.modality) || other.modality == _this.modality)&&(identical(other.mediaType, _this.mediaType) || other.mediaType == _this.mediaType)&&(identical(other.filename, _this.filename) || other.filename == _this.filename)&&(identical(other.byteSize, _this.byteSize) || other.byteSize == _this.byteSize)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height));
}


@override
int get hashCode {
  final _this = this as AttachmentMetadata;
  return Object.hash(runtimeType,_this.id,_this.modality,_this.mediaType,_this.filename,_this.byteSize,_this.width,_this.height);
}



}

/// @nodoc
abstract mixin class $AttachmentMetadataCopyWith<$Res>  {
  factory $AttachmentMetadataCopyWith(AttachmentMetadata value, $Res Function(AttachmentMetadata) _then) = _$AttachmentMetadataCopyWithImpl;
@useResult
$Res call({
 String id, AttachmentModality modality, String mediaType, String filename, int byteSize, int? width, int? height
});




}
/// @nodoc
class _$AttachmentMetadataCopyWithImpl<$Res>
    implements $AttachmentMetadataCopyWith<$Res> {
  _$AttachmentMetadataCopyWithImpl(this._self, this._then);

  final AttachmentMetadata _self;
  final $Res Function(AttachmentMetadata) _then;

/// Create a copy of AttachmentMetadata
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? modality = null,Object? mediaType = null,Object? filename = null,Object? byteSize = null,Object? width = freezed,Object? height = freezed,}) {
  return _then(AttachmentMetadata(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as AttachmentModality,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [AttachmentMetadata].
extension AttachmentMetadataPatterns on AttachmentMetadata {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttachmentMetadata value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttachmentMetadata() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttachmentMetadata value)  $default,){
final _that = this;
switch (_that) {
case _AttachmentMetadata():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttachmentMetadata value)?  $default,){
final _that = this;
switch (_that) {
case _AttachmentMetadata() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  AttachmentModality modality,  String mediaType,  String filename,  int byteSize,  int? width,  int? height)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttachmentMetadata() when $default != null:
return $default(_that.id,_that.modality,_that.mediaType,_that.filename,_that.byteSize,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  AttachmentModality modality,  String mediaType,  String filename,  int byteSize,  int? width,  int? height)  $default,) {final _that = this;
switch (_that) {
case _AttachmentMetadata():
return $default(_that.id,_that.modality,_that.mediaType,_that.filename,_that.byteSize,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  AttachmentModality modality,  String mediaType,  String filename,  int byteSize,  int? width,  int? height)?  $default,) {final _that = this;
switch (_that) {
case _AttachmentMetadata() when $default != null:
return $default(_that.id,_that.modality,_that.mediaType,_that.filename,_that.byteSize,_that.width,_that.height);case _:
  return null;

}
}

}

/// @nodoc


class _AttachmentMetadata implements AttachmentMetadata {
  const _AttachmentMetadata({required this.id, required this.modality, required this.mediaType, required this.filename, required this.byteSize, this.width, this.height});


@override final  String id;
@override final  AttachmentModality modality;
@override final  String mediaType;
@override final  String filename;
@override final  int byteSize;
@override final  int? width;
@override final  int? height;

/// Create a copy of AttachmentMetadata
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttachmentMetadataCopyWith<_AttachmentMetadata> get copyWith => __$AttachmentMetadataCopyWithImpl<_AttachmentMetadata>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttachmentMetadata&&(identical(other.id, id) || other.id == id)&&(identical(other.modality, modality) || other.modality == modality)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.filename, filename) || other.filename == filename)&&(identical(other.byteSize, byteSize) || other.byteSize == byteSize)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,modality,mediaType,filename,byteSize,width,height);
}



}

/// @nodoc
abstract mixin class _$AttachmentMetadataCopyWith<$Res> implements $AttachmentMetadataCopyWith<$Res> {
  factory _$AttachmentMetadataCopyWith(_AttachmentMetadata value, $Res Function(_AttachmentMetadata) _then) = __$AttachmentMetadataCopyWithImpl;
@override @useResult
$Res call({
 String id, AttachmentModality modality, String mediaType, String filename, int byteSize, int? width, int? height
});




}
/// @nodoc
class __$AttachmentMetadataCopyWithImpl<$Res>
    implements _$AttachmentMetadataCopyWith<$Res> {
  __$AttachmentMetadataCopyWithImpl(this._self, this._then);

  final _AttachmentMetadata _self;
  final $Res Function(_AttachmentMetadata) _then;

/// Create a copy of AttachmentMetadata
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? modality = null,Object? mediaType = null,Object? filename = null,Object? byteSize = null,Object? width = freezed,Object? height = freezed,}) {
  return _then(_AttachmentMetadata(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as AttachmentModality,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,filename: null == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$AttachmentAdmissionContext {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentAdmissionContext);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AttachmentAdmissionContextCopyWith<$Res>  {
$AttachmentAdmissionContextCopyWith(AttachmentAdmissionContext _, $Res Function(AttachmentAdmissionContext) __);
}


/// Adds pattern-matching-related methods to [AttachmentAdmissionContext].
extension AttachmentAdmissionContextPatterns on AttachmentAdmissionContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ExistingThreadAttachmentAdmissionContext value)?  existingThread,TResult Function( NewThreadAttachmentAdmissionContext value)?  newThread,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext() when existingThread != null:
return existingThread(_that);case NewThreadAttachmentAdmissionContext() when newThread != null:
return newThread(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ExistingThreadAttachmentAdmissionContext value)  existingThread,required TResult Function( NewThreadAttachmentAdmissionContext value)  newThread,}){
final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext():
return existingThread(_that);case NewThreadAttachmentAdmissionContext():
return newThread(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ExistingThreadAttachmentAdmissionContext value)?  existingThread,TResult? Function( NewThreadAttachmentAdmissionContext value)?  newThread,}){
final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext() when existingThread != null:
return existingThread(_that);case NewThreadAttachmentAdmissionContext() when newThread != null:
return newThread(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String threadId)?  existingThread,TResult Function( ModelSelection route)?  newThread,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext() when existingThread != null:
return existingThread(_that.threadId);case NewThreadAttachmentAdmissionContext() when newThread != null:
return newThread(_that.route);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String threadId)  existingThread,required TResult Function( ModelSelection route)  newThread,}) {final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext():
return existingThread(_that.threadId);case NewThreadAttachmentAdmissionContext():
return newThread(_that.route);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String threadId)?  existingThread,TResult? Function( ModelSelection route)?  newThread,}) {final _that = this;
switch (_that) {
case ExistingThreadAttachmentAdmissionContext() when existingThread != null:
return existingThread(_that.threadId);case NewThreadAttachmentAdmissionContext() when newThread != null:
return newThread(_that.route);case _:
  return null;

}
}

}

/// @nodoc


class ExistingThreadAttachmentAdmissionContext implements AttachmentAdmissionContext {
  const ExistingThreadAttachmentAdmissionContext(this.threadId);


 final  String threadId;

/// Create a copy of AttachmentAdmissionContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ExistingThreadAttachmentAdmissionContextCopyWith<ExistingThreadAttachmentAdmissionContext> get copyWith => _$ExistingThreadAttachmentAdmissionContextCopyWithImpl<ExistingThreadAttachmentAdmissionContext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ExistingThreadAttachmentAdmissionContext&&(identical(other.threadId, threadId) || other.threadId == threadId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId);
}



}

/// @nodoc
abstract mixin class $ExistingThreadAttachmentAdmissionContextCopyWith<$Res> implements $AttachmentAdmissionContextCopyWith<$Res> {
  factory $ExistingThreadAttachmentAdmissionContextCopyWith(ExistingThreadAttachmentAdmissionContext value, $Res Function(ExistingThreadAttachmentAdmissionContext) _then) = _$ExistingThreadAttachmentAdmissionContextCopyWithImpl;
@useResult
$Res call({
 String threadId
});




}
/// @nodoc
class _$ExistingThreadAttachmentAdmissionContextCopyWithImpl<$Res>
    implements $ExistingThreadAttachmentAdmissionContextCopyWith<$Res> {
  _$ExistingThreadAttachmentAdmissionContextCopyWithImpl(this._self, this._then);

  final ExistingThreadAttachmentAdmissionContext _self;
  final $Res Function(ExistingThreadAttachmentAdmissionContext) _then;

/// Create a copy of AttachmentAdmissionContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? threadId = null,}) {
  return _then(ExistingThreadAttachmentAdmissionContext(
null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class NewThreadAttachmentAdmissionContext implements AttachmentAdmissionContext {
  const NewThreadAttachmentAdmissionContext({required this.route});


 final  ModelSelection route;

/// Create a copy of AttachmentAdmissionContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewThreadAttachmentAdmissionContextCopyWith<NewThreadAttachmentAdmissionContext> get copyWith => _$NewThreadAttachmentAdmissionContextCopyWithImpl<NewThreadAttachmentAdmissionContext>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is NewThreadAttachmentAdmissionContext&&(identical(other.route, route) || other.route == route));
}


@override
int get hashCode {
    return Object.hash(runtimeType,route);
}



}

/// @nodoc
abstract mixin class $NewThreadAttachmentAdmissionContextCopyWith<$Res> implements $AttachmentAdmissionContextCopyWith<$Res> {
  factory $NewThreadAttachmentAdmissionContextCopyWith(NewThreadAttachmentAdmissionContext value, $Res Function(NewThreadAttachmentAdmissionContext) _then) = _$NewThreadAttachmentAdmissionContextCopyWithImpl;
@useResult
$Res call({
 ModelSelection route
});


$ModelSelectionCopyWith<$Res> get route;

}
/// @nodoc
class _$NewThreadAttachmentAdmissionContextCopyWithImpl<$Res>
    implements $NewThreadAttachmentAdmissionContextCopyWith<$Res> {
  _$NewThreadAttachmentAdmissionContextCopyWithImpl(this._self, this._then);

  final NewThreadAttachmentAdmissionContext _self;
  final $Res Function(NewThreadAttachmentAdmissionContext) _then;

/// Create a copy of AttachmentAdmissionContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? route = null,}) {
  return _then(NewThreadAttachmentAdmissionContext(
route: null == route ? _self.route : route // ignore: cast_nullable_to_non_nullable
as ModelSelection,
  ));
}

/// Create a copy of AttachmentAdmissionContext
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ModelSelectionCopyWith<$Res> get route {

  return $ModelSelectionCopyWith<$Res>(_self.route, (value) {
    return _then(_self.copyWith(route: value));
  });
}
}

/// @nodoc
mixin _$AttachmentDraftSource {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentDraftSource);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AttachmentDraftSourceCopyWith<$Res>  {
$AttachmentDraftSourceCopyWith(AttachmentDraftSource _, $Res Function(AttachmentDraftSource) __);
}


/// Adds pattern-matching-related methods to [AttachmentDraftSource].
extension AttachmentDraftSourcePatterns on AttachmentDraftSource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LocalFileAttachmentDraftSource value)?  localFile,TResult Function( RemoteUrlAttachmentDraftSource value)?  remoteUrl,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource() when localFile != null:
return localFile(_that);case RemoteUrlAttachmentDraftSource() when remoteUrl != null:
return remoteUrl(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LocalFileAttachmentDraftSource value)  localFile,required TResult Function( RemoteUrlAttachmentDraftSource value)  remoteUrl,}){
final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource():
return localFile(_that);case RemoteUrlAttachmentDraftSource():
return remoteUrl(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LocalFileAttachmentDraftSource value)?  localFile,TResult? Function( RemoteUrlAttachmentDraftSource value)?  remoteUrl,}){
final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource() when localFile != null:
return localFile(_that);case RemoteUrlAttachmentDraftSource() when remoteUrl != null:
return remoteUrl(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String path)?  localFile,TResult Function( String url,  String? filename)?  remoteUrl,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource() when localFile != null:
return localFile(_that.path);case RemoteUrlAttachmentDraftSource() when remoteUrl != null:
return remoteUrl(_that.url,_that.filename);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String path)  localFile,required TResult Function( String url,  String? filename)  remoteUrl,}) {final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource():
return localFile(_that.path);case RemoteUrlAttachmentDraftSource():
return remoteUrl(_that.url,_that.filename);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String path)?  localFile,TResult? Function( String url,  String? filename)?  remoteUrl,}) {final _that = this;
switch (_that) {
case LocalFileAttachmentDraftSource() when localFile != null:
return localFile(_that.path);case RemoteUrlAttachmentDraftSource() when remoteUrl != null:
return remoteUrl(_that.url,_that.filename);case _:
  return null;

}
}

}

/// @nodoc


class LocalFileAttachmentDraftSource implements AttachmentDraftSource {
  const LocalFileAttachmentDraftSource(this.path);


 final  String path;

/// Create a copy of AttachmentDraftSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LocalFileAttachmentDraftSourceCopyWith<LocalFileAttachmentDraftSource> get copyWith => _$LocalFileAttachmentDraftSourceCopyWithImpl<LocalFileAttachmentDraftSource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LocalFileAttachmentDraftSource&&(identical(other.path, path) || other.path == path));
}


@override
int get hashCode {
    return Object.hash(runtimeType,path);
}



}

/// @nodoc
abstract mixin class $LocalFileAttachmentDraftSourceCopyWith<$Res> implements $AttachmentDraftSourceCopyWith<$Res> {
  factory $LocalFileAttachmentDraftSourceCopyWith(LocalFileAttachmentDraftSource value, $Res Function(LocalFileAttachmentDraftSource) _then) = _$LocalFileAttachmentDraftSourceCopyWithImpl;
@useResult
$Res call({
 String path
});




}
/// @nodoc
class _$LocalFileAttachmentDraftSourceCopyWithImpl<$Res>
    implements $LocalFileAttachmentDraftSourceCopyWith<$Res> {
  _$LocalFileAttachmentDraftSourceCopyWithImpl(this._self, this._then);

  final LocalFileAttachmentDraftSource _self;
  final $Res Function(LocalFileAttachmentDraftSource) _then;

/// Create a copy of AttachmentDraftSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? path = null,}) {
  return _then(LocalFileAttachmentDraftSource(
null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class RemoteUrlAttachmentDraftSource implements AttachmentDraftSource {
  const RemoteUrlAttachmentDraftSource(this.url, {this.filename});


 final  String url;
 final  String? filename;

/// Create a copy of AttachmentDraftSource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RemoteUrlAttachmentDraftSourceCopyWith<RemoteUrlAttachmentDraftSource> get copyWith => _$RemoteUrlAttachmentDraftSourceCopyWithImpl<RemoteUrlAttachmentDraftSource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RemoteUrlAttachmentDraftSource&&(identical(other.url, url) || other.url == url)&&(identical(other.filename, filename) || other.filename == filename));
}


@override
int get hashCode {
    return Object.hash(runtimeType,url,filename);
}



}

/// @nodoc
abstract mixin class $RemoteUrlAttachmentDraftSourceCopyWith<$Res> implements $AttachmentDraftSourceCopyWith<$Res> {
  factory $RemoteUrlAttachmentDraftSourceCopyWith(RemoteUrlAttachmentDraftSource value, $Res Function(RemoteUrlAttachmentDraftSource) _then) = _$RemoteUrlAttachmentDraftSourceCopyWithImpl;
@useResult
$Res call({
 String url, String? filename
});




}
/// @nodoc
class _$RemoteUrlAttachmentDraftSourceCopyWithImpl<$Res>
    implements $RemoteUrlAttachmentDraftSourceCopyWith<$Res> {
  _$RemoteUrlAttachmentDraftSourceCopyWithImpl(this._self, this._then);

  final RemoteUrlAttachmentDraftSource _self;
  final $Res Function(RemoteUrlAttachmentDraftSource) _then;

/// Create a copy of AttachmentDraftSource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? url = null,Object? filename = freezed,}) {
  return _then(RemoteUrlAttachmentDraftSource(
null == url ? _self.url : url // ignore: cast_nullable_to_non_nullable
as String,filename: freezed == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$StudioPromptInput {


/// Create a copy of StudioPromptInput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StudioPromptInputCopyWith<StudioPromptInput> get copyWith => _$StudioPromptInputCopyWithImpl<StudioPromptInput>(this as StudioPromptInput, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StudioPromptInput;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StudioPromptInput&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.attachmentDraftIds, _this.attachmentDraftIds));
}


@override
int get hashCode {
  final _this = this as StudioPromptInput;
  return Object.hash(runtimeType,_this.inputId,_this.text,const DeepCollectionEquality().hash(_this.attachmentDraftIds));
}



}

/// @nodoc
abstract mixin class $StudioPromptInputCopyWith<$Res>  {
  factory $StudioPromptInputCopyWith(StudioPromptInput value, $Res Function(StudioPromptInput) _then) = _$StudioPromptInputCopyWithImpl;
@useResult
$Res call({
 String inputId, String text, List<String> attachmentDraftIds
});




}
/// @nodoc
class _$StudioPromptInputCopyWithImpl<$Res>
    implements $StudioPromptInputCopyWith<$Res> {
  _$StudioPromptInputCopyWithImpl(this._self, this._then);

  final StudioPromptInput _self;
  final $Res Function(StudioPromptInput) _then;

/// Create a copy of StudioPromptInput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? inputId = null,Object? text = null,Object? attachmentDraftIds = null,}) {
  return _then(StudioPromptInput(
inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,attachmentDraftIds: null == attachmentDraftIds ? _self.attachmentDraftIds : attachmentDraftIds // ignore: cast_nullable_to_non_nullable
as List<String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StudioPromptInput].
extension StudioPromptInputPatterns on StudioPromptInput {
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
mixin _$DraftSubmissionState {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DraftSubmissionState);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $DraftSubmissionStateCopyWith<$Res>  {
$DraftSubmissionStateCopyWith(DraftSubmissionState _, $Res Function(DraftSubmissionState) __);
}


/// Adds pattern-matching-related methods to [DraftSubmissionState].
extension DraftSubmissionStatePatterns on DraftSubmissionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( IdleDraftSubmission value)?  idle,TResult Function( SubmittingDraft value)?  submitting,TResult Function( FailedDraftSubmission value)?  failed,TResult Function( UnknownDraftSubmission value)?  unknownOutcome,required TResult orElse(),}){
final _that = this;
switch (_that) {
case IdleDraftSubmission() when idle != null:
return idle(_that);case SubmittingDraft() when submitting != null:
return submitting(_that);case FailedDraftSubmission() when failed != null:
return failed(_that);case UnknownDraftSubmission() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( IdleDraftSubmission value)  idle,required TResult Function( SubmittingDraft value)  submitting,required TResult Function( FailedDraftSubmission value)  failed,required TResult Function( UnknownDraftSubmission value)  unknownOutcome,}){
final _that = this;
switch (_that) {
case IdleDraftSubmission():
return idle(_that);case SubmittingDraft():
return submitting(_that);case FailedDraftSubmission():
return failed(_that);case UnknownDraftSubmission():
return unknownOutcome(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( IdleDraftSubmission value)?  idle,TResult? Function( SubmittingDraft value)?  submitting,TResult? Function( FailedDraftSubmission value)?  failed,TResult? Function( UnknownDraftSubmission value)?  unknownOutcome,}){
final _that = this;
switch (_that) {
case IdleDraftSubmission() when idle != null:
return idle(_that);case SubmittingDraft() when submitting != null:
return submitting(_that);case FailedDraftSubmission() when failed != null:
return failed(_that);case UnknownDraftSubmission() when unknownOutcome != null:
return unknownOutcome(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  idle,TResult Function( OperationId operationId,  String inputId)?  submitting,TResult Function( OperationId? operationId,  String? inputId,  StudioFailure error)?  failed,TResult Function( OperationId operationId,  String inputId,  StudioFailure error)?  unknownOutcome,required TResult orElse(),}) {final _that = this;
switch (_that) {
case IdleDraftSubmission() when idle != null:
return idle();case SubmittingDraft() when submitting != null:
return submitting(_that.operationId,_that.inputId);case FailedDraftSubmission() when failed != null:
return failed(_that.operationId,_that.inputId,_that.error);case UnknownDraftSubmission() when unknownOutcome != null:
return unknownOutcome(_that.operationId,_that.inputId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  idle,required TResult Function( OperationId operationId,  String inputId)  submitting,required TResult Function( OperationId? operationId,  String? inputId,  StudioFailure error)  failed,required TResult Function( OperationId operationId,  String inputId,  StudioFailure error)  unknownOutcome,}) {final _that = this;
switch (_that) {
case IdleDraftSubmission():
return idle();case SubmittingDraft():
return submitting(_that.operationId,_that.inputId);case FailedDraftSubmission():
return failed(_that.operationId,_that.inputId,_that.error);case UnknownDraftSubmission():
return unknownOutcome(_that.operationId,_that.inputId,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  idle,TResult? Function( OperationId operationId,  String inputId)?  submitting,TResult? Function( OperationId? operationId,  String? inputId,  StudioFailure error)?  failed,TResult? Function( OperationId operationId,  String inputId,  StudioFailure error)?  unknownOutcome,}) {final _that = this;
switch (_that) {
case IdleDraftSubmission() when idle != null:
return idle();case SubmittingDraft() when submitting != null:
return submitting(_that.operationId,_that.inputId);case FailedDraftSubmission() when failed != null:
return failed(_that.operationId,_that.inputId,_that.error);case UnknownDraftSubmission() when unknownOutcome != null:
return unknownOutcome(_that.operationId,_that.inputId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class IdleDraftSubmission implements DraftSubmissionState {
  const IdleDraftSubmission();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is IdleDraftSubmission);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class SubmittingDraft implements DraftSubmissionState {
  const SubmittingDraft({required this.operationId, required this.inputId});


 final  OperationId operationId;
 final  String inputId;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SubmittingDraftCopyWith<SubmittingDraft> get copyWith => _$SubmittingDraftCopyWithImpl<SubmittingDraft>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SubmittingDraft&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.inputId, inputId) || other.inputId == inputId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,inputId);
}



}

/// @nodoc
abstract mixin class $SubmittingDraftCopyWith<$Res> implements $DraftSubmissionStateCopyWith<$Res> {
  factory $SubmittingDraftCopyWith(SubmittingDraft value, $Res Function(SubmittingDraft) _then) = _$SubmittingDraftCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String inputId
});


$OperationIdCopyWith<$Res> get operationId;

}
/// @nodoc
class _$SubmittingDraftCopyWithImpl<$Res>
    implements $SubmittingDraftCopyWith<$Res> {
  _$SubmittingDraftCopyWithImpl(this._self, this._then);

  final SubmittingDraft _self;
  final $Res Function(SubmittingDraft) _then;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? inputId = null,}) {
  return _then(SubmittingDraft(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class FailedDraftSubmission implements DraftSubmissionState {
  const FailedDraftSubmission({required this.operationId, required this.inputId, required this.error});


 final  OperationId? operationId;
 final  String? inputId;
 final  StudioFailure error;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedDraftSubmissionCopyWith<FailedDraftSubmission> get copyWith => _$FailedDraftSubmissionCopyWithImpl<FailedDraftSubmission>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedDraftSubmission&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,inputId,error);
}



}

/// @nodoc
abstract mixin class $FailedDraftSubmissionCopyWith<$Res> implements $DraftSubmissionStateCopyWith<$Res> {
  factory $FailedDraftSubmissionCopyWith(FailedDraftSubmission value, $Res Function(FailedDraftSubmission) _then) = _$FailedDraftSubmissionCopyWithImpl;
@useResult
$Res call({
 OperationId? operationId, String? inputId, StudioFailure error
});


$OperationIdCopyWith<$Res>? get operationId;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedDraftSubmissionCopyWithImpl<$Res>
    implements $FailedDraftSubmissionCopyWith<$Res> {
  _$FailedDraftSubmissionCopyWithImpl(this._self, this._then);

  final FailedDraftSubmission _self;
  final $Res Function(FailedDraftSubmission) _then;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = freezed,Object? inputId = freezed,Object? error = null,}) {
  return _then(FailedDraftSubmission(
operationId: freezed == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId?,inputId: freezed == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String?,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res>? get operationId {
    if (_self.operationId == null) {
    return null;
  }

  return $OperationIdCopyWith<$Res>(_self.operationId!, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class UnknownDraftSubmission implements DraftSubmissionState {
  const UnknownDraftSubmission({required this.operationId, required this.inputId, required this.error});


 final  OperationId operationId;
 final  String inputId;
 final  StudioFailure error;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownDraftSubmissionCopyWith<UnknownDraftSubmission> get copyWith => _$UnknownDraftSubmissionCopyWithImpl<UnknownDraftSubmission>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownDraftSubmission&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,operationId,inputId,error);
}



}

/// @nodoc
abstract mixin class $UnknownDraftSubmissionCopyWith<$Res> implements $DraftSubmissionStateCopyWith<$Res> {
  factory $UnknownDraftSubmissionCopyWith(UnknownDraftSubmission value, $Res Function(UnknownDraftSubmission) _then) = _$UnknownDraftSubmissionCopyWithImpl;
@useResult
$Res call({
 OperationId operationId, String inputId, StudioFailure error
});


$OperationIdCopyWith<$Res> get operationId;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$UnknownDraftSubmissionCopyWithImpl<$Res>
    implements $UnknownDraftSubmissionCopyWith<$Res> {
  _$UnknownDraftSubmissionCopyWithImpl(this._self, this._then);

  final UnknownDraftSubmission _self;
  final $Res Function(UnknownDraftSubmission) _then;

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? operationId = null,Object? inputId = null,Object? error = null,}) {
  return _then(UnknownDraftSubmission(
operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as OperationId,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$OperationIdCopyWith<$Res> get operationId {

  return $OperationIdCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}/// Create a copy of DraftSubmissionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$AttachmentCleanupIssue {

 String get attachmentDraftId; StudioFailure get error;
/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AttachmentCleanupIssueCopyWith<AttachmentCleanupIssue> get copyWith => _$AttachmentCleanupIssueCopyWithImpl<AttachmentCleanupIssue>(this as AttachmentCleanupIssue, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AttachmentCleanupIssue;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AttachmentCleanupIssue&&(identical(other.attachmentDraftId, _this.attachmentDraftId) || other.attachmentDraftId == _this.attachmentDraftId)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as AttachmentCleanupIssue;
  return Object.hash(runtimeType,_this.attachmentDraftId,_this.error);
}



}

/// @nodoc
abstract mixin class $AttachmentCleanupIssueCopyWith<$Res>  {
  factory $AttachmentCleanupIssueCopyWith(AttachmentCleanupIssue value, $Res Function(AttachmentCleanupIssue) _then) = _$AttachmentCleanupIssueCopyWithImpl;
@useResult
$Res call({
 String attachmentDraftId, StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AttachmentCleanupIssueCopyWithImpl<$Res>
    implements $AttachmentCleanupIssueCopyWith<$Res> {
  _$AttachmentCleanupIssueCopyWithImpl(this._self, this._then);

  final AttachmentCleanupIssue _self;
  final $Res Function(AttachmentCleanupIssue) _then;

/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? attachmentDraftId = null,Object? error = null,}) {
  return _then(AttachmentCleanupIssue(
attachmentDraftId: null == attachmentDraftId ? _self.attachmentDraftId : attachmentDraftId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}
/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [AttachmentCleanupIssue].
extension AttachmentCleanupIssuePatterns on AttachmentCleanupIssue {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AttachmentCleanupIssue value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AttachmentCleanupIssue() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AttachmentCleanupIssue value)  $default,){
final _that = this;
switch (_that) {
case _AttachmentCleanupIssue():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AttachmentCleanupIssue value)?  $default,){
final _that = this;
switch (_that) {
case _AttachmentCleanupIssue() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String attachmentDraftId,  StudioFailure error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AttachmentCleanupIssue() when $default != null:
return $default(_that.attachmentDraftId,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String attachmentDraftId,  StudioFailure error)  $default,) {final _that = this;
switch (_that) {
case _AttachmentCleanupIssue():
return $default(_that.attachmentDraftId,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String attachmentDraftId,  StudioFailure error)?  $default,) {final _that = this;
switch (_that) {
case _AttachmentCleanupIssue() when $default != null:
return $default(_that.attachmentDraftId,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _AttachmentCleanupIssue implements AttachmentCleanupIssue {
  const _AttachmentCleanupIssue({required this.attachmentDraftId, required this.error});


@override final  String attachmentDraftId;
@override final  StudioFailure error;

/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AttachmentCleanupIssueCopyWith<_AttachmentCleanupIssue> get copyWith => __$AttachmentCleanupIssueCopyWithImpl<_AttachmentCleanupIssue>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AttachmentCleanupIssue&&(identical(other.attachmentDraftId, attachmentDraftId) || other.attachmentDraftId == attachmentDraftId)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,attachmentDraftId,error);
}



}

/// @nodoc
abstract mixin class _$AttachmentCleanupIssueCopyWith<$Res> implements $AttachmentCleanupIssueCopyWith<$Res> {
  factory _$AttachmentCleanupIssueCopyWith(_AttachmentCleanupIssue value, $Res Function(_AttachmentCleanupIssue) _then) = __$AttachmentCleanupIssueCopyWithImpl;
@override @useResult
$Res call({
 String attachmentDraftId, StudioFailure error
});


@override $StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class __$AttachmentCleanupIssueCopyWithImpl<$Res>
    implements _$AttachmentCleanupIssueCopyWith<$Res> {
  __$AttachmentCleanupIssueCopyWithImpl(this._self, this._then);

  final _AttachmentCleanupIssue _self;
  final $Res Function(_AttachmentCleanupIssue) _then;

/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? attachmentDraftId = null,Object? error = null,}) {
  return _then(_AttachmentCleanupIssue(
attachmentDraftId: null == attachmentDraftId ? _self.attachmentDraftId : attachmentDraftId // ignore: cast_nullable_to_non_nullable
as String,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AttachmentCleanupIssue
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc
mixin _$ComposerDraftState {


/// Create a copy of ComposerDraftState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ComposerDraftStateCopyWith<ComposerDraftState> get copyWith => _$ComposerDraftStateCopyWithImpl<ComposerDraftState>(this as ComposerDraftState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ComposerDraftState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ComposerDraftState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&(identical(other.attachmentGeneration, _this.attachmentGeneration) || other.attachmentGeneration == _this.attachmentGeneration)&&(identical(other.submissionRevision, _this.submissionRevision) || other.submissionRevision == _this.submissionRevision)&&(identical(other.submission, _this.submission) || other.submission == _this.submission)&&const DeepCollectionEquality().equals(other.cleanupIssues, _this.cleanupIssues));
}


@override
int get hashCode {
  final _this = this as ComposerDraftState;
  return Object.hash(runtimeType,_this.stamp,_this.text,const DeepCollectionEquality().hash(_this.attachments),_this.attachmentGeneration,_this.submissionRevision,_this.submission,const DeepCollectionEquality().hash(_this.cleanupIssues));
}



}

/// @nodoc
abstract mixin class $ComposerDraftStateCopyWith<$Res>  {
  factory $ComposerDraftStateCopyWith(ComposerDraftState value, $Res Function(ComposerDraftState) _then) = _$ComposerDraftStateCopyWithImpl;
@useResult
$Res call({
 DraftStamp stamp, String text, List<AttachmentMetadata> attachments, int attachmentGeneration, int submissionRevision, DraftSubmissionState submission, List<AttachmentCleanupIssue> cleanupIssues
});


$DraftStampCopyWith<$Res> get stamp;$DraftSubmissionStateCopyWith<$Res> get submission;

}
/// @nodoc
class _$ComposerDraftStateCopyWithImpl<$Res>
    implements $ComposerDraftStateCopyWith<$Res> {
  _$ComposerDraftStateCopyWithImpl(this._self, this._then);

  final ComposerDraftState _self;
  final $Res Function(ComposerDraftState) _then;

/// Create a copy of ComposerDraftState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? text = null,Object? attachments = null,Object? attachmentGeneration = null,Object? submissionRevision = null,Object? submission = null,Object? cleanupIssues = null,}) {
  return _then(ComposerDraftState(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as DraftStamp,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentMetadata>,attachmentGeneration: null == attachmentGeneration ? _self.attachmentGeneration : attachmentGeneration // ignore: cast_nullable_to_non_nullable
as int,submissionRevision: null == submissionRevision ? _self.submissionRevision : submissionRevision // ignore: cast_nullable_to_non_nullable
as int,submission: null == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as DraftSubmissionState,cleanupIssues: null == cleanupIssues ? _self.cleanupIssues : cleanupIssues // ignore: cast_nullable_to_non_nullable
as List<AttachmentCleanupIssue>,
  ));
}
/// Create a copy of ComposerDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftStampCopyWith<$Res> get stamp {

  return $DraftStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ComposerDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftSubmissionStateCopyWith<$Res> get submission {

  return $DraftSubmissionStateCopyWith<$Res>(_self.submission, (value) {
    return _then(_self.copyWith(submission: value));
  });
}
}


/// Adds pattern-matching-related methods to [ComposerDraftState].
extension ComposerDraftStatePatterns on ComposerDraftState {
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
mixin _$StartDraftState {


/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartDraftStateCopyWith<StartDraftState> get copyWith => _$StartDraftStateCopyWithImpl<StartDraftState>(this as StartDraftState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartDraftState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartDraftState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.text, _this.text) || other.text == _this.text)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&(identical(other.attachmentGeneration, _this.attachmentGeneration) || other.attachmentGeneration == _this.attachmentGeneration)&&(identical(other.submissionRevision, _this.submissionRevision) || other.submissionRevision == _this.submissionRevision)&&(identical(other.submission, _this.submission) || other.submission == _this.submission)&&const DeepCollectionEquality().equals(other.cleanupIssues, _this.cleanupIssues)&&(identical(other.mode, _this.mode) || other.mode == _this.mode)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&(identical(other.delegationModeOverride, _this.delegationModeOverride) || other.delegationModeOverride == _this.delegationModeOverride)&&(identical(other.delegationPreferenceOverride, _this.delegationPreferenceOverride) || other.delegationPreferenceOverride == _this.delegationPreferenceOverride)&&(identical(other.routePreparation, _this.routePreparation) || other.routePreparation == _this.routePreparation)&&(identical(other.preparation, _this.preparation) || other.preparation == _this.preparation));
}


@override
int get hashCode {
  final _this = this as StartDraftState;
  return Object.hash(runtimeType,_this.stamp,_this.text,const DeepCollectionEquality().hash(_this.attachments),_this.attachmentGeneration,_this.submissionRevision,_this.submission,const DeepCollectionEquality().hash(_this.cleanupIssues),_this.mode,_this.workspaceMode,_this.delegationModeOverride,_this.delegationPreferenceOverride,_this.routePreparation,_this.preparation);
}



}

/// @nodoc
abstract mixin class $StartDraftStateCopyWith<$Res>  {
  factory $StartDraftStateCopyWith(StartDraftState value, $Res Function(StartDraftState) _then) = _$StartDraftStateCopyWithImpl;
@useResult
$Res call({
 DraftStamp stamp, String text, List<AttachmentMetadata> attachments, int attachmentGeneration, int submissionRevision, DraftSubmissionState submission, List<AttachmentCleanupIssue> cleanupIssues, ThreadModeId mode, ThreadWorkspaceMode workspaceMode, DelegationMode? delegationModeOverride, DelegationPreference? delegationPreferenceOverride, StartRoutePreparation routePreparation, NewThreadPreparation? preparation
});


$DraftStampCopyWith<$Res> get stamp;$DraftSubmissionStateCopyWith<$Res> get submission;$StartRoutePreparationCopyWith<$Res> get routePreparation;$NewThreadPreparationCopyWith<$Res>? get preparation;

}
/// @nodoc
class _$StartDraftStateCopyWithImpl<$Res>
    implements $StartDraftStateCopyWith<$Res> {
  _$StartDraftStateCopyWithImpl(this._self, this._then);

  final StartDraftState _self;
  final $Res Function(StartDraftState) _then;

/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? text = null,Object? attachments = null,Object? attachmentGeneration = null,Object? submissionRevision = null,Object? submission = null,Object? cleanupIssues = null,Object? mode = null,Object? workspaceMode = null,Object? delegationModeOverride = freezed,Object? delegationPreferenceOverride = freezed,Object? routePreparation = null,Object? preparation = freezed,}) {
  return _then(StartDraftState(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as DraftStamp,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<AttachmentMetadata>,attachmentGeneration: null == attachmentGeneration ? _self.attachmentGeneration : attachmentGeneration // ignore: cast_nullable_to_non_nullable
as int,submissionRevision: null == submissionRevision ? _self.submissionRevision : submissionRevision // ignore: cast_nullable_to_non_nullable
as int,submission: null == submission ? _self.submission : submission // ignore: cast_nullable_to_non_nullable
as DraftSubmissionState,cleanupIssues: null == cleanupIssues ? _self.cleanupIssues : cleanupIssues // ignore: cast_nullable_to_non_nullable
as List<AttachmentCleanupIssue>,mode: null == mode ? _self.mode : mode // ignore: cast_nullable_to_non_nullable
as ThreadModeId,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,delegationModeOverride: freezed == delegationModeOverride ? _self.delegationModeOverride : delegationModeOverride // ignore: cast_nullable_to_non_nullable
as DelegationMode?,delegationPreferenceOverride: freezed == delegationPreferenceOverride ? _self.delegationPreferenceOverride : delegationPreferenceOverride // ignore: cast_nullable_to_non_nullable
as DelegationPreference?,routePreparation: null == routePreparation ? _self.routePreparation : routePreparation // ignore: cast_nullable_to_non_nullable
as StartRoutePreparation,preparation: freezed == preparation ? _self.preparation : preparation // ignore: cast_nullable_to_non_nullable
as NewThreadPreparation?,
  ));
}
/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftStampCopyWith<$Res> get stamp {

  return $DraftStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$DraftSubmissionStateCopyWith<$Res> get submission {

  return $DraftSubmissionStateCopyWith<$Res>(_self.submission, (value) {
    return _then(_self.copyWith(submission: value));
  });
}/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRoutePreparationCopyWith<$Res> get routePreparation {

  return $StartRoutePreparationCopyWith<$Res>(_self.routePreparation, (value) {
    return _then(_self.copyWith(routePreparation: value));
  });
}/// Create a copy of StartDraftState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$NewThreadPreparationCopyWith<$Res>? get preparation {
    if (_self.preparation == null) {
    return null;
  }

  return $NewThreadPreparationCopyWith<$Res>(_self.preparation!, (value) {
    return _then(_self.copyWith(preparation: value));
  });
}
}


/// Adds pattern-matching-related methods to [StartDraftState].
extension StartDraftStatePatterns on StartDraftState {
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
mixin _$StartRoutePreparation {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartRoutePreparation);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $StartRoutePreparationCopyWith<$Res>  {
$StartRoutePreparationCopyWith(StartRoutePreparation _, $Res Function(StartRoutePreparation) __);
}


/// Adds pattern-matching-related methods to [StartRoutePreparation].
extension StartRoutePreparationPatterns on StartRoutePreparation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UnreadStartRoutePreparation value)?  unread,TResult Function( LoadingStartRoutePreparation value)?  loading,TResult Function( FailedStartRoutePreparation value)?  failure,TResult Function( UnavailableStartRoutePreparation value)?  unavailable,TResult Function( ReadyStartRoutePreparation value)?  ready,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UnreadStartRoutePreparation() when unread != null:
return unread(_that);case LoadingStartRoutePreparation() when loading != null:
return loading(_that);case FailedStartRoutePreparation() when failure != null:
return failure(_that);case UnavailableStartRoutePreparation() when unavailable != null:
return unavailable(_that);case ReadyStartRoutePreparation() when ready != null:
return ready(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UnreadStartRoutePreparation value)  unread,required TResult Function( LoadingStartRoutePreparation value)  loading,required TResult Function( FailedStartRoutePreparation value)  failure,required TResult Function( UnavailableStartRoutePreparation value)  unavailable,required TResult Function( ReadyStartRoutePreparation value)  ready,}){
final _that = this;
switch (_that) {
case UnreadStartRoutePreparation():
return unread(_that);case LoadingStartRoutePreparation():
return loading(_that);case FailedStartRoutePreparation():
return failure(_that);case UnavailableStartRoutePreparation():
return unavailable(_that);case ReadyStartRoutePreparation():
return ready(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UnreadStartRoutePreparation value)?  unread,TResult? Function( LoadingStartRoutePreparation value)?  loading,TResult? Function( FailedStartRoutePreparation value)?  failure,TResult? Function( UnavailableStartRoutePreparation value)?  unavailable,TResult? Function( ReadyStartRoutePreparation value)?  ready,}){
final _that = this;
switch (_that) {
case UnreadStartRoutePreparation() when unread != null:
return unread(_that);case LoadingStartRoutePreparation() when loading != null:
return loading(_that);case FailedStartRoutePreparation() when failure != null:
return failure(_that);case UnavailableStartRoutePreparation() when unavailable != null:
return unavailable(_that);case ReadyStartRoutePreparation() when ready != null:
return ready(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( StartRouteIntent intent,  StartRouteRead? lastKnown)?  unread,TResult Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StartRouteRead? lastKnown)?  loading,TResult Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StudioFailure error,  StartRouteRead? lastKnown)?  failure,TResult Function( UnavailableStartRouteRead result)?  unavailable,TResult Function( ReadyStartRouteRead result)?  ready,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UnreadStartRoutePreparation() when unread != null:
return unread(_that.intent,_that.lastKnown);case LoadingStartRoutePreparation() when loading != null:
return loading(_that.sources,_that.query,_that.intent,_that.lastKnown);case FailedStartRoutePreparation() when failure != null:
return failure(_that.sources,_that.query,_that.intent,_that.error,_that.lastKnown);case UnavailableStartRoutePreparation() when unavailable != null:
return unavailable(_that.result);case ReadyStartRoutePreparation() when ready != null:
return ready(_that.result);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( StartRouteIntent intent,  StartRouteRead? lastKnown)  unread,required TResult Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StartRouteRead? lastKnown)  loading,required TResult Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StudioFailure error,  StartRouteRead? lastKnown)  failure,required TResult Function( UnavailableStartRouteRead result)  unavailable,required TResult Function( ReadyStartRouteRead result)  ready,}) {final _that = this;
switch (_that) {
case UnreadStartRoutePreparation():
return unread(_that.intent,_that.lastKnown);case LoadingStartRoutePreparation():
return loading(_that.sources,_that.query,_that.intent,_that.lastKnown);case FailedStartRoutePreparation():
return failure(_that.sources,_that.query,_that.intent,_that.error,_that.lastKnown);case UnavailableStartRoutePreparation():
return unavailable(_that.result);case ReadyStartRoutePreparation():
return ready(_that.result);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( StartRouteIntent intent,  StartRouteRead? lastKnown)?  unread,TResult? Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StartRouteRead? lastKnown)?  loading,TResult? Function( ConfigurationRoleReadTarget? sources,  StartRouteQuery query,  StartRouteIntent intent,  StudioFailure error,  StartRouteRead? lastKnown)?  failure,TResult? Function( UnavailableStartRouteRead result)?  unavailable,TResult? Function( ReadyStartRouteRead result)?  ready,}) {final _that = this;
switch (_that) {
case UnreadStartRoutePreparation() when unread != null:
return unread(_that.intent,_that.lastKnown);case LoadingStartRoutePreparation() when loading != null:
return loading(_that.sources,_that.query,_that.intent,_that.lastKnown);case FailedStartRoutePreparation() when failure != null:
return failure(_that.sources,_that.query,_that.intent,_that.error,_that.lastKnown);case UnavailableStartRoutePreparation() when unavailable != null:
return unavailable(_that.result);case ReadyStartRoutePreparation() when ready != null:
return ready(_that.result);case _:
  return null;

}
}

}

/// @nodoc


class UnreadStartRoutePreparation implements StartRoutePreparation {
  const UnreadStartRoutePreparation({required this.intent, required this.lastKnown});


 final  StartRouteIntent intent;
 final  StartRouteRead? lastKnown;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnreadStartRoutePreparationCopyWith<UnreadStartRoutePreparation> get copyWith => _$UnreadStartRoutePreparationCopyWithImpl<UnreadStartRoutePreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnreadStartRoutePreparation&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.lastKnown, lastKnown) || other.lastKnown == lastKnown));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,lastKnown);
}



}

/// @nodoc
abstract mixin class $UnreadStartRoutePreparationCopyWith<$Res> implements $StartRoutePreparationCopyWith<$Res> {
  factory $UnreadStartRoutePreparationCopyWith(UnreadStartRoutePreparation value, $Res Function(UnreadStartRoutePreparation) _then) = _$UnreadStartRoutePreparationCopyWithImpl;
@useResult
$Res call({
 StartRouteIntent intent, StartRouteRead? lastKnown
});


$StartRouteIntentCopyWith<$Res> get intent;$StartRouteReadCopyWith<$Res>? get lastKnown;

}
/// @nodoc
class _$UnreadStartRoutePreparationCopyWithImpl<$Res>
    implements $UnreadStartRoutePreparationCopyWith<$Res> {
  _$UnreadStartRoutePreparationCopyWithImpl(this._self, this._then);

  final UnreadStartRoutePreparation _self;
  final $Res Function(UnreadStartRoutePreparation) _then;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? lastKnown = freezed,}) {
  return _then(UnreadStartRoutePreparation(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as StartRouteRead?,
  ));
}

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteReadCopyWith<$Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $StartRouteReadCopyWith<$Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}
}

/// @nodoc


class LoadingStartRoutePreparation implements StartRoutePreparation {
  const LoadingStartRoutePreparation({required this.sources, required this.query, required this.intent, required this.lastKnown});


 final  ConfigurationRoleReadTarget? sources;
 final  StartRouteQuery query;
 final  StartRouteIntent intent;
 final  StartRouteRead? lastKnown;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingStartRoutePreparationCopyWith<LoadingStartRoutePreparation> get copyWith => _$LoadingStartRoutePreparationCopyWithImpl<LoadingStartRoutePreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingStartRoutePreparation&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.lastKnown, lastKnown) || other.lastKnown == lastKnown));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,lastKnown);
}



}

/// @nodoc
abstract mixin class $LoadingStartRoutePreparationCopyWith<$Res> implements $StartRoutePreparationCopyWith<$Res> {
  factory $LoadingStartRoutePreparationCopyWith(LoadingStartRoutePreparation value, $Res Function(LoadingStartRoutePreparation) _then) = _$LoadingStartRoutePreparationCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadTarget? sources, StartRouteQuery query, StartRouteIntent intent, StartRouteRead? lastKnown
});


$ConfigurationRoleReadTargetCopyWith<$Res>? get sources;$StartRouteQueryCopyWith<$Res> get query;$StartRouteIntentCopyWith<$Res> get intent;$StartRouteReadCopyWith<$Res>? get lastKnown;

}
/// @nodoc
class _$LoadingStartRoutePreparationCopyWithImpl<$Res>
    implements $LoadingStartRoutePreparationCopyWith<$Res> {
  _$LoadingStartRoutePreparationCopyWithImpl(this._self, this._then);

  final LoadingStartRoutePreparation _self;
  final $Res Function(LoadingStartRoutePreparation) _then;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sources = freezed,Object? query = null,Object? intent = null,Object? lastKnown = freezed,}) {
  return _then(LoadingStartRoutePreparation(
sources: freezed == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as StartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as StartRouteRead?,
  ));
}

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get sources {
    if (_self.sources == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources!, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<$Res> get query {

  return $StartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteReadCopyWith<$Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $StartRouteReadCopyWith<$Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}
}

/// @nodoc


class FailedStartRoutePreparation implements StartRoutePreparation {
  const FailedStartRoutePreparation({required this.sources, required this.query, required this.intent, required this.error, required this.lastKnown});


 final  ConfigurationRoleReadTarget? sources;
 final  StartRouteQuery query;
 final  StartRouteIntent intent;
 final  StudioFailure error;
 final  StartRouteRead? lastKnown;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedStartRoutePreparationCopyWith<FailedStartRoutePreparation> get copyWith => _$FailedStartRoutePreparationCopyWithImpl<FailedStartRoutePreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedStartRoutePreparation&&(identical(other.sources, sources) || other.sources == sources)&&(identical(other.query, query) || other.query == query)&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.error, error) || other.error == error)&&(identical(other.lastKnown, lastKnown) || other.lastKnown == lastKnown));
}


@override
int get hashCode {
    return Object.hash(runtimeType,sources,query,intent,error,lastKnown);
}



}

/// @nodoc
abstract mixin class $FailedStartRoutePreparationCopyWith<$Res> implements $StartRoutePreparationCopyWith<$Res> {
  factory $FailedStartRoutePreparationCopyWith(FailedStartRoutePreparation value, $Res Function(FailedStartRoutePreparation) _then) = _$FailedStartRoutePreparationCopyWithImpl;
@useResult
$Res call({
 ConfigurationRoleReadTarget? sources, StartRouteQuery query, StartRouteIntent intent, StudioFailure error, StartRouteRead? lastKnown
});


$ConfigurationRoleReadTargetCopyWith<$Res>? get sources;$StartRouteQueryCopyWith<$Res> get query;$StartRouteIntentCopyWith<$Res> get intent;$StudioFailureCopyWith<$Res> get error;$StartRouteReadCopyWith<$Res>? get lastKnown;

}
/// @nodoc
class _$FailedStartRoutePreparationCopyWithImpl<$Res>
    implements $FailedStartRoutePreparationCopyWith<$Res> {
  _$FailedStartRoutePreparationCopyWithImpl(this._self, this._then);

  final FailedStartRoutePreparation _self;
  final $Res Function(FailedStartRoutePreparation) _then;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? sources = freezed,Object? query = null,Object? intent = null,Object? error = null,Object? lastKnown = freezed,}) {
  return _then(FailedStartRoutePreparation(
sources: freezed == sources ? _self.sources : sources // ignore: cast_nullable_to_non_nullable
as ConfigurationRoleReadTarget?,query: null == query ? _self.query : query // ignore: cast_nullable_to_non_nullable
as StartRouteQuery,intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as StartRouteIntent,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as StartRouteRead?,
  ));
}

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ConfigurationRoleReadTargetCopyWith<$Res>? get sources {
    if (_self.sources == null) {
    return null;
  }

  return $ConfigurationRoleReadTargetCopyWith<$Res>(_self.sources!, (value) {
    return _then(_self.copyWith(sources: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteQueryCopyWith<$Res> get query {

  return $StartRouteQueryCopyWith<$Res>(_self.query, (value) {
    return _then(_self.copyWith(query: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteIntentCopyWith<$Res> get intent {

  return $StartRouteIntentCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res> get error {

  return $StudioFailureCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StartRouteReadCopyWith<$Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $StartRouteReadCopyWith<$Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}
}

/// @nodoc


class UnavailableStartRoutePreparation implements StartRoutePreparation {
  const UnavailableStartRoutePreparation({required this.result});


 final  UnavailableStartRouteRead result;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnavailableStartRoutePreparationCopyWith<UnavailableStartRoutePreparation> get copyWith => _$UnavailableStartRoutePreparationCopyWithImpl<UnavailableStartRoutePreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnavailableStartRoutePreparation&&const DeepCollectionEquality().equals(other.result, result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(result));
}



}

/// @nodoc
abstract mixin class $UnavailableStartRoutePreparationCopyWith<$Res> implements $StartRoutePreparationCopyWith<$Res> {
  factory $UnavailableStartRoutePreparationCopyWith(UnavailableStartRoutePreparation value, $Res Function(UnavailableStartRoutePreparation) _then) = _$UnavailableStartRoutePreparationCopyWithImpl;
@useResult
$Res call({
 UnavailableStartRouteRead result
});




}
/// @nodoc
class _$UnavailableStartRoutePreparationCopyWithImpl<$Res>
    implements $UnavailableStartRoutePreparationCopyWith<$Res> {
  _$UnavailableStartRoutePreparationCopyWithImpl(this._self, this._then);

  final UnavailableStartRoutePreparation _self;
  final $Res Function(UnavailableStartRoutePreparation) _then;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = freezed,}) {
  return _then(UnavailableStartRoutePreparation(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as UnavailableStartRouteRead,
  ));
}


}

/// @nodoc


class ReadyStartRoutePreparation implements StartRoutePreparation {
  const ReadyStartRoutePreparation({required this.result});


 final  ReadyStartRouteRead result;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyStartRoutePreparationCopyWith<ReadyStartRoutePreparation> get copyWith => _$ReadyStartRoutePreparationCopyWithImpl<ReadyStartRoutePreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyStartRoutePreparation&&const DeepCollectionEquality().equals(other.result, result));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(result));
}



}

/// @nodoc
abstract mixin class $ReadyStartRoutePreparationCopyWith<$Res> implements $StartRoutePreparationCopyWith<$Res> {
  factory $ReadyStartRoutePreparationCopyWith(ReadyStartRoutePreparation value, $Res Function(ReadyStartRoutePreparation) _then) = _$ReadyStartRoutePreparationCopyWithImpl;
@useResult
$Res call({
 ReadyStartRouteRead result
});




}
/// @nodoc
class _$ReadyStartRoutePreparationCopyWithImpl<$Res>
    implements $ReadyStartRoutePreparationCopyWith<$Res> {
  _$ReadyStartRoutePreparationCopyWithImpl(this._self, this._then);

  final ReadyStartRoutePreparation _self;
  final $Res Function(ReadyStartRoutePreparation) _then;

/// Create a copy of StartRoutePreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? result = freezed,}) {
  return _then(ReadyStartRoutePreparation(
result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as ReadyStartRouteRead,
  ));
}


}

/// @nodoc
mixin _$StartModelIntent {

 String get accountId; String get modelId;
/// Create a copy of StartModelIntent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartModelIntentCopyWith<StartModelIntent> get copyWith => _$StartModelIntentCopyWithImpl<StartModelIntent>(this as StartModelIntent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartModelIntent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartModelIntent&&(identical(other.accountId, _this.accountId) || other.accountId == _this.accountId)&&(identical(other.modelId, _this.modelId) || other.modelId == _this.modelId));
}


@override
int get hashCode {
  final _this = this as StartModelIntent;
  return Object.hash(runtimeType,_this.accountId,_this.modelId);
}

@override
String toString() {
  final _this = this as StartModelIntent;
  return 'StartModelIntent(accountId: ${_this.accountId}, modelId: ${_this.modelId})';
}


}

/// @nodoc
abstract mixin class $StartModelIntentCopyWith<$Res>  {
  factory $StartModelIntentCopyWith(StartModelIntent value, $Res Function(StartModelIntent) _then) = _$StartModelIntentCopyWithImpl;
@useResult
$Res call({
 String accountId, String modelId
});




}
/// @nodoc
class _$StartModelIntentCopyWithImpl<$Res>
    implements $StartModelIntentCopyWith<$Res> {
  _$StartModelIntentCopyWithImpl(this._self, this._then);

  final StartModelIntent _self;
  final $Res Function(StartModelIntent) _then;

/// Create a copy of StartModelIntent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? accountId = null,Object? modelId = null,}) {
  return _then(StartModelIntent(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [StartModelIntent].
extension StartModelIntentPatterns on StartModelIntent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _StartModelIntent value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _StartModelIntent() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _StartModelIntent value)  $default,){
final _that = this;
switch (_that) {
case _StartModelIntent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _StartModelIntent value)?  $default,){
final _that = this;
switch (_that) {
case _StartModelIntent() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String accountId,  String modelId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _StartModelIntent() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String accountId,  String modelId)  $default,) {final _that = this;
switch (_that) {
case _StartModelIntent():
return $default(_that.accountId,_that.modelId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String accountId,  String modelId)?  $default,) {final _that = this;
switch (_that) {
case _StartModelIntent() when $default != null:
return $default(_that.accountId,_that.modelId);case _:
  return null;

}
}

}

/// @nodoc


class _StartModelIntent implements StartModelIntent {
  const _StartModelIntent({required this.accountId, required this.modelId});


@override final  String accountId;
@override final  String modelId;

/// Create a copy of StartModelIntent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$StartModelIntentCopyWith<_StartModelIntent> get copyWith => __$StartModelIntentCopyWithImpl<_StartModelIntent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _StartModelIntent&&(identical(other.accountId, accountId) || other.accountId == accountId)&&(identical(other.modelId, modelId) || other.modelId == modelId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,accountId,modelId);
}

@override
String toString() {
    return 'StartModelIntent(accountId: $accountId, modelId: $modelId)';
}


}

/// @nodoc
abstract mixin class _$StartModelIntentCopyWith<$Res> implements $StartModelIntentCopyWith<$Res> {
  factory _$StartModelIntentCopyWith(_StartModelIntent value, $Res Function(_StartModelIntent) _then) = __$StartModelIntentCopyWithImpl;
@override @useResult
$Res call({
 String accountId, String modelId
});




}
/// @nodoc
class __$StartModelIntentCopyWithImpl<$Res>
    implements _$StartModelIntentCopyWith<$Res> {
  __$StartModelIntentCopyWithImpl(this._self, this._then);

  final _StartModelIntent _self;
  final $Res Function(_StartModelIntent) _then;

/// Create a copy of StartModelIntent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? accountId = null,Object? modelId = null,}) {
  return _then(_StartModelIntent(
accountId: null == accountId ? _self.accountId : accountId // ignore: cast_nullable_to_non_nullable
as String,modelId: null == modelId ? _self.modelId : modelId // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$StartRoutePreferences {


/// Create a copy of StartRoutePreferences
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StartRoutePreferencesCopyWith<StartRoutePreferences> get copyWith => _$StartRoutePreferencesCopyWithImpl<StartRoutePreferences>(this as StartRoutePreferences, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as StartRoutePreferences;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is StartRoutePreferences&&const DeepCollectionEquality().equals(other.models, _this.models)&&const DeepCollectionEquality().equals(other.efforts, _this.efforts));
}


@override
int get hashCode {
  final _this = this as StartRoutePreferences;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.models),const DeepCollectionEquality().hash(_this.efforts));
}

@override
String toString() {
  final _this = this as StartRoutePreferences;
  return 'StartRoutePreferences(models: ${_this.models}, efforts: ${_this.efforts})';
}


}

/// @nodoc
abstract mixin class $StartRoutePreferencesCopyWith<$Res>  {
  factory $StartRoutePreferencesCopyWith(StartRoutePreferences value, $Res Function(StartRoutePreferences) _then) = _$StartRoutePreferencesCopyWithImpl;
@useResult
$Res call({
 Map<String, StartModelIntent> models, Map<String, String> efforts
});




}
/// @nodoc
class _$StartRoutePreferencesCopyWithImpl<$Res>
    implements $StartRoutePreferencesCopyWith<$Res> {
  _$StartRoutePreferencesCopyWithImpl(this._self, this._then);

  final StartRoutePreferences _self;
  final $Res Function(StartRoutePreferences) _then;

/// Create a copy of StartRoutePreferences
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? models = null,Object? efforts = null,}) {
  return _then(StartRoutePreferences(
models: null == models ? _self.models : models // ignore: cast_nullable_to_non_nullable
as Map<String, StartModelIntent>,efforts: null == efforts ? _self.efforts : efforts // ignore: cast_nullable_to_non_nullable
as Map<String, String>,
  ));
}

}


/// Adds pattern-matching-related methods to [StartRoutePreferences].
extension StartRoutePreferencesPatterns on StartRoutePreferences {
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
mixin _$ThreadPreparationProgress {

 String get projectId; String get inputId; ThreadPreparationStage get stage; String? get workspacePath; String? get branch;
/// Create a copy of ThreadPreparationProgress
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadPreparationProgressCopyWith<ThreadPreparationProgress> get copyWith => _$ThreadPreparationProgressCopyWithImpl<ThreadPreparationProgress>(this as ThreadPreparationProgress, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadPreparationProgress;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadPreparationProgress&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.stage, _this.stage) || other.stage == _this.stage)&&(identical(other.workspacePath, _this.workspacePath) || other.workspacePath == _this.workspacePath)&&(identical(other.branch, _this.branch) || other.branch == _this.branch));
}


@override
int get hashCode {
  final _this = this as ThreadPreparationProgress;
  return Object.hash(runtimeType,_this.projectId,_this.inputId,_this.stage,_this.workspacePath,_this.branch);
}



}

/// @nodoc
abstract mixin class $ThreadPreparationProgressCopyWith<$Res>  {
  factory $ThreadPreparationProgressCopyWith(ThreadPreparationProgress value, $Res Function(ThreadPreparationProgress) _then) = _$ThreadPreparationProgressCopyWithImpl;
@useResult
$Res call({
 String projectId, String inputId, ThreadPreparationStage stage, String? workspacePath, String? branch
});




}
/// @nodoc
class _$ThreadPreparationProgressCopyWithImpl<$Res>
    implements $ThreadPreparationProgressCopyWith<$Res> {
  _$ThreadPreparationProgressCopyWithImpl(this._self, this._then);

  final ThreadPreparationProgress _self;
  final $Res Function(ThreadPreparationProgress) _then;

/// Create a copy of ThreadPreparationProgress
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? inputId = null,Object? stage = null,Object? workspacePath = freezed,Object? branch = freezed,}) {
  return _then(ThreadPreparationProgress(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as ThreadPreparationStage,workspacePath: freezed == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as String?,branch: freezed == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadPreparationProgress].
extension ThreadPreparationProgressPatterns on ThreadPreparationProgress {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadPreparationProgress value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadPreparationProgress() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadPreparationProgress value)  $default,){
final _that = this;
switch (_that) {
case _ThreadPreparationProgress():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadPreparationProgress value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadPreparationProgress() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String inputId,  ThreadPreparationStage stage,  String? workspacePath,  String? branch)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadPreparationProgress() when $default != null:
return $default(_that.projectId,_that.inputId,_that.stage,_that.workspacePath,_that.branch);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String inputId,  ThreadPreparationStage stage,  String? workspacePath,  String? branch)  $default,) {final _that = this;
switch (_that) {
case _ThreadPreparationProgress():
return $default(_that.projectId,_that.inputId,_that.stage,_that.workspacePath,_that.branch);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String inputId,  ThreadPreparationStage stage,  String? workspacePath,  String? branch)?  $default,) {final _that = this;
switch (_that) {
case _ThreadPreparationProgress() when $default != null:
return $default(_that.projectId,_that.inputId,_that.stage,_that.workspacePath,_that.branch);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadPreparationProgress implements ThreadPreparationProgress {
  const _ThreadPreparationProgress({required this.projectId, required this.inputId, required this.stage, required this.workspacePath, required this.branch});


@override final  String projectId;
@override final  String inputId;
@override final  ThreadPreparationStage stage;
@override final  String? workspacePath;
@override final  String? branch;

/// Create a copy of ThreadPreparationProgress
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadPreparationProgressCopyWith<_ThreadPreparationProgress> get copyWith => __$ThreadPreparationProgressCopyWithImpl<_ThreadPreparationProgress>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadPreparationProgress&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.stage, stage) || other.stage == stage)&&(identical(other.workspacePath, workspacePath) || other.workspacePath == workspacePath)&&(identical(other.branch, branch) || other.branch == branch));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,inputId,stage,workspacePath,branch);
}



}

/// @nodoc
abstract mixin class _$ThreadPreparationProgressCopyWith<$Res> implements $ThreadPreparationProgressCopyWith<$Res> {
  factory _$ThreadPreparationProgressCopyWith(_ThreadPreparationProgress value, $Res Function(_ThreadPreparationProgress) _then) = __$ThreadPreparationProgressCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String inputId, ThreadPreparationStage stage, String? workspacePath, String? branch
});




}
/// @nodoc
class __$ThreadPreparationProgressCopyWithImpl<$Res>
    implements _$ThreadPreparationProgressCopyWith<$Res> {
  __$ThreadPreparationProgressCopyWithImpl(this._self, this._then);

  final _ThreadPreparationProgress _self;
  final $Res Function(_ThreadPreparationProgress) _then;

/// Create a copy of ThreadPreparationProgress
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? inputId = null,Object? stage = null,Object? workspacePath = freezed,Object? branch = freezed,}) {
  return _then(_ThreadPreparationProgress(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,stage: null == stage ? _self.stage : stage // ignore: cast_nullable_to_non_nullable
as ThreadPreparationStage,workspacePath: freezed == workspacePath ? _self.workspacePath : workspacePath // ignore: cast_nullable_to_non_nullable
as String?,branch: freezed == branch ? _self.branch : branch // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$NewThreadPreparation {

 String get projectId; String get inputId; ThreadWorkspaceMode get workspaceMode; ThreadPreparationProgress? get progress; NewThreadPreparationPhase get phase; StudioFailure? get failure;
/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$NewThreadPreparationCopyWith<NewThreadPreparation> get copyWith => _$NewThreadPreparationCopyWithImpl<NewThreadPreparation>(this as NewThreadPreparation, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as NewThreadPreparation;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is NewThreadPreparation&&(identical(other.projectId, _this.projectId) || other.projectId == _this.projectId)&&(identical(other.inputId, _this.inputId) || other.inputId == _this.inputId)&&(identical(other.workspaceMode, _this.workspaceMode) || other.workspaceMode == _this.workspaceMode)&&(identical(other.progress, _this.progress) || other.progress == _this.progress)&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.failure, _this.failure) || other.failure == _this.failure));
}


@override
int get hashCode {
  final _this = this as NewThreadPreparation;
  return Object.hash(runtimeType,_this.projectId,_this.inputId,_this.workspaceMode,_this.progress,_this.phase,_this.failure);
}



}

/// @nodoc
abstract mixin class $NewThreadPreparationCopyWith<$Res>  {
  factory $NewThreadPreparationCopyWith(NewThreadPreparation value, $Res Function(NewThreadPreparation) _then) = _$NewThreadPreparationCopyWithImpl;
@useResult
$Res call({
 String projectId, String inputId, ThreadWorkspaceMode workspaceMode, ThreadPreparationProgress? progress, NewThreadPreparationPhase phase, StudioFailure? failure
});


$ThreadPreparationProgressCopyWith<$Res>? get progress;$StudioFailureCopyWith<$Res>? get failure;

}
/// @nodoc
class _$NewThreadPreparationCopyWithImpl<$Res>
    implements $NewThreadPreparationCopyWith<$Res> {
  _$NewThreadPreparationCopyWithImpl(this._self, this._then);

  final NewThreadPreparation _self;
  final $Res Function(NewThreadPreparation) _then;

/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projectId = null,Object? inputId = null,Object? workspaceMode = null,Object? progress = freezed,Object? phase = null,Object? failure = freezed,}) {
  return _then(NewThreadPreparation(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ThreadPreparationProgress?,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as NewThreadPreparationPhase,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPreparationProgressCopyWith<$Res>? get progress {
    if (_self.progress == null) {
    return null;
  }

  return $ThreadPreparationProgressCopyWith<$Res>(_self.progress!, (value) {
    return _then(_self.copyWith(progress: value));
  });
}/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}


/// Adds pattern-matching-related methods to [NewThreadPreparation].
extension NewThreadPreparationPatterns on NewThreadPreparation {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _NewThreadPreparation value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _NewThreadPreparation() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _NewThreadPreparation value)  $default,){
final _that = this;
switch (_that) {
case _NewThreadPreparation():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _NewThreadPreparation value)?  $default,){
final _that = this;
switch (_that) {
case _NewThreadPreparation() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String projectId,  String inputId,  ThreadWorkspaceMode workspaceMode,  ThreadPreparationProgress? progress,  NewThreadPreparationPhase phase,  StudioFailure? failure)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _NewThreadPreparation() when $default != null:
return $default(_that.projectId,_that.inputId,_that.workspaceMode,_that.progress,_that.phase,_that.failure);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String projectId,  String inputId,  ThreadWorkspaceMode workspaceMode,  ThreadPreparationProgress? progress,  NewThreadPreparationPhase phase,  StudioFailure? failure)  $default,) {final _that = this;
switch (_that) {
case _NewThreadPreparation():
return $default(_that.projectId,_that.inputId,_that.workspaceMode,_that.progress,_that.phase,_that.failure);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String projectId,  String inputId,  ThreadWorkspaceMode workspaceMode,  ThreadPreparationProgress? progress,  NewThreadPreparationPhase phase,  StudioFailure? failure)?  $default,) {final _that = this;
switch (_that) {
case _NewThreadPreparation() when $default != null:
return $default(_that.projectId,_that.inputId,_that.workspaceMode,_that.progress,_that.phase,_that.failure);case _:
  return null;

}
}

}

/// @nodoc


class _NewThreadPreparation implements NewThreadPreparation {
  const _NewThreadPreparation({required this.projectId, required this.inputId, required this.workspaceMode, required this.progress, required this.phase, required this.failure});


@override final  String projectId;
@override final  String inputId;
@override final  ThreadWorkspaceMode workspaceMode;
@override final  ThreadPreparationProgress? progress;
@override final  NewThreadPreparationPhase phase;
@override final  StudioFailure? failure;

/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$NewThreadPreparationCopyWith<_NewThreadPreparation> get copyWith => __$NewThreadPreparationCopyWithImpl<_NewThreadPreparation>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _NewThreadPreparation&&(identical(other.projectId, projectId) || other.projectId == projectId)&&(identical(other.inputId, inputId) || other.inputId == inputId)&&(identical(other.workspaceMode, workspaceMode) || other.workspaceMode == workspaceMode)&&(identical(other.progress, progress) || other.progress == progress)&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.failure, failure) || other.failure == failure));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projectId,inputId,workspaceMode,progress,phase,failure);
}



}

/// @nodoc
abstract mixin class _$NewThreadPreparationCopyWith<$Res> implements $NewThreadPreparationCopyWith<$Res> {
  factory _$NewThreadPreparationCopyWith(_NewThreadPreparation value, $Res Function(_NewThreadPreparation) _then) = __$NewThreadPreparationCopyWithImpl;
@override @useResult
$Res call({
 String projectId, String inputId, ThreadWorkspaceMode workspaceMode, ThreadPreparationProgress? progress, NewThreadPreparationPhase phase, StudioFailure? failure
});


@override $ThreadPreparationProgressCopyWith<$Res>? get progress;@override $StudioFailureCopyWith<$Res>? get failure;

}
/// @nodoc
class __$NewThreadPreparationCopyWithImpl<$Res>
    implements _$NewThreadPreparationCopyWith<$Res> {
  __$NewThreadPreparationCopyWithImpl(this._self, this._then);

  final _NewThreadPreparation _self;
  final $Res Function(_NewThreadPreparation) _then;

/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projectId = null,Object? inputId = null,Object? workspaceMode = null,Object? progress = freezed,Object? phase = null,Object? failure = freezed,}) {
  return _then(_NewThreadPreparation(
projectId: null == projectId ? _self.projectId : projectId // ignore: cast_nullable_to_non_nullable
as String,inputId: null == inputId ? _self.inputId : inputId // ignore: cast_nullable_to_non_nullable
as String,workspaceMode: null == workspaceMode ? _self.workspaceMode : workspaceMode // ignore: cast_nullable_to_non_nullable
as ThreadWorkspaceMode,progress: freezed == progress ? _self.progress : progress // ignore: cast_nullable_to_non_nullable
as ThreadPreparationProgress?,phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as NewThreadPreparationPhase,failure: freezed == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadPreparationProgressCopyWith<$Res>? get progress {
    if (_self.progress == null) {
    return null;
  }

  return $ThreadPreparationProgressCopyWith<$Res>(_self.progress!, (value) {
    return _then(_self.copyWith(progress: value));
  });
}/// Create a copy of NewThreadPreparation
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get failure {
    if (_self.failure == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.failure!, (value) {
    return _then(_self.copyWith(failure: value));
  });
}
}

// dart format on
