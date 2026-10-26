// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'session_costs_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SessionCostsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $SessionCostsFrameCopyWith<$Res>  {
$SessionCostsFrameCopyWith(SessionCostsFrame _, $Res Function(SessionCostsFrame) __);
}


/// Adds pattern-matching-related methods to [SessionCostsFrame].
extension SessionCostsFramePatterns on SessionCostsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionCostsData value)?  data,TResult Function( SessionCostsResyncRequired value)?  resyncRequired,TResult Function( SessionCostsFeedFailure value)?  failure,TResult Function( SessionCostsClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionCostsData() when data != null:
return data(_that);case SessionCostsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case SessionCostsFeedFailure() when failure != null:
return failure(_that);case SessionCostsClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionCostsData value)  data,required TResult Function( SessionCostsResyncRequired value)  resyncRequired,required TResult Function( SessionCostsFeedFailure value)  failure,required TResult Function( SessionCostsClosed value)  closed,}){
final _that = this;
switch (_that) {
case SessionCostsData():
return data(_that);case SessionCostsResyncRequired():
return resyncRequired(_that);case SessionCostsFeedFailure():
return failure(_that);case SessionCostsClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionCostsData value)?  data,TResult? Function( SessionCostsResyncRequired value)?  resyncRequired,TResult? Function( SessionCostsFeedFailure value)?  failure,TResult? Function( SessionCostsClosed value)?  closed,}){
final _that = this;
switch (_that) {
case SessionCostsData() when data != null:
return data(_that);case SessionCostsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case SessionCostsFeedFailure() when failure != null:
return failure(_that);case SessionCostsClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  SessionCostsEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionCostsData() when data != null:
return data(_that.deliverySequence,_that.event);case SessionCostsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case SessionCostsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case SessionCostsClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  SessionCostsEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case SessionCostsData():
return data(_that.deliverySequence,_that.event);case SessionCostsResyncRequired():
return resyncRequired(_that.identity,_that.reason);case SessionCostsFeedFailure():
return failure(_that.identity,_that.error);case SessionCostsClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  SessionCostsEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case SessionCostsData() when data != null:
return data(_that.deliverySequence,_that.event);case SessionCostsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case SessionCostsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case SessionCostsClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class SessionCostsData implements SessionCostsFrame {
  const SessionCostsData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  SessionCostsEvent event;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsDataCopyWith<SessionCostsData> get copyWith => _$SessionCostsDataCopyWithImpl<SessionCostsData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $SessionCostsDataCopyWith<$Res> implements $SessionCostsFrameCopyWith<$Res> {
  factory $SessionCostsDataCopyWith(SessionCostsData value, $Res Function(SessionCostsData) _then) = _$SessionCostsDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, SessionCostsEvent event
});


$SessionCostsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$SessionCostsDataCopyWithImpl<$Res>
    implements $SessionCostsDataCopyWith<$Res> {
  _$SessionCostsDataCopyWithImpl(this._self, this._then);

  final SessionCostsData _self;
  final $Res Function(SessionCostsData) _then;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(SessionCostsData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as SessionCostsEvent,
  ));
}

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsEventCopyWith<$Res> get event {

  return $SessionCostsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class SessionCostsResyncRequired implements SessionCostsFrame {
  const SessionCostsResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsResyncRequiredCopyWith<SessionCostsResyncRequired> get copyWith => _$SessionCostsResyncRequiredCopyWithImpl<SessionCostsResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $SessionCostsResyncRequiredCopyWith<$Res> implements $SessionCostsFrameCopyWith<$Res> {
  factory $SessionCostsResyncRequiredCopyWith(SessionCostsResyncRequired value, $Res Function(SessionCostsResyncRequired) _then) = _$SessionCostsResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$SessionCostsResyncRequiredCopyWithImpl<$Res>
    implements $SessionCostsResyncRequiredCopyWith<$Res> {
  _$SessionCostsResyncRequiredCopyWithImpl(this._self, this._then);

  final SessionCostsResyncRequired _self;
  final $Res Function(SessionCostsResyncRequired) _then;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(SessionCostsResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of SessionCostsFrame
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


class SessionCostsFeedFailure implements SessionCostsFrame {
  const SessionCostsFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsFeedFailureCopyWith<SessionCostsFeedFailure> get copyWith => _$SessionCostsFeedFailureCopyWithImpl<SessionCostsFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $SessionCostsFeedFailureCopyWith<$Res> implements $SessionCostsFrameCopyWith<$Res> {
  factory $SessionCostsFeedFailureCopyWith(SessionCostsFeedFailure value, $Res Function(SessionCostsFeedFailure) _then) = _$SessionCostsFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$SessionCostsFeedFailureCopyWithImpl<$Res>
    implements $SessionCostsFeedFailureCopyWith<$Res> {
  _$SessionCostsFeedFailureCopyWithImpl(this._self, this._then);

  final SessionCostsFeedFailure _self;
  final $Res Function(SessionCostsFeedFailure) _then;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(SessionCostsFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of SessionCostsFrame
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


class SessionCostsClosed implements SessionCostsFrame {
  const SessionCostsClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsClosedCopyWith<SessionCostsClosed> get copyWith => _$SessionCostsClosedCopyWithImpl<SessionCostsClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $SessionCostsClosedCopyWith<$Res> implements $SessionCostsFrameCopyWith<$Res> {
  factory $SessionCostsClosedCopyWith(SessionCostsClosed value, $Res Function(SessionCostsClosed) _then) = _$SessionCostsClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$SessionCostsClosedCopyWithImpl<$Res>
    implements $SessionCostsClosedCopyWith<$Res> {
  _$SessionCostsClosedCopyWithImpl(this._self, this._then);

  final SessionCostsClosed _self;
  final $Res Function(SessionCostsClosed) _then;

/// Create a copy of SessionCostsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(SessionCostsClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of SessionCostsFrame
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
mixin _$SessionCostsEvent {

 ProductProjectionStamp get stamp; SessionCostsHeader get value;
/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsEventCopyWith<SessionCostsEvent> get copyWith => _$SessionCostsEventCopyWithImpl<SessionCostsEvent>(this as SessionCostsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as SessionCostsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as SessionCostsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}



}

/// @nodoc
abstract mixin class $SessionCostsEventCopyWith<$Res>  {
  factory $SessionCostsEventCopyWith(SessionCostsEvent value, $Res Function(SessionCostsEvent) _then) = _$SessionCostsEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, SessionCostsHeader value
});


$ProductProjectionStampCopyWith<$Res> get stamp;$SessionCostsHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$SessionCostsEventCopyWithImpl<$Res>
    implements $SessionCostsEventCopyWith<$Res> {
  _$SessionCostsEventCopyWithImpl(this._self, this._then);

  final SessionCostsEvent _self;
  final $Res Function(SessionCostsEvent) _then;

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionCostsHeader,
  ));
}
/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsHeaderCopyWith<$Res> get value {

  return $SessionCostsHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [SessionCostsEvent].
extension SessionCostsEventPatterns on SessionCostsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( SessionCostsBaselineEvent value)?  baseline,TResult Function( SessionCostsReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case SessionCostsBaselineEvent() when baseline != null:
return baseline(_that);case SessionCostsReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( SessionCostsBaselineEvent value)  baseline,required TResult Function( SessionCostsReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case SessionCostsBaselineEvent():
return baseline(_that);case SessionCostsReplaceEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( SessionCostsBaselineEvent value)?  baseline,TResult? Function( SessionCostsReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case SessionCostsBaselineEvent() when baseline != null:
return baseline(_that);case SessionCostsReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SessionCostsHeader value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  SessionCostsHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case SessionCostsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case SessionCostsReplaceEvent() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SessionCostsHeader value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  SessionCostsHeader value)  replace,}) {final _that = this;
switch (_that) {
case SessionCostsBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case SessionCostsReplaceEvent():
return replace(_that.stamp,_that.baseRevision,_that.value);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  SessionCostsHeader value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  SessionCostsHeader value)?  replace,}) {final _that = this;
switch (_that) {
case SessionCostsBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case SessionCostsReplaceEvent() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class SessionCostsBaselineEvent implements SessionCostsEvent {
  const SessionCostsBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  SessionCostsHeader value;

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsBaselineEventCopyWith<SessionCostsBaselineEvent> get copyWith => _$SessionCostsBaselineEventCopyWithImpl<SessionCostsBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}



}

/// @nodoc
abstract mixin class $SessionCostsBaselineEventCopyWith<$Res> implements $SessionCostsEventCopyWith<$Res> {
  factory $SessionCostsBaselineEventCopyWith(SessionCostsBaselineEvent value, $Res Function(SessionCostsBaselineEvent) _then) = _$SessionCostsBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, SessionCostsHeader value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $SessionCostsHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$SessionCostsBaselineEventCopyWithImpl<$Res>
    implements $SessionCostsBaselineEventCopyWith<$Res> {
  _$SessionCostsBaselineEventCopyWithImpl(this._self, this._then);

  final SessionCostsBaselineEvent _self;
  final $Res Function(SessionCostsBaselineEvent) _then;

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(SessionCostsBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionCostsHeader,
  ));
}

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsHeaderCopyWith<$Res> get value {

  return $SessionCostsHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class SessionCostsReplaceEvent implements SessionCostsEvent {
  const SessionCostsReplaceEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  SessionCostsHeader value;

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SessionCostsReplaceEventCopyWith<SessionCostsReplaceEvent> get copyWith => _$SessionCostsReplaceEventCopyWithImpl<SessionCostsReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is SessionCostsReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}



}

/// @nodoc
abstract mixin class $SessionCostsReplaceEventCopyWith<$Res> implements $SessionCostsEventCopyWith<$Res> {
  factory $SessionCostsReplaceEventCopyWith(SessionCostsReplaceEvent value, $Res Function(SessionCostsReplaceEvent) _then) = _$SessionCostsReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, SessionCostsHeader value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $SessionCostsHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$SessionCostsReplaceEventCopyWithImpl<$Res>
    implements $SessionCostsReplaceEventCopyWith<$Res> {
  _$SessionCostsReplaceEventCopyWithImpl(this._self, this._then);

  final SessionCostsReplaceEvent _self;
  final $Res Function(SessionCostsReplaceEvent) _then;

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(SessionCostsReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as SessionCostsHeader,
  ));
}

/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of SessionCostsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$SessionCostsHeaderCopyWith<$Res> get value {

  return $SessionCostsHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

// dart format on
