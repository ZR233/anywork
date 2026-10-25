// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'facet_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FacetSyncState {

 FacetSyncPhase get phase; StudioFailure? get error; bool get retryExhausted;
/// Create a copy of FacetSyncState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<FacetSyncState> get copyWith => _$FacetSyncStateCopyWithImpl<FacetSyncState>(this as FacetSyncState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as FacetSyncState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is FacetSyncState&&(identical(other.phase, _this.phase) || other.phase == _this.phase)&&(identical(other.error, _this.error) || other.error == _this.error)&&(identical(other.retryExhausted, _this.retryExhausted) || other.retryExhausted == _this.retryExhausted));
}


@override
int get hashCode {
  final _this = this as FacetSyncState;
  return Object.hash(runtimeType,_this.phase,_this.error,_this.retryExhausted);
}



}

/// @nodoc
abstract mixin class $FacetSyncStateCopyWith<$Res>  {
  factory $FacetSyncStateCopyWith(FacetSyncState value, $Res Function(FacetSyncState) _then) = _$FacetSyncStateCopyWithImpl;
@useResult
$Res call({
 FacetSyncPhase phase, StudioFailure? error, bool retryExhausted
});


$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$FacetSyncStateCopyWithImpl<$Res>
    implements $FacetSyncStateCopyWith<$Res> {
  _$FacetSyncStateCopyWithImpl(this._self, this._then);

  final FacetSyncState _self;
  final $Res Function(FacetSyncState) _then;

/// Create a copy of FacetSyncState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? phase = null,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(FacetSyncState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as FacetSyncPhase,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}
/// Create a copy of FacetSyncState
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


/// Adds pattern-matching-related methods to [FacetSyncState].
extension FacetSyncStatePatterns on FacetSyncState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _FacetSyncState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FacetSyncState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _FacetSyncState value)  $default,){
final _that = this;
switch (_that) {
case _FacetSyncState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _FacetSyncState value)?  $default,){
final _that = this;
switch (_that) {
case _FacetSyncState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( FacetSyncPhase phase,  StudioFailure? error,  bool retryExhausted)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FacetSyncState() when $default != null:
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( FacetSyncPhase phase,  StudioFailure? error,  bool retryExhausted)  $default,) {final _that = this;
switch (_that) {
case _FacetSyncState():
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( FacetSyncPhase phase,  StudioFailure? error,  bool retryExhausted)?  $default,) {final _that = this;
switch (_that) {
case _FacetSyncState() when $default != null:
return $default(_that.phase,_that.error,_that.retryExhausted);case _:
  return null;

}
}

}

/// @nodoc


class _FacetSyncState implements FacetSyncState {
  const _FacetSyncState({required this.phase, this.error, this.retryExhausted = false});


@override final  FacetSyncPhase phase;
@override final  StudioFailure? error;
@override@JsonKey() final  bool retryExhausted;

/// Create a copy of FacetSyncState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FacetSyncStateCopyWith<_FacetSyncState> get copyWith => __$FacetSyncStateCopyWithImpl<_FacetSyncState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _FacetSyncState&&(identical(other.phase, phase) || other.phase == phase)&&(identical(other.error, error) || other.error == error)&&(identical(other.retryExhausted, retryExhausted) || other.retryExhausted == retryExhausted));
}


@override
int get hashCode {
    return Object.hash(runtimeType,phase,error,retryExhausted);
}



}

