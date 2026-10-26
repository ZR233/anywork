// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'bots_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BotsFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $BotsFrameCopyWith<$Res>  {
$BotsFrameCopyWith(BotsFrame _, $Res Function(BotsFrame) __);
}


/// Adds pattern-matching-related methods to [BotsFrame].
extension BotsFramePatterns on BotsFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotsData value)?  data,TResult Function( BotsResyncRequired value)?  resyncRequired,TResult Function( BotsFeedFailure value)?  failure,TResult Function( BotsClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotsData() when data != null:
return data(_that);case BotsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BotsFeedFailure() when failure != null:
return failure(_that);case BotsClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotsData value)  data,required TResult Function( BotsResyncRequired value)  resyncRequired,required TResult Function( BotsFeedFailure value)  failure,required TResult Function( BotsClosed value)  closed,}){
final _that = this;
switch (_that) {
case BotsData():
return data(_that);case BotsResyncRequired():
return resyncRequired(_that);case BotsFeedFailure():
return failure(_that);case BotsClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotsData value)?  data,TResult? Function( BotsResyncRequired value)?  resyncRequired,TResult? Function( BotsFeedFailure value)?  failure,TResult? Function( BotsClosed value)?  closed,}){
final _that = this;
switch (_that) {
case BotsData() when data != null:
return data(_that);case BotsResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case BotsFeedFailure() when failure != null:
return failure(_that);case BotsClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  BotsEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BotsData() when data != null:
return data(_that.deliverySequence,_that.event);case BotsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BotsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case BotsClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  BotsEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case BotsData():
return data(_that.deliverySequence,_that.event);case BotsResyncRequired():
return resyncRequired(_that.identity,_that.reason);case BotsFeedFailure():
return failure(_that.identity,_that.error);case BotsClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  BotsEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case BotsData() when data != null:
return data(_that.deliverySequence,_that.event);case BotsResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case BotsFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case BotsClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class BotsData implements BotsFrame {
  const BotsData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  BotsEvent event;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsDataCopyWith<BotsData> get copyWith => _$BotsDataCopyWithImpl<BotsData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $BotsDataCopyWith<$Res> implements $BotsFrameCopyWith<$Res> {
  factory $BotsDataCopyWith(BotsData value, $Res Function(BotsData) _then) = _$BotsDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, BotsEvent event
});


$BotsEventCopyWith<$Res> get event;

}
/// @nodoc
class _$BotsDataCopyWithImpl<$Res>
    implements $BotsDataCopyWith<$Res> {
  _$BotsDataCopyWithImpl(this._self, this._then);

  final BotsData _self;
  final $Res Function(BotsData) _then;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(BotsData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as BotsEvent,
  ));
}

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsEventCopyWith<$Res> get event {

  return $BotsEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class BotsResyncRequired implements BotsFrame {
  const BotsResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsResyncRequiredCopyWith<BotsResyncRequired> get copyWith => _$BotsResyncRequiredCopyWithImpl<BotsResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $BotsResyncRequiredCopyWith<$Res> implements $BotsFrameCopyWith<$Res> {
  factory $BotsResyncRequiredCopyWith(BotsResyncRequired value, $Res Function(BotsResyncRequired) _then) = _$BotsResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$BotsResyncRequiredCopyWithImpl<$Res>
    implements $BotsResyncRequiredCopyWith<$Res> {
  _$BotsResyncRequiredCopyWithImpl(this._self, this._then);

  final BotsResyncRequired _self;
  final $Res Function(BotsResyncRequired) _then;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BotsResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of BotsFrame
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


class BotsFeedFailure implements BotsFrame {
  const BotsFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsFeedFailureCopyWith<BotsFeedFailure> get copyWith => _$BotsFeedFailureCopyWithImpl<BotsFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $BotsFeedFailureCopyWith<$Res> implements $BotsFrameCopyWith<$Res> {
  factory $BotsFeedFailureCopyWith(BotsFeedFailure value, $Res Function(BotsFeedFailure) _then) = _$BotsFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$BotsFeedFailureCopyWithImpl<$Res>
    implements $BotsFeedFailureCopyWith<$Res> {
  _$BotsFeedFailureCopyWithImpl(this._self, this._then);

  final BotsFeedFailure _self;
  final $Res Function(BotsFeedFailure) _then;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(BotsFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of BotsFrame
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


class BotsClosed implements BotsFrame {
  const BotsClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsClosedCopyWith<BotsClosed> get copyWith => _$BotsClosedCopyWithImpl<BotsClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $BotsClosedCopyWith<$Res> implements $BotsFrameCopyWith<$Res> {
  factory $BotsClosedCopyWith(BotsClosed value, $Res Function(BotsClosed) _then) = _$BotsClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$BotsClosedCopyWithImpl<$Res>
    implements $BotsClosedCopyWith<$Res> {
  _$BotsClosedCopyWithImpl(this._self, this._then);

  final BotsClosed _self;
  final $Res Function(BotsClosed) _then;

/// Create a copy of BotsFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(BotsClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of BotsFrame
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
mixin _$BotsEvent {

 ProductProjectionStamp get stamp; BotsHeader get header; BotsStateSnapshot? get state;
/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsEventCopyWith<BotsEvent> get copyWith => _$BotsEventCopyWithImpl<BotsEvent>(this as BotsEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as BotsEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.state, _this.state) || other.state == _this.state));
}


@override
int get hashCode {
  final _this = this as BotsEvent;
  return Object.hash(runtimeType,_this.stamp,_this.header,_this.state);
}



}

/// @nodoc
abstract mixin class $BotsEventCopyWith<$Res>  {
  factory $BotsEventCopyWith(BotsEvent value, $Res Function(BotsEvent) _then) = _$BotsEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, BotsHeader header, BotsStateSnapshot? state
});


$ProductProjectionStampCopyWith<$Res> get stamp;$BotsHeaderCopyWith<$Res> get header;$BotsStateSnapshotCopyWith<$Res>? get state;

}
/// @nodoc
class _$BotsEventCopyWithImpl<$Res>
    implements $BotsEventCopyWith<$Res> {
  _$BotsEventCopyWithImpl(this._self, this._then);

  final BotsEvent _self;
  final $Res Function(BotsEvent) _then;

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? header = null,Object? state = freezed,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BotsStateSnapshot?,
  ));
}
/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsHeaderCopyWith<$Res> get header {

  return $BotsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateSnapshotCopyWith<$Res>? get state {
    if (_self.state == null) {
    return null;
  }

  return $BotsStateSnapshotCopyWith<$Res>(_self.state!, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}


/// Adds pattern-matching-related methods to [BotsEvent].
extension BotsEventPatterns on BotsEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( BotsBaseline value)?  baseline,TResult Function( BotsStateChangedPayload value)?  stateChanged,required TResult orElse(),}){
final _that = this;
switch (_that) {
case BotsBaseline() when baseline != null:
return baseline(_that);case BotsStateChangedPayload() when stateChanged != null:
return stateChanged(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( BotsBaseline value)  baseline,required TResult Function( BotsStateChangedPayload value)  stateChanged,}){
final _that = this;
switch (_that) {
case BotsBaseline():
return baseline(_that);case BotsStateChangedPayload():
return stateChanged(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( BotsBaseline value)?  baseline,TResult? Function( BotsStateChangedPayload value)?  stateChanged,}){
final _that = this;
switch (_that) {
case BotsBaseline() when baseline != null:
return baseline(_that);case BotsStateChangedPayload() when stateChanged != null:
return stateChanged(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  BotsHeader header,  BotsStateSnapshot? state)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  BotsHeader header,  BotsStateSnapshot? state)?  stateChanged,required TResult orElse(),}) {final _that = this;
switch (_that) {
case BotsBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BotsStateChangedPayload() when stateChanged != null:
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  BotsHeader header,  BotsStateSnapshot? state)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  BotsHeader header,  BotsStateSnapshot? state)  stateChanged,}) {final _that = this;
switch (_that) {
case BotsBaseline():
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BotsStateChangedPayload():
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  BotsHeader header,  BotsStateSnapshot? state)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  BotsHeader header,  BotsStateSnapshot? state)?  stateChanged,}) {final _that = this;
switch (_that) {
case BotsBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.header,_that.state);case BotsStateChangedPayload() when stateChanged != null:
return stateChanged(_that.stamp,_that.baseRevision,_that.header,_that.state);case _:
  return null;

}
}

}

