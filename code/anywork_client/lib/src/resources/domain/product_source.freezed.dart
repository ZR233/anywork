// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'product_source.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ObservedBrief {

 int get revision;
/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObservedBriefCopyWith<ObservedBrief> get copyWith => _$ObservedBriefCopyWithImpl<ObservedBrief>(this as ObservedBrief, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ObservedBrief;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObservedBrief&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ObservedBrief;
  return Object.hash(runtimeType,_this.revision);
}

@override
String toString() {
  final _this = this as ObservedBrief;
  return 'ObservedBrief(revision: ${_this.revision})';
}


}

/// @nodoc
abstract mixin class $ObservedBriefCopyWith<$Res>  {
  factory $ObservedBriefCopyWith(ObservedBrief value, $Res Function(ObservedBrief) _then) = _$ObservedBriefCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$ObservedBriefCopyWithImpl<$Res>
    implements $ObservedBriefCopyWith<$Res> {
  _$ObservedBriefCopyWithImpl(this._self, this._then);

  final ObservedBrief _self;
  final $Res Function(ObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ObservedBrief].
extension ObservedBriefPatterns on ObservedBrief {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UninitializedObservedBrief value)?  uninitialized,TResult Function( LoadingObservedBrief value)?  loading,TResult Function( ReadyObservedBrief value)?  ready,TResult Function( RefreshingObservedBrief value)?  refreshing,TResult Function( StaleObservedBrief value)?  stale,TResult Function( DegradedObservedBrief value)?  degraded,TResult Function( FailedObservedBrief value)?  failed,TResult Function( StoppedObservedBrief value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UninitializedObservedBrief() when uninitialized != null:
return uninitialized(_that);case LoadingObservedBrief() when loading != null:
return loading(_that);case ReadyObservedBrief() when ready != null:
return ready(_that);case RefreshingObservedBrief() when refreshing != null:
return refreshing(_that);case StaleObservedBrief() when stale != null:
return stale(_that);case DegradedObservedBrief() when degraded != null:
return degraded(_that);case FailedObservedBrief() when failed != null:
return failed(_that);case StoppedObservedBrief() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UninitializedObservedBrief value)  uninitialized,required TResult Function( LoadingObservedBrief value)  loading,required TResult Function( ReadyObservedBrief value)  ready,required TResult Function( RefreshingObservedBrief value)  refreshing,required TResult Function( StaleObservedBrief value)  stale,required TResult Function( DegradedObservedBrief value)  degraded,required TResult Function( FailedObservedBrief value)  failed,required TResult Function( StoppedObservedBrief value)  stopped,}){
final _that = this;
switch (_that) {
case UninitializedObservedBrief():
return uninitialized(_that);case LoadingObservedBrief():
return loading(_that);case ReadyObservedBrief():
return ready(_that);case RefreshingObservedBrief():
return refreshing(_that);case StaleObservedBrief():
return stale(_that);case DegradedObservedBrief():
return degraded(_that);case FailedObservedBrief():
return failed(_that);case StoppedObservedBrief():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UninitializedObservedBrief value)?  uninitialized,TResult? Function( LoadingObservedBrief value)?  loading,TResult? Function( ReadyObservedBrief value)?  ready,TResult? Function( RefreshingObservedBrief value)?  refreshing,TResult? Function( StaleObservedBrief value)?  stale,TResult? Function( DegradedObservedBrief value)?  degraded,TResult? Function( FailedObservedBrief value)?  failed,TResult? Function( StoppedObservedBrief value)?  stopped,}){
final _that = this;
switch (_that) {
case UninitializedObservedBrief() when uninitialized != null:
return uninitialized(_that);case LoadingObservedBrief() when loading != null:
return loading(_that);case ReadyObservedBrief() when ready != null:
return ready(_that);case RefreshingObservedBrief() when refreshing != null:
return refreshing(_that);case StaleObservedBrief() when stale != null:
return stale(_that);case DegradedObservedBrief() when degraded != null:
return degraded(_that);case FailedObservedBrief() when failed != null:
return failed(_that);case StoppedObservedBrief() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  uninitialized,TResult Function( int revision,  int startedAt)?  loading,TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult Function( int revision,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  bool retryable)?  degraded,TResult Function( int revision,  int failedAt,  bool retryable)?  failed,TResult Function( int revision,  int stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UninitializedObservedBrief() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedBrief() when loading != null:
return loading(_that.revision,_that.startedAt);case ReadyObservedBrief() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingObservedBrief() when refreshing != null:
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case StaleObservedBrief() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedObservedBrief() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case FailedObservedBrief() when failed != null:
return failed(_that.revision,_that.failedAt,_that.retryable);case StoppedObservedBrief() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  uninitialized,required TResult Function( int revision,  int startedAt)  loading,required TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)  ready,required TResult Function( int revision,  int startedAt,  int? lastCheckedAt)  refreshing,required TResult Function( int revision,  int staleAt,  int? lastCheckedAt)  stale,required TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  bool retryable)  degraded,required TResult Function( int revision,  int failedAt,  bool retryable)  failed,required TResult Function( int revision,  int stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case UninitializedObservedBrief():
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedBrief():
return loading(_that.revision,_that.startedAt);case ReadyObservedBrief():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingObservedBrief():
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case StaleObservedBrief():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedObservedBrief():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case FailedObservedBrief():
return failed(_that.revision,_that.failedAt,_that.retryable);case StoppedObservedBrief():
return stopped(_that.revision,_that.stoppedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  uninitialized,TResult? Function( int revision,  int startedAt)?  loading,TResult? Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult? Function( int revision,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult? Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult? Function( int revision,  int failedAt,  int? lastCheckedAt,  bool retryable)?  degraded,TResult? Function( int revision,  int failedAt,  bool retryable)?  failed,TResult? Function( int revision,  int stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case UninitializedObservedBrief() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedBrief() when loading != null:
return loading(_that.revision,_that.startedAt);case ReadyObservedBrief() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingObservedBrief() when refreshing != null:
return refreshing(_that.revision,_that.startedAt,_that.lastCheckedAt);case StaleObservedBrief() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedObservedBrief() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.retryable);case FailedObservedBrief() when failed != null:
return failed(_that.revision,_that.failedAt,_that.retryable);case StoppedObservedBrief() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class UninitializedObservedBrief implements ObservedBrief {
  const UninitializedObservedBrief({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UninitializedObservedBriefCopyWith<UninitializedObservedBrief> get copyWith => _$UninitializedObservedBriefCopyWithImpl<UninitializedObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UninitializedObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}

@override
String toString() {
    return 'ObservedBrief.uninitialized(revision: $revision, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $UninitializedObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $UninitializedObservedBriefCopyWith(UninitializedObservedBrief value, $Res Function(UninitializedObservedBrief) _then) = _$UninitializedObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$UninitializedObservedBriefCopyWithImpl<$Res>
    implements $UninitializedObservedBriefCopyWith<$Res> {
  _$UninitializedObservedBriefCopyWithImpl(this._self, this._then);

  final UninitializedObservedBrief _self;
  final $Res Function(UninitializedObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(UninitializedObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class LoadingObservedBrief implements ObservedBrief {
  const LoadingObservedBrief({required this.revision, required this.startedAt});


@override final  int revision;
 final  int startedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingObservedBriefCopyWith<LoadingObservedBrief> get copyWith => _$LoadingObservedBriefCopyWithImpl<LoadingObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt);
}

@override
String toString() {
    return 'ObservedBrief.loading(revision: $revision, startedAt: $startedAt)';
}


}

/// @nodoc
abstract mixin class $LoadingObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $LoadingObservedBriefCopyWith(LoadingObservedBrief value, $Res Function(LoadingObservedBrief) _then) = _$LoadingObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int startedAt
});




}
/// @nodoc
class _$LoadingObservedBriefCopyWithImpl<$Res>
    implements $LoadingObservedBriefCopyWith<$Res> {
  _$LoadingObservedBriefCopyWithImpl(this._self, this._then);

  final LoadingObservedBrief _self;
  final $Res Function(LoadingObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,}) {
  return _then(LoadingObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReadyObservedBrief implements ObservedBrief {
  const ReadyObservedBrief({required this.revision, required this.updatedAt, required this.lastCheckedAt});


@override final  int revision;
 final  int updatedAt;
 final  int? lastCheckedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyObservedBriefCopyWith<ReadyObservedBrief> get copyWith => _$ReadyObservedBriefCopyWithImpl<ReadyObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt);
}

@override
String toString() {
    return 'ObservedBrief.ready(revision: $revision, updatedAt: $updatedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $ReadyObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $ReadyObservedBriefCopyWith(ReadyObservedBrief value, $Res Function(ReadyObservedBrief) _then) = _$ReadyObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int? lastCheckedAt
});




}
/// @nodoc
class _$ReadyObservedBriefCopyWithImpl<$Res>
    implements $ReadyObservedBriefCopyWith<$Res> {
  _$ReadyObservedBriefCopyWithImpl(this._self, this._then);

  final ReadyObservedBrief _self;
  final $Res Function(ReadyObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(ReadyObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class RefreshingObservedBrief implements ObservedBrief {
  const RefreshingObservedBrief({required this.revision, required this.startedAt, required this.lastCheckedAt});


@override final  int revision;
 final  int startedAt;
 final  int? lastCheckedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefreshingObservedBriefCopyWith<RefreshingObservedBrief> get copyWith => _$RefreshingObservedBriefCopyWithImpl<RefreshingObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RefreshingObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,startedAt,lastCheckedAt);
}

@override
String toString() {
    return 'ObservedBrief.refreshing(revision: $revision, startedAt: $startedAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $RefreshingObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $RefreshingObservedBriefCopyWith(RefreshingObservedBrief value, $Res Function(RefreshingObservedBrief) _then) = _$RefreshingObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int startedAt, int? lastCheckedAt
});




}
/// @nodoc
class _$RefreshingObservedBriefCopyWithImpl<$Res>
    implements $RefreshingObservedBriefCopyWith<$Res> {
  _$RefreshingObservedBriefCopyWithImpl(this._self, this._then);

  final RefreshingObservedBrief _self;
  final $Res Function(RefreshingObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? startedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(RefreshingObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class StaleObservedBrief implements ObservedBrief {
  const StaleObservedBrief({required this.revision, required this.staleAt, required this.lastCheckedAt});


@override final  int revision;
 final  int staleAt;
 final  int? lastCheckedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaleObservedBriefCopyWith<StaleObservedBrief> get copyWith => _$StaleObservedBriefCopyWithImpl<StaleObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StaleObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt);
}

@override
String toString() {
    return 'ObservedBrief.stale(revision: $revision, staleAt: $staleAt, lastCheckedAt: $lastCheckedAt)';
}


}

/// @nodoc
abstract mixin class $StaleObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $StaleObservedBriefCopyWith(StaleObservedBrief value, $Res Function(StaleObservedBrief) _then) = _$StaleObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int staleAt, int? lastCheckedAt
});




}
/// @nodoc
class _$StaleObservedBriefCopyWithImpl<$Res>
    implements $StaleObservedBriefCopyWith<$Res> {
  _$StaleObservedBriefCopyWithImpl(this._self, this._then);

  final StaleObservedBrief _self;
  final $Res Function(StaleObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(StaleObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedObservedBrief implements ObservedBrief {
  const DegradedObservedBrief({required this.revision, required this.failedAt, required this.lastCheckedAt, required this.retryable});


@override final  int revision;
 final  int failedAt;
 final  int? lastCheckedAt;
 final  bool retryable;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedObservedBriefCopyWith<DegradedObservedBrief> get copyWith => _$DegradedObservedBriefCopyWithImpl<DegradedObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,retryable);
}

@override
String toString() {
    return 'ObservedBrief.degraded(revision: $revision, failedAt: $failedAt, lastCheckedAt: $lastCheckedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $DegradedObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $DegradedObservedBriefCopyWith(DegradedObservedBrief value, $Res Function(DegradedObservedBrief) _then) = _$DegradedObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, int? lastCheckedAt, bool retryable
});




}
/// @nodoc
class _$DegradedObservedBriefCopyWithImpl<$Res>
    implements $DegradedObservedBriefCopyWith<$Res> {
  _$DegradedObservedBriefCopyWithImpl(this._self, this._then);

  final DegradedObservedBrief _self;
  final $Res Function(DegradedObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? retryable = null,}) {
  return _then(DegradedObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class FailedObservedBrief implements ObservedBrief {
  const FailedObservedBrief({required this.revision, required this.failedAt, required this.retryable});


@override final  int revision;
 final  int failedAt;
 final  bool retryable;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedObservedBriefCopyWith<FailedObservedBrief> get copyWith => _$FailedObservedBriefCopyWithImpl<FailedObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,retryable);
}

@override
String toString() {
    return 'ObservedBrief.failed(revision: $revision, failedAt: $failedAt, retryable: $retryable)';
}


}

/// @nodoc
abstract mixin class $FailedObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $FailedObservedBriefCopyWith(FailedObservedBrief value, $Res Function(FailedObservedBrief) _then) = _$FailedObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, bool retryable
});




}
/// @nodoc
class _$FailedObservedBriefCopyWithImpl<$Res>
    implements $FailedObservedBriefCopyWith<$Res> {
  _$FailedObservedBriefCopyWithImpl(this._self, this._then);

  final FailedObservedBrief _self;
  final $Res Function(FailedObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? retryable = null,}) {
  return _then(FailedObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc


class StoppedObservedBrief implements ObservedBrief {
  const StoppedObservedBrief({required this.revision, required this.stoppedAt});


@override final  int revision;
 final  int stoppedAt;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedObservedBriefCopyWith<StoppedObservedBrief> get copyWith => _$StoppedObservedBriefCopyWithImpl<StoppedObservedBrief>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedObservedBrief&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}

@override
String toString() {
    return 'ObservedBrief.stopped(revision: $revision, stoppedAt: $stoppedAt)';
}


}

/// @nodoc
abstract mixin class $StoppedObservedBriefCopyWith<$Res> implements $ObservedBriefCopyWith<$Res> {
  factory $StoppedObservedBriefCopyWith(StoppedObservedBrief value, $Res Function(StoppedObservedBrief) _then) = _$StoppedObservedBriefCopyWithImpl;
@override @useResult
$Res call({
 int revision, int stoppedAt
});




}
/// @nodoc
class _$StoppedObservedBriefCopyWithImpl<$Res>
    implements $StoppedObservedBriefCopyWith<$Res> {
  _$StoppedObservedBriefCopyWithImpl(this._self, this._then);

  final StoppedObservedBrief _self;
  final $Res Function(StoppedObservedBrief) _then;

/// Create a copy of ObservedBrief
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(StoppedObservedBrief(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ObservedHeader {

 ObservedBrief get brief; ProductSourceStatusRef get status;
/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObservedHeaderCopyWith<ObservedHeader> get copyWith => _$ObservedHeaderCopyWithImpl<ObservedHeader>(this as ObservedHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ObservedHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObservedHeader&&(identical(other.brief, _this.brief) || other.brief == _this.brief)&&(identical(other.status, _this.status) || other.status == _this.status));
}


@override
int get hashCode {
  final _this = this as ObservedHeader;
  return Object.hash(runtimeType,_this.brief,_this.status);
}

@override
String toString() {
  final _this = this as ObservedHeader;
  return 'ObservedHeader(brief: ${_this.brief}, status: ${_this.status})';
}


}

/// @nodoc
abstract mixin class $ObservedHeaderCopyWith<$Res>  {
  factory $ObservedHeaderCopyWith(ObservedHeader value, $Res Function(ObservedHeader) _then) = _$ObservedHeaderCopyWithImpl;
@useResult
$Res call({
 ObservedBrief brief, ProductSourceStatusRef status
});


$ObservedBriefCopyWith<$Res> get brief;$ProductSourceStatusRefCopyWith<$Res> get status;

}
/// @nodoc
class _$ObservedHeaderCopyWithImpl<$Res>
    implements $ObservedHeaderCopyWith<$Res> {
  _$ObservedHeaderCopyWithImpl(this._self, this._then);

  final ObservedHeader _self;
  final $Res Function(ObservedHeader) _then;

/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? brief = null,Object? status = null,}) {
  return _then(ObservedHeader(
brief: null == brief ? _self.brief : brief // ignore: cast_nullable_to_non_nullable
as ObservedBrief,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ProductSourceStatusRef,
  ));
}
/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedBriefCopyWith<$Res> get brief {

  return $ObservedBriefCopyWith<$Res>(_self.brief, (value) {
    return _then(_self.copyWith(brief: value));
  });
}/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductSourceStatusRefCopyWith<$Res> get status {

  return $ProductSourceStatusRefCopyWith<$Res>(_self.status, (value) {
    return _then(_self.copyWith(status: value));
  });
}
}


/// Adds pattern-matching-related methods to [ObservedHeader].
extension ObservedHeaderPatterns on ObservedHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ObservedHeader value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ObservedHeader() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ObservedHeader value)  $default,){
final _that = this;
switch (_that) {
case _ObservedHeader():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ObservedHeader value)?  $default,){
final _that = this;
switch (_that) {
case _ObservedHeader() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ObservedBrief brief,  ProductSourceStatusRef status)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ObservedHeader() when $default != null:
return $default(_that.brief,_that.status);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ObservedBrief brief,  ProductSourceStatusRef status)  $default,) {final _that = this;
switch (_that) {
case _ObservedHeader():
return $default(_that.brief,_that.status);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ObservedBrief brief,  ProductSourceStatusRef status)?  $default,) {final _that = this;
switch (_that) {
case _ObservedHeader() when $default != null:
return $default(_that.brief,_that.status);case _:
  return null;

}
}

}