/// @nodoc
abstract mixin class _$FacetSyncStateCopyWith<$Res> implements $FacetSyncStateCopyWith<$Res> {
  factory _$FacetSyncStateCopyWith(_FacetSyncState value, $Res Function(_FacetSyncState) _then) = __$FacetSyncStateCopyWithImpl;
@override @useResult
$Res call({
 FacetSyncPhase phase, StudioFailure? error, bool retryExhausted
});


@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$FacetSyncStateCopyWithImpl<$Res>
    implements _$FacetSyncStateCopyWith<$Res> {
  __$FacetSyncStateCopyWithImpl(this._self, this._then);

  final _FacetSyncState _self;
  final $Res Function(_FacetSyncState) _then;

/// Create a copy of FacetSyncState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? phase = null,Object? error = freezed,Object? retryExhausted = null,}) {
  return _then(_FacetSyncState(
phase: null == phase ? _self.phase : phase // ignore: cast_nullable_to_non_nullable
as FacetSyncPhase,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,retryExhausted: null == retryExhausted ? _self.retryExhausted : retryExhausted // ignore: cast_nullable_to_non_nullable
as bool,
  ));
}

/// Create a copy of FacetSyncState
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
mixin _$ThreadExecutionState {

 ThreadFacetStamp? get stamp; FacetSyncState get sync; ThreadExecutionBaseline? get value;
/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionStateCopyWith<ThreadExecutionState> get copyWith => _$ThreadExecutionStateCopyWithImpl<ThreadExecutionState>(this as ThreadExecutionState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadExecutionState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.sync, _this.sync) || other.sync == _this.sync)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadExecutionState;
  return Object.hash(runtimeType,_this.stamp,_this.sync,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionStateCopyWith<$Res>  {
  factory $ThreadExecutionStateCopyWith(ThreadExecutionState value, $Res Function(ThreadExecutionState) _then) = _$ThreadExecutionStateCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadExecutionBaseline? value
});


$ThreadFacetStampCopyWith<$Res>? get stamp;$FacetSyncStateCopyWith<$Res> get sync;$ThreadExecutionBaselineCopyWith<$Res>? get value;

}
/// @nodoc
class _$ThreadExecutionStateCopyWithImpl<$Res>
    implements $ThreadExecutionStateCopyWith<$Res> {
  _$ThreadExecutionStateCopyWithImpl(this._self, this._then);

  final ThreadExecutionState _self;
  final $Res Function(ThreadExecutionState) _then;

/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(ThreadExecutionState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadExecutionBaseline?,
  ));
}
/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionBaselineCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadExecutionBaselineCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadExecutionState].
extension ThreadExecutionStatePatterns on ThreadExecutionState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadExecutionState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadExecutionState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadExecutionState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadExecutionState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadExecutionState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadExecutionBaseline? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadExecutionState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadExecutionBaseline? value)  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionState():
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadExecutionBaseline? value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadExecutionState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadExecutionState implements ThreadExecutionState {
  const _ThreadExecutionState({this.stamp, required this.sync, this.value});


@override final  ThreadFacetStamp? stamp;
@override final  FacetSyncState sync;
@override final  ThreadExecutionBaseline? value;

/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadExecutionStateCopyWith<_ThreadExecutionState> get copyWith => __$ThreadExecutionStateCopyWithImpl<_ThreadExecutionState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadExecutionState&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.sync, sync) || other.sync == sync)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,sync,value);
}



}

/// @nodoc
abstract mixin class _$ThreadExecutionStateCopyWith<$Res> implements $ThreadExecutionStateCopyWith<$Res> {
  factory _$ThreadExecutionStateCopyWith(_ThreadExecutionState value, $Res Function(_ThreadExecutionState) _then) = __$ThreadExecutionStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadExecutionBaseline? value
});


@override $ThreadFacetStampCopyWith<$Res>? get stamp;@override $FacetSyncStateCopyWith<$Res> get sync;@override $ThreadExecutionBaselineCopyWith<$Res>? get value;

}
/// @nodoc
class __$ThreadExecutionStateCopyWithImpl<$Res>
    implements _$ThreadExecutionStateCopyWith<$Res> {
  __$ThreadExecutionStateCopyWithImpl(this._self, this._then);

  final _ThreadExecutionState _self;
  final $Res Function(_ThreadExecutionState) _then;

/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(_ThreadExecutionState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadExecutionBaseline?,
  ));
}

/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadExecutionState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionBaselineCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadExecutionBaselineCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadMetricsState {

 ThreadFacetStamp? get stamp; FacetSyncState get sync; ThreadMetricsValue? get value;
/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsStateCopyWith<ThreadMetricsState> get copyWith => _$ThreadMetricsStateCopyWithImpl<ThreadMetricsState>(this as ThreadMetricsState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMetricsState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.sync, _this.sync) || other.sync == _this.sync)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadMetricsState;
  return Object.hash(runtimeType,_this.stamp,_this.sync,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsStateCopyWith<$Res>  {
  factory $ThreadMetricsStateCopyWith(ThreadMetricsState value, $Res Function(ThreadMetricsState) _then) = _$ThreadMetricsStateCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadMetricsValue? value
});


