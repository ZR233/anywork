// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_content_nested.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadAttachmentView {

 String get id; AttachmentModality get modality; String get mediaType; int get byteSize; String? get filename; int? get width; int? get height;
/// Create a copy of ThreadAttachmentView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAttachmentViewCopyWith<ThreadAttachmentView> get copyWith => _$ThreadAttachmentViewCopyWithImpl<ThreadAttachmentView>(this as ThreadAttachmentView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAttachmentView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAttachmentView&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.modality, _this.modality) || other.modality == _this.modality)&&(identical(other.mediaType, _this.mediaType) || other.mediaType == _this.mediaType)&&(identical(other.byteSize, _this.byteSize) || other.byteSize == _this.byteSize)&&(identical(other.filename, _this.filename) || other.filename == _this.filename)&&(identical(other.width, _this.width) || other.width == _this.width)&&(identical(other.height, _this.height) || other.height == _this.height));
}


@override
int get hashCode {
  final _this = this as ThreadAttachmentView;
  return Object.hash(runtimeType,_this.id,_this.modality,_this.mediaType,_this.byteSize,_this.filename,_this.width,_this.height);
}



}

/// @nodoc
abstract mixin class $ThreadAttachmentViewCopyWith<$Res>  {
  factory $ThreadAttachmentViewCopyWith(ThreadAttachmentView value, $Res Function(ThreadAttachmentView) _then) = _$ThreadAttachmentViewCopyWithImpl;
@useResult
$Res call({
 String id, AttachmentModality modality, String mediaType, int byteSize, String? filename, int? width, int? height
});




}
/// @nodoc
class _$ThreadAttachmentViewCopyWithImpl<$Res>
    implements $ThreadAttachmentViewCopyWith<$Res> {
  _$ThreadAttachmentViewCopyWithImpl(this._self, this._then);

  final ThreadAttachmentView _self;
  final $Res Function(ThreadAttachmentView) _then;

/// Create a copy of ThreadAttachmentView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? modality = null,Object? mediaType = null,Object? byteSize = null,Object? filename = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(ThreadAttachmentView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as AttachmentModality,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,filename: freezed == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadAttachmentView].
extension ThreadAttachmentViewPatterns on ThreadAttachmentView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadAttachmentView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadAttachmentView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadAttachmentView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadAttachmentView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadAttachmentView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadAttachmentView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  AttachmentModality modality,  String mediaType,  int byteSize,  String? filename,  int? width,  int? height)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadAttachmentView() when $default != null:
return $default(_that.id,_that.modality,_that.mediaType,_that.byteSize,_that.filename,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  AttachmentModality modality,  String mediaType,  int byteSize,  String? filename,  int? width,  int? height)  $default,) {final _that = this;
switch (_that) {
case _ThreadAttachmentView():
return $default(_that.id,_that.modality,_that.mediaType,_that.byteSize,_that.filename,_that.width,_that.height);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  AttachmentModality modality,  String mediaType,  int byteSize,  String? filename,  int? width,  int? height)?  $default,) {final _that = this;
switch (_that) {
case _ThreadAttachmentView() when $default != null:
return $default(_that.id,_that.modality,_that.mediaType,_that.byteSize,_that.filename,_that.width,_that.height);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadAttachmentView implements ThreadAttachmentView {
  const _ThreadAttachmentView({required this.id, required this.modality, required this.mediaType, required this.byteSize, this.filename, this.width, this.height});


@override final  String id;
@override final  AttachmentModality modality;
@override final  String mediaType;
@override final  int byteSize;
@override final  String? filename;
@override final  int? width;
@override final  int? height;

/// Create a copy of ThreadAttachmentView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadAttachmentViewCopyWith<_ThreadAttachmentView> get copyWith => __$ThreadAttachmentViewCopyWithImpl<_ThreadAttachmentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadAttachmentView&&(identical(other.id, id) || other.id == id)&&(identical(other.modality, modality) || other.modality == modality)&&(identical(other.mediaType, mediaType) || other.mediaType == mediaType)&&(identical(other.byteSize, byteSize) || other.byteSize == byteSize)&&(identical(other.filename, filename) || other.filename == filename)&&(identical(other.width, width) || other.width == width)&&(identical(other.height, height) || other.height == height));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,modality,mediaType,byteSize,filename,width,height);
}



}

/// @nodoc
abstract mixin class _$ThreadAttachmentViewCopyWith<$Res> implements $ThreadAttachmentViewCopyWith<$Res> {
  factory _$ThreadAttachmentViewCopyWith(_ThreadAttachmentView value, $Res Function(_ThreadAttachmentView) _then) = __$ThreadAttachmentViewCopyWithImpl;
@override @useResult
$Res call({
 String id, AttachmentModality modality, String mediaType, int byteSize, String? filename, int? width, int? height
});




}
/// @nodoc
class __$ThreadAttachmentViewCopyWithImpl<$Res>
    implements _$ThreadAttachmentViewCopyWith<$Res> {
  __$ThreadAttachmentViewCopyWithImpl(this._self, this._then);

  final _ThreadAttachmentView _self;
  final $Res Function(_ThreadAttachmentView) _then;

/// Create a copy of ThreadAttachmentView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? modality = null,Object? mediaType = null,Object? byteSize = null,Object? filename = freezed,Object? width = freezed,Object? height = freezed,}) {
  return _then(_ThreadAttachmentView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,modality: null == modality ? _self.modality : modality // ignore: cast_nullable_to_non_nullable
as AttachmentModality,mediaType: null == mediaType ? _self.mediaType : mediaType // ignore: cast_nullable_to_non_nullable
as String,byteSize: null == byteSize ? _self.byteSize : byteSize // ignore: cast_nullable_to_non_nullable
as int,filename: freezed == filename ? _self.filename : filename // ignore: cast_nullable_to_non_nullable
as String?,width: freezed == width ? _self.width : width // ignore: cast_nullable_to_non_nullable
as int?,height: freezed == height ? _self.height : height // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$SkillResourceBaseView {

 SkillResourceBaseKind get kind; String get value;
/// Create a copy of SkillResourceBaseView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillResourceBaseViewCopyWith<SkillResourceBaseView> get copyWith => _$SkillResourceBaseViewCopyWithImpl<SkillResourceBaseView>(this as SkillResourceBaseView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillResourceBaseView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillResourceBaseView&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as SkillResourceBaseView;
  return Object.hash(runtimeType,_this.kind,_this.value);
}



}

/// @nodoc
abstract mixin class $SkillResourceBaseViewCopyWith<$Res>  {
  factory $SkillResourceBaseViewCopyWith(SkillResourceBaseView value, $Res Function(SkillResourceBaseView) _then) = _$SkillResourceBaseViewCopyWithImpl;
@useResult
$Res call({
 SkillResourceBaseKind kind, String value
});




}
/// @nodoc
class _$SkillResourceBaseViewCopyWithImpl<$Res>
    implements $SkillResourceBaseViewCopyWith<$Res> {
  _$SkillResourceBaseViewCopyWithImpl(this._self, this._then);

  final SkillResourceBaseView _self;
  final $Res Function(SkillResourceBaseView) _then;

/// Create a copy of SkillResourceBaseView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? value = null,}) {
  return _then(SkillResourceBaseView(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SkillResourceBaseKind,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillResourceBaseView].
extension SkillResourceBaseViewPatterns on SkillResourceBaseView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillResourceBaseView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillResourceBaseView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillResourceBaseView value)  $default,){
final _that = this;
switch (_that) {
case _SkillResourceBaseView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillResourceBaseView value)?  $default,){
final _that = this;
switch (_that) {
case _SkillResourceBaseView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SkillResourceBaseKind kind,  String value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillResourceBaseView() when $default != null:
return $default(_that.kind,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SkillResourceBaseKind kind,  String value)  $default,) {final _that = this;
switch (_that) {
case _SkillResourceBaseView():
return $default(_that.kind,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SkillResourceBaseKind kind,  String value)?  $default,) {final _that = this;
switch (_that) {
case _SkillResourceBaseView() when $default != null:
return $default(_that.kind,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _SkillResourceBaseView implements SkillResourceBaseView {
  const _SkillResourceBaseView(this.kind, this.value);


@override final  SkillResourceBaseKind kind;
@override final  String value;

/// Create a copy of SkillResourceBaseView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillResourceBaseViewCopyWith<_SkillResourceBaseView> get copyWith => __$SkillResourceBaseViewCopyWithImpl<_SkillResourceBaseView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillResourceBaseView&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,value);
}



}

/// @nodoc
abstract mixin class _$SkillResourceBaseViewCopyWith<$Res> implements $SkillResourceBaseViewCopyWith<$Res> {
  factory _$SkillResourceBaseViewCopyWith(_SkillResourceBaseView value, $Res Function(_SkillResourceBaseView) _then) = __$SkillResourceBaseViewCopyWithImpl;
@override @useResult
$Res call({
 SkillResourceBaseKind kind, String value
});




}
/// @nodoc
class __$SkillResourceBaseViewCopyWithImpl<$Res>
    implements _$SkillResourceBaseViewCopyWith<$Res> {
  __$SkillResourceBaseViewCopyWithImpl(this._self, this._then);

  final _SkillResourceBaseView _self;
  final $Res Function(_SkillResourceBaseView) _then;

/// Create a copy of SkillResourceBaseView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? value = null,}) {
  return _then(_SkillResourceBaseView(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SkillResourceBaseKind,null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$SkillActivationCauseView {

 SkillActivationCauseKind get kind; String get id;
/// Create a copy of SkillActivationCauseView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillActivationCauseViewCopyWith<SkillActivationCauseView> get copyWith => _$SkillActivationCauseViewCopyWithImpl<SkillActivationCauseView>(this as SkillActivationCauseView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillActivationCauseView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillActivationCauseView&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.id, _this.id) || other.id == _this.id));
}


@override
int get hashCode {
  final _this = this as SkillActivationCauseView;
  return Object.hash(runtimeType,_this.kind,_this.id);
}



}

/// @nodoc
abstract mixin class $SkillActivationCauseViewCopyWith<$Res>  {
  factory $SkillActivationCauseViewCopyWith(SkillActivationCauseView value, $Res Function(SkillActivationCauseView) _then) = _$SkillActivationCauseViewCopyWithImpl;
@useResult
$Res call({
 SkillActivationCauseKind kind, String id
});




}
/// @nodoc
class _$SkillActivationCauseViewCopyWithImpl<$Res>
    implements $SkillActivationCauseViewCopyWith<$Res> {
  _$SkillActivationCauseViewCopyWithImpl(this._self, this._then);

  final SkillActivationCauseView _self;
  final $Res Function(SkillActivationCauseView) _then;

/// Create a copy of SkillActivationCauseView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? id = null,}) {
  return _then(SkillActivationCauseView(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SkillActivationCauseKind,null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [SkillActivationCauseView].
extension SkillActivationCauseViewPatterns on SkillActivationCauseView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillActivationCauseView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillActivationCauseView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillActivationCauseView value)  $default,){
final _that = this;
switch (_that) {
case _SkillActivationCauseView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillActivationCauseView value)?  $default,){
final _that = this;
switch (_that) {
case _SkillActivationCauseView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SkillActivationCauseKind kind,  String id)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillActivationCauseView() when $default != null:
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SkillActivationCauseKind kind,  String id)  $default,) {final _that = this;
switch (_that) {
case _SkillActivationCauseView():
return $default(_that.kind,_that.id);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SkillActivationCauseKind kind,  String id)?  $default,) {final _that = this;
switch (_that) {
case _SkillActivationCauseView() when $default != null:
return $default(_that.kind,_that.id);case _:
  return null;

}
}

}

/// @nodoc


class _SkillActivationCauseView implements SkillActivationCauseView {
  const _SkillActivationCauseView(this.kind, this.id);


@override final  SkillActivationCauseKind kind;
@override final  String id;

/// Create a copy of SkillActivationCauseView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillActivationCauseViewCopyWith<_SkillActivationCauseView> get copyWith => __$SkillActivationCauseViewCopyWithImpl<_SkillActivationCauseView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillActivationCauseView&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.id, id) || other.id == id));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,id);
}



}

/// @nodoc
abstract mixin class _$SkillActivationCauseViewCopyWith<$Res> implements $SkillActivationCauseViewCopyWith<$Res> {
  factory _$SkillActivationCauseViewCopyWith(_SkillActivationCauseView value, $Res Function(_SkillActivationCauseView) _then) = __$SkillActivationCauseViewCopyWithImpl;
@override @useResult
$Res call({
 SkillActivationCauseKind kind, String id
});




}
/// @nodoc
class __$SkillActivationCauseViewCopyWithImpl<$Res>
    implements _$SkillActivationCauseViewCopyWith<$Res> {
  __$SkillActivationCauseViewCopyWithImpl(this._self, this._then);

  final _SkillActivationCauseView _self;
  final $Res Function(_SkillActivationCauseView) _then;

/// Create a copy of SkillActivationCauseView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? id = null,}) {
  return _then(_SkillActivationCauseView(
null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as SkillActivationCauseKind,null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadContentLifecycleView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContentLifecycleView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadContentLifecycleViewCopyWith<$Res>  {
$ThreadContentLifecycleViewCopyWith(ThreadContentLifecycleView _, $Res Function(ThreadContentLifecycleView) __);
}


/// Adds pattern-matching-related methods to [ThreadContentLifecycleView].
extension ThreadContentLifecycleViewPatterns on ThreadContentLifecycleView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( StreamingThreadContentView value)?  streaming,TResult Function( CompletedThreadContentView value)?  completed,TResult Function( FailedThreadContentView value)?  failed,TResult Function( CancelledThreadContentView value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case StreamingThreadContentView() when streaming != null:
return streaming(_that);case CompletedThreadContentView() when completed != null:
return completed(_that);case FailedThreadContentView() when failed != null:
return failed(_that);case CancelledThreadContentView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( StreamingThreadContentView value)  streaming,required TResult Function( CompletedThreadContentView value)  completed,required TResult Function( FailedThreadContentView value)  failed,required TResult Function( CancelledThreadContentView value)  cancelled,}){
final _that = this;
switch (_that) {
case StreamingThreadContentView():
return streaming(_that);case CompletedThreadContentView():
return completed(_that);case FailedThreadContentView():
return failed(_that);case CancelledThreadContentView():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( StreamingThreadContentView value)?  streaming,TResult? Function( CompletedThreadContentView value)?  completed,TResult? Function( FailedThreadContentView value)?  failed,TResult? Function( CancelledThreadContentView value)?  cancelled,}){
final _that = this;
switch (_that) {
case StreamingThreadContentView() when streaming != null:
return streaming(_that);case CompletedThreadContentView() when completed != null:
return completed(_that);case FailedThreadContentView() when failed != null:
return failed(_that);case CancelledThreadContentView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  streaming,TResult Function( int completedAt)?  completed,TResult Function( int failedAt,  String error)?  failed,TResult Function( int cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case StreamingThreadContentView() when streaming != null:
return streaming();case CompletedThreadContentView() when completed != null:
return completed(_that.completedAt);case FailedThreadContentView() when failed != null:
return failed(_that.failedAt,_that.error);case CancelledThreadContentView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  streaming,required TResult Function( int completedAt)  completed,required TResult Function( int failedAt,  String error)  failed,required TResult Function( int cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case StreamingThreadContentView():
return streaming();case CompletedThreadContentView():
return completed(_that.completedAt);case FailedThreadContentView():
return failed(_that.failedAt,_that.error);case CancelledThreadContentView():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  streaming,TResult? Function( int completedAt)?  completed,TResult? Function( int failedAt,  String error)?  failed,TResult? Function( int cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case StreamingThreadContentView() when streaming != null:
return streaming();case CompletedThreadContentView() when completed != null:
return completed(_that.completedAt);case FailedThreadContentView() when failed != null:
return failed(_that.failedAt,_that.error);case CancelledThreadContentView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class StreamingThreadContentView extends ThreadContentLifecycleView {
  const StreamingThreadContentView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StreamingThreadContentView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class CompletedThreadContentView extends ThreadContentLifecycleView {
  const CompletedThreadContentView(this.completedAt): super._();


 final  int completedAt;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletedThreadContentViewCopyWith<CompletedThreadContentView> get copyWith => _$CompletedThreadContentViewCopyWithImpl<CompletedThreadContentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletedThreadContentView&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt);
}



}

/// @nodoc
abstract mixin class $CompletedThreadContentViewCopyWith<$Res> implements $ThreadContentLifecycleViewCopyWith<$Res> {
  factory $CompletedThreadContentViewCopyWith(CompletedThreadContentView value, $Res Function(CompletedThreadContentView) _then) = _$CompletedThreadContentViewCopyWithImpl;
@useResult
$Res call({
 int completedAt
});




}
/// @nodoc
class _$CompletedThreadContentViewCopyWithImpl<$Res>
    implements $CompletedThreadContentViewCopyWith<$Res> {
  _$CompletedThreadContentViewCopyWithImpl(this._self, this._then);

  final CompletedThreadContentView _self;
  final $Res Function(CompletedThreadContentView) _then;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,}) {
  return _then(CompletedThreadContentView(
null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class FailedThreadContentView extends ThreadContentLifecycleView {
  const FailedThreadContentView(this.failedAt, this.error): super._();


 final  int failedAt;
 final  String error;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedThreadContentViewCopyWith<FailedThreadContentView> get copyWith => _$FailedThreadContentViewCopyWithImpl<FailedThreadContentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedThreadContentView&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}



}

/// @nodoc
abstract mixin class $FailedThreadContentViewCopyWith<$Res> implements $ThreadContentLifecycleViewCopyWith<$Res> {
  factory $FailedThreadContentViewCopyWith(FailedThreadContentView value, $Res Function(FailedThreadContentView) _then) = _$FailedThreadContentViewCopyWithImpl;
@useResult
$Res call({
 int failedAt, String error
});




}
/// @nodoc
class _$FailedThreadContentViewCopyWithImpl<$Res>
    implements $FailedThreadContentViewCopyWith<$Res> {
  _$FailedThreadContentViewCopyWithImpl(this._self, this._then);

  final FailedThreadContentView _self;
  final $Res Function(FailedThreadContentView) _then;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(FailedThreadContentView(
null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancelledThreadContentView extends ThreadContentLifecycleView {
  const CancelledThreadContentView(this.cancelledAt, this.reason): super._();


 final  int cancelledAt;
 final  String reason;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledThreadContentViewCopyWith<CancelledThreadContentView> get copyWith => _$CancelledThreadContentViewCopyWithImpl<CancelledThreadContentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledThreadContentView&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledThreadContentViewCopyWith<$Res> implements $ThreadContentLifecycleViewCopyWith<$Res> {
  factory $CancelledThreadContentViewCopyWith(CancelledThreadContentView value, $Res Function(CancelledThreadContentView) _then) = _$CancelledThreadContentViewCopyWithImpl;
@useResult
$Res call({
 int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledThreadContentViewCopyWithImpl<$Res>
    implements $CancelledThreadContentViewCopyWith<$Res> {
  _$CancelledThreadContentViewCopyWithImpl(this._self, this._then);

  final CancelledThreadContentView _self;
  final $Res Function(CancelledThreadContentView) _then;

/// Create a copy of ThreadContentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledThreadContentView(
null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadToolInvocationView {

 String get toolCallId; String get name; String get arguments; String? get callId; String? get providerItemId; String? get workingDirectory; String? get taskId;
/// Create a copy of ThreadToolInvocationView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolInvocationViewCopyWith<ThreadToolInvocationView> get copyWith => _$ThreadToolInvocationViewCopyWithImpl<ThreadToolInvocationView>(this as ThreadToolInvocationView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadToolInvocationView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolInvocationView&&(identical(other.toolCallId, _this.toolCallId) || other.toolCallId == _this.toolCallId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.arguments, _this.arguments) || other.arguments == _this.arguments)&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.providerItemId, _this.providerItemId) || other.providerItemId == _this.providerItemId)&&(identical(other.workingDirectory, _this.workingDirectory) || other.workingDirectory == _this.workingDirectory)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId));
}


@override
int get hashCode {
  final _this = this as ThreadToolInvocationView;
  return Object.hash(runtimeType,_this.toolCallId,_this.name,_this.arguments,_this.callId,_this.providerItemId,_this.workingDirectory,_this.taskId);
}



}

/// @nodoc
abstract mixin class $ThreadToolInvocationViewCopyWith<$Res>  {
  factory $ThreadToolInvocationViewCopyWith(ThreadToolInvocationView value, $Res Function(ThreadToolInvocationView) _then) = _$ThreadToolInvocationViewCopyWithImpl;
@useResult
$Res call({
 String toolCallId, String name, String arguments, String? callId, String? providerItemId, String? workingDirectory, String? taskId
});




}
/// @nodoc
class _$ThreadToolInvocationViewCopyWithImpl<$Res>
    implements $ThreadToolInvocationViewCopyWith<$Res> {
  _$ThreadToolInvocationViewCopyWithImpl(this._self, this._then);

  final ThreadToolInvocationView _self;
  final $Res Function(ThreadToolInvocationView) _then;

/// Create a copy of ThreadToolInvocationView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toolCallId = null,Object? name = null,Object? arguments = null,Object? callId = freezed,Object? providerItemId = freezed,Object? workingDirectory = freezed,Object? taskId = freezed,}) {
  return _then(ThreadToolInvocationView(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,callId: freezed == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String?,providerItemId: freezed == providerItemId ? _self.providerItemId : providerItemId // ignore: cast_nullable_to_non_nullable
as String?,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadToolInvocationView].
extension ThreadToolInvocationViewPatterns on ThreadToolInvocationView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadToolInvocationView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadToolInvocationView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadToolInvocationView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadToolInvocationView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadToolInvocationView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadToolInvocationView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String toolCallId,  String name,  String arguments,  String? callId,  String? providerItemId,  String? workingDirectory,  String? taskId)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadToolInvocationView() when $default != null:
return $default(_that.toolCallId,_that.name,_that.arguments,_that.callId,_that.providerItemId,_that.workingDirectory,_that.taskId);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String toolCallId,  String name,  String arguments,  String? callId,  String? providerItemId,  String? workingDirectory,  String? taskId)  $default,) {final _that = this;
switch (_that) {
case _ThreadToolInvocationView():
return $default(_that.toolCallId,_that.name,_that.arguments,_that.callId,_that.providerItemId,_that.workingDirectory,_that.taskId);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String toolCallId,  String name,  String arguments,  String? callId,  String? providerItemId,  String? workingDirectory,  String? taskId)?  $default,) {final _that = this;
switch (_that) {
case _ThreadToolInvocationView() when $default != null:
return $default(_that.toolCallId,_that.name,_that.arguments,_that.callId,_that.providerItemId,_that.workingDirectory,_that.taskId);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadToolInvocationView extends ThreadToolInvocationView {
  const _ThreadToolInvocationView({required this.toolCallId, required this.name, required this.arguments, this.callId, this.providerItemId, this.workingDirectory, this.taskId}): super._();


@override final  String toolCallId;
@override final  String name;
@override final  String arguments;
@override final  String? callId;
@override final  String? providerItemId;
@override final  String? workingDirectory;
@override final  String? taskId;

/// Create a copy of ThreadToolInvocationView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadToolInvocationViewCopyWith<_ThreadToolInvocationView> get copyWith => __$ThreadToolInvocationViewCopyWithImpl<_ThreadToolInvocationView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadToolInvocationView&&(identical(other.toolCallId, toolCallId) || other.toolCallId == toolCallId)&&(identical(other.name, name) || other.name == name)&&(identical(other.arguments, arguments) || other.arguments == arguments)&&(identical(other.callId, callId) || other.callId == callId)&&(identical(other.providerItemId, providerItemId) || other.providerItemId == providerItemId)&&(identical(other.workingDirectory, workingDirectory) || other.workingDirectory == workingDirectory)&&(identical(other.taskId, taskId) || other.taskId == taskId));
}


@override
int get hashCode {
    return Object.hash(runtimeType,toolCallId,name,arguments,callId,providerItemId,workingDirectory,taskId);
}



}

/// @nodoc
abstract mixin class _$ThreadToolInvocationViewCopyWith<$Res> implements $ThreadToolInvocationViewCopyWith<$Res> {
  factory _$ThreadToolInvocationViewCopyWith(_ThreadToolInvocationView value, $Res Function(_ThreadToolInvocationView) _then) = __$ThreadToolInvocationViewCopyWithImpl;
@override @useResult
$Res call({
 String toolCallId, String name, String arguments, String? callId, String? providerItemId, String? workingDirectory, String? taskId
});




}
/// @nodoc
class __$ThreadToolInvocationViewCopyWithImpl<$Res>
    implements _$ThreadToolInvocationViewCopyWith<$Res> {
  __$ThreadToolInvocationViewCopyWithImpl(this._self, this._then);

  final _ThreadToolInvocationView _self;
  final $Res Function(_ThreadToolInvocationView) _then;

/// Create a copy of ThreadToolInvocationView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? toolCallId = null,Object? name = null,Object? arguments = null,Object? callId = freezed,Object? providerItemId = freezed,Object? workingDirectory = freezed,Object? taskId = freezed,}) {
  return _then(_ThreadToolInvocationView(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,callId: freezed == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String?,providerItemId: freezed == providerItemId ? _self.providerItemId : providerItemId // ignore: cast_nullable_to_non_nullable
as String?,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

/// @nodoc
mixin _$ThreadToolOutput {


/// Create a copy of ThreadToolOutput
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolOutputCopyWith<ThreadToolOutput> get copyWith => _$ThreadToolOutputCopyWithImpl<ThreadToolOutput>(this as ThreadToolOutput, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadToolOutput;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolOutput&&(identical(other.result, _this.result) || other.result == _this.result)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&const DeepCollectionEquality().equals(other.outputArtifacts, _this.outputArtifacts)&&(identical(other.exitCode, _this.exitCode) || other.exitCode == _this.exitCode));
}


@override
int get hashCode {
  final _this = this as ThreadToolOutput;
  return Object.hash(runtimeType,_this.result,const DeepCollectionEquality().hash(_this.attachments),const DeepCollectionEquality().hash(_this.outputArtifacts),_this.exitCode);
}



}

/// @nodoc
abstract mixin class $ThreadToolOutputCopyWith<$Res>  {
  factory $ThreadToolOutputCopyWith(ThreadToolOutput value, $Res Function(ThreadToolOutput) _then) = _$ThreadToolOutputCopyWithImpl;
@useResult
$Res call({
 String result, List<ThreadAttachmentView> attachments, List<OpaqueArtifactJson> outputArtifacts, int? exitCode
});




}
/// @nodoc
class _$ThreadToolOutputCopyWithImpl<$Res>
    implements $ThreadToolOutputCopyWith<$Res> {
  _$ThreadToolOutputCopyWithImpl(this._self, this._then);

  final ThreadToolOutput _self;
  final $Res Function(ThreadToolOutput) _then;

/// Create a copy of ThreadToolOutput
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? result = null,Object? attachments = null,Object? outputArtifacts = null,Object? exitCode = freezed,}) {
  return _then(ThreadToolOutput(
result: null == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<ThreadAttachmentView>,outputArtifacts: null == outputArtifacts ? _self.outputArtifacts : outputArtifacts // ignore: cast_nullable_to_non_nullable
as List<OpaqueArtifactJson>,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadToolOutput].
extension ThreadToolOutputPatterns on ThreadToolOutput {
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
mixin _$ThreadToolFailureView {

 ThreadToolFailureKindView get kind; String get message;
/// Create a copy of ThreadToolFailureView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadToolFailureViewCopyWith<ThreadToolFailureView> get copyWith => _$ThreadToolFailureViewCopyWithImpl<ThreadToolFailureView>(this as ThreadToolFailureView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadToolFailureView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolFailureView&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.message, _this.message) || other.message == _this.message));
}


@override
int get hashCode {
  final _this = this as ThreadToolFailureView;
  return Object.hash(runtimeType,_this.kind,_this.message);
}



}

/// @nodoc
abstract mixin class $ThreadToolFailureViewCopyWith<$Res>  {
  factory $ThreadToolFailureViewCopyWith(ThreadToolFailureView value, $Res Function(ThreadToolFailureView) _then) = _$ThreadToolFailureViewCopyWithImpl;
@useResult
$Res call({
 ThreadToolFailureKindView kind, String message
});




}
/// @nodoc
class _$ThreadToolFailureViewCopyWithImpl<$Res>
    implements $ThreadToolFailureViewCopyWith<$Res> {
  _$ThreadToolFailureViewCopyWithImpl(this._self, this._then);

  final ThreadToolFailureView _self;
  final $Res Function(ThreadToolFailureView) _then;

/// Create a copy of ThreadToolFailureView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? kind = null,Object? message = null,}) {
  return _then(ThreadToolFailureView(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadToolFailureKindView,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadToolFailureView].
extension ThreadToolFailureViewPatterns on ThreadToolFailureView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadToolFailureView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadToolFailureView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadToolFailureView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadToolFailureView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadToolFailureView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadToolFailureView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadToolFailureKindView kind,  String message)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadToolFailureView() when $default != null:
return $default(_that.kind,_that.message);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadToolFailureKindView kind,  String message)  $default,) {final _that = this;
switch (_that) {
case _ThreadToolFailureView():
return $default(_that.kind,_that.message);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadToolFailureKindView kind,  String message)?  $default,) {final _that = this;
switch (_that) {
case _ThreadToolFailureView() when $default != null:
return $default(_that.kind,_that.message);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadToolFailureView implements ThreadToolFailureView {
  const _ThreadToolFailureView({required this.kind, required this.message});


@override final  ThreadToolFailureKindView kind;
@override final  String message;

/// Create a copy of ThreadToolFailureView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadToolFailureViewCopyWith<_ThreadToolFailureView> get copyWith => __$ThreadToolFailureViewCopyWithImpl<_ThreadToolFailureView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadToolFailureView&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.message, message) || other.message == message));
}


@override
int get hashCode {
    return Object.hash(runtimeType,kind,message);
}



}

/// @nodoc
abstract mixin class _$ThreadToolFailureViewCopyWith<$Res> implements $ThreadToolFailureViewCopyWith<$Res> {
  factory _$ThreadToolFailureViewCopyWith(_ThreadToolFailureView value, $Res Function(_ThreadToolFailureView) _then) = __$ThreadToolFailureViewCopyWithImpl;
@override @useResult
$Res call({
 ThreadToolFailureKindView kind, String message
});




}
/// @nodoc
class __$ThreadToolFailureViewCopyWithImpl<$Res>
    implements _$ThreadToolFailureViewCopyWith<$Res> {
  __$ThreadToolFailureViewCopyWithImpl(this._self, this._then);

  final _ThreadToolFailureView _self;
  final $Res Function(_ThreadToolFailureView) _then;

/// Create a copy of ThreadToolFailureView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? kind = null,Object? message = null,}) {
  return _then(_ThreadToolFailureView(
kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as ThreadToolFailureKindView,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadToolLifecycleView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadToolLifecycleView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadToolLifecycleViewCopyWith<$Res>  {
$ThreadToolLifecycleViewCopyWith(ThreadToolLifecycleView _, $Res Function(ThreadToolLifecycleView) __);
}


/// Adds pattern-matching-related methods to [ThreadToolLifecycleView].
extension ThreadToolLifecycleViewPatterns on ThreadToolLifecycleView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueuedThreadToolView value)?  queued,TResult Function( StartedThreadToolView value)?  started,TResult Function( StreamingThreadToolView value)?  streaming,TResult Function( AwaitingApprovalThreadToolView value)?  awaitingApproval,TResult Function( ApprovedThreadToolView value)?  approved,TResult Function( RunningThreadToolView value)?  running,TResult Function( CancellingThreadToolView value)?  cancelling,TResult Function( InterruptedThreadToolView value)?  interrupted,TResult Function( SucceededThreadToolView value)?  succeeded,TResult Function( FailedThreadToolView value)?  failed,TResult Function( DeniedThreadToolView value)?  denied,TResult Function( CancelledThreadToolView value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueuedThreadToolView() when queued != null:
return queued(_that);case StartedThreadToolView() when started != null:
return started(_that);case StreamingThreadToolView() when streaming != null:
return streaming(_that);case AwaitingApprovalThreadToolView() when awaitingApproval != null:
return awaitingApproval(_that);case ApprovedThreadToolView() when approved != null:
return approved(_that);case RunningThreadToolView() when running != null:
return running(_that);case CancellingThreadToolView() when cancelling != null:
return cancelling(_that);case InterruptedThreadToolView() when interrupted != null:
return interrupted(_that);case SucceededThreadToolView() when succeeded != null:
return succeeded(_that);case FailedThreadToolView() when failed != null:
return failed(_that);case DeniedThreadToolView() when denied != null:
return denied(_that);case CancelledThreadToolView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueuedThreadToolView value)  queued,required TResult Function( StartedThreadToolView value)  started,required TResult Function( StreamingThreadToolView value)  streaming,required TResult Function( AwaitingApprovalThreadToolView value)  awaitingApproval,required TResult Function( ApprovedThreadToolView value)  approved,required TResult Function( RunningThreadToolView value)  running,required TResult Function( CancellingThreadToolView value)  cancelling,required TResult Function( InterruptedThreadToolView value)  interrupted,required TResult Function( SucceededThreadToolView value)  succeeded,required TResult Function( FailedThreadToolView value)  failed,required TResult Function( DeniedThreadToolView value)  denied,required TResult Function( CancelledThreadToolView value)  cancelled,}){
final _that = this;
switch (_that) {
case QueuedThreadToolView():
return queued(_that);case StartedThreadToolView():
return started(_that);case StreamingThreadToolView():
return streaming(_that);case AwaitingApprovalThreadToolView():
return awaitingApproval(_that);case ApprovedThreadToolView():
return approved(_that);case RunningThreadToolView():
return running(_that);case CancellingThreadToolView():
return cancelling(_that);case InterruptedThreadToolView():
return interrupted(_that);case SucceededThreadToolView():
return succeeded(_that);case FailedThreadToolView():
return failed(_that);case DeniedThreadToolView():
return denied(_that);case CancelledThreadToolView():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueuedThreadToolView value)?  queued,TResult? Function( StartedThreadToolView value)?  started,TResult? Function( StreamingThreadToolView value)?  streaming,TResult? Function( AwaitingApprovalThreadToolView value)?  awaitingApproval,TResult? Function( ApprovedThreadToolView value)?  approved,TResult? Function( RunningThreadToolView value)?  running,TResult? Function( CancellingThreadToolView value)?  cancelling,TResult? Function( InterruptedThreadToolView value)?  interrupted,TResult? Function( SucceededThreadToolView value)?  succeeded,TResult? Function( FailedThreadToolView value)?  failed,TResult? Function( DeniedThreadToolView value)?  denied,TResult? Function( CancelledThreadToolView value)?  cancelled,}){
final _that = this;
switch (_that) {
case QueuedThreadToolView() when queued != null:
return queued(_that);case StartedThreadToolView() when started != null:
return started(_that);case StreamingThreadToolView() when streaming != null:
return streaming(_that);case AwaitingApprovalThreadToolView() when awaitingApproval != null:
return awaitingApproval(_that);case ApprovedThreadToolView() when approved != null:
return approved(_that);case RunningThreadToolView() when running != null:
return running(_that);case CancellingThreadToolView() when cancelling != null:
return cancelling(_that);case InterruptedThreadToolView() when interrupted != null:
return interrupted(_that);case SucceededThreadToolView() when succeeded != null:
return succeeded(_that);case FailedThreadToolView() when failed != null:
return failed(_that);case DeniedThreadToolView() when denied != null:
return denied(_that);case CancelledThreadToolView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  queued,TResult Function()?  started,TResult Function()?  streaming,TResult Function()?  awaitingApproval,TResult Function()?  approved,TResult Function( String streamedOutput)?  running,TResult Function( String streamedOutput)?  cancelling,TResult Function( int interruptedAt,  String reason)?  interrupted,TResult Function( int completedAt,  ThreadToolOutput output)?  succeeded,TResult Function( int failedAt,  ThreadToolFailureView failure,  ThreadToolOutput? output)?  failed,TResult Function( int deniedAt,  String reason)?  denied,TResult Function( int cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueuedThreadToolView() when queued != null:
return queued();case StartedThreadToolView() when started != null:
return started();case StreamingThreadToolView() when streaming != null:
return streaming();case AwaitingApprovalThreadToolView() when awaitingApproval != null:
return awaitingApproval();case ApprovedThreadToolView() when approved != null:
return approved();case RunningThreadToolView() when running != null:
return running(_that.streamedOutput);case CancellingThreadToolView() when cancelling != null:
return cancelling(_that.streamedOutput);case InterruptedThreadToolView() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case SucceededThreadToolView() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case FailedThreadToolView() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case DeniedThreadToolView() when denied != null:
return denied(_that.deniedAt,_that.reason);case CancelledThreadToolView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  queued,required TResult Function()  started,required TResult Function()  streaming,required TResult Function()  awaitingApproval,required TResult Function()  approved,required TResult Function( String streamedOutput)  running,required TResult Function( String streamedOutput)  cancelling,required TResult Function( int interruptedAt,  String reason)  interrupted,required TResult Function( int completedAt,  ThreadToolOutput output)  succeeded,required TResult Function( int failedAt,  ThreadToolFailureView failure,  ThreadToolOutput? output)  failed,required TResult Function( int deniedAt,  String reason)  denied,required TResult Function( int cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case QueuedThreadToolView():
return queued();case StartedThreadToolView():
return started();case StreamingThreadToolView():
return streaming();case AwaitingApprovalThreadToolView():
return awaitingApproval();case ApprovedThreadToolView():
return approved();case RunningThreadToolView():
return running(_that.streamedOutput);case CancellingThreadToolView():
return cancelling(_that.streamedOutput);case InterruptedThreadToolView():
return interrupted(_that.interruptedAt,_that.reason);case SucceededThreadToolView():
return succeeded(_that.completedAt,_that.output);case FailedThreadToolView():
return failed(_that.failedAt,_that.failure,_that.output);case DeniedThreadToolView():
return denied(_that.deniedAt,_that.reason);case CancelledThreadToolView():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  queued,TResult? Function()?  started,TResult? Function()?  streaming,TResult? Function()?  awaitingApproval,TResult? Function()?  approved,TResult? Function( String streamedOutput)?  running,TResult? Function( String streamedOutput)?  cancelling,TResult? Function( int interruptedAt,  String reason)?  interrupted,TResult? Function( int completedAt,  ThreadToolOutput output)?  succeeded,TResult? Function( int failedAt,  ThreadToolFailureView failure,  ThreadToolOutput? output)?  failed,TResult? Function( int deniedAt,  String reason)?  denied,TResult? Function( int cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case QueuedThreadToolView() when queued != null:
return queued();case StartedThreadToolView() when started != null:
return started();case StreamingThreadToolView() when streaming != null:
return streaming();case AwaitingApprovalThreadToolView() when awaitingApproval != null:
return awaitingApproval();case ApprovedThreadToolView() when approved != null:
return approved();case RunningThreadToolView() when running != null:
return running(_that.streamedOutput);case CancellingThreadToolView() when cancelling != null:
return cancelling(_that.streamedOutput);case InterruptedThreadToolView() when interrupted != null:
return interrupted(_that.interruptedAt,_that.reason);case SucceededThreadToolView() when succeeded != null:
return succeeded(_that.completedAt,_that.output);case FailedThreadToolView() when failed != null:
return failed(_that.failedAt,_that.failure,_that.output);case DeniedThreadToolView() when denied != null:
return denied(_that.deniedAt,_that.reason);case CancelledThreadToolView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class QueuedThreadToolView extends ThreadToolLifecycleView {
  const QueuedThreadToolView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedThreadToolView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class StartedThreadToolView extends ThreadToolLifecycleView {
  const StartedThreadToolView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StartedThreadToolView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class StreamingThreadToolView extends ThreadToolLifecycleView {
  const StreamingThreadToolView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StreamingThreadToolView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class AwaitingApprovalThreadToolView extends ThreadToolLifecycleView {
  const AwaitingApprovalThreadToolView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AwaitingApprovalThreadToolView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class ApprovedThreadToolView extends ThreadToolLifecycleView {
  const ApprovedThreadToolView(): super._();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ApprovedThreadToolView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RunningThreadToolView extends ThreadToolLifecycleView {
  const RunningThreadToolView(this.streamedOutput): super._();


 final  String streamedOutput;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RunningThreadToolViewCopyWith<RunningThreadToolView> get copyWith => _$RunningThreadToolViewCopyWithImpl<RunningThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningThreadToolView&&(identical(other.streamedOutput, streamedOutput) || other.streamedOutput == streamedOutput));
}


@override
int get hashCode {
    return Object.hash(runtimeType,streamedOutput);
}



}

/// @nodoc
abstract mixin class $RunningThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $RunningThreadToolViewCopyWith(RunningThreadToolView value, $Res Function(RunningThreadToolView) _then) = _$RunningThreadToolViewCopyWithImpl;
@useResult
$Res call({
 String streamedOutput
});




}
/// @nodoc
class _$RunningThreadToolViewCopyWithImpl<$Res>
    implements $RunningThreadToolViewCopyWith<$Res> {
  _$RunningThreadToolViewCopyWithImpl(this._self, this._then);

  final RunningThreadToolView _self;
  final $Res Function(RunningThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? streamedOutput = null,}) {
  return _then(RunningThreadToolView(
null == streamedOutput ? _self.streamedOutput : streamedOutput // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancellingThreadToolView extends ThreadToolLifecycleView {
  const CancellingThreadToolView(this.streamedOutput): super._();


 final  String streamedOutput;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancellingThreadToolViewCopyWith<CancellingThreadToolView> get copyWith => _$CancellingThreadToolViewCopyWithImpl<CancellingThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancellingThreadToolView&&(identical(other.streamedOutput, streamedOutput) || other.streamedOutput == streamedOutput));
}


@override
int get hashCode {
    return Object.hash(runtimeType,streamedOutput);
}



}

/// @nodoc
abstract mixin class $CancellingThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $CancellingThreadToolViewCopyWith(CancellingThreadToolView value, $Res Function(CancellingThreadToolView) _then) = _$CancellingThreadToolViewCopyWithImpl;
@useResult
$Res call({
 String streamedOutput
});




}
/// @nodoc
class _$CancellingThreadToolViewCopyWithImpl<$Res>
    implements $CancellingThreadToolViewCopyWith<$Res> {
  _$CancellingThreadToolViewCopyWithImpl(this._self, this._then);

  final CancellingThreadToolView _self;
  final $Res Function(CancellingThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? streamedOutput = null,}) {
  return _then(CancellingThreadToolView(
null == streamedOutput ? _self.streamedOutput : streamedOutput // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class InterruptedThreadToolView extends ThreadToolLifecycleView {
  const InterruptedThreadToolView(this.interruptedAt, this.reason): super._();


 final  int interruptedAt;
 final  String reason;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InterruptedThreadToolViewCopyWith<InterruptedThreadToolView> get copyWith => _$InterruptedThreadToolViewCopyWithImpl<InterruptedThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InterruptedThreadToolView&&(identical(other.interruptedAt, interruptedAt) || other.interruptedAt == interruptedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,interruptedAt,reason);
}



}

/// @nodoc
abstract mixin class $InterruptedThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $InterruptedThreadToolViewCopyWith(InterruptedThreadToolView value, $Res Function(InterruptedThreadToolView) _then) = _$InterruptedThreadToolViewCopyWithImpl;
@useResult
$Res call({
 int interruptedAt, String reason
});




}
/// @nodoc
class _$InterruptedThreadToolViewCopyWithImpl<$Res>
    implements $InterruptedThreadToolViewCopyWith<$Res> {
  _$InterruptedThreadToolViewCopyWithImpl(this._self, this._then);

  final InterruptedThreadToolView _self;
  final $Res Function(InterruptedThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? interruptedAt = null,Object? reason = null,}) {
  return _then(InterruptedThreadToolView(
null == interruptedAt ? _self.interruptedAt : interruptedAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class SucceededThreadToolView extends ThreadToolLifecycleView {
  const SucceededThreadToolView(this.completedAt, this.output): super._();


 final  int completedAt;
 final  ThreadToolOutput output;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SucceededThreadToolViewCopyWith<SucceededThreadToolView> get copyWith => _$SucceededThreadToolViewCopyWithImpl<SucceededThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SucceededThreadToolView&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,output);
}



}

/// @nodoc
abstract mixin class $SucceededThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $SucceededThreadToolViewCopyWith(SucceededThreadToolView value, $Res Function(SucceededThreadToolView) _then) = _$SucceededThreadToolViewCopyWithImpl;
@useResult
$Res call({
 int completedAt, ThreadToolOutput output
});


$ThreadToolOutputCopyWith<$Res> get output;

}
/// @nodoc
class _$SucceededThreadToolViewCopyWithImpl<$Res>
    implements $SucceededThreadToolViewCopyWith<$Res> {
  _$SucceededThreadToolViewCopyWithImpl(this._self, this._then);

  final SucceededThreadToolView _self;
  final $Res Function(SucceededThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? output = null,}) {
  return _then(SucceededThreadToolView(
null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,null == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as ThreadToolOutput,
  ));
}

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolOutputCopyWith<$Res> get output {

  return $ThreadToolOutputCopyWith<$Res>(_self.output, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}

/// @nodoc


class FailedThreadToolView extends ThreadToolLifecycleView {
  const FailedThreadToolView(this.failedAt, this.failure, this.output): super._();


 final  int failedAt;
 final  ThreadToolFailureView failure;
 final  ThreadToolOutput? output;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedThreadToolViewCopyWith<FailedThreadToolView> get copyWith => _$FailedThreadToolViewCopyWithImpl<FailedThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedThreadToolView&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.failure, failure) || other.failure == failure)&&(identical(other.output, output) || other.output == output));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,failure,output);
}



}

/// @nodoc
abstract mixin class $FailedThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $FailedThreadToolViewCopyWith(FailedThreadToolView value, $Res Function(FailedThreadToolView) _then) = _$FailedThreadToolViewCopyWithImpl;
@useResult
$Res call({
 int failedAt, ThreadToolFailureView failure, ThreadToolOutput? output
});


$ThreadToolFailureViewCopyWith<$Res> get failure;$ThreadToolOutputCopyWith<$Res>? get output;

}
/// @nodoc
class _$FailedThreadToolViewCopyWithImpl<$Res>
    implements $FailedThreadToolViewCopyWith<$Res> {
  _$FailedThreadToolViewCopyWithImpl(this._self, this._then);

  final FailedThreadToolView _self;
  final $Res Function(FailedThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? failure = null,Object? output = freezed,}) {
  return _then(FailedThreadToolView(
null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,null == failure ? _self.failure : failure // ignore: cast_nullable_to_non_nullable
as ThreadToolFailureView,freezed == output ? _self.output : output // ignore: cast_nullable_to_non_nullable
as ThreadToolOutput?,
  ));
}

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolFailureViewCopyWith<$Res> get failure {

  return $ThreadToolFailureViewCopyWith<$Res>(_self.failure, (value) {
    return _then(_self.copyWith(failure: value));
  });
}/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolOutputCopyWith<$Res>? get output {
    if (_self.output == null) {
    return null;
  }

  return $ThreadToolOutputCopyWith<$Res>(_self.output!, (value) {
    return _then(_self.copyWith(output: value));
  });
}
}

/// @nodoc


class DeniedThreadToolView extends ThreadToolLifecycleView {
  const DeniedThreadToolView(this.deniedAt, this.reason): super._();


 final  int deniedAt;
 final  String reason;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeniedThreadToolViewCopyWith<DeniedThreadToolView> get copyWith => _$DeniedThreadToolViewCopyWithImpl<DeniedThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeniedThreadToolView&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}



}

/// @nodoc
abstract mixin class $DeniedThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $DeniedThreadToolViewCopyWith(DeniedThreadToolView value, $Res Function(DeniedThreadToolView) _then) = _$DeniedThreadToolViewCopyWithImpl;
@useResult
$Res call({
 int deniedAt, String reason
});




}
/// @nodoc
class _$DeniedThreadToolViewCopyWithImpl<$Res>
    implements $DeniedThreadToolViewCopyWith<$Res> {
  _$DeniedThreadToolViewCopyWithImpl(this._self, this._then);

  final DeniedThreadToolView _self;
  final $Res Function(DeniedThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(DeniedThreadToolView(
null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancelledThreadToolView extends ThreadToolLifecycleView {
  const CancelledThreadToolView(this.cancelledAt, this.reason): super._();


 final  int cancelledAt;
 final  String reason;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledThreadToolViewCopyWith<CancelledThreadToolView> get copyWith => _$CancelledThreadToolViewCopyWithImpl<CancelledThreadToolView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledThreadToolView&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledThreadToolViewCopyWith<$Res> implements $ThreadToolLifecycleViewCopyWith<$Res> {
  factory $CancelledThreadToolViewCopyWith(CancelledThreadToolView value, $Res Function(CancelledThreadToolView) _then) = _$CancelledThreadToolViewCopyWithImpl;
@useResult
$Res call({
 int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledThreadToolViewCopyWithImpl<$Res>
    implements $CancelledThreadToolViewCopyWith<$Res> {
  _$CancelledThreadToolViewCopyWithImpl(this._self, this._then);

  final CancelledThreadToolView _self;
  final $Res Function(CancelledThreadToolView) _then;

/// Create a copy of ThreadToolLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledThreadToolView(
null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadAgentIdentityView {

 String get id; String get path; String? get parentPath; String get role; String get task; int get depth;
/// Create a copy of ThreadAgentIdentityView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAgentIdentityViewCopyWith<ThreadAgentIdentityView> get copyWith => _$ThreadAgentIdentityViewCopyWithImpl<ThreadAgentIdentityView>(this as ThreadAgentIdentityView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAgentIdentityView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAgentIdentityView&&(identical(other.id, _this.id) || other.id == _this.id)&&(identical(other.path, _this.path) || other.path == _this.path)&&(identical(other.parentPath, _this.parentPath) || other.parentPath == _this.parentPath)&&(identical(other.role, _this.role) || other.role == _this.role)&&(identical(other.task, _this.task) || other.task == _this.task)&&(identical(other.depth, _this.depth) || other.depth == _this.depth));
}


@override
int get hashCode {
  final _this = this as ThreadAgentIdentityView;
  return Object.hash(runtimeType,_this.id,_this.path,_this.parentPath,_this.role,_this.task,_this.depth);
}



}

/// @nodoc
abstract mixin class $ThreadAgentIdentityViewCopyWith<$Res>  {
  factory $ThreadAgentIdentityViewCopyWith(ThreadAgentIdentityView value, $Res Function(ThreadAgentIdentityView) _then) = _$ThreadAgentIdentityViewCopyWithImpl;
@useResult
$Res call({
 String id, String path, String? parentPath, String role, String task, int depth
});




}
/// @nodoc
class _$ThreadAgentIdentityViewCopyWithImpl<$Res>
    implements $ThreadAgentIdentityViewCopyWith<$Res> {
  _$ThreadAgentIdentityViewCopyWithImpl(this._self, this._then);

  final ThreadAgentIdentityView _self;
  final $Res Function(ThreadAgentIdentityView) _then;

/// Create a copy of ThreadAgentIdentityView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? task = null,Object? depth = null,}) {
  return _then(ThreadAgentIdentityView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadAgentIdentityView].
extension ThreadAgentIdentityViewPatterns on ThreadAgentIdentityView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadAgentIdentityView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadAgentIdentityView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadAgentIdentityView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadAgentIdentityView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadAgentIdentityView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadAgentIdentityView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String id,  String path,  String? parentPath,  String role,  String task,  int depth)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadAgentIdentityView() when $default != null:
return $default(_that.id,_that.path,_that.parentPath,_that.role,_that.task,_that.depth);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String id,  String path,  String? parentPath,  String role,  String task,  int depth)  $default,) {final _that = this;
switch (_that) {
case _ThreadAgentIdentityView():
return $default(_that.id,_that.path,_that.parentPath,_that.role,_that.task,_that.depth);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String id,  String path,  String? parentPath,  String role,  String task,  int depth)?  $default,) {final _that = this;
switch (_that) {
case _ThreadAgentIdentityView() when $default != null:
return $default(_that.id,_that.path,_that.parentPath,_that.role,_that.task,_that.depth);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadAgentIdentityView implements ThreadAgentIdentityView {
  const _ThreadAgentIdentityView({required this.id, required this.path, this.parentPath, required this.role, required this.task, required this.depth});


@override final  String id;
@override final  String path;
@override final  String? parentPath;
@override final  String role;
@override final  String task;
@override final  int depth;

/// Create a copy of ThreadAgentIdentityView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadAgentIdentityViewCopyWith<_ThreadAgentIdentityView> get copyWith => __$ThreadAgentIdentityViewCopyWithImpl<_ThreadAgentIdentityView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadAgentIdentityView&&(identical(other.id, id) || other.id == id)&&(identical(other.path, path) || other.path == path)&&(identical(other.parentPath, parentPath) || other.parentPath == parentPath)&&(identical(other.role, role) || other.role == role)&&(identical(other.task, task) || other.task == task)&&(identical(other.depth, depth) || other.depth == depth));
}


@override
int get hashCode {
    return Object.hash(runtimeType,id,path,parentPath,role,task,depth);
}



}

/// @nodoc
abstract mixin class _$ThreadAgentIdentityViewCopyWith<$Res> implements $ThreadAgentIdentityViewCopyWith<$Res> {
  factory _$ThreadAgentIdentityViewCopyWith(_ThreadAgentIdentityView value, $Res Function(_ThreadAgentIdentityView) _then) = __$ThreadAgentIdentityViewCopyWithImpl;
@override @useResult
$Res call({
 String id, String path, String? parentPath, String role, String task, int depth
});




}
/// @nodoc
class __$ThreadAgentIdentityViewCopyWithImpl<$Res>
    implements _$ThreadAgentIdentityViewCopyWith<$Res> {
  __$ThreadAgentIdentityViewCopyWithImpl(this._self, this._then);

  final _ThreadAgentIdentityView _self;
  final $Res Function(_ThreadAgentIdentityView) _then;

/// Create a copy of ThreadAgentIdentityView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? path = null,Object? parentPath = freezed,Object? role = null,Object? task = null,Object? depth = null,}) {
  return _then(_ThreadAgentIdentityView(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,path: null == path ? _self.path : path // ignore: cast_nullable_to_non_nullable
as String,parentPath: freezed == parentPath ? _self.parentPath : parentPath // ignore: cast_nullable_to_non_nullable
as String?,role: null == role ? _self.role : role // ignore: cast_nullable_to_non_nullable
as String,task: null == task ? _self.task : task // ignore: cast_nullable_to_non_nullable
as String,depth: null == depth ? _self.depth : depth // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadAgentLifecycleView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAgentLifecycleView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadAgentLifecycleViewCopyWith<$Res>  {
$ThreadAgentLifecycleViewCopyWith(ThreadAgentLifecycleView _, $Res Function(ThreadAgentLifecycleView) __);
}


/// Adds pattern-matching-related methods to [ThreadAgentLifecycleView].
extension ThreadAgentLifecycleViewPatterns on ThreadAgentLifecycleView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( QueuedThreadAgentView value)?  queued,TResult Function( RunningThreadAgentView value)?  running,TResult Function( SucceededThreadAgentView value)?  succeeded,TResult Function( DeniedThreadAgentView value)?  denied,TResult Function( CancelledThreadAgentView value)?  cancelled,TResult Function( FailedThreadAgentView value)?  failed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case QueuedThreadAgentView() when queued != null:
return queued(_that);case RunningThreadAgentView() when running != null:
return running(_that);case SucceededThreadAgentView() when succeeded != null:
return succeeded(_that);case DeniedThreadAgentView() when denied != null:
return denied(_that);case CancelledThreadAgentView() when cancelled != null:
return cancelled(_that);case FailedThreadAgentView() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( QueuedThreadAgentView value)  queued,required TResult Function( RunningThreadAgentView value)  running,required TResult Function( SucceededThreadAgentView value)  succeeded,required TResult Function( DeniedThreadAgentView value)  denied,required TResult Function( CancelledThreadAgentView value)  cancelled,required TResult Function( FailedThreadAgentView value)  failed,}){
final _that = this;
switch (_that) {
case QueuedThreadAgentView():
return queued(_that);case RunningThreadAgentView():
return running(_that);case SucceededThreadAgentView():
return succeeded(_that);case DeniedThreadAgentView():
return denied(_that);case CancelledThreadAgentView():
return cancelled(_that);case FailedThreadAgentView():
return failed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( QueuedThreadAgentView value)?  queued,TResult? Function( RunningThreadAgentView value)?  running,TResult? Function( SucceededThreadAgentView value)?  succeeded,TResult? Function( DeniedThreadAgentView value)?  denied,TResult? Function( CancelledThreadAgentView value)?  cancelled,TResult? Function( FailedThreadAgentView value)?  failed,}){
final _that = this;
switch (_that) {
case QueuedThreadAgentView() when queued != null:
return queued(_that);case RunningThreadAgentView() when running != null:
return running(_that);case SucceededThreadAgentView() when succeeded != null:
return succeeded(_that);case DeniedThreadAgentView() when denied != null:
return denied(_that);case CancelledThreadAgentView() when cancelled != null:
return cancelled(_that);case FailedThreadAgentView() when failed != null:
return failed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  queued,TResult Function()?  running,TResult Function( int completedAt,  String summary)?  succeeded,TResult Function( int deniedAt,  String reason)?  denied,TResult Function( int cancelledAt,  String reason)?  cancelled,TResult Function( int failedAt,  String error)?  failed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case QueuedThreadAgentView() when queued != null:
return queued();case RunningThreadAgentView() when running != null:
return running();case SucceededThreadAgentView() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case DeniedThreadAgentView() when denied != null:
return denied(_that.deniedAt,_that.reason);case CancelledThreadAgentView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case FailedThreadAgentView() when failed != null:
return failed(_that.failedAt,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  queued,required TResult Function()  running,required TResult Function( int completedAt,  String summary)  succeeded,required TResult Function( int deniedAt,  String reason)  denied,required TResult Function( int cancelledAt,  String reason)  cancelled,required TResult Function( int failedAt,  String error)  failed,}) {final _that = this;
switch (_that) {
case QueuedThreadAgentView():
return queued();case RunningThreadAgentView():
return running();case SucceededThreadAgentView():
return succeeded(_that.completedAt,_that.summary);case DeniedThreadAgentView():
return denied(_that.deniedAt,_that.reason);case CancelledThreadAgentView():
return cancelled(_that.cancelledAt,_that.reason);case FailedThreadAgentView():
return failed(_that.failedAt,_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  queued,TResult? Function()?  running,TResult? Function( int completedAt,  String summary)?  succeeded,TResult? Function( int deniedAt,  String reason)?  denied,TResult? Function( int cancelledAt,  String reason)?  cancelled,TResult? Function( int failedAt,  String error)?  failed,}) {final _that = this;
switch (_that) {
case QueuedThreadAgentView() when queued != null:
return queued();case RunningThreadAgentView() when running != null:
return running();case SucceededThreadAgentView() when succeeded != null:
return succeeded(_that.completedAt,_that.summary);case DeniedThreadAgentView() when denied != null:
return denied(_that.deniedAt,_that.reason);case CancelledThreadAgentView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case FailedThreadAgentView() when failed != null:
return failed(_that.failedAt,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class QueuedThreadAgentView implements ThreadAgentLifecycleView {
  const QueuedThreadAgentView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is QueuedThreadAgentView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class RunningThreadAgentView implements ThreadAgentLifecycleView {
  const RunningThreadAgentView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningThreadAgentView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class SucceededThreadAgentView implements ThreadAgentLifecycleView {
  const SucceededThreadAgentView(this.completedAt, this.summary);


 final  int completedAt;
 final  String summary;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SucceededThreadAgentViewCopyWith<SucceededThreadAgentView> get copyWith => _$SucceededThreadAgentViewCopyWithImpl<SucceededThreadAgentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SucceededThreadAgentView&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.summary, summary) || other.summary == summary));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,summary);
}



}

/// @nodoc
abstract mixin class $SucceededThreadAgentViewCopyWith<$Res> implements $ThreadAgentLifecycleViewCopyWith<$Res> {
  factory $SucceededThreadAgentViewCopyWith(SucceededThreadAgentView value, $Res Function(SucceededThreadAgentView) _then) = _$SucceededThreadAgentViewCopyWithImpl;
@useResult
$Res call({
 int completedAt, String summary
});




}
/// @nodoc
class _$SucceededThreadAgentViewCopyWithImpl<$Res>
    implements $SucceededThreadAgentViewCopyWith<$Res> {
  _$SucceededThreadAgentViewCopyWithImpl(this._self, this._then);

  final SucceededThreadAgentView _self;
  final $Res Function(SucceededThreadAgentView) _then;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? summary = null,}) {
  return _then(SucceededThreadAgentView(
null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,null == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DeniedThreadAgentView implements ThreadAgentLifecycleView {
  const DeniedThreadAgentView(this.deniedAt, this.reason);


 final  int deniedAt;
 final  String reason;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeniedThreadAgentViewCopyWith<DeniedThreadAgentView> get copyWith => _$DeniedThreadAgentViewCopyWithImpl<DeniedThreadAgentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeniedThreadAgentView&&(identical(other.deniedAt, deniedAt) || other.deniedAt == deniedAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deniedAt,reason);
}



}

/// @nodoc
abstract mixin class $DeniedThreadAgentViewCopyWith<$Res> implements $ThreadAgentLifecycleViewCopyWith<$Res> {
  factory $DeniedThreadAgentViewCopyWith(DeniedThreadAgentView value, $Res Function(DeniedThreadAgentView) _then) = _$DeniedThreadAgentViewCopyWithImpl;
@useResult
$Res call({
 int deniedAt, String reason
});




}
/// @nodoc
class _$DeniedThreadAgentViewCopyWithImpl<$Res>
    implements $DeniedThreadAgentViewCopyWith<$Res> {
  _$DeniedThreadAgentViewCopyWithImpl(this._self, this._then);

  final DeniedThreadAgentView _self;
  final $Res Function(DeniedThreadAgentView) _then;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deniedAt = null,Object? reason = null,}) {
  return _then(DeniedThreadAgentView(
null == deniedAt ? _self.deniedAt : deniedAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancelledThreadAgentView implements ThreadAgentLifecycleView {
  const CancelledThreadAgentView(this.cancelledAt, this.reason);


 final  int cancelledAt;
 final  String reason;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledThreadAgentViewCopyWith<CancelledThreadAgentView> get copyWith => _$CancelledThreadAgentViewCopyWithImpl<CancelledThreadAgentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledThreadAgentView&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledThreadAgentViewCopyWith<$Res> implements $ThreadAgentLifecycleViewCopyWith<$Res> {
  factory $CancelledThreadAgentViewCopyWith(CancelledThreadAgentView value, $Res Function(CancelledThreadAgentView) _then) = _$CancelledThreadAgentViewCopyWithImpl;
@useResult
$Res call({
 int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledThreadAgentViewCopyWithImpl<$Res>
    implements $CancelledThreadAgentViewCopyWith<$Res> {
  _$CancelledThreadAgentViewCopyWithImpl(this._self, this._then);

  final CancelledThreadAgentView _self;
  final $Res Function(CancelledThreadAgentView) _then;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledThreadAgentView(
null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class FailedThreadAgentView implements ThreadAgentLifecycleView {
  const FailedThreadAgentView(this.failedAt, this.error);


 final  int failedAt;
 final  String error;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedThreadAgentViewCopyWith<FailedThreadAgentView> get copyWith => _$FailedThreadAgentViewCopyWithImpl<FailedThreadAgentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedThreadAgentView&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}



}

/// @nodoc
abstract mixin class $FailedThreadAgentViewCopyWith<$Res> implements $ThreadAgentLifecycleViewCopyWith<$Res> {
  factory $FailedThreadAgentViewCopyWith(FailedThreadAgentView value, $Res Function(FailedThreadAgentView) _then) = _$FailedThreadAgentViewCopyWithImpl;
@useResult
$Res call({
 int failedAt, String error
});




}
/// @nodoc
class _$FailedThreadAgentViewCopyWithImpl<$Res>
    implements $FailedThreadAgentViewCopyWith<$Res> {
  _$FailedThreadAgentViewCopyWithImpl(this._self, this._then);

  final FailedThreadAgentView _self;
  final $Res Function(FailedThreadAgentView) _then;

/// Create a copy of ThreadAgentLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(FailedThreadAgentView(
null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadInferenceUsageView {

 int get promptTokens; int get completionTokens; int get cachedPromptTokens; int get totalTokens;
/// Create a copy of ThreadInferenceUsageView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadInferenceUsageViewCopyWith<ThreadInferenceUsageView> get copyWith => _$ThreadInferenceUsageViewCopyWithImpl<ThreadInferenceUsageView>(this as ThreadInferenceUsageView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadInferenceUsageView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadInferenceUsageView&&(identical(other.promptTokens, _this.promptTokens) || other.promptTokens == _this.promptTokens)&&(identical(other.completionTokens, _this.completionTokens) || other.completionTokens == _this.completionTokens)&&(identical(other.cachedPromptTokens, _this.cachedPromptTokens) || other.cachedPromptTokens == _this.cachedPromptTokens)&&(identical(other.totalTokens, _this.totalTokens) || other.totalTokens == _this.totalTokens));
}


@override
int get hashCode {
  final _this = this as ThreadInferenceUsageView;
  return Object.hash(runtimeType,_this.promptTokens,_this.completionTokens,_this.cachedPromptTokens,_this.totalTokens);
}



}

/// @nodoc
abstract mixin class $ThreadInferenceUsageViewCopyWith<$Res>  {
  factory $ThreadInferenceUsageViewCopyWith(ThreadInferenceUsageView value, $Res Function(ThreadInferenceUsageView) _then) = _$ThreadInferenceUsageViewCopyWithImpl;
@useResult
$Res call({
 int promptTokens, int completionTokens, int cachedPromptTokens, int totalTokens
});




}
/// @nodoc
class _$ThreadInferenceUsageViewCopyWithImpl<$Res>
    implements $ThreadInferenceUsageViewCopyWith<$Res> {
  _$ThreadInferenceUsageViewCopyWithImpl(this._self, this._then);

  final ThreadInferenceUsageView _self;
  final $Res Function(ThreadInferenceUsageView) _then;

/// Create a copy of ThreadInferenceUsageView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? promptTokens = null,Object? completionTokens = null,Object? cachedPromptTokens = null,Object? totalTokens = null,}) {
  return _then(ThreadInferenceUsageView(
promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadInferenceUsageView].
extension ThreadInferenceUsageViewPatterns on ThreadInferenceUsageView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadInferenceUsageView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadInferenceUsageView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadInferenceUsageView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadInferenceUsageView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadInferenceUsageView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadInferenceUsageView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int promptTokens,  int completionTokens,  int cachedPromptTokens,  int totalTokens)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadInferenceUsageView() when $default != null:
return $default(_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.totalTokens);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int promptTokens,  int completionTokens,  int cachedPromptTokens,  int totalTokens)  $default,) {final _that = this;
switch (_that) {
case _ThreadInferenceUsageView():
return $default(_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.totalTokens);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int promptTokens,  int completionTokens,  int cachedPromptTokens,  int totalTokens)?  $default,) {final _that = this;
switch (_that) {
case _ThreadInferenceUsageView() when $default != null:
return $default(_that.promptTokens,_that.completionTokens,_that.cachedPromptTokens,_that.totalTokens);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadInferenceUsageView implements ThreadInferenceUsageView {
  const _ThreadInferenceUsageView({required this.promptTokens, required this.completionTokens, required this.cachedPromptTokens, required this.totalTokens});


@override final  int promptTokens;
@override final  int completionTokens;
@override final  int cachedPromptTokens;
@override final  int totalTokens;

/// Create a copy of ThreadInferenceUsageView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadInferenceUsageViewCopyWith<_ThreadInferenceUsageView> get copyWith => __$ThreadInferenceUsageViewCopyWithImpl<_ThreadInferenceUsageView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadInferenceUsageView&&(identical(other.promptTokens, promptTokens) || other.promptTokens == promptTokens)&&(identical(other.completionTokens, completionTokens) || other.completionTokens == completionTokens)&&(identical(other.cachedPromptTokens, cachedPromptTokens) || other.cachedPromptTokens == cachedPromptTokens)&&(identical(other.totalTokens, totalTokens) || other.totalTokens == totalTokens));
}


@override
int get hashCode {
    return Object.hash(runtimeType,promptTokens,completionTokens,cachedPromptTokens,totalTokens);
}



}

/// @nodoc
abstract mixin class _$ThreadInferenceUsageViewCopyWith<$Res> implements $ThreadInferenceUsageViewCopyWith<$Res> {
  factory _$ThreadInferenceUsageViewCopyWith(_ThreadInferenceUsageView value, $Res Function(_ThreadInferenceUsageView) _then) = __$ThreadInferenceUsageViewCopyWithImpl;
@override @useResult
$Res call({
 int promptTokens, int completionTokens, int cachedPromptTokens, int totalTokens
});




}
/// @nodoc
class __$ThreadInferenceUsageViewCopyWithImpl<$Res>
    implements _$ThreadInferenceUsageViewCopyWith<$Res> {
  __$ThreadInferenceUsageViewCopyWithImpl(this._self, this._then);

  final _ThreadInferenceUsageView _self;
  final $Res Function(_ThreadInferenceUsageView) _then;

/// Create a copy of ThreadInferenceUsageView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? promptTokens = null,Object? completionTokens = null,Object? cachedPromptTokens = null,Object? totalTokens = null,}) {
  return _then(_ThreadInferenceUsageView(
promptTokens: null == promptTokens ? _self.promptTokens : promptTokens // ignore: cast_nullable_to_non_nullable
as int,completionTokens: null == completionTokens ? _self.completionTokens : completionTokens // ignore: cast_nullable_to_non_nullable
as int,cachedPromptTokens: null == cachedPromptTokens ? _self.cachedPromptTokens : cachedPromptTokens // ignore: cast_nullable_to_non_nullable
as int,totalTokens: null == totalTokens ? _self.totalTokens : totalTokens // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadInferenceLifecycleView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadInferenceLifecycleView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadInferenceLifecycleViewCopyWith<$Res>  {
$ThreadInferenceLifecycleViewCopyWith(ThreadInferenceLifecycleView _, $Res Function(ThreadInferenceLifecycleView) __);
}


/// Adds pattern-matching-related methods to [ThreadInferenceLifecycleView].
extension ThreadInferenceLifecycleViewPatterns on ThreadInferenceLifecycleView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RunningThreadInferenceView value)?  running,TResult Function( CompletedThreadInferenceView value)?  completed,TResult Function( FailedThreadInferenceView value)?  failed,TResult Function( CancelledThreadInferenceView value)?  cancelled,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RunningThreadInferenceView() when running != null:
return running(_that);case CompletedThreadInferenceView() when completed != null:
return completed(_that);case FailedThreadInferenceView() when failed != null:
return failed(_that);case CancelledThreadInferenceView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RunningThreadInferenceView value)  running,required TResult Function( CompletedThreadInferenceView value)  completed,required TResult Function( FailedThreadInferenceView value)  failed,required TResult Function( CancelledThreadInferenceView value)  cancelled,}){
final _that = this;
switch (_that) {
case RunningThreadInferenceView():
return running(_that);case CompletedThreadInferenceView():
return completed(_that);case FailedThreadInferenceView():
return failed(_that);case CancelledThreadInferenceView():
return cancelled(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RunningThreadInferenceView value)?  running,TResult? Function( CompletedThreadInferenceView value)?  completed,TResult? Function( FailedThreadInferenceView value)?  failed,TResult? Function( CancelledThreadInferenceView value)?  cancelled,}){
final _that = this;
switch (_that) {
case RunningThreadInferenceView() when running != null:
return running(_that);case CompletedThreadInferenceView() when completed != null:
return completed(_that);case FailedThreadInferenceView() when failed != null:
return failed(_that);case CancelledThreadInferenceView() when cancelled != null:
return cancelled(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  running,TResult Function( int completedAt,  ThreadInferenceUsageView usage)?  completed,TResult Function( int failedAt,  String error)?  failed,TResult Function( int cancelledAt,  String reason)?  cancelled,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RunningThreadInferenceView() when running != null:
return running();case CompletedThreadInferenceView() when completed != null:
return completed(_that.completedAt,_that.usage);case FailedThreadInferenceView() when failed != null:
return failed(_that.failedAt,_that.error);case CancelledThreadInferenceView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  running,required TResult Function( int completedAt,  ThreadInferenceUsageView usage)  completed,required TResult Function( int failedAt,  String error)  failed,required TResult Function( int cancelledAt,  String reason)  cancelled,}) {final _that = this;
switch (_that) {
case RunningThreadInferenceView():
return running();case CompletedThreadInferenceView():
return completed(_that.completedAt,_that.usage);case FailedThreadInferenceView():
return failed(_that.failedAt,_that.error);case CancelledThreadInferenceView():
return cancelled(_that.cancelledAt,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  running,TResult? Function( int completedAt,  ThreadInferenceUsageView usage)?  completed,TResult? Function( int failedAt,  String error)?  failed,TResult? Function( int cancelledAt,  String reason)?  cancelled,}) {final _that = this;
switch (_that) {
case RunningThreadInferenceView() when running != null:
return running();case CompletedThreadInferenceView() when completed != null:
return completed(_that.completedAt,_that.usage);case FailedThreadInferenceView() when failed != null:
return failed(_that.failedAt,_that.error);case CancelledThreadInferenceView() when cancelled != null:
return cancelled(_that.cancelledAt,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RunningThreadInferenceView implements ThreadInferenceLifecycleView {
  const RunningThreadInferenceView();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RunningThreadInferenceView);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class CompletedThreadInferenceView implements ThreadInferenceLifecycleView {
  const CompletedThreadInferenceView(this.completedAt, this.usage);


 final  int completedAt;
 final  ThreadInferenceUsageView usage;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CompletedThreadInferenceViewCopyWith<CompletedThreadInferenceView> get copyWith => _$CompletedThreadInferenceViewCopyWithImpl<CompletedThreadInferenceView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CompletedThreadInferenceView&&(identical(other.completedAt, completedAt) || other.completedAt == completedAt)&&(identical(other.usage, usage) || other.usage == usage));
}


@override
int get hashCode {
    return Object.hash(runtimeType,completedAt,usage);
}



}

/// @nodoc
abstract mixin class $CompletedThreadInferenceViewCopyWith<$Res> implements $ThreadInferenceLifecycleViewCopyWith<$Res> {
  factory $CompletedThreadInferenceViewCopyWith(CompletedThreadInferenceView value, $Res Function(CompletedThreadInferenceView) _then) = _$CompletedThreadInferenceViewCopyWithImpl;
@useResult
$Res call({
 int completedAt, ThreadInferenceUsageView usage
});


$ThreadInferenceUsageViewCopyWith<$Res> get usage;

}
/// @nodoc
class _$CompletedThreadInferenceViewCopyWithImpl<$Res>
    implements $CompletedThreadInferenceViewCopyWith<$Res> {
  _$CompletedThreadInferenceViewCopyWithImpl(this._self, this._then);

  final CompletedThreadInferenceView _self;
  final $Res Function(CompletedThreadInferenceView) _then;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? completedAt = null,Object? usage = null,}) {
  return _then(CompletedThreadInferenceView(
null == completedAt ? _self.completedAt : completedAt // ignore: cast_nullable_to_non_nullable
as int,null == usage ? _self.usage : usage // ignore: cast_nullable_to_non_nullable
as ThreadInferenceUsageView,
  ));
}

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadInferenceUsageViewCopyWith<$Res> get usage {

  return $ThreadInferenceUsageViewCopyWith<$Res>(_self.usage, (value) {
    return _then(_self.copyWith(usage: value));
  });
}
}

/// @nodoc


class FailedThreadInferenceView implements ThreadInferenceLifecycleView {
  const FailedThreadInferenceView(this.failedAt, this.error);


 final  int failedAt;
 final  String error;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedThreadInferenceViewCopyWith<FailedThreadInferenceView> get copyWith => _$FailedThreadInferenceViewCopyWithImpl<FailedThreadInferenceView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedThreadInferenceView&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,failedAt,error);
}



}

/// @nodoc
abstract mixin class $FailedThreadInferenceViewCopyWith<$Res> implements $ThreadInferenceLifecycleViewCopyWith<$Res> {
  factory $FailedThreadInferenceViewCopyWith(FailedThreadInferenceView value, $Res Function(FailedThreadInferenceView) _then) = _$FailedThreadInferenceViewCopyWithImpl;
@useResult
$Res call({
 int failedAt, String error
});




}
/// @nodoc
class _$FailedThreadInferenceViewCopyWithImpl<$Res>
    implements $FailedThreadInferenceViewCopyWith<$Res> {
  _$FailedThreadInferenceViewCopyWithImpl(this._self, this._then);

  final FailedThreadInferenceView _self;
  final $Res Function(FailedThreadInferenceView) _then;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? failedAt = null,Object? error = null,}) {
  return _then(FailedThreadInferenceView(
null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class CancelledThreadInferenceView implements ThreadInferenceLifecycleView {
  const CancelledThreadInferenceView(this.cancelledAt, this.reason);


 final  int cancelledAt;
 final  String reason;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$CancelledThreadInferenceViewCopyWith<CancelledThreadInferenceView> get copyWith => _$CancelledThreadInferenceViewCopyWithImpl<CancelledThreadInferenceView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is CancelledThreadInferenceView&&(identical(other.cancelledAt, cancelledAt) || other.cancelledAt == cancelledAt)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,cancelledAt,reason);
}



}

/// @nodoc
abstract mixin class $CancelledThreadInferenceViewCopyWith<$Res> implements $ThreadInferenceLifecycleViewCopyWith<$Res> {
  factory $CancelledThreadInferenceViewCopyWith(CancelledThreadInferenceView value, $Res Function(CancelledThreadInferenceView) _then) = _$CancelledThreadInferenceViewCopyWithImpl;
@useResult
$Res call({
 int cancelledAt, String reason
});




}
/// @nodoc
class _$CancelledThreadInferenceViewCopyWithImpl<$Res>
    implements $CancelledThreadInferenceViewCopyWith<$Res> {
  _$CancelledThreadInferenceViewCopyWithImpl(this._self, this._then);

  final CancelledThreadInferenceView _self;
  final $Res Function(CancelledThreadInferenceView) _then;

/// Create a copy of ThreadInferenceLifecycleView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? cancelledAt = null,Object? reason = null,}) {
  return _then(CancelledThreadInferenceView(
null == cancelledAt ? _self.cancelledAt : cancelledAt // ignore: cast_nullable_to_non_nullable
as int,null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$RawHistoryPayload {

 String get format; int get version; String get content;
/// Create a copy of RawHistoryPayload
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RawHistoryPayloadCopyWith<RawHistoryPayload> get copyWith => _$RawHistoryPayloadCopyWithImpl<RawHistoryPayload>(this as RawHistoryPayload, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RawHistoryPayload;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RawHistoryPayload&&(identical(other.format, _this.format) || other.format == _this.format)&&(identical(other.version, _this.version) || other.version == _this.version)&&(identical(other.content, _this.content) || other.content == _this.content));
}


@override
int get hashCode {
  final _this = this as RawHistoryPayload;
  return Object.hash(runtimeType,_this.format,_this.version,_this.content);
}



}

/// @nodoc
abstract mixin class $RawHistoryPayloadCopyWith<$Res>  {
  factory $RawHistoryPayloadCopyWith(RawHistoryPayload value, $Res Function(RawHistoryPayload) _then) = _$RawHistoryPayloadCopyWithImpl;
@useResult
$Res call({
 String format, int version, String content
});




}
/// @nodoc
class _$RawHistoryPayloadCopyWithImpl<$Res>
    implements $RawHistoryPayloadCopyWith<$Res> {
  _$RawHistoryPayloadCopyWithImpl(this._self, this._then);

  final RawHistoryPayload _self;
  final $Res Function(RawHistoryPayload) _then;

/// Create a copy of RawHistoryPayload
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? format = null,Object? version = null,Object? content = null,}) {
  return _then(RawHistoryPayload(
null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String,null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,
  ));
}

}


/// Adds pattern-matching-related methods to [RawHistoryPayload].
extension RawHistoryPayloadPatterns on RawHistoryPayload {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RawHistoryPayload value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RawHistoryPayload() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RawHistoryPayload value)  $default,){
final _that = this;
switch (_that) {
case _RawHistoryPayload():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RawHistoryPayload value)?  $default,){
final _that = this;
switch (_that) {
case _RawHistoryPayload() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String format,  int version,  String content)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RawHistoryPayload() when $default != null:
return $default(_that.format,_that.version,_that.content);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String format,  int version,  String content)  $default,) {final _that = this;
switch (_that) {
case _RawHistoryPayload():
return $default(_that.format,_that.version,_that.content);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String format,  int version,  String content)?  $default,) {final _that = this;
switch (_that) {
case _RawHistoryPayload() when $default != null:
return $default(_that.format,_that.version,_that.content);case _:
  return null;

}
}

}

/// @nodoc


class _RawHistoryPayload implements RawHistoryPayload {
  const _RawHistoryPayload(this.format, this.version, this.content);


@override final  String format;
@override final  int version;
@override final  String content;

/// Create a copy of RawHistoryPayload
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RawHistoryPayloadCopyWith<_RawHistoryPayload> get copyWith => __$RawHistoryPayloadCopyWithImpl<_RawHistoryPayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RawHistoryPayload&&(identical(other.format, format) || other.format == format)&&(identical(other.version, version) || other.version == version)&&(identical(other.content, content) || other.content == content));
}


@override
int get hashCode {
    return Object.hash(runtimeType,format,version,content);
}



}

/// @nodoc
abstract mixin class _$RawHistoryPayloadCopyWith<$Res> implements $RawHistoryPayloadCopyWith<$Res> {
  factory _$RawHistoryPayloadCopyWith(_RawHistoryPayload value, $Res Function(_RawHistoryPayload) _then) = __$RawHistoryPayloadCopyWithImpl;
@override @useResult
$Res call({
 String format, int version, String content
});




}
/// @nodoc
class __$RawHistoryPayloadCopyWithImpl<$Res>
    implements _$RawHistoryPayloadCopyWith<$Res> {
  __$RawHistoryPayloadCopyWithImpl(this._self, this._then);

  final _RawHistoryPayload _self;
  final $Res Function(_RawHistoryPayload) _then;

/// Create a copy of RawHistoryPayload
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? format = null,Object? version = null,Object? content = null,}) {
  return _then(_RawHistoryPayload(
null == format ? _self.format : format // ignore: cast_nullable_to_non_nullable
as String,null == version ? _self.version : version // ignore: cast_nullable_to_non_nullable
as int,null == content ? _self.content : content // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc
mixin _$ThreadWaitPresentationView {

 ThreadWaitIntentView get intent; ThreadWaitState get state; bool? get messagesReady;
/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWaitPresentationViewCopyWith<ThreadWaitPresentationView> get copyWith => _$ThreadWaitPresentationViewCopyWithImpl<ThreadWaitPresentationView>(this as ThreadWaitPresentationView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWaitPresentationView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWaitPresentationView&&(identical(other.intent, _this.intent) || other.intent == _this.intent)&&(identical(other.state, _this.state) || other.state == _this.state)&&(identical(other.messagesReady, _this.messagesReady) || other.messagesReady == _this.messagesReady));
}


@override
int get hashCode {
  final _this = this as ThreadWaitPresentationView;
  return Object.hash(runtimeType,_this.intent,_this.state,_this.messagesReady);
}



}

/// @nodoc
abstract mixin class $ThreadWaitPresentationViewCopyWith<$Res>  {
  factory $ThreadWaitPresentationViewCopyWith(ThreadWaitPresentationView value, $Res Function(ThreadWaitPresentationView) _then) = _$ThreadWaitPresentationViewCopyWithImpl;
@useResult
$Res call({
 ThreadWaitIntentView intent, ThreadWaitState state, bool? messagesReady
});


$ThreadWaitIntentViewCopyWith<$Res> get intent;

}
/// @nodoc
class _$ThreadWaitPresentationViewCopyWithImpl<$Res>
    implements $ThreadWaitPresentationViewCopyWith<$Res> {
  _$ThreadWaitPresentationViewCopyWithImpl(this._self, this._then);

  final ThreadWaitPresentationView _self;
  final $Res Function(ThreadWaitPresentationView) _then;

/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? intent = null,Object? state = null,Object? messagesReady = freezed,}) {
  return _then(ThreadWaitPresentationView(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as ThreadWaitIntentView,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadWaitState,messagesReady: freezed == messagesReady ? _self.messagesReady : messagesReady // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}
/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWaitIntentViewCopyWith<$Res> get intent {

  return $ThreadWaitIntentViewCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadWaitPresentationView].
extension ThreadWaitPresentationViewPatterns on ThreadWaitPresentationView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadWaitPresentationView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadWaitPresentationView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadWaitPresentationView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadWaitPresentationView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadWaitPresentationView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadWaitPresentationView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadWaitIntentView intent,  ThreadWaitState state,  bool? messagesReady)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadWaitPresentationView() when $default != null:
return $default(_that.intent,_that.state,_that.messagesReady);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadWaitIntentView intent,  ThreadWaitState state,  bool? messagesReady)  $default,) {final _that = this;
switch (_that) {
case _ThreadWaitPresentationView():
return $default(_that.intent,_that.state,_that.messagesReady);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadWaitIntentView intent,  ThreadWaitState state,  bool? messagesReady)?  $default,) {final _that = this;
switch (_that) {
case _ThreadWaitPresentationView() when $default != null:
return $default(_that.intent,_that.state,_that.messagesReady);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadWaitPresentationView implements ThreadWaitPresentationView {
  const _ThreadWaitPresentationView({required this.intent, required this.state, this.messagesReady});


@override final  ThreadWaitIntentView intent;
@override final  ThreadWaitState state;
@override final  bool? messagesReady;

/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadWaitPresentationViewCopyWith<_ThreadWaitPresentationView> get copyWith => __$ThreadWaitPresentationViewCopyWithImpl<_ThreadWaitPresentationView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadWaitPresentationView&&(identical(other.intent, intent) || other.intent == intent)&&(identical(other.state, state) || other.state == state)&&(identical(other.messagesReady, messagesReady) || other.messagesReady == messagesReady));
}


@override
int get hashCode {
    return Object.hash(runtimeType,intent,state,messagesReady);
}



}

/// @nodoc
abstract mixin class _$ThreadWaitPresentationViewCopyWith<$Res> implements $ThreadWaitPresentationViewCopyWith<$Res> {
  factory _$ThreadWaitPresentationViewCopyWith(_ThreadWaitPresentationView value, $Res Function(_ThreadWaitPresentationView) _then) = __$ThreadWaitPresentationViewCopyWithImpl;
@override @useResult
$Res call({
 ThreadWaitIntentView intent, ThreadWaitState state, bool? messagesReady
});


@override $ThreadWaitIntentViewCopyWith<$Res> get intent;

}
/// @nodoc
class __$ThreadWaitPresentationViewCopyWithImpl<$Res>
    implements _$ThreadWaitPresentationViewCopyWith<$Res> {
  __$ThreadWaitPresentationViewCopyWithImpl(this._self, this._then);

  final _ThreadWaitPresentationView _self;
  final $Res Function(_ThreadWaitPresentationView) _then;

/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? intent = null,Object? state = null,Object? messagesReady = freezed,}) {
  return _then(_ThreadWaitPresentationView(
intent: null == intent ? _self.intent : intent // ignore: cast_nullable_to_non_nullable
as ThreadWaitIntentView,state: null == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as ThreadWaitState,messagesReady: freezed == messagesReady ? _self.messagesReady : messagesReady // ignore: cast_nullable_to_non_nullable
as bool?,
  ));
}

/// Create a copy of ThreadWaitPresentationView
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWaitIntentViewCopyWith<$Res> get intent {

  return $ThreadWaitIntentViewCopyWith<$Res>(_self.intent, (value) {
    return _then(_self.copyWith(intent: value));
  });
}
}

/// @nodoc
mixin _$ThreadWaitIntentView {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWaitIntentView);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadWaitIntentViewCopyWith<$Res>  {
$ThreadWaitIntentViewCopyWith(ThreadWaitIntentView _, $Res Function(ThreadWaitIntentView) __);
}


/// Adds pattern-matching-related methods to [ThreadWaitIntentView].
extension ThreadWaitIntentViewPatterns on ThreadWaitIntentView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadWaitEventsIntentView value)?  events,TResult Function( ThreadWaitTimerIntentView value)?  timer,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView() when events != null:
return events(_that);case ThreadWaitTimerIntentView() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadWaitEventsIntentView value)  events,required TResult Function( ThreadWaitTimerIntentView value)  timer,}){
final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView():
return events(_that);case ThreadWaitTimerIntentView():
return timer(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadWaitEventsIntentView value)?  events,TResult? Function( ThreadWaitTimerIntentView value)?  timer,}){
final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView() when events != null:
return events(_that);case ThreadWaitTimerIntentView() when timer != null:
return timer(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( List<ThreadWaitTargetView> targets,  int timeoutMs)?  events,TResult Function( int durationMs)?  timer,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView() when events != null:
return events(_that.targets,_that.timeoutMs);case ThreadWaitTimerIntentView() when timer != null:
return timer(_that.durationMs);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( List<ThreadWaitTargetView> targets,  int timeoutMs)  events,required TResult Function( int durationMs)  timer,}) {final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView():
return events(_that.targets,_that.timeoutMs);case ThreadWaitTimerIntentView():
return timer(_that.durationMs);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( List<ThreadWaitTargetView> targets,  int timeoutMs)?  events,TResult? Function( int durationMs)?  timer,}) {final _that = this;
switch (_that) {
case ThreadWaitEventsIntentView() when events != null:
return events(_that.targets,_that.timeoutMs);case ThreadWaitTimerIntentView() when timer != null:
return timer(_that.durationMs);case _:
  return null;

}
}

}


/// @nodoc


class ThreadWaitTimerIntentView extends ThreadWaitIntentView {
  const ThreadWaitTimerIntentView({required this.durationMs}): super._();


 final  int durationMs;

/// Create a copy of ThreadWaitIntentView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWaitTimerIntentViewCopyWith<ThreadWaitTimerIntentView> get copyWith => _$ThreadWaitTimerIntentViewCopyWithImpl<ThreadWaitTimerIntentView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWaitTimerIntentView&&(identical(other.durationMs, durationMs) || other.durationMs == durationMs));
}


@override
int get hashCode {
    return Object.hash(runtimeType,durationMs);
}



}

/// @nodoc
abstract mixin class $ThreadWaitTimerIntentViewCopyWith<$Res> implements $ThreadWaitIntentViewCopyWith<$Res> {
  factory $ThreadWaitTimerIntentViewCopyWith(ThreadWaitTimerIntentView value, $Res Function(ThreadWaitTimerIntentView) _then) = _$ThreadWaitTimerIntentViewCopyWithImpl;
@useResult
$Res call({
 int durationMs
});




}
/// @nodoc
class _$ThreadWaitTimerIntentViewCopyWithImpl<$Res>
    implements $ThreadWaitTimerIntentViewCopyWith<$Res> {
  _$ThreadWaitTimerIntentViewCopyWithImpl(this._self, this._then);

  final ThreadWaitTimerIntentView _self;
  final $Res Function(ThreadWaitTimerIntentView) _then;

/// Create a copy of ThreadWaitIntentView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? durationMs = null,}) {
  return _then(ThreadWaitTimerIntentView(
durationMs: null == durationMs ? _self.durationMs : durationMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ThreadWaitEventsIntentView {


/// Create a copy of ThreadWaitEventsIntentView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWaitEventsIntentViewCopyWith<ThreadWaitEventsIntentView> get copyWith => _$ThreadWaitEventsIntentViewCopyWithImpl<ThreadWaitEventsIntentView>(this as ThreadWaitEventsIntentView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWaitEventsIntentView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWaitEventsIntentView&&const DeepCollectionEquality().equals(other.targets, _this.targets)&&(identical(other.timeoutMs, _this.timeoutMs) || other.timeoutMs == _this.timeoutMs));
}


@override
int get hashCode {
  final _this = this as ThreadWaitEventsIntentView;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.targets),_this.timeoutMs);
}



}

/// @nodoc
abstract mixin class $ThreadWaitEventsIntentViewCopyWith<$Res> implements $ThreadWaitIntentViewCopyWith<$Res> {
  factory $ThreadWaitEventsIntentViewCopyWith(ThreadWaitEventsIntentView value, $Res Function(ThreadWaitEventsIntentView) _then) = _$ThreadWaitEventsIntentViewCopyWithImpl;
@useResult
$Res call({
 List<ThreadWaitTargetView> targets, int timeoutMs
});




}
/// @nodoc
class _$ThreadWaitEventsIntentViewCopyWithImpl<$Res>
    implements $ThreadWaitEventsIntentViewCopyWith<$Res> {
  _$ThreadWaitEventsIntentViewCopyWithImpl(this._self, this._then);

  final ThreadWaitEventsIntentView _self;
  final $Res Function(ThreadWaitEventsIntentView) _then;

/// Create a copy of ThreadWaitEventsIntentView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? targets = null,Object? timeoutMs = null,}) {
  return _then(ThreadWaitEventsIntentView(
targets: null == targets ? _self.targets : targets // ignore: cast_nullable_to_non_nullable
as List<ThreadWaitTargetView>,timeoutMs: null == timeoutMs ? _self.timeoutMs : timeoutMs // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadWaitEventsIntentView].
extension ThreadWaitEventsIntentViewPatterns on ThreadWaitEventsIntentView {
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
mixin _$ThreadWaitTargetView {

 String get taskId; String? get toolName; String? get summary; bool get summaryTruncated; ThreadWaitTargetStatus? get status;
/// Create a copy of ThreadWaitTargetView
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadWaitTargetViewCopyWith<ThreadWaitTargetView> get copyWith => _$ThreadWaitTargetViewCopyWithImpl<ThreadWaitTargetView>(this as ThreadWaitTargetView, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadWaitTargetView;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadWaitTargetView&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.toolName, _this.toolName) || other.toolName == _this.toolName)&&(identical(other.summary, _this.summary) || other.summary == _this.summary)&&(identical(other.summaryTruncated, _this.summaryTruncated) || other.summaryTruncated == _this.summaryTruncated)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as ThreadWaitTargetView;
  return Object.hash(runtimeType,_this.taskId,_this.toolName,_this.summary,_this.summaryTruncated,_this.status);
}



}

/// @nodoc
abstract mixin class $ThreadWaitTargetViewCopyWith<$Res>  {
  factory $ThreadWaitTargetViewCopyWith(ThreadWaitTargetView value, $Res Function(ThreadWaitTargetView) _then) = _$ThreadWaitTargetViewCopyWithImpl;
@useResult
$Res call({
 String taskId, String? toolName, String? summary, bool summaryTruncated, ThreadWaitTargetStatus? status
});




}
/// @nodoc
class _$ThreadWaitTargetViewCopyWithImpl<$Res>
    implements $ThreadWaitTargetViewCopyWith<$Res> {
  _$ThreadWaitTargetViewCopyWithImpl(this._self, this._then);

  final ThreadWaitTargetView _self;
  final $Res Function(ThreadWaitTargetView) _then;

/// Create a copy of ThreadWaitTargetView
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? taskId = null,Object? toolName = freezed,Object? summary = freezed,Object? summaryTruncated = null,Object? status = freezed,}) {
  return _then(ThreadWaitTargetView(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,toolName: freezed == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadWaitTargetStatus?,
  ));
}

}


/// Adds pattern-matching-related methods to [ThreadWaitTargetView].
extension ThreadWaitTargetViewPatterns on ThreadWaitTargetView {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadWaitTargetView value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadWaitTargetView() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadWaitTargetView value)  $default,){
final _that = this;
switch (_that) {
case _ThreadWaitTargetView():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadWaitTargetView value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadWaitTargetView() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String taskId,  String? toolName,  String? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadWaitTargetView() when $default != null:
return $default(_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String taskId,  String? toolName,  String? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)  $default,) {final _that = this;
switch (_that) {
case _ThreadWaitTargetView():
return $default(_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String taskId,  String? toolName,  String? summary,  bool summaryTruncated,  ThreadWaitTargetStatus? status)?  $default,) {final _that = this;
switch (_that) {
case _ThreadWaitTargetView() when $default != null:
return $default(_that.taskId,_that.toolName,_that.summary,_that.summaryTruncated,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadWaitTargetView implements ThreadWaitTargetView {
  const _ThreadWaitTargetView({required this.taskId, this.toolName, this.summary, this.summaryTruncated = false, this.status});


@override final  String taskId;
@override final  String? toolName;
@override final  String? summary;
@override@JsonKey() final  bool summaryTruncated;
@override final  ThreadWaitTargetStatus? status;

/// Create a copy of ThreadWaitTargetView
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadWaitTargetViewCopyWith<_ThreadWaitTargetView> get copyWith => __$ThreadWaitTargetViewCopyWithImpl<_ThreadWaitTargetView>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadWaitTargetView&&(identical(other.taskId, taskId) || other.taskId == taskId)&&(identical(other.toolName, toolName) || other.toolName == toolName)&&(identical(other.summary, summary) || other.summary == summary)&&(identical(other.summaryTruncated, summaryTruncated) || other.summaryTruncated == summaryTruncated)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,taskId,toolName,summary,summaryTruncated,status);
}



}

/// @nodoc
abstract mixin class _$ThreadWaitTargetViewCopyWith<$Res> implements $ThreadWaitTargetViewCopyWith<$Res> {
  factory _$ThreadWaitTargetViewCopyWith(_ThreadWaitTargetView value, $Res Function(_ThreadWaitTargetView) _then) = __$ThreadWaitTargetViewCopyWithImpl;
@override @useResult
$Res call({
 String taskId, String? toolName, String? summary, bool summaryTruncated, ThreadWaitTargetStatus? status
});




}
/// @nodoc
class __$ThreadWaitTargetViewCopyWithImpl<$Res>
    implements _$ThreadWaitTargetViewCopyWith<$Res> {
  __$ThreadWaitTargetViewCopyWithImpl(this._self, this._then);

  final _ThreadWaitTargetView _self;
  final $Res Function(_ThreadWaitTargetView) _then;

/// Create a copy of ThreadWaitTargetView
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? taskId = null,Object? toolName = freezed,Object? summary = freezed,Object? summaryTruncated = null,Object? status = freezed,}) {
  return _then(_ThreadWaitTargetView(
taskId: null == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String,toolName: freezed == toolName ? _self.toolName : toolName // ignore: cast_nullable_to_non_nullable
as String?,summary: freezed == summary ? _self.summary : summary // ignore: cast_nullable_to_non_nullable
as String?,summaryTruncated: null == summaryTruncated ? _self.summaryTruncated : summaryTruncated // ignore: cast_nullable_to_non_nullable
as bool,status: freezed == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ThreadWaitTargetStatus?,
  ));
}


}

/// @nodoc
mixin _$TimelineToolPart {


/// Create a copy of TimelineToolPart
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TimelineToolPartCopyWith<TimelineToolPart> get copyWith => _$TimelineToolPartCopyWithImpl<TimelineToolPart>(this as TimelineToolPart, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TimelineToolPart;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TimelineToolPart&&(identical(other.toolCallId, _this.toolCallId) || other.toolCallId == _this.toolCallId)&&(identical(other.name, _this.name) || other.name == _this.name)&&(identical(other.callId, _this.callId) || other.callId == _this.callId)&&(identical(other.providerItemId, _this.providerItemId) || other.providerItemId == _this.providerItemId)&&(identical(other.arguments, _this.arguments) || other.arguments == _this.arguments)&&(identical(other.result, _this.result) || other.result == _this.result)&&const DeepCollectionEquality().equals(other.attachments, _this.attachments)&&const DeepCollectionEquality().equals(other.outputArtifacts, _this.outputArtifacts)&&(identical(other.exitCode, _this.exitCode) || other.exitCode == _this.exitCode)&&(identical(other.timedOut, _this.timedOut) || other.timedOut == _this.timedOut)&&(identical(other.workingDirectory, _this.workingDirectory) || other.workingDirectory == _this.workingDirectory)&&(identical(other.denialReason, _this.denialReason) || other.denialReason == _this.denialReason)&&(identical(other.taskId, _this.taskId) || other.taskId == _this.taskId)&&(identical(other.userInput, _this.userInput) || other.userInput == _this.userInput)&&(identical(other.wait, _this.wait) || other.wait == _this.wait));
}


@override
int get hashCode {
  final _this = this as TimelineToolPart;
  return Object.hash(runtimeType,_this.toolCallId,_this.name,_this.callId,_this.providerItemId,_this.arguments,_this.result,const DeepCollectionEquality().hash(_this.attachments),const DeepCollectionEquality().hash(_this.outputArtifacts),_this.exitCode,_this.timedOut,_this.workingDirectory,_this.denialReason,_this.taskId,_this.userInput,_this.wait);
}



}

/// @nodoc
abstract mixin class $TimelineToolPartCopyWith<$Res>  {
  factory $TimelineToolPartCopyWith(TimelineToolPart value, $Res Function(TimelineToolPart) _then) = _$TimelineToolPartCopyWithImpl;
@useResult
$Res call({
 String toolCallId, String name, String? callId, String? providerItemId, String arguments, String? result, List<ThreadAttachmentView> attachments, List<OpaqueArtifactJson> outputArtifacts, int? exitCode, bool timedOut, String? workingDirectory, String? denialReason, String? taskId, ThreadToolUserInputView? userInput, ThreadWaitPresentationView? wait
});


$ThreadToolUserInputViewCopyWith<$Res>? get userInput;$ThreadWaitPresentationViewCopyWith<$Res>? get wait;

}
/// @nodoc
class _$TimelineToolPartCopyWithImpl<$Res>
    implements $TimelineToolPartCopyWith<$Res> {
  _$TimelineToolPartCopyWithImpl(this._self, this._then);

  final TimelineToolPart _self;
  final $Res Function(TimelineToolPart) _then;

/// Create a copy of TimelineToolPart
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? toolCallId = null,Object? name = null,Object? callId = freezed,Object? providerItemId = freezed,Object? arguments = null,Object? result = freezed,Object? attachments = null,Object? outputArtifacts = null,Object? exitCode = freezed,Object? timedOut = null,Object? workingDirectory = freezed,Object? denialReason = freezed,Object? taskId = freezed,Object? userInput = freezed,Object? wait = freezed,}) {
  return _then(TimelineToolPart(
toolCallId: null == toolCallId ? _self.toolCallId : toolCallId // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,callId: freezed == callId ? _self.callId : callId // ignore: cast_nullable_to_non_nullable
as String?,providerItemId: freezed == providerItemId ? _self.providerItemId : providerItemId // ignore: cast_nullable_to_non_nullable
as String?,arguments: null == arguments ? _self.arguments : arguments // ignore: cast_nullable_to_non_nullable
as String,result: freezed == result ? _self.result : result // ignore: cast_nullable_to_non_nullable
as String?,attachments: null == attachments ? _self.attachments : attachments // ignore: cast_nullable_to_non_nullable
as List<ThreadAttachmentView>,outputArtifacts: null == outputArtifacts ? _self.outputArtifacts : outputArtifacts // ignore: cast_nullable_to_non_nullable
as List<OpaqueArtifactJson>,exitCode: freezed == exitCode ? _self.exitCode : exitCode // ignore: cast_nullable_to_non_nullable
as int?,timedOut: null == timedOut ? _self.timedOut : timedOut // ignore: cast_nullable_to_non_nullable
as bool,workingDirectory: freezed == workingDirectory ? _self.workingDirectory : workingDirectory // ignore: cast_nullable_to_non_nullable
as String?,denialReason: freezed == denialReason ? _self.denialReason : denialReason // ignore: cast_nullable_to_non_nullable
as String?,taskId: freezed == taskId ? _self.taskId : taskId // ignore: cast_nullable_to_non_nullable
as String?,userInput: freezed == userInput ? _self.userInput : userInput // ignore: cast_nullable_to_non_nullable
as ThreadToolUserInputView?,wait: freezed == wait ? _self.wait : wait // ignore: cast_nullable_to_non_nullable
as ThreadWaitPresentationView?,
  ));
}
/// Create a copy of TimelineToolPart
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadToolUserInputViewCopyWith<$Res>? get userInput {
    if (_self.userInput == null) {
    return null;
  }

  return $ThreadToolUserInputViewCopyWith<$Res>(_self.userInput!, (value) {
    return _then(_self.copyWith(userInput: value));
  });
}/// Create a copy of TimelineToolPart
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadWaitPresentationViewCopyWith<$Res>? get wait {
    if (_self.wait == null) {
    return null;
  }

  return $ThreadWaitPresentationViewCopyWith<$Res>(_self.wait!, (value) {
    return _then(_self.copyWith(wait: value));
  });
}
}


/// Adds pattern-matching-related methods to [TimelineToolPart].
extension TimelineToolPartPatterns on TimelineToolPart {
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
