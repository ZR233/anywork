// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotsHeader {

 ObservedHeader get source; int? get botsRevision; int? get updatedAt;
/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsHeaderCopyWith<BotsHeader> get copyWith => _$BotsHeaderCopyWithImpl<BotsHeader>(this as BotsHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsHeader&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.botsRevision, _this.botsRevision) || other.botsRevision == _this.botsRevision)&&(identical(other.updatedAt, _this.updatedAt) || other.updatedAt == _this.updatedAt));
}


@override
int get hashCode {
  final _this = this as BotsHeader;
  return Object.hash(runtimeType,_this.source,_this.botsRevision,_this.updatedAt);
}

@override
String toString() {
  final _this = this as BotsHeader;
  return 'BotsHeader(source: ${_this.source}, botsRevision: ${_this.botsRevision}, updatedAt: ${_this.updatedAt})';
}


}

/// @nodoc
abstract mixin class $BotsHeaderCopyWith<$Res>  {
  factory $BotsHeaderCopyWith(BotsHeader value, $Res Function(BotsHeader) _then) = _$BotsHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedHeader source, int? botsRevision, int? updatedAt
});


$ObservedHeaderCopyWith<$Res> get source;

}
/// @nodoc
class _$BotsHeaderCopyWithImpl<$Res>
    implements $BotsHeaderCopyWith<$Res> {
  _$BotsHeaderCopyWithImpl(this._self, this._then);

  final BotsHeader _self;
  final $Res Function(BotsHeader) _then;

/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? source = null,Object? botsRevision = freezed,Object? updatedAt = freezed,}) {
  return _then(BotsHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,botsRevision: freezed == botsRevision ? _self.botsRevision : botsRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}
/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsHeader].
extension BotsHeaderPatterns on BotsHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotsHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotsHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotsHeader value)  $default,){
final _that = this;
switch (_that) {
case _BotsHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotsHeader value)?  $default,){
final _that = this;
switch (_that) {
case _BotsHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedHeader source,  int? botsRevision,  int? updatedAt)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotsHeader() when $default != null:
return $default(_that.source,_that.botsRevision,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedHeader source,  int? botsRevision,  int? updatedAt)  $default,) {final _that = this;
switch (_that) {
case _BotsHeader():
return $default(_that.source,_that.botsRevision,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedHeader source,  int? botsRevision,  int? updatedAt)?  $default,) {final _that = this;
switch (_that) {
case _BotsHeader() when $default != null:
return $default(_that.source,_that.botsRevision,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _BotsHeader implements BotsHeader {
  const _BotsHeader({required this.source, required this.botsRevision, required this.updatedAt});


@override final  ObservedHeader source;
@override final  int? botsRevision;
@override final  int? updatedAt;

/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotsHeaderCopyWith<_BotsHeader> get copyWith => __$BotsHeaderCopyWithImpl<_BotsHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotsHeader&&(identical(other.source, source) || other.source == source)&&(identical(other.botsRevision, botsRevision) || other.botsRevision == botsRevision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,source,botsRevision,updatedAt);
}

@override
String toString() {
    return 'BotsHeader(source: $source, botsRevision: $botsRevision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$BotsHeaderCopyWith<$Res> implements $BotsHeaderCopyWith<$Res> {
  factory _$BotsHeaderCopyWith(_BotsHeader value, $Res Function(_BotsHeader) _then) = __$BotsHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedHeader source, int? botsRevision, int? updatedAt
});


@override $ObservedHeaderCopyWith<$Res> get source;

}
/// @nodoc
class __$BotsHeaderCopyWithImpl<$Res>
    implements _$BotsHeaderCopyWith<$Res> {
  __$BotsHeaderCopyWithImpl(this._self, this._then);

  final _BotsHeader _self;
  final $Res Function(_BotsHeader) _then;

/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? source = null,Object? botsRevision = freezed,Object? updatedAt = freezed,}) {
  return _then(_BotsHeader(
source: null == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ObservedHeader,botsRevision: freezed == botsRevision ? _self.botsRevision : botsRevision // ignore: cast_nullable_to_non_nullable
as int?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of BotsHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<$Res> get source {

  return $ObservedHeaderCopyWith<$Res>(_self.source, (value) {
    return _then(_self.copyWith(source: value));
  });
}
}

/// @nodoc
mixin _$BotsState {

 ProductProjection<BotsHeader> get projection; ReadValue<ProductSourceStatus, ProductSourceStatusRef>? get sourceStatus; Materialized<BotsStateSnapshot, ResourceStamp>? get snapshot;
/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsStateCopyWith<BotsState> get copyWith => _$BotsStateCopyWithImpl<BotsState>(this as BotsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsState&&(identical(other.projection, _this.projection) || other.projection == _this.projection)&&(identical(other.sourceStatus, _this.sourceStatus) || other.sourceStatus == _this.sourceStatus)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as BotsState;
  return Object.hash(runtimeType,_this.projection,_this.sourceStatus,_this.snapshot);
}



}

/// @nodoc
abstract mixin class $BotsStateCopyWith<$Res>  {
  factory $BotsStateCopyWith(BotsState value, $Res Function(BotsState) _then) = _$BotsStateCopyWithImpl;
@useResult
$Res call({
 ProductProjection<BotsHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, Materialized<BotsStateSnapshot, ResourceStamp>? snapshot
});


$ProductProjectionCopyWith<BotsHeader, $Res> get projection;$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;$MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>? get snapshot;

}
/// @nodoc
class _$BotsStateCopyWithImpl<$Res>
    implements $BotsStateCopyWith<$Res> {
  _$BotsStateCopyWithImpl(this._self, this._then);

  final BotsState _self;
  final $Res Function(BotsState) _then;

/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? snapshot = freezed,}) {
  return _then(BotsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<BotsHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as Materialized<BotsStateSnapshot, ResourceStamp>?,
  ));
}
/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<BotsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<BotsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsState].
extension BotsStatePatterns on BotsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotsState value)  $default,){
final _that = this;
switch (_that) {
case _BotsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotsState value)?  $default,){
final _that = this;
switch (_that) {
case _BotsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ProductProjection<BotsHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  Materialized<BotsStateSnapshot, ResourceStamp>? snapshot)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotsState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ProductProjection<BotsHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  Materialized<BotsStateSnapshot, ResourceStamp>? snapshot)  $default,) {final _that = this;
switch (_that) {
case _BotsState():
return $default(_that.projection,_that.sourceStatus,_that.snapshot);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ProductProjection<BotsHeader> projection,  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus,  Materialized<BotsStateSnapshot, ResourceStamp>? snapshot)?  $default,) {final _that = this;
switch (_that) {
case _BotsState() when $default != null:
return $default(_that.projection,_that.sourceStatus,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class _BotsState implements BotsState {
  const _BotsState({required this.projection, required this.sourceStatus, required this.snapshot});


@override final  ProductProjection<BotsHeader> projection;
@override final  ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus;
@override final  Materialized<BotsStateSnapshot, ResourceStamp>? snapshot;

/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotsStateCopyWith<_BotsState> get copyWith => __$BotsStateCopyWithImpl<_BotsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotsState&&(identical(other.projection, projection) || other.projection == projection)&&(identical(other.sourceStatus, sourceStatus) || other.sourceStatus == sourceStatus)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,projection,sourceStatus,snapshot);
}



}

/// @nodoc
abstract mixin class _$BotsStateCopyWith<$Res> implements $BotsStateCopyWith<$Res> {
  factory _$BotsStateCopyWith(_BotsState value, $Res Function(_BotsState) _then) = __$BotsStateCopyWithImpl;
@override @useResult
$Res call({
 ProductProjection<BotsHeader> projection, ReadValue<ProductSourceStatus, ProductSourceStatusRef>? sourceStatus, Materialized<BotsStateSnapshot, ResourceStamp>? snapshot
});


@override $ProductProjectionCopyWith<BotsHeader, $Res> get projection;@override $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus;@override $MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>? get snapshot;

}
/// @nodoc
class __$BotsStateCopyWithImpl<$Res>
    implements _$BotsStateCopyWith<$Res> {
  __$BotsStateCopyWithImpl(this._self, this._then);

  final _BotsState _self;
  final $Res Function(_BotsState) _then;

/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? projection = null,Object? sourceStatus = freezed,Object? snapshot = freezed,}) {
  return _then(_BotsState(
projection: null == projection ? _self.projection : projection // ignore: cast_nullable_to_non_nullable
as ProductProjection<BotsHeader>,sourceStatus: freezed == sourceStatus ? _self.sourceStatus : sourceStatus // ignore: cast_nullable_to_non_nullable
as ReadValue<ProductSourceStatus, ProductSourceStatusRef>?,snapshot: freezed == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as Materialized<BotsStateSnapshot, ResourceStamp>?,
  ));
}

