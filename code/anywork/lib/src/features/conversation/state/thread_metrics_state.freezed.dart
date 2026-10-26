// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_metrics_state.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadMetricsViewState {

 String get threadId; ThreadMetricsState? get source; bool get visible; bool get detailsVisible; bool get retrying; int get latestIntent; StudioFailure? get error;
/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsViewStateCopyWith<ThreadMetricsViewState> get copyWith => _$ThreadMetricsViewStateCopyWithImpl<ThreadMetricsViewState>(this as ThreadMetricsViewState, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMetricsViewState;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsViewState&&(identical(other.threadId, _this.threadId) || other.threadId == _this.threadId)&&(identical(other.source, _this.source) || other.source == _this.source)&&(identical(other.visible, _this.visible) || other.visible == _this.visible)&&(identical(other.detailsVisible, _this.detailsVisible) || other.detailsVisible == _this.detailsVisible)&&(identical(other.retrying, _this.retrying) || other.retrying == _this.retrying)&&(identical(other.latestIntent, _this.latestIntent) || other.latestIntent == _this.latestIntent)&&(identical(other.error, _this.error) || other.error == _this.error));
}


@override
int get hashCode {
  final _this = this as ThreadMetricsViewState;
  return Object.hash(runtimeType,_this.threadId,_this.source,_this.visible,_this.detailsVisible,_this.retrying,_this.latestIntent,_this.error);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsViewStateCopyWith<$Res>  {
  factory $ThreadMetricsViewStateCopyWith(ThreadMetricsViewState value, $Res Function(ThreadMetricsViewState) _then) = _$ThreadMetricsViewStateCopyWithImpl;
@useResult
$Res call({
 String threadId, ThreadMetricsState? source, bool visible, bool detailsVisible, bool retrying, int latestIntent, StudioFailure? error
});


$ThreadMetricsStateCopyWith<$Res>? get source;$StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class _$ThreadMetricsViewStateCopyWithImpl<$Res>
    implements $ThreadMetricsViewStateCopyWith<$Res> {
  _$ThreadMetricsViewStateCopyWithImpl(this._self, this._then);

  final ThreadMetricsViewState _self;
  final $Res Function(ThreadMetricsViewState) _then;

/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? threadId = null,Object? source = freezed,Object? visible = null,Object? detailsVisible = null,Object? retrying = null,Object? latestIntent = null,Object? error = freezed,}) {
  return _then(ThreadMetricsViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ThreadMetricsState?,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,retrying: null == retrying ? _self.retrying : retrying // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}
/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsStateCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $ThreadMetricsStateCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadMetricsViewState
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


/// Adds pattern-matching-related methods to [ThreadMetricsViewState].
extension ThreadMetricsViewStatePatterns on ThreadMetricsViewState {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _ThreadMetricsViewState value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _ThreadMetricsViewState() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _ThreadMetricsViewState value)  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsViewState():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _ThreadMetricsViewState value)?  $default,){
final _that = this;
switch (_that) {
case _ThreadMetricsViewState() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String threadId,  ThreadMetricsState? source,  bool visible,  bool detailsVisible,  bool retrying,  int latestIntent,  StudioFailure? error)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _ThreadMetricsViewState() when $default != null:
return $default(_that.threadId,_that.source,_that.visible,_that.detailsVisible,_that.retrying,_that.latestIntent,_that.error);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String threadId,  ThreadMetricsState? source,  bool visible,  bool detailsVisible,  bool retrying,  int latestIntent,  StudioFailure? error)  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsViewState():
return $default(_that.threadId,_that.source,_that.visible,_that.detailsVisible,_that.retrying,_that.latestIntent,_that.error);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String threadId,  ThreadMetricsState? source,  bool visible,  bool detailsVisible,  bool retrying,  int latestIntent,  StudioFailure? error)?  $default,) {final _that = this;
switch (_that) {
case _ThreadMetricsViewState() when $default != null:
return $default(_that.threadId,_that.source,_that.visible,_that.detailsVisible,_that.retrying,_that.latestIntent,_that.error);case _:
  return null;

}
}

}

