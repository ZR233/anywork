// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'acp_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$AcpAuthFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AcpAuthFrameCopyWith<$Res>  {
$AcpAuthFrameCopyWith(AcpAuthFrame _, $Res Function(AcpAuthFrame) __);
}


/// Adds pattern-matching-related methods to [AcpAuthFrame].
extension AcpAuthFramePatterns on AcpAuthFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpAuthData value)?  data,TResult Function( AcpAuthResyncRequired value)?  resyncRequired,TResult Function( AcpAuthFeedFailure value)?  failure,TResult Function( AcpAuthClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpAuthData() when data != null:
return data(_that);case AcpAuthResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AcpAuthFeedFailure() when failure != null:
return failure(_that);case AcpAuthClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpAuthData value)  data,required TResult Function( AcpAuthResyncRequired value)  resyncRequired,required TResult Function( AcpAuthFeedFailure value)  failure,required TResult Function( AcpAuthClosed value)  closed,}){
final _that = this;
switch (_that) {
case AcpAuthData():
return data(_that);case AcpAuthResyncRequired():
return resyncRequired(_that);case AcpAuthFeedFailure():
return failure(_that);case AcpAuthClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpAuthData value)?  data,TResult? Function( AcpAuthResyncRequired value)?  resyncRequired,TResult? Function( AcpAuthFeedFailure value)?  failure,TResult? Function( AcpAuthClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AcpAuthData() when data != null:
return data(_that);case AcpAuthResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AcpAuthFeedFailure() when failure != null:
return failure(_that);case AcpAuthClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AcpAuthEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpAuthData() when data != null:
return data(_that.deliverySequence,_that.event);case AcpAuthResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AcpAuthFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AcpAuthClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AcpAuthEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AcpAuthData():
return data(_that.deliverySequence,_that.event);case AcpAuthResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AcpAuthFeedFailure():
return failure(_that.identity,_that.error);case AcpAuthClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AcpAuthEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AcpAuthData() when data != null:
return data(_that.deliverySequence,_that.event);case AcpAuthResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AcpAuthFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AcpAuthClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AcpAuthData implements AcpAuthFrame {
  const AcpAuthData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AcpAuthEvent event;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthDataCopyWith<AcpAuthData> get copyWith => _$AcpAuthDataCopyWithImpl<AcpAuthData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AcpAuthDataCopyWith<$Res> implements $AcpAuthFrameCopyWith<$Res> {
  factory $AcpAuthDataCopyWith(AcpAuthData value, $Res Function(AcpAuthData) _then) = _$AcpAuthDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AcpAuthEvent event
});


$AcpAuthEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AcpAuthDataCopyWithImpl<$Res>
    implements $AcpAuthDataCopyWith<$Res> {
  _$AcpAuthDataCopyWithImpl(this._self, this._then);

  final AcpAuthData _self;
  final $Res Function(AcpAuthData) _then;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AcpAuthData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AcpAuthEvent,
  ));
}

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthEventCopyWith<$Res> get event {

  return $AcpAuthEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AcpAuthResyncRequired implements AcpAuthFrame {
  const AcpAuthResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthResyncRequiredCopyWith<AcpAuthResyncRequired> get copyWith => _$AcpAuthResyncRequiredCopyWithImpl<AcpAuthResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AcpAuthResyncRequiredCopyWith<$Res> implements $AcpAuthFrameCopyWith<$Res> {
  factory $AcpAuthResyncRequiredCopyWith(AcpAuthResyncRequired value, $Res Function(AcpAuthResyncRequired) _then) = _$AcpAuthResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AcpAuthResyncRequiredCopyWithImpl<$Res>
    implements $AcpAuthResyncRequiredCopyWith<$Res> {
  _$AcpAuthResyncRequiredCopyWithImpl(this._self, this._then);

  final AcpAuthResyncRequired _self;
  final $Res Function(AcpAuthResyncRequired) _then;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AcpAuthResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AcpAuthFrame
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


class AcpAuthFeedFailure implements AcpAuthFrame {
  const AcpAuthFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthFeedFailureCopyWith<AcpAuthFeedFailure> get copyWith => _$AcpAuthFeedFailureCopyWithImpl<AcpAuthFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AcpAuthFeedFailureCopyWith<$Res> implements $AcpAuthFrameCopyWith<$Res> {
  factory $AcpAuthFeedFailureCopyWith(AcpAuthFeedFailure value, $Res Function(AcpAuthFeedFailure) _then) = _$AcpAuthFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AcpAuthFeedFailureCopyWithImpl<$Res>
    implements $AcpAuthFeedFailureCopyWith<$Res> {
  _$AcpAuthFeedFailureCopyWithImpl(this._self, this._then);

  final AcpAuthFeedFailure _self;
  final $Res Function(AcpAuthFeedFailure) _then;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AcpAuthFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AcpAuthFrame
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


class AcpAuthClosed implements AcpAuthFrame {
  const AcpAuthClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthClosedCopyWith<AcpAuthClosed> get copyWith => _$AcpAuthClosedCopyWithImpl<AcpAuthClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AcpAuthClosedCopyWith<$Res> implements $AcpAuthFrameCopyWith<$Res> {
  factory $AcpAuthClosedCopyWith(AcpAuthClosed value, $Res Function(AcpAuthClosed) _then) = _$AcpAuthClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AcpAuthClosedCopyWithImpl<$Res>
    implements $AcpAuthClosedCopyWith<$Res> {
  _$AcpAuthClosedCopyWithImpl(this._self, this._then);

  final AcpAuthClosed _self;
  final $Res Function(AcpAuthClosed) _then;

/// Create a copy of AcpAuthFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AcpAuthClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AcpAuthFrame
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
mixin _$AcpAuthEvent {

 ProductProjectionStamp get stamp; AcpAuthSnapshot get snapshot;
/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthEventCopyWith<AcpAuthEvent> get copyWith => _$AcpAuthEventCopyWithImpl<AcpAuthEvent>(this as AcpAuthEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpAuthEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as AcpAuthEvent;
  return Object.hash(runtimeType,_this.stamp,_this.snapshot);
}



}

/// @nodoc
abstract mixin class $AcpAuthEventCopyWith<$Res>  {
  factory $AcpAuthEventCopyWith(AcpAuthEvent value, $Res Function(AcpAuthEvent) _then) = _$AcpAuthEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, AcpAuthSnapshot snapshot
});


$ProductProjectionStampCopyWith<$Res> get stamp;$AcpAuthSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpAuthEventCopyWithImpl<$Res>
    implements $AcpAuthEventCopyWith<$Res> {
  _$AcpAuthEventCopyWithImpl(this._self, this._then);

  final AcpAuthEvent _self;
  final $Res Function(AcpAuthEvent) _then;

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? snapshot = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot,
  ));
}
/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res> get snapshot {

  return $AcpAuthSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpAuthEvent].
extension AcpAuthEventPatterns on AcpAuthEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpAuthBaseline value)?  baseline,TResult Function( AcpAuthChanged value)?  changed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpAuthBaseline() when baseline != null:
return baseline(_that);case AcpAuthChanged() when changed != null:
return changed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpAuthBaseline value)  baseline,required TResult Function( AcpAuthChanged value)  changed,}){
final _that = this;
switch (_that) {
case AcpAuthBaseline():
return baseline(_that);case AcpAuthChanged():
return changed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpAuthBaseline value)?  baseline,TResult? Function( AcpAuthChanged value)?  changed,}){
final _that = this;
switch (_that) {
case AcpAuthBaseline() when baseline != null:
return baseline(_that);case AcpAuthChanged() when changed != null:
return changed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpAuthSnapshot snapshot)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AcpAuthSnapshot snapshot)?  changed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpAuthBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpAuthChanged() when changed != null:
return changed(_that.stamp,_that.baseRevision,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpAuthSnapshot snapshot)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AcpAuthSnapshot snapshot)  changed,}) {final _that = this;
switch (_that) {
case AcpAuthBaseline():
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpAuthChanged():
return changed(_that.stamp,_that.baseRevision,_that.snapshot);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpAuthSnapshot snapshot)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AcpAuthSnapshot snapshot)?  changed,}) {final _that = this;
switch (_that) {
case AcpAuthBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpAuthChanged() when changed != null:
return changed(_that.stamp,_that.baseRevision,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class AcpAuthBaseline implements AcpAuthEvent {
  const AcpAuthBaseline({required this.identity, required this.stamp, required this.snapshot});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AcpAuthSnapshot snapshot;

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthBaselineCopyWith<AcpAuthBaseline> get copyWith => _$AcpAuthBaselineCopyWithImpl<AcpAuthBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthBaseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,snapshot);
}



}

/// @nodoc
abstract mixin class $AcpAuthBaselineCopyWith<$Res> implements $AcpAuthEventCopyWith<$Res> {
  factory $AcpAuthBaselineCopyWith(AcpAuthBaseline value, $Res Function(AcpAuthBaseline) _then) = _$AcpAuthBaselineCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AcpAuthSnapshot snapshot
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $AcpAuthSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpAuthBaselineCopyWithImpl<$Res>
    implements $AcpAuthBaselineCopyWith<$Res> {
  _$AcpAuthBaselineCopyWithImpl(this._self, this._then);

  final AcpAuthBaseline _self;
  final $Res Function(AcpAuthBaseline) _then;

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? snapshot = null,}) {
  return _then(AcpAuthBaseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot,
  ));
}

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res> get snapshot {

  return $AcpAuthSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

/// @nodoc


class AcpAuthChanged implements AcpAuthEvent {
  const AcpAuthChanged({required this.stamp, required this.baseRevision, required this.snapshot});


@override final  ProductProjectionStamp stamp;
/// 发布方声明被本次事实取代的水位；与 reducer 当前水位不等就是 gap。
 final  int baseRevision;
@override final  AcpAuthSnapshot snapshot;

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpAuthChangedCopyWith<AcpAuthChanged> get copyWith => _$AcpAuthChangedCopyWithImpl<AcpAuthChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpAuthChanged&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,snapshot);
}



}

