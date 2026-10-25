// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'read_primitives.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReadText {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadText);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ReadTextCopyWith<$Res>  {
$ReadTextCopyWith(ReadText _, $Res Function(ReadText) __);
}


/// Adds pattern-matching-related methods to [ReadText].
extension ReadTextPatterns on ReadText {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( InlineReadText value)?  inline,TResult Function( DeferredReadText value)?  deferred,required TResult orElse(),}){
final _that = this;
switch (_that) {
case InlineReadText() when inline != null:
return inline(_that);case DeferredReadText() when deferred != null:
return deferred(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( InlineReadText value)  inline,required TResult Function( DeferredReadText value)  deferred,}){
final _that = this;
switch (_that) {
case InlineReadText():
return inline(_that);case DeferredReadText():
return deferred(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( InlineReadText value)?  inline,TResult? Function( DeferredReadText value)?  deferred,}){
final _that = this;
switch (_that) {
case InlineReadText() when inline != null:
return inline(_that);case DeferredReadText() when deferred != null:
return deferred(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String text)?  inline,TResult Function( int fieldId,  int utf8Bytes)?  deferred,required TResult orElse(),}) {final _that = this;
switch (_that) {
case InlineReadText() when inline != null:
return inline(_that.text);case DeferredReadText() when deferred != null:
return deferred(_that.fieldId,_that.utf8Bytes);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String text)  inline,required TResult Function( int fieldId,  int utf8Bytes)  deferred,}) {final _that = this;
switch (_that) {
case InlineReadText():
return inline(_that.text);case DeferredReadText():
return deferred(_that.fieldId,_that.utf8Bytes);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String text)?  inline,TResult? Function( int fieldId,  int utf8Bytes)?  deferred,}) {final _that = this;
switch (_that) {
case InlineReadText() when inline != null:
return inline(_that.text);case DeferredReadText() when deferred != null:
return deferred(_that.fieldId,_that.utf8Bytes);case _:
  return null;

}
}

}

/// @nodoc


class InlineReadText implements ReadText {
  const InlineReadText({required this.text});


 final  String text;

/// Create a copy of ReadText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InlineReadTextCopyWith<InlineReadText> get copyWith => _$InlineReadTextCopyWithImpl<InlineReadText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is InlineReadText&&(identical(other.text, text) || other.text == text));
}


@override
int get hashCode {
    return Object.hash(runtimeType,text);
}



}

/// @nodoc
abstract mixin class $InlineReadTextCopyWith<$Res> implements $ReadTextCopyWith<$Res> {
  factory $InlineReadTextCopyWith(InlineReadText value, $Res Function(InlineReadText) _then) = _$InlineReadTextCopyWithImpl;
@useResult
$Res call({
 String text
});




}
/// @nodoc
class _$InlineReadTextCopyWithImpl<$Res>
    implements $InlineReadTextCopyWith<$Res> {
  _$InlineReadTextCopyWithImpl(this._self, this._then);

  final InlineReadText _self;
  final $Res Function(InlineReadText) _then;

/// Create a copy of ReadText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? text = null,}) {
  return _then(InlineReadText(
text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,
  ));
}


}

/// @nodoc


class DeferredReadText implements ReadText {
  const DeferredReadText({required this.fieldId, required this.utf8Bytes});


 final  int fieldId;
 final  int utf8Bytes;

/// Create a copy of ReadText
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DeferredReadTextCopyWith<DeferredReadText> get copyWith => _$DeferredReadTextCopyWithImpl<DeferredReadText>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DeferredReadText&&(identical(other.fieldId, fieldId) || other.fieldId == fieldId)&&(identical(other.utf8Bytes, utf8Bytes) || other.utf8Bytes == utf8Bytes));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fieldId,utf8Bytes);
}



}