/// @nodoc


class _ThreadMetricsViewState extends ThreadMetricsViewState {
  const _ThreadMetricsViewState({required this.threadId, this.source, this.visible = true, this.detailsVisible = false, this.retrying = false, this.latestIntent = 0, this.error}): super._();


@override final  String threadId;
@override final  ThreadMetricsState? source;
@override@JsonKey() final  bool visible;
@override@JsonKey() final  bool detailsVisible;
@override@JsonKey() final  bool retrying;
@override@JsonKey() final  int latestIntent;
@override final  StudioFailure? error;

/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ThreadMetricsViewStateCopyWith<_ThreadMetricsViewState> get copyWith => __$ThreadMetricsViewStateCopyWithImpl<_ThreadMetricsViewState>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _ThreadMetricsViewState&&(identical(other.threadId, threadId) || other.threadId == threadId)&&(identical(other.source, source) || other.source == source)&&(identical(other.visible, visible) || other.visible == visible)&&(identical(other.detailsVisible, detailsVisible) || other.detailsVisible == detailsVisible)&&(identical(other.retrying, retrying) || other.retrying == retrying)&&(identical(other.latestIntent, latestIntent) || other.latestIntent == latestIntent)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,threadId,source,visible,detailsVisible,retrying,latestIntent,error);
}



}

/// @nodoc
abstract mixin class _$ThreadMetricsViewStateCopyWith<$Res> implements $ThreadMetricsViewStateCopyWith<$Res> {
  factory _$ThreadMetricsViewStateCopyWith(_ThreadMetricsViewState value, $Res Function(_ThreadMetricsViewState) _then) = __$ThreadMetricsViewStateCopyWithImpl;
@override @useResult
$Res call({
 String threadId, ThreadMetricsState? source, bool visible, bool detailsVisible, bool retrying, int latestIntent, StudioFailure? error
});


@override $ThreadMetricsStateCopyWith<$Res>? get source;@override $StudioFailureCopyWith<$Res>? get error;

}
/// @nodoc
class __$ThreadMetricsViewStateCopyWithImpl<$Res>
    implements _$ThreadMetricsViewStateCopyWith<$Res> {
  __$ThreadMetricsViewStateCopyWithImpl(this._self, this._then);

  final _ThreadMetricsViewState _self;
  final $Res Function(_ThreadMetricsViewState) _then;

/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? threadId = null,Object? source = freezed,Object? visible = null,Object? detailsVisible = null,Object? retrying = null,Object? latestIntent = null,Object? error = freezed,}) {
  return _then(_ThreadMetricsViewState(
threadId: null == threadId ? _self.threadId : threadId // ignore: cast_nullable_to_non_nullable
as String,source: freezed == source ? _self.source : source // ignore: cast_nullable_to_non_nullable
as ThreadMetricsState?,visible: null == visible ? _self.visible : visible // ignore: cast_nullable_to_non_nullable
as bool,detailsVisible: null == detailsVisible ? _self.detailsVisible : detailsVisible // ignore: cast_nullable_to_non_nullable
as bool,retrying: null == retrying ? _self.retrying : retrying // ignore: cast_nullable_to_non_nullable
as bool,latestIntent: null == latestIntent ? _self.latestIntent : latestIntent // ignore: cast_nullable_to_non_nullable
as int,error: freezed == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure?,
  ));
}

/// Create a copy of ThreadMetricsViewState
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsStateCopyWith<$Res>? get source {
    if (_self.source == null) {
    return null;
  }

  return $ThreadMetricsStateCopyWith<$Res>(_self.source!, (value) {
    return _then(_self.copyWith(source: value));
  });
}/// Create a copy of ThreadMetricsViewState
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
