// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint, type=warning, deprecated_member_use, deprecated_member_use_from_same_package
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'persistence_frames.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PersistenceEvent {

 ProductProjectionStamp get stamp; PersistenceHeader get value;
/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceEventCopyWith<PersistenceEvent> get copyWith => _$PersistenceEventCopyWithImpl<PersistenceEvent>(this as PersistenceEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&(identical(other.value, _this.value) || other.value == _this.value));
}


@override
int get hashCode {
  final _this = this as PersistenceEvent;
  return Object.hash(runtimeType,_this.stamp,_this.value);
}

@override
String toString() {
  final _this = this as PersistenceEvent;
  return 'PersistenceEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $PersistenceEventCopyWith<$Res>  {
  factory $PersistenceEventCopyWith(PersistenceEvent value, $Res Function(PersistenceEvent) _then) = _$PersistenceEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp, PersistenceHeader value
});


$ProductProjectionStampCopyWith<$Res> get stamp;$PersistenceHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceEventCopyWithImpl<$Res>
    implements $PersistenceEventCopyWith<$Res> {
  _$PersistenceEventCopyWithImpl(this._self, this._then);

  final PersistenceEvent _self;
  final $Res Function(PersistenceEvent) _then;

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,Object? value = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PersistenceHeader,
  ));
}
/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceHeaderCopyWith<$Res> get value {

  return $PersistenceHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceEvent].
