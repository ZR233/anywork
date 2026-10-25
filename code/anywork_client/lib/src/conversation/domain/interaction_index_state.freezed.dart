// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'interaction_index_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$InteractionListItem {

 InteractionReadRef get reference; String get interactionId; int get revision; InteractionKind get kind; InteractionStatus get status; int get createdAt; int get updatedAt;
/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionListItemCopyWith<InteractionListItem> get copyWith => _$InteractionListItemCopyWithImpl<InteractionListItem>(this as InteractionListItem, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionListItem;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionListItem&&(identical(other.reference, _this.reference) || other.reference == _this.reference)&&(identical(other.interactionId, _this.interactionId) || other.interactionId == _this.interactionId)&&(identical(other.revision, _this.revision) || other.revision == _this.revision)&&(identical(other.kind, _this.kind) || other.kind == _this.kind)&&(identical(other.status, _this.status) || other.status == _this.status)&&(identical(other.createdAt, _this.createdAt) || other.createdAt == _this.createdAt)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as InteractionListItem;
  return Object.hash(runtimeType,_this.reference,_this.interactionId,_this.revision,_this.kind,_this.status,_this.createdAt,_this.updatedAt);
}



}

/// @nodoc
abstract mixin class $InteractionListItemCopyWith<$Res>  {
  factory $InteractionListItemCopyWith(InteractionListItem value, $Res Function(InteractionListItem) _then) = _$InteractionListItemCopyWithImpl;
@useResult
$Res call({
 InteractionReadRef reference, String interactionId, int revision, InteractionKind kind, InteractionStatus status, int createdAt, int updatedAt
});


$InteractionReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class _$InteractionListItemCopyWithImpl<$Res>
    implements $InteractionListItemCopyWith<$Res> {
  _$InteractionListItemCopyWithImpl(this._self, this._then);

  final InteractionListItem _self;
  final $Res Function(InteractionListItem) _then;

/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? reference = null,Object? interactionId = null,Object? revision = null,Object? kind = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(InteractionListItem(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionReadRef,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InteractionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InteractionStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}
/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadRefCopyWith<$Res> get reference {

  return $InteractionReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionListItem].
extension InteractionListItemPatterns on InteractionListItem {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionListItem value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionListItem() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionListItem value)  $default,){
final _that = this;
switch (_that) {
case _InteractionListItem():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionListItem value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionListItem() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionReadRef reference,  String interactionId,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionListItem() when $default != null:
return $default(_that.reference,_that.interactionId,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionReadRef reference,  String interactionId,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)  $default,) {final _that = this;
switch (_that) {
case _InteractionListItem():
return $default(_that.reference,_that.interactionId,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionReadRef reference,  String interactionId,  int revision,  InteractionKind kind,  InteractionStatus status,  int createdAt,  int updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _InteractionListItem() when $default != null:
return $default(_that.reference,_that.interactionId,_that.revision,_that.kind,_that.status,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionListItem implements InteractionListItem {
  const _InteractionListItem({required this.reference, required this.interactionId, required this.revision, required this.kind, required this.status, required this.createdAt, required this.updatedAt});


@override final  InteractionReadRef reference;
@override final  String interactionId;
@override final  int revision;
@override final  InteractionKind kind;
@override final  InteractionStatus status;
@override final  int createdAt;
@override final  int updatedAt;

/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionListItemCopyWith<_InteractionListItem> get copyWith => __$InteractionListItemCopyWithImpl<_InteractionListItem>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionListItem&&(identical(other.reference, reference) || other.reference == reference)&&(identical(other.interactionId, interactionId) || other.interactionId == interactionId)&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.kind, kind) || other.kind == kind)&&(identical(other.status, status) || other.status == status)&&(identical(other.createdAt, createdAt) || other.createdAt == createdAt)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,reference,interactionId,revision,kind,status,createdAt,updatedAt);
}



}

/// @nodoc
abstract mixin class _$InteractionListItemCopyWith<$Res> implements $InteractionListItemCopyWith<$Res> {
  factory _$InteractionListItemCopyWith(_InteractionListItem value, $Res Function(_InteractionListItem) _then) = __$InteractionListItemCopyWithImpl;
@override @useResult
$Res call({
 InteractionReadRef reference, String interactionId, int revision, InteractionKind kind, InteractionStatus status, int createdAt, int updatedAt
});


@override $InteractionReadRefCopyWith<$Res> get reference;

}
/// @nodoc
class __$InteractionListItemCopyWithImpl<$Res>
    implements _$InteractionListItemCopyWith<$Res> {
  __$InteractionListItemCopyWithImpl(this._self, this._then);

  final _InteractionListItem _self;
  final $Res Function(_InteractionListItem) _then;

/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? reference = null,Object? interactionId = null,Object? revision = null,Object? kind = null,Object? status = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_InteractionListItem(
reference: null == reference ? _self.reference : reference // ignore: cast_nullable_to_non_nullable
as InteractionReadRef,interactionId: null == interactionId ? _self.interactionId : interactionId // ignore: cast_nullable_to_non_nullable
as String,revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,kind: null == kind ? _self.kind : kind // ignore: cast_nullable_to_non_nullable
as InteractionKind,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as InteractionStatus,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of InteractionListItem
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionReadRefCopyWith<$Res> get reference {

  return $InteractionReadRefCopyWith<$Res>(_self.reference, (value) {
    return _then(_self.copyWith(reference: value));
  });
}
}

/// @nodoc
mixin _$InteractionIndexReadSnapshot {


/// Create a copy of InteractionIndexReadSnapshot
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionIndexReadSnapshotCopyWith<InteractionIndexReadSnapshot> get copyWith => _$InteractionIndexReadSnapshotCopyWithImpl<InteractionIndexReadSnapshot>(this as InteractionIndexReadSnapshot, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionIndexReadSnapshot;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionIndexReadSnapshot&&(identical(other.origin, _this.origin) || other.origin == _this.origin)&&(identical(other.index, _this.index) || other.index == _this.index)&&const DeepCollectionEquality().equals(other.items, _this.items)&&(identical(other.nextOffset, _this.nextOffset) || other.nextOffset == _this.nextOffset)&&(identical(other.complete, _this.complete) || other.complete == _this.complete));
}


@override
int get hashCode {
  final _this = this as InteractionIndexReadSnapshot;
  return Object.hash(runtimeType,_this.origin,_this.index,const DeepCollectionEquality().hash(_this.items),_this.nextOffset,_this.complete);
}



}

/// @nodoc
abstract mixin class $InteractionIndexReadSnapshotCopyWith<$Res>  {
  factory $InteractionIndexReadSnapshotCopyWith(InteractionIndexReadSnapshot value, $Res Function(InteractionIndexReadSnapshot) _then) = _$InteractionIndexReadSnapshotCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp origin, InteractionIndexHeader index, List<InteractionListItem> items, int? nextOffset, bool complete
});


$ThreadFacetStampCopyWith<$Res> get origin;$InteractionIndexHeaderCopyWith<$Res> get index;

}
/// @nodoc
class _$InteractionIndexReadSnapshotCopyWithImpl<$Res>
    implements $InteractionIndexReadSnapshotCopyWith<$Res> {
  _$InteractionIndexReadSnapshotCopyWithImpl(this._self, this._then);

  final InteractionIndexReadSnapshot _self;
  final $Res Function(InteractionIndexReadSnapshot) _then;

/// Create a copy of InteractionIndexReadSnapshot
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? origin = null,Object? index = null,Object? items = null,Object? nextOffset = freezed,Object? complete = null,}) {
  return _then(InteractionIndexReadSnapshot(
origin: null == origin ? _self.origin : origin // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,index: null == index ? _self.index : index // ignore: cast_nullable_to_non_nullable
as InteractionIndexHeader,items: null == items ? _self.items : items // ignore: cast_nullable_to_non_nullable
as List<InteractionListItem>,nextOffset: freezed == nextOffset ? _self.nextOffset : nextOffset // ignore: cast_nullable_to_non_nullable
as int?,complete: null == complete ? _self.complete : complete // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of InteractionIndexReadSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get origin {

  return $ThreadFacetStampCopyWith<$Res>(_self.origin, (value) {
    return _then(_self.copyWith(origin: value));
  });
}/// Create a copy of InteractionIndexReadSnapshot
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexHeaderCopyWith<$Res> get index {

  return $InteractionIndexHeaderCopyWith<$Res>(_self.index, (value) {
    return _then(_self.copyWith(index: value));
  });
}
}


/// Adds pattern-matching-related methods to [InteractionIndexReadSnapshot].
extension InteractionIndexReadSnapshotPatterns on InteractionIndexReadSnapshot {
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
mixin _$InteractionIndexReadState {

 InteractionIndexReadSnapshot? get current; InteractionIndexReadSnapshot? get lastKnown; bool get loading; StudioFailure? get error;
/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$InteractionIndexReadStateCopyWith<InteractionIndexReadState> get copyWith => _$InteractionIndexReadStateCopyWithImpl<InteractionIndexReadState>(this as InteractionIndexReadState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as InteractionIndexReadState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is InteractionIndexReadState&&(identical(other.current, _this.current) || other.current == _this.current)&&(identical(other.lastKnown, _this.lastKnown) || other.lastKnown == _this.lastKnown)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as InteractionIndexReadState;
  return Object.hash(runtimeType,_this.current,_this.lastKnown,_this.loading,_this.error);
}



}

/// @nodoc
abstract mixin class $InteractionIndexReadStateCopyWith<$Res>  {
  factory $InteractionIndexReadStateCopyWith(InteractionIndexReadState value, $Res Function(InteractionIndexReadState) _then) = _$InteractionIndexReadStateCopyWithImpl;
@useResult
$Res call({
 InteractionIndexReadSnapshot? current, InteractionIndexReadSnapshot? lastKnown, bool loading, StudioFailure? error
});


$InteractionIndexReadSnapshotCopyWith<$Res>? get current;$InteractionIndexReadSnapshotCopyWith<$Res>? get lastKnown;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$InteractionIndexReadStateCopyWithImpl<$Res>
    implements $InteractionIndexReadStateCopyWith<$Res> {
  _$InteractionIndexReadStateCopyWithImpl(this._self, this._then);

  final InteractionIndexReadState _self;
  final $Res Function(InteractionIndexReadState) _then;

/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? current = freezed,Object? lastKnown = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(InteractionIndexReadState(
current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadSnapshot?,lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadSnapshot?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadSnapshotCopyWith<$Res>? get current {
    if (_self.current == null) {
    return null;
  }

  return $InteractionIndexReadSnapshotCopyWith<$Res>(_self.current!, (value) {
    return _then(_self.copyWith(current: value));
  });
}/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadSnapshotCopyWith<$Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $InteractionIndexReadSnapshotCopyWith<$Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}/// Create a copy of InteractionIndexReadState
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


/// Adds pattern-matching-related methods to [InteractionIndexReadState].
extension InteractionIndexReadStatePatterns on InteractionIndexReadState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _InteractionIndexReadState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _InteractionIndexReadState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _InteractionIndexReadState value)  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexReadState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _InteractionIndexReadState value)?  $default,){
final _that = this;
switch (_that) {
case _InteractionIndexReadState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( InteractionIndexReadSnapshot? current,  InteractionIndexReadSnapshot? lastKnown,  bool loading,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _InteractionIndexReadState() when $default != null:
return $default(_that.current,_that.lastKnown,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( InteractionIndexReadSnapshot? current,  InteractionIndexReadSnapshot? lastKnown,  bool loading,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexReadState():
return $default(_that.current,_that.lastKnown,_that.loading,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( InteractionIndexReadSnapshot? current,  InteractionIndexReadSnapshot? lastKnown,  bool loading,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _InteractionIndexReadState() when $default != null:
return $default(_that.current,_that.lastKnown,_that.loading,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _InteractionIndexReadState implements InteractionIndexReadState {
  const _InteractionIndexReadState({this.current, this.lastKnown, this.loading = false, this.error});


@override final  InteractionIndexReadSnapshot? current;
@override final  InteractionIndexReadSnapshot? lastKnown;
@override@JsonKey() final  bool loading;
@override final  StudioFailure? error;

/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$InteractionIndexReadStateCopyWith<_InteractionIndexReadState> get copyWith => __$InteractionIndexReadStateCopyWithImpl<_InteractionIndexReadState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _InteractionIndexReadState&&(identical(other.current, current) || other.current == current)&&(identical(other.lastKnown, lastKnown) || other.lastKnown == lastKnown)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,current,lastKnown,loading,error);
}



}

/// @nodoc
abstract mixin class _$InteractionIndexReadStateCopyWith<$Res> implements $InteractionIndexReadStateCopyWith<$Res> {
  factory _$InteractionIndexReadStateCopyWith(_InteractionIndexReadState value, $Res Function(_InteractionIndexReadState) _then) = __$InteractionIndexReadStateCopyWithImpl;
@override @useResult
$Res call({
 InteractionIndexReadSnapshot? current, InteractionIndexReadSnapshot? lastKnown, bool loading, StudioFailure? error
});


@override $InteractionIndexReadSnapshotCopyWith<$Res>? get current;@override $InteractionIndexReadSnapshotCopyWith<$Res>? get lastKnown;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$InteractionIndexReadStateCopyWithImpl<$Res>
    implements _$InteractionIndexReadStateCopyWith<$Res> {
  __$InteractionIndexReadStateCopyWithImpl(this._self, this._then);

  final _InteractionIndexReadState _self;
  final $Res Function(_InteractionIndexReadState) _then;

/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? current = freezed,Object? lastKnown = freezed,Object? loading = null,Object? error = freezed,}) {
  return _then(_InteractionIndexReadState(
current: freezed == current ? _self.current : current // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadSnapshot?,lastKnown: freezed == lastKnown ? _self.lastKnown : lastKnown // ignore: cast_nullable_to_non_nullable
as InteractionIndexReadSnapshot?,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadSnapshotCopyWith<$Res>? get current {
    if (_self.current == null) {
    return null;
  }

  return $InteractionIndexReadSnapshotCopyWith<$Res>(_self.current!, (value) {
    return _then(_self.copyWith(current: value));
  });
}/// Create a copy of InteractionIndexReadState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$InteractionIndexReadSnapshotCopyWith<$Res>? get lastKnown {
    if (_self.lastKnown == null) {
    return null;
  }

  return $InteractionIndexReadSnapshotCopyWith<$Res>(_self.lastKnown!, (value) {
    return _then(_self.copyWith(lastKnown: value));
  });
}/// Create a copy of InteractionIndexReadState
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

/// @nodoc
mixin _$ConversationRecoveryAccess {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ConversationRecoveryAccess);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ConversationRecoveryAccessCopyWith<$Res>  {
$ConversationRecoveryAccessCopyWith(ConversationRecoveryAccess _, $Res Function(ConversationRecoveryAccess) __);
}


/// Adds pattern-matching-related methods to [ConversationRecoveryAccess].
extension ConversationRecoveryAccessPatterns on ConversationRecoveryAccess {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AllowedConversationRecovery value)?  allowed,TResult Function( BlockedConversationRecovery value)?  blocked,TResult Function( UnknownConversationRecovery value)?  unknown,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AllowedConversationRecovery() when allowed != null:
return allowed(_that);case BlockedConversationRecovery() when blocked != null:
return blocked(_that);case UnknownConversationRecovery() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AllowedConversationRecovery value)  allowed,required TResult Function( BlockedConversationRecovery value)  blocked,required TResult Function( UnknownConversationRecovery value)  unknown,}){
final _that = this;
switch (_that) {
case AllowedConversationRecovery():
return allowed(_that);case BlockedConversationRecovery():
return blocked(_that);case UnknownConversationRecovery():
return unknown(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AllowedConversationRecovery value)?  allowed,TResult? Function( BlockedConversationRecovery value)?  blocked,TResult? Function( UnknownConversationRecovery value)?  unknown,}){
final _that = this;
switch (_that) {
case AllowedConversationRecovery() when allowed != null:
return allowed(_that);case BlockedConversationRecovery() when blocked != null:
return blocked(_that);case UnknownConversationRecovery() when unknown != null:
return unknown(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function()?  allowed,TResult Function( StudioFailure error)?  blocked,TResult Function( StudioFailure? error)?  unknown,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AllowedConversationRecovery() when allowed != null:
return allowed();case BlockedConversationRecovery() when blocked != null:
return blocked(_that.error);case UnknownConversationRecovery() when unknown != null:
return unknown(_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function()  allowed,required TResult Function( StudioFailure error)  blocked,required TResult Function( StudioFailure? error)  unknown,}) {final _that = this;
switch (_that) {
case AllowedConversationRecovery():
return allowed();case BlockedConversationRecovery():
return blocked(_that.error);case UnknownConversationRecovery():
return unknown(_that.error);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function()?  allowed,TResult? Function( StudioFailure error)?  blocked,TResult? Function( StudioFailure? error)?  unknown,}) {final _that = this;
switch (_that) {
case AllowedConversationRecovery() when allowed != null:
return allowed();case BlockedConversationRecovery() when blocked != null:
return blocked(_that.error);case UnknownConversationRecovery() when unknown != null:
return unknown(_that.error);case _:
  return null;

}
}

}

/// @nodoc


class AllowedConversationRecovery implements ConversationRecoveryAccess {
  const AllowedConversationRecovery();







@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AllowedConversationRecovery);
}


@override
int get hashCode => runtimeType.hashCode;



}




/// @nodoc


class BlockedConversationRecovery implements ConversationRecoveryAccess {
  const BlockedConversationRecovery({required this.error});


 final  StudioFailure error;

/// Create a copy of ConversationRecoveryAccess
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BlockedConversationRecoveryCopyWith<BlockedConversationRecovery> get copyWith => _$BlockedConversationRecoveryCopyWithImpl<BlockedConversationRecovery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BlockedConversationRecovery&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $BlockedConversationRecoveryCopyWith<$Res> implements $ConversationRecoveryAccessCopyWith<$Res> {
  factory $BlockedConversationRecoveryCopyWith(BlockedConversationRecovery value, $Res Function(BlockedConversationRecovery) _then) = _$BlockedConversationRecoveryCopyWithImpl;
@useResult
$Res call({
 StudioFailure error
});


$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$BlockedConversationRecoveryCopyWithImpl<$Res>
    implements $BlockedConversationRecoveryCopyWith<$Res> {
  _$BlockedConversationRecoveryCopyWithImpl(this._self, this._then);

  final BlockedConversationRecovery _self;
  final $Res Function(BlockedConversationRecovery) _then;

/// Create a copy of ConversationRecoveryAccess
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = null,}) {
  return _then(BlockedConversationRecovery(
error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ConversationRecoveryAccess
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


class UnknownConversationRecovery implements ConversationRecoveryAccess {
  const UnknownConversationRecovery({this.error});


 final  StudioFailure? error;

/// Create a copy of ConversationRecoveryAccess
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UnknownConversationRecoveryCopyWith<UnknownConversationRecovery> get copyWith => _$UnknownConversationRecoveryCopyWithImpl<UnknownConversationRecovery>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UnknownConversationRecovery&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,error);
}



}

/// @nodoc
abstract mixin class $UnknownConversationRecoveryCopyWith<$Res> implements $ConversationRecoveryAccessCopyWith<$Res> {
  factory $UnknownConversationRecoveryCopyWith(UnknownConversationRecovery value, $Res Function(UnknownConversationRecovery) _then) = _$UnknownConversationRecoveryCopyWithImpl;
@useResult
$Res call({
 StudioFailure? error
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$UnknownConversationRecoveryCopyWithImpl<$Res>
    implements $UnknownConversationRecoveryCopyWith<$Res> {
  _$UnknownConversationRecoveryCopyWithImpl(this._self, this._then);

  final UnknownConversationRecovery _self;
  final $Res Function(UnknownConversationRecovery) _then;

/// Create a copy of ConversationRecoveryAccess
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? error = freezed,}) {
  return _then(UnknownConversationRecovery(
error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ConversationRecoveryAccess
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