/// @nodoc


class _ObservedHeader implements ObservedHeader {
  const _ObservedHeader({required this.brief, required this.status});


@override final  ObservedBrief brief;
@override final  ProductSourceStatusRef status;

/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ObservedHeaderCopyWith<_ObservedHeader> get copyWith => __$ObservedHeaderCopyWithImpl<_ObservedHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ObservedHeader&&(identical(other.brief, brief) || other.brief == brief)&&(identical(other.status, status) || other.status == status));
}


@override
int get hashCode {
    return Object.hash(runtimeType,brief,status);
}

@override
String toString() {
    return 'ObservedHeader(brief: $brief, status: $status)';
}


}

/// @nodoc
abstract mixin class _$ObservedHeaderCopyWith<$Res> implements $ObservedHeaderCopyWith<$Res> {
  factory _$ObservedHeaderCopyWith(_ObservedHeader value, $Res Function(_ObservedHeader) _then) = __$ObservedHeaderCopyWithImpl;
@override @useResult
$Res call({
 ObservedBrief brief, ProductSourceStatusRef status
});


@override $ObservedBriefCopyWith<$Res> get brief;@override $ProductSourceStatusRefCopyWith<$Res> get status;

}
/// @nodoc
class __$ObservedHeaderCopyWithImpl<$Res>
    implements _$ObservedHeaderCopyWith<$Res> {
  __$ObservedHeaderCopyWithImpl(this._self, this._then);

  final _ObservedHeader _self;
  final $Res Function(_ObservedHeader) _then;

/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? brief = null,Object? status = null,}) {
  return _then(_ObservedHeader(
brief: null == brief ? _self.brief : brief // ignore: cast_nullable_to_non_nullable
as ObservedBrief,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as ProductSourceStatusRef,
  ));
}