/// @nodoc
abstract mixin class $DeferredReadTextCopyWith<$Res> implements $ReadTextCopyWith<$Res> {
  factory $DeferredReadTextCopyWith(DeferredReadText value, $Res Function(DeferredReadText) _then) = _$DeferredReadTextCopyWithImpl;
@useResult
$Res call({
 int fieldId, int utf8Bytes
});




}
/// @nodoc
class _$DeferredReadTextCopyWithImpl<$Res>
    implements $DeferredReadTextCopyWith<$Res> {
  _$DeferredReadTextCopyWithImpl(this._self, this._then);

  final DeferredReadText _self;
  final $Res Function(DeferredReadText) _then;

/// Create a copy of ReadText
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? fieldId = null,Object? utf8Bytes = null,}) {
  return _then(DeferredReadText(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int,utf8Bytes: null == utf8Bytes ? _self.utf8Bytes : utf8Bytes // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$TextChunk {

 int get fieldId; int get offset; String get text; int? get nextOffset;
/// Create a copy of TextChunk
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextChunkCopyWith<TextChunk> get copyWith => _$TextChunkCopyWithImpl<TextChunk>(this as TextChunk, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TextChunk;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextChunk&&(identical(other.fieldId, _this.fieldId) || other.fieldId == _this.fieldId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.text, _this.text) || other.text == _this.text)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as TextChunk;
  return Object.hash(runtimeType,_this.fieldId,_this.offset,_this.text,_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $TextChunkCopyWith<$Res>  {
  factory $TextChunkCopyWith(TextChunk value, $Res Function(TextChunk) _then) = _$TextChunkCopyWithImpl;
@useResult
$Res call({
 int fieldId, int offset, String text, int? nextOffset
});




}
/// @nodoc
class _$TextChunkCopyWithImpl<$Res>
    implements $TextChunkCopyWith<$Res> {
  _$TextChunkCopyWithImpl(this._self, this._then);

  final TextChunk _self;
  final $Res Function(TextChunk) _then;

/// Create a copy of TextChunk
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? fieldId = null,Object? offset = null,Object? text = null,Object? nextOffset = freezed,}) {
  return _then(TextChunk(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [TextChunk].
extension TextChunkPatterns on TextChunk {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TextChunk value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TextChunk() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TextChunk value)  $default,){
final _that = this;
switch (_that) {
case _TextChunk():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TextChunk value)?  $default,){
final _that = this;
switch (_that) {
case _TextChunk() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int fieldId,  int offset,  String text,  int? nextOffset)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TextChunk() when $default != null:
return $default(_that.fieldId,_that.offset,_that.text,_that.nextOffset);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int fieldId,  int offset,  String text,  int? nextOffset)  $default,) {final _that = this;
switch (_that) {
case _TextChunk():
return $default(_that.fieldId,_that.offset,_that.text,_that.nextOffset);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int fieldId,  int offset,  String text,  int? nextOffset)?  $default,) {final _that = this;
switch (_that) {
case _TextChunk() when $default != null:
return $default(_that.fieldId,_that.offset,_that.text,_that.nextOffset);case _:
  return null;

}
}

}

/// @nodoc


class _TextChunk implements TextChunk {
  const _TextChunk({required this.fieldId, required this.offset, required this.text, required this.nextOffset});


@override final  int fieldId;
@override final  int offset;
@override final  String text;
@override final  int? nextOffset;

/// Create a copy of TextChunk
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TextChunkCopyWith<_TextChunk> get copyWith => __$TextChunkCopyWithImpl<_TextChunk>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TextChunk&&(identical(other.fieldId, fieldId) || other.fieldId == fieldId)&&(identical(other.offset, offset) || other.offset == offset)&&(identical(other.text, text) || other.text == text)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset));
}


@override
int get hashCode {
    return Object.hash(runtimeType,fieldId,offset,text,nextOffset);
}



}

