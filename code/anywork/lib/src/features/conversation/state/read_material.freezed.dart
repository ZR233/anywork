// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'read_material.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ReadMaterial<H,I> {

 H? get header; List<I> get items; Map<int, TextReadProgress> get texts; int? get nextOffset; bool get loading; StudioFailure? get error;
/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadMaterialCopyWith<H, I, ReadMaterial<H, I>> get copyWith => _$ReadMaterialCopyWithImpl<H, I, ReadMaterial<H, I>>(this as ReadMaterial<H, I>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ReadMaterial<H, I>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadMaterial<H, I>&&const DeepCollectionEquality().equals(other.header, _this.header)&&const DeepCollectionEquality().equals(other.items, _this.items)&&const DeepCollectionEquality().equals(other.texts, _this.texts)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ReadMaterial<H, I>;
  return Object.hash(runtimeType,const DeepCollectionEquality().hash(_this.header),const DeepCollectionEquality().hash(_this.items),const DeepCollectionEquality().hash(_this.texts),_this.nextOffset,_this.loading,_this.error);
}



}

/// @nodoc
abstract mixin class $ReadMaterialCopyWith<H,I,$Res>  {
  factory $ReadMaterialCopyWith(ReadMaterial<H, I> value, $Res Function(ReadMaterial<H, I>) _then) = _$ReadMaterialCopyWithImpl;
@useResult
$Res call({
 H? header, List<I> items, Map<int, TextReadProgress> texts, int? nextOffset, bool loading, StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ReadMaterialCopyWithImpl<H,I,$Res>
    implements $ReadMaterialCopyWith<H, I, $Res> {
  _$ReadMaterialCopyWithImpl(this._self, this._then);

  final ReadMaterial<H, I> _self;
  final $Res Function(ReadMaterial<H, I>) _then;

/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = freezed,Object? items = null,Object? texts = null,Object? nextOffset = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(ReadMaterial(
header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as H?,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<I>,texts: null == texts ? _self.texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}


/// Adds pattern-matching-related methods to [ReadMaterial].
extension ReadMaterialPatterns<H,I> on ReadMaterial<H, I> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ReadMaterial<H, I> value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ReadMaterial() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ReadMaterial<H, I> value)  $default,){
final _that = this;
switch (_that) {
case _ReadMaterial():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ReadMaterial<H, I> value)?  $default,){
final _that = this;
switch (_that) {
case _ReadMaterial() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( H? header,  List<I> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool loading,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ReadMaterial() when $default != null:
return $default(_that.header,_that.items,_that.texts,_that.nextOffset,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( H? header,  List<I> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool loading,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _ReadMaterial():
return $default(_that.header,_that.items,_that.texts,_that.nextOffset,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( H? header,  List<I> items,  Map<int, TextReadProgress> texts,  int? nextOffset,  bool loading,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _ReadMaterial() when $default != null:
return $default(_that.header,_that.items,_that.texts,_that.nextOffset,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ReadMaterial<H,I> extends ReadMaterial<H, I> {
  const _ReadMaterial({this.header,  List<I> items = const [],  Map<int, TextReadProgress> texts = const {}, this.nextOffset, this.loading = false, this.error}): _items = items,_texts = texts,super._();


@override final  H? header;
 final  List<I> _items;
@override@JsonKey() List<I> get items {
  if (_items is EqualUnmodifiableListView) return _items;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_items);
}

 final  Map<int, TextReadProgress> _texts;
@override@JsonKey() Map<int, TextReadProgress> get texts {
  if (_texts is EqualUnmodifiableMapView) return _texts;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableMapView(_texts);
}

@override final  int? nextOffset;
@override@JsonKey() final  bool loading;
@override final  StudioFailure? error;

/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ReadMaterialCopyWith<H, I, _ReadMaterial<H, I>> get copyWith => __$ReadMaterialCopyWithImpl<H, I, _ReadMaterial<H, I>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ReadMaterial<H, I>&&const DeepCollectionEquality().equals(other.header, header)&&const DeepCollectionEquality().equals(other.items, _items)&&const DeepCollectionEquality().equals(other.texts, _texts)&&(identical(other.nextOffset, nextOffset) || other.nextOffset == nextOffset)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,const DeepCollectionEquality().hash(header),const DeepCollectionEquality().hash(_items),const DeepCollectionEquality().hash(_texts),nextOffset,loading,error);
}



}

/// @nodoc
abstract mixin class _$ReadMaterialCopyWith<H,I,$Res> implements $ReadMaterialCopyWith<H, I, $Res> {
  factory _$ReadMaterialCopyWith(_ReadMaterial<H, I> value, $Res Function(_ReadMaterial<H, I>) _then) = __$ReadMaterialCopyWithImpl;
@override @useResult
$Res call({
 H? header, List<I> items, Map<int, TextReadProgress> texts, int? nextOffset, bool loading, StudioFailure? error
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ReadMaterialCopyWithImpl<H,I,$Res>
    implements _$ReadMaterialCopyWith<H, I, $Res> {
  __$ReadMaterialCopyWithImpl(this._self, this._then);

  final _ReadMaterial<H, I> _self;
  final $Res Function(_ReadMaterial<H, I>) _then;

/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = freezed,Object? items = null,Object? texts = null,Object? nextOffset = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(_ReadMaterial<H, I>(
header: freezed == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as H?,items: null == items ? _self._items : items // ignore: cast_nullable_to_non_nullable
as List<I>,texts: null == texts ? _self._texts : texts // ignore: cast_nullable_to_non_nullable
as Map<int, TextReadProgress>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ReadMaterial
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$StudioFailureCopyWith<$Res>? get error {
    if (_self.error == null) {
    return null;
  }

  return $StudioFailureCopyWith<$Res>(_self.error!, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

// dart format on