$ThreadFacetStampCopyWith<$Res>? get stamp;$FacetSyncStateCopyWith<$Res> get sync;$ThreadMetricsValueCopyWith<$Res>? get value;

}
/// @nodoc
class _$ThreadMetricsStateCopyWithImpl<$Res>
    implements $ThreadMetricsStateCopyWith<$Res> {
  _$ThreadMetricsStateCopyWithImpl(this._self, this._then);

  final ThreadMetricsState _self;
  final $Res Function(ThreadMetricsState) _then;

/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(ThreadMetricsState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadMetricsValue?,
  ));
}
/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadMetricsValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadMetricsState].
extension ThreadMetricsStatePatterns on ThreadMetricsState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadMetricsState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadMetricsState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadMetricsState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadMetricsState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadMetricsValue? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadMetricsState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadMetricsValue? value)  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsState():
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadMetricsValue? value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadMetricsState implements ThreadMetricsState {
  const _ThreadMetricsState({this.stamp, required this.sync, this.value});


@override final  ThreadFacetStamp? stamp;
@override final  FacetSyncState sync;
@override final  ThreadMetricsValue? value;

/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadMetricsStateCopyWith<_ThreadMetricsState> get copyWith => __$ThreadMetricsStateCopyWithImpl<_ThreadMetricsState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadMetricsState&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.sync, sync) || other.sync == sync)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,sync,value);
}



}

/// @nodoc
abstract mixin class _$ThreadMetricsStateCopyWith<$Res> implements $ThreadMetricsStateCopyWith<$Res> {
  factory _$ThreadMetricsStateCopyWith(_ThreadMetricsState value, $Res Function(_ThreadMetricsState) _then) = __$ThreadMetricsStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadMetricsValue? value
});


@override $ThreadFacetStampCopyWith<$Res>? get stamp;@override $FacetSyncStateCopyWith<$Res> get sync;@override $ThreadMetricsValueCopyWith<$Res>? get value;

}
/// @nodoc
class __$ThreadMetricsStateCopyWithImpl<$Res>
    implements _$ThreadMetricsStateCopyWith<$Res> {
  __$ThreadMetricsStateCopyWithImpl(this._self, this._then);

  final _ThreadMetricsState _self;
  final $Res Function(_ThreadMetricsState) _then;

/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(_ThreadMetricsState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadMetricsValue?,
  ));
}

/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadMetricsState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadMetricsValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadContextState {

 ThreadFacetStamp? get stamp; FacetSyncState get sync; ThreadContextValue? get value;
/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextStateCopyWith<ThreadContextState> get copyWith => _$ThreadContextStateCopyWithImpl<ThreadContextState>(this as ThreadContextState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadContextState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.sync, _this.sync) || other.sync == _this.sync)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadContextState;
  return Object.hash(runtimeType,_this.stamp,_this.sync,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadContextStateCopyWith<$Res>  {
  factory $ThreadContextStateCopyWith(ThreadContextState value, $Res Function(ThreadContextState) _then) = _$ThreadContextStateCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadContextValue? value
});


$ThreadFacetStampCopyWith<$Res>? get stamp;$FacetSyncStateCopyWith<$Res> get sync;$ThreadContextValueCopyWith<$Res>? get value;

}
/// @nodoc
class _$ThreadContextStateCopyWithImpl<$Res>
    implements $ThreadContextStateCopyWith<$Res> {
  _$ThreadContextStateCopyWithImpl(this._self, this._then);

  final ThreadContextState _self;
  final $Res Function(ThreadContextState) _then;

/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(ThreadContextState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadContextValue?,
  ));
}
/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadContextValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadContextState].
extension ThreadContextStatePatterns on ThreadContextState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadContextState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadContextState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadContextState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadContextState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadContextState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadContextState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadContextValue? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadContextState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadContextValue? value)  $default,) {final _that = this;
switch (_that) {
case _ThreadContextState():
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadContextValue? value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadContextState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadContextState implements ThreadContextState {
  const _ThreadContextState({this.stamp, required this.sync, this.value});


@override final  ThreadFacetStamp? stamp;
@override final  FacetSyncState sync;
@override final  ThreadContextValue? value;

/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadContextStateCopyWith<_ThreadContextState> get copyWith => __$ThreadContextStateCopyWithImpl<_ThreadContextState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadContextState&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.sync, sync) || other.sync == sync)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,sync,value);
}



}