/// @nodoc
abstract mixin class _$TextChunkCopyWith<$Res> implements $TextChunkCopyWith<$Res> {
  factory _$TextChunkCopyWith(_TextChunk value, $Res Function(_TextChunk) _then) = __$TextChunkCopyWithImpl;
@override @useResult
$Res call({
 int fieldId, int offset, String text, int? nextOffset
});




}
/// @nodoc
class __$TextChunkCopyWithImpl<$Res>
    implements _$TextChunkCopyWith<$Res> {
  __$TextChunkCopyWithImpl(this._self, this._then);

  final _TextChunk _self;
  final $Res Function(_TextChunk) _then;

/// Create a copy of TextChunk
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? fieldId = null,Object? offset = null,Object? text = null,Object? nextOffset = freezed,}) {
  return _then(_TextChunk(
fieldId: null == fieldId ? _self.fieldId : fieldId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,text: null == text ? _self.text : text // ignore: cast_nullable_to_non_nullable
as String,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc
mixin _$TypedListRef {

 int get listId; int get total;
/// Create a copy of TypedListRef
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TypedListRefCopyWith<TypedListRef> get copyWith => _$TypedListRefCopyWithImpl<TypedListRef>(this as TypedListRef, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TypedListRef;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TypedListRef&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.total, _this.total) || other.total == _this.total));
}


@override
int get hashCode {
  final _this = this as TypedListRef;
  return Object.hash(runtimeType,_this.listId,_this.total);
}

@override
String toString() {
  final _this = this as TypedListRef;
  return 'TypedListRef(listId: ${_this.listId}, total: ${_this.total})';
}


}