/// @nodoc


class BotsBaseline implements BotsEvent {
  const BotsBaseline({required this.identity, required this.stamp, required this.header, required this.state});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  BotsHeader header;
@override final  BotsStateSnapshot? state;

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsBaselineCopyWith<BotsBaseline> get copyWith => _$BotsBaselineCopyWithImpl<BotsBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsBaseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.header, header) || other.header == header)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,header,state);
}



}

/// @nodoc
abstract mixin class $BotsBaselineCopyWith<$Res> implements $BotsEventCopyWith<$Res> {
  factory $BotsBaselineCopyWith(BotsBaseline value, $Res Function(BotsBaseline) _then) = _$BotsBaselineCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, BotsHeader header, BotsStateSnapshot? state
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $BotsHeaderCopyWith<$Res> get header;@override $BotsStateSnapshotCopyWith<$Res>? get state;

}
/// @nodoc
class _$BotsBaselineCopyWithImpl<$Res>
    implements $BotsBaselineCopyWith<$Res> {
  _$BotsBaselineCopyWithImpl(this._self, this._then);

  final BotsBaseline _self;
  final $Res Function(BotsBaseline) _then;

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? header = null,Object? state = freezed,}) {
  return _then(BotsBaseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BotsStateSnapshot?,
  ));
}

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsHeaderCopyWith<$Res> get header {

  return $BotsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateSnapshotCopyWith<$Res>? get state {
    if (_self.state == null) {
    return null;
  }

  return $BotsStateSnapshotCopyWith<$Res>(_self.state!, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

/// @nodoc


class BotsStateChangedPayload implements BotsEvent {
  const BotsStateChangedPayload({required this.stamp, required this.baseRevision, required this.header, required this.state});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  BotsHeader header;
@override final  BotsStateSnapshot? state;

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BotsStateChangedPayloadCopyWith<BotsStateChangedPayload> get copyWith => _$BotsStateChangedPayloadCopyWithImpl<BotsStateChangedPayload>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is BotsStateChangedPayload&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.header, header) || other.header == header)&&(identical(other.state, state) || other.state == state));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,header,state);
}



}

