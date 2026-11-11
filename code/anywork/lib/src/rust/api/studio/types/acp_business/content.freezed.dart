// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'content.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BridgeAcpContentBlock {

 BridgeAcpAnnotations? get annotations; Map<String, BridgeAcpJsonValue>? get meta;
/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlockCopyWith<BridgeAcpContentBlock> get copyWith => _$BridgeAcpContentBlockCopyWithImpl<BridgeAcpContentBlock>(this as BridgeAcpContentBlock, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpContentBlock;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock&&(identical(other.annotations, _this.annotations) || other.annotations == _this.annotations)&&const DeepCollectionEquality().equals(other.meta, _this.meta));
}


@override
int get hashCode {
  final _this = this as BridgeAcpContentBlock;
  return Object.hash(runtimeType,_this.annotations,const DeepCollectionEquality().hash(_this.meta));
}

@override
String toString() {
  final _this = this as BridgeAcpContentBlock;
  return 'BridgeAcpContentBlock(annotations: ${_this.annotations}, meta: ${_this.meta})';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlockCopyWith<$Res>  {
  factory $BridgeAcpContentBlockCopyWith(BridgeAcpContentBlock value, $Res Function(BridgeAcpContentBlock) _then) = _$BridgeAcpContentBlockCopyWithImpl;
@useResult
$Res call({
 BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpContentBlockCopyWithImpl<$Res>
    implements $BridgeAcpContentBlockCopyWith<$Res> {
  _$BridgeAcpContentBlockCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock _self;
  final $Res Function(BridgeAcpContentBlock) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAcpContentBlock].
extension BridgeAcpContentBlockPatterns on BridgeAcpContentBlock {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpContentBlock_Text value)?  text,TResult Function( BridgeAcpContentBlock_Image value)?  image,TResult Function( BridgeAcpContentBlock_Audio value)?  audio,TResult Function( BridgeAcpContentBlock_ResourceLink value)?  resourceLink,TResult Function( BridgeAcpContentBlock_Resource value)?  resource,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text() when text != null:
return text(_that);case BridgeAcpContentBlock_Image() when image != null:
return image(_that);case BridgeAcpContentBlock_Audio() when audio != null:
return audio(_that);case BridgeAcpContentBlock_ResourceLink() when resourceLink != null:
return resourceLink(_that);case BridgeAcpContentBlock_Resource() when resource != null:
return resource(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpContentBlock_Text value)  text,required TResult Function( BridgeAcpContentBlock_Image value)  image,required TResult Function( BridgeAcpContentBlock_Audio value)  audio,required TResult Function( BridgeAcpContentBlock_ResourceLink value)  resourceLink,required TResult Function( BridgeAcpContentBlock_Resource value)  resource,}){
final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text():
return text(_that);case BridgeAcpContentBlock_Image():
return image(_that);case BridgeAcpContentBlock_Audio():
return audio(_that);case BridgeAcpContentBlock_ResourceLink():
return resourceLink(_that);case BridgeAcpContentBlock_Resource():
return resource(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpContentBlock_Text value)?  text,TResult? Function( BridgeAcpContentBlock_Image value)?  image,TResult? Function( BridgeAcpContentBlock_Audio value)?  audio,TResult? Function( BridgeAcpContentBlock_ResourceLink value)?  resourceLink,TResult? Function( BridgeAcpContentBlock_Resource value)?  resource,}){
final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text() when text != null:
return text(_that);case BridgeAcpContentBlock_Image() when image != null:
return image(_that);case BridgeAcpContentBlock_Audio() when audio != null:
return audio(_that);case BridgeAcpContentBlock_ResourceLink() when resourceLink != null:
return resourceLink(_that);case BridgeAcpContentBlock_Resource() when resource != null:
return resource(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  text,TResult Function( String data,  String mimeType,  String? uri,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  image,TResult Function( String data,  String mimeType,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  audio,TResult Function( String name,  String uri,  String? description,  String? mimeType,  PlatformInt64? size,  String? title,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  resourceLink,TResult Function( BridgeAcpEmbeddedResource resource,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  resource,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text() when text != null:
return text(_that.text,_that.annotations,_that.meta);case BridgeAcpContentBlock_Image() when image != null:
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case BridgeAcpContentBlock_Audio() when audio != null:
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case BridgeAcpContentBlock_ResourceLink() when resourceLink != null:
return resourceLink(_that.name,_that.uri,_that.description,_that.mimeType,_that.size,_that.title,_that.annotations,_that.meta);case BridgeAcpContentBlock_Resource() when resource != null:
return resource(_that.resource,_that.annotations,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)  text,required TResult Function( String data,  String mimeType,  String? uri,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)  image,required TResult Function( String data,  String mimeType,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)  audio,required TResult Function( String name,  String uri,  String? description,  String? mimeType,  PlatformInt64? size,  String? title,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)  resourceLink,required TResult Function( BridgeAcpEmbeddedResource resource,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)  resource,}) {final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text():
return text(_that.text,_that.annotations,_that.meta);case BridgeAcpContentBlock_Image():
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case BridgeAcpContentBlock_Audio():
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case BridgeAcpContentBlock_ResourceLink():
return resourceLink(_that.name,_that.uri,_that.description,_that.mimeType,_that.size,_that.title,_that.annotations,_that.meta);case BridgeAcpContentBlock_Resource():
return resource(_that.resource,_that.annotations,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  text,TResult? Function( String data,  String mimeType,  String? uri,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  image,TResult? Function( String data,  String mimeType,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  audio,TResult? Function( String name,  String uri,  String? description,  String? mimeType,  PlatformInt64? size,  String? title,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  resourceLink,TResult? Function( BridgeAcpEmbeddedResource resource,  BridgeAcpAnnotations? annotations,  Map<String, BridgeAcpJsonValue>? meta)?  resource,}) {final _that = this;
switch (_that) {
case BridgeAcpContentBlock_Text() when text != null:
return text(_that.text,_that.annotations,_that.meta);case BridgeAcpContentBlock_Image() when image != null:
return image(_that.data,_that.mimeType,_that.uri,_that.annotations,_that.meta);case BridgeAcpContentBlock_Audio() when audio != null:
return audio(_that.data,_that.mimeType,_that.annotations,_that.meta);case BridgeAcpContentBlock_ResourceLink() when resourceLink != null:
return resourceLink(_that.name,_that.uri,_that.description,_that.mimeType,_that.size,_that.title,_that.annotations,_that.meta);case BridgeAcpContentBlock_Resource() when resource != null:
return resource(_that.resource,_that.annotations,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpContentBlock_Text extends BridgeAcpContentBlock {
  const BridgeAcpContentBlock_Text({required this.text, this.annotations,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String text;
@override final  BridgeAcpAnnotations? annotations;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlock_TextCopyWith<BridgeAcpContentBlock_Text> get copyWith => _$BridgeAcpContentBlock_TextCopyWithImpl<BridgeAcpContentBlock_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock_Text&&(identical(other.text, text) || other.text == text)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,annotations,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpContentBlock.text(text: $text, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlock_TextCopyWith<$Res> implements $BridgeAcpContentBlockCopyWith<$Res> {
  factory $BridgeAcpContentBlock_TextCopyWith(BridgeAcpContentBlock_Text value, $Res Function(BridgeAcpContentBlock_Text) _then) = _$BridgeAcpContentBlock_TextCopyWithImpl;
@override @useResult
$Res call({
 String text, BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpContentBlock_TextCopyWithImpl<$Res>
    implements $BridgeAcpContentBlock_TextCopyWith<$Res> {
  _$BridgeAcpContentBlock_TextCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock_Text _self;
  final $Res Function(BridgeAcpContentBlock_Text) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpContentBlock_Text(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpContentBlock_Image extends BridgeAcpContentBlock {
  const BridgeAcpContentBlock_Image({required this.data, required this.mimeType, this.uri, this.annotations,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String data;
 final  String mimeType;
 final  String? uri;
@override final  BridgeAcpAnnotations? annotations;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlock_ImageCopyWith<BridgeAcpContentBlock_Image> get copyWith => _$BridgeAcpContentBlock_ImageCopyWithImpl<BridgeAcpContentBlock_Image>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock_Image&&(identical(other.data, data) || other.data == data)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,data,mimeType,uri,annotations,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpContentBlock.image(data: $data, mimeType: $mimeType, uri: $uri, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlock_ImageCopyWith<$Res> implements $BridgeAcpContentBlockCopyWith<$Res> {
  factory $BridgeAcpContentBlock_ImageCopyWith(BridgeAcpContentBlock_Image value, $Res Function(BridgeAcpContentBlock_Image) _then) = _$BridgeAcpContentBlock_ImageCopyWithImpl;
@override @useResult
$Res call({
 String data, String mimeType, String? uri, BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpContentBlock_ImageCopyWithImpl<$Res>
    implements $BridgeAcpContentBlock_ImageCopyWith<$Res> {
  _$BridgeAcpContentBlock_ImageCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock_Image _self;
  final $Res Function(BridgeAcpContentBlock_Image) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? mimeType = null,Object? uri = freezed,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpContentBlock_Image(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,uri: freezed == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String?,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpContentBlock_Audio extends BridgeAcpContentBlock {
  const BridgeAcpContentBlock_Audio({required this.data, required this.mimeType, this.annotations,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String data;
 final  String mimeType;
@override final  BridgeAcpAnnotations? annotations;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlock_AudioCopyWith<BridgeAcpContentBlock_Audio> get copyWith => _$BridgeAcpContentBlock_AudioCopyWithImpl<BridgeAcpContentBlock_Audio>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock_Audio&&(identical(other.data, data) || other.data == data)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,data,mimeType,annotations,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpContentBlock.audio(data: $data, mimeType: $mimeType, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlock_AudioCopyWith<$Res> implements $BridgeAcpContentBlockCopyWith<$Res> {
  factory $BridgeAcpContentBlock_AudioCopyWith(BridgeAcpContentBlock_Audio value, $Res Function(BridgeAcpContentBlock_Audio) _then) = _$BridgeAcpContentBlock_AudioCopyWithImpl;
@override @useResult
$Res call({
 String data, String mimeType, BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpContentBlock_AudioCopyWithImpl<$Res>
    implements $BridgeAcpContentBlock_AudioCopyWith<$Res> {
  _$BridgeAcpContentBlock_AudioCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock_Audio _self;
  final $Res Function(BridgeAcpContentBlock_Audio) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? data = null,Object? mimeType = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpContentBlock_Audio(
data: null == data ? _self.data : data // ignore: cast_nullable_to_non_nullable
as String,mimeType: null == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpContentBlock_ResourceLink extends BridgeAcpContentBlock {
  const BridgeAcpContentBlock_ResourceLink({required this.name, required this.uri, this.description, this.mimeType, this.size, this.title, this.annotations,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String name;
 final  String uri;
 final  String? description;
 final  String? mimeType;
 final  PlatformInt64? size;
 final  String? title;
@override final  BridgeAcpAnnotations? annotations;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlock_ResourceLinkCopyWith<BridgeAcpContentBlock_ResourceLink> get copyWith => _$BridgeAcpContentBlock_ResourceLinkCopyWithImpl<BridgeAcpContentBlock_ResourceLink>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock_ResourceLink&&(identical(other.name, name) || other.name == name)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.description, description) || other.description == description)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&(identical(other.size, size) || other.size == size)&&(identical(other.title, title) || other.title == title)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,name,uri,description,mimeType,size,title,annotations,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpContentBlock.resourceLink(name: $name, uri: $uri, description: $description, mimeType: $mimeType, size: $size, title: $title, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlock_ResourceLinkCopyWith<$Res> implements $BridgeAcpContentBlockCopyWith<$Res> {
  factory $BridgeAcpContentBlock_ResourceLinkCopyWith(BridgeAcpContentBlock_ResourceLink value, $Res Function(BridgeAcpContentBlock_ResourceLink) _then) = _$BridgeAcpContentBlock_ResourceLinkCopyWithImpl;
@override @useResult
$Res call({
 String name, String uri, String? description, String? mimeType, PlatformInt64? size, String? title, BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpContentBlock_ResourceLinkCopyWithImpl<$Res>
    implements $BridgeAcpContentBlock_ResourceLinkCopyWith<$Res> {
  _$BridgeAcpContentBlock_ResourceLinkCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock_ResourceLink _self;
  final $Res Function(BridgeAcpContentBlock_ResourceLink) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? name = null,Object? uri = null,Object? description = freezed,Object? mimeType = freezed,Object? size = freezed,Object? title = freezed,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpContentBlock_ResourceLink(
name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,description: freezed == description ? _self.description : description // ignore: cast_nullable_to_non_nullable
as String?,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,size: freezed == size ? _self.size : size // ignore: cast_nullable_to_non_nullable
as PlatformInt64?,title: freezed == title ? _self.title : title // ignore: cast_nullable_to_non_nullable
as String?,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpContentBlock_Resource extends BridgeAcpContentBlock {
  const BridgeAcpContentBlock_Resource({required this.resource, this.annotations,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  BridgeAcpEmbeddedResource resource;
@override final  BridgeAcpAnnotations? annotations;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpContentBlock_ResourceCopyWith<BridgeAcpContentBlock_Resource> get copyWith => _$BridgeAcpContentBlock_ResourceCopyWithImpl<BridgeAcpContentBlock_Resource>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpContentBlock_Resource&&(identical(other.resource, resource) || other.resource == resource)&&(identical(other.annotations, annotations) || other.annotations == annotations)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,resource,annotations,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpContentBlock.resource(resource: $resource, annotations: $annotations, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpContentBlock_ResourceCopyWith<$Res> implements $BridgeAcpContentBlockCopyWith<$Res> {
  factory $BridgeAcpContentBlock_ResourceCopyWith(BridgeAcpContentBlock_Resource value, $Res Function(BridgeAcpContentBlock_Resource) _then) = _$BridgeAcpContentBlock_ResourceCopyWithImpl;
@override @useResult
$Res call({
 BridgeAcpEmbeddedResource resource, BridgeAcpAnnotations? annotations, Map<String, BridgeAcpJsonValue>? meta
});


$BridgeAcpEmbeddedResourceCopyWith<$Res> get resource;

}
/// @nodoc
class _$BridgeAcpContentBlock_ResourceCopyWithImpl<$Res>
    implements $BridgeAcpContentBlock_ResourceCopyWith<$Res> {
  _$BridgeAcpContentBlock_ResourceCopyWithImpl(this._self, this._then);

  final BridgeAcpContentBlock_Resource _self;
  final $Res Function(BridgeAcpContentBlock_Resource) _then;

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? resource = null,Object? annotations = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpContentBlock_Resource(
resource: null == resource ? _self.resource : resource // ignore: cast_nullable_to_non_nullable
as BridgeAcpEmbeddedResource,annotations: freezed == annotations ? _self.annotations : annotations // ignore: cast_nullable_to_non_nullable
as BridgeAcpAnnotations?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

/// Create a copy of BridgeAcpContentBlock
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BridgeAcpEmbeddedResourceCopyWith<$Res> get resource {

  return $BridgeAcpEmbeddedResourceCopyWith<$Res>(_self.resource, (value) {
    return _then(_self.copyWith(resource: value));
  });
}
}

/// @nodoc
mixin _$BridgeAcpEmbeddedResource {

 String get uri; String? get mimeType; Map<String, BridgeAcpJsonValue>? get meta;
/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpEmbeddedResourceCopyWith<BridgeAcpEmbeddedResource> get copyWith => _$BridgeAcpEmbeddedResourceCopyWithImpl<BridgeAcpEmbeddedResource>(this as BridgeAcpEmbeddedResource, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BridgeAcpEmbeddedResource;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpEmbeddedResource&&(identical(other.uri, _this.uri) || other.uri == _this.uri)&&(identical(other.mimeType, _this.mimeType) || other.mimeType == _this.mimeType)&&const DeepCollectionEquality().equals(other.meta, _this.meta));
}


@override
int get hashCode {
  final _this = this as BridgeAcpEmbeddedResource;
  return Object.hash(runtimeType,_this.uri,_this.mimeType,const DeepCollectionEquality().hash(_this.meta));
}

@override
String toString() {
  final _this = this as BridgeAcpEmbeddedResource;
  return 'BridgeAcpEmbeddedResource(uri: ${_this.uri}, mimeType: ${_this.mimeType}, meta: ${_this.meta})';
}


}

/// @nodoc
abstract mixin class $BridgeAcpEmbeddedResourceCopyWith<$Res>  {
  factory $BridgeAcpEmbeddedResourceCopyWith(BridgeAcpEmbeddedResource value, $Res Function(BridgeAcpEmbeddedResource) _then) = _$BridgeAcpEmbeddedResourceCopyWithImpl;
@useResult
$Res call({
 String uri, String? mimeType, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpEmbeddedResourceCopyWithImpl<$Res>
    implements $BridgeAcpEmbeddedResourceCopyWith<$Res> {
  _$BridgeAcpEmbeddedResourceCopyWithImpl(this._self, this._then);

  final BridgeAcpEmbeddedResource _self;
  final $Res Function(BridgeAcpEmbeddedResource) _then;

/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? uri = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(_self.copyWith(
uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self.meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}

}


/// Adds pattern-matching-related methods to [BridgeAcpEmbeddedResource].
extension BridgeAcpEmbeddedResourcePatterns on BridgeAcpEmbeddedResource {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BridgeAcpEmbeddedResource_Text value)?  text,TResult Function( BridgeAcpEmbeddedResource_Blob value)?  blob,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text() when text != null:
return text(_that);case BridgeAcpEmbeddedResource_Blob() when blob != null:
return blob(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BridgeAcpEmbeddedResource_Text value)  text,required TResult Function( BridgeAcpEmbeddedResource_Blob value)  blob,}){
final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text():
return text(_that);case BridgeAcpEmbeddedResource_Blob():
return blob(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BridgeAcpEmbeddedResource_Text value)?  text,TResult? Function( BridgeAcpEmbeddedResource_Blob value)?  blob,}){
final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text() when text != null:
return text(_that);case BridgeAcpEmbeddedResource_Blob() when blob != null:
return blob(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)?  text,TResult Function( String blob,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)?  blob,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text() when text != null:
return text(_that.text,_that.uri,_that.mimeType,_that.meta);case BridgeAcpEmbeddedResource_Blob() when blob != null:
return blob(_that.blob,_that.uri,_that.mimeType,_that.meta);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)  text,required TResult Function( String blob,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)  blob,}) {final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text():
return text(_that.text,_that.uri,_that.mimeType,_that.meta);case BridgeAcpEmbeddedResource_Blob():
return blob(_that.blob,_that.uri,_that.mimeType,_that.meta);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)?  text,TResult? Function( String blob,  String uri,  String? mimeType,  Map<String, BridgeAcpJsonValue>? meta)?  blob,}) {final _that = this;
switch (_that) {
case BridgeAcpEmbeddedResource_Text() when text != null:
return text(_that.text,_that.uri,_that.mimeType,_that.meta);case BridgeAcpEmbeddedResource_Blob() when blob != null:
return blob(_that.blob,_that.uri,_that.mimeType,_that.meta);case _:
  return null;

}
}

}

/// @nodoc


class BridgeAcpEmbeddedResource_Text extends BridgeAcpEmbeddedResource {
  const BridgeAcpEmbeddedResource_Text({required this.text, required this.uri, this.mimeType,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String text;
@override final  String uri;
@override final  String? mimeType;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpEmbeddedResource_TextCopyWith<BridgeAcpEmbeddedResource_Text> get copyWith => _$BridgeAcpEmbeddedResource_TextCopyWithImpl<BridgeAcpEmbeddedResource_Text>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpEmbeddedResource_Text&&(identical(other.text, text) || other.text == text)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text,uri,mimeType,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpEmbeddedResource.text(text: $text, uri: $uri, mimeType: $mimeType, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpEmbeddedResource_TextCopyWith<$Res> implements $BridgeAcpEmbeddedResourceCopyWith<$Res> {
  factory $BridgeAcpEmbeddedResource_TextCopyWith(BridgeAcpEmbeddedResource_Text value, $Res Function(BridgeAcpEmbeddedResource_Text) _then) = _$BridgeAcpEmbeddedResource_TextCopyWithImpl;
@override @useResult
$Res call({
 String text, String uri, String? mimeType, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpEmbeddedResource_TextCopyWithImpl<$Res>
    implements $BridgeAcpEmbeddedResource_TextCopyWith<$Res> {
  _$BridgeAcpEmbeddedResource_TextCopyWithImpl(this._self, this._then);

  final BridgeAcpEmbeddedResource_Text _self;
  final $Res Function(BridgeAcpEmbeddedResource_Text) _then;

/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? text = null,Object? uri = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpEmbeddedResource_Text(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

/// @nodoc


class BridgeAcpEmbeddedResource_Blob extends BridgeAcpEmbeddedResource {
  const BridgeAcpEmbeddedResource_Blob({required this.blob, required this.uri, this.mimeType,  Map<String, BridgeAcpJsonValue>? meta}): _meta = meta,super._();


 final  String blob;
@override final  String uri;
@override final  String? mimeType;
 final  Map<String, BridgeAcpJsonValue>? _meta;
@override Map<String, BridgeAcpJsonValue>? get meta {
  final value = _meta;
  if (value == null) return null;
  if (_meta is EqualUnmodifiableMapView) return _meta;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(value);
}


/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BridgeAcpEmbeddedResource_BlobCopyWith<BridgeAcpEmbeddedResource_Blob> get copyWith => _$BridgeAcpEmbeddedResource_BlobCopyWithImpl<BridgeAcpEmbeddedResource_Blob>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BridgeAcpEmbeddedResource_Blob&&(identical(other.blob, blob) || other.blob == blob)&&(identical(other.uri, uri) || other.uri == uri)&&(identical(other.mimeType, mimeType) || other.mimeType == mimeType)&&const DeepCollectionEquality().equals(other.meta, _meta));
}


@override
int get hashCode {
    return Object.hash(runtimeType,blob,uri,mimeType,const DeepCollectionEquality().hash(_meta));
}

@override
String toString() {
    return 'BridgeAcpEmbeddedResource.blob(blob: $blob, uri: $uri, mimeType: $mimeType, meta: $meta)';
}


}

/// @nodoc
abstract mixin class $BridgeAcpEmbeddedResource_BlobCopyWith<$Res> implements $BridgeAcpEmbeddedResourceCopyWith<$Res> {
  factory $BridgeAcpEmbeddedResource_BlobCopyWith(BridgeAcpEmbeddedResource_Blob value, $Res Function(BridgeAcpEmbeddedResource_Blob) _then) = _$BridgeAcpEmbeddedResource_BlobCopyWithImpl;
@override @useResult
$Res call({
 String blob, String uri, String? mimeType, Map<String, BridgeAcpJsonValue>? meta
});




}
/// @nodoc
class _$BridgeAcpEmbeddedResource_BlobCopyWithImpl<$Res>
    implements $BridgeAcpEmbeddedResource_BlobCopyWith<$Res> {
  _$BridgeAcpEmbeddedResource_BlobCopyWithImpl(this._self, this._then);

  final BridgeAcpEmbeddedResource_Blob _self;
  final $Res Function(BridgeAcpEmbeddedResource_Blob) _then;

/// Create a copy of BridgeAcpEmbeddedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? blob = null,Object? uri = null,Object? mimeType = freezed,Object? meta = freezed,}) {
  return _then(BridgeAcpEmbeddedResource_Blob(
blob: null == blob ? _self.blob : blob // ignore: cast_nullable_to_non_nullable
as String,uri: null == uri ? _self.uri : uri // ignore: cast_nullable_to_non_nullable
as String,mimeType: freezed == mimeType ? _self.mimeType : mimeType // ignore: cast_nullable_to_non_nullable
as String?,meta: freezed == meta ? _self._meta : meta // ignore: cast_nullable_to_non_nullable
as Map<String, BridgeAcpJsonValue>?,
  ));
}


}

// dart format on
