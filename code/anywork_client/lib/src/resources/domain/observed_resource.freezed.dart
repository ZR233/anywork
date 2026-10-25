// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'observed_resource.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SourceStateError {

 String get code; String get message; bool get retryable;
/// Create a copy of SourceStateError
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SourceStateErrorCopyWith<SourceStateError> get copyWith => _$SourceStateErrorCopyWithImpl<SourceStateError>(this as SourceStateError, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SourceStateError;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SourceStateError&&(identical(other.code, _this.code) || other.code == _this.code)&&(identical(other.message, _this.message) || other.message == _this.message)&&(identical(other.retryable, _this.retryable) || other.retryable == _this.retryable));
}


@override
int get hashCode {
  final _this = this as SourceStateError;
  return Object.hash(runtimeType,_this.code,_this.message,_this.retryable);
}



}

/// @nodoc
abstract mixin class $SourceStateErrorCopyWith<$Res>  {
  factory $SourceStateErrorCopyWith(SourceStateError value, $Res Function(SourceStateError) _then) = _$SourceStateErrorCopyWithImpl;
@useResult
$Res call({
 String code, String message, bool retryable
});




}
/// @nodoc
class _$SourceStateErrorCopyWithImpl<$Res>
    implements $SourceStateErrorCopyWith<$Res> {
  _$SourceStateErrorCopyWithImpl(this._self, this._then);

  final SourceStateError _self;
  final $Res Function(SourceStateError) _then;

/// Create a copy of SourceStateError
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(SourceStateError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

}


/// Adds pattern-matching-related methods to [SourceStateError].
extension SourceStateErrorPatterns on SourceStateError {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _SourceStateError value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SourceStateError() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _SourceStateError value)  $default,){
final _that = this;
switch (_that) {
case _SourceStateError():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _SourceStateError value)?  $default,){
final _that = this;
switch (_that) {
case _SourceStateError() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String code,  String message,  bool retryable)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SourceStateError() when $default != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String code,  String message,  bool retryable)  $default,) {final _that = this;
switch (_that) {
case _SourceStateError():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String code,  String message,  bool retryable)?  $default,) {final _that = this;
switch (_that) {
case _SourceStateError() when $default != null:
return $default(_that.code,_that.message,_that.retryable);case _:
  return null;

}
}

}

/// @nodoc


class _SourceStateError implements SourceStateError {
  const _SourceStateError({required this.code, required this.message, required this.retryable});


@override final  String code;
@override final  String message;
@override final  bool retryable;

/// Create a copy of SourceStateError
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SourceStateErrorCopyWith<_SourceStateError> get copyWith => __$SourceStateErrorCopyWithImpl<_SourceStateError>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _SourceStateError&&(identical(other.code, code) || other.code == code)&&(identical(other.message, message) || other.message == message)&&(identical(other.retryable, retryable) || other.retryable == retryable));
}


@override
int get hashCode {
    return Object.hash(runtimeType,code,message,retryable);
}



}