/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionCopyWith<BotsHeader, $Res> get projection {

  return $ProductProjectionCopyWith<BotsHeader, $Res>(_self.projection, (value) {
    return _then(_self.copyWith(projection: value));
  });
}/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>? get sourceStatus {
    if (_self.sourceStatus == null) {
    return null;
  }

  return $ReadValueCopyWith<ProductSourceStatus, ProductSourceStatusRef, $Res>(_self.sourceStatus!, (value) {
    return _then(_self.copyWith(sourceStatus: value));
  });
}/// Create a copy of BotsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>? get snapshot {
    if (_self.snapshot == null) {
    return null;
  }

  return $MaterializedCopyWith<BotsStateSnapshot, ResourceStamp, $Res>(_self.snapshot!, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

/// @nodoc
mixin _$BotConversationsState {

 String get botId; BotConversationPage? get page; CollectionContinuation get continuation; bool get loading; StudioFailure? get error; bool get closed;
/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotConversationsStateCopyWith<BotConversationsState> get copyWith => _$BotConversationsStateCopyWithImpl<BotConversationsState>(this as BotConversationsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotConversationsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotConversationsState&&(identical(other.botId, _this.botId) || other.botId == _this.botId)&&(identical(other.page, _this.page) || other.page == _this.page)&&(identical(other.continuation, _this.continuation) || other.continuation == _this.continuation)&&(identical(other.loading, _this.loading) || other.loading == _this.loading)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.closed, _this.closed) || other.closed == _this.closed));
}