/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ObservedBriefCopyWith<$Res> get brief {

  return $ObservedBriefCopyWith<$Res>(_self.brief, (value) {
    return _then(_self.copyWith(brief: value));
  });
}/// Create a copy of ObservedHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductSourceStatusRefCopyWith<$Res> get status {

  return $ProductSourceStatusRefCopyWith<$Res>(_self.status, (value) {
    return _then(_self.copyWith(status: value));
  });
}
}

/// @nodoc
mixin _$SourceStateErrorRead {

 ReadText get code; ReadText get message; bool get retryable;
/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<SourceStateErrorRead> get copyWith => _$SourceStateErrorReadCopyWithImpl<SourceStateErrorRead>(this as SourceStateErrorRead, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SourceStateErrorRead;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceStateErrorRead&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable));
}


@override
int get hashCode {
  final _this = this as SourceStateErrorRead;
  return Object.hash(runtimeType,_this.code,_this.message,_this.retryable);
}



}

/// @nodoc
abstract mixin class $SourceStateErrorReadCopyWith<$Res>  {
  factory $SourceStateErrorReadCopyWith(SourceStateErrorRead value, $Res Function(SourceStateErrorRead) _then) = _$SourceStateErrorReadCopyWithImpl;
@useResult
$Res call({
 ReadText code, ReadText message, bool retryable
});


$ReadTextCopyWith<$Res> get code;$ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class _$SourceStateErrorReadCopyWithImpl<$Res>
    implements $SourceStateErrorReadCopyWith<$Res> {
  _$SourceStateErrorReadCopyWithImpl(this._self, this._then);

  final SourceStateErrorRead _self;
  final $Res Function(SourceStateErrorRead) _then;

/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(SourceStateErrorRead(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ReadText,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get code {

  return $ReadTextCopyWith<$Res>(_self.code, (value) {
    return _then(_self.copyWith(code: value));
  });
}/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}


/// Adds pattern-matching-related methods to [SourceStateErrorRead].
extension SourceStateErrorReadPatterns on SourceStateErrorRead {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceStateErrorRead value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceStateErrorRead() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceStateErrorRead value)  $default,){
final _that = this;
switch (_that) {
case _SourceStateErrorRead():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceStateErrorRead value)?  $default,){
final _that = this;
switch (_that) {
case _SourceStateErrorRead() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ReadText code,  ReadText message,  bool retryable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceStateErrorRead() when $default != null:
return $default(_that.code,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ReadText code,  ReadText message,  bool retryable)  $default,) {final _that = this;
switch (_that) {
case _SourceStateErrorRead():
return $default(_that.code,_that.message,_that.retryable);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ReadText code,  ReadText message,  bool retryable)?  $default,) {final _that = this;
switch (_that) {
case _SourceStateErrorRead() when $default != null:
return $default(_that.code,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class _SourceStateErrorRead implements SourceStateErrorRead {
  const _SourceStateErrorRead({required this.code, required this.message, required this.retryable});


@override final  ReadText code;
@override final  ReadText message;
@override final  bool retryable;

/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceStateErrorReadCopyWith<_SourceStateErrorRead> get copyWith => __$SourceStateErrorReadCopyWithImpl<_SourceStateErrorRead>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceStateErrorRead&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable);
}



}

/// @nodoc
abstract mixin class _$SourceStateErrorReadCopyWith<$Res> implements $SourceStateErrorReadCopyWith<$Res> {
  factory _$SourceStateErrorReadCopyWith(_SourceStateErrorRead value, $Res Function(_SourceStateErrorRead) _then) = __$SourceStateErrorReadCopyWithImpl;
@override @useResult
$Res call({
 ReadText code, ReadText message, bool retryable
});


@override $ReadTextCopyWith<$Res> get code;@override $ReadTextCopyWith<$Res> get message;

}
/// @nodoc
class __$SourceStateErrorReadCopyWithImpl<$Res>
    implements _$SourceStateErrorReadCopyWith<$Res> {
  __$SourceStateErrorReadCopyWithImpl(this._self, this._then);

  final _SourceStateErrorRead _self;
  final $Res Function(_SourceStateErrorRead) _then;

/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(_SourceStateErrorRead(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as ReadText,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as ReadText,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get code {

  return $ReadTextCopyWith<$Res>(_self.code, (value) {
    return _then(_self.copyWith(code: value));
  });
}/// Create a copy of SourceStateErrorRead
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get message {

  return $ReadTextCopyWith<$Res>(_self.message, (value) {
    return _then(_self.copyWith(message: value));
  });
}
}

/// @nodoc
mixin _$ProductSourceStatusReadHeader {

 int get revision;
/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductSourceStatusReadHeaderCopyWith<ProductSourceStatusReadHeader> get copyWith => _$ProductSourceStatusReadHeaderCopyWithImpl<ProductSourceStatusReadHeader>(this as ProductSourceStatusReadHeader, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductSourceStatusReadHeader;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductSourceStatusReadHeader&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductSourceStatusReadHeader;
  return Object.hash(runtimeType,_this.revision);
}



}

/// @nodoc
abstract mixin class $ProductSourceStatusReadHeaderCopyWith<$Res>  {
  factory $ProductSourceStatusReadHeaderCopyWith(ProductSourceStatusReadHeader value, $Res Function(ProductSourceStatusReadHeader) _then) = _$ProductSourceStatusReadHeaderCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$ProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  _$ProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final ProductSourceStatusReadHeader _self;
  final $Res Function(ProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductSourceStatusReadHeader].
extension ProductSourceStatusReadHeaderPatterns on ProductSourceStatusReadHeader {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UninitializedProductSourceStatusReadHeader value)?  uninitialized,TResult Function( LoadingProductSourceStatusReadHeader value)?  loading,TResult Function( ReadyProductSourceStatusReadHeader value)?  ready,TResult Function( RefreshingProductSourceStatusReadHeader value)?  refreshing,TResult Function( StaleProductSourceStatusReadHeader value)?  stale,TResult Function( DegradedProductSourceStatusReadHeader value)?  degraded,TResult Function( FailedProductSourceStatusReadHeader value)?  failed,TResult Function( StoppedProductSourceStatusReadHeader value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader() when uninitialized != null:
return uninitialized(_that);case LoadingProductSourceStatusReadHeader() when loading != null:
return loading(_that);case ReadyProductSourceStatusReadHeader() when ready != null:
return ready(_that);case RefreshingProductSourceStatusReadHeader() when refreshing != null:
return refreshing(_that);case StaleProductSourceStatusReadHeader() when stale != null:
return stale(_that);case DegradedProductSourceStatusReadHeader() when degraded != null:
return degraded(_that);case FailedProductSourceStatusReadHeader() when failed != null:
return failed(_that);case StoppedProductSourceStatusReadHeader() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UninitializedProductSourceStatusReadHeader value)  uninitialized,required TResult Function( LoadingProductSourceStatusReadHeader value)  loading,required TResult Function( ReadyProductSourceStatusReadHeader value)  ready,required TResult Function( RefreshingProductSourceStatusReadHeader value)  refreshing,required TResult Function( StaleProductSourceStatusReadHeader value)  stale,required TResult Function( DegradedProductSourceStatusReadHeader value)  degraded,required TResult Function( FailedProductSourceStatusReadHeader value)  failed,required TResult Function( StoppedProductSourceStatusReadHeader value)  stopped,}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader():
return uninitialized(_that);case LoadingProductSourceStatusReadHeader():
return loading(_that);case ReadyProductSourceStatusReadHeader():
return ready(_that);case RefreshingProductSourceStatusReadHeader():
return refreshing(_that);case StaleProductSourceStatusReadHeader():
return stale(_that);case DegradedProductSourceStatusReadHeader():
return degraded(_that);case FailedProductSourceStatusReadHeader():
return failed(_that);case StoppedProductSourceStatusReadHeader():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UninitializedProductSourceStatusReadHeader value)?  uninitialized,TResult? Function( LoadingProductSourceStatusReadHeader value)?  loading,TResult? Function( ReadyProductSourceStatusReadHeader value)?  ready,TResult? Function( RefreshingProductSourceStatusReadHeader value)?  refreshing,TResult? Function( StaleProductSourceStatusReadHeader value)?  stale,TResult? Function( DegradedProductSourceStatusReadHeader value)?  degraded,TResult? Function( FailedProductSourceStatusReadHeader value)?  failed,TResult? Function( StoppedProductSourceStatusReadHeader value)?  stopped,}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader() when uninitialized != null:
return uninitialized(_that);case LoadingProductSourceStatusReadHeader() when loading != null:
return loading(_that);case ReadyProductSourceStatusReadHeader() when ready != null:
return ready(_that);case RefreshingProductSourceStatusReadHeader() when refreshing != null:
return refreshing(_that);case StaleProductSourceStatusReadHeader() when stale != null:
return stale(_that);case DegradedProductSourceStatusReadHeader() when degraded != null:
return degraded(_that);case FailedProductSourceStatusReadHeader() when failed != null:
return failed(_that);case StoppedProductSourceStatusReadHeader() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  uninitialized,TResult Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt)?  loading,TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateErrorRead error)?  degraded,TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateErrorRead error)?  failed,TResult Function( int revision,  int stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatusReadHeader() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatusReadHeader() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatusReadHeader() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatusReadHeader() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatusReadHeader() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatusReadHeader() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatusReadHeader() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  uninitialized,required TResult Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt)  loading,required TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)  ready,required TResult Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt,  int? lastCheckedAt)  refreshing,required TResult Function( int revision,  int staleAt,  int? lastCheckedAt)  stale,required TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateErrorRead error)  degraded,required TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateErrorRead error)  failed,required TResult Function( int revision,  int stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader():
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatusReadHeader():
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatusReadHeader():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatusReadHeader():
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatusReadHeader():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatusReadHeader():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatusReadHeader():
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatusReadHeader():
return stopped(_that.revision,_that.stoppedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  uninitialized,TResult? Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt)?  loading,TResult? Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult? Function( int revision,  StateOperation operation,  ReadText operationId,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult? Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult? Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateErrorRead error)?  degraded,TResult? Function( int revision,  int failedAt,  StateOperation operation,  SourceStateErrorRead error)?  failed,TResult? Function( int revision,  int stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatusReadHeader() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatusReadHeader() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatusReadHeader() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatusReadHeader() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatusReadHeader() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatusReadHeader() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatusReadHeader() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatusReadHeader() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class UninitializedProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const UninitializedProductSourceStatusReadHeader({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UninitializedProductSourceStatusReadHeaderCopyWith<UninitializedProductSourceStatusReadHeader> get copyWith => _$UninitializedProductSourceStatusReadHeaderCopyWithImpl<UninitializedProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UninitializedProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $UninitializedProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $UninitializedProductSourceStatusReadHeaderCopyWith(UninitializedProductSourceStatusReadHeader value, $Res Function(UninitializedProductSourceStatusReadHeader) _then) = _$UninitializedProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$UninitializedProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $UninitializedProductSourceStatusReadHeaderCopyWith<$Res> {
  _$UninitializedProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final UninitializedProductSourceStatusReadHeader _self;
  final $Res Function(UninitializedProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(UninitializedProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class LoadingProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const LoadingProductSourceStatusReadHeader({required this.revision, required this.operation, required this.operationId, required this.startedAt});


@override final  int revision;
 final  StateOperation operation;
 final  ReadText operationId;
 final  int startedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingProductSourceStatusReadHeaderCopyWith<LoadingProductSourceStatusReadHeader> get copyWith => _$LoadingProductSourceStatusReadHeaderCopyWithImpl<LoadingProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt);
}



}

/// @nodoc
abstract mixin class $LoadingProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $LoadingProductSourceStatusReadHeaderCopyWith(LoadingProductSourceStatusReadHeader value, $Res Function(LoadingProductSourceStatusReadHeader) _then) = _$LoadingProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, ReadText operationId, int startedAt
});


$ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$LoadingProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $LoadingProductSourceStatusReadHeaderCopyWith<$Res> {
  _$LoadingProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final LoadingProductSourceStatusReadHeader _self;
  final $Res Function(LoadingProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(LoadingProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class ReadyProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const ReadyProductSourceStatusReadHeader({required this.revision, required this.updatedAt, required this.lastCheckedAt});


@override final  int revision;
 final  int updatedAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyProductSourceStatusReadHeaderCopyWith<ReadyProductSourceStatusReadHeader> get copyWith => _$ReadyProductSourceStatusReadHeaderCopyWithImpl<ReadyProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $ReadyProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $ReadyProductSourceStatusReadHeaderCopyWith(ReadyProductSourceStatusReadHeader value, $Res Function(ReadyProductSourceStatusReadHeader) _then) = _$ReadyProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int? lastCheckedAt
});




}
/// @nodoc
class _$ReadyProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $ReadyProductSourceStatusReadHeaderCopyWith<$Res> {
  _$ReadyProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final ReadyProductSourceStatusReadHeader _self;
  final $Res Function(ReadyProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(ReadyProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class RefreshingProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const RefreshingProductSourceStatusReadHeader({required this.revision, required this.operation, required this.operationId, required this.startedAt, required this.lastCheckedAt});


@override final  int revision;
 final  StateOperation operation;
 final  ReadText operationId;
 final  int startedAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefreshingProductSourceStatusReadHeaderCopyWith<RefreshingProductSourceStatusReadHeader> get copyWith => _$RefreshingProductSourceStatusReadHeaderCopyWithImpl<RefreshingProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RefreshingProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $RefreshingProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $RefreshingProductSourceStatusReadHeaderCopyWith(RefreshingProductSourceStatusReadHeader value, $Res Function(RefreshingProductSourceStatusReadHeader) _then) = _$RefreshingProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, ReadText operationId, int startedAt, int? lastCheckedAt
});


$ReadTextCopyWith<$Res> get operationId;

}
/// @nodoc
class _$RefreshingProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $RefreshingProductSourceStatusReadHeaderCopyWith<$Res> {
  _$RefreshingProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final RefreshingProductSourceStatusReadHeader _self;
  final $Res Function(RefreshingProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(RefreshingProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as ReadText,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ReadTextCopyWith<$Res> get operationId {

  return $ReadTextCopyWith<$Res>(_self.operationId, (value) {
    return _then(_self.copyWith(operationId: value));
  });
}
}

/// @nodoc


class StaleProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const StaleProductSourceStatusReadHeader({required this.revision, required this.staleAt, required this.lastCheckedAt});


@override final  int revision;
 final  int staleAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaleProductSourceStatusReadHeaderCopyWith<StaleProductSourceStatusReadHeader> get copyWith => _$StaleProductSourceStatusReadHeaderCopyWithImpl<StaleProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StaleProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $StaleProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $StaleProductSourceStatusReadHeaderCopyWith(StaleProductSourceStatusReadHeader value, $Res Function(StaleProductSourceStatusReadHeader) _then) = _$StaleProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int staleAt, int? lastCheckedAt
});




}
/// @nodoc
class _$StaleProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $StaleProductSourceStatusReadHeaderCopyWith<$Res> {
  _$StaleProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final StaleProductSourceStatusReadHeader _self;
  final $Res Function(StaleProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(StaleProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const DegradedProductSourceStatusReadHeader({required this.revision, required this.failedAt, required this.lastCheckedAt, required this.operation, required this.error});


@override final  int revision;
 final  int failedAt;
 final  int? lastCheckedAt;
 final  StateOperation operation;
 final  SourceStateErrorRead error;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedProductSourceStatusReadHeaderCopyWith<DegradedProductSourceStatusReadHeader> get copyWith => _$DegradedProductSourceStatusReadHeaderCopyWithImpl<DegradedProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,operation,error);
}



}

/// @nodoc
abstract mixin class $DegradedProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $DegradedProductSourceStatusReadHeaderCopyWith(DegradedProductSourceStatusReadHeader value, $Res Function(DegradedProductSourceStatusReadHeader) _then) = _$DegradedProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, int? lastCheckedAt, StateOperation operation, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$DegradedProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $DegradedProductSourceStatusReadHeaderCopyWith<$Res> {
  _$DegradedProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final DegradedProductSourceStatusReadHeader _self;
  final $Res Function(DegradedProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? operation = null,Object? error = null,}) {
  return _then(DegradedProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class FailedProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const FailedProductSourceStatusReadHeader({required this.revision, required this.failedAt, required this.operation, required this.error});


@override final  int revision;
 final  int failedAt;
 final  StateOperation operation;
 final  SourceStateErrorRead error;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedProductSourceStatusReadHeaderCopyWith<FailedProductSourceStatusReadHeader> get copyWith => _$FailedProductSourceStatusReadHeaderCopyWithImpl<FailedProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,operation,error);
}



}