/// @nodoc
abstract mixin class _$SourceStateErrorCopyWith<$Res> implements $SourceStateErrorCopyWith<$Res> {
  factory _$SourceStateErrorCopyWith(_SourceStateError value, $Res Function(_SourceStateError) _then) = __$SourceStateErrorCopyWithImpl;
@override @useResult
$Res call({
 String code, String message, bool retryable
});




}
/// @nodoc
class __$SourceStateErrorCopyWithImpl<$Res>
    implements _$SourceStateErrorCopyWith<$Res> {
  __$SourceStateErrorCopyWithImpl(this._self, this._then);

  final _SourceStateError _self;
  final $Res Function(_SourceStateError) _then;

/// Create a copy of SourceStateError
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? code = null,Object? message = null,Object? retryable = null,}) {
  return _then(_SourceStateError(
code: null == code ? _self.code : code // ignore: cast_nullable_to_non_nullable
as String,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,retryable: null == retryable ? _self.retryable : retryable // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}


}

/// @nodoc
mixin _$ObservedResource<T> {

 int get revision;
/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ObservedResourceCopyWith<T, ObservedResource<T>> get copyWith => _$ObservedResourceCopyWithImpl<T, ObservedResource<T>>(this as ObservedResource<T>, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ObservedResource<T>;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ObservedResource<T>&&(identical(other.revision, _this.revision) || other.revision == _this.revision));
}


@override
int get hashCode {
  final _this = this as ObservedResource<T>;
  return Object.hash(runtimeType,_this.revision);
}



}

/// @nodoc
abstract mixin class $ObservedResourceCopyWith<T,$Res>  {
  factory $ObservedResourceCopyWith(ObservedResource<T> value, $Res Function(ObservedResource<T>) _then) = _$ObservedResourceCopyWithImpl;
@useResult
$Res call({
 int revision
});




}
/// @nodoc
class _$ObservedResourceCopyWithImpl<T,$Res>
    implements $ObservedResourceCopyWith<T, $Res> {
  _$ObservedResourceCopyWithImpl(this._self, this._then);

  final ObservedResource<T> _self;
  final $Res Function(ObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? revision = null,}) {
  return _then(_self.copyWith(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,
  ));
}

}


