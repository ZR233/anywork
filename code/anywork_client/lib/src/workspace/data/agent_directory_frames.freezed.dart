// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'agent_directory_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AgentDirectoryBaseline {

 AgentDirectoryHeader get header; ProductCollectionRef? get collection;
/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryBaselineCopyWith<AgentDirectoryBaseline> get copyWith => _$AgentDirectoryBaselineCopyWithImpl<AgentDirectoryBaseline>(this as AgentDirectoryBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as AgentDirectoryBaseline;
  return 'AgentDirectoryBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryBaselineCopyWith<$Res>  {
  factory $AgentDirectoryBaselineCopyWith(AgentDirectoryBaseline value, $Res Function(AgentDirectoryBaseline) _then) = _$AgentDirectoryBaselineCopyWithImpl;
@useResult
$Res call({
 AgentDirectoryHeader header, ProductCollectionRef? collection
});


$AgentDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AgentDirectoryBaselineCopyWithImpl<$Res>
    implements $AgentDirectoryBaselineCopyWith<$Res> {
  _$AgentDirectoryBaselineCopyWithImpl(this._self, this._then);

  final AgentDirectoryBaseline _self;
  final $Res Function(AgentDirectoryBaseline) _then;

/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(AgentDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryHeaderCopyWith<$Res> get header {

  return $AgentDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentDirectoryBaseline
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


/// Adds pattern-matching-related methods to [AgentDirectoryBaseline].
extension AgentDirectoryBaselinePatterns on AgentDirectoryBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _AgentDirectoryBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _AgentDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _AgentDirectoryBaseline value)  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _AgentDirectoryBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _AgentDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( AgentDirectoryHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _AgentDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( AgentDirectoryHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( AgentDirectoryHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _AgentDirectoryBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _AgentDirectoryBaseline implements AgentDirectoryBaseline {
  const _AgentDirectoryBaseline({required this.header, required this.collection});


@override final  AgentDirectoryHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$AgentDirectoryBaselineCopyWith<_AgentDirectoryBaseline> get copyWith => __$AgentDirectoryBaselineCopyWithImpl<_AgentDirectoryBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _AgentDirectoryBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'AgentDirectoryBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$AgentDirectoryBaselineCopyWith<$Res> implements $AgentDirectoryBaselineCopyWith<$Res> {
  factory _$AgentDirectoryBaselineCopyWith(_AgentDirectoryBaseline value, $Res Function(_AgentDirectoryBaseline) _then) = __$AgentDirectoryBaselineCopyWithImpl;
@override @useResult
$Res call({
 AgentDirectoryHeader header, ProductCollectionRef? collection
});


@override $AgentDirectoryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$AgentDirectoryBaselineCopyWithImpl<$Res>
    implements _$AgentDirectoryBaselineCopyWith<$Res> {
  __$AgentDirectoryBaselineCopyWithImpl(this._self, this._then);

  final _AgentDirectoryBaseline _self;
  final $Res Function(_AgentDirectoryBaseline) _then;

/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_AgentDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of AgentDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryHeaderCopyWith<$Res> get header {

  return $AgentDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentDirectoryBaseline
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
mixin _$AgentDirectoryChange {


/// Create a copy of AgentDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryChangeCopyWith<AgentDirectoryChange> get copyWith => _$AgentDirectoryChangeCopyWithImpl<AgentDirectoryChange>(this as AgentDirectoryChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $AgentDirectoryChangeCopyWith<$Res>  {
  factory $AgentDirectoryChangeCopyWith(AgentDirectoryChange value, $Res Function(AgentDirectoryChange) _then) = _$AgentDirectoryChangeCopyWithImpl;
@useResult
$Res call({
 AgentDirectoryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$AgentDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$AgentDirectoryChangeCopyWithImpl<$Res>
    implements $AgentDirectoryChangeCopyWith<$Res> {
  _$AgentDirectoryChangeCopyWithImpl(this._self, this._then);

  final AgentDirectoryChange _self;
  final $Res Function(AgentDirectoryChange) _then;

/// Create a copy of AgentDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(AgentDirectoryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as AgentDirectoryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of AgentDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryHeaderCopyWith<$Res> get header {

  return $AgentDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of AgentDirectoryChange
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


/// Adds pattern-matching-related methods to [AgentDirectoryChange].
extension AgentDirectoryChangePatterns on AgentDirectoryChange {
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
mixin _$AgentDirectoryEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryEventCopyWith<AgentDirectoryEvent> get copyWith => _$AgentDirectoryEventCopyWithImpl<AgentDirectoryEvent>(this as AgentDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AgentDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as AgentDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as AgentDirectoryEvent;
  return 'AgentDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryEventCopyWith<$Res>  {
  factory $AgentDirectoryEventCopyWith(AgentDirectoryEvent value, $Res Function(AgentDirectoryEvent) _then) = _$AgentDirectoryEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$AgentDirectoryEventCopyWithImpl<$Res>
    implements $AgentDirectoryEventCopyWith<$Res> {
  _$AgentDirectoryEventCopyWithImpl(this._self, this._then);

  final AgentDirectoryEvent _self;
  final $Res Function(AgentDirectoryEvent) _then;

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [AgentDirectoryEvent].
extension AgentDirectoryEventPatterns on AgentDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentDirectoryBaselineEvent value)?  baseline,TResult Function( AgentDirectoryChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case AgentDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentDirectoryBaselineEvent value)  baseline,required TResult Function( AgentDirectoryChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent():
return baseline(_that);case AgentDirectoryChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentDirectoryBaselineEvent value)?  baseline,TResult? Function( AgentDirectoryChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case AgentDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentDirectoryBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AgentDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AgentDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentDirectoryBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AgentDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case AgentDirectoryChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AgentDirectoryBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AgentDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case AgentDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case AgentDirectoryChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class AgentDirectoryBaselineEvent implements AgentDirectoryEvent {
  const AgentDirectoryBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AgentDirectoryBaseline value;

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryBaselineEventCopyWith<AgentDirectoryBaselineEvent> get copyWith => _$AgentDirectoryBaselineEventCopyWithImpl<AgentDirectoryBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'AgentDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryBaselineEventCopyWith<$Res> implements $AgentDirectoryEventCopyWith<$Res> {
  factory $AgentDirectoryBaselineEventCopyWith(AgentDirectoryBaselineEvent value, $Res Function(AgentDirectoryBaselineEvent) _then) = _$AgentDirectoryBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AgentDirectoryBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$AgentDirectoryBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$AgentDirectoryBaselineEventCopyWithImpl<$Res>
    implements $AgentDirectoryBaselineEventCopyWith<$Res> {
  _$AgentDirectoryBaselineEventCopyWithImpl(this._self, this._then);

  final AgentDirectoryBaselineEvent _self;
  final $Res Function(AgentDirectoryBaselineEvent) _then;

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(AgentDirectoryBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentDirectoryBaseline,
  ));
}

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryBaselineCopyWith<$Res> get value {

  return $AgentDirectoryBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class AgentDirectoryChangeEvent implements AgentDirectoryEvent {
  const AgentDirectoryChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  AgentDirectoryChange value;

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryChangeEventCopyWith<AgentDirectoryChangeEvent> get copyWith => _$AgentDirectoryChangeEventCopyWithImpl<AgentDirectoryChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'AgentDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $AgentDirectoryChangeEventCopyWith<$Res> implements $AgentDirectoryEventCopyWith<$Res> {
  factory $AgentDirectoryChangeEventCopyWith(AgentDirectoryChangeEvent value, $Res Function(AgentDirectoryChangeEvent) _then) = _$AgentDirectoryChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AgentDirectoryChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$AgentDirectoryChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$AgentDirectoryChangeEventCopyWithImpl<$Res>
    implements $AgentDirectoryChangeEventCopyWith<$Res> {
  _$AgentDirectoryChangeEventCopyWithImpl(this._self, this._then);

  final AgentDirectoryChangeEvent _self;
  final $Res Function(AgentDirectoryChangeEvent) _then;

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(AgentDirectoryChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as AgentDirectoryChange,
  ));
}

/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AgentDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryChangeCopyWith<$Res> get value {

  return $AgentDirectoryChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$AgentDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AgentDirectoryFrameCopyWith<$Res>  {
$AgentDirectoryFrameCopyWith(AgentDirectoryFrame _, $Res Function(AgentDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [AgentDirectoryFrame].
extension AgentDirectoryFramePatterns on AgentDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AgentDirectoryData value)?  data,TResult Function( AgentDirectoryResyncRequired value)?  resyncRequired,TResult Function( AgentDirectoryFeedFailure value)?  failure,TResult Function( AgentDirectoryClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AgentDirectoryData() when data != null:
return data(_that);case AgentDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AgentDirectoryFeedFailure() when failure != null:
return failure(_that);case AgentDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AgentDirectoryData value)  data,required TResult Function( AgentDirectoryResyncRequired value)  resyncRequired,required TResult Function( AgentDirectoryFeedFailure value)  failure,required TResult Function( AgentDirectoryClosed value)  closed,}){
final _that = this;
switch (_that) {
case AgentDirectoryData():
return data(_that);case AgentDirectoryResyncRequired():
return resyncRequired(_that);case AgentDirectoryFeedFailure():
return failure(_that);case AgentDirectoryClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AgentDirectoryData value)?  data,TResult? Function( AgentDirectoryResyncRequired value)?  resyncRequired,TResult? Function( AgentDirectoryFeedFailure value)?  failure,TResult? Function( AgentDirectoryClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AgentDirectoryData() when data != null:
return data(_that);case AgentDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AgentDirectoryFeedFailure() when failure != null:
return failure(_that);case AgentDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AgentDirectoryEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AgentDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case AgentDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AgentDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AgentDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AgentDirectoryEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AgentDirectoryData():
return data(_that.deliverySequence,_that.event);case AgentDirectoryResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AgentDirectoryFeedFailure():
return failure(_that.identity,_that.error);case AgentDirectoryClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AgentDirectoryEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AgentDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case AgentDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AgentDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AgentDirectoryClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AgentDirectoryData implements AgentDirectoryFrame {
  const AgentDirectoryData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AgentDirectoryEvent event;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryDataCopyWith<AgentDirectoryData> get copyWith => _$AgentDirectoryDataCopyWithImpl<AgentDirectoryData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryDataCopyWith<$Res> implements $AgentDirectoryFrameCopyWith<$Res> {
  factory $AgentDirectoryDataCopyWith(AgentDirectoryData value, $Res Function(AgentDirectoryData) _then) = _$AgentDirectoryDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AgentDirectoryEvent event
});


$AgentDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AgentDirectoryDataCopyWithImpl<$Res>
    implements $AgentDirectoryDataCopyWith<$Res> {
  _$AgentDirectoryDataCopyWithImpl(this._self, this._then);

  final AgentDirectoryData _self;
  final $Res Function(AgentDirectoryData) _then;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AgentDirectoryData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AgentDirectoryEvent,
  ));
}

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AgentDirectoryEventCopyWith<$Res> get event {

  return $AgentDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AgentDirectoryResyncRequired implements AgentDirectoryFrame {
  const AgentDirectoryResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryResyncRequiredCopyWith<AgentDirectoryResyncRequired> get copyWith => _$AgentDirectoryResyncRequiredCopyWithImpl<AgentDirectoryResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryResyncRequiredCopyWith<$Res> implements $AgentDirectoryFrameCopyWith<$Res> {
  factory $AgentDirectoryResyncRequiredCopyWith(AgentDirectoryResyncRequired value, $Res Function(AgentDirectoryResyncRequired) _then) = _$AgentDirectoryResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AgentDirectoryResyncRequiredCopyWithImpl<$Res>
    implements $AgentDirectoryResyncRequiredCopyWith<$Res> {
  _$AgentDirectoryResyncRequiredCopyWithImpl(this._self, this._then);

  final AgentDirectoryResyncRequired _self;
  final $Res Function(AgentDirectoryResyncRequired) _then;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AgentDirectoryResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AgentDirectoryFrame
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


class AgentDirectoryFeedFailure implements AgentDirectoryFrame {
  const AgentDirectoryFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryFeedFailureCopyWith<AgentDirectoryFeedFailure> get copyWith => _$AgentDirectoryFeedFailureCopyWithImpl<AgentDirectoryFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryFeedFailureCopyWith<$Res> implements $AgentDirectoryFrameCopyWith<$Res> {
  factory $AgentDirectoryFeedFailureCopyWith(AgentDirectoryFeedFailure value, $Res Function(AgentDirectoryFeedFailure) _then) = _$AgentDirectoryFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AgentDirectoryFeedFailureCopyWithImpl<$Res>
    implements $AgentDirectoryFeedFailureCopyWith<$Res> {
  _$AgentDirectoryFeedFailureCopyWithImpl(this._self, this._then);

  final AgentDirectoryFeedFailure _self;
  final $Res Function(AgentDirectoryFeedFailure) _then;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AgentDirectoryFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AgentDirectoryFrame
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


class AgentDirectoryClosed implements AgentDirectoryFrame {
  const AgentDirectoryClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AgentDirectoryClosedCopyWith<AgentDirectoryClosed> get copyWith => _$AgentDirectoryClosedCopyWithImpl<AgentDirectoryClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AgentDirectoryClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AgentDirectoryClosedCopyWith<$Res> implements $AgentDirectoryFrameCopyWith<$Res> {
  factory $AgentDirectoryClosedCopyWith(AgentDirectoryClosed value, $Res Function(AgentDirectoryClosed) _then) = _$AgentDirectoryClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AgentDirectoryClosedCopyWithImpl<$Res>
    implements $AgentDirectoryClosedCopyWith<$Res> {
  _$AgentDirectoryClosedCopyWithImpl(this._self, this._then);

  final AgentDirectoryClosed _self;
  final $Res Function(AgentDirectoryClosed) _then;

/// Create a copy of AgentDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AgentDirectoryClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AgentDirectoryFrame
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