/// @nodoc
abstract mixin class $FailedProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $FailedProductSourceStatusReadHeaderCopyWith(FailedProductSourceStatusReadHeader value, $Res Function(FailedProductSourceStatusReadHeader) _then) = _$FailedProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, StateOperation operation, SourceStateErrorRead error
});


$SourceStateErrorReadCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $FailedProductSourceStatusReadHeaderCopyWith<$Res> {
  _$FailedProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final FailedProductSourceStatusReadHeader _self;
  final $Res Function(FailedProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? operation = null,Object? error = null,}) {
  return _then(FailedProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateErrorRead,
  ));
}

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorReadCopyWith<$Res> get error {

  return $SourceStateErrorReadCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class StoppedProductSourceStatusReadHeader implements ProductSourceStatusReadHeader {
  const StoppedProductSourceStatusReadHeader({required this.revision, required this.stoppedAt});


@override final  int revision;
 final  int stoppedAt;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedProductSourceStatusReadHeaderCopyWith<StoppedProductSourceStatusReadHeader> get copyWith => _$StoppedProductSourceStatusReadHeaderCopyWithImpl<StoppedProductSourceStatusReadHeader>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedProductSourceStatusReadHeader&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}



}

/// @nodoc
abstract mixin class $StoppedProductSourceStatusReadHeaderCopyWith<$Res> implements $ProductSourceStatusReadHeaderCopyWith<$Res> {
  factory $StoppedProductSourceStatusReadHeaderCopyWith(StoppedProductSourceStatusReadHeader value, $Res Function(StoppedProductSourceStatusReadHeader) _then) = _$StoppedProductSourceStatusReadHeaderCopyWithImpl;
@override @useResult
$Res call({
 int revision, int stoppedAt
});




}
/// @nodoc
class _$StoppedProductSourceStatusReadHeaderCopyWithImpl<$Res>
    implements $StoppedProductSourceStatusReadHeaderCopyWith<$Res> {
  _$StoppedProductSourceStatusReadHeaderCopyWithImpl(this._self, this._then);

  final StoppedProductSourceStatusReadHeader _self;
  final $Res Function(StoppedProductSourceStatusReadHeader) _then;

/// Create a copy of ProductSourceStatusReadHeader
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(StoppedProductSourceStatusReadHeader(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc
mixin _$ProductSourceStatus {

 int get revision;
/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ProductSourceStatusCopyWith<ProductSourceStatus> get copyWith => _$ProductSourceStatusCopyWithImpl<ProductSourceStatus>(this as ProductSourceStatus, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ProductSourceStatus;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ProductSourceStatus&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ProductSourceStatus;
  return Object.hash(runtimeType,_this.revision);
}



}

/// @nodoc
abstract mixin class $ProductSourceStatusCopyWith<$Res>  {
  factory $ProductSourceStatusCopyWith(ProductSourceStatus value, $Res Function(ProductSourceStatus) _then) = _$ProductSourceStatusCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$ProductSourceStatusCopyWithImpl<$Res>
    implements $ProductSourceStatusCopyWith<$Res> {
  _$ProductSourceStatusCopyWithImpl(this._self, this._then);

  final ProductSourceStatus _self;
  final $Res Function(ProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ProductSourceStatus].
extension ProductSourceStatusPatterns on ProductSourceStatus {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UninitializedProductSourceStatus value)?  uninitialized,TResult Function( LoadingProductSourceStatus value)?  loading,TResult Function( ReadyProductSourceStatus value)?  ready,TResult Function( RefreshingProductSourceStatus value)?  refreshing,TResult Function( StaleProductSourceStatus value)?  stale,TResult Function( DegradedProductSourceStatus value)?  degraded,TResult Function( FailedProductSourceStatus value)?  failed,TResult Function( StoppedProductSourceStatus value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatus() when uninitialized != null:
return uninitialized(_that);case LoadingProductSourceStatus() when loading != null:
return loading(_that);case ReadyProductSourceStatus() when ready != null:
return ready(_that);case RefreshingProductSourceStatus() when refreshing != null:
return refreshing(_that);case StaleProductSourceStatus() when stale != null:
return stale(_that);case DegradedProductSourceStatus() when degraded != null:
return degraded(_that);case FailedProductSourceStatus() when failed != null:
return failed(_that);case StoppedProductSourceStatus() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UninitializedProductSourceStatus value)  uninitialized,required TResult Function( LoadingProductSourceStatus value)  loading,required TResult Function( ReadyProductSourceStatus value)  ready,required TResult Function( RefreshingProductSourceStatus value)  refreshing,required TResult Function( StaleProductSourceStatus value)  stale,required TResult Function( DegradedProductSourceStatus value)  degraded,required TResult Function( FailedProductSourceStatus value)  failed,required TResult Function( StoppedProductSourceStatus value)  stopped,}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatus():
return uninitialized(_that);case LoadingProductSourceStatus():
return loading(_that);case ReadyProductSourceStatus():
return ready(_that);case RefreshingProductSourceStatus():
return refreshing(_that);case StaleProductSourceStatus():
return stale(_that);case DegradedProductSourceStatus():
return degraded(_that);case FailedProductSourceStatus():
return failed(_that);case StoppedProductSourceStatus():
return stopped(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UninitializedProductSourceStatus value)?  uninitialized,TResult? Function( LoadingProductSourceStatus value)?  loading,TResult? Function( ReadyProductSourceStatus value)?  ready,TResult? Function( RefreshingProductSourceStatus value)?  refreshing,TResult? Function( StaleProductSourceStatus value)?  stale,TResult? Function( DegradedProductSourceStatus value)?  degraded,TResult? Function( FailedProductSourceStatus value)?  failed,TResult? Function( StoppedProductSourceStatus value)?  stopped,}){
final _that = this;
switch (_that) {
case UninitializedProductSourceStatus() when uninitialized != null:
return uninitialized(_that);case LoadingProductSourceStatus() when loading != null:
return loading(_that);case ReadyProductSourceStatus() when ready != null:
return ready(_that);case RefreshingProductSourceStatus() when refreshing != null:
return refreshing(_that);case StaleProductSourceStatus() when stale != null:
return stale(_that);case DegradedProductSourceStatus() when degraded != null:
return degraded(_that);case FailedProductSourceStatus() when failed != null:
return failed(_that);case StoppedProductSourceStatus() when stopped != null:
return stopped(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  uninitialized,TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt)?  loading,TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error)?  degraded,TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)?  failed,TResult Function( int revision,  int stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatus() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatus() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatus() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatus() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatus() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatus() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatus() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatus() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  uninitialized,required TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt)  loading,required TResult Function( int revision,  int updatedAt,  int? lastCheckedAt)  ready,required TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt)  refreshing,required TResult Function( int revision,  int staleAt,  int? lastCheckedAt)  stale,required TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error)  degraded,required TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)  failed,required TResult Function( int revision,  int stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatus():
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatus():
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatus():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatus():
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatus():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatus():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatus():
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatus():
return stopped(_that.revision,_that.stoppedAt);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  uninitialized,TResult? Function( int revision,  StateOperation operation,  String operationId,  int startedAt)?  loading,TResult? Function( int revision,  int updatedAt,  int? lastCheckedAt)?  ready,TResult? Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt)?  refreshing,TResult? Function( int revision,  int staleAt,  int? lastCheckedAt)?  stale,TResult? Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error)?  degraded,TResult? Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)?  failed,TResult? Function( int revision,  int stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case UninitializedProductSourceStatus() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingProductSourceStatus() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyProductSourceStatus() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt);case RefreshingProductSourceStatus() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt);case StaleProductSourceStatus() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt);case DegradedProductSourceStatus() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error);case FailedProductSourceStatus() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedProductSourceStatus() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class UninitializedProductSourceStatus implements ProductSourceStatus {
  const UninitializedProductSourceStatus({required this.revision, required this.updatedAt});


@override final  int revision;
 final  int updatedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UninitializedProductSourceStatusCopyWith<UninitializedProductSourceStatus> get copyWith => _$UninitializedProductSourceStatusCopyWithImpl<UninitializedProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UninitializedProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $UninitializedProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $UninitializedProductSourceStatusCopyWith(UninitializedProductSourceStatus value, $Res Function(UninitializedProductSourceStatus) _then) = _$UninitializedProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$UninitializedProductSourceStatusCopyWithImpl<$Res>
    implements $UninitializedProductSourceStatusCopyWith<$Res> {
  _$UninitializedProductSourceStatusCopyWithImpl(this._self, this._then);

  final UninitializedProductSourceStatus _self;
  final $Res Function(UninitializedProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(UninitializedProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class LoadingProductSourceStatus implements ProductSourceStatus {
  const LoadingProductSourceStatus({required this.revision, required this.operation, required this.operationId, required this.startedAt});


@override final  int revision;
 final  StateOperation operation;
 final  String operationId;
 final  int startedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingProductSourceStatusCopyWith<LoadingProductSourceStatus> get copyWith => _$LoadingProductSourceStatusCopyWithImpl<LoadingProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt);
}



}

/// @nodoc
abstract mixin class $LoadingProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $LoadingProductSourceStatusCopyWith(LoadingProductSourceStatus value, $Res Function(LoadingProductSourceStatus) _then) = _$LoadingProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, String operationId, int startedAt
});




}
/// @nodoc
class _$LoadingProductSourceStatusCopyWithImpl<$Res>
    implements $LoadingProductSourceStatusCopyWith<$Res> {
  _$LoadingProductSourceStatusCopyWithImpl(this._self, this._then);

  final LoadingProductSourceStatus _self;
  final $Res Function(LoadingProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(LoadingProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReadyProductSourceStatus implements ProductSourceStatus {
  const ReadyProductSourceStatus({required this.revision, required this.updatedAt, required this.lastCheckedAt});


@override final  int revision;
 final  int updatedAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyProductSourceStatusCopyWith<ReadyProductSourceStatus> get copyWith => _$ReadyProductSourceStatusCopyWithImpl<ReadyProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $ReadyProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $ReadyProductSourceStatusCopyWith(ReadyProductSourceStatus value, $Res Function(ReadyProductSourceStatus) _then) = _$ReadyProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int? lastCheckedAt
});




}
/// @nodoc
class _$ReadyProductSourceStatusCopyWithImpl<$Res>
    implements $ReadyProductSourceStatusCopyWith<$Res> {
  _$ReadyProductSourceStatusCopyWithImpl(this._self, this._then);

  final ReadyProductSourceStatus _self;
  final $Res Function(ReadyProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(ReadyProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class RefreshingProductSourceStatus implements ProductSourceStatus {
  const RefreshingProductSourceStatus({required this.revision, required this.operation, required this.operationId, required this.startedAt, required this.lastCheckedAt});


@override final  int revision;
 final  StateOperation operation;
 final  String operationId;
 final  int startedAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefreshingProductSourceStatusCopyWith<RefreshingProductSourceStatus> get copyWith => _$RefreshingProductSourceStatusCopyWithImpl<RefreshingProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RefreshingProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $RefreshingProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $RefreshingProductSourceStatusCopyWith(RefreshingProductSourceStatus value, $Res Function(RefreshingProductSourceStatus) _then) = _$RefreshingProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, String operationId, int startedAt, int? lastCheckedAt
});




}
/// @nodoc
class _$RefreshingProductSourceStatusCopyWithImpl<$Res>
    implements $RefreshingProductSourceStatusCopyWith<$Res> {
  _$RefreshingProductSourceStatusCopyWithImpl(this._self, this._then);

  final RefreshingProductSourceStatus _self;
  final $Res Function(RefreshingProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(RefreshingProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class StaleProductSourceStatus implements ProductSourceStatus {
  const StaleProductSourceStatus({required this.revision, required this.staleAt, required this.lastCheckedAt});


@override final  int revision;
 final  int staleAt;
 final  int? lastCheckedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaleProductSourceStatusCopyWith<StaleProductSourceStatus> get copyWith => _$StaleProductSourceStatusCopyWithImpl<StaleProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StaleProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt);
}



}

/// @nodoc
abstract mixin class $StaleProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $StaleProductSourceStatusCopyWith(StaleProductSourceStatus value, $Res Function(StaleProductSourceStatus) _then) = _$StaleProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int staleAt, int? lastCheckedAt
});




}
/// @nodoc
class _$StaleProductSourceStatusCopyWithImpl<$Res>
    implements $StaleProductSourceStatusCopyWith<$Res> {
  _$StaleProductSourceStatusCopyWithImpl(this._self, this._then);

  final StaleProductSourceStatus _self;
  final $Res Function(StaleProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,}) {
  return _then(StaleProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

/// @nodoc


class DegradedProductSourceStatus implements ProductSourceStatus {
  const DegradedProductSourceStatus({required this.revision, required this.failedAt, required this.lastCheckedAt, required this.operation, required this.error});


@override final  int revision;
 final  int failedAt;
 final  int? lastCheckedAt;
 final  StateOperation operation;
 final  SourceStateError error;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedProductSourceStatusCopyWith<DegradedProductSourceStatus> get copyWith => _$DegradedProductSourceStatusCopyWithImpl<DegradedProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,operation,error);
}



}