extension PersistenceEventPatterns on PersistenceEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PersistenceBaselineEvent value)?  baseline,TResult Function( PersistenceReplaceEvent value)?  replace,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PersistenceBaselineEvent() when baseline != null:
return baseline(_that);case PersistenceReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PersistenceBaselineEvent value)  baseline,required TResult Function( PersistenceReplaceEvent value)  replace,}){
final _that = this;
switch (_that) {
case PersistenceBaselineEvent():
return baseline(_that);case PersistenceReplaceEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PersistenceBaselineEvent value)?  baseline,TResult? Function( PersistenceReplaceEvent value)?  replace,}){
final _that = this;
switch (_that) {
case PersistenceBaselineEvent() when baseline != null:
return baseline(_that);case PersistenceReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceHeader value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceHeader value)?  replace,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PersistenceBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceReplaceEvent() when replace != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceHeader value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceHeader value)  replace,}) {final _that = this;
switch (_that) {
case PersistenceBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceReplaceEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceHeader value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceHeader value)?  replace,}) {final _that = this;
switch (_that) {
case PersistenceBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceReplaceEvent() when replace != null:
return replace(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class PersistenceBaselineEvent implements PersistenceEvent {
  const PersistenceBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  PersistenceHeader value;

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceBaselineEventCopyWith<PersistenceBaselineEvent> get copyWith => _$PersistenceBaselineEventCopyWithImpl<PersistenceBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'PersistenceEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $PersistenceBaselineEventCopyWith<$Res> implements $PersistenceEventCopyWith<$Res> {
  factory $PersistenceBaselineEventCopyWith(PersistenceBaselineEvent value, $Res Function(PersistenceBaselineEvent) _then) = _$PersistenceBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, PersistenceHeader value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $PersistenceHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceBaselineEventCopyWithImpl<$Res>
    implements $PersistenceBaselineEventCopyWith<$Res> {
  _$PersistenceBaselineEventCopyWithImpl(this._self, this._then);

  final PersistenceBaselineEvent _self;
  final $Res Function(PersistenceBaselineEvent) _then;

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(PersistenceBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PersistenceHeader,
  ));
}

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceHeaderCopyWith<$Res> get value {

  return $PersistenceHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class PersistenceReplaceEvent implements PersistenceEvent {
  const PersistenceReplaceEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  PersistenceHeader value;

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceReplaceEventCopyWith<PersistenceReplaceEvent> get copyWith => _$PersistenceReplaceEventCopyWithImpl<PersistenceReplaceEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceReplaceEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'PersistenceEvent.replace(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $PersistenceReplaceEventCopyWith<$Res> implements $PersistenceEventCopyWith<$Res> {
  factory $PersistenceReplaceEventCopyWith(PersistenceReplaceEvent value, $Res Function(PersistenceReplaceEvent) _then) = _$PersistenceReplaceEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, PersistenceHeader value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;@override $PersistenceHeaderCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceReplaceEventCopyWithImpl<$Res>
    implements $PersistenceReplaceEventCopyWith<$Res> {
  _$PersistenceReplaceEventCopyWithImpl(this._self, this._then);

  final PersistenceReplaceEvent _self;
  final $Res Function(PersistenceReplaceEvent) _then;

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(PersistenceReplaceEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PersistenceHeader,
  ));
}

/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PersistenceEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceHeaderCopyWith<$Res> get value {

  return $PersistenceHeaderCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PersistenceFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $PersistenceFrameCopyWith<$Res>  {
$PersistenceFrameCopyWith(PersistenceFrame _, $Res Function(PersistenceFrame) __);
}


/// Adds pattern-matching-related methods to [PersistenceFrame].
extension PersistenceFramePatterns on PersistenceFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PersistenceData value)?  data,TResult Function( PersistenceResyncRequired value)?  resyncRequired,TResult Function( PersistenceFeedFailure value)?  failure,TResult Function( PersistenceClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PersistenceData() when data != null:
return data(_that);case PersistenceResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PersistenceFeedFailure() when failure != null:
return failure(_that);case PersistenceClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PersistenceData value)  data,required TResult Function( PersistenceResyncRequired value)  resyncRequired,required TResult Function( PersistenceFeedFailure value)  failure,required TResult Function( PersistenceClosed value)  closed,}){
final _that = this;
switch (_that) {
case PersistenceData():
return data(_that);case PersistenceResyncRequired():
return resyncRequired(_that);case PersistenceFeedFailure():
return failure(_that);case PersistenceClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PersistenceData value)?  data,TResult? Function( PersistenceResyncRequired value)?  resyncRequired,TResult? Function( PersistenceFeedFailure value)?  failure,TResult? Function( PersistenceClosed value)?  closed,}){
final _that = this;
switch (_that) {
case PersistenceData() when data != null:
return data(_that);case PersistenceResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PersistenceFeedFailure() when failure != null:
return failure(_that);case PersistenceClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  PersistenceEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PersistenceData() when data != null:
return data(_that.deliverySequence,_that.event);case PersistenceResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PersistenceFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PersistenceClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  PersistenceEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case PersistenceData():
return data(_that.deliverySequence,_that.event);case PersistenceResyncRequired():
return resyncRequired(_that.identity,_that.reason);case PersistenceFeedFailure():
return failure(_that.identity,_that.error);case PersistenceClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  PersistenceEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case PersistenceData() when data != null:
return data(_that.deliverySequence,_that.event);case PersistenceResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PersistenceFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PersistenceClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class PersistenceData implements PersistenceFrame {
  const PersistenceData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  PersistenceEvent event;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceDataCopyWith<PersistenceData> get copyWith => _$PersistenceDataCopyWithImpl<PersistenceData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $PersistenceDataCopyWith<$Res> implements $PersistenceFrameCopyWith<$Res> {
  factory $PersistenceDataCopyWith(PersistenceData value, $Res Function(PersistenceData) _then) = _$PersistenceDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, PersistenceEvent event
});


$PersistenceEventCopyWith<$Res> get event;

}
/// @nodoc
class _$PersistenceDataCopyWithImpl<$Res>
    implements $PersistenceDataCopyWith<$Res> {
  _$PersistenceDataCopyWithImpl(this._self, this._then);

  final PersistenceData _self;
  final $Res Function(PersistenceData) _then;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(PersistenceData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as PersistenceEvent,
  ));
}

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceEventCopyWith<$Res> get event {

  return $PersistenceEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class PersistenceResyncRequired implements PersistenceFrame {
  const PersistenceResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceResyncRequiredCopyWith<PersistenceResyncRequired> get copyWith => _$PersistenceResyncRequiredCopyWithImpl<PersistenceResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PersistenceResyncRequiredCopyWith<$Res> implements $PersistenceFrameCopyWith<$Res> {
  factory $PersistenceResyncRequiredCopyWith(PersistenceResyncRequired value, $Res Function(PersistenceResyncRequired) _then) = _$PersistenceResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PersistenceResyncRequiredCopyWithImpl<$Res>
    implements $PersistenceResyncRequiredCopyWith<$Res> {
  _$PersistenceResyncRequiredCopyWithImpl(this._self, this._then);

  final PersistenceResyncRequired _self;
  final $Res Function(PersistenceResyncRequired) _then;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PersistenceResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of PersistenceFrame
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


class PersistenceFeedFailure implements PersistenceFrame {
  const PersistenceFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceFeedFailureCopyWith<PersistenceFeedFailure> get copyWith => _$PersistenceFeedFailureCopyWithImpl<PersistenceFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $PersistenceFeedFailureCopyWith<$Res> implements $PersistenceFrameCopyWith<$Res> {
  factory $PersistenceFeedFailureCopyWith(PersistenceFeedFailure value, $Res Function(PersistenceFeedFailure) _then) = _$PersistenceFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$PersistenceFeedFailureCopyWithImpl<$Res>
    implements $PersistenceFeedFailureCopyWith<$Res> {
  _$PersistenceFeedFailureCopyWithImpl(this._self, this._then);

  final PersistenceFeedFailure _self;
  final $Res Function(PersistenceFeedFailure) _then;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(PersistenceFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PersistenceFrame
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


class PersistenceClosed implements PersistenceFrame {
  const PersistenceClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceClosedCopyWith<PersistenceClosed> get copyWith => _$PersistenceClosedCopyWithImpl<PersistenceClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PersistenceClosedCopyWith<$Res> implements $PersistenceFrameCopyWith<$Res> {
  factory $PersistenceClosedCopyWith(PersistenceClosed value, $Res Function(PersistenceClosed) _then) = _$PersistenceClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PersistenceClosedCopyWithImpl<$Res>
    implements $PersistenceClosedCopyWith<$Res> {
  _$PersistenceClosedCopyWithImpl(this._self, this._then);

  final PersistenceClosed _self;
  final $Res Function(PersistenceClosed) _then;

/// Create a copy of PersistenceFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PersistenceClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of PersistenceFrame
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
mixin _$PersistenceQueueBaseline {

 PersistenceQueueHeader get header; ProductCollectionRef? get collection;
/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueBaselineCopyWith<PersistenceQueueBaseline> get copyWith => _$PersistenceQueueBaselineCopyWithImpl<PersistenceQueueBaseline>(this as PersistenceQueueBaseline, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueBaseline;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueBaseline&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.collection, _this.collection) || other.collection == _this.collection));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueBaseline;
  return Object.hash(runtimeType,_this.header,_this.collection);
}

@override
String toString() {
  final _this = this as PersistenceQueueBaseline;
  return 'PersistenceQueueBaseline(header: ${_this.header}, collection: ${_this.collection})';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueBaselineCopyWith<$Res>  {
  factory $PersistenceQueueBaselineCopyWith(PersistenceQueueBaseline value, $Res Function(PersistenceQueueBaseline) _then) = _$PersistenceQueueBaselineCopyWithImpl;
@useResult
$Res call({
 PersistenceQueueHeader header, ProductCollectionRef? collection
});


$PersistenceQueueHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PersistenceQueueBaselineCopyWithImpl<$Res>
    implements $PersistenceQueueBaselineCopyWith<$Res> {
  _$PersistenceQueueBaselineCopyWithImpl(this._self, this._then);

  final PersistenceQueueBaseline _self;
  final $Res Function(PersistenceQueueBaseline) _then;

/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(PersistenceQueueBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PersistenceQueueHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}
/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueHeaderCopyWith<$Res> get header {

  return $PersistenceQueueHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueBaseline].
extension PersistenceQueueBaselinePatterns on PersistenceQueueBaseline {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _PersistenceQueueBaseline value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PersistenceQueueBaseline() when $default != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _PersistenceQueueBaseline value)  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueBaseline():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _PersistenceQueueBaseline value)?  $default,){
final _that = this;
switch (_that) {
case _PersistenceQueueBaseline() when $default != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( PersistenceQueueHeader header,  ProductCollectionRef? collection)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PersistenceQueueBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( PersistenceQueueHeader header,  ProductCollectionRef? collection)  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueBaseline():
return $default(_that.header,_that.collection);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( PersistenceQueueHeader header,  ProductCollectionRef? collection)?  $default,) {final _that = this;
switch (_that) {
case _PersistenceQueueBaseline() when $default != null:
return $default(_that.header,_that.collection);case _:
  return null;

}
}

}

/// @nodoc


class _PersistenceQueueBaseline implements PersistenceQueueBaseline {
  const _PersistenceQueueBaseline({required this.header, required this.collection});


@override final  PersistenceQueueHeader header;
@override final  ProductCollectionRef? collection;

/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PersistenceQueueBaselineCopyWith<_PersistenceQueueBaseline> get copyWith => __$PersistenceQueueBaselineCopyWithImpl<_PersistenceQueueBaseline>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is _PersistenceQueueBaseline&&(identical(other.header, header) || other.header == header)&&(identical(other.collection, collection) || other.collection == collection));
}


@override
int get hashCode {
    return Object.hash(runtimeType,header,collection);
}

@override
String toString() {
    return 'PersistenceQueueBaseline(header: $header, collection: $collection)';
}


}

/// @nodoc
abstract mixin class _$PersistenceQueueBaselineCopyWith<$Res> implements $PersistenceQueueBaselineCopyWith<$Res> {
  factory _$PersistenceQueueBaselineCopyWith(_PersistenceQueueBaseline value, $Res Function(_PersistenceQueueBaseline) _then) = __$PersistenceQueueBaselineCopyWithImpl;
@override @useResult
$Res call({
 PersistenceQueueHeader header, ProductCollectionRef? collection
});


@override $PersistenceQueueHeaderCopyWith<$Res> get header;@override $ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class __$PersistenceQueueBaselineCopyWithImpl<$Res>
    implements _$PersistenceQueueBaselineCopyWith<$Res> {
  __$PersistenceQueueBaselineCopyWithImpl(this._self, this._then);

  final _PersistenceQueueBaseline _self;
  final $Res Function(_PersistenceQueueBaseline) _then;

/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? header = null,Object? collection = freezed,}) {
  return _then(_PersistenceQueueBaseline(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PersistenceQueueHeader,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,
  ));
}

/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueHeaderCopyWith<$Res> get header {

  return $PersistenceQueueHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PersistenceQueueBaseline
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueChange {


/// Create a copy of PersistenceQueueChange
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueChangeCopyWith<PersistenceQueueChange> get copyWith => _$PersistenceQueueChangeCopyWithImpl<PersistenceQueueChange>(this as PersistenceQueueChange, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueChange;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueChange&&(identical(other.header, _this.header) || other.header == _this.header)&&(identical(other.baseCollectionRevision, _this.baseCollectionRevision) || other.baseCollectionRevision == _this.baseCollectionRevision)&&(identical(other.collection, _this.collection) || other.collection == _this.collection)&&const DeepCollectionEquality().equals(other.upserted, _this.upserted)&&const DeepCollectionEquality().equals(other.removedEntries, _this.removedEntries));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueChange;
  return Object.hash(runtimeType,_this.header,_this.baseCollectionRevision,_this.collection,const DeepCollectionEquality().hash(_this.upserted),const DeepCollectionEquality().hash(_this.removedEntries));
}



}

/// @nodoc
abstract mixin class $PersistenceQueueChangeCopyWith<$Res>  {
  factory $PersistenceQueueChangeCopyWith(PersistenceQueueChange value, $Res Function(PersistenceQueueChange) _then) = _$PersistenceQueueChangeCopyWithImpl;
@useResult
$Res call({
 PersistenceQueueHeader header, int? baseCollectionRevision, ProductCollectionRef? collection, List<ProductEntityRef> upserted, List<int> removedEntries
});


$PersistenceQueueHeaderCopyWith<$Res> get header;$ProductCollectionRefCopyWith<$Res>? get collection;

}
/// @nodoc
class _$PersistenceQueueChangeCopyWithImpl<$Res>
    implements $PersistenceQueueChangeCopyWith<$Res> {
  _$PersistenceQueueChangeCopyWithImpl(this._self, this._then);

  final PersistenceQueueChange _self;
  final $Res Function(PersistenceQueueChange) _then;

/// Create a copy of PersistenceQueueChange
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? header = null,Object? baseCollectionRevision = freezed,Object? collection = freezed,Object? upserted = null,Object? removedEntries = null,}) {
  return _then(PersistenceQueueChange(
header: null == header ? _self.header : header // ignore: cast_nullable_to_non_nullable
as PersistenceQueueHeader,baseCollectionRevision: freezed == baseCollectionRevision ? _self.baseCollectionRevision : baseCollectionRevision // ignore: cast_nullable_to_non_nullable
as int?,collection: freezed == collection ? _self.collection : collection // ignore: cast_nullable_to_non_nullable
as ProductCollectionRef?,upserted: null == upserted ? _self.upserted : upserted // ignore: cast_nullable_to_non_nullable
as List<ProductEntityRef>,removedEntries: null == removedEntries ? _self.removedEntries : removedEntries // ignore: cast_nullable_to_non_nullable
as List<int>,
  ));
}
/// Create a copy of PersistenceQueueChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueHeaderCopyWith<$Res> get header {

  return $PersistenceQueueHeaderCopyWith<$Res>(_self.header, (value) {
    return _then(_self.copyWith(header: value));
  });
}/// Create a copy of PersistenceQueueChange
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductCollectionRefCopyWith<$Res>? get collection {
    if (_self.collection == null) {
    return null;
  }

  return $ProductCollectionRefCopyWith<$Res>(_self.collection!, (value) {
    return _then(_self.copyWith(collection: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueChange].
extension PersistenceQueueChangePatterns on PersistenceQueueChange {
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
mixin _$PersistenceQueueEvent {

 ProductProjectionStamp get stamp; Object get value;
/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueEventCopyWith<PersistenceQueueEvent> get copyWith => _$PersistenceQueueEventCopyWithImpl<PersistenceQueueEvent>(this as PersistenceQueueEvent, _$identity);



@override
bool operator ==(Object other) {
  final _this = this as PersistenceQueueEvent;
  return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueEvent&&(identical(other.stamp, _this.stamp) || other.stamp == _this.stamp)&&const DeepCollectionEquality().equals(other.value, _this.value));
}


@override
int get hashCode {
  final _this = this as PersistenceQueueEvent;
  return Object.hash(runtimeType,_this.stamp,const DeepCollectionEquality().hash(_this.value));
}

@override
String toString() {
  final _this = this as PersistenceQueueEvent;
  return 'PersistenceQueueEvent(stamp: ${_this.stamp}, value: ${_this.value})';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueEventCopyWith<$Res>  {
  factory $PersistenceQueueEventCopyWith(PersistenceQueueEvent value, $Res Function(PersistenceQueueEvent) _then) = _$PersistenceQueueEventCopyWithImpl;
@useResult
$Res call({
 ProductProjectionStamp stamp
});


$ProductProjectionStampCopyWith<$Res> get stamp;

}
/// @nodoc
class _$PersistenceQueueEventCopyWithImpl<$Res>
    implements $PersistenceQueueEventCopyWith<$Res> {
  _$PersistenceQueueEventCopyWithImpl(this._self, this._then);

  final PersistenceQueueEvent _self;
  final $Res Function(PersistenceQueueEvent) _then;

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? stamp = null,}) {
  return _then(_self.copyWith(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,
  ));
}
/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}
}


/// Adds pattern-matching-related methods to [PersistenceQueueEvent].
extension PersistenceQueueEventPatterns on PersistenceQueueEvent {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PersistenceQueueBaselineEvent value)?  baseline,TResult Function( PersistenceQueueChangeEvent value)?  change,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent() when baseline != null:
return baseline(_that);case PersistenceQueueChangeEvent() when change != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PersistenceQueueBaselineEvent value)  baseline,required TResult Function( PersistenceQueueChangeEvent value)  change,}){
final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent():
return baseline(_that);case PersistenceQueueChangeEvent():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PersistenceQueueBaselineEvent value)?  baseline,TResult? Function( PersistenceQueueChangeEvent value)?  change,}){
final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent() when baseline != null:
return baseline(_that);case PersistenceQueueChangeEvent() when change != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceQueueBaseline value)?  baseline,TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceQueueChange value)?  change,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceQueueChangeEvent() when change != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceQueueBaseline value)  baseline,required TResult Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceQueueChange value)  change,}) {final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent():
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceQueueChangeEvent():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( ProductFeedIdentity identity,  ProductProjectionStamp stamp,  PersistenceQueueBaseline value)?  baseline,TResult? Function( ProductProjectionStamp stamp,  int baseRevision,  PersistenceQueueChange value)?  change,}) {final _that = this;
switch (_that) {
case PersistenceQueueBaselineEvent() when baseline != null:
return baseline(_that.identity,_that.stamp,_that.value);case PersistenceQueueChangeEvent() when change != null:
return change(_that.stamp,_that.baseRevision,_that.value);case _:
  return null;

}
}

}