@override
int get hashCode {
  final _this = this as BotConversationsState;
  return Object.hash(runtimeType,_this.botId,_this.page,_this.continuation,_this.loading,_this.error,_this.closed);
}



}

/// @nodoc
abstract mixin class $BotConversationsStateCopyWith<$Res>  {
  factory $BotConversationsStateCopyWith(BotConversationsState value, $Res Function(BotConversationsState) _then) = _$BotConversationsStateCopyWithImpl;
@useResult
$Res call({
 String botId, BotConversationPage? page, CollectionContinuation continuation, bool loading, StudioFailure? error, bool closed
});


$BotConversationPageCopyWith<$Res>? get page;$CollectionContinuationCopyWith<$Res> get continuation;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$BotConversationsStateCopyWithImpl<$Res>
    implements $BotConversationsStateCopyWith<$Res> {
  _$BotConversationsStateCopyWithImpl(this._self, this._then);

  final BotConversationsState _self;
  final $Res Function(BotConversationsState) _then;

/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? botId = null,Object? page = freezed,Object? continuation = null,Object? loading = null,Object? error = freezed,Object? closed = null,}) {
  return _then(BotConversationsState(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as BotConversationPage?,continuation: null == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as CollectionContinuation,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationPageCopyWith<$Res>? get page {
    if (_self.page == null) {
    return null;
  }

  return $BotConversationPageCopyWith<$Res>(_self.page!, (value) {
    return _then(_self.copyWith(page: value));
  });
}/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionContinuationCopyWith<$Res> get continuation {

  return $CollectionContinuationCopyWith<$Res>(_self.continuation, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}/// Create a copy of BotConversationsState
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


/// Adds pattern-matching-related methods to [BotConversationsState].
extension BotConversationsStatePatterns on BotConversationsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BotConversationsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BotConversationsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BotConversationsState value)  $default,){
final _that = this;
switch (_that) {
case _BotConversationsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BotConversationsState value)?  $default,){
final _that = this;
switch (_that) {
case _BotConversationsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String botId,  BotConversationPage? page,  CollectionContinuation continuation,  bool loading,  StudioFailure? error,  bool closed)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BotConversationsState() when $default != null:
return $default(_that.botId,_that.page,_that.continuation,_that.loading,_that.error,_that.closed);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String botId,  BotConversationPage? page,  CollectionContinuation continuation,  bool loading,  StudioFailure? error,  bool closed)  $default,) {final _that = this;
switch (_that) {
case _BotConversationsState():
return $default(_that.botId,_that.page,_that.continuation,_that.loading,_that.error,_that.closed);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String botId,  BotConversationPage? page,  CollectionContinuation continuation,  bool loading,  StudioFailure? error,  bool closed)?  $default,) {final _that = this;
switch (_that) {
case _BotConversationsState() when $default != null:
return $default(_that.botId,_that.page,_that.continuation,_that.loading,_that.error,_that.closed);case _:
  return null;

}
}

}