/// @nodoc
abstract mixin class $BotsStateChangedPayloadCopyWith<$Res> implements $BotsEventCopyWith<$Res> {
  factory $BotsStateChangedPayloadCopyWith(BotsStateChangedPayload value, $Res Function(BotsStateChangedPayload) _then) = _$BotsStateChangedPayloadCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, BotsHeader header, BotsStateSnapshot? state
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $BotsHeaderCopyWith<$Res> get header;@override $BotsStateSnapshotCopyWith<$Res>? get state;

}
/// @nodoc
class _$BotsStateChangedPayloadCopyWithImpl<$Res>
    implements $BotsStateChangedPayloadCopyWith<$Res> {
  _$BotsStateChangedPayloadCopyWithImpl(this._self, this._then);

  final BotsStateChangedPayload _self;
  final $Res Function(BotsStateChangedPayload) _then;

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? header = null,Object? state = freezed,}) {
  return _then(BotsStateChangedPayload(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as BotsHeader,state: freezed == state ? _self.state : state // ignore: cast_nullable_to_non_nullable
as BotsStateSnapshot?,
  ));
}

/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsHeaderCopyWith<$Res> get header {

  return $BotsHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of BotsEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$BotsStateSnapshotCopyWith<$Res>? get state {
    if (_self.state == null) {
    return null;
  }

  return $BotsStateSnapshotCopyWith<$Res>(_self.state!, (value) {
    return _then(_self.copyWith(state: value));
  });
}
}

// dart format on