/// @nodoc
abstract mixin class $TypedListRefCopyWith<$Res>  {
  factory $TypedListRefCopyWith(TypedListRef value, $Res Function(TypedListRef) _then) = _$TypedListRefCopyWithImpl;
@useResult
$Res call({
 int listId, int total
});




}
/// @nodoc
class _$TypedListRefCopyWithImpl<$Res>
    implements $TypedListRefCopyWith<$Res> {
  _$TypedListRefCopyWithImpl(this._self, this._then);

  final TypedListRef _self;
  final $Res Function(TypedListRef) _then;

/// Create a copy of TypedListRef
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? total = null,}) {
  return _then(TypedListRef(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [TypedListRef].
extension TypedListRefPatterns on TypedListRef {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TypedListRef value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TypedListRef() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TypedListRef value)  $default,){
final _that = this;
switch (_that) {
case _TypedListRef():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TypedListRef value)?  $default,){
final _that = this;
switch (_that) {
case _TypedListRef() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( int listId,  int total)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TypedListRef() when $default != null:
return $default(_that.listId,_that.total);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( int listId,  int total)  $default,) {final _that = this;
switch (_that) {
case _TypedListRef():
return $default(_that.listId,_that.total);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( int listId,  int total)?  $default,) {final _that = this;
switch (_that) {
case _TypedListRef() when $default != null:
return $default(_that.listId,_that.total);case _:
  return null;

}
}

}

/// @nodoc


class _TypedListRef implements TypedListRef {
  const _TypedListRef({required this.listId, required this.total});


@override final  int listId;
@override final  int total;

/// Create a copy of TypedListRef
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TypedListRefCopyWith<_TypedListRef> get copyWith => __$TypedListRefCopyWithImpl<_TypedListRef>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TypedListRef&&(identical(other.listId, listId) || other.listId == listId)&&(identical(other.total, total) || other.total == total));
}


@override
int get hashCode {
    return Object.hash(runtimeType,listId,total);
}

@override
String toString() {
    return 'TypedListRef(listId: $listId, total: $total)';
}


}

/// @nodoc
abstract mixin class _$TypedListRefCopyWith<$Res> implements $TypedListRefCopyWith<$Res> {
  factory _$TypedListRefCopyWith(_TypedListRef value, $Res Function(_TypedListRef) _then) = __$TypedListRefCopyWithImpl;
@override @useResult
$Res call({
 int listId, int total
});




}
/// @nodoc
class __$TypedListRefCopyWithImpl<$Res>
    implements _$TypedListRefCopyWith<$Res> {
  __$TypedListRefCopyWithImpl(this._self, this._then);

  final _TypedListRef _self;
  final $Res Function(_TypedListRef) _then;

/// Create a copy of TypedListRef
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? listId = null,Object? total = null,}) {
  return _then(_TypedListRef(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$TextReadItem {

 ReadText get value;
/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextReadItemCopyWith<TextReadItem> get copyWith => _$TextReadItemCopyWithImpl<TextReadItem>(this as TextReadItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TextReadItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextReadItem&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as TextReadItem;
  return Object.hash(runtimeType,_this.value);
}



}

/// @nodoc
abstract mixin class $TextReadItemCopyWith<$Res>  {
  factory $TextReadItemCopyWith(TextReadItem value, $Res Function(TextReadItem) _then) = _$TextReadItemCopyWithImpl;
@useResult
$Res call({
 ReadText value
});


$ReadTextCopyWith<$Res> get value;

}
/// @nodoc
class _$TextReadItemCopyWithImpl<$Res>
    implements $TextReadItemCopyWith<$Res> {
  _$TextReadItemCopyWithImpl(this._self, this._then);

  final TextReadItem _self;
  final $Res Function(TextReadItem) _then;

/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? value = null,}) {
  return _then(TextReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}
/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get value {

  return $ReadTextCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [TextReadItem].
extension TextReadItemPatterns on TextReadItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _TextReadItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _TextReadItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _TextReadItem value)  $default,){
final _that = this;
switch (_that) {
case _TextReadItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _TextReadItem value)?  $default,){
final _that = this;
switch (_that) {
case _TextReadItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _TextReadItem() when $default != null:
return $default(_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText value)  $default,) {final _that = this;
switch (_that) {
case _TextReadItem():
return $default(_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText value)?  $default,) {final _that = this;
switch (_that) {
case _TextReadItem() when $default != null:
return $default(_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _TextReadItem implements TextReadItem {
  const _TextReadItem({required this.value});


@override final  ReadText value;

/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$TextReadItemCopyWith<_TextReadItem> get copyWith => __$TextReadItemCopyWithImpl<_TextReadItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _TextReadItem&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,value);
}



}

/// @nodoc
abstract mixin class _$TextReadItemCopyWith<$Res> implements $TextReadItemCopyWith<$Res> {
  factory _$TextReadItemCopyWith(_TextReadItem value, $Res Function(_TextReadItem) _then) = __$TextReadItemCopyWithImpl;
@override @useResult
$Res call({
 ReadText value
});


@override $ReadTextCopyWith<$Res> get value;

}
/// @nodoc
class __$TextReadItemCopyWithImpl<$Res>
    implements _$TextReadItemCopyWith<$Res> {
  __$TextReadItemCopyWithImpl(this._self, this._then);

  final _TextReadItem _self;
  final $Res Function(_TextReadItem) _then;

/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? value = null,}) {
  return _then(_TextReadItem(
value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ReadText,
  ));
}

/// Create a copy of TextReadItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get value {

  return $ReadTextCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$TextReadPage {


/// Create a copy of TextReadPage
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$TextReadPageCopyWith<TextReadPage> get copyWith => _$TextReadPageCopyWithImpl<TextReadPage>(this as TextReadPage, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as TextReadPage;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is TextReadPage&&(identical(other.listId, _this.listId) || other.listId == _this.listId)&&(identical(other.offset, _this.offset) || other.offset == _this.offset)&&(identical(other.total, _this.total) || other.total == _this.total)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset));
}


@override
int get hashCode {
  final _this = this as TextReadPage;
  return Object.hash(runtimeType,_this.listId,_this.offset,_this.total,const DeepCollectionEquality().hash(_this.items),_this.nextOffset);
}



}

/// @nodoc
abstract mixin class $TextReadPageCopyWith<$Res>  {
  factory $TextReadPageCopyWith(TextReadPage value, $Res Function(TextReadPage) _then) = _$TextReadPageCopyWithImpl;
@useResult
$Res call({
 int listId, int offset, int total, List<TextReadItem> items, int? nextOffset
});




}
/// @nodoc
class _$TextReadPageCopyWithImpl<$Res>
    implements $TextReadPageCopyWith<$Res> {
  _$TextReadPageCopyWithImpl(this._self, this._then);

  final TextReadPage _self;
  final $Res Function(TextReadPage) _then;

/// Create a copy of TextReadPage
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? listId = null,Object? offset = null,Object? total = null,Object? items = null,Object? nextOffset = freezed,}) {
  return _then(TextReadPage(
listId: null == listId ? _self.listId : listId // ignore: cast_nullable_to_non_nullable
as int,offset: null == offset ? _self.offset : offset // ignore: cast_nullable_to_non_nullable
as int,total: null == total ? _self.total : total // ignore: cast_nullable_to_non_nullable
as int,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<TextReadItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [TextReadPage].
extension TextReadPagePatterns on TextReadPage {
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