/// @nodoc


class PersistenceQueueBaselineEvent implements PersistenceQueueEvent {
  const PersistenceQueueBaselineEvent({required this.identity, required this.stamp, required this.value});


 final  ProductFeedIdentity identity;
@override final  ProductProjectionStamp stamp;
@override final  PersistenceQueueBaseline value;

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueBaselineEventCopyWith<PersistenceQueueBaselineEvent> get copyWith => _$PersistenceQueueBaselineEventCopyWithImpl<PersistenceQueueBaselineEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueBaselineEvent&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,stamp,value);
}

@override
String toString() {
    return 'PersistenceQueueEvent.baseline(identity: $identity, stamp: $stamp, value: $value)';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueBaselineEventCopyWith<$Res> implements $PersistenceQueueEventCopyWith<$Res> {
  factory $PersistenceQueueBaselineEventCopyWith(PersistenceQueueBaselineEvent value, $Res Function(PersistenceQueueBaselineEvent) _then) = _$PersistenceQueueBaselineEventCopyWithImpl;
@override @useResult
$Res call({
 ProductFeedIdentity identity, ProductProjectionStamp stamp, PersistenceQueueBaseline value
});


$ProductFeedIdentityCopyWith<$Res> get identity;@override $ProductProjectionStampCopyWith<$Res> get stamp;$PersistenceQueueBaselineCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceQueueBaselineEventCopyWithImpl<$Res>
    implements $PersistenceQueueBaselineEventCopyWith<$Res> {
  _$PersistenceQueueBaselineEventCopyWithImpl(this._self, this._then);

  final PersistenceQueueBaselineEvent _self;
  final $Res Function(PersistenceQueueBaselineEvent) _then;

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? stamp = null,Object? value = null,}) {
  return _then(PersistenceQueueBaselineEvent(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PersistenceQueueBaseline,
  ));
}

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueBaselineCopyWith<$Res> get value {

  return $PersistenceQueueBaselineCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc


class PersistenceQueueChangeEvent implements PersistenceQueueEvent {
  const PersistenceQueueChangeEvent({required this.stamp, required this.baseRevision, required this.value});


@override final  ProductProjectionStamp stamp;
 final  int baseRevision;
@override final  PersistenceQueueChange value;

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueChangeEventCopyWith<PersistenceQueueChangeEvent> get copyWith => _$PersistenceQueueChangeEventCopyWithImpl<PersistenceQueueChangeEvent>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueChangeEvent&&(identical(other.stamp, stamp) || other.stamp == stamp)&&(identical(other.baseRevision, baseRevision) || other.baseRevision == baseRevision)&&(identical(other.value, value) || other.value == value));
}


@override
int get hashCode {
    return Object.hash(runtimeType,stamp,baseRevision,value);
}

@override
String toString() {
    return 'PersistenceQueueEvent.change(stamp: $stamp, baseRevision: $baseRevision, value: $value)';
}


}