/// @nodoc


class _BotConversationsState implements BotConversationsState {
  const _BotConversationsState({required this.botId, required this.page, required this.continuation, required this.loading, required this.error, required this.closed});


@override final  String botId;
@override final  BotConversationPage? page;
@override final  CollectionContinuation continuation;
@override final  bool loading;
@override final  StudioFailure? error;
@override final  bool closed;

/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BotConversationsStateCopyWith<_BotConversationsState> get copyWith => __$BotConversationsStateCopyWithImpl<_BotConversationsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _BotConversationsState&&(identical(other.botId, botId) || other.botId == botId)&&(identical(other.page, page) || other.page == page)&&(identical(other.continuation, continuation) || other.continuation == continuation)&&(identical(other.loading, loading) || other.loading == loading)&&(identical(other.error, error) || other.error == error)&&(identical(other.closed, closed) || other.closed == closed));
}


@override
int get hashCode {
    return Object.hash(runtimeType,botId,page,continuation,loading,error,closed);
}



}

/// @nodoc
abstract mixin class _$BotConversationsStateCopyWith<$Res> implements $BotConversationsStateCopyWith<$Res> {
  factory _$BotConversationsStateCopyWith(_BotConversationsState value, $Res Function(_BotConversationsState) _then) = __$BotConversationsStateCopyWithImpl;
@override @useResult
$Res call({
 String botId, BotConversationPage? page, CollectionContinuation continuation, bool loading, StudioFailure? error, bool closed
});


@override $BotConversationPageCopyWith<$Res>? get page;@override $CollectionContinuationCopyWith<$Res> get continuation;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$BotConversationsStateCopyWithImpl<$Res>
    implements _$BotConversationsStateCopyWith<$Res> {
  __$BotConversationsStateCopyWithImpl(this._self, this._then);

  final _BotConversationsState _self;
  final $Res Function(_BotConversationsState) _then;

/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? botId = null,Object? page = freezed,Object? continuation = null,Object? loading = null,Object? error = freezed,Object? closed = null,}) {
  return _then(_BotConversationsState(
botId: null == botId ? _self.botId : botId // ignore: cast_nullable_to_non_nullable
as String,page: freezed == page ? _self.page : page // ignore: cast_nullable_to_non_nullable
as BotConversationPage?,continuation: null == continuation ? _self.continuation : continuation // ignore: cast_nullable_to_non_nullable
as CollectionContinuation,loading: null == loading ? _self.loading : loading // ignore: cast_nullable_to_non_nullable
as bool,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,closed: null == closed ? _self.closed : closed // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotConversationPageCopyWith<$Res>? get page {
    if (_self.page == null) {
    return null;
  }

  return $BotConversationPageCopyWith<$Res>(_self.page!, (value) {
    return _then(_self.copyWith(page: value));
  });
}/// Create a copy of BotConversationsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$CollectionContinuationCopyWith<$Res> get continuation {

  return $CollectionContinuationCopyWith<$Res>(_self.continuation, (value) {
    return _then(_self.copyWith(continuation: value));
  });
}/// Create a copy of BotConversationsState
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