/// @nodoc
abstract mixin class $AcpAuthChangedCopyWith<$Res> implements $AcpAuthEventCopyWith<$Res> {
  factory $AcpAuthChangedCopyWith(AcpAuthChanged value, $Res Function(AcpAuthChanged) _then) = _$AcpAuthChangedCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AcpAuthSnapshot snapshot
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $AcpAuthSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpAuthChangedCopyWithImpl<$Res>
    implements $AcpAuthChangedCopyWith<$Res> {
  _$AcpAuthChangedCopyWithImpl(this._self, this._then);

  final AcpAuthChanged _self;
  final $Res Function(AcpAuthChanged) _then;

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? snapshot = null,}) {
  return _then(AcpAuthChanged(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpAuthSnapshot,
  ));
}

/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpAuthEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpAuthSnapshotCopyWith<$Res> get snapshot {

  return $AcpAuthSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

/// @nodoc
mixin _$AcpInstallFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $AcpInstallFrameCopyWith<$Res>  {
$AcpInstallFrameCopyWith(AcpInstallFrame _, $Res Function(AcpInstallFrame) __);
}


/// Adds pattern-matching-related methods to [AcpInstallFrame].
extension AcpInstallFramePatterns on AcpInstallFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpInstallData value)?  data,TResult Function( AcpInstallResyncRequired value)?  resyncRequired,TResult Function( AcpInstallFeedFailure value)?  failure,TResult Function( AcpInstallClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpInstallData() when data != null:
return data(_that);case AcpInstallResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AcpInstallFeedFailure() when failure != null:
return failure(_that);case AcpInstallClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpInstallData value)  data,required TResult Function( AcpInstallResyncRequired value)  resyncRequired,required TResult Function( AcpInstallFeedFailure value)  failure,required TResult Function( AcpInstallClosed value)  closed,}){
final _that = this;
switch (_that) {
case AcpInstallData():
return data(_that);case AcpInstallResyncRequired():
return resyncRequired(_that);case AcpInstallFeedFailure():
return failure(_that);case AcpInstallClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpInstallData value)?  data,TResult? Function( AcpInstallResyncRequired value)?  resyncRequired,TResult? Function( AcpInstallFeedFailure value)?  failure,TResult? Function( AcpInstallClosed value)?  closed,}){
final _that = this;
switch (_that) {
case AcpInstallData() when data != null:
return data(_that);case AcpInstallResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case AcpInstallFeedFailure() when failure != null:
return failure(_that);case AcpInstallClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  AcpInstallEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpInstallData() when data != null:
return data(_that.deliverySequence,_that.event);case AcpInstallResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AcpInstallFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AcpInstallClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  AcpInstallEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case AcpInstallData():
return data(_that.deliverySequence,_that.event);case AcpInstallResyncRequired():
return resyncRequired(_that.identity,_that.reason);case AcpInstallFeedFailure():
return failure(_that.identity,_that.error);case AcpInstallClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  AcpInstallEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case AcpInstallData() when data != null:
return data(_that.deliverySequence,_that.event);case AcpInstallResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case AcpInstallFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case AcpInstallClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class AcpInstallData implements AcpInstallFrame {
  const AcpInstallData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  AcpInstallEvent event;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallDataCopyWith<AcpInstallData> get copyWith => _$AcpInstallDataCopyWithImpl<AcpInstallData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $AcpInstallDataCopyWith<$Res> implements $AcpInstallFrameCopyWith<$Res> {
  factory $AcpInstallDataCopyWith(AcpInstallData value, $Res Function(AcpInstallData) _then) = _$AcpInstallDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, AcpInstallEvent event
});


$AcpInstallEventCopyWith<$Res> get event;

}
/// @nodoc
class _$AcpInstallDataCopyWithImpl<$Res>
    implements $AcpInstallDataCopyWith<$Res> {
  _$AcpInstallDataCopyWithImpl(this._self, this._then);

  final AcpInstallData _self;
  final $Res Function(AcpInstallData) _then;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(AcpInstallData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as AcpInstallEvent,
  ));
}

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallEventCopyWith<$Res> get event {

  return $AcpInstallEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class AcpInstallResyncRequired implements AcpInstallFrame {
  const AcpInstallResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallResyncRequiredCopyWith<AcpInstallResyncRequired> get copyWith => _$AcpInstallResyncRequiredCopyWithImpl<AcpInstallResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AcpInstallResyncRequiredCopyWith<$Res> implements $AcpInstallFrameCopyWith<$Res> {
  factory $AcpInstallResyncRequiredCopyWith(AcpInstallResyncRequired value, $Res Function(AcpInstallResyncRequired) _then) = _$AcpInstallResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AcpInstallResyncRequiredCopyWithImpl<$Res>
    implements $AcpInstallResyncRequiredCopyWith<$Res> {
  _$AcpInstallResyncRequiredCopyWithImpl(this._self, this._then);

  final AcpInstallResyncRequired _self;
  final $Res Function(AcpInstallResyncRequired) _then;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AcpInstallResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of AcpInstallFrame
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


class AcpInstallFeedFailure implements AcpInstallFrame {
  const AcpInstallFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallFeedFailureCopyWith<AcpInstallFeedFailure> get copyWith => _$AcpInstallFeedFailureCopyWithImpl<AcpInstallFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $AcpInstallFeedFailureCopyWith<$Res> implements $AcpInstallFrameCopyWith<$Res> {
  factory $AcpInstallFeedFailureCopyWith(AcpInstallFeedFailure value, $Res Function(AcpInstallFeedFailure) _then) = _$AcpInstallFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$AcpInstallFeedFailureCopyWithImpl<$Res>
    implements $AcpInstallFeedFailureCopyWith<$Res> {
  _$AcpInstallFeedFailureCopyWithImpl(this._self, this._then);

  final AcpInstallFeedFailure _self;
  final $Res Function(AcpInstallFeedFailure) _then;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(AcpInstallFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AcpInstallFrame
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


class AcpInstallClosed implements AcpInstallFrame {
  const AcpInstallClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallClosedCopyWith<AcpInstallClosed> get copyWith => _$AcpInstallClosedCopyWithImpl<AcpInstallClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $AcpInstallClosedCopyWith<$Res> implements $AcpInstallFrameCopyWith<$Res> {
  factory $AcpInstallClosedCopyWith(AcpInstallClosed value, $Res Function(AcpInstallClosed) _then) = _$AcpInstallClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$AcpInstallClosedCopyWithImpl<$Res>
    implements $AcpInstallClosedCopyWith<$Res> {
  _$AcpInstallClosedCopyWithImpl(this._self, this._then);

  final AcpInstallClosed _self;
  final $Res Function(AcpInstallClosed) _then;

/// Create a copy of AcpInstallFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(AcpInstallClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of AcpInstallFrame
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
mixin _$AcpInstallEvent {

 ProductProjectionStamp get stamp; AcpInstallSnapshot get snapshot;
/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallEventCopyWith<AcpInstallEvent> get copyWith => _$AcpInstallEventCopyWithImpl<AcpInstallEvent>(this as AcpInstallEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as AcpInstallEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.snapshot, _this.snapshot) || other.snapshot == _this.snapshot));
}


@override
int get hashCode {
  final _this = this as AcpInstallEvent;
  return Object.hash(runtimeType,_this.stamp,_this.snapshot);
}



}

/// @nodoc
abstract mixin class $AcpInstallEventCopyWith<$Res>  {
  factory $AcpInstallEventCopyWith(AcpInstallEvent value, $Res Function(AcpInstallEvent) _then) = _$AcpInstallEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, AcpInstallSnapshot snapshot
});


$ProductProjectionStampCopyWith<$Res> get stamp;$AcpInstallSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpInstallEventCopyWithImpl<$Res>
    implements $AcpInstallEventCopyWith<$Res> {
  _$AcpInstallEventCopyWithImpl(this._self, this._then);

  final AcpInstallEvent _self;
  final $Res Function(AcpInstallEvent) _then;

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? snapshot = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpInstallSnapshot,
  ));
}
/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallSnapshotCopyWith<$Res> get snapshot {

  return $AcpInstallSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}


/// Adds pattern-matching-related methods to [AcpInstallEvent].
extension AcpInstallEventPatterns on AcpInstallEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( AcpInstallBaseline value)?  baseline,TResult Function( AcpInstallChanged value)?  changed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case AcpInstallBaseline() when baseline != null:
return baseline(_that);case AcpInstallChanged() when changed != null:
return changed(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( AcpInstallBaseline value)  baseline,required TResult Function( AcpInstallChanged value)  changed,}){
final _that = this;
switch (_that) {
case AcpInstallBaseline():
return baseline(_that);case AcpInstallChanged():
return changed(_that);}
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( AcpInstallBaseline value)?  baseline,TResult? Function( AcpInstallChanged value)?  changed,}){
final _that = this;
switch (_that) {
case AcpInstallBaseline() when baseline != null:
return baseline(_that);case AcpInstallChanged() when changed != null:
return changed(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpInstallSnapshot snapshot)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AcpInstallSnapshot snapshot)?  changed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case AcpInstallBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpInstallChanged() when changed != null:
return changed(_that.stamp,_that.baseRevision,_that.snapshot);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpInstallSnapshot snapshot)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  AcpInstallSnapshot snapshot)  changed,}) {final _that = this;
switch (_that) {
case AcpInstallBaseline():
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpInstallChanged():
return changed(_that.stamp,_that.baseRevision,_that.snapshot);}
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  AcpInstallSnapshot snapshot)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  AcpInstallSnapshot snapshot)?  changed,}) {final _that = this;
switch (_that) {
case AcpInstallBaseline() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.snapshot);case AcpInstallChanged() when changed != null:
return changed(_that.stamp,_that.baseRevision,_that.snapshot);case _:
  return null;

}
}

}