/// @nodoc
abstract mixin class $DegradedProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $DegradedProductSourceStatusCopyWith(DegradedProductSourceStatus value, $Res Function(DegradedProductSourceStatus) _then) = _$DegradedProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, int? lastCheckedAt, StateOperation operation, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$DegradedProductSourceStatusCopyWithImpl<$Res>
    implements $DegradedProductSourceStatusCopyWith<$Res> {
  _$DegradedProductSourceStatusCopyWithImpl(this._self, this._then);

  final DegradedProductSourceStatus _self;
  final $Res Function(DegradedProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? operation = null,Object? error = null,}) {
  return _then(DegradedProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class FailedProductSourceStatus implements ProductSourceStatus {
  const FailedProductSourceStatus({required this.revision, required this.failedAt, required this.operation, required this.error});


@override final  int revision;
 final  int failedAt;
 final  StateOperation operation;
 final  SourceStateError error;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedProductSourceStatusCopyWith<FailedProductSourceStatus> get copyWith => _$FailedProductSourceStatusCopyWithImpl<FailedProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,operation,error);
}



}

/// @nodoc
abstract mixin class $FailedProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $FailedProductSourceStatusCopyWith(FailedProductSourceStatus value, $Res Function(FailedProductSourceStatus) _then) = _$FailedProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, StateOperation operation, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedProductSourceStatusCopyWithImpl<$Res>
    implements $FailedProductSourceStatusCopyWith<$Res> {
  _$FailedProductSourceStatusCopyWithImpl(this._self, this._then);

  final FailedProductSourceStatus _self;
  final $Res Function(FailedProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? operation = null,Object? error = null,}) {
  return _then(FailedProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<$Res> get error {

  return $SourceStateErrorCopyWith<$Res>(_self.error, (value) {
    return _then(_self.copyWith(error: value));
  });
}
}

/// @nodoc


class StoppedProductSourceStatus implements ProductSourceStatus {
  const StoppedProductSourceStatus({required this.revision, required this.stoppedAt});


@override final  int revision;
 final  int stoppedAt;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedProductSourceStatusCopyWith<StoppedProductSourceStatus> get copyWith => _$StoppedProductSourceStatusCopyWithImpl<StoppedProductSourceStatus>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedProductSourceStatus&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}



}

/// @nodoc
abstract mixin class $StoppedProductSourceStatusCopyWith<$Res> implements $ProductSourceStatusCopyWith<$Res> {
  factory $StoppedProductSourceStatusCopyWith(StoppedProductSourceStatus value, $Res Function(StoppedProductSourceStatus) _then) = _$StoppedProductSourceStatusCopyWithImpl;
@override @useResult
$Res call({
 int revision, int stoppedAt
});




}
/// @nodoc
class _$StoppedProductSourceStatusCopyWithImpl<$Res>
    implements $StoppedProductSourceStatusCopyWith<$Res> {
  _$StoppedProductSourceStatusCopyWithImpl(this._self, this._then);

  final StoppedProductSourceStatus _self;
  final $Res Function(StoppedProductSourceStatus) _then;

/// Create a copy of ProductSourceStatus
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(StoppedProductSourceStatus(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
