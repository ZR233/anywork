// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_directory_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadDirectoryBaseline {

 ThreadDirectoryHeader get header; ProductCollectionRef? get collection;
/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryBaselineCopyWith<ThreadDirectoryBaseline> get copyWith => _$ThreadDirectoryBaselineCopyWithImpl<ThreadDirectoryBaseline>(this as ThreadDirectoryBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as ThreadDirectoryBaseline;
  return 'ThreadDirectoryBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryBaselineCopyWith<$Res>  {
  factory $ThreadDirectoryBaselineCopyWith(ThreadDirectoryBaseline value, $Res Function(ThreadDirectoryBaseline) _then) = _$ThreadDirectoryBaselineCopyWithImpl;
@useResult
$Res call({
 ThreadDirectoryHeader header, ProductCollectionRef? collection
});


$ThreadDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ThreadDirectoryBaselineCopyWithImpl<$Res>
    implements $ThreadDirectoryBaselineCopyWith<$Res> {
  _$ThreadDirectoryBaselineCopyWithImpl(this._self, this._then);

  final ThreadDirectoryBaseline _self;
  final $Res Function(ThreadDirectoryBaseline) _then;

/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(ThreadDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryHeaderCopyWith<$Res> get header {

  return $ThreadDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ThreadDirectoryBaseline
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


/// Adds pattern-matching-related methods to [ThreadDirectoryBaseline].
extension ThreadDirectoryBaselinePatterns on ThreadDirectoryBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadDirectoryBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadDirectoryBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadDirectoryBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadDirectoryHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadDirectoryHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadDirectoryHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _ThreadDirectoryBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadDirectoryBaseline implements ThreadDirectoryBaseline {
  const _ThreadDirectoryBaseline({required this.header, required this.collection});


@override final  ThreadDirectoryHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadDirectoryBaselineCopyWith<_ThreadDirectoryBaseline> get copyWith => __$ThreadDirectoryBaselineCopyWithImpl<_ThreadDirectoryBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadDirectoryBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'ThreadDirectoryBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$ThreadDirectoryBaselineCopyWith<$Res> implements $ThreadDirectoryBaselineCopyWith<$Res> {
  factory _$ThreadDirectoryBaselineCopyWith(_ThreadDirectoryBaseline value, $Res Function(_ThreadDirectoryBaseline) _then) = __$ThreadDirectoryBaselineCopyWithImpl;
@override @useResult
$Res call({
 ThreadDirectoryHeader header, ProductCollectionRef? collection
});


@override $ThreadDirectoryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ThreadDirectoryBaselineCopyWithImpl<$Res>
    implements _$ThreadDirectoryBaselineCopyWith<$Res> {
  __$ThreadDirectoryBaselineCopyWithImpl(this._self, this._then);

  final _ThreadDirectoryBaseline _self;
  final $Res Function(_ThreadDirectoryBaseline) _then;

/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_ThreadDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of ThreadDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryHeaderCopyWith<$Res> get header {

  return $ThreadDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ThreadDirectoryBaseline
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
mixin _$ThreadDirectoryChange {


/// Create a copy of ThreadDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryChangeCopyWith<ThreadDirectoryChange> get copyWith => _$ThreadDirectoryChangeCopyWithImpl<ThreadDirectoryChange>(this as ThreadDirectoryChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryChangeCopyWith<$Res>  {
  factory $ThreadDirectoryChangeCopyWith(ThreadDirectoryChange value, $Res Function(ThreadDirectoryChange) _then) = _$ThreadDirectoryChangeCopyWithImpl;
@useResult
$Res call({
 ThreadDirectoryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$ThreadDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ThreadDirectoryChangeCopyWithImpl<$Res>
    implements $ThreadDirectoryChangeCopyWith<$Res> {
  _$ThreadDirectoryChangeCopyWithImpl(this._self, this._then);

  final ThreadDirectoryChange _self;
  final $Res Function(ThreadDirectoryChange) _then;

/// Create a copy of ThreadDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(ThreadDirectoryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of ThreadDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryHeaderCopyWith<$Res> get header {

  return $ThreadDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ThreadDirectoryChange
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


/// Adds pattern-matching-related methods to [ThreadDirectoryChange].
extension ThreadDirectoryChangePatterns on ThreadDirectoryChange {
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
mixin _$ThreadDirectoryEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryEventCopyWith<ThreadDirectoryEvent> get copyWith => _$ThreadDirectoryEventCopyWithImpl<ThreadDirectoryEvent>(this as ThreadDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as ThreadDirectoryEvent;
  return 'ThreadDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryEventCopyWith<$Res>  {
  factory $ThreadDirectoryEventCopyWith(ThreadDirectoryEvent value, $Res Function(ThreadDirectoryEvent) _then) = _$ThreadDirectoryEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ThreadDirectoryEventCopyWithImpl<$Res>
    implements $ThreadDirectoryEventCopyWith<$Res> {
  _$ThreadDirectoryEventCopyWithImpl(this._self, this._then);

  final ThreadDirectoryEvent _self;
  final $Res Function(ThreadDirectoryEvent) _then;

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadDirectoryEvent].
extension ThreadDirectoryEventPatterns on ThreadDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadDirectoryBaselineEvent value)?  baseline,TResult Function( ThreadDirectoryChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case ThreadDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadDirectoryBaselineEvent value)  baseline,required TResult Function( ThreadDirectoryChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent():
return baseline(_that);case ThreadDirectoryChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadDirectoryBaselineEvent value)?  baseline,TResult? Function( ThreadDirectoryChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case ThreadDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ThreadDirectoryBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ThreadDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ThreadDirectoryBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ThreadDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadDirectoryChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ThreadDirectoryBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  ThreadDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case ThreadDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadDirectoryChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadDirectoryBaselineEvent implements ThreadDirectoryEvent {
  const ThreadDirectoryBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  ThreadDirectoryBaseline value;

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryBaselineEventCopyWith<ThreadDirectoryBaselineEvent> get copyWith => _$ThreadDirectoryBaselineEventCopyWithImpl<ThreadDirectoryBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'ThreadDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryBaselineEventCopyWith<$Res> implements $ThreadDirectoryEventCopyWith<$Res> {
  factory $ThreadDirectoryBaselineEventCopyWith(ThreadDirectoryBaselineEvent value, $Res Function(ThreadDirectoryBaselineEvent) _then) = _$ThreadDirectoryBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, ThreadDirectoryBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$ThreadDirectoryBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadDirectoryBaselineEventCopyWithImpl<$Res>
    implements $ThreadDirectoryBaselineEventCopyWith<$Res> {
  _$ThreadDirectoryBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadDirectoryBaselineEvent _self;
  final $Res Function(ThreadDirectoryBaselineEvent) _then;

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadDirectoryBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryBaseline,
  ));
}

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryBaselineCopyWith<$Res> get value {

  return $ThreadDirectoryBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadDirectoryChangeEvent implements ThreadDirectoryEvent {
  const ThreadDirectoryChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  ThreadDirectoryChange value;

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryChangeEventCopyWith<ThreadDirectoryChangeEvent> get copyWith => _$ThreadDirectoryChangeEventCopyWithImpl<ThreadDirectoryChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'ThreadDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $ThreadDirectoryChangeEventCopyWith<$Res> implements $ThreadDirectoryEventCopyWith<$Res> {
  factory $ThreadDirectoryChangeEventCopyWith(ThreadDirectoryChangeEvent value, $Res Function(ThreadDirectoryChangeEvent) _then) = _$ThreadDirectoryChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, ThreadDirectoryChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$ThreadDirectoryChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadDirectoryChangeEventCopyWithImpl<$Res>
    implements $ThreadDirectoryChangeEventCopyWith<$Res> {
  _$ThreadDirectoryChangeEventCopyWithImpl(this._self, this._then);

  final ThreadDirectoryChangeEvent _self;
  final $Res Function(ThreadDirectoryChangeEvent) _then;

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ThreadDirectoryChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryChange,
  ));
}

/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryChangeCopyWith<$Res> get value {

  return $ThreadDirectoryChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadDirectoryFrameCopyWith<$Res>  {
$ThreadDirectoryFrameCopyWith(ThreadDirectoryFrame _, $Res Function(ThreadDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadDirectoryFrame].
extension ThreadDirectoryFramePatterns on ThreadDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadDirectoryData value)?  data,TResult Function( ThreadDirectoryResyncRequired value)?  resyncRequired,TResult Function( ThreadDirectoryFeedFailure value)?  failure,TResult Function( ThreadDirectoryClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadDirectoryData() when data != null:
return data(_that);case ThreadDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadDirectoryFeedFailure() when failure != null:
return failure(_that);case ThreadDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadDirectoryData value)  data,required TResult Function( ThreadDirectoryResyncRequired value)  resyncRequired,required TResult Function( ThreadDirectoryFeedFailure value)  failure,required TResult Function( ThreadDirectoryClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadDirectoryData():
return data(_that);case ThreadDirectoryResyncRequired():
return resyncRequired(_that);case ThreadDirectoryFeedFailure():
return failure(_that);case ThreadDirectoryClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadDirectoryData value)?  data,TResult? Function( ThreadDirectoryResyncRequired value)?  resyncRequired,TResult? Function( ThreadDirectoryFeedFailure value)?  failure,TResult? Function( ThreadDirectoryClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadDirectoryData() when data != null:
return data(_that);case ThreadDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadDirectoryFeedFailure() when failure != null:
return failure(_that);case ThreadDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadDirectoryEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadDirectoryEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadDirectoryData():
return data(_that.deliverySequence,_that.event);case ThreadDirectoryResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadDirectoryFeedFailure():
return failure(_that.identity,_that.error);case ThreadDirectoryClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadDirectoryEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadDirectoryClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadDirectoryData implements ThreadDirectoryFrame {
  const ThreadDirectoryData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadDirectoryEvent event;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryDataCopyWith<ThreadDirectoryData> get copyWith => _$ThreadDirectoryDataCopyWithImpl<ThreadDirectoryData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryDataCopyWith<$Res> implements $ThreadDirectoryFrameCopyWith<$Res> {
  factory $ThreadDirectoryDataCopyWith(ThreadDirectoryData value, $Res Function(ThreadDirectoryData) _then) = _$ThreadDirectoryDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadDirectoryEvent event
});


$ThreadDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadDirectoryDataCopyWithImpl<$Res>
    implements $ThreadDirectoryDataCopyWith<$Res> {
  _$ThreadDirectoryDataCopyWithImpl(this._self, this._then);

  final ThreadDirectoryData _self;
  final $Res Function(ThreadDirectoryData) _then;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadDirectoryData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadDirectoryEvent,
  ));
}

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadDirectoryEventCopyWith<$Res> get event {

  return $ThreadDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadDirectoryResyncRequired implements ThreadDirectoryFrame {
  const ThreadDirectoryResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryResyncRequiredCopyWith<ThreadDirectoryResyncRequired> get copyWith => _$ThreadDirectoryResyncRequiredCopyWithImpl<ThreadDirectoryResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryResyncRequiredCopyWith<$Res> implements $ThreadDirectoryFrameCopyWith<$Res> {
  factory $ThreadDirectoryResyncRequiredCopyWith(ThreadDirectoryResyncRequired value, $Res Function(ThreadDirectoryResyncRequired) _then) = _$ThreadDirectoryResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadDirectoryResyncRequiredCopyWithImpl<$Res>
    implements $ThreadDirectoryResyncRequiredCopyWith<$Res> {
  _$ThreadDirectoryResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadDirectoryResyncRequired _self;
  final $Res Function(ThreadDirectoryResyncRequired) _then;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadDirectoryResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of ThreadDirectoryFrame
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


class ThreadDirectoryFeedFailure implements ThreadDirectoryFrame {
  const ThreadDirectoryFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryFeedFailureCopyWith<ThreadDirectoryFeedFailure> get copyWith => _$ThreadDirectoryFeedFailureCopyWithImpl<ThreadDirectoryFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryFeedFailureCopyWith<$Res> implements $ThreadDirectoryFrameCopyWith<$Res> {
  factory $ThreadDirectoryFeedFailureCopyWith(ThreadDirectoryFeedFailure value, $Res Function(ThreadDirectoryFeedFailure) _then) = _$ThreadDirectoryFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadDirectoryFeedFailureCopyWithImpl<$Res>
    implements $ThreadDirectoryFeedFailureCopyWith<$Res> {
  _$ThreadDirectoryFeedFailureCopyWithImpl(this._self, this._then);

  final ThreadDirectoryFeedFailure _self;
  final $Res Function(ThreadDirectoryFeedFailure) _then;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadDirectoryFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadDirectoryFrame
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


class ThreadDirectoryClosed implements ThreadDirectoryFrame {
  const ThreadDirectoryClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadDirectoryClosedCopyWith<ThreadDirectoryClosed> get copyWith => _$ThreadDirectoryClosedCopyWithImpl<ThreadDirectoryClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadDirectoryClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadDirectoryClosedCopyWith<$Res> implements $ThreadDirectoryFrameCopyWith<$Res> {
  factory $ThreadDirectoryClosedCopyWith(ThreadDirectoryClosed value, $Res Function(ThreadDirectoryClosed) _then) = _$ThreadDirectoryClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadDirectoryClosedCopyWithImpl<$Res>
    implements $ThreadDirectoryClosedCopyWith<$Res> {
  _$ThreadDirectoryClosedCopyWithImpl(this._self, this._then);

  final ThreadDirectoryClosed _self;
  final $Res Function(ThreadDirectoryClosed) _then;

/// Create a copy of ThreadDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadDirectoryClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of ThreadDirectoryFrame
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