/// @nodoc
abstract mixin class $PersistenceQueueChangeEventCopyWith<$Res> implements $PersistenceQueueEventCopyWith<$Res> {
  factory $PersistenceQueueChangeEventCopyWith(PersistenceQueueChangeEvent value, $Res Function(PersistenceQueueChangeEvent) _then) = _$PersistenceQueueChangeEventCopyWithImpl;
@override @useResult
$Res call({
 ProductProjectionStamp stamp, int baseRevision, PersistenceQueueChange value
});


@override $ProductProjectionStampCopyWith<$Res> get stamp;$PersistenceQueueChangeCopyWith<$Res> get value;

}
/// @nodoc
class _$PersistenceQueueChangeEventCopyWithImpl<$Res>
    implements $PersistenceQueueChangeEventCopyWith<$Res> {
  _$PersistenceQueueChangeEventCopyWithImpl(this._self, this._then);

  final PersistenceQueueChangeEvent _self;
  final $Res Function(PersistenceQueueChangeEvent) _then;

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? stamp = null,Object? baseRevision = null,Object? value = null,}) {
  return _then(PersistenceQueueChangeEvent(
stamp: null == stamp ? _self.stamp : stamp // ignore: cast_nullable_to_non_nullable
as ProductProjectionStamp,baseRevision: null == baseRevision ? _self.baseRevision : baseRevision // ignore: cast_nullable_to_non_nullable
as int,value: null == value ? _self.value : value // ignore: cast_nullable_to_non_nullable
as PersistenceQueueChange,
  ));
}

