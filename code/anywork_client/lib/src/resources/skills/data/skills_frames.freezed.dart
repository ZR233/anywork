// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'skills_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SkillsBaseline {

 SkillsHeader get header; ProductCollectionRef? get collection;
/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsBaselineCopyWith<SkillsBaseline> get copyWith => _$SkillsBaselineCopyWithImpl<SkillsBaseline>(this as SkillsBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as SkillsBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as SkillsBaseline;
  return 'SkillsBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $SkillsBaselineCopyWith<$Res>  {
  factory $SkillsBaselineCopyWith(SkillsBaseline value, $Res Function(SkillsBaseline) _then) = _$SkillsBaselineCopyWithImpl;
@useResult
$Res call({
 SkillsHeader header, ProductCollectionRef? collection
});


$SkillsHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$SkillsBaselineCopyWithImpl<$Res>
    implements $SkillsBaselineCopyWith<$Res> {
  _$SkillsBaselineCopyWithImpl(this._self, this._then);

  final SkillsBaseline _self;
  final $Res Function(SkillsBaseline) _then;

/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(SkillsBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as SkillsHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsHeaderCopyWith<$Res> get header {

  return $SkillsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of SkillsBaseline
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


/// Adds pattern-matching-related methods to [SkillsBaseline].
extension SkillsBaselinePatterns on SkillsBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SkillsBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SkillsBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SkillsBaseline value)  $default,){
final _that = this;
switch (_that) {
case _SkillsBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SkillsBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _SkillsBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( SkillsHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SkillsBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( SkillsHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _SkillsBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( SkillsHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _SkillsBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _SkillsBaseline implements SkillsBaseline {
  const _SkillsBaseline({required this.header, required this.collection});


@override final  SkillsHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SkillsBaselineCopyWith<_SkillsBaseline> get copyWith => __$SkillsBaselineCopyWithImpl<_SkillsBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SkillsBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'SkillsBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$SkillsBaselineCopyWith<$Res> implements $SkillsBaselineCopyWith<$Res> {
  factory _$SkillsBaselineCopyWith(_SkillsBaseline value, $Res Function(_SkillsBaseline) _then) = __$SkillsBaselineCopyWithImpl;
@override @useResult
$Res call({
 SkillsHeader header, ProductCollectionRef? collection
});


@override $SkillsHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$SkillsBaselineCopyWithImpl<$Res>
    implements _$SkillsBaselineCopyWith<$Res> {
  __$SkillsBaselineCopyWithImpl(this._self, this._then);

  final _SkillsBaseline _self;
  final $Res Function(_SkillsBaseline) _then;

/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_SkillsBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as SkillsHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of SkillsBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsHeaderCopyWith<$Res> get header {

  return $SkillsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of SkillsBaseline
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
mixin _$SkillsChange {


/// Create a copy of SkillsChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsChangeCopyWith<SkillsChange> get copyWith => _$SkillsChangeCopyWithImpl<SkillsChange>(this as SkillsChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as SkillsChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $SkillsChangeCopyWith<$Res>  {
  factory $SkillsChangeCopyWith(SkillsChange value, $Res Function(SkillsChange) _then) = _$SkillsChangeCopyWithImpl;
@useResult
$Res call({
 SkillsHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$SkillsHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$SkillsChangeCopyWithImpl<$Res>
    implements $SkillsChangeCopyWith<$Res> {
  _$SkillsChangeCopyWithImpl(this._self, this._then);

  final SkillsChange _self;
  final $Res Function(SkillsChange) _then;

/// Create a copy of SkillsChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(SkillsChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as SkillsHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of SkillsChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsHeaderCopyWith<$Res> get header {

  return $SkillsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of SkillsChange
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


/// Adds pattern-matching-related methods to [SkillsChange].
extension SkillsChangePatterns on SkillsChange {
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
mixin _$SkillsEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsEventCopyWith<SkillsEvent> get copyWith => _$SkillsEventCopyWithImpl<SkillsEvent>(this as SkillsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SkillsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as SkillsEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as SkillsEvent;
  return 'SkillsEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $SkillsEventCopyWith<$Res>  {
  factory $SkillsEventCopyWith(SkillsEvent value, $Res Function(SkillsEvent) _then) = _$SkillsEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$SkillsEventCopyWithImpl<$Res>
    implements $SkillsEventCopyWith<$Res> {
  _$SkillsEventCopyWithImpl(this._self, this._then);

  final SkillsEvent _self;
  final $Res Function(SkillsEvent) _then;

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [SkillsEvent].
extension SkillsEventPatterns on SkillsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SkillsBaselineEvent value)?  baseline,TResult Function( SkillsChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SkillsBaselineEvent() when baseline != null:
return baseline(_that);case SkillsChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SkillsBaselineEvent value)  baseline,required TResult Function( SkillsChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case SkillsBaselineEvent():
return baseline(_that);case SkillsChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SkillsBaselineEvent value)?  baseline,TResult? Function( SkillsChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case SkillsBaselineEvent() when baseline != null:
return baseline(_that);case SkillsChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SkillsBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  SkillsChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SkillsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case SkillsChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SkillsBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  SkillsChange value)  change,}) {final _that = this;
switch (_that) {
case SkillsBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case SkillsChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SkillsBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  SkillsChange value)?  change,}) {final _that = this;
switch (_that) {
case SkillsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case SkillsChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class SkillsBaselineEvent implements SkillsEvent {
  const SkillsBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  SkillsBaseline value;

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsBaselineEventCopyWith<SkillsBaselineEvent> get copyWith => _$SkillsBaselineEventCopyWithImpl<SkillsBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'SkillsEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $SkillsBaselineEventCopyWith<$Res> implements $SkillsEventCopyWith<$Res> {
  factory $SkillsBaselineEventCopyWith(SkillsBaselineEvent value, $Res Function(SkillsBaselineEvent) _then) = _$SkillsBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, SkillsBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$SkillsBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$SkillsBaselineEventCopyWithImpl<$Res>
    implements $SkillsBaselineEventCopyWith<$Res> {
  _$SkillsBaselineEventCopyWithImpl(this._self, this._then);

  final SkillsBaselineEvent _self;
  final $Res Function(SkillsBaselineEvent) _then;

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(SkillsBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SkillsBaseline,
  ));
}

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsBaselineCopyWith<$Res> get value {

  return $SkillsBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class SkillsChangeEvent implements SkillsEvent {
  const SkillsChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  SkillsChange value;

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsChangeEventCopyWith<SkillsChangeEvent> get copyWith => _$SkillsChangeEventCopyWithImpl<SkillsChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'SkillsEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $SkillsChangeEventCopyWith<$Res> implements $SkillsEventCopyWith<$Res> {
  factory $SkillsChangeEventCopyWith(SkillsChangeEvent value, $Res Function(SkillsChangeEvent) _then) = _$SkillsChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, SkillsChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$SkillsChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$SkillsChangeEventCopyWithImpl<$Res>
    implements $SkillsChangeEventCopyWith<$Res> {
  _$SkillsChangeEventCopyWithImpl(this._self, this._then);

  final SkillsChangeEvent _self;
  final $Res Function(SkillsChangeEvent) _then;

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(SkillsChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SkillsChange,
  ));
}

/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of SkillsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsChangeCopyWith<$Res> get value {

  return $SkillsChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$SkillsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SkillsFrameCopyWith<$Res>  {
$SkillsFrameCopyWith(SkillsFrame _, $Res Function(SkillsFrame) __);
}


/// Adds pattern-matching-related methods to [SkillsFrame].
extension SkillsFramePatterns on SkillsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SkillsData value)?  data,TResult Function( SkillsResyncRequired value)?  resyncRequired,TResult Function( SkillsFeedFailure value)?  failure,TResult Function( SkillsClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SkillsData() when data != null:
return data(_that);case SkillsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case SkillsFeedFailure() when failure != null:
return failure(_that);case SkillsClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SkillsData value)  data,required TResult Function( SkillsResyncRequired value)  resyncRequired,required TResult Function( SkillsFeedFailure value)  failure,required TResult Function( SkillsClosed value)  closed,}){
final _that = this;
switch (_that) {
case SkillsData():
return data(_that);case SkillsResyncRequired():
return resyncRequired(_that);case SkillsFeedFailure():
return failure(_that);case SkillsClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SkillsData value)?  data,TResult? Function( SkillsResyncRequired value)?  resyncRequired,TResult? Function( SkillsFeedFailure value)?  failure,TResult? Function( SkillsClosed value)?  closed,}){
final _that = this;
switch (_that) {
case SkillsData() when data != null:
return data(_that);case SkillsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case SkillsFeedFailure() when failure != null:
return failure(_that);case SkillsClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  SkillsEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SkillsData() when data != null:
return data(_that.deliverySequence,_that.event);case SkillsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case SkillsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case SkillsClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  SkillsEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case SkillsData():
return data(_that.deliverySequence,_that.event);case SkillsResyncRequired():
return resyncRequired(_that.identity,_that.reason);case SkillsFeedFailure():
return failure(_that.identity,_that.error);case SkillsClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  SkillsEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case SkillsData() when data != null:
return data(_that.deliverySequence,_that.event);case SkillsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case SkillsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case SkillsClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class SkillsData implements SkillsFrame {
  const SkillsData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  SkillsEvent event;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsDataCopyWith<SkillsData> get copyWith => _$SkillsDataCopyWithImpl<SkillsData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $SkillsDataCopyWith<$Res> implements $SkillsFrameCopyWith<$Res> {
  factory $SkillsDataCopyWith(SkillsData value, $Res Function(SkillsData) _then) = _$SkillsDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, SkillsEvent event
});


$SkillsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$SkillsDataCopyWithImpl<$Res>
    implements $SkillsDataCopyWith<$Res> {
  _$SkillsDataCopyWithImpl(this._self, this._then);

  final SkillsData _self;
  final $Res Function(SkillsData) _then;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(SkillsData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as SkillsEvent,
  ));
}

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SkillsEventCopyWith<$Res> get event {

  return $SkillsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class SkillsResyncRequired implements SkillsFrame {
  const SkillsResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsResyncRequiredCopyWith<SkillsResyncRequired> get copyWith => _$SkillsResyncRequiredCopyWithImpl<SkillsResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $SkillsResyncRequiredCopyWith<$Res> implements $SkillsFrameCopyWith<$Res> {
  factory $SkillsResyncRequiredCopyWith(SkillsResyncRequired value, $Res Function(SkillsResyncRequired) _then) = _$SkillsResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$SkillsResyncRequiredCopyWithImpl<$Res>
    implements $SkillsResyncRequiredCopyWith<$Res> {
  _$SkillsResyncRequiredCopyWithImpl(this._self, this._then);

  final SkillsResyncRequired _self;
  final $Res Function(SkillsResyncRequired) _then;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(SkillsResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of SkillsFrame
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


class SkillsFeedFailure implements SkillsFrame {
  const SkillsFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsFeedFailureCopyWith<SkillsFeedFailure> get copyWith => _$SkillsFeedFailureCopyWithImpl<SkillsFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $SkillsFeedFailureCopyWith<$Res> implements $SkillsFrameCopyWith<$Res> {
  factory $SkillsFeedFailureCopyWith(SkillsFeedFailure value, $Res Function(SkillsFeedFailure) _then) = _$SkillsFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$SkillsFeedFailureCopyWithImpl<$Res>
    implements $SkillsFeedFailureCopyWith<$Res> {
  _$SkillsFeedFailureCopyWithImpl(this._self, this._then);

  final SkillsFeedFailure _self;
  final $Res Function(SkillsFeedFailure) _then;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(SkillsFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of SkillsFrame
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


class SkillsClosed implements SkillsFrame {
  const SkillsClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SkillsClosedCopyWith<SkillsClosed> get copyWith => _$SkillsClosedCopyWithImpl<SkillsClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SkillsClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $SkillsClosedCopyWith<$Res> implements $SkillsFrameCopyWith<$Res> {
  factory $SkillsClosedCopyWith(SkillsClosed value, $Res Function(SkillsClosed) _then) = _$SkillsClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$SkillsClosedCopyWithImpl<$Res>
    implements $SkillsClosedCopyWith<$Res> {
  _$SkillsClosedCopyWithImpl(this._self, this._then);

  final SkillsClosed _self;
  final $Res Function(SkillsClosed) _then;

/// Create a copy of SkillsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(SkillsClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of SkillsFrame
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