/// Adds pattern-matching-related methods to [ObservedResource].
extension ObservedResourcePatterns<T> on ObservedResource<T> {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( UninitializedObservedResource<T> value)?  uninitialized,TResult Function( LoadingObservedResource<T> value)?  loading,TResult Function( ReadyObservedResource<T> value)?  ready,TResult Function( RefreshingObservedResource<T> value)?  refreshing,TResult Function( StaleObservedResource<T> value)?  stale,TResult Function( DegradedObservedResource<T> value)?  degraded,TResult Function( FailedObservedResource<T> value)?  failed,TResult Function( StoppedObservedResource<T> value)?  stopped,required TResult orElse(),}){
final _that = this;
switch (_that) {
case UninitializedObservedResource() when uninitialized != null:
return uninitialized(_that);case LoadingObservedResource() when loading != null:
return loading(_that);case ReadyObservedResource() when ready != null:
return ready(_that);case RefreshingObservedResource() when refreshing != null:
return refreshing(_that);case StaleObservedResource() when stale != null:
return stale(_that);case DegradedObservedResource() when degraded != null:
return degraded(_that);case FailedObservedResource() when failed != null:
return failed(_that);case StoppedObservedResource() when stopped != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( UninitializedObservedResource<T> value)  uninitialized,required TResult Function( LoadingObservedResource<T> value)  loading,required TResult Function( ReadyObservedResource<T> value)  ready,required TResult Function( RefreshingObservedResource<T> value)  refreshing,required TResult Function( StaleObservedResource<T> value)  stale,required TResult Function( DegradedObservedResource<T> value)  degraded,required TResult Function( FailedObservedResource<T> value)  failed,required TResult Function( StoppedObservedResource<T> value)  stopped,}){
final _that = this;
switch (_that) {
case UninitializedObservedResource():
return uninitialized(_that);case LoadingObservedResource():
return loading(_that);case ReadyObservedResource():
return ready(_that);case RefreshingObservedResource():
return refreshing(_that);case StaleObservedResource():
return stale(_that);case DegradedObservedResource():
return degraded(_that);case FailedObservedResource():
return failed(_that);case StoppedObservedResource():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( UninitializedObservedResource<T> value)?  uninitialized,TResult? Function( LoadingObservedResource<T> value)?  loading,TResult? Function( ReadyObservedResource<T> value)?  ready,TResult? Function( RefreshingObservedResource<T> value)?  refreshing,TResult? Function( StaleObservedResource<T> value)?  stale,TResult? Function( DegradedObservedResource<T> value)?  degraded,TResult? Function( FailedObservedResource<T> value)?  failed,TResult? Function( StoppedObservedResource<T> value)?  stopped,}){
final _that = this;
switch (_that) {
case UninitializedObservedResource() when uninitialized != null:
return uninitialized(_that);case LoadingObservedResource() when loading != null:
return loading(_that);case ReadyObservedResource() when ready != null:
return ready(_that);case RefreshingObservedResource() when refreshing != null:
return refreshing(_that);case StaleObservedResource() when stale != null:
return stale(_that);case DegradedObservedResource() when degraded != null:
return degraded(_that);case FailedObservedResource() when failed != null:
return failed(_that);case StoppedObservedResource() when stopped != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int revision,  int updatedAt)?  uninitialized,TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt)?  loading,TResult Function( int revision,  int updatedAt,  int? lastCheckedAt,  T value)?  ready,TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt,  T value)?  refreshing,TResult Function( int revision,  int staleAt,  int? lastCheckedAt,  T value)?  stale,TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error,  T value)?  degraded,TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)?  failed,TResult Function( int revision,  int stoppedAt)?  stopped,required TResult orElse(),}) {final _that = this;
switch (_that) {
case UninitializedObservedResource() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedResource() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyObservedResource() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt,_that.value);case RefreshingObservedResource() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt,_that.value);case StaleObservedResource() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt,_that.value);case DegradedObservedResource() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error,_that.value);case FailedObservedResource() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedObservedResource() when stopped != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int revision,  int updatedAt)  uninitialized,required TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt)  loading,required TResult Function( int revision,  int updatedAt,  int? lastCheckedAt,  T value)  ready,required TResult Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt,  T value)  refreshing,required TResult Function( int revision,  int staleAt,  int? lastCheckedAt,  T value)  stale,required TResult Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error,  T value)  degraded,required TResult Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)  failed,required TResult Function( int revision,  int stoppedAt)  stopped,}) {final _that = this;
switch (_that) {
case UninitializedObservedResource():
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedResource():
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyObservedResource():
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt,_that.value);case RefreshingObservedResource():
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt,_that.value);case StaleObservedResource():
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt,_that.value);case DegradedObservedResource():
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error,_that.value);case FailedObservedResource():
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedObservedResource():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int revision,  int updatedAt)?  uninitialized,TResult? Function( int revision,  StateOperation operation,  String operationId,  int startedAt)?  loading,TResult? Function( int revision,  int updatedAt,  int? lastCheckedAt,  T value)?  ready,TResult? Function( int revision,  StateOperation operation,  String operationId,  int startedAt,  int? lastCheckedAt,  T value)?  refreshing,TResult? Function( int revision,  int staleAt,  int? lastCheckedAt,  T value)?  stale,TResult? Function( int revision,  int failedAt,  int? lastCheckedAt,  StateOperation operation,  SourceStateError error,  T value)?  degraded,TResult? Function( int revision,  int failedAt,  StateOperation operation,  SourceStateError error)?  failed,TResult? Function( int revision,  int stoppedAt)?  stopped,}) {final _that = this;
switch (_that) {
case UninitializedObservedResource() when uninitialized != null:
return uninitialized(_that.revision,_that.updatedAt);case LoadingObservedResource() when loading != null:
return loading(_that.revision,_that.operation,_that.operationId,_that.startedAt);case ReadyObservedResource() when ready != null:
return ready(_that.revision,_that.updatedAt,_that.lastCheckedAt,_that.value);case RefreshingObservedResource() when refreshing != null:
return refreshing(_that.revision,_that.operation,_that.operationId,_that.startedAt,_that.lastCheckedAt,_that.value);case StaleObservedResource() when stale != null:
return stale(_that.revision,_that.staleAt,_that.lastCheckedAt,_that.value);case DegradedObservedResource() when degraded != null:
return degraded(_that.revision,_that.failedAt,_that.lastCheckedAt,_that.operation,_that.error,_that.value);case FailedObservedResource() when failed != null:
return failed(_that.revision,_that.failedAt,_that.operation,_that.error);case StoppedObservedResource() when stopped != null:
return stopped(_that.revision,_that.stoppedAt);case _:
  return null;

}
}

}