/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductProjectionStampCopyWith<$Res> get stamp {

  return $ProductProjectionStampCopyWith<$Res>(_self.stamp, (value) {
    return _then(_self.copyWith(stamp: value));
  });
}/// Create a copy of PersistenceQueueEvent
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueChangeCopyWith<$Res> get value {

  return $PersistenceQueueChangeCopyWith<$Res>(_self.value, (value) {
    return _then(_self.copyWith(value: value));
  });
}
}

/// @nodoc
mixin _$PersistenceQueueFrame {





@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueFrame);
}


@override
int get hashCode => runtimeType.hashCode;



}

/// @nodoc
class $PersistenceQueueFrameCopyWith<$Res>  {
$PersistenceQueueFrameCopyWith(PersistenceQueueFrame _, $Res Function(PersistenceQueueFrame) __);
}


/// Adds pattern-matching-related methods to [PersistenceQueueFrame].
extension PersistenceQueueFramePatterns on PersistenceQueueFrame {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( PersistenceQueueData value)?  data,TResult Function( PersistenceQueueResyncRequired value)?  resyncRequired,TResult Function( PersistenceQueueFeedFailure value)?  failure,TResult Function( PersistenceQueueClosed value)?  closed,required TResult orElse(),}){
final _that = this;
switch (_that) {
case PersistenceQueueData() when data != null:
return data(_that);case PersistenceQueueResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PersistenceQueueFeedFailure() when failure != null:
return failure(_that);case PersistenceQueueClosed() when closed != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( PersistenceQueueData value)  data,required TResult Function( PersistenceQueueResyncRequired value)  resyncRequired,required TResult Function( PersistenceQueueFeedFailure value)  failure,required TResult Function( PersistenceQueueClosed value)  closed,}){
final _that = this;
switch (_that) {
case PersistenceQueueData():
return data(_that);case PersistenceQueueResyncRequired():
return resyncRequired(_that);case PersistenceQueueFeedFailure():
return failure(_that);case PersistenceQueueClosed():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( PersistenceQueueData value)?  data,TResult? Function( PersistenceQueueResyncRequired value)?  resyncRequired,TResult? Function( PersistenceQueueFeedFailure value)?  failure,TResult? Function( PersistenceQueueClosed value)?  closed,}){
final _that = this;
switch (_that) {
case PersistenceQueueData() when data != null:
return data(_that);case PersistenceQueueResyncRequired() when resyncRequired != null:
return resyncRequired(_that);case PersistenceQueueFeedFailure() when failure != null:
return failure(_that);case PersistenceQueueClosed() when closed != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( int deliverySequence,  PersistenceQueueEvent event)?  data,TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,required TResult orElse(),}) {final _that = this;
switch (_that) {
case PersistenceQueueData() when data != null:
return data(_that.deliverySequence,_that.event);case PersistenceQueueResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PersistenceQueueFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PersistenceQueueClosed() when closed != null:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( int deliverySequence,  PersistenceQueueEvent event)  data,required TResult Function( ProductFeedIdentity identity,  ProductResyncReason reason)  resyncRequired,required TResult Function( ProductFeedIdentity identity,  StudioFailure error)  failure,required TResult Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)  closed,}) {final _that = this;
switch (_that) {
case PersistenceQueueData():
return data(_that.deliverySequence,_that.event);case PersistenceQueueResyncRequired():
return resyncRequired(_that.identity,_that.reason);case PersistenceQueueFeedFailure():
return failure(_that.identity,_that.error);case PersistenceQueueClosed():
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( int deliverySequence,  PersistenceQueueEvent event)?  data,TResult? Function( ProductFeedIdentity identity,  ProductResyncReason reason)?  resyncRequired,TResult? Function( ProductFeedIdentity identity,  StudioFailure error)?  failure,TResult? Function( ProductFeedIdentity identity,  ProductFeedCloseReason reason)?  closed,}) {final _that = this;
switch (_that) {
case PersistenceQueueData() when data != null:
return data(_that.deliverySequence,_that.event);case PersistenceQueueResyncRequired() when resyncRequired != null:
return resyncRequired(_that.identity,_that.reason);case PersistenceQueueFeedFailure() when failure != null:
return failure(_that.identity,_that.error);case PersistenceQueueClosed() when closed != null:
return closed(_that.identity,_that.reason);case _:
  return null;

}
}

}