/// @nodoc
abstract mixin class _$ThreadContextStateCopyWith<$Res> implements $ThreadContextStateCopyWith<$Res> {
  factory _$ThreadContextStateCopyWith(_ThreadContextState value, $Res Function(_ThreadContextState) _then) = __$ThreadContextStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadContextValue? value
});


@override $ThreadFacetStampCopyWith<$Res>? get stamp;@override $FacetSyncStateCopyWith<$Res> get sync;@override $ThreadContextValueCopyWith<$Res>? get value;

}
/// @nodoc
class __$ThreadContextStateCopyWithImpl<$Res>
    implements _$ThreadContextStateCopyWith<$Res> {
  __$ThreadContextStateCopyWithImpl(this._self, this._then);

  final _ThreadContextState _self;
  final $Res Function(_ThreadContextState) _then;

/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(_ThreadContextState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadContextValue?,
  ));
}

/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadContextState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadContextValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadConfigurationState {

 ThreadFacetStamp? get stamp; FacetSyncState get sync; ThreadConfigurationValue? get value;
/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationStateCopyWith<ThreadConfigurationState> get copyWith => _$ThreadConfigurationStateCopyWithImpl<ThreadConfigurationState>(this as ThreadConfigurationState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadConfigurationState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.sync, _this.sync) || other.sync == _this.sync)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadConfigurationState;
  return Object.hash(runtimeType,_this.stamp,_this.sync,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationStateCopyWith<$Res>  {
  factory $ThreadConfigurationStateCopyWith(ThreadConfigurationState value, $Res Function(ThreadConfigurationState) _then) = _$ThreadConfigurationStateCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadConfigurationValue? value
});


$ThreadFacetStampCopyWith<$Res>? get stamp;$FacetSyncStateCopyWith<$Res> get sync;$ThreadConfigurationValueCopyWith<$Res>? get value;

}
/// @nodoc
class _$ThreadConfigurationStateCopyWithImpl<$Res>
    implements $ThreadConfigurationStateCopyWith<$Res> {
  _$ThreadConfigurationStateCopyWithImpl(this._self, this._then);

  final ThreadConfigurationState _self;
  final $Res Function(ThreadConfigurationState) _then;

/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(ThreadConfigurationState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationValue?,
  ));
}
/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadConfigurationValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadConfigurationState].
extension ThreadConfigurationStatePatterns on ThreadConfigurationState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadConfigurationState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadConfigurationState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadConfigurationState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadConfigurationState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadConfigurationState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadConfigurationValue? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadConfigurationState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadConfigurationValue? value)  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationState():
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadConfigurationValue? value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadConfigurationState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadConfigurationState implements ThreadConfigurationState {
  const _ThreadConfigurationState({this.stamp, required this.sync, this.value});


@override final  ThreadFacetStamp? stamp;
@override final  FacetSyncState sync;
@override final  ThreadConfigurationValue? value;

/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadConfigurationStateCopyWith<_ThreadConfigurationState> get copyWith => __$ThreadConfigurationStateCopyWithImpl<_ThreadConfigurationState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadConfigurationState&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.sync, sync) || other.sync == sync)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,sync,value);
}



}

/// @nodoc
abstract mixin class _$ThreadConfigurationStateCopyWith<$Res> implements $ThreadConfigurationStateCopyWith<$Res> {
  factory _$ThreadConfigurationStateCopyWith(_ThreadConfigurationState value, $Res Function(_ThreadConfigurationState) _then) = __$ThreadConfigurationStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadConfigurationValue? value
});


@override $ThreadFacetStampCopyWith<$Res>? get stamp;@override $FacetSyncStateCopyWith<$Res> get sync;@override $ThreadConfigurationValueCopyWith<$Res>? get value;

}
/// @nodoc
class __$ThreadConfigurationStateCopyWithImpl<$Res>
    implements _$ThreadConfigurationStateCopyWith<$Res> {
  __$ThreadConfigurationStateCopyWithImpl(this._self, this._then);

  final _ThreadConfigurationState _self;
  final $Res Function(_ThreadConfigurationState) _then;

/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(_ThreadConfigurationState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationValue?,
  ));
}