/// @nodoc


class UninitializedObservedResource<T> extends ObservedResource<T> {
  const UninitializedObservedResource({required this.revision, required this.updatedAt}): super._();


@override final  int revision;
 final  int updatedAt;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$UninitializedObservedResourceCopyWith<T, UninitializedObservedResource<T>> get copyWith => _$UninitializedObservedResourceCopyWithImpl<T, UninitializedObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is UninitializedObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt);
}



}

/// @nodoc
abstract mixin class $UninitializedObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $UninitializedObservedResourceCopyWith(UninitializedObservedResource<T> value, $Res Function(UninitializedObservedResource<T>) _then) = _$UninitializedObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt
});




}
/// @nodoc
class _$UninitializedObservedResourceCopyWithImpl<T,$Res>
    implements $UninitializedObservedResourceCopyWith<T, $Res> {
  _$UninitializedObservedResourceCopyWithImpl(this._self, this._then);

  final UninitializedObservedResource<T> _self;
  final $Res Function(UninitializedObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,}) {
  return _then(UninitializedObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class LoadingObservedResource<T> extends ObservedResource<T> {
  const LoadingObservedResource({required this.revision, required this.operation, required this.operationId, required this.startedAt}): super._();


@override final  int revision;
 final  StateOperation operation;
 final  String operationId;
 final  int startedAt;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$LoadingObservedResourceCopyWith<T, LoadingObservedResource<T>> get copyWith => _$LoadingObservedResourceCopyWithImpl<T, LoadingObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is LoadingObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt);
}



}