/// @nodoc


class PersistenceQueueData implements PersistenceQueueFrame {
  const PersistenceQueueData({required this.deliverySequence, required this.event});


 final  int deliverySequence;
 final  PersistenceQueueEvent event;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueDataCopyWith<PersistenceQueueData> get copyWith => _$PersistenceQueueDataCopyWithImpl<PersistenceQueueData>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueData&&(identical(other.deliverySequence, deliverySequence) || other.deliverySequence == deliverySequence)&&(identical(other.event, event) || other.event == event));
}


@override
int get hashCode {
    return Object.hash(runtimeType,deliverySequence,event);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueDataCopyWith<$Res> implements $PersistenceQueueFrameCopyWith<$Res> {
  factory $PersistenceQueueDataCopyWith(PersistenceQueueData value, $Res Function(PersistenceQueueData) _then) = _$PersistenceQueueDataCopyWithImpl;
@useResult
$Res call({
 int deliverySequence, PersistenceQueueEvent event
});


$PersistenceQueueEventCopyWith<$Res> get event;

}
/// @nodoc
class _$PersistenceQueueDataCopyWithImpl<$Res>
    implements $PersistenceQueueDataCopyWith<$Res> {
  _$PersistenceQueueDataCopyWithImpl(this._self, this._then);

  final PersistenceQueueData _self;
  final $Res Function(PersistenceQueueData) _then;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? deliverySequence = null,Object? event = null,}) {
  return _then(PersistenceQueueData(
deliverySequence: null == deliverySequence ? _self.deliverySequence : deliverySequence // ignore: cast_nullable_to_non_nullable
as int,event: null == event ? _self.event : event // ignore: cast_nullable_to_non_nullable
as PersistenceQueueEvent,
  ));
}

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$PersistenceQueueEventCopyWith<$Res> get event {

  return $PersistenceQueueEventCopyWith<$Res>(_self.event, (value) {
    return _then(_self.copyWith(event: value));
  });
}
}

