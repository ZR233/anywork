// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'project_directory_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ProjectDirectoryBaseline {

 ProjectDirectoryHeader get header; ProductCollectionRef? get collection;
/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryBaselineCopyWith<ProjectDirectoryBaseline> get copyWith => _$ProjectDirectoryBaselineCopyWithImpl<ProjectDirectoryBaseline>(this as ProjectDirectoryBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as ProjectDirectoryBaseline;
  return 'ProjectDirectoryBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryBaselineCopyWith<$Res>  {
  factory $ProjectDirectoryBaselineCopyWith(ProjectDirectoryBaseline value, $Res Function(ProjectDirectoryBaseline) _then) = _$ProjectDirectoryBaselineCopyWithImpl;
@useResult
$Res call({
 ProjectDirectoryHeader header, ProductCollectionRef? collection
});


$ProjectDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ProjectDirectoryBaselineCopyWithImpl<$Res>
    implements $ProjectDirectoryBaselineCopyWith<$Res> {
  _$ProjectDirectoryBaselineCopyWithImpl(this._self, this._then);

  final ProjectDirectoryBaseline _self;
  final $Res Function(ProjectDirectoryBaseline) _then;

/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(ProjectDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryHeaderCopyWith<$Res> get header {

  return $ProjectDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ProjectDirectoryBaseline
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


/// Adds pattern-matching-related methods to [ProjectDirectoryBaseline].
extension ProjectDirectoryBaselinePatterns on ProjectDirectoryBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ProjectDirectoryBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ProjectDirectoryBaseline value)  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ProjectDirectoryBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProjectDirectoryHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProjectDirectoryHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProjectDirectoryHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _ProjectDirectoryBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _ProjectDirectoryBaseline implements ProjectDirectoryBaseline {
  const _ProjectDirectoryBaseline({required this.header, required this.collection});


@override final  ProjectDirectoryHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ProjectDirectoryBaselineCopyWith<_ProjectDirectoryBaseline> get copyWith => __$ProjectDirectoryBaselineCopyWithImpl<_ProjectDirectoryBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ProjectDirectoryBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'ProjectDirectoryBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$ProjectDirectoryBaselineCopyWith<$Res> implements $ProjectDirectoryBaselineCopyWith<$Res> {
  factory _$ProjectDirectoryBaselineCopyWith(_ProjectDirectoryBaseline value, $Res Function(_ProjectDirectoryBaseline) _then) = __$ProjectDirectoryBaselineCopyWithImpl;
@override @useResult
$Res call({
 ProjectDirectoryHeader header, ProductCollectionRef? collection
});


@override $ProjectDirectoryHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$ProjectDirectoryBaselineCopyWithImpl<$Res>
    implements _$ProjectDirectoryBaselineCopyWith<$Res> {
  __$ProjectDirectoryBaselineCopyWithImpl(this._self, this._then);

  final _ProjectDirectoryBaseline _self;
  final $Res Function(_ProjectDirectoryBaseline) _then;

/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_ProjectDirectoryBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of ProjectDirectoryBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryHeaderCopyWith<$Res> get header {

  return $ProjectDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ProjectDirectoryBaseline
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
mixin _$ProjectDirectoryChange {


/// Create a copy of ProjectDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryChangeCopyWith<ProjectDirectoryChange> get copyWith => _$ProjectDirectoryChangeCopyWithImpl<ProjectDirectoryChange>(this as ProjectDirectoryChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryChangeCopyWith<$Res>  {
  factory $ProjectDirectoryChangeCopyWith(ProjectDirectoryChange value, $Res Function(ProjectDirectoryChange) _then) = _$ProjectDirectoryChangeCopyWithImpl;
@useResult
$Res call({
 ProjectDirectoryHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$ProjectDirectoryHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$ProjectDirectoryChangeCopyWithImpl<$Res>
    implements $ProjectDirectoryChangeCopyWith<$Res> {
  _$ProjectDirectoryChangeCopyWithImpl(this._self, this._then);

  final ProjectDirectoryChange _self;
  final $Res Function(ProjectDirectoryChange) _then;

/// Create a copy of ProjectDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(ProjectDirectoryChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of ProjectDirectoryChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryHeaderCopyWith<$Res> get header {

  return $ProjectDirectoryHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of ProjectDirectoryChange
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


/// Adds pattern-matching-related methods to [ProjectDirectoryChange].
extension ProjectDirectoryChangePatterns on ProjectDirectoryChange {
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
mixin _$ProjectDirectoryEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryEventCopyWith<ProjectDirectoryEvent> get copyWith => _$ProjectDirectoryEventCopyWithImpl<ProjectDirectoryEvent>(this as ProjectDirectoryEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProjectDirectoryEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ProjectDirectoryEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as ProjectDirectoryEvent;
  return 'ProjectDirectoryEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryEventCopyWith<$Res>  {
  factory $ProjectDirectoryEventCopyWith(ProjectDirectoryEvent value, $Res Function(ProjectDirectoryEvent) _then) = _$ProjectDirectoryEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ProjectDirectoryEventCopyWithImpl<$Res>
    implements $ProjectDirectoryEventCopyWith<$Res> {
  _$ProjectDirectoryEventCopyWithImpl(this._self, this._then);

  final ProjectDirectoryEvent _self;
  final $Res Function(ProjectDirectoryEvent) _then;

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ProjectDirectoryEvent].
extension ProjectDirectoryEventPatterns on ProjectDirectoryEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProjectDirectoryBaselineEvent value)?  baseline,TResult Function( ProjectDirectoryChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case ProjectDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProjectDirectoryBaselineEvent value)  baseline,required TResult Function( ProjectDirectoryChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent():
return baseline(_that);case ProjectDirectoryChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProjectDirectoryBaselineEvent value)?  baseline,TResult? Function( ProjectDirectoryChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent() when baseline != null:
return baseline(_that);case ProjectDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ProjectDirectoryBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ProjectDirectoryChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ProjectDirectoryChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ProjectDirectoryBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  ProjectDirectoryChange value)  change,}) {final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ProjectDirectoryChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  ProjectDirectoryBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  ProjectDirectoryChange value)?  change,}) {final _that = this;
switch (_that) {
case ProjectDirectoryBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ProjectDirectoryChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ProjectDirectoryBaselineEvent implements ProjectDirectoryEvent {
  const ProjectDirectoryBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  ProjectDirectoryBaseline value;

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryBaselineEventCopyWith<ProjectDirectoryBaselineEvent> get copyWith => _$ProjectDirectoryBaselineEventCopyWithImpl<ProjectDirectoryBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'ProjectDirectoryEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryBaselineEventCopyWith<$Res> implements $ProjectDirectoryEventCopyWith<$Res> {
  factory $ProjectDirectoryBaselineEventCopyWith(ProjectDirectoryBaselineEvent value, $Res Function(ProjectDirectoryBaselineEvent) _then) = _$ProjectDirectoryBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, ProjectDirectoryBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$ProjectDirectoryBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ProjectDirectoryBaselineEventCopyWithImpl<$Res>
    implements $ProjectDirectoryBaselineEventCopyWith<$Res> {
  _$ProjectDirectoryBaselineEventCopyWithImpl(this._self, this._then);

  final ProjectDirectoryBaselineEvent _self;
  final $Res Function(ProjectDirectoryBaselineEvent) _then;

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ProjectDirectoryBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryBaseline,
  ));
}

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryBaselineCopyWith<$Res> get value {

  return $ProjectDirectoryBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ProjectDirectoryChangeEvent implements ProjectDirectoryEvent {
  const ProjectDirectoryChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  ProjectDirectoryChange value;

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryChangeEventCopyWith<ProjectDirectoryChangeEvent> get copyWith => _$ProjectDirectoryChangeEventCopyWithImpl<ProjectDirectoryChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'ProjectDirectoryEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $ProjectDirectoryChangeEventCopyWith<$Res> implements $ProjectDirectoryEventCopyWith<$Res> {
  factory $ProjectDirectoryChangeEventCopyWith(ProjectDirectoryChangeEvent value, $Res Function(ProjectDirectoryChangeEvent) _then) = _$ProjectDirectoryChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, ProjectDirectoryChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$ProjectDirectoryChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ProjectDirectoryChangeEventCopyWithImpl<$Res>
    implements $ProjectDirectoryChangeEventCopyWith<$Res> {
  _$ProjectDirectoryChangeEventCopyWithImpl(this._self, this._then);

  final ProjectDirectoryChangeEvent _self;
  final $Res Function(ProjectDirectoryChangeEvent) _then;

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ProjectDirectoryChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryChange,
  ));
}

/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ProjectDirectoryEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryChangeCopyWith<$Res> get value {

  return $ProjectDirectoryChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ProjectDirectoryFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ProjectDirectoryFrameCopyWith<$Res>  {
$ProjectDirectoryFrameCopyWith(ProjectDirectoryFrame _, $Res Function(ProjectDirectoryFrame) __);
}


/// Adds pattern-matching-related methods to [ProjectDirectoryFrame].
extension ProjectDirectoryFramePatterns on ProjectDirectoryFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ProjectDirectoryData value)?  data,TResult Function( ProjectDirectoryResyncRequired value)?  resyncRequired,TResult Function( ProjectDirectoryFeedFailure value)?  failure,TResult Function( ProjectDirectoryClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ProjectDirectoryData() when data != null:
return data(_that);case ProjectDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ProjectDirectoryFeedFailure() when failure != null:
return failure(_that);case ProjectDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ProjectDirectoryData value)  data,required TResult Function( ProjectDirectoryResyncRequired value)  resyncRequired,required TResult Function( ProjectDirectoryFeedFailure value)  failure,required TResult Function( ProjectDirectoryClosed value)  closed,}){
final _that = this;
switch (_that) {
case ProjectDirectoryData():
return data(_that);case ProjectDirectoryResyncRequired():
return resyncRequired(_that);case ProjectDirectoryFeedFailure():
return failure(_that);case ProjectDirectoryClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ProjectDirectoryData value)?  data,TResult? Function( ProjectDirectoryResyncRequired value)?  resyncRequired,TResult? Function( ProjectDirectoryFeedFailure value)?  failure,TResult? Function( ProjectDirectoryClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ProjectDirectoryData() when data != null:
return data(_that);case ProjectDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ProjectDirectoryFeedFailure() when failure != null:
return failure(_that);case ProjectDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ProjectDirectoryEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ProjectDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case ProjectDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ProjectDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ProjectDirectoryClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ProjectDirectoryEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case ProjectDirectoryData():
return data(_that.deliverySequence,_that.event);case ProjectDirectoryResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ProjectDirectoryFeedFailure():
return failure(_that.identity,_that.error);case ProjectDirectoryClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ProjectDirectoryEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ProjectDirectoryData() when data != null:
return data(_that.deliverySequence,_that.event);case ProjectDirectoryResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ProjectDirectoryFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case ProjectDirectoryClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ProjectDirectoryData implements ProjectDirectoryFrame {
  const ProjectDirectoryData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ProjectDirectoryEvent event;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryDataCopyWith<ProjectDirectoryData> get copyWith => _$ProjectDirectoryDataCopyWithImpl<ProjectDirectoryData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryDataCopyWith<$Res> implements $ProjectDirectoryFrameCopyWith<$Res> {
  factory $ProjectDirectoryDataCopyWith(ProjectDirectoryData value, $Res Function(ProjectDirectoryData) _then) = _$ProjectDirectoryDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ProjectDirectoryEvent event
});


$ProjectDirectoryEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ProjectDirectoryDataCopyWithImpl<$Res>
    implements $ProjectDirectoryDataCopyWith<$Res> {
  _$ProjectDirectoryDataCopyWithImpl(this._self, this._then);

  final ProjectDirectoryData _self;
  final $Res Function(ProjectDirectoryData) _then;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ProjectDirectoryData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ProjectDirectoryEvent,
  ));
}

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProjectDirectoryEventCopyWith<$Res> get event {

  return $ProjectDirectoryEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ProjectDirectoryResyncRequired implements ProjectDirectoryFrame {
  const ProjectDirectoryResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryResyncRequiredCopyWith<ProjectDirectoryResyncRequired> get copyWith => _$ProjectDirectoryResyncRequiredCopyWithImpl<ProjectDirectoryResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryResyncRequiredCopyWith<$Res> implements $ProjectDirectoryFrameCopyWith<$Res> {
  factory $ProjectDirectoryResyncRequiredCopyWith(ProjectDirectoryResyncRequired value, $Res Function(ProjectDirectoryResyncRequired) _then) = _$ProjectDirectoryResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ProjectDirectoryResyncRequiredCopyWithImpl<$Res>
    implements $ProjectDirectoryResyncRequiredCopyWith<$Res> {
  _$ProjectDirectoryResyncRequiredCopyWithImpl(this._self, this._then);

  final ProjectDirectoryResyncRequired _self;
  final $Res Function(ProjectDirectoryResyncRequired) _then;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ProjectDirectoryResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of ProjectDirectoryFrame
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


class ProjectDirectoryFeedFailure implements ProjectDirectoryFrame {
  const ProjectDirectoryFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryFeedFailureCopyWith<ProjectDirectoryFeedFailure> get copyWith => _$ProjectDirectoryFeedFailureCopyWithImpl<ProjectDirectoryFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryFeedFailureCopyWith<$Res> implements $ProjectDirectoryFrameCopyWith<$Res> {
  factory $ProjectDirectoryFeedFailureCopyWith(ProjectDirectoryFeedFailure value, $Res Function(ProjectDirectoryFeedFailure) _then) = _$ProjectDirectoryFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ProjectDirectoryFeedFailureCopyWithImpl<$Res>
    implements $ProjectDirectoryFeedFailureCopyWith<$Res> {
  _$ProjectDirectoryFeedFailureCopyWithImpl(this._self, this._then);

  final ProjectDirectoryFeedFailure _self;
  final $Res Function(ProjectDirectoryFeedFailure) _then;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ProjectDirectoryFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ProjectDirectoryFrame
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


class ProjectDirectoryClosed implements ProjectDirectoryFrame {
  const ProjectDirectoryClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProjectDirectoryClosedCopyWith<ProjectDirectoryClosed> get copyWith => _$ProjectDirectoryClosedCopyWithImpl<ProjectDirectoryClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ProjectDirectoryClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ProjectDirectoryClosedCopyWith<$Res> implements $ProjectDirectoryFrameCopyWith<$Res> {
  factory $ProjectDirectoryClosedCopyWith(ProjectDirectoryClosed value, $Res Function(ProjectDirectoryClosed) _then) = _$ProjectDirectoryClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ProjectDirectoryClosedCopyWithImpl<$Res>
    implements $ProjectDirectoryClosedCopyWith<$Res> {
  _$ProjectDirectoryClosedCopyWithImpl(this._self, this._then);

  final ProjectDirectoryClosed _self;
  final $Res Function(ProjectDirectoryClosed) _then;

/// Create a copy of ProjectDirectoryFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ProjectDirectoryClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of ProjectDirectoryFrame
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