/// @nodoc
abstract mixin class $LoadingObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $LoadingObservedResourceCopyWith(LoadingObservedResource<T> value, $Res Function(LoadingObservedResource<T>) _then) = _$LoadingObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, String operationId, int startedAt
});




}
/// @nodoc
class _$LoadingObservedResourceCopyWithImpl<T,$Res>
    implements $LoadingObservedResourceCopyWith<T, $Res> {
  _$LoadingObservedResourceCopyWithImpl(this._self, this._then);

  final LoadingObservedResource<T> _self;
  final $Res Function(LoadingObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,}) {
  return _then(LoadingObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

/// @nodoc


class ReadyObservedResource<T> extends ObservedResource<T> {
  const ReadyObservedResource({required this.revision, required this.updatedAt, required this.lastCheckedAt, required this.value}): super._();


@override final  int revision;
 final  int updatedAt;
 final  int? lastCheckedAt;
 final  T value;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ReadyObservedResourceCopyWith<T, ReadyObservedResource<T>> get copyWith => _$ReadyObservedResourceCopyWithImpl<T, ReadyObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ReadyObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.updatedAt, updatedAt) || other.updatedAt == updatedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,updatedAt,lastCheckedAt,const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class $ReadyObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $ReadyObservedResourceCopyWith(ReadyObservedResource<T> value, $Res Function(ReadyObservedResource<T>) _then) = _$ReadyObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int updatedAt, int? lastCheckedAt, T value
});




}
/// @nodoc
class _$ReadyObservedResourceCopyWithImpl<T,$Res>
    implements $ReadyObservedResourceCopyWith<T, $Res> {
  _$ReadyObservedResourceCopyWithImpl(this._self, this._then);

  final ReadyObservedResource<T> _self;
  final $Res Function(ReadyObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? updatedAt = null,Object? lastCheckedAt = freezed,Object? value = freezed,}) {
  return _then(ReadyObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class RefreshingObservedResource<T> extends ObservedResource<T> {
  const RefreshingObservedResource({required this.revision, required this.operation, required this.operationId, required this.startedAt, required this.lastCheckedAt, required this.value}): super._();


@override final  int revision;
 final  StateOperation operation;
 final  String operationId;
 final  int startedAt;
 final  int? lastCheckedAt;
 final  T value;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$RefreshingObservedResourceCopyWith<T, RefreshingObservedResource<T>> get copyWith => _$RefreshingObservedResourceCopyWithImpl<T, RefreshingObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is RefreshingObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.operationId, operationId) || other.operationId == operationId)&&(identical(other.startedAt, startedAt) || other.startedAt == startedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,operation,operationId,startedAt,lastCheckedAt,const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class $RefreshingObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $RefreshingObservedResourceCopyWith(RefreshingObservedResource<T> value, $Res Function(RefreshingObservedResource<T>) _then) = _$RefreshingObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, StateOperation operation, String operationId, int startedAt, int? lastCheckedAt, T value
});




}
/// @nodoc
class _$RefreshingObservedResourceCopyWithImpl<T,$Res>
    implements $RefreshingObservedResourceCopyWith<T, $Res> {
  _$RefreshingObservedResourceCopyWithImpl(this._self, this._then);

  final RefreshingObservedResource<T> _self;
  final $Res Function(RefreshingObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? operation = null,Object? operationId = null,Object? startedAt = null,Object? lastCheckedAt = freezed,Object? value = freezed,}) {
  return _then(RefreshingObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,operationId: null == operationId ? _self.operationId : operationId // ignore: cast_nullable_to_non_nullable
as String,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class StaleObservedResource<T> extends ObservedResource<T> {
  const StaleObservedResource({required this.revision, required this.staleAt, required this.lastCheckedAt, required this.value}): super._();


@override final  int revision;
 final  int staleAt;
 final  int? lastCheckedAt;
 final  T value;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StaleObservedResourceCopyWith<T, StaleObservedResource<T>> get copyWith => _$StaleObservedResourceCopyWithImpl<T, StaleObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StaleObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.staleAt, staleAt) || other.staleAt == staleAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,staleAt,lastCheckedAt,const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class $StaleObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $StaleObservedResourceCopyWith(StaleObservedResource<T> value, $Res Function(StaleObservedResource<T>) _then) = _$StaleObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int staleAt, int? lastCheckedAt, T value
});




}
/// @nodoc
class _$StaleObservedResourceCopyWithImpl<T,$Res>
    implements $StaleObservedResourceCopyWith<T, $Res> {
  _$StaleObservedResourceCopyWithImpl(this._self, this._then);

  final StaleObservedResource<T> _self;
  final $Res Function(StaleObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? staleAt = null,Object? lastCheckedAt = freezed,Object? value = freezed,}) {
  return _then(StaleObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,staleAt: null == staleAt ? _self.staleAt : staleAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}


}

/// @nodoc


class DegradedObservedResource<T> extends ObservedResource<T> {
  const DegradedObservedResource({required this.revision, required this.failedAt, required this.lastCheckedAt, required this.operation, required this.error, required this.value}): super._();


@override final  int revision;
 final  int failedAt;
 final  int? lastCheckedAt;
 final  StateOperation operation;
 final  SourceStateError error;
 final  T value;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$DegradedObservedResourceCopyWith<T, DegradedObservedResource<T>> get copyWith => _$DegradedObservedResourceCopyWithImpl<T, DegradedObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is DegradedObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.lastCheckedAt, lastCheckedAt) || other.lastCheckedAt == lastCheckedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error)&&const DeepCollectionEquality().equals(other.value, value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,lastCheckedAt,operation,error,const DeepCollectionEquality().hash(value));
}



}

/// @nodoc
abstract mixin class $DegradedObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $DegradedObservedResourceCopyWith(DegradedObservedResource<T> value, $Res Function(DegradedObservedResource<T>) _then) = _$DegradedObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, int? lastCheckedAt, StateOperation operation, SourceStateError error, T value
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$DegradedObservedResourceCopyWithImpl<T,$Res>
    implements $DegradedObservedResourceCopyWith<T, $Res> {
  _$DegradedObservedResourceCopyWithImpl(this._self, this._then);

  final DegradedObservedResource<T> _self;
  final $Res Function(DegradedObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? lastCheckedAt = freezed,Object? operation = null,Object? error = null,Object? value = freezed,}) {
  return _then(DegradedObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,lastCheckedAt: freezed == lastCheckedAt ? _self.lastCheckedAt : lastCheckedAt // ignore: cast_nullable_to_non_nullable
as int?,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as T,
  ));
}

