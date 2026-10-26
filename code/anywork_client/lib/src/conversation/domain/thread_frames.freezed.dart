// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'thread_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$ThreadExecutionFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadExecutionFrameCopyWith<$Res>  {
$ThreadExecutionFrameCopyWith(ThreadExecutionFrame _, $Res Function(ThreadExecutionFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadExecutionFrame].
extension ThreadExecutionFramePatterns on ThreadExecutionFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadExecutionData value)?  data,TResult Function( ThreadExecutionResyncRequired value)?  resyncRequired,TResult Function( ThreadExecutionFailure value)?  failure,TResult Function( ThreadExecutionClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadExecutionData() when data != null:
return data(_that);case ThreadExecutionResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadExecutionFailure() when failure != null:
return failure(_that);case ThreadExecutionClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadExecutionData value)  data,required TResult Function( ThreadExecutionResyncRequired value)  resyncRequired,required TResult Function( ThreadExecutionFailure value)  failure,required TResult Function( ThreadExecutionClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadExecutionData():
return data(_that);case ThreadExecutionResyncRequired():
return resyncRequired(_that);case ThreadExecutionFailure():
return failure(_that);case ThreadExecutionClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadExecutionData value)?  data,TResult? Function( ThreadExecutionResyncRequired value)?  resyncRequired,TResult? Function( ThreadExecutionFailure value)?  failure,TResult? Function( ThreadExecutionClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadExecutionData() when data != null:
return data(_that);case ThreadExecutionResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadExecutionFailure() when failure != null:
return failure(_that);case ThreadExecutionClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadExecutionEvent event)?  data,TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadExecutionData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadExecutionResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadExecutionFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadExecutionClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadExecutionEvent event)  data,required TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)  resyncRequired,required TResult Function( ThreadFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadExecutionData():
return data(_that.deliverySequence,_that.event);case ThreadExecutionResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadExecutionFailure():
return failure(_that.identity,_that.error);case ThreadExecutionClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadExecutionEvent event)?  data,TResult? Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult? Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadExecutionData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadExecutionResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadExecutionFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadExecutionClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadExecutionData implements ThreadExecutionFrame {
  const ThreadExecutionData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadExecutionEvent event;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionDataCopyWith<ThreadExecutionData> get copyWith => _$ThreadExecutionDataCopyWithImpl<ThreadExecutionData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionDataCopyWith<$Res> implements $ThreadExecutionFrameCopyWith<$Res> {
  factory $ThreadExecutionDataCopyWith(ThreadExecutionData value, $Res Function(ThreadExecutionData) _then) = _$ThreadExecutionDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadExecutionEvent event
});


$ThreadExecutionEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadExecutionDataCopyWithImpl<$Res>
    implements $ThreadExecutionDataCopyWith<$Res> {
  _$ThreadExecutionDataCopyWithImpl(this._self, this._then);

  final ThreadExecutionData _self;
  final $Res Function(ThreadExecutionData) _then;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadExecutionData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadExecutionEvent,
  ));
}

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionEventCopyWith<$Res> get event {

  return $ThreadExecutionEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadExecutionResyncRequired implements ThreadExecutionFrame {
  const ThreadExecutionResyncRequired({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadResyncReason reason;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionResyncRequiredCopyWith<ThreadExecutionResyncRequired> get copyWith => _$ThreadExecutionResyncRequiredCopyWithImpl<ThreadExecutionResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionResyncRequiredCopyWith<$Res> implements $ThreadExecutionFrameCopyWith<$Res> {
  factory $ThreadExecutionResyncRequiredCopyWith(ThreadExecutionResyncRequired value, $Res Function(ThreadExecutionResyncRequired) _then) = _$ThreadExecutionResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadResyncReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadExecutionResyncRequiredCopyWithImpl<$Res>
    implements $ThreadExecutionResyncRequiredCopyWith<$Res> {
  _$ThreadExecutionResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadExecutionResyncRequired _self;
  final $Res Function(ThreadExecutionResyncRequired) _then;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadExecutionResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadResyncReason,
  ));
}

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class ThreadExecutionFailure implements ThreadExecutionFrame {
  const ThreadExecutionFailure({required this.identity, required this.error});


 final  ThreadFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionFailureCopyWith<ThreadExecutionFailure> get copyWith => _$ThreadExecutionFailureCopyWithImpl<ThreadExecutionFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionFailureCopyWith<$Res> implements $ThreadExecutionFrameCopyWith<$Res> {
  factory $ThreadExecutionFailureCopyWith(ThreadExecutionFailure value, $Res Function(ThreadExecutionFailure) _then) = _$ThreadExecutionFailureCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, StudioFailure error
});


$ThreadFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadExecutionFailureCopyWithImpl<$Res>
    implements $ThreadExecutionFailureCopyWith<$Res> {
  _$ThreadExecutionFailureCopyWithImpl(this._self, this._then);

  final ThreadExecutionFailure _self;
  final $Res Function(ThreadExecutionFailure) _then;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadExecutionFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadExecutionFrame
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


class ThreadExecutionClosed implements ThreadExecutionFrame {
  const ThreadExecutionClosed({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadFeedClosedReason reason;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionClosedCopyWith<ThreadExecutionClosed> get copyWith => _$ThreadExecutionClosedCopyWithImpl<ThreadExecutionClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionClosedCopyWith<$Res> implements $ThreadExecutionFrameCopyWith<$Res> {
  factory $ThreadExecutionClosedCopyWith(ThreadExecutionClosed value, $Res Function(ThreadExecutionClosed) _then) = _$ThreadExecutionClosedCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFeedClosedReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadExecutionClosedCopyWithImpl<$Res>
    implements $ThreadExecutionClosedCopyWith<$Res> {
  _$ThreadExecutionClosedCopyWithImpl(this._self, this._then);

  final ThreadExecutionClosed _self;
  final $Res Function(ThreadExecutionClosed) _then;

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadExecutionClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadFeedClosedReason,
  ));
}

/// Create a copy of ThreadExecutionFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$ThreadExecutionEvent {

 ThreadFacetStamp get stamp; Object get value;
/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionEventCopyWith<ThreadExecutionEvent> get copyWith => _$ThreadExecutionEventCopyWithImpl<ThreadExecutionEvent>(this as ThreadExecutionEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadExecutionEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadExecutionEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $ThreadExecutionEventCopyWith<$Res>  {
  factory $ThreadExecutionEventCopyWith(ThreadExecutionEvent value, $Res Function(ThreadExecutionEvent) _then) = _$ThreadExecutionEventCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp stamp
});


$ThreadFacetStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ThreadExecutionEventCopyWithImpl<$Res>
    implements $ThreadExecutionEventCopyWith<$Res> {
  _$ThreadExecutionEventCopyWithImpl(this._self, this._then);

  final ThreadExecutionEvent _self;
  final $Res Function(ThreadExecutionEvent) _then;

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,
  ));
}
/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadExecutionEvent].
extension ThreadExecutionEventPatterns on ThreadExecutionEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadExecutionBaselineEvent value)?  baseline,TResult Function( ThreadExecutionChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent() when baseline != null:
return baseline(_that);case ThreadExecutionChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadExecutionBaselineEvent value)  baseline,required TResult Function( ThreadExecutionChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent():
return baseline(_that);case ThreadExecutionChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadExecutionBaselineEvent value)?  baseline,TResult? Function( ThreadExecutionChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent() when baseline != null:
return baseline(_that);case ThreadExecutionChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadExecutionBaseline value)?  baseline,TResult Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadExecutionChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadExecutionChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadExecutionBaseline value)  baseline,required TResult Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadExecutionChange value)  change,}) {final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadExecutionChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadExecutionBaseline value)?  baseline,TResult? Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadExecutionChange value)?  change,}) {final _that = this;
switch (_that) {
case ThreadExecutionBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadExecutionChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadExecutionBaselineEvent implements ThreadExecutionEvent {
  const ThreadExecutionBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ThreadFeedIdentity identity;
@override final  ThreadFacetStamp stamp;
@override final  ThreadExecutionBaseline value;

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionBaselineEventCopyWith<ThreadExecutionBaselineEvent> get copyWith => _$ThreadExecutionBaselineEventCopyWithImpl<ThreadExecutionBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionBaselineEventCopyWith<$Res> implements $ThreadExecutionEventCopyWith<$Res> {
  factory $ThreadExecutionBaselineEventCopyWith(ThreadExecutionBaselineEvent value, $Res Function(ThreadExecutionBaselineEvent) _then) = _$ThreadExecutionBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFacetStamp stamp, ThreadExecutionBaseline value
});


$ThreadFeedIdentityCopyWith<$Res> get identity;@override $ThreadFacetStampCopyWith<$Res> get stamp;$ThreadExecutionBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadExecutionBaselineEventCopyWithImpl<$Res>
    implements $ThreadExecutionBaselineEventCopyWith<$Res> {
  _$ThreadExecutionBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadExecutionBaselineEvent _self;
  final $Res Function(ThreadExecutionBaselineEvent) _then;

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadExecutionBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadExecutionBaseline,
  ));
}

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionBaselineCopyWith<$Res> get value {

  return $ThreadExecutionBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadExecutionChangeEvent implements ThreadExecutionEvent {
  const ThreadExecutionChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ThreadFacetStamp stamp;
 final  int baseRevision;
@override final  ThreadExecutionChange value;

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadExecutionChangeEventCopyWith<ThreadExecutionChangeEvent> get copyWith => _$ThreadExecutionChangeEventCopyWithImpl<ThreadExecutionChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadExecutionChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $ThreadExecutionChangeEventCopyWith<$Res> implements $ThreadExecutionEventCopyWith<$Res> {
  factory $ThreadExecutionChangeEventCopyWith(ThreadExecutionChangeEvent value, $Res Function(ThreadExecutionChangeEvent) _then) = _$ThreadExecutionChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp stamp, int baseRevision, ThreadExecutionChange value
});


@override $ThreadFacetStampCopyWith<$Res> get stamp;$ThreadExecutionChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadExecutionChangeEventCopyWithImpl<$Res>
    implements $ThreadExecutionChangeEventCopyWith<$Res> {
  _$ThreadExecutionChangeEventCopyWithImpl(this._self, this._then);

  final ThreadExecutionChangeEvent _self;
  final $Res Function(ThreadExecutionChangeEvent) _then;

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ThreadExecutionChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadExecutionChange,
  ));
}

