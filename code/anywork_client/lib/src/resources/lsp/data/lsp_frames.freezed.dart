// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'lsp_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$LspBaseline {

 LspHeader get header; ProductCollectionRef? get collection;
/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspBaselineCopyWith<LspBaseline> get copyWith => _$LspBaselineCopyWithImpl<LspBaseline>(this as LspBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as LspBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as LspBaseline;
  return 'LspBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $LspBaselineCopyWith<$Res>  {
  factory $LspBaselineCopyWith(LspBaseline value, $Res Function(LspBaseline) _then) = _$LspBaselineCopyWithImpl;
@useResult
$Res call({
 LspHeader header, ProductCollectionRef? collection
});


$LspHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$LspBaselineCopyWithImpl<$Res>
    implements $LspBaselineCopyWith<$Res> {
  _$LspBaselineCopyWithImpl(this._self, this._then);

  final LspBaseline _self;
  final $Res Function(LspBaseline) _then;

/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(LspBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as LspHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspHeaderCopyWith<$Res> get header {

  return $LspHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspBaseline].
extension LspBaselinePatterns on LspBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _LspBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _LspBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _LspBaseline value)  $default,){
final _that = this;
switch (_that) {
case _LspBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _LspBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _LspBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( LspHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _LspBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( LspHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _LspBaseline():
return $default(_that.header,_that.collection);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( LspHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _LspBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _LspBaseline implements LspBaseline {
  const _LspBaseline({required this.header, required this.collection});


@override final  LspHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$LspBaselineCopyWith<_LspBaseline> get copyWith => __$LspBaselineCopyWithImpl<_LspBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _LspBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'LspBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$LspBaselineCopyWith<$Res> implements $LspBaselineCopyWith<$Res> {
  factory _$LspBaselineCopyWith(_LspBaseline value, $Res Function(_LspBaseline) _then) = __$LspBaselineCopyWithImpl;
@override @useResult
$Res call({
 LspHeader header, ProductCollectionRef? collection
});


@override $LspHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$LspBaselineCopyWithImpl<$Res>
    implements _$LspBaselineCopyWith<$Res> {
  __$LspBaselineCopyWithImpl(this._self, this._then);

  final _LspBaseline _self;
  final $Res Function(_LspBaseline) _then;

/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_LspBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as LspHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspHeaderCopyWith<$Res> get header {

  return $LspHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of LspBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$LspChange {


/// Create a copy of LspChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspChangeCopyWith<LspChange> get copyWith => _$LspChangeCopyWithImpl<LspChange>(this as LspChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as LspChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $LspChangeCopyWith<$Res>  {
  factory $LspChangeCopyWith(LspChange value, $Res Function(LspChange) _then) = _$LspChangeCopyWithImpl;
@useResult
$Res call({
 LspHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$LspHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$LspChangeCopyWithImpl<$Res>
    implements $LspChangeCopyWith<$Res> {
  _$LspChangeCopyWithImpl(this._self, this._then);

  final LspChange _self;
  final $Res Function(LspChange) _then;

/// Create a copy of LspChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(LspChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as LspHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of LspChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspHeaderCopyWith<$Res> get header {

  return $LspHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of LspChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspChange].
extension LspChangePatterns on LspChange {
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
mixin _$LspEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspEventCopyWith<LspEvent> get copyWith => _$LspEventCopyWithImpl<LspEvent>(this as LspEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as LspEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is LspEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as LspEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as LspEvent;
  return 'LspEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $LspEventCopyWith<$Res>  {
  factory $LspEventCopyWith(LspEvent value, $Res Function(LspEvent) _then) = _$LspEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$LspEventCopyWithImpl<$Res>
    implements $LspEventCopyWith<$Res> {
  _$LspEventCopyWithImpl(this._self, this._then);

  final LspEvent _self;
  final $Res Function(LspEvent) _then;

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [LspEvent].
extension LspEventPatterns on LspEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LspBaselineEvent value)?  baseline,TResult Function( LspChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LspBaselineEvent() when baseline != null:
return baseline(_that);case LspChangeEvent() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LspBaselineEvent value)  baseline,required TResult Function( LspChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case LspBaselineEvent():
return baseline(_that);case LspChangeEvent():
return change(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LspBaselineEvent value)?  baseline,TResult? Function( LspChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case LspBaselineEvent() when baseline != null:
return baseline(_that);case LspChangeEvent() when change != null:
return change(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  LspBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  LspChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LspBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case LspChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  LspBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  LspChange value)  change,}) {final _that = this;
switch (_that) {
case LspBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case LspChangeEvent():
return change(_that.stamp,_that.baseRevision,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  LspBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  LspChange value)?  change,}) {final _that = this;
switch (_that) {
case LspBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case LspChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class LspBaselineEvent implements LspEvent {
  const LspBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  LspBaseline value;

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspBaselineEventCopyWith<LspBaselineEvent> get copyWith => _$LspBaselineEventCopyWithImpl<LspBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'LspEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $LspBaselineEventCopyWith<$Res> implements $LspEventCopyWith<$Res> {
  factory $LspBaselineEventCopyWith(LspBaselineEvent value, $Res Function(LspBaselineEvent) _then) = _$LspBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, LspBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$LspBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$LspBaselineEventCopyWithImpl<$Res>
    implements $LspBaselineEventCopyWith<$Res> {
  _$LspBaselineEventCopyWithImpl(this._self, this._then);

  final LspBaselineEvent _self;
  final $Res Function(LspBaselineEvent) _then;

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(LspBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as LspBaseline,
  ));
}

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspBaselineCopyWith<$Res> get value {

  return $LspBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class LspChangeEvent implements LspEvent {
  const LspChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  LspChange value;

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspChangeEventCopyWith<LspChangeEvent> get copyWith => _$LspChangeEventCopyWithImpl<LspChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'LspEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $LspChangeEventCopyWith<$Res> implements $LspEventCopyWith<$Res> {
  factory $LspChangeEventCopyWith(LspChangeEvent value, $Res Function(LspChangeEvent) _then) = _$LspChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, LspChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$LspChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$LspChangeEventCopyWithImpl<$Res>
    implements $LspChangeEventCopyWith<$Res> {
  _$LspChangeEventCopyWithImpl(this._self, this._then);

  final LspChangeEvent _self;
  final $Res Function(LspChangeEvent) _then;

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(LspChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as LspChange,
  ));
}

/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of LspEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspChangeCopyWith<$Res> get value {

  return $LspChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$LspFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $LspFrameCopyWith<$Res>  {
$LspFrameCopyWith(LspFrame _, $Res Function(LspFrame) __);
}


/// Adds pattern-matching-related methods to [LspFrame].
extension LspFramePatterns on LspFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( LspData value)?  data,TResult Function( LspResyncRequired value)?  resyncRequired,TResult Function( LspFeedFailure value)?  failure,TResult Function( LspClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case LspData() when data != null:
return data(_that);case LspResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case LspFeedFailure() when failure != null:
return failure(_that);case LspClosed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( LspData value)  data,required TResult Function( LspResyncRequired value)  resyncRequired,required TResult Function( LspFeedFailure value)  failure,required TResult Function( LspClosed value)  closed,}){
final _that = this;
switch (_that) {
case LspData():
return data(_that);case LspResyncRequired():
return resyncRequired(_that);case LspFeedFailure():
return failure(_that);case LspClosed():
return closed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( LspData value)?  data,TResult? Function( LspResyncRequired value)?  resyncRequired,TResult? Function( LspFeedFailure value)?  failure,TResult? Function( LspClosed value)?  closed,}){
final _that = this;
switch (_that) {
case LspData() when data != null:
return data(_that);case LspResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case LspFeedFailure() when failure != null:
return failure(_that);case LspClosed() when closed != null:
return closed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  LspEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case LspData() when data != null:
return data(_that.deliverySequence,_that.event);case LspResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case LspFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case LspClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  LspEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case LspData():
return data(_that.deliverySequence,_that.event);case LspResyncRequired():
return resyncRequired(_that.identity,_that.reason);case LspFeedFailure():
return failure(_that.identity,_that.error);case LspClosed():
return closed(_that.identity,_that.reason);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  LspEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case LspData() when data != null:
return data(_that.deliverySequence,_that.event);case LspResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case LspFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case LspClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class LspData implements LspFrame {
  const LspData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  LspEvent event;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspDataCopyWith<LspData> get copyWith => _$LspDataCopyWithImpl<LspData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $LspDataCopyWith<$Res> implements $LspFrameCopyWith<$Res> {
  factory $LspDataCopyWith(LspData value, $Res Function(LspData) _then) = _$LspDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, LspEvent event
});


$LspEventCopyWith<$Res> get event;

}
/// @nodoc
class _$LspDataCopyWithImpl<$Res>
    implements $LspDataCopyWith<$Res> {
  _$LspDataCopyWithImpl(this._self, this._then);

  final LspData _self;
  final $Res Function(LspData) _then;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(LspData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as LspEvent,
  ));
}

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$LspEventCopyWith<$Res> get event {

  return $LspEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class LspResyncRequired implements LspFrame {
  const LspResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspResyncRequiredCopyWith<LspResyncRequired> get copyWith => _$LspResyncRequiredCopyWithImpl<LspResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $LspResyncRequiredCopyWith<$Res> implements $LspFrameCopyWith<$Res> {
  factory $LspResyncRequiredCopyWith(LspResyncRequired value, $Res Function(LspResyncRequired) _then) = _$LspResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$LspResyncRequiredCopyWithImpl<$Res>
    implements $LspResyncRequiredCopyWith<$Res> {
  _$LspResyncRequiredCopyWithImpl(this._self, this._then);

  final LspResyncRequired _self;
  final $Res Function(LspResyncRequired) _then;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(LspResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class LspFeedFailure implements LspFrame {
  const LspFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspFeedFailureCopyWith<LspFeedFailure> get copyWith => _$LspFeedFailureCopyWithImpl<LspFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $LspFeedFailureCopyWith<$Res> implements $LspFrameCopyWith<$Res> {
  factory $LspFeedFailureCopyWith(LspFeedFailure value, $Res Function(LspFeedFailure) _then) = _$LspFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$LspFeedFailureCopyWithImpl<$Res>
    implements $LspFeedFailureCopyWith<$Res> {
  _$LspFeedFailureCopyWithImpl(this._self, this._then);

  final LspFeedFailure _self;
  final $Res Function(LspFeedFailure) _then;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(LspFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of LspFrame
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


class LspClosed implements LspFrame {
  const LspClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LspClosedCopyWith<LspClosed> get copyWith => _$LspClosedCopyWithImpl<LspClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LspClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $LspClosedCopyWith<$Res> implements $LspFrameCopyWith<$Res> {
  factory $LspClosedCopyWith(LspClosed value, $Res Function(LspClosed) _then) = _$LspClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$LspClosedCopyWithImpl<$Res>
    implements $LspClosedCopyWith<$Res> {
  _$LspClosedCopyWithImpl(this._self, this._then);

  final LspClosed _self;
  final $Res Function(LspClosed) _then;

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(LspClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of LspFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

// dart format on