/// Create a copy of ObservedResource
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


class FailedObservedResource<T> extends ObservedResource<T> {
  const FailedObservedResource({required this.revision, required this.failedAt, required this.operation, required this.error}): super._();


@override final  int revision;
 final  int failedAt;
 final  StateOperation operation;
 final  SourceStateError error;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FailedObservedResourceCopyWith<T, FailedObservedResource<T>> get copyWith => _$FailedObservedResourceCopyWithImpl<T, FailedObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is FailedObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.failedAt, failedAt) || other.failedAt == failedAt)&&(identical(other.operation, operation) || other.operation == operation)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,failedAt,operation,error);
}



}

/// @nodoc
abstract mixin class $FailedObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $FailedObservedResourceCopyWith(FailedObservedResource<T> value, $Res Function(FailedObservedResource<T>) _then) = _$FailedObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int failedAt, StateOperation operation, SourceStateError error
});


$SourceStateErrorCopyWith<$Res> get error;

}
/// @nodoc
class _$FailedObservedResourceCopyWithImpl<T,$Res>
    implements $FailedObservedResourceCopyWith<T, $Res> {
  _$FailedObservedResourceCopyWithImpl(this._self, this._then);

  final FailedObservedResource<T> _self;
  final $Res Function(FailedObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? failedAt = null,Object? operation = null,Object? error = null,}) {
  return _then(FailedObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,failedAt: null == failedAt ? _self.failedAt : failedAt // ignore: cast_nullable_to_non_nullable
as int,operation: null == operation ? _self.operation : operation // ignore: cast_nullable_to_non_nullable
as StateOperation,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as SourceStateError,
  ));
}

/// Create a copy of ObservedResource
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


class StoppedObservedResource<T> extends ObservedResource<T> {
  const StoppedObservedResource({required this.revision, required this.stoppedAt}): super._();


@override final  int revision;
 final  int stoppedAt;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$StoppedObservedResourceCopyWith<T, StoppedObservedResource<T>> get copyWith => _$StoppedObservedResourceCopyWithImpl<T, StoppedObservedResource<T>>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is StoppedObservedResource<T>&&(identical(other.revision, revision) || other.revision == revision)&&(identical(other.stoppedAt, stoppedAt) || other.stoppedAt == stoppedAt));
}


@override
int get hashCode {
    return Object.hash(runtimeType,revision,stoppedAt);
}



}

/// @nodoc
abstract mixin class $StoppedObservedResourceCopyWith<T,$Res> implements $ObservedResourceCopyWith<T, $Res> {
  factory $StoppedObservedResourceCopyWith(StoppedObservedResource<T> value, $Res Function(StoppedObservedResource<T>) _then) = _$StoppedObservedResourceCopyWithImpl;
@override @useResult
$Res call({
 int revision, int stoppedAt
});




}
/// @nodoc
class _$StoppedObservedResourceCopyWithImpl<T,$Res>
    implements $StoppedObservedResourceCopyWith<T, $Res> {
  _$StoppedObservedResourceCopyWithImpl(this._self, this._then);

  final StoppedObservedResource<T> _self;
  final $Res Function(StoppedObservedResource<T>) _then;

/// Create a copy of ObservedResource
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? revision = null,Object? stoppedAt = null,}) {
  return _then(StoppedObservedResource<T>(
revision: null == revision ? _self.revision : revision // ignore: cast_nullable_to_non_nullable
as int,stoppedAt: null == stoppedAt ? _self.stoppedAt : stoppedAt // ignore: cast_nullable_to_non_nullable
as int,
  ));
}


}

// dart format on
