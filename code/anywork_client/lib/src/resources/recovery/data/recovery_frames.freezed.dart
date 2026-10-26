// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'recovery_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$RecoveryBaseline {

 RecoveryHeader get header; ProductCollectionRef? get collection;
/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryBaselineCopyWith<RecoveryBaseline> get copyWith => _$RecoveryBaselineCopyWithImpl<RecoveryBaseline>(this as RecoveryBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as RecoveryBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as RecoveryBaseline;
  return 'RecoveryBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $RecoveryBaselineCopyWith<$Res>  {
  factory $RecoveryBaselineCopyWith(RecoveryBaseline value, $Res Function(RecoveryBaseline) _then) = _$RecoveryBaselineCopyWithImpl;
@useResult
$Res call({
 RecoveryHeader header, ProductCollectionRef? collection
});


$RecoveryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$RecoveryBaselineCopyWithImpl<$Res>
    implements $RecoveryBaselineCopyWith<$Res> {
  _$RecoveryBaselineCopyWithImpl(this._self, this._then);

  final RecoveryBaseline _self;
  final $Res Function(RecoveryBaseline) _then;

/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(RecoveryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as RecoveryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryHeaderCopyWith<$Res> get header {

  return $RecoveryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of RecoveryBaseline
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


/// Adds pattern-matching-related methods to [RecoveryBaseline].
extension RecoveryBaselinePatterns on RecoveryBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _RecoveryBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _RecoveryBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _RecoveryBaseline value)  $default,){
final _that = this;
switch (_that) {
case _RecoveryBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _RecoveryBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _RecoveryBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( RecoveryHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _RecoveryBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( RecoveryHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _RecoveryBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( RecoveryHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _RecoveryBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _RecoveryBaseline implements RecoveryBaseline {
  const _RecoveryBaseline({required this.header, required this.collection});


@override final  RecoveryHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$RecoveryBaselineCopyWith<_RecoveryBaseline> get copyWith => __$RecoveryBaselineCopyWithImpl<_RecoveryBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _RecoveryBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'RecoveryBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$RecoveryBaselineCopyWith<$Res> implements $RecoveryBaselineCopyWith<$Res> {
  factory _$RecoveryBaselineCopyWith(_RecoveryBaseline value, $Res Function(_RecoveryBaseline) _then) = __$RecoveryBaselineCopyWithImpl;
@override @useResult
$Res call({
 RecoveryHeader header, ProductCollectionRef? collection
});


@override $RecoveryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$RecoveryBaselineCopyWithImpl<$Res>
    implements _$RecoveryBaselineCopyWith<$Res> {
  __$RecoveryBaselineCopyWithImpl(this._self, this._then);

  final _RecoveryBaseline _self;
  final $Res Function(_RecoveryBaseline) _then;

/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_RecoveryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as RecoveryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of RecoveryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryHeaderCopyWith<$Res> get header {

  return $RecoveryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of RecoveryBaseline
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
mixin _$RecoveryChange {


/// Create a copy of RecoveryChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryChangeCopyWith<RecoveryChange> get copyWith => _$RecoveryChangeCopyWithImpl<RecoveryChange>(this as RecoveryChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as RecoveryChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $RecoveryChangeCopyWith<$Res>  {
  factory $RecoveryChangeCopyWith(RecoveryChange value, $Res Function(RecoveryChange) _then) = _$RecoveryChangeCopyWithImpl;
@useResult
$Res call({
 RecoveryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$RecoveryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$RecoveryChangeCopyWithImpl<$Res>
    implements $RecoveryChangeCopyWith<$Res> {
  _$RecoveryChangeCopyWithImpl(this._self, this._then);

  final RecoveryChange _self;
  final $Res Function(RecoveryChange) _then;

/// Create a copy of RecoveryChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(RecoveryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as RecoveryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of RecoveryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryHeaderCopyWith<$Res> get header {

  return $RecoveryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of RecoveryChange
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


/// Adds pattern-matching-related methods to [RecoveryChange].
extension RecoveryChangePatterns on RecoveryChange {
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
mixin _$RecoveryEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryEventCopyWith<RecoveryEvent> get copyWith => _$RecoveryEventCopyWithImpl<RecoveryEvent>(this as RecoveryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as RecoveryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as RecoveryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as RecoveryEvent;
  return 'RecoveryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $RecoveryEventCopyWith<$Res>  {
  factory $RecoveryEventCopyWith(RecoveryEvent value, $Res Function(RecoveryEvent) _then) = _$RecoveryEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$RecoveryEventCopyWithImpl<$Res>
    implements $RecoveryEventCopyWith<$Res> {
  _$RecoveryEventCopyWithImpl(this._self, this._then);

  final RecoveryEvent _self;
  final $Res Function(RecoveryEvent) _then;

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [RecoveryEvent].
extension RecoveryEventPatterns on RecoveryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RecoveryBaselineEvent value)?  baseline,TResult Function( RecoveryChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RecoveryBaselineEvent() when baseline != null:
return baseline(_that);case RecoveryChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RecoveryBaselineEvent value)  baseline,required TResult Function( RecoveryChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case RecoveryBaselineEvent():
return baseline(_that);case RecoveryChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RecoveryBaselineEvent value)?  baseline,TResult? Function( RecoveryChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case RecoveryBaselineEvent() when baseline != null:
return baseline(_that);case RecoveryChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  RecoveryBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  RecoveryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RecoveryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case RecoveryChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  RecoveryBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  RecoveryChange value)  change,}) {final _that = this;
switch (_that) {
case RecoveryBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case RecoveryChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  RecoveryBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  RecoveryChange value)?  change,}) {final _that = this;
switch (_that) {
case RecoveryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case RecoveryChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class RecoveryBaselineEvent implements RecoveryEvent {
  const RecoveryBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  RecoveryBaseline value;

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryBaselineEventCopyWith<RecoveryBaselineEvent> get copyWith => _$RecoveryBaselineEventCopyWithImpl<RecoveryBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'RecoveryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $RecoveryBaselineEventCopyWith<$Res> implements $RecoveryEventCopyWith<$Res> {
  factory $RecoveryBaselineEventCopyWith(RecoveryBaselineEvent value, $Res Function(RecoveryBaselineEvent) _then) = _$RecoveryBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, RecoveryBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$RecoveryBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$RecoveryBaselineEventCopyWithImpl<$Res>
    implements $RecoveryBaselineEventCopyWith<$Res> {
  _$RecoveryBaselineEventCopyWithImpl(this._self, this._then);

  final RecoveryBaselineEvent _self;
  final $Res Function(RecoveryBaselineEvent) _then;

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(RecoveryBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RecoveryBaseline,
  ));
}

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryBaselineCopyWith<$Res> get value {

  return $RecoveryBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class RecoveryChangeEvent implements RecoveryEvent {
  const RecoveryChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  RecoveryChange value;

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryChangeEventCopyWith<RecoveryChangeEvent> get copyWith => _$RecoveryChangeEventCopyWithImpl<RecoveryChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'RecoveryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $RecoveryChangeEventCopyWith<$Res> implements $RecoveryEventCopyWith<$Res> {
  factory $RecoveryChangeEventCopyWith(RecoveryChangeEvent value, $Res Function(RecoveryChangeEvent) _then) = _$RecoveryChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, RecoveryChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$RecoveryChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$RecoveryChangeEventCopyWithImpl<$Res>
    implements $RecoveryChangeEventCopyWith<$Res> {
  _$RecoveryChangeEventCopyWithImpl(this._self, this._then);

  final RecoveryChangeEvent _self;
  final $Res Function(RecoveryChangeEvent) _then;

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(RecoveryChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as RecoveryChange,
  ));
}

/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of RecoveryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryChangeCopyWith<$Res> get value {

  return $RecoveryChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$RecoveryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $RecoveryFrameCopyWith<$Res>  {
$RecoveryFrameCopyWith(RecoveryFrame _, $Res Function(RecoveryFrame) __);
}


/// Adds pattern-matching-related methods to [RecoveryFrame].
extension RecoveryFramePatterns on RecoveryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( RecoveryData value)?  data,TResult Function( RecoveryResyncRequired value)?  resyncRequired,TResult Function( RecoveryFeedFailure value)?  failure,TResult Function( RecoveryClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case RecoveryData() when data != null:
return data(_that);case RecoveryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case RecoveryFeedFailure() when failure != null:
return failure(_that);case RecoveryClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( RecoveryData value)  data,required TResult Function( RecoveryResyncRequired value)  resyncRequired,required TResult Function( RecoveryFeedFailure value)  failure,required TResult Function( RecoveryClosed value)  closed,}){
final _that = this;
switch (_that) {
case RecoveryData():
return data(_that);case RecoveryResyncRequired():
return resyncRequired(_that);case RecoveryFeedFailure():
return failure(_that);case RecoveryClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( RecoveryData value)?  data,TResult? Function( RecoveryResyncRequired value)?  resyncRequired,TResult? Function( RecoveryFeedFailure value)?  failure,TResult? Function( RecoveryClosed value)?  closed,}){
final _that = this;
switch (_that) {
case RecoveryData() when data != null:
return data(_that);case RecoveryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case RecoveryFeedFailure() when failure != null:
return failure(_that);case RecoveryClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  RecoveryEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case RecoveryData() when data != null:
return data(_that.deliverySequence,_that.event);case RecoveryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case RecoveryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case RecoveryClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  RecoveryEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case RecoveryData():
return data(_that.deliverySequence,_that.event);case RecoveryResyncRequired():
return resyncRequired(_that.identity,_that.reason);case RecoveryFeedFailure():
return failure(_that.identity,_that.error);case RecoveryClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  RecoveryEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case RecoveryData() when data != null:
return data(_that.deliverySequence,_that.event);case RecoveryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case RecoveryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case RecoveryClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class RecoveryData implements RecoveryFrame {
  const RecoveryData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  RecoveryEvent event;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryDataCopyWith<RecoveryData> get copyWith => _$RecoveryDataCopyWithImpl<RecoveryData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $RecoveryDataCopyWith<$Res> implements $RecoveryFrameCopyWith<$Res> {
  factory $RecoveryDataCopyWith(RecoveryData value, $Res Function(RecoveryData) _then) = _$RecoveryDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, RecoveryEvent event
});


$RecoveryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$RecoveryDataCopyWithImpl<$Res>
    implements $RecoveryDataCopyWith<$Res> {
  _$RecoveryDataCopyWithImpl(this._self, this._then);

  final RecoveryData _self;
  final $Res Function(RecoveryData) _then;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(RecoveryData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as RecoveryEvent,
  ));
}

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$RecoveryEventCopyWith<$Res> get event {

  return $RecoveryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class RecoveryResyncRequired implements RecoveryFrame {
  const RecoveryResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryResyncRequiredCopyWith<RecoveryResyncRequired> get copyWith => _$RecoveryResyncRequiredCopyWithImpl<RecoveryResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $RecoveryResyncRequiredCopyWith<$Res> implements $RecoveryFrameCopyWith<$Res> {
  factory $RecoveryResyncRequiredCopyWith(RecoveryResyncRequired value, $Res Function(RecoveryResyncRequired) _then) = _$RecoveryResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$RecoveryResyncRequiredCopyWithImpl<$Res>
    implements $RecoveryResyncRequiredCopyWith<$Res> {
  _$RecoveryResyncRequiredCopyWithImpl(this._self, this._then);

  final RecoveryResyncRequired _self;
  final $Res Function(RecoveryResyncRequired) _then;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(RecoveryResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of RecoveryFrame
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


class RecoveryFeedFailure implements RecoveryFrame {
  const RecoveryFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryFeedFailureCopyWith<RecoveryFeedFailure> get copyWith => _$RecoveryFeedFailureCopyWithImpl<RecoveryFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $RecoveryFeedFailureCopyWith<$Res> implements $RecoveryFrameCopyWith<$Res> {
  factory $RecoveryFeedFailureCopyWith(RecoveryFeedFailure value, $Res Function(RecoveryFeedFailure) _then) = _$RecoveryFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$RecoveryFeedFailureCopyWithImpl<$Res>
    implements $RecoveryFeedFailureCopyWith<$Res> {
  _$RecoveryFeedFailureCopyWithImpl(this._self, this._then);

  final RecoveryFeedFailure _self;
  final $Res Function(RecoveryFeedFailure) _then;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(RecoveryFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of RecoveryFrame
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


class RecoveryClosed implements RecoveryFrame {
  const RecoveryClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RecoveryClosedCopyWith<RecoveryClosed> get copyWith => _$RecoveryClosedCopyWithImpl<RecoveryClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RecoveryClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $RecoveryClosedCopyWith<$Res> implements $RecoveryFrameCopyWith<$Res> {
  factory $RecoveryClosedCopyWith(RecoveryClosed value, $Res Function(RecoveryClosed) _then) = _$RecoveryClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$RecoveryClosedCopyWithImpl<$Res>
    implements $RecoveryClosedCopyWith<$Res> {
  _$RecoveryClosedCopyWithImpl(this._self, this._then);

  final RecoveryClosed _self;
  final $Res Function(RecoveryClosed) _then;

/// Create a copy of RecoveryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(RecoveryClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of RecoveryFrame
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