/// @nodoc


class PersistenceQueueResyncRequired implements PersistenceQueueFrame {
  const PersistenceQueueResyncRequired({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductResyncReason reason;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueResyncRequiredCopyWith<PersistenceQueueResyncRequired> get copyWith => _$PersistenceQueueResyncRequiredCopyWithImpl<PersistenceQueueResyncRequired>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueResyncRequired&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueResyncRequiredCopyWith<$Res> implements $PersistenceQueueFrameCopyWith<$Res> {
  factory $PersistenceQueueResyncRequiredCopyWith(PersistenceQueueResyncRequired value, $Res Function(PersistenceQueueResyncRequired) _then) = _$PersistenceQueueResyncRequiredCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductResyncReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PersistenceQueueResyncRequiredCopyWithImpl<$Res>
    implements $PersistenceQueueResyncRequiredCopyWith<$Res> {
  _$PersistenceQueueResyncRequiredCopyWithImpl(this._self, this._then);

  final PersistenceQueueResyncRequired _self;
  final $Res Function(PersistenceQueueResyncRequired) _then;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PersistenceQueueResyncRequired(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductResyncReason,
  ));
}

/// Create a copy of PersistenceQueueFrame
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


class PersistenceQueueFeedFailure implements PersistenceQueueFrame {
  const PersistenceQueueFeedFailure({required this.identity, required this.error});


 final  ProductFeedIdentity identity;
 final  StudioFailure error;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueFeedFailureCopyWith<PersistenceQueueFeedFailure> get copyWith => _$PersistenceQueueFeedFailureCopyWithImpl<PersistenceQueueFeedFailure>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueFeedFailure&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.error, error) || other.error == error));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,error);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueFeedFailureCopyWith<$Res> implements $PersistenceQueueFrameCopyWith<$Res> {
  factory $PersistenceQueueFeedFailureCopyWith(PersistenceQueueFeedFailure value, $Res Function(PersistenceQueueFeedFailure) _then) = _$PersistenceQueueFeedFailureCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, StudioFailure error
});