/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadExecutionEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadExecutionChangeCopyWith<$Res> get value {

  return $ThreadExecutionChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadMetricsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadMetricsFrameCopyWith<$Res>  {
$ThreadMetricsFrameCopyWith(ThreadMetricsFrame _, $Res Function(ThreadMetricsFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadMetricsFrame].
extension ThreadMetricsFramePatterns on ThreadMetricsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadMetricsData value)?  data,TResult Function( ThreadMetricsResyncRequired value)?  resyncRequired,TResult Function( ThreadMetricsFailure value)?  failure,TResult Function( ThreadMetricsClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadMetricsData() when data != null:
return data(_that);case ThreadMetricsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadMetricsFailure() when failure != null:
return failure(_that);case ThreadMetricsClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadMetricsData value)  data,required TResult Function( ThreadMetricsResyncRequired value)  resyncRequired,required TResult Function( ThreadMetricsFailure value)  failure,required TResult Function( ThreadMetricsClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadMetricsData():
return data(_that);case ThreadMetricsResyncRequired():
return resyncRequired(_that);case ThreadMetricsFailure():
return failure(_that);case ThreadMetricsClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadMetricsData value)?  data,TResult? Function( ThreadMetricsResyncRequired value)?  resyncRequired,TResult? Function( ThreadMetricsFailure value)?  failure,TResult? Function( ThreadMetricsClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadMetricsData() when data != null:
return data(_that);case ThreadMetricsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadMetricsFailure() when failure != null:
return failure(_that);case ThreadMetricsClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadMetricsEvent event)?  data,TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadMetricsData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadMetricsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadMetricsFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadMetricsClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadMetricsEvent event)  data,required TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)  resyncRequired,required TResult Function( ThreadFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadMetricsData():
return data(_that.deliverySequence,_that.event);case ThreadMetricsResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadMetricsFailure():
return failure(_that.identity,_that.error);case ThreadMetricsClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadMetricsEvent event)?  data,TResult? Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult? Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadMetricsData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadMetricsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadMetricsFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadMetricsClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadMetricsData implements ThreadMetricsFrame {
  const ThreadMetricsData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadMetricsEvent event;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsDataCopyWith<ThreadMetricsData> get copyWith => _$ThreadMetricsDataCopyWithImpl<ThreadMetricsData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsDataCopyWith<$Res> implements $ThreadMetricsFrameCopyWith<$Res> {
  factory $ThreadMetricsDataCopyWith(ThreadMetricsData value, $Res Function(ThreadMetricsData) _then) = _$ThreadMetricsDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadMetricsEvent event
});


$ThreadMetricsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadMetricsDataCopyWithImpl<$Res>
    implements $ThreadMetricsDataCopyWith<$Res> {
  _$ThreadMetricsDataCopyWithImpl(this._self, this._then);

  final ThreadMetricsData _self;
  final $Res Function(ThreadMetricsData) _then;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadMetricsData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadMetricsEvent,
  ));
}

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsEventCopyWith<$Res> get event {

  return $ThreadMetricsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadMetricsResyncRequired implements ThreadMetricsFrame {
  const ThreadMetricsResyncRequired({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadResyncReason reason;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsResyncRequiredCopyWith<ThreadMetricsResyncRequired> get copyWith => _$ThreadMetricsResyncRequiredCopyWithImpl<ThreadMetricsResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsResyncRequiredCopyWith<$Res> implements $ThreadMetricsFrameCopyWith<$Res> {
  factory $ThreadMetricsResyncRequiredCopyWith(ThreadMetricsResyncRequired value, $Res Function(ThreadMetricsResyncRequired) _then) = _$ThreadMetricsResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadResyncReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadMetricsResyncRequiredCopyWithImpl<$Res>
    implements $ThreadMetricsResyncRequiredCopyWith<$Res> {
  _$ThreadMetricsResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadMetricsResyncRequired _self;
  final $Res Function(ThreadMetricsResyncRequired) _then;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadMetricsResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadResyncReason,
  ));
}

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class ThreadMetricsFailure implements ThreadMetricsFrame {
  const ThreadMetricsFailure({required this.identity, required this.error});


 final  ThreadFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsFailureCopyWith<ThreadMetricsFailure> get copyWith => _$ThreadMetricsFailureCopyWithImpl<ThreadMetricsFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsFailureCopyWith<$Res> implements $ThreadMetricsFrameCopyWith<$Res> {
  factory $ThreadMetricsFailureCopyWith(ThreadMetricsFailure value, $Res Function(ThreadMetricsFailure) _then) = _$ThreadMetricsFailureCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, StudioFailure error
});


$ThreadFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadMetricsFailureCopyWithImpl<$Res>
    implements $ThreadMetricsFailureCopyWith<$Res> {
  _$ThreadMetricsFailureCopyWithImpl(this._self, this._then);

  final ThreadMetricsFailure _self;
  final $Res Function(ThreadMetricsFailure) _then;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadMetricsFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadMetricsFrame
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


class ThreadMetricsClosed implements ThreadMetricsFrame {
  const ThreadMetricsClosed({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadFeedClosedReason reason;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsClosedCopyWith<ThreadMetricsClosed> get copyWith => _$ThreadMetricsClosedCopyWithImpl<ThreadMetricsClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsClosedCopyWith<$Res> implements $ThreadMetricsFrameCopyWith<$Res> {
  factory $ThreadMetricsClosedCopyWith(ThreadMetricsClosed value, $Res Function(ThreadMetricsClosed) _then) = _$ThreadMetricsClosedCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFeedClosedReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadMetricsClosedCopyWithImpl<$Res>
    implements $ThreadMetricsClosedCopyWith<$Res> {
  _$ThreadMetricsClosedCopyWithImpl(this._self, this._then);

  final ThreadMetricsClosed _self;
  final $Res Function(ThreadMetricsClosed) _then;

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadMetricsClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadFeedClosedReason,
  ));
}

/// Create a copy of ThreadMetricsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$ThreadMetricsEvent {

 ThreadFacetStamp get stamp; ThreadMetricsValue get value;
/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsEventCopyWith<ThreadMetricsEvent> get copyWith => _$ThreadMetricsEventCopyWithImpl<ThreadMetricsEvent>(this as ThreadMetricsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadMetricsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadMetricsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsEventCopyWith<$Res>  {
  factory $ThreadMetricsEventCopyWith(ThreadMetricsEvent value, $Res Function(ThreadMetricsEvent) _then) = _$ThreadMetricsEventCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp stamp, ThreadMetricsValue value
});


$ThreadFacetStampCopyWith<$Res> get stamp;$ThreadMetricsValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadMetricsEventCopyWithImpl<$Res>
    implements $ThreadMetricsEventCopyWith<$Res> {
  _$ThreadMetricsEventCopyWithImpl(this._self, this._then);

  final ThreadMetricsEvent _self;
  final $Res Function(ThreadMetricsEvent) _then;

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadMetricsValue,
  ));
}
/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<$Res> get value {

  return $ThreadMetricsValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadMetricsEvent].
extension ThreadMetricsEventPatterns on ThreadMetricsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadMetricsBaselineEvent value)?  baseline,TResult Function( ThreadMetricsReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent() when baseline != null:
return baseline(_that);case ThreadMetricsReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadMetricsBaselineEvent value)  baseline,required TResult Function( ThreadMetricsReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent():
return baseline(_that);case ThreadMetricsReplaceEvent():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadMetricsBaselineEvent value)?  baseline,TResult? Function( ThreadMetricsReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent() when baseline != null:
return baseline(_that);case ThreadMetricsReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadMetricsValue value)?  baseline,TResult Function( ThreadFacetStamp stamp,  ThreadMetricsValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadMetricsReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadMetricsValue value)  baseline,required TResult Function( ThreadFacetStamp stamp,  ThreadMetricsValue value)  replace,}) {final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadMetricsReplaceEvent():
return replace(_that.stamp,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadMetricsValue value)?  baseline,TResult? Function( ThreadFacetStamp stamp,  ThreadMetricsValue value)?  replace,}) {final _that = this;
switch (_that) {
case ThreadMetricsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadMetricsReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadMetricsBaselineEvent implements ThreadMetricsEvent {
  const ThreadMetricsBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ThreadFeedIdentity identity;
@override final  ThreadFacetStamp stamp;
@override final  ThreadMetricsValue value;

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsBaselineEventCopyWith<ThreadMetricsBaselineEvent> get copyWith => _$ThreadMetricsBaselineEventCopyWithImpl<ThreadMetricsBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsBaselineEventCopyWith<$Res> implements $ThreadMetricsEventCopyWith<$Res> {
  factory $ThreadMetricsBaselineEventCopyWith(ThreadMetricsBaselineEvent value, $Res Function(ThreadMetricsBaselineEvent) _then) = _$ThreadMetricsBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFacetStamp stamp, ThreadMetricsValue value
});


$ThreadFeedIdentityCopyWith<$Res> get identity;@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadMetricsValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadMetricsBaselineEventCopyWithImpl<$Res>
    implements $ThreadMetricsBaselineEventCopyWith<$Res> {
  _$ThreadMetricsBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadMetricsBaselineEvent _self;
  final $Res Function(ThreadMetricsBaselineEvent) _then;

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadMetricsBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadMetricsValue,
  ));
}

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<$Res> get value {

  return $ThreadMetricsValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadMetricsReplaceEvent implements ThreadMetricsEvent {
  const ThreadMetricsReplaceEvent({required this.stamp, required this.value});


@override final  ThreadFacetStamp stamp;
@override final  ThreadMetricsValue value;

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadMetricsReplaceEventCopyWith<ThreadMetricsReplaceEvent> get copyWith => _$ThreadMetricsReplaceEventCopyWithImpl<ThreadMetricsReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadMetricsReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadMetricsReplaceEventCopyWith<$Res> implements $ThreadMetricsEventCopyWith<$Res> {
  factory $ThreadMetricsReplaceEventCopyWith(ThreadMetricsReplaceEvent value, $Res Function(ThreadMetricsReplaceEvent) _then) = _$ThreadMetricsReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp stamp, ThreadMetricsValue value
});


@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadMetricsValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadMetricsReplaceEventCopyWithImpl<$Res>
    implements $ThreadMetricsReplaceEventCopyWith<$Res> {
  _$ThreadMetricsReplaceEventCopyWithImpl(this._self, this._then);

  final ThreadMetricsReplaceEvent _self;
  final $Res Function(ThreadMetricsReplaceEvent) _then;

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(ThreadMetricsReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadMetricsValue,
  ));
}