/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadConfigurationState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadConfigurationValueCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadAuthoringState {

 ThreadFacetStamp? get stamp; FacetSyncState get sync; ThreadAuthoringBaseline? get value;
/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringStateCopyWith<ThreadAuthoringState> get copyWith => _$ThreadAuthoringStateCopyWithImpl<ThreadAuthoringState>(this as ThreadAuthoringState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAuthoringState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringState&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.sync, _this.sync) || other.sync == _this.sync)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadAuthoringState;
  return Object.hash(runtimeType,_this.stamp,_this.sync,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringStateCopyWith<$Res>  {
  factory $ThreadAuthoringStateCopyWith(ThreadAuthoringState value, $Res Function(ThreadAuthoringState) _then) = _$ThreadAuthoringStateCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadAuthoringBaseline? value
});


$ThreadFacetStampCopyWith<$Res>? get stamp;$FacetSyncStateCopyWith<$Res> get sync;$ThreadAuthoringBaselineCopyWith<$Res>? get value;

}
/// @nodoc
class _$ThreadAuthoringStateCopyWithImpl<$Res>
    implements $ThreadAuthoringStateCopyWith<$Res> {
  _$ThreadAuthoringStateCopyWithImpl(this._self, this._then);

  final ThreadAuthoringState _self;
  final $Res Function(ThreadAuthoringState) _then;

/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(ThreadAuthoringState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadAuthoringBaseline?,
  ));
}
/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAuthoringBaselineCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadAuthoringBaselineCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadAuthoringState].
extension ThreadAuthoringStatePatterns on ThreadAuthoringState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadAuthoringState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadAuthoringState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadAuthoringState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadAuthoringState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadAuthoringState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadAuthoringBaseline? value)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadAuthoringState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadAuthoringBaseline? value)  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringState():
return $default(_that.stamp,_that.sync,_that.value);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( ThreadFacetStamp? stamp,  FacetSyncState sync,  ThreadAuthoringBaseline? value)?  $default,) {final _that = this;
switch (_that) {
case _ThreadAuthoringState() when $default != null:
return $default(_that.stamp,_that.sync,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadAuthoringState implements ThreadAuthoringState {
  const _ThreadAuthoringState({this.stamp, required this.sync, this.value});


@override final  ThreadFacetStamp? stamp;
@override final  FacetSyncState sync;
@override final  ThreadAuthoringBaseline? value;

/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadAuthoringStateCopyWith<_ThreadAuthoringState> get copyWith => __$ThreadAuthoringStateCopyWithImpl<_ThreadAuthoringState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadAuthoringState&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.sync, sync) || other.sync == sync)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,sync,value);
}



}

/// @nodoc
abstract mixin class _$ThreadAuthoringStateCopyWith<$Res> implements $ThreadAuthoringStateCopyWith<$Res> {
  factory _$ThreadAuthoringStateCopyWith(_ThreadAuthoringState value, $Res Function(_ThreadAuthoringState) _then) = __$ThreadAuthoringStateCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp? stamp, FacetSyncState sync, ThreadAuthoringBaseline? value
});


@override $ThreadFacetStampCopyWith<$Res>? get stamp;@override $FacetSyncStateCopyWith<$Res> get sync;@override $ThreadAuthoringBaselineCopyWith<$Res>? get value;

}
/// @nodoc
class __$ThreadAuthoringStateCopyWithImpl<$Res>
    implements _$ThreadAuthoringStateCopyWith<$Res> {
  __$ThreadAuthoringStateCopyWithImpl(this._self, this._then);

  final _ThreadAuthoringState _self;
  final $Res Function(_ThreadAuthoringState) _then;

/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = freezed,Object? sync = null,Object? value = freezed,}) {
  return _then(_ThreadAuthoringState(
stamp: freezed == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp?,sync: null == sync ? _self.sync : sync // ignore: cast_nullable_to_non_nullable
as FacetSyncState,value: freezed == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadAuthoringBaseline?,
  ));
}

/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res>? get stamp {
    if (_self.stamp == null) {
    return null;
  }

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp!, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$FacetSyncStateCopyWith<$Res> get sync {

  return $FacetSyncStateCopyWith<$Res>(_self.sync, (value) {
    return _then(_self.copyWith(sync: value));
  });
}/// Create a copy of ThreadAuthoringState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAuthoringBaselineCopyWith<$Res>? get value {
    if (_self.value == null) {
    return null;
  }

  return $ThreadAuthoringBaselineCopyWith<$Res>(_self.value!, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