$ProductFeedIdentityCopyWith<$Res> get identity;$StudioFailureCopyWith<$Res> get error;

}
/// @nodoc
class _$PersistenceQueueFeedFailureCopyWithImpl<$Res>
    implements $PersistenceQueueFeedFailureCopyWith<$Res> {
  _$PersistenceQueueFeedFailureCopyWithImpl(this._self, this._then);

  final PersistenceQueueFeedFailure _self;
  final $Res Function(PersistenceQueueFeedFailure) _then;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? error = null,}) {
  return _then(PersistenceQueueFeedFailure(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,error: null == error ? _self.error : error // ignore: cast_nullable_to_non_nullable
as StudioFailure,
  ));
}

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}/// Create a copy of PersistenceQueueFrame
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


class PersistenceQueueClosed implements PersistenceQueueFrame {
  const PersistenceQueueClosed({required this.identity, required this.reason});


 final  ProductFeedIdentity identity;
 final  ProductFeedCloseReason reason;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PersistenceQueueClosedCopyWith<PersistenceQueueClosed> get copyWith => _$PersistenceQueueClosedCopyWithImpl<PersistenceQueueClosed>(this, _$identity);



@override
bool operator ==(Object other) {
    return identical(this, other) || (other.runtimeType == runtimeType&&other is PersistenceQueueClosed&&(identical(other.identity, identity) || other.identity == identity)&&(identical(other.reason, reason) || other.reason == reason));
}


@override
int get hashCode {
    return Object.hash(runtimeType,identity,reason);
}



}

/// @nodoc
abstract mixin class $PersistenceQueueClosedCopyWith<$Res> implements $PersistenceQueueFrameCopyWith<$Res> {
  factory $PersistenceQueueClosedCopyWith(PersistenceQueueClosed value, $Res Function(PersistenceQueueClosed) _then) = _$PersistenceQueueClosedCopyWithImpl;
@useResult
$Res call({
 ProductFeedIdentity identity, ProductFeedCloseReason reason
});


$ProductFeedIdentityCopyWith<$Res> get identity;

}
/// @nodoc
class _$PersistenceQueueClosedCopyWithImpl<$Res>
    implements $PersistenceQueueClosedCopyWith<$Res> {
  _$PersistenceQueueClosedCopyWithImpl(this._self, this._then);

  final PersistenceQueueClosed _self;
  final $Res Function(PersistenceQueueClosed) _then;

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') $Res call({Object? identity = null,Object? reason = null,}) {
  return _then(PersistenceQueueClosed(
identity: null == identity ? _self.identity : identity // ignore: cast_nullable_to_non_nullable
as ProductFeedIdentity,reason: null == reason ? _self.reason : reason // ignore: cast_nullable_to_non_nullable
as ProductFeedCloseReason,
  ));
}

/// Create a copy of PersistenceQueueFrame
/// with the given fields replaced by the non-null parameter values.
@override
@pragma('vm:prefer-inline')
$ProductFeedIdentityCopyWith<$Res> get identity {

  return $ProductFeedIdentityCopyWith<$Res>(_self.identity, (value) {
    return _then(_self.copyWith(identity: value));
  });
}
}

// dart format on