/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadMetricsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadMetricsValueCopyWith<$Res> get value {

  return $ThreadMetricsValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadContextFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadContextFrameCopyWith<$Res>  {
$ThreadContextFrameCopyWith(ThreadContextFrame _, $Res Function(ThreadContextFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadContextFrame].
extension ThreadContextFramePatterns on ThreadContextFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadContextData value)?  data,TResult Function( ThreadContextResyncRequired value)?  resyncRequired,TResult Function( ThreadContextFailure value)?  failure,TResult Function( ThreadContextClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadContextData() when data != null:
return data(_that);case ThreadContextResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadContextFailure() when failure != null:
return failure(_that);case ThreadContextClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadContextData value)  data,required TResult Function( ThreadContextResyncRequired value)  resyncRequired,required TResult Function( ThreadContextFailure value)  failure,required TResult Function( ThreadContextClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadContextData():
return data(_that);case ThreadContextResyncRequired():
return resyncRequired(_that);case ThreadContextFailure():
return failure(_that);case ThreadContextClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadContextData value)?  data,TResult? Function( ThreadContextResyncRequired value)?  resyncRequired,TResult? Function( ThreadContextFailure value)?  failure,TResult? Function( ThreadContextClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadContextData() when data != null:
return data(_that);case ThreadContextResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadContextFailure() when failure != null:
return failure(_that);case ThreadContextClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadContextEvent event)?  data,TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadContextData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadContextResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadContextFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadContextClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadContextEvent event)  data,required TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)  resyncRequired,required TResult Function( ThreadFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadContextData():
return data(_that.deliverySequence,_that.event);case ThreadContextResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadContextFailure():
return failure(_that.identity,_that.error);case ThreadContextClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadContextEvent event)?  data,TResult? Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult? Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadContextData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadContextResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadContextFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadContextClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadContextData implements ThreadContextFrame {
  const ThreadContextData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadContextEvent event;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextDataCopyWith<ThreadContextData> get copyWith => _$ThreadContextDataCopyWithImpl<ThreadContextData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadContextDataCopyWith<$Res> implements $ThreadContextFrameCopyWith<$Res> {
  factory $ThreadContextDataCopyWith(ThreadContextData value, $Res Function(ThreadContextData) _then) = _$ThreadContextDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadContextEvent event
});


$ThreadContextEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadContextDataCopyWithImpl<$Res>
    implements $ThreadContextDataCopyWith<$Res> {
  _$ThreadContextDataCopyWithImpl(this._self, this._then);

  final ThreadContextData _self;
  final $Res Function(ThreadContextData) _then;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadContextData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadContextEvent,
  ));
}

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextEventCopyWith<$Res> get event {

  return $ThreadContextEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadContextResyncRequired implements ThreadContextFrame {
  const ThreadContextResyncRequired({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadResyncReason reason;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextResyncRequiredCopyWith<ThreadContextResyncRequired> get copyWith => _$ThreadContextResyncRequiredCopyWithImpl<ThreadContextResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadContextResyncRequiredCopyWith<$Res> implements $ThreadContextFrameCopyWith<$Res> {
  factory $ThreadContextResyncRequiredCopyWith(ThreadContextResyncRequired value, $Res Function(ThreadContextResyncRequired) _then) = _$ThreadContextResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadResyncReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadContextResyncRequiredCopyWithImpl<$Res>
    implements $ThreadContextResyncRequiredCopyWith<$Res> {
  _$ThreadContextResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadContextResyncRequired _self;
  final $Res Function(ThreadContextResyncRequired) _then;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadContextResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadResyncReason,
  ));
}

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class ThreadContextFailure implements ThreadContextFrame {
  const ThreadContextFailure({required this.identity, required this.error});


 final  ThreadFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextFailureCopyWith<ThreadContextFailure> get copyWith => _$ThreadContextFailureCopyWithImpl<ThreadContextFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadContextFailureCopyWith<$Res> implements $ThreadContextFrameCopyWith<$Res> {
  factory $ThreadContextFailureCopyWith(ThreadContextFailure value, $Res Function(ThreadContextFailure) _then) = _$ThreadContextFailureCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, StudioFailure error
});


$ThreadFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadContextFailureCopyWithImpl<$Res>
    implements $ThreadContextFailureCopyWith<$Res> {
  _$ThreadContextFailureCopyWithImpl(this._self, this._then);

  final ThreadContextFailure _self;
  final $Res Function(ThreadContextFailure) _then;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadContextFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadContextFrame
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


class ThreadContextClosed implements ThreadContextFrame {
  const ThreadContextClosed({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadFeedClosedReason reason;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextClosedCopyWith<ThreadContextClosed> get copyWith => _$ThreadContextClosedCopyWithImpl<ThreadContextClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadContextClosedCopyWith<$Res> implements $ThreadContextFrameCopyWith<$Res> {
  factory $ThreadContextClosedCopyWith(ThreadContextClosed value, $Res Function(ThreadContextClosed) _then) = _$ThreadContextClosedCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFeedClosedReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadContextClosedCopyWithImpl<$Res>
    implements $ThreadContextClosedCopyWith<$Res> {
  _$ThreadContextClosedCopyWithImpl(this._self, this._then);

  final ThreadContextClosed _self;
  final $Res Function(ThreadContextClosed) _then;

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadContextClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadFeedClosedReason,
  ));
}

/// Create a copy of ThreadContextFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$ThreadContextEvent {

 ThreadFacetStamp get stamp; ThreadContextValue get value;
/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextEventCopyWith<ThreadContextEvent> get copyWith => _$ThreadContextEventCopyWithImpl<ThreadContextEvent>(this as ThreadContextEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadContextEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadContextEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadContextEventCopyWith<$Res>  {
  factory $ThreadContextEventCopyWith(ThreadContextEvent value, $Res Function(ThreadContextEvent) _then) = _$ThreadContextEventCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp stamp, ThreadContextValue value
});


$ThreadFacetStampCopyWith<$Res> get stamp;$ThreadContextValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadContextEventCopyWithImpl<$Res>
    implements $ThreadContextEventCopyWith<$Res> {
  _$ThreadContextEventCopyWithImpl(this._self, this._then);

  final ThreadContextEvent _self;
  final $Res Function(ThreadContextEvent) _then;

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadContextValue,
  ));
}
/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<$Res> get value {

  return $ThreadContextValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadContextEvent].
extension ThreadContextEventPatterns on ThreadContextEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadContextBaselineEvent value)?  baseline,TResult Function( ThreadContextReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadContextBaselineEvent() when baseline != null:
return baseline(_that);case ThreadContextReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadContextBaselineEvent value)  baseline,required TResult Function( ThreadContextReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case ThreadContextBaselineEvent():
return baseline(_that);case ThreadContextReplaceEvent():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadContextBaselineEvent value)?  baseline,TResult? Function( ThreadContextReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case ThreadContextBaselineEvent() when baseline != null:
return baseline(_that);case ThreadContextReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadContextValue value)?  baseline,TResult Function( ThreadFacetStamp stamp,  ThreadContextValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadContextBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadContextReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadContextValue value)  baseline,required TResult Function( ThreadFacetStamp stamp,  ThreadContextValue value)  replace,}) {final _that = this;
switch (_that) {
case ThreadContextBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadContextReplaceEvent():
return replace(_that.stamp,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadContextValue value)?  baseline,TResult? Function( ThreadFacetStamp stamp,  ThreadContextValue value)?  replace,}) {final _that = this;
switch (_that) {
case ThreadContextBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadContextReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadContextBaselineEvent implements ThreadContextEvent {
  const ThreadContextBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ThreadFeedIdentity identity;
@override final  ThreadFacetStamp stamp;
@override final  ThreadContextValue value;

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextBaselineEventCopyWith<ThreadContextBaselineEvent> get copyWith => _$ThreadContextBaselineEventCopyWithImpl<ThreadContextBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadContextBaselineEventCopyWith<$Res> implements $ThreadContextEventCopyWith<$Res> {
  factory $ThreadContextBaselineEventCopyWith(ThreadContextBaselineEvent value, $Res Function(ThreadContextBaselineEvent) _then) = _$ThreadContextBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFacetStamp stamp, ThreadContextValue value
});


$ThreadFeedIdentityCopyWith<$Res> get identity;@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadContextValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadContextBaselineEventCopyWithImpl<$Res>
    implements $ThreadContextBaselineEventCopyWith<$Res> {
  _$ThreadContextBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadContextBaselineEvent _self;
  final $Res Function(ThreadContextBaselineEvent) _then;

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadContextBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadContextValue,
  ));
}

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<$Res> get value {

  return $ThreadContextValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadContextReplaceEvent implements ThreadContextEvent {
  const ThreadContextReplaceEvent({required this.stamp, required this.value});


@override final  ThreadFacetStamp stamp;
@override final  ThreadContextValue value;

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadContextReplaceEventCopyWith<ThreadContextReplaceEvent> get copyWith => _$ThreadContextReplaceEventCopyWithImpl<ThreadContextReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadContextReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadContextReplaceEventCopyWith<$Res> implements $ThreadContextEventCopyWith<$Res> {
  factory $ThreadContextReplaceEventCopyWith(ThreadContextReplaceEvent value, $Res Function(ThreadContextReplaceEvent) _then) = _$ThreadContextReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp stamp, ThreadContextValue value
});


@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadContextValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadContextReplaceEventCopyWithImpl<$Res>
    implements $ThreadContextReplaceEventCopyWith<$Res> {
  _$ThreadContextReplaceEventCopyWithImpl(this._self, this._then);

  final ThreadContextReplaceEvent _self;
  final $Res Function(ThreadContextReplaceEvent) _then;

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(ThreadContextReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadContextValue,
  ));
}

/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadContextEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadContextValueCopyWith<$Res> get value {

  return $ThreadContextValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadConfigurationFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadConfigurationFrameCopyWith<$Res>  {
$ThreadConfigurationFrameCopyWith(ThreadConfigurationFrame _, $Res Function(ThreadConfigurationFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadConfigurationFrame].
extension ThreadConfigurationFramePatterns on ThreadConfigurationFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadConfigurationData value)?  data,TResult Function( ThreadConfigurationResyncRequired value)?  resyncRequired,TResult Function( ThreadConfigurationFailure value)?  failure,TResult Function( ThreadConfigurationClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadConfigurationData() when data != null:
return data(_that);case ThreadConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadConfigurationFailure() when failure != null:
return failure(_that);case ThreadConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadConfigurationData value)  data,required TResult Function( ThreadConfigurationResyncRequired value)  resyncRequired,required TResult Function( ThreadConfigurationFailure value)  failure,required TResult Function( ThreadConfigurationClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadConfigurationData():
return data(_that);case ThreadConfigurationResyncRequired():
return resyncRequired(_that);case ThreadConfigurationFailure():
return failure(_that);case ThreadConfigurationClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadConfigurationData value)?  data,TResult? Function( ThreadConfigurationResyncRequired value)?  resyncRequired,TResult? Function( ThreadConfigurationFailure value)?  failure,TResult? Function( ThreadConfigurationClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadConfigurationData() when data != null:
return data(_that);case ThreadConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadConfigurationFailure() when failure != null:
return failure(_that);case ThreadConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadConfigurationEvent event)?  data,TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadConfigurationData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadConfigurationFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadConfigurationClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadConfigurationEvent event)  data,required TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)  resyncRequired,required TResult Function( ThreadFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadConfigurationData():
return data(_that.deliverySequence,_that.event);case ThreadConfigurationResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadConfigurationFailure():
return failure(_that.identity,_that.error);case ThreadConfigurationClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadConfigurationEvent event)?  data,TResult? Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult? Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadConfigurationData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadConfigurationResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadConfigurationFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadConfigurationClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadConfigurationData implements ThreadConfigurationFrame {
  const ThreadConfigurationData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadConfigurationEvent event;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationDataCopyWith<ThreadConfigurationData> get copyWith => _$ThreadConfigurationDataCopyWithImpl<ThreadConfigurationData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationDataCopyWith<$Res> implements $ThreadConfigurationFrameCopyWith<$Res> {
  factory $ThreadConfigurationDataCopyWith(ThreadConfigurationData value, $Res Function(ThreadConfigurationData) _then) = _$ThreadConfigurationDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadConfigurationEvent event
});


$ThreadConfigurationEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadConfigurationDataCopyWithImpl<$Res>
    implements $ThreadConfigurationDataCopyWith<$Res> {
  _$ThreadConfigurationDataCopyWithImpl(this._self, this._then);

  final ThreadConfigurationData _self;
  final $Res Function(ThreadConfigurationData) _then;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadConfigurationData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationEvent,
  ));
}

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationEventCopyWith<$Res> get event {

  return $ThreadConfigurationEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadConfigurationResyncRequired implements ThreadConfigurationFrame {
  const ThreadConfigurationResyncRequired({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadResyncReason reason;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationResyncRequiredCopyWith<ThreadConfigurationResyncRequired> get copyWith => _$ThreadConfigurationResyncRequiredCopyWithImpl<ThreadConfigurationResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationResyncRequiredCopyWith<$Res> implements $ThreadConfigurationFrameCopyWith<$Res> {
  factory $ThreadConfigurationResyncRequiredCopyWith(ThreadConfigurationResyncRequired value, $Res Function(ThreadConfigurationResyncRequired) _then) = _$ThreadConfigurationResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadResyncReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadConfigurationResyncRequiredCopyWithImpl<$Res>
    implements $ThreadConfigurationResyncRequiredCopyWith<$Res> {
  _$ThreadConfigurationResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadConfigurationResyncRequired _self;
  final $Res Function(ThreadConfigurationResyncRequired) _then;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadConfigurationResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadResyncReason,
  ));
}

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class ThreadConfigurationFailure implements ThreadConfigurationFrame {
  const ThreadConfigurationFailure({required this.identity, required this.error});


 final  ThreadFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationFailureCopyWith<ThreadConfigurationFailure> get copyWith => _$ThreadConfigurationFailureCopyWithImpl<ThreadConfigurationFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationFailureCopyWith<$Res> implements $ThreadConfigurationFrameCopyWith<$Res> {
  factory $ThreadConfigurationFailureCopyWith(ThreadConfigurationFailure value, $Res Function(ThreadConfigurationFailure) _then) = _$ThreadConfigurationFailureCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, StudioFailure error
});


$ThreadFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadConfigurationFailureCopyWithImpl<$Res>
    implements $ThreadConfigurationFailureCopyWith<$Res> {
  _$ThreadConfigurationFailureCopyWithImpl(this._self, this._then);

  final ThreadConfigurationFailure _self;
  final $Res Function(ThreadConfigurationFailure) _then;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadConfigurationFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadConfigurationFrame
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


class ThreadConfigurationClosed implements ThreadConfigurationFrame {
  const ThreadConfigurationClosed({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadFeedClosedReason reason;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationClosedCopyWith<ThreadConfigurationClosed> get copyWith => _$ThreadConfigurationClosedCopyWithImpl<ThreadConfigurationClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationClosedCopyWith<$Res> implements $ThreadConfigurationFrameCopyWith<$Res> {
  factory $ThreadConfigurationClosedCopyWith(ThreadConfigurationClosed value, $Res Function(ThreadConfigurationClosed) _then) = _$ThreadConfigurationClosedCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFeedClosedReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadConfigurationClosedCopyWithImpl<$Res>
    implements $ThreadConfigurationClosedCopyWith<$Res> {
  _$ThreadConfigurationClosedCopyWithImpl(this._self, this._then);

  final ThreadConfigurationClosed _self;
  final $Res Function(ThreadConfigurationClosed) _then;

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadConfigurationClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadFeedClosedReason,
  ));
}

/// Create a copy of ThreadConfigurationFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$ThreadConfigurationEvent {

 ThreadFacetStamp get stamp; ThreadConfigurationValue get value;
/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationEventCopyWith<ThreadConfigurationEvent> get copyWith => _$ThreadConfigurationEventCopyWithImpl<ThreadConfigurationEvent>(this as ThreadConfigurationEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadConfigurationEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadConfigurationEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationEventCopyWith<$Res>  {
  factory $ThreadConfigurationEventCopyWith(ThreadConfigurationEvent value, $Res Function(ThreadConfigurationEvent) _then) = _$ThreadConfigurationEventCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp stamp, ThreadConfigurationValue value
});


$ThreadFacetStampCopyWith<$Res> get stamp;$ThreadConfigurationValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadConfigurationEventCopyWithImpl<$Res>
    implements $ThreadConfigurationEventCopyWith<$Res> {
  _$ThreadConfigurationEventCopyWithImpl(this._self, this._then);

  final ThreadConfigurationEvent _self;
  final $Res Function(ThreadConfigurationEvent) _then;

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationValue,
  ));
}
/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<$Res> get value {

  return $ThreadConfigurationValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadConfigurationEvent].
extension ThreadConfigurationEventPatterns on ThreadConfigurationEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadConfigurationBaselineEvent value)?  baseline,TResult Function( ThreadConfigurationReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent() when baseline != null:
return baseline(_that);case ThreadConfigurationReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadConfigurationBaselineEvent value)  baseline,required TResult Function( ThreadConfigurationReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent():
return baseline(_that);case ThreadConfigurationReplaceEvent():
return replace(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadConfigurationBaselineEvent value)?  baseline,TResult? Function( ThreadConfigurationReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent() when baseline != null:
return baseline(_that);case ThreadConfigurationReplaceEvent() when replace != null:
return replace(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadConfigurationValue value)?  baseline,TResult Function( ThreadFacetStamp stamp,  ThreadConfigurationValue value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadConfigurationReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadConfigurationValue value)  baseline,required TResult Function( ThreadFacetStamp stamp,  ThreadConfigurationValue value)  replace,}) {final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadConfigurationReplaceEvent():
return replace(_that.stamp,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadConfigurationValue value)?  baseline,TResult? Function( ThreadFacetStamp stamp,  ThreadConfigurationValue value)?  replace,}) {final _that = this;
switch (_that) {
case ThreadConfigurationBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadConfigurationReplaceEvent() when replace != null:
return replace(_that.stamp,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadConfigurationBaselineEvent implements ThreadConfigurationEvent {
  const ThreadConfigurationBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ThreadFeedIdentity identity;
@override final  ThreadFacetStamp stamp;
@override final  ThreadConfigurationValue value;

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationBaselineEventCopyWith<ThreadConfigurationBaselineEvent> get copyWith => _$ThreadConfigurationBaselineEventCopyWithImpl<ThreadConfigurationBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationBaselineEventCopyWith<$Res> implements $ThreadConfigurationEventCopyWith<$Res> {
  factory $ThreadConfigurationBaselineEventCopyWith(ThreadConfigurationBaselineEvent value, $Res Function(ThreadConfigurationBaselineEvent) _then) = _$ThreadConfigurationBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFacetStamp stamp, ThreadConfigurationValue value
});


$ThreadFeedIdentityCopyWith<$Res> get identity;@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadConfigurationValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadConfigurationBaselineEventCopyWithImpl<$Res>
    implements $ThreadConfigurationBaselineEventCopyWith<$Res> {
  _$ThreadConfigurationBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadConfigurationBaselineEvent _self;
  final $Res Function(ThreadConfigurationBaselineEvent) _then;

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadConfigurationBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationValue,
  ));
}

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<$Res> get value {

  return $ThreadConfigurationValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadConfigurationReplaceEvent implements ThreadConfigurationEvent {
  const ThreadConfigurationReplaceEvent({required this.stamp, required this.value});


@override final  ThreadFacetStamp stamp;
@override final  ThreadConfigurationValue value;

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadConfigurationReplaceEventCopyWith<ThreadConfigurationReplaceEvent> get copyWith => _$ThreadConfigurationReplaceEventCopyWithImpl<ThreadConfigurationReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadConfigurationReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadConfigurationReplaceEventCopyWith<$Res> implements $ThreadConfigurationEventCopyWith<$Res> {
  factory $ThreadConfigurationReplaceEventCopyWith(ThreadConfigurationReplaceEvent value, $Res Function(ThreadConfigurationReplaceEvent) _then) = _$ThreadConfigurationReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp stamp, ThreadConfigurationValue value
});


@override $ThreadFacetStampCopyWith<$Res> get stamp;@override $ThreadConfigurationValueCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadConfigurationReplaceEventCopyWithImpl<$Res>
    implements $ThreadConfigurationReplaceEventCopyWith<$Res> {
  _$ThreadConfigurationReplaceEventCopyWithImpl(this._self, this._then);

  final ThreadConfigurationReplaceEvent _self;
  final $Res Function(ThreadConfigurationReplaceEvent) _then;

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(ThreadConfigurationReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadConfigurationValue,
  ));
}

/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadConfigurationEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadConfigurationValueCopyWith<$Res> get value {

  return $ThreadConfigurationValueCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$ThreadAuthoringFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $ThreadAuthoringFrameCopyWith<$Res>  {
$ThreadAuthoringFrameCopyWith(ThreadAuthoringFrame _, $Res Function(ThreadAuthoringFrame) __);
}


/// Adds pattern-matching-related methods to [ThreadAuthoringFrame].
extension ThreadAuthoringFramePatterns on ThreadAuthoringFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadAuthoringData value)?  data,TResult Function( ThreadAuthoringResyncRequired value)?  resyncRequired,TResult Function( ThreadAuthoringFailure value)?  failure,TResult Function( ThreadAuthoringClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadAuthoringData() when data != null:
return data(_that);case ThreadAuthoringResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadAuthoringFailure() when failure != null:
return failure(_that);case ThreadAuthoringClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadAuthoringData value)  data,required TResult Function( ThreadAuthoringResyncRequired value)  resyncRequired,required TResult Function( ThreadAuthoringFailure value)  failure,required TResult Function( ThreadAuthoringClosed value)  closed,}){
final _that = this;
switch (_that) {
case ThreadAuthoringData():
return data(_that);case ThreadAuthoringResyncRequired():
return resyncRequired(_that);case ThreadAuthoringFailure():
return failure(_that);case ThreadAuthoringClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadAuthoringData value)?  data,TResult? Function( ThreadAuthoringResyncRequired value)?  resyncRequired,TResult? Function( ThreadAuthoringFailure value)?  failure,TResult? Function( ThreadAuthoringClosed value)?  closed,}){
final _that = this;
switch (_that) {
case ThreadAuthoringData() when data != null:
return data(_that);case ThreadAuthoringResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case ThreadAuthoringFailure() when failure != null:
return failure(_that);case ThreadAuthoringClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  ThreadAuthoringEvent event)?  data,TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadAuthoringData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadAuthoringResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadAuthoringFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadAuthoringClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  ThreadAuthoringEvent event)  data,required TResult Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)  resyncRequired,required TResult Function( ThreadFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)  closed,}) {final _that = this;
switch (_that) {
case ThreadAuthoringData():
return data(_that.deliverySequence,_that.event);case ThreadAuthoringResyncRequired():
return resyncRequired(_that.identity,_that.reason);case ThreadAuthoringFailure():
return failure(_that.identity,_that.error);case ThreadAuthoringClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  ThreadAuthoringEvent event)?  data,TResult? Function( ThreadFeedIdentity identity,  ThreadResyncReason reason)?  resyncRequired,TResult? Function( ThreadFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ThreadFeedIdentity identity,  ThreadFeedClosedReason reason)?  closed,}) {final _that = this;
switch (_that) {
case ThreadAuthoringData() when data != null:
return data(_that.deliverySequence,_that.event);case ThreadAuthoringResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case ThreadAuthoringFailure() when failure != null:
return failure(_that.identity,_that.error);case ThreadAuthoringClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class ThreadAuthoringData implements ThreadAuthoringFrame {
  const ThreadAuthoringData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  ThreadAuthoringEvent event;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringDataCopyWith<ThreadAuthoringData> get copyWith => _$ThreadAuthoringDataCopyWithImpl<ThreadAuthoringData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringDataCopyWith<$Res> implements $ThreadAuthoringFrameCopyWith<$Res> {
  factory $ThreadAuthoringDataCopyWith(ThreadAuthoringData value, $Res Function(ThreadAuthoringData) _then) = _$ThreadAuthoringDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, ThreadAuthoringEvent event
});


$ThreadAuthoringEventCopyWith<$Res> get event;

}
/// @nodoc
class _$ThreadAuthoringDataCopyWithImpl<$Res>
    implements $ThreadAuthoringDataCopyWith<$Res> {
  _$ThreadAuthoringDataCopyWithImpl(this._self, this._then);

  final ThreadAuthoringData _self;
  final $Res Function(ThreadAuthoringData) _then;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(ThreadAuthoringData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as ThreadAuthoringEvent,
  ));
}

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAuthoringEventCopyWith<$Res> get event {

  return $ThreadAuthoringEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class ThreadAuthoringResyncRequired implements ThreadAuthoringFrame {
  const ThreadAuthoringResyncRequired({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadResyncReason reason;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringResyncRequiredCopyWith<ThreadAuthoringResyncRequired> get copyWith => _$ThreadAuthoringResyncRequiredCopyWithImpl<ThreadAuthoringResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringResyncRequiredCopyWith<$Res> implements $ThreadAuthoringFrameCopyWith<$Res> {
  factory $ThreadAuthoringResyncRequiredCopyWith(ThreadAuthoringResyncRequired value, $Res Function(ThreadAuthoringResyncRequired) _then) = _$ThreadAuthoringResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadResyncReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadAuthoringResyncRequiredCopyWithImpl<$Res>
    implements $ThreadAuthoringResyncRequiredCopyWith<$Res> {
  _$ThreadAuthoringResyncRequiredCopyWithImpl(this._self, this._then);

  final ThreadAuthoringResyncRequired _self;
  final $Res Function(ThreadAuthoringResyncRequired) _then;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadAuthoringResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadResyncReason,
  ));
}

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc


class ThreadAuthoringFailure implements ThreadAuthoringFrame {
  const ThreadAuthoringFailure({required this.identity, required this.error});


 final  ThreadFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringFailureCopyWith<ThreadAuthoringFailure> get copyWith => _$ThreadAuthoringFailureCopyWithImpl<ThreadAuthoringFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringFailureCopyWith<$Res> implements $ThreadAuthoringFrameCopyWith<$Res> {
  factory $ThreadAuthoringFailureCopyWith(ThreadAuthoringFailure value, $Res Function(ThreadAuthoringFailure) _then) = _$ThreadAuthoringFailureCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, StudioFailure error
});


$ThreadFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$ThreadAuthoringFailureCopyWithImpl<$Res>
    implements $ThreadAuthoringFailureCopyWith<$Res> {
  _$ThreadAuthoringFailureCopyWithImpl(this._self, this._then);

  final ThreadAuthoringFailure _self;
  final $Res Function(ThreadAuthoringFailure) _then;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(ThreadAuthoringFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadAuthoringFrame
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


class ThreadAuthoringClosed implements ThreadAuthoringFrame {
  const ThreadAuthoringClosed({required this.identity, required this.reason});


 final  ThreadFeedIdentity identity;
 final  ThreadFeedClosedReason reason;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringClosedCopyWith<ThreadAuthoringClosed> get copyWith => _$ThreadAuthoringClosedCopyWithImpl<ThreadAuthoringClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringClosedCopyWith<$Res> implements $ThreadAuthoringFrameCopyWith<$Res> {
  factory $ThreadAuthoringClosedCopyWith(ThreadAuthoringClosed value, $Res Function(ThreadAuthoringClosed) _then) = _$ThreadAuthoringClosedCopyWithImpl;
@useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFeedClosedReason reason
});


$ThreadFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$ThreadAuthoringClosedCopyWithImpl<$Res>
    implements $ThreadAuthoringClosedCopyWith<$Res> {
  _$ThreadAuthoringClosedCopyWithImpl(this._self, this._then);

  final ThreadAuthoringClosed _self;
  final $Res Function(ThreadAuthoringClosed) _then;

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(ThreadAuthoringClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ThreadFeedClosedReason,
  ));
}

/// Create a copy of ThreadAuthoringFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

/// @nodoc
mixin _$ThreadAuthoringEvent {

 ThreadFacetStamp get stamp; Object get value;
/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringEventCopyWith<ThreadAuthoringEvent> get copyWith => _$ThreadAuthoringEventCopyWithImpl<ThreadAuthoringEvent>(this as ThreadAuthoringEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as ThreadAuthoringEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as ThreadAuthoringEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringEventCopyWith<$Res>  {
  factory $ThreadAuthoringEventCopyWith(ThreadAuthoringEvent value, $Res Function(ThreadAuthoringEvent) _then) = _$ThreadAuthoringEventCopyWithImpl;
@useResult
$Res call({
 ThreadFacetStamp stamp
});


$ThreadFacetStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$ThreadAuthoringEventCopyWithImpl<$Res>
    implements $ThreadAuthoringEventCopyWith<$Res> {
  _$ThreadAuthoringEventCopyWithImpl(this._self, this._then);

  final ThreadAuthoringEvent _self;
  final $Res Function(ThreadAuthoringEvent) _then;

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,
  ));
}
/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [ThreadAuthoringEvent].
extension ThreadAuthoringEventPatterns on ThreadAuthoringEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( ThreadAuthoringBaselineEvent value)?  baseline,TResult Function( ThreadAuthoringChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent() when baseline != null:
return baseline(_that);case ThreadAuthoringChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( ThreadAuthoringBaselineEvent value)  baseline,required TResult Function( ThreadAuthoringChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent():
return baseline(_that);case ThreadAuthoringChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( ThreadAuthoringBaselineEvent value)?  baseline,TResult? Function( ThreadAuthoringChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent() when baseline != null:
return baseline(_that);case ThreadAuthoringChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadAuthoringBaseline value)?  baseline,TResult Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadAuthoringChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadAuthoringChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadAuthoringBaseline value)  baseline,required TResult Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadAuthoringChange value)  change,}) {final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case ThreadAuthoringChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ThreadFeedIdentity identity,  ThreadFacetStamp stamp,  ThreadAuthoringBaseline value)?  baseline,TResult? Function( ThreadFacetStamp stamp,  int baseRevision,  ThreadAuthoringChange value)?  change,}) {final _that = this;
switch (_that) {
case ThreadAuthoringBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case ThreadAuthoringChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class ThreadAuthoringBaselineEvent implements ThreadAuthoringEvent {
  const ThreadAuthoringBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ThreadFeedIdentity identity;
@override final  ThreadFacetStamp stamp;
@override final  ThreadAuthoringBaseline value;

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringBaselineEventCopyWith<ThreadAuthoringBaselineEvent> get copyWith => _$ThreadAuthoringBaselineEventCopyWithImpl<ThreadAuthoringBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringBaselineEventCopyWith<$Res> implements $ThreadAuthoringEventCopyWith<$Res> {
  factory $ThreadAuthoringBaselineEventCopyWith(ThreadAuthoringBaselineEvent value, $Res Function(ThreadAuthoringBaselineEvent) _then) = _$ThreadAuthoringBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFeedIdentity identity, ThreadFacetStamp stamp, ThreadAuthoringBaseline value
});


$ThreadFeedIdentityCopyWith<$Res> get identity;@override $ThreadFacetStampCopyWith<$Res> get stamp;$ThreadAuthoringBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadAuthoringBaselineEventCopyWithImpl<$Res>
    implements $ThreadAuthoringBaselineEventCopyWith<$Res> {
  _$ThreadAuthoringBaselineEventCopyWithImpl(this._self, this._then);

  final ThreadAuthoringBaselineEvent _self;
  final $Res Function(ThreadAuthoringBaselineEvent) _then;

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(ThreadAuthoringBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ThreadFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadAuthoringBaseline,
  ));
}

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFeedIdentityCopyWith<$Res> get identity {

  return $ThreadFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAuthoringBaselineCopyWith<$Res> get value {

  return $ThreadAuthoringBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class ThreadAuthoringChangeEvent implements ThreadAuthoringEvent {
  const ThreadAuthoringChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ThreadFacetStamp stamp;
 final  int baseRevision;
@override final  ThreadAuthoringChange value;

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ThreadAuthoringChangeEventCopyWith<ThreadAuthoringChangeEvent> get copyWith => _$ThreadAuthoringChangeEventCopyWithImpl<ThreadAuthoringChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is ThreadAuthoringChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $ThreadAuthoringChangeEventCopyWith<$Res> implements $ThreadAuthoringEventCopyWith<$Res> {
  factory $ThreadAuthoringChangeEventCopyWith(ThreadAuthoringChangeEvent value, $Res Function(ThreadAuthoringChangeEvent) _then) = _$ThreadAuthoringChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ThreadFacetStamp stamp, int baseRevision, ThreadAuthoringChange value
});


@override $ThreadFacetStampCopyWith<$Res> get stamp;$ThreadAuthoringChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$ThreadAuthoringChangeEventCopyWithImpl<$Res>
    implements $ThreadAuthoringChangeEventCopyWith<$Res> {
  _$ThreadAuthoringChangeEventCopyWithImpl(this._self, this._then);

  final ThreadAuthoringChangeEvent _self;
  final $Res Function(ThreadAuthoringChangeEvent) _then;

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(ThreadAuthoringChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ThreadFacetStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as ThreadAuthoringChange,
  ));
}

/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadFacetStampCopyWith<$Res> get stamp {

  return $ThreadFacetStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of ThreadAuthoringEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ThreadAuthoringChangeCopyWith<$Res> get value {

  return $ThreadAuthoringChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