/// @nodoc


class AcpInstallBaseline implements AcpInstallEvent {
  const AcpInstallBaseline({required this.identity, required this.stamp, required this.snapshot});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  AcpInstallSnapshot snapshot;

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallBaselineCopyWith<AcpInstallBaseline> get copyWith => _$AcpInstallBaselineCopyWithImpl<AcpInstallBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallBaseline&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,snapshot);
}



}

/// @nodoc
abstract mixin class $AcpInstallBaselineCopyWith<$Res> implements $AcpInstallEventCopyWith<$Res> {
  factory $AcpInstallBaselineCopyWith(AcpInstallBaseline value, $Res Function(AcpInstallBaseline) _then) = _$AcpInstallBaselineCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, AcpInstallSnapshot snapshot
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $AcpInstallSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpInstallBaselineCopyWithImpl<$Res>
    implements $AcpInstallBaselineCopyWith<$Res> {
  _$AcpInstallBaselineCopyWithImpl(this._self, this._then);

  final AcpInstallBaseline _self;
  final $Res Function(AcpInstallBaseline) _then;

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? snapshot = null,}) {
  return _then(AcpInstallBaseline(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpInstallSnapshot,
  ));
}

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallSnapshotCopyWith<$Res> get snapshot {

  return $AcpInstallSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

/// @nodoc


class AcpInstallChanged implements AcpInstallEvent {
  const AcpInstallChanged({required this.stamp, required this.baseRevision, required this.snapshot});


@override final  ProductProjectionStamp stamp;
/// 发布方声明被本次事实取代的水位；与 reducer 当前水位不等就是 gap。
 final  int baseRevision;
@override final  AcpInstallSnapshot snapshot;

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$AcpInstallChangedCopyWith<AcpInstallChanged> get copyWith => _$AcpInstallChangedCopyWithImpl<AcpInstallChanged>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is AcpInstallChanged&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.snapshot, snapshot) || other.snapshot == snapshot));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,snapshot);
}



}

/// @nodoc
abstract mixin class $AcpInstallChangedCopyWith<$Res> implements $AcpInstallEventCopyWith<$Res> {
  factory $AcpInstallChangedCopyWith(AcpInstallChanged value, $Res Function(AcpInstallChanged) _then) = _$AcpInstallChangedCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, AcpInstallSnapshot snapshot
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $AcpInstallSnapshotCopyWith<$Res> get snapshot;

}
/// @nodoc
class _$AcpInstallChangedCopyWithImpl<$Res>
    implements $AcpInstallChangedCopyWith<$Res> {
  _$AcpInstallChangedCopyWithImpl(this._self, this._then);

  final AcpInstallChanged _self;
  final $Res Function(AcpInstallChanged) _then;

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? snapshot = null,}) {
  return _then(AcpInstallChanged(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,snapshot: null == snapshot ? _self.snapshot : snapshot // ignore: cast_nullable_to_non_nullable
as AcpInstallSnapshot,
  ));
}

/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of AcpInstallEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$AcpInstallSnapshotCopyWith<$Res> get snapshot {

  return $AcpInstallSnapshotCopyWith<$Res>(_self.snapshot, (value) {
    return _then(_self.copyWith(snapshot: value));
  });
}
}

// dart format on
